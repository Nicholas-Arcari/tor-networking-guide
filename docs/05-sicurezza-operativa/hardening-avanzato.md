> **Lingua / Language**: Italiano | [English](../en/05-sicurezza-operativa/hardening-avanzato.md)

# Hardening Avanzato - Servizi, Rete, Filesystem e Firefox

Servizi da disabilitare (Avahi, CUPS, Bluetooth), MAC/hostname randomization,
filesystem privacy (tmpfs, secure delete, swap), logging/audit, hardening
Firefox profilo tor-proxy, e checklist completa.

> **Estratto da**: [Hardening di Sistema](hardening-sistema.md) per kernel
> sysctl, firewall nftables/iptables e AppArmor.

---

## Servizi da disabilitare

### Servizi che comunicano in chiaro e rivelano informazioni

```bash
# Avahi (mDNS/DNS-SD) - broadcast sulla LAN
sudo systemctl stop avahi-daemon
sudo systemctl disable avahi-daemon
sudo systemctl mask avahi-daemon
# Avahi annuncia servizi locali sulla rete → fingerprint macchina

# CUPS browsing - scoperta stampanti via broadcast
sudo systemctl stop cups-browsed
sudo systemctl disable cups-browsed
# Invia broadcast per scoprire stampanti → rivela la tua presenza sulla LAN

# Bluetooth - potenziale vettore di leak e tracking
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
# /etc/fstab - montare /tmp in RAM
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
# torrc - minimizzare logging
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

Sul mio Kali non applico tutto l'hardening descritto - sarebbe eccessivo per
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
progressivamente. Ogni misura aggiuntiva ha un costo in usabilità - trovare il
proprio equilibrio è parte del processo.

---

## Vedi anche

- [DNS Leak](dns-leak.md) - Prevenzione DNS leak con firewall
- [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) - Whonix, Tails, network namespaces
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - iptables/nftables per Tor system-wide
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - Hardening come parte dell'OPSEC
- [Analisi Forense e Artefatti](analisi-forense-e-artefatti.md) - Ridurre artefatti con hardening
