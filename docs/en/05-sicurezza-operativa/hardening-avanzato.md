> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/hardening-avanzato.md) | English

# Advanced Hardening - Services, Network, Filesystem and Firefox

Services to disable (Avahi, CUPS, Bluetooth), MAC/hostname randomization,
filesystem privacy (tmpfs, secure delete, swap), logging/audit, Firefox
tor-proxy profile hardening, and complete checklist.

> **Extracted from**: [System Hardening](hardening-sistema.md) for kernel
> sysctl, nftables/iptables firewall and AppArmor.

---

## Services to disable

### Services that communicate in cleartext and reveal information

```bash
# Avahi (mDNS/DNS-SD) - broadcasts on LAN
sudo systemctl stop avahi-daemon
sudo systemctl disable avahi-daemon
sudo systemctl mask avahi-daemon
# Avahi announces local services on the network → machine fingerprint

# CUPS browsing - printer discovery via broadcast
sudo systemctl stop cups-browsed
sudo systemctl disable cups-browsed
# Sends broadcasts to discover printers → reveals your presence on the LAN

# Bluetooth - potential leak and tracking vector
sudo systemctl stop bluetooth
sudo systemctl disable bluetooth
# The Bluetooth MAC is a persistent identifier

# NetworkManager connectivity check
# Makes periodic HTTP requests to verify connectivity
# /etc/NetworkManager/NetworkManager.conf
# [connectivity]
# enabled=false
```

### Verify listening services

```bash
# All listening services
ss -tlnp
ss -ulnp

# Services that should not be active for Tor usage:
# - :53 (local DNS resolver that is not Tor)
# - :631 (CUPS web interface)
# - :5353 (Avahi mDNS) [NB: different from Tor DNSPort if using 5353]
# - :3389 (xrdp)
```

---

## Network hardening

### MAC address randomization

The MAC address is a persistent identifier for your network interface:

```bash
# Check current MAC
ip link show eth0 | grep ether

# Randomize (temporary, until reboot)
sudo ip link set eth0 down
sudo macchanger -r eth0
sudo ip link set eth0 up

# Randomize automatically via NetworkManager
# /etc/NetworkManager/conf.d/99-random-mac.conf
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
```

### Disable unnecessary protocols

```bash
# Disable LLDP (Link Layer Discovery Protocol)
sudo systemctl stop lldpd 2>/dev/null
sudo systemctl disable lldpd 2>/dev/null

# Disable SNMP
sudo systemctl stop snmpd 2>/dev/null
sudo systemctl disable snmpd 2>/dev/null
```

### Hostname randomization

The hostname is sent in DHCP requests:

```bash
# Check current hostname
hostname

# Random hostname for DHCP
# /etc/NetworkManager/conf.d/99-random-hostname.conf
[connection]
# Do not send real hostname in DHCP
ipv4.dhcp-send-hostname=false
ipv6.dhcp-send-hostname=false
```

---

## Filesystem and privacy

### Disable core dumps

```bash
# /etc/security/limits.conf
* hard core 0
* soft core 0

# /etc/sysctl.d/99-no-coredump.conf
kernel.core_pattern=|/bin/false
fs.suid_dumpable=0
```

### tmpfs for sensitive directories

```bash
# /etc/fstab - mount /tmp in RAM
tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,mode=1777,size=2G 0 0

# Effect: temporary files never touch the disk
# On reboot: /tmp is automatically cleared
```

### Secure delete

```bash
# Install secure-delete
sudo apt install secure-delete

# Securely delete files
srm -vz sensitive_file.txt

# Wipe free space
sfill -v /tmp/
```

### Disable swap (or encrypt it)

Swap can contain sensitive data paged out from RAM:

```bash
# Disable swap
sudo swapoff -a
# Remove the swap line from /etc/fstab

# Or: encrypt swap
# /etc/crypttab:
# swap /dev/sdXN /dev/urandom swap,cipher=aes-xts-plain64,size=256
```

---

## Logging and audit

### Minimize system logs

Logs can reveal activity:

```bash
# Reduce log retention
# /etc/systemd/journald.conf
[Journal]
MaxRetentionSec=1week
MaxFileSec=1day
Compress=yes
```

### Tor-specific logs

```ini
# torrc - minimize logging
Log notice file /var/log/tor/notices.log
# Do NOT use debug/info in production → too many circuit details
```

### Audit ControlPort access

```bash
# Monitor who accesses the ControlPort
sudo auditctl -a always,exit -F arch=b64 -S connect -F a2=9051 -k tor_control
# Logs every connection to port 9051
```

---

## Firefox tor-proxy profile hardening

### Essential about:config

```
# Remote DNS via SOCKS
network.proxy.socks_remote_dns = true

# Disable DNS prefetch
network.dns.disablePrefetch = true
network.prefetch-next = false

# Disable speculative connections
network.http.speculative-parallel-limit = 0

# Disable WebRTC (IP leak)
media.peerconnection.enabled = false
media.peerconnection.ice.default_address_only = true

# Disable IPv6
network.dns.disableIPv6 = true

# Disable geolocation
geo.enabled = false
geo.wifi.uri = ""

# Disable telemetry
toolkit.telemetry.enabled = false
datareporting.healthreport.uploadEnabled = false

# Disable safe browsing (contacts Google)
browser.safebrowsing.enabled = false
browser.safebrowsing.malware.enabled = false

# Disable beacon
beacon.enabled = false

# Resist fingerprinting
privacy.resistFingerprinting = true

# First-party isolation
privacy.firstparty.isolate = true

# Disable offline cache
browser.cache.offline.enable = false

# Disable battery API (fingerprinting)
dom.battery.enabled = false
```

### Recommended extensions

| Extension | Purpose |
|-----------|---------|
| uBlock Origin | Blocks trackers and ads |
| NoScript | Selectively blocks JavaScript |
| HTTPS Everywhere | Forces HTTPS (less necessary with HTTPS-Only mode) |

**Do not install too many extensions**: each extension changes the browser's fingerprint.
Tor Browser does not allow extra extensions for this reason.

---

## Complete hardening checklist

### Before using Tor

- [ ] IPv6 disabled (sysctl + ip6tables)
- [ ] Restrictive firewall active (only Tor can go out)
- [ ] DNS leak prevention (iptables port 53)
- [ ] Avahi/mDNS disabled
- [ ] CUPS browsing disabled
- [ ] Bluetooth disabled
- [ ] Core dump disabled
- [ ] MAC randomized (if on WiFi)
- [ ] Hostname not sent in DHCP
- [ ] Connectivity check disabled
- [ ] Firefox tor-proxy profile configured (about:config)
- [ ] WebRTC disabled

### Periodic verification

- [ ] `tcpdump -i eth0 'not port 9001 and not port 443'` → no non-Tor traffic
- [ ] `ss -tlnp` → only necessary ports listening
- [ ] `ip -6 addr` → no IPv6 addresses
- [ ] `curl https://check.torproject.org/api/ip` → `IsTor: true`

---

## In my experience

On my Kali I do not apply all the hardening described - it would be excessive for
my daily use. The measures I always have active:

1. **IPv6 disabled** via sysctl: I did this after discovering with tcpdump
   that my system was making cleartext AAAA DNS queries despite proxychains.

2. **Hardened Firefox tor-proxy profile**: all the about:config settings
   listed above. I configured them after reading the Tor Browser documentation
   on anti-fingerprinting protections.

3. **WebRTC disabled**: discovered that Firefox with active WebRTC leaks the local
   IP even with a SOCKS5 proxy.

4. **Avahi disabled**: I do not use service discovery on the LAN and prefer not to
   broadcast my presence.

For high-security sessions (OSINT, sensitive research), I add the temporary
restrictive firewall. I activate it beforehand, verify with tcpdump that
everything goes through Tor, do the work, then remove it.

The advice: start with the basics (IPv6, DNS, WebRTC) and progressively add
hardening. Each additional measure has a usability cost - finding your own
balance is part of the process.

---

## See also

- [DNS Leak](dns-leak.md) - DNS leak prevention with firewall
- [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) - Whonix, Tails, network namespaces
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - iptables/nftables for system-wide Tor
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Hardening as part of OPSEC
- [Forensic Analysis and Artifacts](analisi-forense-e-artefatti.md) - Reducing artifacts with hardening
