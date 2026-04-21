> **Lingua / Language**: [Italiano](../../06-configurazioni-avanzate/transparent-proxy-avanzato.md) | English

# Advanced Transparent Proxy - LAN, Troubleshooting and Production Script

Tor gateway for the LAN (PREROUTING), comprehensive troubleshooting (7 common problems),
transparent proxy hardening, production-ready script with checks and rollback,
comparison with Whonix/Tails, and limitations.

> **Extracted from**: [Transparent Proxy](transparent-proxy.md) for TransPort,
> iptables/nftables, IPv6, and the kernel mechanism.

---

## Transparent proxy for LAN traffic (PREROUTING)

### Scenario: Tor gateway for the LAN

Architecture: a Kali computer acts as a gateway for other devices, torifying
all their traffic:

```
[Laptop] --------+
                  |
[Phone] ---------+--->  [Kali Gateway] --->  [Tor] --->  Internet
                  |     eth0: 192.168.1.100
[IoT] -----------+     (ip_forward=1)
```

### PREROUTING rules

```bash
# Enable IP forwarding
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# NAT PREROUTING: capture traffic from the LAN
iptables -t nat -A PREROUTING -i eth0 -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -A PREROUTING -i eth0 -p tcp --syn -j REDIRECT --to-ports 9040

# FILTER FORWARD: block non-redirected traffic
iptables -A FORWARD -j DROP
```

### Torrc for gateway

```ini
# Accept connections from the LAN (not just localhost)
TransPort 0.0.0.0:9040
DNSPort 0.0.0.0:5353

# WARNING: this exposes TransPort and DNSPort on the network
# Use only on trusted and controlled networks
```

**Risk**: if the LAN is not trusted, anyone can use your Tor node
as a proxy. Restrict with iptables INPUT rules for specific IPs/subnets.

---

## Troubleshooting

### Problem 1: No network after activation

**Symptom**: after running the script, no connections work.

```bash
# Verify Tor is running
systemctl is-active tor@default.service

# Verify TransPort is listening
ss -tlnp | grep 9040
# If empty -> TransPort not configured in torrc

# Verify bootstrap
journalctl -u tor@default.service | grep "Bootstrapped"
# If not at 100% -> Tor is not yet connected
```

### Problem 2: DNS does not work

**Symptom**: web pages do not load, but `curl http://IP:port` works.

```bash
# Verify DNSPort
ss -ulnp | grep 5353
# If empty -> DNSPort not configured

# Direct DNS test
dig @127.0.0.1 -p 5353 example.com
# If timeout -> Tor is not resolving DNS

# Verify iptables rule
iptables -t nat -L OUTPUT -n -v | grep 53
# Should show the REDIRECT rule for port 53
```

### Problem 3: apt update extremely slow

**Cause**: all apt traffic goes through Tor (3 hops) -> slow.

```bash
# Temporary solution: exclude _apt from iptables
APT_UID=$(id -u _apt)
iptables -t nat -I OUTPUT -m owner --uid-owner $APT_UID -j RETURN
iptables -I OUTPUT -m owner --uid-owner $APT_UID -j ACCEPT

# After the update, remove the exception:
iptables -t nat -D OUTPUT -m owner --uid-owner $APT_UID -j RETURN
iptables -D OUTPUT -m owner --uid-owner $APT_UID -j ACCEPT
```

### Problem 4: NTP blocked, clock drifting

**Cause**: NTP uses UDP port 123 -> blocked.

```bash
# Check clock
timedatectl status

# Solution: sync manually via HTTP
torsocks curl -s http://worldtimeapi.org/api/ip | python3 -c "
import json, sys, subprocess
data = json.load(sys.stdin)
print(f'Setting time to: {data[\"datetime\"]}')"

# Or: allow NTP in iptables (acceptable leak for NTP)
iptables -I OUTPUT -p udp --dport 123 -j ACCEPT
# NOTE: NTP leak reveals timezone/locale, but not web traffic
```

### Problem 5: Local services unreachable

**Symptom**: cannot connect to localhost:5173 (Docker, dev server).

```bash
# Verify localhost is excluded from redirect
iptables -t nat -L OUTPUT -n | grep 127.0.0.0
# Should show RETURN for 127.0.0.0/8

# If missing, add:
iptables -t nat -I OUTPUT 3 -d 127.0.0.0/8 -j RETURN
```

### Problem 6: Emergency rollback

```bash
# If something goes wrong and you lose connectivity:
iptables -F
iptables -t nat -F
iptables -P OUTPUT ACCEPT
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT

# With nftables:
nft flush ruleset
```

### Problem 7: Verify rules are active

```bash
# iptables
iptables -t nat -L OUTPUT -n -v --line-numbers
iptables -L OUTPUT -n -v --line-numbers

# nftables
nft list ruleset

# Verify with real traffic
curl --max-time 10 https://check.torproject.org/api/ip
# {"IsTor":true,"IP":"..."}
```

---

## Transparent proxy hardening

### Block ICMP redirect

```bash
# Prevent ICMP redirects that could bypass the rules
sysctl -w net.ipv4.conf.all.accept_redirects=0
sysctl -w net.ipv4.conf.all.send_redirects=0
sysctl -w net.ipv4.conf.all.secure_redirects=0
```

### IP spoofing protection

```bash
# Enable reverse path filtering
sysctl -w net.ipv4.conf.all.rp_filter=1
```

### Logging dropped packets

```bash
# Add LOG rule before the final DROP
iptables -A OUTPUT -j LOG --log-prefix "[TOR-DROP] " --log-level 4
iptables -A OUTPUT -j DROP

# Monitor:
sudo journalctl -k | grep TOR-DROP
```

### Disable leaking services

```bash
# Disable Avahi (mDNS)
sudo systemctl stop avahi-daemon
sudo systemctl disable avahi-daemon

# Disable CUPS browsing (if not needed)
sudo systemctl stop cups-browsed

# Disable NetworkManager connectivity check
# /etc/NetworkManager/NetworkManager.conf
[connectivity]
enabled=false
```

---

## Production-ready script

```bash
#!/bin/bash
# tor-transparent-proxy.sh - Production-ready script for Tor transparent proxy
# Usage: sudo ./tor-transparent-proxy.sh {start|stop|status}

set -euo pipefail

LOCK_FILE="/var/run/tor-transparent-proxy.lock"
BACKUP_FILE="/tmp/iptables-backup-$(date +%s).rules"
TOR_UID=$(id -u debian-tor 2>/dev/null || echo "")
TRANS_PORT=9040
DNS_PORT=5353

log() { echo "[$(date '+%H:%M:%S')] $1"; }

check_prereqs() {
    if [ -z "$TOR_UID" ]; then
        log "ERROR: user debian-tor not found"
        exit 1
    fi
    
    if ! systemctl is-active --quiet tor@default.service; then
        log "ERROR: Tor is not running. Start it first: sudo systemctl start tor@default.service"
        exit 1
    fi
    
    if ! ss -tlnp | grep -q ":${TRANS_PORT} "; then
        log "ERROR: TransPort $TRANS_PORT not listening. Add 'TransPort $TRANS_PORT' to torrc"
        exit 1
    fi
    
    if ! ss -ulnp | grep -q ":${DNS_PORT} "; then
        log "ERROR: DNSPort $DNS_PORT not listening. Add 'DNSPort $DNS_PORT' to torrc"
        exit 1
    fi
    
    if ! journalctl -u tor@default.service --no-pager 2>/dev/null | grep -q "Bootstrapped 100%"; then
        log "WARNING: Bootstrap not at 100%. Connectivity may be limited."
    fi
}

start() {
    if [ -f "$LOCK_FILE" ]; then
        log "ERROR: transparent proxy already active (lock file: $LOCK_FILE)"
        exit 1
    fi
    
    check_prereqs
    
    # Backup current rules
    iptables-save > "$BACKUP_FILE"
    log "Rules backup saved to $BACKUP_FILE"
    
    log "Activating transparent proxy..."
    
    # Flush existing rules
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
    
    log "Transparent proxy ACTIVE."
    log "  WARNING: UDP (except DNS) is blocked"
    log "  WARNING: IPv6 is blocked"
    log "  To deactivate: sudo $0 stop"
    
    # Verification
    log "Verifying connection..."
    TOR_IP=$(curl -s --max-time 30 https://api.ipify.org 2>/dev/null)
    if [ -n "$TOR_IP" ]; then
        log "OK: connection via Tor working (exit: $TOR_IP)"
    else
        log "WARNING: connection verification failed. Check Tor logs."
    fi
}

stop() {
    log "Deactivating transparent proxy..."
    
    iptables -t nat -F OUTPUT
    iptables -F OUTPUT
    iptables -P OUTPUT ACCEPT
    ip6tables -F OUTPUT 2>/dev/null || true
    ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
    
    rm -f "$LOCK_FILE"
    
    log "Transparent proxy DEACTIVATED. Direct traffic restored."
}

status() {
    if [ -f "$LOCK_FILE" ]; then
        log "Transparent proxy: ACTIVE (since $(cat $LOCK_FILE))"
    else
        log "Transparent proxy: NOT ACTIVE"
    fi
    
    echo ""
    echo "=== NAT OUTPUT Rules ==="
    iptables -t nat -L OUTPUT -n -v --line-numbers 2>/dev/null
    echo ""
    echo "=== FILTER OUTPUT Rules ==="
    iptables -L OUTPUT -n -v --line-numbers 2>/dev/null
}

case "${1:-}" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    *)      echo "Usage: sudo $0 {start|stop|status}" ;;
esac
```

---

## Comparison with Whonix and Tails

### Whonix

Whonix implements the transparent proxy with a two-VM approach:

```
[Workstation VM] --only-->  [Gateway VM] --->  [Tor] --->  Internet
  - No direct network         - Transparent proxy
    access                     - TransPort + DNSPort
  - Everything goes through    - Filters ALL non-Tor traffic
    the gateway
```

Advantages over an iptables script:
- VM-level isolation (even if the kernel is compromised)
- The workstation can NEVER reach the network directly
- Does not depend on iptables rules (which can be bypassed with root)

### Tails

Tails uses a similar approach but on a live system:

- Boot from USB -> no persistence on disk
- iptables configured at boot (immutable)
- All traffic forced via Tor
- Failsafe: if Tor does not work, no connectivity

### Comparison

| Aspect | iptables Script | Whonix | Tails |
|--------|----------------|--------|-------|
| Isolation | iptables (user-space) | VM (hypervisor) | Live OS |
| Root bypass | Yes (root can flush) | No (separate VMs) | No (read-only) |
| Persistence | Configurable | Yes | No (RAM only) |
| Complexity | Low | Medium | Low (preconfigured) |
| Flexibility | High | Medium | Low |
| Security | Medium | High | High |

---

## Transparent proxy limitations

| Limitation | Description | Mitigation |
|-----------|-------------|------------|
| No UDP | Tor does not support UDP -> blocked | None |
| No ICMP | ping does not work | None |
| Performance | All traffic over 3 hops -> slow | Exclusions by UID |
| Single point of failure | If Tor crashes, no network | Monitoring + auto-restart |
| NTP blocked | Clock may drift | HTTP sync or NTP exception |
| Slow apt | Updates via Tor | Exception for _apt UID |
| No stream isolation | TransPort does not support isolation | Use SocksPort where possible |
| Root bypass | Root can remove rules | Whonix/Tails for protection |
| Hostname lost | TransPort receives IP only | DNSPort + AutomapHosts |

---

## In my experience

I do not use the transparent proxy daily on my Kali. I prefer selective routing
with per-application proxychains because:

- **Does not block UDP for normal activities**: NTP, DNS for non-Tor activities, and
  other UDP services continue to work
- **Does not slow down the entire system**: only explicitly torified applications
  go through Tor's 3 hops
- **More flexible**: I can choose what to anonymize and what not to

I use the transparent proxy in two specific scenarios:

1. **Temporary security testing**: when I need to ensure no traffic exits
   directly (e.g., during an OSINT test where a single leak would reveal
   my IP). I activate the script, run the tests, then deactivate it.

2. **Leak verification**: I activate the transparent proxy to verify that my
   per-application configurations have no hidden leaks. If everything works
   even with the transparent proxy active, it means the apps are configured
   correctly.

The production-ready script with pre-condition checks and lock file was developed
after a negative experience: I had activated the transparent proxy without verifying
that Tor had completed bootstrapping. Result: no connectivity for 2 minutes, the time
it took Tor to finish bootstrapping. Now the script verifies everything before
activating the rules.

---

## See also

- [VPN and Tor Hybrid](vpn-e-tor-ibrido.md) - TransPort as a quasi-VPN alternative
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - DNS leak prevention with TransPort
- [Multi-Instance and Stream Isolation](multi-istanza-e-stream-isolation.md) - Circuit isolation
- [System Hardening](../05-sicurezza-operativa/hardening-sistema.md) - nftables and firewall rules
- [Isolation and Compartmentalization](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Namespaces and containers as alternatives
