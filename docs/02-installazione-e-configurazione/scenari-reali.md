# Scenari Reali - Installazione e Configurazione in Azione

Casi operativi in cui la corretta installazione, configurazione del torrc
e gestione del servizio hanno fatto la differenza durante engagement reali.

---

## Indice

- [Scenario 1: Torrc misconfigured causa DNS leak in un pentest](#scenario-1-torrc-misconfigured-causa-dns-leak-in-un-pentest)
- [Scenario 2: Bootstrap failure durante un audit in rete restrittiva](#scenario-2-bootstrap-failure-durante-un-audit-in-rete-restrittiva)
- [Scenario 3: Clock skew blocca Tor in una VM di laboratorio](#scenario-3-clock-skew-blocca-tor-in-una-vm-di-laboratorio)
- [Scenario 4: Permessi debian-tor rompono l'automazione NEWNYM](#scenario-4-permessi-debian-tor-rompono-lautomazione-newnym)
- [Scenario 5: Configurazione multi-identità per red team engagement](#scenario-5-configurazione-multi-identità-per-red-team-engagement)

---

## Scenario 1: Torrc misconfigured causa DNS leak in un pentest

### Contesto

Durante un penetration test esterno, l'operatore usava Tor per la ricognizione
anonima. Il torrc aveva `SocksPort 9050` configurato correttamente, ma mancava
`DNSPort` e l'applicazione (un tool di OSINT) faceva risoluzione DNS diretta
bypassando il SOCKS proxy.

### Problema

Il tool effettuava query DNS verso il DNS dell'ISP dell'operatore prima di
connettersi via Tor. Il target aveva monitoring DNS passivo e ha rilevato
query dal range IP del team di pentest - prima ancora che il traffico HTTP
arrivasse via Tor.

### Analisi

```bash
# Verificare se ci sono DNS leak
# 1. Monitorare le query DNS uscenti
sudo tcpdump -i eth0 port 53 -n

# 2. Mentre si esegue il tool
proxychains python3 osint-tool.py --target example.com

# Output tcpdump:
# 10:23:45 IP 192.168.1.100.52341 > 8.8.8.8.53: A? example.com
# → DNS leak! La query esce in chiaro
```

### Soluzione

```ini
# Aggiungere al torrc
DNSPort 5353
AutomapHostsOnResolve 1
```

```bash
# Configurare il resolver di sistema per usare Tor DNS
# /etc/resolv.conf
nameserver 127.0.0.1

# Redirezionare porta 53 a 5353 con iptables
sudo iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
sudo iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353
```

### Lezione appresa

`SocksPort` protegge solo il traffico TCP che transita via SOCKS. Le query DNS
sono un canale separato. Senza `DNSPort` e senza regole iptables, qualsiasi
applicazione che fa DNS diretto causa leak. Vedi [torrc - Guida Completa](torrc-guida-completa.md)
per la configurazione completa di `DNSPort` e `AutomapHostsOnResolve`.

---

## Scenario 2: Bootstrap failure durante un audit in rete restrittiva

### Contesto

Audit di sicurezza presso un cliente con rete corporate protetta da firewall
next-gen e proxy HTTPS obbligatorio. Il team doveva operare da dentro la rete
del cliente, ma Tor non riusciva a completare il bootstrap.

### Diagnosi step-by-step

```bash
# 1. Verificare lo stato
sudo journalctl -u tor@default.service -f
# Output: "Bootstrapped 5% (conn): Connecting to a relay" per 3 minuti

# 2. Senza bridge: il firewall blocca le connessioni dirette ai relay
# Tor usa porta 9001 (ORPort) che il firewall non permette

# 3. Con bridge obfs4: il bootstrap arriva al 10% poi si blocca
# Il firewall fa man-in-the-middle su tutto il traffico TLS (corporate proxy)
# obfs4 non riesce a negoziare perché il certificato del bridge non corrisponde

# 4. Soluzione: ReachableAddresses + meek-azure (simula traffico Azure CDN)
```

### Configurazione risolutiva

```ini
# torrc per rete con HTTPS proxy obbligatorio
UseBridges 1
ClientTransportPlugin meek_lite exec /usr/bin/obfs4proxy

# meek-azure simula traffico verso Azure CDN - il proxy corporate lo permette
Bridge meek_lite 0.0.2.0:2 97700DFE9F483596DDA6264C4D7DF7641E1E39CE \
  url=https://meek.azureedge.net/ front=ajax.aspnetcdn.com

# Solo porte permesse dal firewall
ReachableAddresses *:80, *:443
ReachableAddresses reject *:*
```

### Lezione appresa

In reti corporate con proxy HTTPS, obfs4 spesso fallisce perché il proxy
intercetta e modifica il TLS handshake. `meek` funziona meglio perché usa
domain fronting attraverso CDN legittime che il proxy permette.
La direttiva `ReachableAddresses` (vedi [torrc-bridge-e-sicurezza.md](torrc-bridge-e-sicurezza.md))
è essenziale in questi contesti.

---

## Scenario 3: Clock skew blocca Tor in una VM di laboratorio

### Contesto

Un analista ha preparato una VM Kali per un engagement. La VM era stata
snapshot-ata settimane prima. Al boot, l'orologio della VM era indietro
di 18 giorni. Tor rifiutava il consenso.

### Sintomo

```bash
sudo journalctl -u tor@default.service | tail -5
# [warn] Our clock is 18 days behind the time published in the consensus.
# [warn] Tor needs an accurate clock to work correctly. Please check your time.
# [err] No valid consensus available.
```

### Soluzione

```bash
# 1. Verificare l'orologio
timedatectl
#   Local time: Mon 2026-03-20 14:23:00 CET  ← 18 giorni indietro

# 2. Sincronizzare con NTP
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# 3. Verificare
timedatectl
#   Local time: Mon 2026-04-07 14:23:15 CET  ← corretto

# 4. Riavviare Tor
sudo systemctl restart tor@default.service

# 5. Monitorare il bootstrap
sudo journalctl -u tor@default.service -f
# Bootstrapped 100% (done): Done
```

### Lezione appresa

Il consenso Tor ha finestre di validità strette (3 ore). Un clock skew anche
moderato può impedire il bootstrap. Nelle VM, specialmente dopo restore da
snapshot, l'orologio è quasi sempre sbagliato. Verificare `timedatectl`
prima di avviare Tor è un passo da includere in ogni checklist operativa.
Vedi [gestione-del-servizio.md](gestione-del-servizio.md) per il debug completo.

---

## Scenario 4: Permessi debian-tor rompono l'automazione NEWNYM

### Contesto

Il team aveva automatizzato la rotazione IP con uno script bash eseguito da
cron. Lo script funzionava quando eseguito manualmente, ma falliva quando
schedulato in cron.

### Problema

```bash
# Crontab:
*/5 * * * * /home/operator/scripts/rotate-ip.sh >> /var/log/rotate.log 2>&1

# Log output:
# [2026-04-07 10:05:01] Authenticating to ControlPort...
# 515 Authentication failed
```

L'utente `operator` era nel gruppo `debian-tor` e poteva leggere il cookie
in una shell interattiva. Ma cron non carica i gruppi supplementari allo
stesso modo - il processo cron non aveva i permessi per leggere
`/run/tor/control.authcookie`.

### Soluzione

```bash
# Opzione 1: eseguire lo script come debian-tor
*/5 * * * * sudo -u debian-tor /home/operator/scripts/rotate-ip.sh

# Opzione 2: usare HashedControlPassword invece di CookieAuthentication
# Nel torrc:
HashedControlPassword 16:872860B76453A77D...

# Nello script:
printf 'AUTHENTICATE "password"\r\nSIGNAL NEWNYM\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051
```

### Lezione appresa

`CookieAuthentication` dipende dai permessi del file system. In contesti
automatizzati (cron, systemd timer, Ansible), i gruppi supplementari
dell'utente non sono sempre disponibili. Per automazione,
`HashedControlPassword` è più affidabile - ma la password va protetta.
Vedi [configurazione-iniziale.md](configurazione-iniziale.md) per la
configurazione del gruppo debian-tor e i suoi limiti.

---

## Scenario 5: Configurazione multi-identità per red team engagement

### Contesto

Red team engagement con 3 operatori che condividevano la stessa macchina
Kali come punto di uscita Tor. Ogni operatore aveva un target diverso e
doveva mantenere identità separate - se un operatore veniva rilevato, gli
altri due non dovevano essere correlabili.

### Problema

Con un solo `SocksPort 9050`, tutti gli operatori condividevano gli stessi
circuiti. Un `SIGNAL NEWNYM` da parte di un operatore invalidava i circuiti
di tutti gli altri.

### Soluzione: torrc multi-porta

```ini
# torrc - tre identità isolate
SocksPort 9050 IsolateSOCKSAuth IsolateDestAddr  # Operatore 1
SocksPort 9052 IsolateSOCKSAuth IsolateDestAddr  # Operatore 2
SocksPort 9054 IsolateSOCKSAuth IsolateDestAddr  # Operatore 3

ControlPort 9051
CookieAuthentication 1
DNSPort 5353
```

```bash
# proxychains per ogni operatore
# /etc/proxychains4-op1.conf → socks5 127.0.0.1 9050
# /etc/proxychains4-op2.conf → socks5 127.0.0.1 9052
# /etc/proxychains4-op3.conf → socks5 127.0.0.1 9054

# Uso:
proxychains4 -f /etc/proxychains4-op1.conf nmap -sT target1.com
proxychains4 -f /etc/proxychains4-op2.conf curl target2.com
```

### Lezione appresa

Per engagement multi-operatore, i `SocksPort` multipli con `IsolateSOCKSAuth`
e `IsolateDestAddr` garantiscono che i circuiti siano completamente separati.
Alternativa più robusta: istanze Tor multiple (vedi
[Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md)).
Vedi [torrc-performance-e-relay.md](torrc-performance-e-relay.md) per la
configurazione completa.

---

## Riepilogo

| Scenario | Configurazione applicata | Rischio mitigato |
|----------|------------------------|------------------|
| DNS leak | DNSPort + iptables redirect | Query DNS in chiaro verso ISP |
| Rete restrittiva | meek + ReachableAddresses | Bootstrap failure dietro corporate proxy |
| Clock skew | NTP + timedatectl | Consenso rifiutato, Tor non parte |
| Permessi cron | HashedControlPassword | Automazione NEWNYM fallita |
| Multi-operatore | SocksPort multipli isolati | Correlazione tra identità operatori |

---

## Vedi anche

- [Installazione e Verifica](installazione-e-verifica.md) - Setup iniziale
- [torrc - Guida Completa](torrc-guida-completa.md) - Tutte le direttive
- [Gestione del Servizio](gestione-del-servizio.md) - systemd, log, debug
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Approfondimento DNS leak
- [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Istanze multiple
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - iptables e intercettazione DNS
