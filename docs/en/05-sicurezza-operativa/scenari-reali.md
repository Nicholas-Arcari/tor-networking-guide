> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/scenari-reali.md) | English

# Real-World Scenarios - Tor Operational Security in Action

Operational cases where DNS leak, fingerprinting, OPSEC, isolation and hardening
made the difference during penetration tests, red team engagements and
OSINT activities.

---

## Table of Contents

- [Scenario 1: Undetected DNS leak during OSINT on a sensitive target](#scenario-1-undetected-dns-leak-during-osint-on-a-sensitive-target)
- [Scenario 2: JA3 fingerprint betrays the operator during red team](#scenario-2-ja3-fingerprint-betrays-the-operator-during-red-team)
- [Scenario 3: Forensic artifacts on workstation post-engagement](#scenario-3-forensic-artifacts-on-workstation-post-engagement)
- [Scenario 4: OPSEC failure - temporal correlation between sessions](#scenario-4-opsec-failure--temporal-correlation-between-sessions)
- [Scenario 5: Isolation with network namespace saves an engagement](#scenario-5-isolation-with-network-namespace-saves-an-engagement)

---

## Scenario 1: Undetected DNS leak during OSINT on a sensitive target

### Context

An OSINT team was gathering information on a target organization. The operator
used `proxychains firefox` with the tor-proxy profile to browse sites connected
to the target. After two days, the client received alerts from their SOC
indicating suspicious DNS queries for their domains from an Italian IP.

### Problem

Firefox with proxychains resolved correctly via Tor for directly visited sites,
but DNS prefetch pre-resolved the domains of links on the pages.

```bash
# tcpdump shows the prefetch queries going out in cleartext
sudo tcpdump -i eth0 port 53 -n
# 14:23:01 IP 151.x.x.x.48320 > 192.168.1.1.53: A? subdomain.target.com
# 14:23:01 IP 151.x.x.x.48321 > 192.168.1.1.53: A? mail.target.com
# → Firefox was pre-resolving links on the page BEFORE the click
```

The tor-proxy profile had `network.proxy.socks_remote_dns = true`, but
`network.dns.disablePrefetch` had remained at `false` (default).

### Fix

```
# about:config - add to the tor-proxy profile:
network.dns.disablePrefetch = true
network.prefetch-next = false
network.predictor.enabled = false
network.http.speculative-parallel-limit = 0
```

### Lesson learned

`socks_remote_dns` protects only explicit DNS requests. Firefox's DNS prefetch
is a separate mechanism that completely bypasses the proxy. See
[DNS Leak](dns-leak.md) for all scenarios and [Advanced Hardening](hardening-avanzato.md)
for the complete Firefox configuration.

---

## Scenario 2: JA3 fingerprint betrays the operator during red team

### Context

During a red team engagement, the operator used Firefox+proxychains on Kali for
web reconnaissance on the target. The target had a WAF (Web Application Firewall)
with active JA3 fingerprinting. After a few requests, the Tor exit IP was
blocked.

### Analysis

The target's WAF compared the JA3 hash with the declared User-Agent:

```
User-Agent: Mozilla/5.0 (Windows NT 10.0; rv:128.0) [privacy.resistFingerprinting]
JA3 hash: e7d705a3286e19ea42f587b344ee6865 [Firefox on Linux]

→ INCONSISTENCY: User-Agent says Windows, JA3 says Linux
→ WAF flag: "spoofed User-Agent" → automatic block
```

With `privacy.resistFingerprinting` enabled, Firefox declared Windows in the
User-Agent, but the TLS ClientHello contained parameters specific to Firefox
on Linux - a discrepancy impossible for a real Windows user.

### Solution

```bash
# Option 1: Do NOT use resistFingerprinting (JA3/UA consistency)
# The JA3 matches Firefox on Linux, and the UA says Linux
# Less suspicious for WAFs with JA3 matching

# Option 2: Tor Browser (JA3 and UA consistent, large pool)
# Tor Browser has a specific JA3 and matching UA
# The WAF sees "Tor Browser user" - pool of millions

# Option 3: curl with --socks5-hostname (different JA3)
proxychains curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
  https://target.com/
# curl has a different JA3 than Firefox - less associated with Linux
```

### Lesson learned

`privacy.resistFingerprinting` creates inconsistency between User-Agent and JA3, which is
more suspicious than not spoofing. For web reconnaissance on targets with advanced WAFs,
use Tor Browser (consistent JA3/UA) or tools with non-browser JA3.
See [Fingerprinting](fingerprinting.md) for JA3/JA4 and the protection table.

---

## Scenario 3: Forensic artifacts on workstation post-engagement

### Context

After a 3-month red team engagement, the team had to return the corporate
workstations. A team member had used Tor on that machine for reconnaissance.
The corporate policy required a forensic audit before return.

### Problem

The audit found extensive traces of Tor usage:

```bash
# The auditor ran:
dpkg -l | grep -iE "tor |torsocks|obfs4|nyx|proxychains"
# → 5 Tor-related packages installed

journalctl -u tor@default --since "3 months ago" | head -50
# → Hundreds of entries with start/NEWNYM/shutdown timestamps

cat /var/lib/tor/state
# → Guard fingerprint, last use, configured obfs4 bridges

grep -r "proxychains\|torsocks\|nyx" ~/.zsh_history
# → 200+ commands with specific client targets

cat ~/.mozilla/firefox/*.tor-proxy/prefs.js | grep socks
# → SOCKS5 configuration 127.0.0.1:9050
```

### Applied mitigation (post-incident)

```bash
# 1. Tor cleanup
sudo systemctl stop tor@default.service
sudo apt purge tor tor-geoipdb obfs4proxy nyx torsocks
sudo rm -rf /var/lib/tor/ /var/log/tor/ /etc/tor/

# 2. Browser cleanup
rm -rf ~/.mozilla/firefox/*.tor-proxy/

# 3. History cleanup
rm -f ~/.zsh_history ~/.bash_history

# 4. Log cleanup
sudo journalctl --vacuum-time=1d

# 5. Apt history cleanup
sudo rm /var/log/apt/history.log*
```

### Lesson learned

For engagements where Tor usage must not leave traces on the machine:
- Use a dedicated VM (deletable at end of engagement)
- Or Tails from USB (zero disk artifacts)
- Or Docker with tmpfs volume (disposable container)

Post-hoc cleanup is always incomplete: journald may have entries in
rotated segments, the filesystem may have recoverable data. See
[Forensic Analysis and Artifacts](analisi-forense-e-artefatti.md) for the complete
artifact list.

---

## Scenario 4: OPSEC failure - temporal correlation between sessions

### Context

An operator conducted anonymous reconnaissance on a target's forum. They used
Tor correctly, NEWNYM between sessions, no login. But the target's SOC
correlated the anonymous sessions with the engagement.

### How it was discovered

```
Pattern observed by the target's SOC:
- Anonymous visits to the forum: every day 09:00-09:30 and 14:00-14:30
- Always from European Tor exits
- Navigation pattern: always the same forum sections
- Visits started exactly on the engagement start day

SOC correlation:
- The engagement was communicated internally on March 1
- Anonymous visits to the forum started on March 2
- Visits follow Italian work hours (09-18 CET)
- The operator is the only recurring Tor visitor to the forum
→ Conclusion: the anonymous visits come from the pentest team
```

### Procedural fix

```
1. Do NOT start reconnaissance the day after kick-off
   → Start at least 1-2 weeks before (if the contract allows)
   → Or randomize the start

2. Do NOT use predictable schedules
   → Vary access times (not always 09:00 and 14:00)
   → Include accesses outside work hours

3. Use NEWNYM between different forum sections
   → Do not browse multiple sections with the same exit IP

4. Mix with non-target traffic
   → Also visit other similar forums to create noise
```

### Lesson learned

Behavioral OPSEC is as important as technical OPSEC. Regular temporal patterns
and correlation with known events (engagement start) are deanonymization vectors
that Tor cannot prevent. See
[OPSEC and Common Mistakes](opsec-e-errori-comuni.md) for behavioral patterns
and [OPSEC - Real-World Cases](opsec-casi-reali-e-difese.md) for historical cases.

---

## Scenario 5: Isolation with network namespace saves an engagement

### Context

During an engagement, an operator needed to run a custom Python
script via Tor to enumerate API endpoints of the target. The script used
`requests` with SOCKS5 proxy, but also made calls to internal services
(logging, local database) that should not go through Tor.

### Problem

The script had a bug: a dependency made HTTP requests to an external
telemetry service without respecting the configured SOCKS5 proxy. The
requests went out with the operator's real IP.

```python
# The operator's code (correct):
import requests
session = requests.Session()
session.proxies = {"https": "socks5h://127.0.0.1:9050"}
resp = session.get("https://api.target.com/v1/users")

# The imported dependency (bug):
import analytics  # internal logging library
analytics.track("scan_started")  # → HTTP POST to analytics.example.com
# → Goes out with real IP! The library does not use the session's proxy
```

### Solution: network namespace

```bash
# Create isolated namespace
sudo ip netns add pentest_ns
sudo ip link add veth-host type veth peer name veth-ns
sudo ip link set veth-ns netns pentest_ns
sudo ip addr add 10.200.1.1/24 dev veth-host
sudo ip link set veth-host up
sudo ip netns exec pentest_ns ip addr add 10.200.1.2/24 dev veth-ns
sudo ip netns exec pentest_ns ip link set veth-ns up
sudo ip netns exec pentest_ns ip link set lo up
sudo ip netns exec pentest_ns ip route add default via 10.200.1.1

# Force all namespace traffic through Tor TransPort
sudo iptables -t nat -A PREROUTING -s 10.200.1.0/24 -p tcp \
    -j REDIRECT --to-ports 9040
sudo iptables -t nat -A PREROUTING -s 10.200.1.0/24 -p udp --dport 53 \
    -j REDIRECT --to-ports 5353
sudo iptables -A FORWARD -s 10.200.1.0/24 -j DROP

# Run the script in the namespace
sudo ip netns exec pentest_ns sudo -u $USER python3 scan_api.py
# → ALL TCP traffic goes through Tor, including telemetry
# → The analytics.track() request goes through Tor automatically
# → UDP blocked (no DNS leak possible)
```

### Lesson learned

The network namespace forces **all** traffic from a process and its
dependencies through Tor, regardless of how the code handles
connections. It is the ideal solution for scripts with uncontrolled dependencies.
See [Advanced Isolation](isolamento-avanzato.md) for the complete setup and
[Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) for
iptables/nftables.

---

## Summary

| Scenario | Area | Mitigated risk |
|----------|------|----------------|
| DNS prefetch in OSINT | DNS Leak | Cleartext DNS queries for target domains |
| JA3 mismatch with WAF | Fingerprinting | IP block due to UA/JA3 inconsistency |
| Post-engagement artifacts | Forensics | Tor traces on corporate workstation |
| Temporal correlation | OPSEC | Predictable access patterns |
| Namespace for Python script | Isolation | IP leak from uncontrolled dependencies |

---

## See also

- [DNS Leak](dns-leak.md) - Leak scenarios and verification
- [Fingerprinting](fingerprinting.md) - JA3, browser, OS fingerprinting
- [Forensic Analysis and Artifacts](analisi-forense-e-artefatti.md) - Disk and RAM artifacts
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Mistakes and correlation
- [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) - Namespaces, Whonix, Tails
- [System Hardening](hardening-sistema.md) - Firefox and system configuration
