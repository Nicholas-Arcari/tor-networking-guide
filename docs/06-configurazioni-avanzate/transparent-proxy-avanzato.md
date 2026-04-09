# Transparent Proxy Avanzato - LAN, Troubleshooting e Script Production

Gateway Tor per la LAN (PREROUTING), troubleshooting completo (7 problemi comuni),
hardening del transparent proxy, script production-ready con check e rollback,
confronto con Whonix/Tails e limiti.

> **Estratto da**: [Transparent Proxy](transparent-proxy.md) per TransPort,
> iptables/nftables, IPv6 e il meccanismo kernel.

---

## Transparent proxy per traffico LAN (PREROUTING)

### Scenario: gateway Tor per la LAN

Architettura: un computer Kali fa da gateway per altri dispositivi, torificando
tutto il loro traffico:

```
[Laptop] ────┐
              │
[Telefono] ──┼──→ [Kali Gateway] ──→ [Tor] ──→ Internet
              │    eth0: 192.168.1.100
[IoT] ───────┘    (ip_forward=1)
```

### Regole PREROUTING

```bash
# Abilitare IP forwarding
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# NAT PREROUTING: cattura traffico dalla LAN
iptables -t nat -A PREROUTING -i eth0 -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -A PREROUTING -i eth0 -p tcp --syn -j REDIRECT --to-ports 9040

# FILTER FORWARD: blocca traffico non ridirezionato
iptables -A FORWARD -j DROP
```

### Torrc per gateway

```ini
# Accettare connessioni dalla LAN (non solo localhost)
TransPort 0.0.0.0:9040
DNSPort 0.0.0.0:5353

# ATTENZIONE: questo espone TransPort e DNSPort sulla rete
# Usare solo su reti fidate e controllate
```

**Rischio**: se la rete LAN non è fidata, chiunque può usare il tuo nodo Tor
come proxy. Limitare con iptables INPUT per IP/subnet specifici.

---

## Troubleshooting

### Problema 1: Nessuna rete dopo attivazione

**Sintomo**: dopo lo script, nessuna connessione funziona.

```bash
# Verificare che Tor sia attivo
systemctl is-active tor@default.service

# Verificare che TransPort sia in ascolto
ss -tlnp | grep 9040
# Se vuoto → TransPort non configurato nel torrc

# Verificare bootstrap
journalctl -u tor@default.service | grep "Bootstrapped"
# Se non al 100% → Tor non è ancora connesso
```

### Problema 2: DNS non funziona

**Sintomo**: le pagine web non si caricano, ma `curl http://IP:porta` funziona.

```bash
# Verificare DNSPort
ss -ulnp | grep 5353
# Se vuoto → DNSPort non configurato

# Test DNS diretto
dig @127.0.0.1 -p 5353 example.com
# Se timeout → Tor non risolve DNS

# Verificare regola iptables
iptables -t nat -L OUTPUT -n -v | grep 53
# Deve mostrare la regola REDIRECT per porta 53
```

### Problema 3: apt update lentissimo

**Causa**: tutto il traffico apt passa per Tor (3 hop) → lento.

```bash
# Soluzione temporanea: escludere _apt dall'iptables
APT_UID=$(id -u _apt)
iptables -t nat -I OUTPUT -m owner --uid-owner $APT_UID -j RETURN
iptables -I OUTPUT -m owner --uid-owner $APT_UID -j ACCEPT

# Dopo l'update, rimuovere l'eccezione:
iptables -t nat -D OUTPUT -m owner --uid-owner $APT_UID -j RETURN
iptables -D OUTPUT -m owner --uid-owner $APT_UID -j ACCEPT
```

### Problema 4: NTP bloccato, orologio che deriva

**Causa**: NTP usa UDP porta 123 → bloccato.

```bash
# Verificare orologio
timedatectl status

# Soluzione: sincronizzare manualmente via HTTP
torsocks curl -s http://worldtimeapi.org/api/ip | python3 -c "
import json, sys, subprocess
data = json.load(sys.stdin)
print(f'Setting time to: {data[\"datetime\"]}')"

# Oppure: permettere NTP nell'iptables (leak accettabile per NTP)
iptables -I OUTPUT -p udp --dport 123 -j ACCEPT
# NOTA: NTP leak rivela timezone/locale, ma non traffico web
```

### Problema 5: Servizi locali non raggiungibili

**Sintomo**: non riesci a connetterti a localhost:5173 (Docker, dev server).

```bash
# Verificare che localhost sia escluso dal redirect
iptables -t nat -L OUTPUT -n | grep 127.0.0.0
# Deve mostrare RETURN per 127.0.0.0/8

# Se manca, aggiungere:
iptables -t nat -I OUTPUT 3 -d 127.0.0.0/8 -j RETURN
```

### Problema 6: Rollback d'emergenza

```bash
# Se qualcosa va storto e perdi connettività:
iptables -F
iptables -t nat -F
iptables -P OUTPUT ACCEPT
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT

# Con nftables:
nft flush ruleset
```

### Problema 7: Verificare che le regole siano attive

```bash
# iptables
iptables -t nat -L OUTPUT -n -v --line-numbers
iptables -L OUTPUT -n -v --line-numbers

# nftables
nft list ruleset

# Verificare con traffico reale
curl --max-time 10 https://check.torproject.org/api/ip
# {"IsTor":true,"IP":"..."}
```

---

## Hardening del transparent proxy

### Blocco ICMP redirect

```bash
# Prevenire ICMP redirect che potrebbero bypassare le regole
sysctl -w net.ipv4.conf.all.accept_redirects=0
sysctl -w net.ipv4.conf.all.send_redirects=0
sysctl -w net.ipv4.conf.all.secure_redirects=0
```

### Protezione IP spoofing

```bash
# Attivare reverse path filtering
sysctl -w net.ipv4.conf.all.rp_filter=1
```

### Logging pacchetti droppati

```bash
# Aggiungere regola LOG prima del DROP finale
iptables -A OUTPUT -j LOG --log-prefix "[TOR-DROP] " --log-level 4
iptables -A OUTPUT -j DROP

# Monitorare:
sudo journalctl -k | grep TOR-DROP
```

### Disabilitare servizi che leakano

```bash
# Disabilitare Avahi (mDNS)
sudo systemctl stop avahi-daemon
sudo systemctl disable avahi-daemon

# Disabilitare CUPS browsing (se non serve)
sudo systemctl stop cups-browsed

# Disabilitare NetworkManager connectivity check
# /etc/NetworkManager/NetworkManager.conf
[connectivity]
enabled=false
```

---

## Script production-ready

```bash
#!/bin/bash
# tor-transparent-proxy.sh - Script production-ready per transparent proxy Tor
# Uso: sudo ./tor-transparent-proxy.sh {start|stop|status}

set -euo pipefail

LOCK_FILE="/var/run/tor-transparent-proxy.lock"
BACKUP_FILE="/tmp/iptables-backup-$(date +%s).rules"
TOR_UID=$(id -u debian-tor 2>/dev/null || echo "")
TRANS_PORT=9040
DNS_PORT=5353

log() { echo "[$(date '+%H:%M:%S')] $1"; }

check_prereqs() {
    if [ -z "$TOR_UID" ]; then
        log "ERRORE: utente debian-tor non trovato"
        exit 1
    fi
    
    if ! systemctl is-active --quiet tor@default.service; then
        log "ERRORE: Tor non è attivo. Avvialo prima: sudo systemctl start tor@default.service"
        exit 1
    fi
    
    if ! ss -tlnp | grep -q ":${TRANS_PORT} "; then
        log "ERRORE: TransPort $TRANS_PORT non in ascolto. Aggiungi 'TransPort $TRANS_PORT' al torrc"
        exit 1
    fi
    
    if ! ss -ulnp | grep -q ":${DNS_PORT} "; then
        log "ERRORE: DNSPort $DNS_PORT non in ascolto. Aggiungi 'DNSPort $DNS_PORT' al torrc"
        exit 1
    fi
    
    if ! journalctl -u tor@default.service --no-pager 2>/dev/null | grep -q "Bootstrapped 100%"; then
        log "WARNING: Bootstrap non al 100%. La connettività potrebbe essere limitata."
    fi
}

start() {
    if [ -f "$LOCK_FILE" ]; then
        log "ERRORE: transparent proxy già attivo (lock file: $LOCK_FILE)"
        exit 1
    fi
    
    check_prereqs
    
    # Backup regole correnti
    iptables-save > "$BACKUP_FILE"
    log "Backup regole salvato in $BACKUP_FILE"
    
    log "Attivazione transparent proxy..."
    
    # Flush regole esistenti
    iptables -t nat -F OUTPUT
    iptables -F OUTPUT
    
    # --- NAT ---
    iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_UID -j RETURN
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $DNS_PORT
    iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A OUTPUT -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A OUTPUT -d 10.0.0.0/8 -j RETURN
    iptables -t nat -A OUTPUT -d 172.16.0.0/12 -j RETURN
    iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TRANS_PORT
    
    # --- FILTER ---
    iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT
    iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT
    iptables -A OUTPUT -p udp -d 127.0.0.1 --dport $DNS_PORT -j ACCEPT
    iptables -A OUTPUT -j DROP
    
    # --- IPv6 DROP ---
    ip6tables -A OUTPUT -j DROP 2>/dev/null || true
    
    # Lock file
    echo "$(date)" > "$LOCK_FILE"
    
    log "Transparent proxy ATTIVO."
    log "  ATTENZIONE: UDP (tranne DNS) è bloccato"
    log "  ATTENZIONE: IPv6 è bloccato"
    log "  Per disattivare: sudo $0 stop"
    
    # Verifica
    log "Verifica connessione..."
    TOR_IP=$(curl -s --max-time 30 https://api.ipify.org 2>/dev/null)
    if [ -n "$TOR_IP" ]; then
        log "OK: connessione via Tor funzionante (exit: $TOR_IP)"
    else
        log "WARNING: verifica connessione fallita. Controllare i log di Tor."
    fi
}

stop() {
    log "Disattivazione transparent proxy..."
    
    iptables -t nat -F OUTPUT
    iptables -F OUTPUT
    iptables -P OUTPUT ACCEPT
    ip6tables -F OUTPUT 2>/dev/null || true
    ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
    
    rm -f "$LOCK_FILE"
    
    log "Transparent proxy DISATTIVATO. Traffico diretto ripristinato."
}

status() {
    if [ -f "$LOCK_FILE" ]; then
        log "Transparent proxy: ATTIVO (dal $(cat $LOCK_FILE))"
    else
        log "Transparent proxy: NON ATTIVO"
    fi
    
    echo ""
    echo "=== Regole NAT OUTPUT ==="
    iptables -t nat -L OUTPUT -n -v --line-numbers 2>/dev/null
    echo ""
    echo "=== Regole FILTER OUTPUT ==="
    iptables -L OUTPUT -n -v --line-numbers 2>/dev/null
}

case "${1:-}" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    *)      echo "Uso: sudo $0 {start|stop|status}" ;;
esac
```

---

## Confronto con Whonix e Tails

### Whonix

Whonix implementa il transparent proxy con un approccio a due VM:

```
[Workstation VM] ──only──→ [Gateway VM] ──→ [Tor] ──→ Internet
  - Non ha accesso diretto      - Transparent proxy
    alla rete                    - TransPort + DNSPort
  - Tutto passa per il gateway   - Filtra TUTTO il non-Tor
```

Vantaggi vs script iptables:
- Isolamento a livello VM (anche se il kernel è compromesso)
- La workstation non può MAI raggiungere la rete direttamente
- Non dipende da regole iptables (che possono essere bypassate con root)

### Tails

Tails usa un approccio simile ma su sistema live:

- Boot da USB → nessuna persistenza su disco
- iptables configurato al boot (immutabile)
- Tutto il traffico forzato via Tor
- Failsafe: se Tor non funziona, nessuna connettività

### Confronto

| Aspetto | Script iptables | Whonix | Tails |
|---------|----------------|--------|-------|
| Isolamento | Iptables (user-space) | VM (hypervisor) | Live OS |
| Root bypass | Sì (root può flush) | No (VM separate) | No (read-only) |
| Persistenza | Configurabile | Sì | No (RAM only) |
| Complessità | Bassa | Media | Bassa (preconfigurato) |
| Flessibilità | Alta | Media | Bassa |
| Sicurezza | Media | Alta | Alta |

---

## Limiti del transparent proxy

| Limite | Descrizione | Mitigazione |
|--------|-------------|-------------|
| No UDP | Tor non supporta UDP → bloccato | Nessuna |
| No ICMP | ping non funziona | Nessuna |
| Performance | Tutto il traffico su 3 hop → lento | Esclusioni per UID |
| Single point of failure | Se Tor crasha, niente rete | Monitoraggio + auto-restart |
| NTP bloccato | Orologio potrebbe desincronizzarsi | Sync HTTP o eccezione NTP |
| apt lento | Aggiornamenti via Tor | Eccezione per _apt UID |
| No stream isolation | TransPort non supporta isolamento | Usare SocksPort dove possibile |
| Root bypass | Root può rimuovere regole | Whonix/Tails per protezione |
| Hostname perso | TransPort riceve solo IP | DNSPort + AutomapHosts |

---

## Nella mia esperienza

Non uso il transparent proxy quotidianamente sul mio Kali. Preferisco il routing
selettivo con proxychains per-applicazione perché:

- **Non blocca UDP per le attività normali**: NTP, DNS per attività non-Tor, e
  altri servizi UDP continuano a funzionare
- **Non rallenta tutto il sistema**: solo le applicazioni esplicitamente torrificate
  passano per i 3 hop di Tor
- **Più flessibile**: posso scegliere cosa anonimizzare e cosa no

Uso il transparent proxy in due scenari specifici:

1. **Testing di sicurezza temporaneo**: quando devo assicurarmi che nessun traffico
   esca direttamente (es. durante un test OSINT dove un singolo leak rivelerebbe
   il mio IP). Attivo lo script, eseguo i test, lo disattivo.

2. **Verifica leak**: attivo il transparent proxy per verificare che le mie
   configurazioni per-applicazione non abbiano leak nascosti. Se tutto funziona
   anche con il transparent proxy, vuol dire che le app sono configurate
   correttamente.

Lo script production-ready con check pre-condizioni e lock file l'ho sviluppato
dopo un'esperienza negativa: avevo attivato il transparent proxy senza verificare
che Tor avesse completato il bootstrap. Risultato: nessuna connettività per 2
minuti, il tempo che Tor finisse il bootstrap. Ora lo script verifica tutto prima
di attivare le regole.

---

## Vedi anche

- [VPN e Tor Ibrido](vpn-e-tor-ibrido.md) - TransPort come alternativa quasi-VPN
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Prevenzione DNS leak con TransPort
- [Multi-Istanza e Stream Isolation](multi-istanza-e-stream-isolation.md) - Isolamento circuiti
- [Hardening di Sistema](../05-sicurezza-operativa/hardening-sistema.md) - nftables e regole firewall
- [Isolamento e Compartimentazione](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Namespace e container come alternative
