# Hardening di Sistema per l'Uso di Tor

Questo documento copre le misure di hardening a livello di sistema operativo per
massimizzare la sicurezza quando si usa Tor. Include configurazione kernel, firewall,
profili AppArmor, servizi da disabilitare, e prevenzione leak a livello OS.

> **Vedi anche**: [DNS Leak](./dns-leak.md) per la prevenzione DNS,
> [Isolamento e Compartimentazione](./isolamento-e-compartimentazione.md) per VM/container,
> [OPSEC e Errori Comuni](./opsec-e-errori-comuni.md) per errori operativi,
> [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) per iptables.

---

## Indice

- [Panoramica del threat model](#panoramica-del-threat-model)
- [Kernel hardening — sysctl](#kernel-hardening--sysctl)
- [Firewall — nftables/iptables](#firewall--nftablesiptables)
- [Disabilitare IPv6](#disabilitare-ipv6)
- [AppArmor per Tor](#apparmor-per-tor)
- [Servizi da disabilitare](#servizi-da-disabilitare)
- [Hardening rete](#hardening-rete)
- [File system e privacy](#file-system-e-privacy)
- [Logging e audit](#logging-e-audit)
- [Hardening Firefox profilo tor-proxy](#hardening-firefox-profilo-tor-proxy)
- [Checklist hardening completa](#checklist-hardening-completa)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Panoramica del threat model

L'hardening di sistema protegge da:

| Minaccia | Senza hardening | Con hardening |
|----------|----------------|---------------|
| DNS leak via UDP | Possibile | Bloccato (iptables) |
| IPv6 leak | Possibile | Bloccato (sysctl + iptables) |
| Servizi che comunicano in chiaro | Attivi di default | Disabilitati |
| Kernel info leak | Esposto | Ridotto (sysctl) |
| Traffic correlation via timing | Possibile | Ridotto (disabilita NTP leak) |
| Crash dump con dati sensibili | Attivo | Disabilitato |
| File temporanei su disco | Persistenti | tmpfs / shred |

---

## Kernel hardening — sysctl

### Parametri di rete

```bash
# /etc/sysctl.d/99-tor-hardening.conf

# --- IPv6: disabilitare completamente ---
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# --- Prevenire leak di informazioni di rete ---
# Disabilitare ICMP redirect (potrebbe bypassare routing Tor)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Disabilitare source routing (attacco per bypassare routing)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Attivare reverse path filtering (anti-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignorare broadcast ICMP (prevenzione smurf attack)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignorare ICMP bogus error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disabilitare IP forwarding (a meno che non sia gateway Tor)
net.ipv4.ip_forward = 0

# Log pacchetti marziani (impossibili)
net.ipv4.conf.all.log_martians = 1
```

### Parametri kernel generici

```bash
# --- Protezione kernel ---
# Nascondere puntatori kernel nei log
kernel.kptr_restrict = 2

# Restringere accesso a dmesg
kernel.dmesg_restrict = 1

# Disabilitare SysRq (prevenire dump)
kernel.sysrq = 0

# Restringere ptrace (prevenire attach ai processi)
kernel.yama.ptrace_scope = 2

# ASLR massimo
kernel.randomize_va_space = 2

# Disabilitare core dump (potrebbero contenere dati sensibili)
fs.suid_dumpable = 0
```

### Applicare

```bash
# Applicare immediatamente
sudo sysctl --system

# Verificare
sysctl net.ipv6.conf.all.disable_ipv6
# net.ipv6.conf.all.disable_ipv6 = 1
```

---

## Firewall — nftables/iptables

### Strategia: deny-all, allow-Tor

L'obiettivo è bloccare TUTTO il traffico che non passa da Tor:

```bash
#!/bin/bash
# tor-firewall.sh — Firewall restrittivo per uso Tor

TOR_UID=$(id -u debian-tor)

# === OUTPUT: cosa può uscire ===

# Flush
iptables -F OUTPUT

# Permetti traffico di Tor (il daemon stesso)
iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT

# Permetti localhost (ControlPort, SocksPort, DNSPort)
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT

# Permetti LAN (opzionale, per DHCP, stampanti, NAS)
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# Blocca TUTTO il resto
iptables -A OUTPUT -j LOG --log-prefix "[TOR-FW-DROP] " --log-level 4
iptables -A OUTPUT -j DROP

# === IPv6: blocca tutto ===
ip6tables -F OUTPUT
ip6tables -A OUTPUT -j DROP

echo "Firewall Tor attivo. Solo traffico via Tor permesso."
```

### Differenza con il transparent proxy

```
Transparent proxy:
  → Tutto il traffico TCP viene RIDIREZIONATO a Tor (TransPort)
  → Le app non sanno di usare Tor
  → UDP bloccato

Firewall restrittivo:
  → Il traffico diretto viene BLOCCATO
  → Le app devono essere configurate per usare SocksPort
  → Se un'app non usa il proxy → connessione bloccata → NO leak
  → Approccio più conservativo
```

Il firewall restrittivo è un **complemento** a proxychains/torsocks, non un
sostituto. Cattura tutto ciò che sfugge al wrapper LD_PRELOAD.

### Regole per scenari specifici

```bash
# Permettere NTP (accettare il leak di timing per avere orologio corretto)
iptables -I OUTPUT -p udp --dport 123 -j ACCEPT

# Permettere apt update senza Tor (molto più veloce)
APT_UID=$(id -u _apt)
iptables -I OUTPUT -m owner --uid-owner $APT_UID -j ACCEPT

# Permettere un utente specifico di bypassare il firewall
iptables -I OUTPUT -m owner --uid-owner 1001 -j ACCEPT
```

---

## Disabilitare IPv6

IPv6 è un vettore di leak critico perché:
- Tor ha supporto IPv6 limitato (client-side)
- iptables non copre IPv6 (serve ip6tables separato)
- Molte applicazioni preferiscono IPv6 quando disponibile

### Metodo completo

```bash
# 1. sysctl (già visto sopra)
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1

# 2. ip6tables (blocco a livello firewall)
sudo ip6tables -P INPUT DROP
sudo ip6tables -P OUTPUT DROP
sudo ip6tables -P FORWARD DROP

# 3. GRUB (disabilita a livello kernel boot)
# /etc/default/grub:
# GRUB_CMDLINE_LINUX="ipv6.disable=1"
# sudo update-grub

# 4. Verificare
ip -6 addr show
# Nessun output = IPv6 disabilitato

cat /proc/sys/net/ipv6/conf/all/disable_ipv6
# 1
```

---

## AppArmor per Tor

### Profilo AppArmor per Tor daemon

Kali/Debian include un profilo AppArmor per Tor. Verificare:

```bash
# Stato AppArmor
sudo aa-status | grep tor
# /usr/bin/tor (enforce)

# Se non attivo:
sudo aa-enforce /etc/apparmor.d/system_tor
```

### Cosa limita il profilo

Il profilo AppArmor per Tor:
- Limita l'accesso filesystem: solo `/var/lib/tor/`, `/var/log/tor/`, config
- Impedisce l'accesso a home directory, `/tmp`, e altri percorsi
- Limita le capability di rete
- Impedisce l'accesso ad altri processi

### Profilo personalizzato più restrittivo

```
# /etc/apparmor.d/local/system_tor
# Override locale per restrizioni aggiuntive

# Negare accesso a device
deny /dev/** rw,

# Negare accesso a proc (tranne necessario)
deny /proc/*/maps r,
deny /proc/*/status r,

# Permettere solo le porte necessarie
network tcp,
# Implicitamente nega raw socket, UDP (tranne DNS interno)
```

---

## Servizi da disabilitare

### Servizi che comunicano in chiaro e rivelano informazioni

```bash
# Avahi (mDNS/DNS-SD) — broadcast sulla LAN
sudo systemctl stop avahi-daemon
sudo systemctl disable avahi-daemon
sudo systemctl mask avahi-daemon
# Avahi annuncia servizi locali sulla rete → fingerprint macchina

# CUPS browsing — scoperta stampanti via broadcast
sudo systemctl stop cups-browsed
sudo systemctl disable cups-browsed
# Invia broadcast per scoprire stampanti → rivela la tua presenza sulla LAN

# Bluetooth — potenziale vettore di leak e tracking
sudo systemctl stop bluetooth
sudo systemctl disable bluetooth
# Il MAC Bluetooth è un identificatore persistente

# NetworkManager connectivity check
# Fa richieste HTTP periodiche per verificare la connettività
# /etc/NetworkManager/NetworkManager.conf
# [connectivity]
# enabled=false
```

### Verificare servizi in ascolto

```bash
# Tutti i servizi in ascolto
ss -tlnp
ss -ulnp

# Servizi che non dovrebbero essere attivi per uso Tor:
# - :53 (DNS resolver locale che non sia Tor)
# - :631 (CUPS web interface)
# - :5353 (Avahi mDNS) [NB: diverso dal DNSPort Tor se usa 5353]
# - :3389 (xrdp)
```

---

## Hardening rete

### MAC address randomization

Il MAC address è un identificatore persistente per la tua interfaccia di rete:

```bash
# Verificare MAC attuale
ip link show eth0 | grep ether

# Randomizzare (temporaneo, fino a reboot)
sudo ip link set eth0 down
sudo macchanger -r eth0
sudo ip link set eth0 up

# Randomizzare automaticamente via NetworkManager
# /etc/NetworkManager/conf.d/99-random-mac.conf
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
```

### Disabilitare protocolli non necessari

```bash
# Disabilitare LLDP (Link Layer Discovery Protocol)
sudo systemctl stop lldpd 2>/dev/null
sudo systemctl disable lldpd 2>/dev/null

# Disabilitare SNMP
sudo systemctl stop snmpd 2>/dev/null
sudo systemctl disable snmpd 2>/dev/null
```

### Hostname randomization

L'hostname viene inviato in richieste DHCP:

```bash
# Verificare hostname attuale
hostname

# Hostname casuale per DHCP
# /etc/NetworkManager/conf.d/99-random-hostname.conf
[connection]
# Non inviare hostname reale nel DHCP
ipv4.dhcp-send-hostname=false
ipv6.dhcp-send-hostname=false
```

---

## File system e privacy

### Disabilitare core dump

```bash
# /etc/security/limits.conf
* hard core 0
* soft core 0

# /etc/sysctl.d/99-no-coredump.conf
kernel.core_pattern=|/bin/false
fs.suid_dumpable=0
```

### tmpfs per directory sensibili

```bash
# /etc/fstab — montare /tmp in RAM
tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,mode=1777,size=2G 0 0

# Effetto: i file temporanei non toccano mai il disco
# Al reboot: /tmp viene cancellato automaticamente
```

### Secure delete

```bash
# Installare secure-delete
sudo apt install secure-delete

# Cancellare file in modo sicuro
srm -vz file_sensibile.txt

# Pulire spazio libero
sfill -v /tmp/
```

### Disabilitare swap (o cifrarlo)

La swap può contenere dati sensibili scaricati dalla RAM:

```bash
# Disabilitare swap
sudo swapoff -a
# Rimuovere da /etc/fstab la riga swap

# Oppure: cifrare la swap
# /etc/crypttab:
# swap /dev/sdXN /dev/urandom swap,cipher=aes-xts-plain64,size=256
```

---

## Logging e audit

### Minimizzare i log di sistema

I log possono rivelare attività:

```bash
# Ridurre retention dei log
# /etc/systemd/journald.conf
[Journal]
MaxRetentionSec=1week
MaxFileSec=1day
Compress=yes
```

### Log specifici di Tor

```ini
# torrc — minimizzare logging
Log notice file /var/log/tor/notices.log
# NON usare debug/info in produzione → troppi dettagli sui circuiti
```

### Audit accessi al ControlPort

```bash
# Monitorare chi accede al ControlPort
sudo auditctl -a always,exit -F arch=b64 -S connect -F a2=9051 -k tor_control
# Logga ogni connessione alla porta 9051
```

---

## Hardening Firefox profilo tor-proxy

### about:config essenziale

```
# DNS remoto via SOCKS
network.proxy.socks_remote_dns = true

# Disabilitare prefetch DNS
network.dns.disablePrefetch = true
network.prefetch-next = false

# Disabilitare speculative connections
network.http.speculative-parallel-limit = 0

# Disabilitare WebRTC (leak IP)
media.peerconnection.enabled = false
media.peerconnection.ice.default_address_only = true

# Disabilitare IPv6
network.dns.disableIPv6 = true

# Disabilitare geolocation
geo.enabled = false
geo.wifi.uri = ""

# Disabilitare telemetry
toolkit.telemetry.enabled = false
datareporting.healthreport.uploadEnabled = false

# Disabilitare safe browsing (contatta Google)
browser.safebrowsing.enabled = false
browser.safebrowsing.malware.enabled = false

# Disabilitare beacon
beacon.enabled = false

# Resist fingerprinting
privacy.resistFingerprinting = true

# Isolamento first-party
privacy.firstparty.isolate = true

# Disabilitare offline cache
browser.cache.offline.enable = false

# Disabilitare battery API (fingerprinting)
dom.battery.enabled = false
```

### Estensioni consigliate

| Estensione | Scopo |
|-----------|-------|
| uBlock Origin | Blocca tracker e ads |
| NoScript | Blocca JavaScript selettivamente |
| HTTPS Everywhere | Forza HTTPS (meno necessario con HTTPS-Only mode) |

**Non installare troppe estensioni**: ogni estensione cambia il fingerprint del browser.
Tor Browser non permette estensioni extra per questo motivo.

---

## Checklist hardening completa

### Prima dell'uso di Tor

- [ ] IPv6 disabilitato (sysctl + ip6tables)
- [ ] Firewall restrittivo attivo (solo Tor può uscire)
- [ ] DNS leak prevention (iptables porta 53)
- [ ] Avahi/mDNS disabilitato
- [ ] CUPS browsing disabilitato
- [ ] Bluetooth disabilitato
- [ ] Core dump disabilitato
- [ ] MAC randomizzato (se su WiFi)
- [ ] Hostname non inviato in DHCP
- [ ] Connectivity check disabilitato
- [ ] Firefox profilo tor-proxy configurato (about:config)
- [ ] WebRTC disabilitato

### Verifica periodica

- [ ] `tcpdump -i eth0 'not port 9001 and not port 443'` → nessun traffico non-Tor
- [ ] `ss -tlnp` → solo porte necessarie in ascolto
- [ ] `ip -6 addr` → nessun indirizzo IPv6
- [ ] `curl https://check.torproject.org/api/ip` → `IsTor: true`

---

## Nella mia esperienza

Sul mio Kali non applico tutto l'hardening descritto — sarebbe eccessivo per
il mio uso quotidiano. Le misure che ho sempre attive:

1. **IPv6 disabilitato** via sysctl: l'ho fatto dopo aver scoperto con tcpdump
   che il mio sistema faceva query DNS AAAA in chiaro nonostante proxychains.

2. **Firefox profilo tor-proxy hardened**: tutte le impostazioni about:config
   sopra elencate. Le ho configurate dopo aver letto la documentazione di Tor
   Browser sulle protezioni anti-fingerprinting.

3. **WebRTC disabilitato**: scoperto che Firefox con WebRTC attivo leak-a l'IP
   locale anche con proxy SOCKS5.

4. **Avahi disabilitato**: non uso discovery servizi sulla LAN e preferisco non
   broadcast-are la mia presenza.

Per sessioni ad alta sicurezza (OSINT, ricerca sensibile), aggiungo il firewall
restrittivo temporaneo. Lo attivo prima, verifico con tcpdump che tutto passi
da Tor, eseguo il lavoro, poi lo rimuovo.

Il consiglio: partire dalle basi (IPv6, DNS, WebRTC) e aggiungere hardening
progressivamente. Ogni misura aggiuntiva ha un costo in usabilità — trovare il
proprio equilibrio è parte del processo.
