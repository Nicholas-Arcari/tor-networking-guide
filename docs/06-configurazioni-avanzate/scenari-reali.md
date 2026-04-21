> **Lingua / Language**: Italiano | [English](../en/06-configurazioni-avanzate/scenari-reali.md)

# Scenari Reali - Configurazioni Avanzate Tor in Azione

Casi operativi in cui transparent proxy, VPN+Tor, multi-istanza, stream isolation
e gestione localhost hanno fatto la differenza durante penetration test e
red team engagement.

---

## Indice

- [Scenario 1: Transparent proxy blocca leak di tool non cooperante](#scenario-1-transparent-proxy-blocca-leak-di-tool-non-cooperante)
- [Scenario 2: Stream isolation mancante correla identità durante OSINT](#scenario-2-stream-isolation-mancante-correla-identità-durante-osint)
- [Scenario 3: VPN cade e Tor espone l'uso all'ISP](#scenario-3-vpn-cade-e-tor-espone-luso-allisp)
- [Scenario 4: Docker container leak IP reale via DNS hardcoded](#scenario-4-docker-container-leak-ip-reale-via-dns-hardcoded)

---

## Scenario 1: Transparent proxy blocca leak di tool non cooperante

### Contesto

Durante un pentest, il team usava un tool commerciale di vulnerability scanning
che non supportava proxy SOCKS5. Il tool doveva scansionare il target via Tor
per nascondere l'IP del team.

### Problema

Il tool ignorava `proxychains` (usava raw socket per alcune operazioni) e
non rispettava variabili d'ambiente proxy:

```bash
proxychains vuln-scanner --target api.target.com
# tcpdump mostra: pacchetti SYN diretti verso api.target.com
# → Il tool bypassava proxychains con syscall dirette
```

### Soluzione: transparent proxy temporaneo

```bash
# Attivare il transparent proxy
sudo ./tor-transparent-proxy.sh start
# → Tutto il TCP del sistema forzato via Tor
# → Anche le raw socket del tool passano da TransPort

# Eseguire lo scan
vuln-scanner --target api.target.com
# tcpdump: nessun traffico diretto verso il target
# Tutto ridirezionato a TransPort 9040

# Disattivare dopo lo scan
sudo ./tor-transparent-proxy.sh stop
```

### Lezione appresa

Il transparent proxy è la soluzione per tool che non supportano proxy o
che bypassano LD_PRELOAD. Le regole iptables catturano **tutto** il traffico
TCP a livello kernel, indipendentemente da come l'applicazione crea le
connessioni. Vedi [Transparent Proxy](transparent-proxy.md) per il setup
completo e [Transparent Proxy Avanzato](transparent-proxy-avanzato.md) per
lo script production-ready.

---

## Scenario 2: Stream isolation mancante correla identità durante OSINT

### Contesto

Un operatore OSINT raccoglieva informazioni su due target separati: una
persona fisica e un'azienda. Usava una singola istanza Tor con SocksPort 9050
senza flag di isolamento.

### Problema

Entrambe le ricerche condividevano lo stesso circuito Tor (stesso exit node):

```
[Browser tab 1: LinkedIn del target persona] → Exit 185.220.101.x
[Browser tab 2: sito azienda target]          → Exit 185.220.101.x
[curl: API OSINT per persona]                  → Exit 185.220.101.x

L'exit node (o un osservatore) vede:
  - Ricerca LinkedIn su "Mario Rossi"
  - Visita a target-azienda.com
  - Query API OSINT per "Mario Rossi"
→ Correla: qualcuno sta investigando Mario Rossi e la sua azienda
```

### Fix: IsolateSOCKSAuth con credenziali per-dominio

```ini
# torrc
SocksPort 9050 IsolateSOCKSAuth
```

```bash
# Ricerche su persona → circuito A
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "persona:osint1" \
     https://api.osint-tool.com/search?name=target

# Ricerche su azienda → circuito B (diverso)
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "azienda:osint2" \
     https://target-azienda.com/
```

### Lezione appresa

Senza `IsolateSOCKSAuth` o `IsolateDestAddr`, un singolo exit malevolo può
correlare tutte le attività dell'operatore. Per OSINT su target multipli,
usare credenziali SOCKS5 diverse per ogni target o istanze Tor separate.
Vedi [Multi-Istanza e Stream Isolation](multi-istanza-e-stream-isolation.md)
per il setup multi-istanza.

---

## Scenario 3: VPN cade e Tor espone l'uso all'ISP

### Contesto

Un operatore usava la configurazione VPN→Tor per nascondere l'uso di Tor
all'ISP aziendale (che monitorava il traffico). La VPN WireGuard era connessa
al server aziendale, e Tor passava dalla VPN.

### Problema

La connessione WireGuard è caduta (timeout del server) durante una sessione
Tor attiva. Tor si è riconnesso automaticamente al guard node **senza VPN**,
esponendo direttamente il traffico Tor all'ISP:

```
PRIMA (VPN attiva):
  Client → [WireGuard] → VPN Server → Guard Tor
  ISP vede: traffico WireGuard (non sa che è Tor)

DOPO (VPN caduta):
  Client → Guard Tor (direttamente)
  ISP vede: connessione diretta a IP noto come relay Tor
  → ISP alert: "utente connesso a relay Tor"
```

### Fix: kill switch iptables

```bash
#!/bin/bash
# Blocca tutto il traffico se la VPN non è attiva
VPN_IFACE="wg0"
VPN_SERVER_IP="85.x.x.x"

# Permetti solo verso il server VPN
iptables -A OUTPUT -d $VPN_SERVER_IP -j ACCEPT
# Permetti traffico sulla VPN
iptables -A OUTPUT -o $VPN_IFACE -j ACCEPT
# Permetti localhost
iptables -A OUTPUT -o lo -j ACCEPT
# DROP tutto il resto
iptables -A OUTPUT -j DROP

# Se wg0 cade → regola 2 non matcha → tutto droppato → no leak
```

### Lezione appresa

VPN→Tor senza kill switch è pericoloso. Se la VPN cade, Tor si riconnette
direttamente, esponendo l'uso all'ISP. Un kill switch iptables è **obbligatorio**
per questa configurazione. In alternativa, usare bridge obfs4 (non richiede
VPN e maschera il traffico Tor come HTTPS). Vedi
[VPN e Tor - Configurazioni Ibride](vpn-e-tor-ibrido.md) per le architetture.

---

## Scenario 4: Docker container leak IP reale via DNS hardcoded

### Contesto

Un tool di ricognizione era containerizzato in Docker con proxy SOCKS5
configurato via variabile d'ambiente. Il container doveva uscire via Tor.

### Problema

```yaml
# docker-compose.yml
services:
  recon:
    image: recon-tool:latest
    environment:
      - HTTPS_PROXY=socks5h://host.docker.internal:9050
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Il tool rispettava la variabile `HTTPS_PROXY` per le connessioni HTTP, ma
usava un resolver DNS interno con Google DNS hardcoded (`8.8.8.8`) per
alcune operazioni. Le query DNS uscivano dal container direttamente:

```bash
# Dall'host, monitorando:
sudo tcpdump -i docker0 port 53
# 10:15:32 IP 172.17.0.2.45123 > 8.8.8.8.53: A? target.com
# → DNS leak dal container!
```

### Soluzione: network isolation + DNS forzato

```yaml
services:
  recon:
    image: recon-tool:latest
    environment:
      - HTTPS_PROXY=socks5h://tor:9050
    networks:
      - tor-net
    dns: 172.18.0.2  # IP del container Tor (DNSPort)

  tor:
    image: tor-proxy:latest
    networks:
      - tor-net

networks:
  tor-net:
    driver: bridge
    internal: true  # NESSUN accesso diretto a Internet
```

Con `internal: true`, il container `recon` non può raggiungere Internet
direttamente - tutto deve passare dal container `tor`.

### Lezione appresa

Le variabili d'ambiente proxy non controllano il DNS in tutti i casi.
Container con resolver hardcoded bypassano il proxy per le query DNS.
Usare Docker network `internal: true` per forzare l'isolamento di rete,
combinato con un container Tor dedicato come unico punto di uscita. Vedi
[Tor e Localhost - Docker e Sviluppo](localhost-docker-e-sviluppo.md) per
gli scenari Docker.

---

## Riepilogo

| Scenario | Strumento | Rischio mitigato |
|----------|----------|------------------|
| Tool non cooperante | Transparent proxy | Leak IP da raw socket/syscall dirette |
| OSINT multi-target | IsolateSOCKSAuth | Correlazione tra target diversi |
| VPN drop senza kill switch | iptables kill switch | Esposizione uso Tor all'ISP |
| Docker DNS hardcoded | Docker internal network | DNS leak da container |

---

## Vedi anche

- [Transparent Proxy](transparent-proxy.md) - Setup iptables/nftables
- [Multi-Istanza e Stream Isolation](multi-istanza-e-stream-isolation.md) - Isolamento circuiti
- [VPN e Tor - Configurazioni Ibride](vpn-e-tor-ibrido.md) - VPN→Tor, kill switch
- [Tor e Localhost](tor-e-localhost.md) - Docker e servizi locali
