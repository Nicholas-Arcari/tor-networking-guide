# Isolamento Avanzato - Qubes, Namespaces, Docker e Confronto

Soluzioni avanzate di isolamento per Tor: Qubes OS con compartimentazione
multi-identità, network namespaces Linux, Docker, transparent proxy con iptables,
e confronto per threat model.

> **Estratto da**: [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md)
> per Whonix, Tails e la matrice comparativa.

---

## Qubes OS - Compartimentazione estrema

### Architettura

Qubes OS usa la virtualizzazione Xen per compartimentare il sistema in "qubes"
(VM leggere) completamente isolate:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Qubes OS (Xen hypervisor)                 │
│                                                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐│
│  │  Personal │  │   Work   │  │  Vault   │  │  Disposable VM   ││
│  │  (green)  │  │  (blue)  │  │  (black) │  │  (red)           ││
│  │           │  │          │  │          │  │                  ││
│  │ Browser   │  │ Browser  │  │ KeePass  │  │ File sospetti   ││
│  │ Email     │  │ IDE      │  │ GPG keys │  │ Link non fidati ││
│  │ Social    │  │ Git      │  │ No rete  │  │ Autodistruzione ││
│  └─────┬─────┘  └────┬─────┘  └──────────┘  └────────┬─────────┘│
│        │              │                               │          │
│  ┌─────▼──────────────▼───────────────────────────────▼────────┐│
│  │                    sys-firewall                              ││
│  │            (regole firewall per ogni qube)                   ││
│  └─────────────────────────┬───────────────────────────────────┘│
│                            │                                     │
│  ┌─────────────────────────▼───────────────────────────────────┐│
│  │                      sys-net                                 ││
│  │              (driver di rete, WiFi, eth)                     ││
│  └─────────────────────────┬───────────────────────────────────┘│
└────────────────────────────┼─────────────────────────────────────┘
                             │
                         Internet


Per traffico Tor, aggiungi sys-whonix:
  [Qube Tor] → [sys-whonix (Whonix Gateway)] → [sys-firewall] → [sys-net]
  [Qube Personal] → [sys-firewall] → [sys-net]  (rete normale)
```

### Compartimentazione per identità

```
Scenario reale con Qubes:

Qube "personal":
  - Email personale, social, banking
  - Rete normale via sys-firewall

Qube "work":
  - Email lavoro, IDE, repository
  - Rete normale o VPN via sys-firewall

Qube "anon-browsing":
  - Tor Browser, navigazione anonima
  - Rete via sys-whonix (forzata via Tor)

Qube "anon-comm":
  - Comunicazione anonima (email, chat)
  - Rete via sys-whonix

Qube "vault":
  - Password, chiavi GPG, documenti sensibili
  - NESSUNA rete (completamente isolato)

Qube "untrusted":
  - Aprire file scaricati, link sospetti
  - Disposable: autodistruzione alla chiusura

Ogni qube è una VM Xen completamente isolata:
  - Se "untrusted" viene compromesso → gli altri qube sono intatti
  - Se "anon-browsing" è compromesso → non può accedere a "personal"
  - "vault" non ha rete → impossibile esfiltrare dati
```

### Requisiti hardware

```
Minimi:
  - CPU: 64-bit Intel/AMD con VT-x/AMD-V e VT-d/AMD-Vi (IOMMU)
  - RAM: 16 GB (minimo pratico per 4-5 qube)
  - Disco: 256 GB SSD (ogni qube occupa spazio)
  - GPU: Intel integrata (NVIDIA/AMD hanno problemi)

Raccomandati:
  - RAM: 32 GB (per 8+ qube contemporanei)
  - Disco: 512 GB SSD NVMe
  - TPM 2.0 per anti-evil-maid

Hardware certificato:
  - Purism Librem 14/15 (hardware open)
  - Lenovo ThinkPad T480/X1 Carbon (ben supportati)
  - Dell Latitude (vari modelli)
  - Vedi: https://www.qubes-os.org/hcl/
```

### Quando usare Qubes

```
✓ Hai bisogno di compartimentazione multi-identità
✓ Vuoi separare completamente lavoro, personale, anonimo
✓ Hai risorse hardware sufficienti (16+ GB RAM)
✓ Vuoi protezione anche da exploit del kernel
✓ Sei disposto a investire tempo nella curva di apprendimento

✗ Hai meno di 16 GB di RAM
✗ La tua CPU non supporta VT-d/IOMMU
✗ Hai bisogno di gaming o GPU passthrough
✗ Vuoi un sistema semplice da usare
```

---

## Network Namespaces Linux

### Architettura

I network namespaces di Linux permettono di creare ambienti di rete isolati
senza virtualizzazione. Sono un meccanismo del kernel nativo:

```
┌─────────────────────────────────────────────┐
│                  Host Linux                  │
│                                              │
│  Namespace "default" (host)                  │
│  ┌────────────────────────────────────────┐  │
│  │ eth0: 192.168.1.100 (rete reale)      │  │
│  │ veth0: 10.200.1.1 (ponte al namespace)│  │
│  │ Tor daemon (SocksPort 9050)           │  │
│  └───────────────┬────────────────────────┘  │
│                  │ veth pair                  │
│  Namespace "tor_ns" (isolato)                │
│  ┌───────────────┴────────────────────────┐  │
│  │ veth1: 10.200.1.2 (unica interfaccia) │  │
│  │ Default GW: 10.200.1.1                │  │
│  │                                        │  │
│  │ App → veth1 → veth0 → host            │  │
│  │       (tutto il traffico passa          │  │
│  │        dall'host, dove Tor lo cattura)  │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

### Setup completo passo-passo

```bash
#!/bin/bash
# tor-namespace-setup.sh - Crea un namespace di rete isolato per Tor

# 1. Creare il namespace
sudo ip netns add tor_ns

# 2. Creare una coppia di interfacce veth
sudo ip link add veth-host type veth peer name veth-tor

# 3. Spostare un'estremità nel namespace
sudo ip link set veth-tor netns tor_ns

# 4. Configurare le interfacce
# Lato host:
sudo ip addr add 10.200.1.1/24 dev veth-host
sudo ip link set veth-host up

# Lato namespace:
sudo ip netns exec tor_ns ip addr add 10.200.1.2/24 dev veth-tor
sudo ip netns exec tor_ns ip link set veth-tor up
sudo ip netns exec tor_ns ip link set lo up

# 5. Configurare il routing nel namespace
sudo ip netns exec tor_ns ip route add default via 10.200.1.1

# 6. Abilitare IP forwarding sull'host
sudo sysctl -w net.ipv4.ip_forward=1

# 7. Configurare iptables sull'host per forzare via Tor
# Tutto il traffico dal namespace → TransPort di Tor
sudo iptables -t nat -A PREROUTING -s 10.200.1.0/24 -p tcp \
    -j REDIRECT --to-ports 9040
sudo iptables -t nat -A PREROUTING -s 10.200.1.0/24 -p udp --dport 53 \
    -j REDIRECT --to-ports 5353

# Blocca tutto il traffico diretto dal namespace
sudo iptables -A FORWARD -s 10.200.1.0/24 -j DROP

# 8. Configurare DNS nel namespace
sudo mkdir -p /etc/netns/tor_ns
echo "nameserver 10.200.1.1" | sudo tee /etc/netns/tor_ns/resolv.conf

# 9. Test: eseguire comandi nel namespace
sudo ip netns exec tor_ns curl --max-time 30 https://check.torproject.org/api/ip
# Dovrebbe mostrare {"IsTor":true,...}

# 10. Per eseguire un browser nel namespace:
sudo ip netns exec tor_ns sudo -u $USER firefox -no-remote -P tor-ns
```

### Script di cleanup

```bash
#!/bin/bash
# tor-namespace-cleanup.sh - Rimuove il namespace Tor

sudo ip netns exec tor_ns ip link set veth-tor down 2>/dev/null
sudo ip link set veth-host down 2>/dev/null
sudo ip link del veth-host 2>/dev/null
sudo ip netns del tor_ns 2>/dev/null

# Rimuovi regole iptables
sudo iptables -t nat -D PREROUTING -s 10.200.1.0/24 -p tcp \
    -j REDIRECT --to-ports 9040 2>/dev/null
sudo iptables -t nat -D PREROUTING -s 10.200.1.0/24 -p udp --dport 53 \
    -j REDIRECT --to-ports 5353 2>/dev/null
sudo iptables -D FORWARD -s 10.200.1.0/24 -j DROP 2>/dev/null

echo "Namespace tor_ns rimosso"
```

### Vantaggi e limiti

```
Vantaggi:
  + Nessuna virtualizzazione necessaria (zero overhead)
  + Nativo Linux (kernel feature)
  + Isolamento di rete completo
  + Combinabile con cgroups per limitare risorse
  + Leggero: creazione/distruzione in millisecondi

Limiti:
  - Configurazione manuale complessa
  - Se le regole iptables sono sbagliate → leak possibile
  - Non amnesico (disco e RAM dell'host sono accessibili)
  - Non protegge da exploit del kernel (condivide il kernel)
  - Richiede root per la configurazione
  - Non isola il filesystem (il namespace vede i file dell'host)
```

---

## Docker e containerizzazione

### Tor in Docker

```dockerfile
# Dockerfile per un container Tor isolato
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tor \
    proxychains4 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY torrc /etc/tor/torrc
COPY proxychains4.conf /etc/proxychains4.conf

# Tor gira come utente debian-tor
USER debian-tor
EXPOSE 9050

CMD ["tor", "-f", "/etc/tor/torrc"]
```

### Docker Compose con browser

```yaml
# docker-compose.yml
version: '3.8'

services:
  tor:
    build: .
    container_name: tor-proxy
    networks:
      - tor-net
    ports:
      - "127.0.0.1:9050:9050"  # SocksPort (solo localhost)
    restart: unless-stopped

  browser:
    image: jlesage/firefox:latest
    container_name: tor-browser
    networks:
      - tor-net
    environment:
      - http_proxy=socks5h://tor:9050
      - https_proxy=socks5h://tor:9050
    ports:
      - "127.0.0.1:5800:5800"  # Web UI
    depends_on:
      - tor
    # Nessun accesso diretto a Internet
    # Solo via la rete tor-net → tor container

networks:
  tor-net:
    driver: bridge
    internal: true  # NESSUN accesso a Internet diretto
    # I container possono comunicare tra loro
    # ma NON possono raggiungere Internet direttamente
```

### Limiti di Docker per l'anonimato

```
Docker NON è progettato per la sicurezza:
  - Il daemon Docker gira come root
  - Container escapes sono possibili (CVE multiple)
  - Le network policy di Docker non sono pensate per l'anonimato
  - I log Docker possono contenere informazioni sensibili
  - L'isolamento non è a livello hypervisor (condivide il kernel)

Docker è utile per:
  ✓ Ambienti riproducibili e portabili
  ✓ Isolamento leggero per test
  ✓ CI/CD con Tor
  ✓ Separazione delle applicazioni

Docker NON è sufficiente per:
  ✗ Anonimato ad alto rischio
  ✗ Protezione da exploit del kernel
  ✗ Protezione da avversari sofisticati
```

---

## Transparent proxy con iptables

### Setup rapido per uso system-wide

```bash
#!/bin/bash
# transparent-tor.sh - Forza tutto il traffico TCP via Tor

TOR_USER="debian-tor"
TRANS_PORT=9040
DNS_PORT=5353

# Permetti traffico di Tor
sudo iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_USER -j RETURN

# DNS via Tor
sudo iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $DNS_PORT

# TCP via TransPort
sudo iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TRANS_PORT

# Blocca traffico diretto (non-Tor)
sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m owner --uid-owner $TOR_USER -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A OUTPUT -j DROP

echo "Transparent proxy attivo. Tutto il TCP passa da Tor."
echo "ATTENZIONE: UDP bloccato (niente NTP, QUIC, VoIP)"
```

### Vantaggi e limiti

```
Vantaggi:
  + Tutto il traffico TCP passa da Tor senza configurazione app
  + DNS forzato via Tor (no leak possibile)
  + Leak prevention a livello firewall

Limiti:
  - UDP completamente bloccato (NTP, DNS diretto, QUIC, VoIP)
  - Se Tor si blocca → tutta la rete è bloccata
  - Fragile: un errore nelle regole → leak
  - Performance degradate (tutto il traffico su 3 hop)
  - Non isola le applicazioni tra loro
```

Per una guida completa, vedi `docs/06-configurazioni-avanzate/transparent-proxy.md`.

---

## Confronto per threat model

### Avversario: Tracker web (Google, Facebook)

```
Protezione necessaria: nascondere IP, prevenire fingerprinting
Soluzione minima: Tor Browser
Soluzione raccomandata: Tor Browser
Note: l'isolamento di sistema non è necessario per questo threat model
```

### Avversario: ISP

```
Protezione necessaria: nascondere destinazioni e uso di Tor
Soluzione minima: Tor + bridge obfs4
Soluzione raccomandata: Tor + bridge obfs4 + proxy_dns
Note: il mio caso d'uso. proxychains è sufficiente.
```

### Avversario: rete locale ostile (WiFi pubblica, hotel)

```
Protezione necessaria: nascondere tutto il traffico, MAC spoofing
Soluzione minima: VPN + Tor Browser
Soluzione raccomandata: Tails (MAC randomizzato + tutto via Tor)
Note: Tails è ideale per reti non fidate
```

### Avversario: forze dell'ordine nazionali

```
Protezione necessaria: anonimato completo, amnesia, OPSEC rigoroso
Soluzione minima: Whonix
Soluzione raccomandata: Tails (amnesico) o Qubes+Whonix
Note: OPSEC umano è più importante della tecnologia
```

### Avversario: intelligence (NSA, GCHQ)

```
Protezione necessaria: tutto quanto sopra + difesa da correlazione globale
Soluzione minima: Qubes + Whonix + OPSEC perfetto
Soluzione raccomandata: Qubes + Whonix + Tails per sessioni specifiche
Note: contro un avversario globale, nessuna soluzione è garantita
```

| Scenario | Soluzione consigliata |
|----------|---------------------|
| Studio e test (il mio caso) | Tor + proxychains |
| Privacy dall'ISP | Tor + proxychains + bridge obfs4 |
| Navigazione anonima seria | Tor Browser |
| Alto rischio (giornalismo, attivismo) | Tails o Whonix |
| Compartimentazione multi-identità | Qubes OS + Whonix |
| Protezione system-wide leggera | iptables transparent proxy |
| Ambienti di test riproducibili | Docker + Tor |
| Rete locale non fidata | Tails (USB live) |

---

## La mia posizione

Per il mio caso d'uso (studio, test, privacy dall'ISP), il setup attuale
(Tor daemon + proxychains su Kali) è sufficiente. Le soluzioni di isolamento
sono per scenari dove l'anonimato è critico.

La scelta dipende dal modello di minaccia. Non esiste una soluzione "migliore"
in assoluto - esiste la soluzione adatta al rischio specifico.

Se dovessi scalare il mio setup per un rischio maggiore, la progressione sarebbe:
1. **Attuale**: proxychains + bridge obfs4 (privacy dall'ISP)
2. **Intermedio**: transparent proxy con iptables (leak prevention)
3. **Alto**: Whonix su KVM (isolamento completo)
4. **Critico**: Tails da USB (amnesia + isolamento)
5. **Massimo**: Qubes + Whonix (compartimentazione + isolamento)

---

## Vedi anche

- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - Setup completo iptables/nftables
- [Hardening di Sistema](hardening-sistema.md) - sysctl, AppArmor, nftables
- [DNS Leak](dns-leak.md) - Prevenzione DNS leak a tutti i livelli
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - L'isolamento non sostituisce l'OPSEC
- [Analisi Forense e Artefatti](analisi-forense-e-artefatti.md) - Cosa lascia tracce su disco e RAM
- [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Isolamento dei circuiti
