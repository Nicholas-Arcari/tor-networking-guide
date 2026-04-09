# Scenari Reali - Strumenti Operativi Tor in Azione

Casi operativi in cui proxychains, torsocks, Nyx, ControlPort e la gestione
DNS hanno fatto la differenza durante penetration test e red team engagement.

---

## Indice

- [Scenario 1: proxychains fallisce silenziosamente durante un pentest](#scenario-1-proxychains-fallisce-silenziosamente-durante-un-pentest)
- [Scenario 2: DNS leak rilevato con tcpdump durante ricognizione](#scenario-2-dns-leak-rilevato-con-tcpdump-durante-ricognizione)
- [Scenario 3: Nyx rivela un guard compromesso durante un engagement](#scenario-3-nyx-rivela-un-guard-compromesso-durante-un-engagement)
- [Scenario 4: torsocks blocca UDP e rompe un tool di scanning](#scenario-4-torsocks-blocca-udp-e-rompe-un-tool-di-scanning)
- [Scenario 5: Automazione NEWNYM per evasione rate limiting](#scenario-5-automazione-newnym-per-evasione-rate-limiting)

---

## Scenario 1: proxychains fallisce silenziosamente durante un pentest

### Contesto

Un operatore usava `proxychains nmap -sT` per port scanning anonimo del target.
Lo scan restituiva risultati, ma un controllo incrociato mostrava che alcuni
pacchetti non passavano da Tor - uscivano con l'IP reale dell'operatore.

### Problema

nmap, quando invocato con `proxychains`, non instradata tutto il traffico via
SOCKS. In particolare:
- I ping ICMP (se non disabilitati con `-Pn`) bypassano proxychains
- Le connessioni raw socket non sono intercettate da LD_PRELOAD
- nmap usa syscall dirette che aggirano l'hooking di proxychains

### Diagnosi

```bash
# Monitorare il traffico uscente mentre si scanna
sudo tcpdump -i eth0 not port 9050 and host TARGET_IP -n

# Output:
# 10:23:45 IP 192.168.1.100 > TARGET_IP: ICMP echo request
# → ICMP esce direttamente, non via Tor!
```

### Soluzione

```bash
# 1. Sempre usare -Pn con nmap via proxychains (no ping)
proxychains nmap -sT -Pn -p80,443,22 target.example.com

# 2. Alternativa più sicura: torsocks (blocca UDP e ICMP)
torsocks nmap -sT -Pn target.example.com

# 3. Alternativa massima sicurezza: transparent proxy con iptables
# che cattura TUTTO il traffico uscente
```

### Lezione appresa

proxychains intercetta solo `connect()` e `getaddrinfo()` via LD_PRELOAD - non
cattura raw socket, ICMP, o syscall dirette. Per scanning anonimo, usare sempre
`-Pn` e preferire `-sT` (TCP connect). Vedi [proxychains-guida-completa.md](proxychains-guida-completa.md)
per i limiti di LD_PRELOAD.

---

## Scenario 2: DNS leak rilevato con tcpdump durante ricognizione

### Contesto

Il team conduceva OSINT su un target via Tor. Un tool Python personalizzato
usava `requests` con proxy SOCKS5, ma il DNS leakava verso l'ISP.

### Diagnosi

```bash
# Terminal 1: monitorare DNS uscente
sudo tcpdump -i eth0 port 53 -n

# Terminal 2: eseguire il tool
proxychains python3 osint-tool.py --target example.com

# tcpdump output:
# 10:30:12 IP 192.168.1.100.43210 > 8.8.8.8.53: A? api.target.com
# → DNS leak! Il tool risolve prima di inviare al proxy
```

Il problema: il tool usava `requests.get(url, proxies=...)` con `socks5://`
invece di `socks5h://`. La `h` alla fine indica "risolvi hostname via proxy".

### Fix

```python
# SBAGLIATO - risolve DNS localmente
proxies = {"https": "socks5://127.0.0.1:9050"}

# CORRETTO - risolve DNS via Tor
proxies = {"https": "socks5h://127.0.0.1:9050"}
```

### Lezione appresa

La differenza tra `socks5://` e `socks5h://` è critica. Senza la `h`, la
libreria risolve l'hostname localmente prima di inviare l'IP al proxy - il
DNS esce in chiaro. Vedi [dns-avanzato-e-hardening.md](dns-avanzato-e-hardening.md)
per tutti gli scenari di DNS leak.

---

## Scenario 3: Nyx rivela un guard compromesso durante un engagement

### Contesto

Un operatore aveva Tor attivo da 3 settimane per un engagement di lungo periodo.
Controllando Nyx occasionalmente, ha notato che la latenza verso il guard era
passata da 50ms a 800ms, e la bandwidth era crollata.

### Analisi con Nyx

```
# Schermata Connections in Nyx:
#  Guard $AAAA~SlowGuard  → latency: 823ms  bandwidth: 120 KB/s
#  (3 settimane fa era 50ms e 2 MB/s)
```

Verificando su Relay Search:
```bash
torsocks curl -s "https://onionoo.torproject.org/details?lookup=$AAAA" | python3 -c "
import json, sys
r = json.load(sys.stdin)['relays'][0]
print(f'Flags: {r.get(\"flags\",[])}')
print(f'Bandwidth: {r.get(\"observed_bandwidth\",0)//1024} KB/s')
"
# Flags: ['Running', 'Valid'] ← ha PERSO il flag Guard e Stable!
```

Il guard aveva perso i flag Guard e Stable - probabilmente problemi hardware o
di rete sul server. Ma Tor continuava a usarlo perché era ancora nel file `state`.

### Soluzione

```bash
# Forzare rotazione guard (solo in casi giustificati)
sudo systemctl stop tor@default.service
sudo rm /var/lib/tor/state
sudo systemctl start tor@default.service

# Verificare il nuovo guard in Nyx
nyx  # → Connections → guard con flag Guard+Stable e latenza <100ms
```

### Lezione appresa

Nyx (vedi [nyx-e-monitoraggio.md](nyx-e-monitoraggio.md)) è lo strumento migliore
per monitorare la salute dei circuiti nel tempo. In engagement di lungo periodo,
verificare periodicamente che il guard abbia ancora i flag appropriati.

---

## Scenario 4: torsocks blocca UDP e rompe un tool di scanning

### Contesto

Un operatore tentava di usare `torsocks` con un tool di enumerazione DNS che
usava query UDP dirette (non via la libreria C resolver).

### Problema

```bash
torsocks fierce --domain target.com
# WARNING torsocks[12345]: [syscall] Unsupported syscall number 44. Denying...
# Nessun risultato DNS
```

torsocks blocca tutte le syscall UDP (`sendto()` su socket SOCK_DGRAM) perché
Tor non supporta UDP. Ma il tool dipende da UDP per le query DNS.

### Soluzione

```bash
# Opzione 1: usare proxychains (non blocca UDP, ma non lo instradata)
# PRO: il tool funziona
# CONTRO: le query DNS escono in chiaro (leak!)
proxychains fierce --domain target.com

# Opzione 2: usare il DNSPort di Tor + configurare il tool
# Configurare il sistema per usare 127.0.0.1:5353 come DNS
# Le query saranno risolte da Tor

# Opzione 3: usare un DNS-over-TCP tool
# dig +tcp @127.0.0.1 -p 5353 target.com ANY
```

### Lezione appresa

torsocks è più sicuro di proxychains (blocca UDP invece di lasciarlo passare),
ma questo rompe tool che dipendono da UDP. La scelta tra proxychains e torsocks
dipende dal contesto: sicurezza vs compatibilità. Vedi
[torsocks-avanzato.md](torsocks-avanzato.md) per il confronto dettagliato.

---

## Scenario 5: Automazione NEWNYM per evasione rate limiting

### Contesto

Il team doveva enumerare endpoint di un'API protetta da rate limiting basato su
IP (max 100 richieste per IP, poi blocco di 5 minuti). Servivano 3000 richieste.

### Soluzione con NEWNYM automatizzato

```bash
#!/bin/bash
# rotate-and-query.sh - Esegue richieste con rotazione IP automatica

COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
ENDPOINT="https://api.target.com/v1/users"
BATCH_SIZE=90  # sotto il limite di 100

for batch in $(seq 1 34); do  # 34 batch × 90 = 3060 richieste
    echo "[Batch $batch] Ruotando IP..."
    printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
    sleep 3  # attendere la costruzione del nuovo circuito

    NEW_IP=$(proxychains curl -s https://api.ipify.org 2>/dev/null)
    echo "[Batch $batch] Nuovo IP: $NEW_IP"

    for i in $(seq 1 $BATCH_SIZE); do
        proxychains curl -s "$ENDPOINT?page=$((($batch-1)*$BATCH_SIZE+$i))" \
          >> results.json 2>/dev/null
    done
done
```

### Rate limit del NEWNYM

NEWNYM ha un rate limit interno: Tor accetta segnali NEWNYM al massimo ogni
10 secondi. Segnali più frequenti vengono ignorati silenziosamente.

```bash
# Verificare che il circuito sia cambiato
OLD_IP=$(proxychains curl -s https://api.ipify.org)
printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
sleep 3
NEW_IP=$(proxychains curl -s https://api.ipify.org)

if [ "$OLD_IP" = "$NEW_IP" ]; then
    echo "[!] IP non cambiato - pochi exit per questa porta"
fi
```

### Lezione appresa

Il ControlPort e NEWNYM (vedi [controllo-circuiti-e-newnym.md](controllo-circuiti-e-newnym.md))
permettono automazione avanzata. Il rate limit di 10 secondi va rispettato -
segnali più frequenti sono silenziosamente ignorati. Inoltre, NEWNYM non
garantisce un exit diverso: con pochi exit disponibili per la porta target,
lo stesso exit può essere riselezionato.

---

## Riepilogo

| Scenario | Strumento | Rischio mitigato |
|----------|----------|------------------|
| proxychains + nmap | proxychains | ICMP leak con IP reale |
| DNS leak Python | socks5h:// | Query DNS in chiaro verso ISP |
| Guard degradato | Nyx | Circuiti lenti per guard compromesso |
| torsocks + UDP | torsocks | Tool DNS rotto, scelta sicurezza vs compatibilità |
| Rate limiting | ControlPort/NEWNYM | Blocco IP dopo troppe richieste |

---

## Vedi anche

- [ProxyChains - Guida Completa](proxychains-guida-completa.md) - Limiti LD_PRELOAD
- [torsocks](torsocks.md) - Blocco UDP, edge cases
- [Nyx e Monitoraggio](nyx-e-monitoraggio.md) - Monitoraggio circuiti
- [Controllo Circuiti e NEWNYM](controllo-circuiti-e-newnym.md) - Automazione ControlPort
- [DNS Avanzato e Hardening](dns-avanzato-e-hardening.md) - Tutti gli scenari DNS leak
