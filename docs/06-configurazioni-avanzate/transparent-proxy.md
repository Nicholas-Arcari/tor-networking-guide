# Transparent Proxy — Forzare Tutto il Traffico via Tor con iptables/nftables

Questo documento analizza come configurare un transparent proxy Tor usando iptables
e nftables, che instrada tutto il traffico TCP del sistema attraverso Tor senza
richiedere configurazione per-applicazione.

> **Vedi anche**: [VPN e Tor Ibrido](./vpn-e-tor-ibrido.md) per routing selettivo,
> [DNS Leak](../05-sicurezza-operativa/dns-leak.md) per prevenzione leak DNS,
> [Isolamento e Compartimentazione](../05-sicurezza-operativa/isolamento-e-compartimentazione.md)
> per Whonix/Tails, [torrc Guida Completa](../02-installazione-e-configurazione/torrc-guida-completa.md)
> per TransPort.

---

## Indice

- [Cos'è un Transparent Proxy](#cosè-un-transparent-proxy)
- [Come funziona TransPort a livello kernel](#come-funziona-transport-a-livello-kernel)
- [Configurazione torrc](#configurazione-torrc)
- [Regole iptables — analisi riga per riga](#regole-iptables--analisi-riga-per-riga)
- [nftables — equivalente moderno](#nftables--equivalente-moderno)
- [IPv6 e transparent proxy](#ipv6-e-transparent-proxy)
- [Transparent proxy per traffico LAN (PREROUTING)](#transparent-proxy-per-traffico-lan-prerouting)
- [Troubleshooting](#troubleshooting)
- [Hardening del transparent proxy](#hardening-del-transparent-proxy)
- [Script production-ready](#script-production-ready)
- [Confronto con Whonix e Tails](#confronto-con-whonix-e-tails)
- [Limiti del transparent proxy](#limiti-del-transparent-proxy)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Cos'è un Transparent Proxy

Un transparent proxy intercetta il traffico a livello di kernel (netfilter) e lo
ridireziona verso Tor, senza che le applicazioni ne siano consapevoli:

```
Senza transparent proxy:
[App] → connect(93.184.216.34:443) → Internet (diretto, il tuo IP reale)

Con transparent proxy:
[App] → connect(93.184.216.34:443)
  → netfilter intercetta (REDIRECT rule)
  → ridireziona a 127.0.0.1:9040 (TransPort Tor)
  → Tor costruisce circuito
  → Exit node si connette a 93.184.216.34:443
  → IP visibile: exit node, non il tuo
```

Il vantaggio: **nessuna configurazione per-applicazione**. Ogni processo sul
sistema è forzato attraverso Tor. Lo svantaggio: **tutto o niente** — non puoi
escludere selettivamente applicazioni (tranne con eccezioni iptables per UID).

---

## Come funziona TransPort a livello kernel

### Il meccanismo REDIRECT

Quando iptables esegue `REDIRECT --to-ports 9040` su un pacchetto TCP:

1. **Intercettazione**: netfilter cattura il pacchetto nella catena OUTPUT
2. **Modifica destinazione**: il kernel riscrive `dst_addr:dst_port` a `127.0.0.1:9040`
3. **Conntrack**: il kernel memorizza la destinazione originale nella tabella conntrack:
   ```
   conntrack entry:
     src=127.0.0.1:45678 dst=93.184.216.34:443 → redirect to 127.0.0.1:9040
   ```
4. **Consegna a Tor**: il pacchetto arriva al socket TransPort di Tor
5. **SO_ORIGINAL_DST**: Tor chiama `getsockopt(SO_ORIGINAL_DST)` per recuperare
   la destinazione originale (93.184.216.34:443) dalla tabella conntrack
6. **Connessione via circuito**: Tor costruisce un circuito e fa `RELAY_BEGIN`
   verso la destinazione originale

```
Kernel flow:
[App: connect(93.184.216.34:443)]
  ↓
[netfilter OUTPUT chain]
  ↓ match: -p tcp --syn
  ↓ target: REDIRECT --to-ports 9040
  ↓
[conntrack: salva original dst = 93.184.216.34:443]
  ↓
[pacchetto arriva a 127.0.0.1:9040 (TransPort Tor)]
  ↓
[Tor: getsockopt(fd, SOL_IP, SO_ORIGINAL_DST) → 93.184.216.34:443]
  ↓
[Tor: RELAY_BEGIN "93.184.216.34:443" via circuito]
```

### Differenza con SocksPort

| Aspetto | SocksPort | TransPort |
|---------|-----------|-----------|
| Protocollo | SOCKS5 (applicazione consapevole) | TCP nativo (trasparente) |
| DNS | Hostname via SOCKS5 (ATYP=0x03) | IP solo (hostname perso) |
| Configurazione app | Necessaria (proxy setting) | Non necessaria |
| Isolamento | Per-stream (IsolateSOCKSAuth) | No (tutti sullo stesso circuito) |
| Overhead | SOCKS5 handshake | Nessuno (redirect kernel) |

**Problema critico**: TransPort riceve solo l'IP di destinazione, non l'hostname.
Tor non sa quale sito stai visitando (solo l'IP). Questo può causare problemi con
hosting condiviso (più siti sullo stesso IP). Per questo il DNS deve essere risolto
separatamente via DNSPort.

---

## Configurazione torrc

```ini
# Porte standard
SocksPort 9050
DNSPort 5353
ControlPort 9051
CookieAuthentication 1

# TransPort per transparent proxy
TransPort 9040

# AutomapHosts per mapping DNS
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10

# Sicurezza
ClientUseIPv6 0
```

### Dettaglio direttive

| Direttiva | Valore | Perché |
|-----------|--------|--------|
| `TransPort 9040` | Porta TCP per connessioni redirect | Accetta TCP nativo (non SOCKS) |
| `DNSPort 5353` | Porta UDP per DNS | Risolve DNS via Tor |
| `AutomapHostsOnResolve 1` | Mappa hostname → IP fittizi | Necessario per mapping DNS→TransPort |
| `VirtualAddrNetworkIPv4` | Range IP fittizi | Per AutomapHosts |
| `ClientUseIPv6 0` | Disabilita IPv6 | Previene leak IPv6 |

---

## Regole iptables — analisi riga per riga

### Script completo annotato

```bash
#!/bin/bash
TOR_UID=$(id -u debian-tor)
TRANS_PORT=9040
DNS_PORT=5353

# --- NAT table: ridirezionamento ---

# Regola 1: Non toccare il traffico di Tor stesso
iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_UID -j RETURN
# -m owner: match basato sull'UID del processo
# --uid-owner $TOR_UID: solo il processo Tor (utente debian-tor)
# -j RETURN: non applicare altre regole NAT → traffico Tor esce diretto
# SENZA QUESTA REGOLA: il traffico di Tor verrebbe ridirezionato a se stesso → loop infinito

# Regola 2: Ridireziona DNS al DNSPort di Tor
iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $DNS_PORT
# -p udp --dport 53: cattura tutte le query DNS (UDP porta 53)
# -j REDIRECT: riscrive la destinazione a 127.0.0.1:DNS_PORT
# Effetto: ogni query DNS del sistema viene risolta via Tor

# Regola 3: Non ridirezionare localhost
iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN
# -d 127.0.0.0/8: traffico diretto a localhost
# RETURN: lascia passare senza redirect
# Necessario per: ControlPort, SocksPort, comunicazione interna

# Regola 4: Non ridirezionare rete locale
iptables -t nat -A OUTPUT -d 192.168.0.0/16 -j RETURN
iptables -t nat -A OUTPUT -d 10.0.0.0/8 -j RETURN
# Necessario per: DHCP, servizi LAN, stampanti, NAS

# Regola 5: Ridireziona TUTTO il TCP rimanente al TransPort
iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TRANS_PORT
# --syn: solo pacchetti SYN (nuove connessioni)
# PERCHÉ --syn: le connessioni già stabilite continuano normalmente
# senza --syn, ogni pacchetto TCP verrebbe processato → overhead enorme

# --- FILTER table: blocco leak ---

# Regola 6: Permetti traffico di Tor
iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT

# Regola 7: Permetti traffico locale
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT

# Regola 8: Permetti DNS verso DNSPort
iptables -A OUTPUT -p udp -d 127.0.0.1 --dport $DNS_PORT -j ACCEPT

# Regola 9: BLOCCA TUTTO IL RESTO
iptables -A OUTPUT -j DROP
# Questa è la regola di sicurezza: se qualcosa sfugge al NAT redirect,
# viene droppato qui. Previene qualsiasi leak.
```

### L'ordine delle regole è critico

Le regole vengono valutate in ordine. Se invertissimo le regole 1 e 5:
- Il traffico TCP di Tor verrebbe ridirezionato a TransPort
- TransPort manderebbe il traffico a Tor → che viene ridirezionato → loop
- **Risultato: nessuna connettività, possibile crash di Tor**

---

## nftables — equivalente moderno

Kali Linux e Debian stanno migrando da iptables a nftables. Ecco l'equivalente:

### Conversione completa

```nft
#!/usr/sbin/nft -f

# Flush regole esistenti
flush ruleset

# Variabili
define TOR_UID = debian-tor
define TRANS_PORT = 9040
define DNS_PORT = 5353

table ip tor_proxy {
    
    chain output_nat {
        type nat hook output priority -100; policy accept;
        
        # Non toccare il traffico di Tor stesso
        meta skuid $TOR_UID return
        
        # Ridireziona DNS al DNSPort di Tor
        udp dport 53 redirect to :$DNS_PORT
        
        # Non ridirezionare localhost e LAN
        ip daddr 127.0.0.0/8 return
        ip daddr 192.168.0.0/16 return
        ip daddr 10.0.0.0/8 return
        
        # Ridireziona tutto il TCP al TransPort
        tcp flags syn / syn,ack redirect to :$TRANS_PORT
    }
    
    chain output_filter {
        type filter hook output priority 0; policy drop;
        
        # Permetti traffico di Tor
        meta skuid $TOR_UID accept
        
        # Permetti traffico locale
        ip daddr 127.0.0.0/8 accept
        
        # Permetti DNS verso DNSPort
        udp dport $DNS_PORT ip daddr 127.0.0.1 accept
        
        # Tutto il resto: DROP (policy)
    }
}
```

### Tabella di conversione iptables → nftables

| iptables | nftables |
|----------|----------|
| `-t nat -A OUTPUT` | `chain output_nat { type nat hook output ... }` |
| `-m owner --uid-owner` | `meta skuid` |
| `-p tcp --syn` | `tcp flags syn / syn,ack` |
| `-j REDIRECT --to-ports` | `redirect to :PORT` |
| `-j RETURN` | `return` |
| `-j ACCEPT` | `accept` |
| `-j DROP` | `drop` (o policy drop) |
| `-d 127.0.0.0/8` | `ip daddr 127.0.0.0/8` |
| `iptables -F` | `flush ruleset` |

### Vantaggi di nftables

- **Sintassi unificata**: IPv4 e IPv6 in un singolo file (con `inet` family)
- **Performance**: single-pass evaluation, meno overhead
- **Atomicità**: tutto il ruleset viene caricato atomicamente
- **Set e map**: strutture dati per regole complesse

### Rollback nftables

```bash
# Rimuovere tutte le regole
nft flush ruleset

# Verificare che sia vuoto
nft list ruleset
```

---

## IPv6 e transparent proxy

### Il problema IPv6

IPv6 è gestito separatamente dal kernel Linux:
- `iptables` → solo IPv4
- `ip6tables` → solo IPv6
- `nftables` con family `inet` → entrambi

Se configuri solo iptables per il transparent proxy, il traffico IPv6 esce
direttamente → **leak completo**.

### Blocco completo IPv6

```bash
# Metodo 1: sysctl (disabilita IPv6 a livello kernel)
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# Persistente in /etc/sysctl.d/99-disable-ipv6.conf:
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Metodo 2: ip6tables DROP all (se non puoi disabilitare IPv6)
ip6tables -A OUTPUT -j DROP
ip6tables -A INPUT -j DROP
ip6tables -A FORWARD -j DROP
```

### nftables con IPv6

Con nftables family `inet`, puoi gestire entrambi:

```nft
table inet tor_proxy {
    chain output_filter {
        type filter hook output priority 0; policy drop;
        
        # Permetti traffico Tor (solo IPv4)
        meta skuid debian-tor accept
        
        # Permetti localhost IPv4
        ip daddr 127.0.0.0/8 accept
        
        # Blocca TUTTO IPv6 (policy drop lo fa automaticamente)
        # Non serve regola esplicita: senza accept per IPv6, viene droppato
    }
}
```

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
# tor-transparent-proxy.sh — Script production-ready per transparent proxy Tor
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
