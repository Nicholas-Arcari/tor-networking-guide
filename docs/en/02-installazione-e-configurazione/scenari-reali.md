> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/scenari-reali.md) | English

# Real-World Scenarios - Installation and Configuration in Action

Operational cases where correct installation, torrc configuration,
and service management made the difference during real engagements.

---

## Table of Contents

- [Scenario 1: Misconfigured torrc causes DNS leak during a pentest](#scenario-1-misconfigured-torrc-causes-dns-leak-during-a-pentest)
- [Scenario 2: Bootstrap failure during an audit on a restrictive network](#scenario-2-bootstrap-failure-during-an-audit-on-a-restrictive-network)
- [Scenario 3: Clock skew blocks Tor in a lab VM](#scenario-3-clock-skew-blocks-tor-in-a-lab-vm)
- [Scenario 4: debian-tor permissions break NEWNYM automation](#scenario-4-debian-tor-permissions-break-newnym-automation)
- [Scenario 5: Multi-identity configuration for red team engagement](#scenario-5-multi-identity-configuration-for-red-team-engagement)

---

## Scenario 1: Misconfigured torrc causes DNS leak during a pentest

### Context

During an external penetration test, the operator was using Tor for anonymous
reconnaissance. The torrc had `SocksPort 9050` configured correctly, but was missing
`DNSPort`, and the application (an OSINT tool) performed direct DNS resolution
bypassing the SOCKS proxy.

### Problem

The tool made DNS queries to the operator's ISP DNS before connecting via Tor.
The target had passive DNS monitoring and detected queries from the pentest
team's IP range -- before any HTTP traffic arrived via Tor.

### Analysis

```bash
# Check for DNS leaks
# 1. Monitor outgoing DNS queries
sudo tcpdump -i eth0 port 53 -n

# 2. While running the tool
proxychains python3 osint-tool.py --target example.com

# tcpdump output:
# 10:23:45 IP 192.168.1.100.52341 > 8.8.8.8.53: A? example.com
# -> DNS leak! The query goes out in cleartext
```

### Solution

```ini
# Add to the torrc
DNSPort 5353
AutomapHostsOnResolve 1
```

```bash
# Configure the system resolver to use Tor DNS
# /etc/resolv.conf
nameserver 127.0.0.1

# Redirect port 53 to 5353 with iptables
sudo iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
sudo iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353
```

### Lesson learned

`SocksPort` only protects TCP traffic that transits via SOCKS. DNS queries
are a separate channel. Without `DNSPort` and without iptables rules, any
application that performs direct DNS causes a leak. See [torrc - Complete Guide](torrc-guida-completa.md)
for the full configuration of `DNSPort` and `AutomapHostsOnResolve`.

---

## Scenario 2: Bootstrap failure during an audit on a restrictive network

### Context

Security audit at a client site with a corporate network protected by a
next-gen firewall and mandatory HTTPS proxy. The team had to operate from inside
the client's network, but Tor could not complete the bootstrap.

### Step-by-step diagnosis

```bash
# 1. Check status
sudo journalctl -u tor@default.service -f
# Output: "Bootstrapped 5% (conn): Connecting to a relay" for 3 minutes

# 2. Without bridges: the firewall blocks direct connections to relays
# Tor uses port 9001 (ORPort) which the firewall does not allow

# 3. With obfs4 bridges: bootstrap reaches 10% then gets stuck
# The firewall performs man-in-the-middle on all TLS traffic (corporate proxy)
# obfs4 cannot negotiate because the bridge certificate does not match

# 4. Solution: ReachableAddresses + meek-azure (simulates Azure CDN traffic)
```

### Resolving configuration

```ini
# torrc for network with mandatory HTTPS proxy
UseBridges 1
ClientTransportPlugin meek_lite exec /usr/bin/obfs4proxy

# meek-azure simulates traffic to Azure CDN - the corporate proxy allows it
Bridge meek_lite 0.0.2.0:2 97700DFE9F483596DDA6264C4D7DF7641E1E39CE \
  url=https://meek.azureedge.net/ front=ajax.aspnetcdn.com

# Only ports allowed by the firewall
ReachableAddresses *:80, *:443
ReachableAddresses reject *:*
```

### Lesson learned

On corporate networks with HTTPS proxies, obfs4 often fails because the proxy
intercepts and modifies the TLS handshake. `meek` works better because it uses
domain fronting through legitimate CDNs that the proxy allows.
The `ReachableAddresses` directive (see [torrc-bridge-e-sicurezza.md](torrc-bridge-e-sicurezza.md))
is essential in these contexts.

---

## Scenario 3: Clock skew blocks Tor in a lab VM

### Context

An analyst prepared a Kali VM for an engagement. The VM had been
snapshot-ted weeks earlier. At boot, the VM clock was 18 days behind.
Tor rejected the consensus.

### Symptom

```bash
sudo journalctl -u tor@default.service | tail -5
# [warn] Our clock is 18 days behind the time published in the consensus.
# [warn] Tor needs an accurate clock to work correctly. Please check your time.
# [err] No valid consensus available.
```

### Solution

```bash
# 1. Check the clock
timedatectl
#   Local time: Mon 2026-03-20 14:23:00 CET  <- 18 days behind

# 2. Synchronize with NTP
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# 3. Verify
timedatectl
#   Local time: Mon 2026-04-07 14:23:15 CET  <- correct

# 4. Restart Tor
sudo systemctl restart tor@default.service

# 5. Monitor bootstrap
sudo journalctl -u tor@default.service -f
# Bootstrapped 100% (done): Done
```

### Lesson learned

The Tor consensus has tight validity windows (3 hours). Even a moderate clock skew
can prevent bootstrap. In VMs, especially after restoring from snapshots, the clock
is almost always wrong. Checking `timedatectl` before starting Tor is a step
that should be included in every operational checklist.
See [gestione-del-servizio.md](gestione-del-servizio.md) for the full debugging process.

---

## Scenario 4: debian-tor permissions break NEWNYM automation

### Context

The team had automated IP rotation with a bash script executed by
cron. The script worked when run manually but failed when scheduled
in cron.

### Problem

```bash
# Crontab:
*/5 * * * * /home/operator/scripts/rotate-ip.sh >> /var/log/rotate.log 2>&1

# Log output:
# [2026-04-07 10:05:01] Authenticating to ControlPort...
# 515 Authentication failed
```

The `operator` user was in the `debian-tor` group and could read the cookie
in an interactive shell. But cron does not load supplementary groups in the
same way -- the cron process did not have permissions to read
`/run/tor/control.authcookie`.

### Solution

```bash
# Option 1: run the script as debian-tor
*/5 * * * * sudo -u debian-tor /home/operator/scripts/rotate-ip.sh

# Option 2: use HashedControlPassword instead of CookieAuthentication
# In the torrc:
HashedControlPassword 16:872860B76453A77D...

# In the script:
printf 'AUTHENTICATE "password"\r\nSIGNAL NEWNYM\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051
```

### Lesson learned

`CookieAuthentication` depends on file system permissions. In automated
contexts (cron, systemd timers, Ansible), the user's supplementary groups
are not always available. For automation,
`HashedControlPassword` is more reliable -- but the password must be protected.
See [configurazione-iniziale.md](configurazione-iniziale.md) for the
debian-tor group configuration and its limitations.

---

## Scenario 5: Multi-identity configuration for red team engagement

### Context

Red team engagement with 3 operators sharing the same Kali machine
as a Tor exit point. Each operator had a different target and
needed to maintain separate identities -- if one operator was detected, the
other two should not be correlatable.

### Problem

With a single `SocksPort 9050`, all operators shared the same circuits.
A `SIGNAL NEWNYM` from one operator invalidated the circuits for all
the others.

### Solution: multi-port torrc

```ini
# torrc - three isolated identities
SocksPort 9050 IsolateSOCKSAuth IsolateDestAddr  # Operator 1
SocksPort 9052 IsolateSOCKSAuth IsolateDestAddr  # Operator 2
SocksPort 9054 IsolateSOCKSAuth IsolateDestAddr  # Operator 3

ControlPort 9051
CookieAuthentication 1
DNSPort 5353
```

```bash
# proxychains for each operator
# /etc/proxychains4-op1.conf -> socks5 127.0.0.1 9050
# /etc/proxychains4-op2.conf -> socks5 127.0.0.1 9052
# /etc/proxychains4-op3.conf -> socks5 127.0.0.1 9054

# Usage:
proxychains4 -f /etc/proxychains4-op1.conf nmap -sT target1.com
proxychains4 -f /etc/proxychains4-op2.conf curl target2.com
```

### Lesson learned

For multi-operator engagements, multiple `SocksPort` entries with `IsolateSOCKSAuth`
and `IsolateDestAddr` ensure that circuits are completely separate.
A more robust alternative: multiple Tor instances (see
[Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md)).
See [torrc-performance-e-relay.md](torrc-performance-e-relay.md) for the
full configuration.

---

## Summary

| Scenario | Applied configuration | Mitigated risk |
|----------|----------------------|----------------|
| DNS leak | DNSPort + iptables redirect | Cleartext DNS queries to ISP |
| Restrictive network | meek + ReachableAddresses | Bootstrap failure behind corporate proxy |
| Clock skew | NTP + timedatectl | Consensus rejected, Tor does not start |
| Cron permissions | HashedControlPassword | NEWNYM automation failure |
| Multi-operator | Multiple isolated SocksPort | Correlation between operator identities |

---

## See also

- [Installation and Verification](installazione-e-verifica.md) - Initial setup
- [torrc - Complete Guide](torrc-guida-completa.md) - All directives
- [Service Management](gestione-del-servizio.md) - systemd, logs, debugging
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - DNS leak deep dive
- [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Multiple instances
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - iptables and DNS interception
