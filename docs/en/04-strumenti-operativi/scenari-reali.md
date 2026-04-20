> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/scenari-reali.md) | English

# Real-World Scenarios - Tor Operational Tools in Action

Operational cases where proxychains, torsocks, Nyx, ControlPort, and DNS management
made the difference during penetration tests and red team engagements.

---

## Table of Contents

- [Scenario 1: proxychains silently fails during a pentest](#scenario-1-proxychains-silently-fails-during-a-pentest)
- [Scenario 2: DNS leak detected with tcpdump during reconnaissance](#scenario-2-dns-leak-detected-with-tcpdump-during-reconnaissance)
- [Scenario 3: Nyx reveals a compromised guard during an engagement](#scenario-3-nyx-reveals-a-compromised-guard-during-an-engagement)
- [Scenario 4: torsocks blocks UDP and breaks a scanning tool](#scenario-4-torsocks-blocks-udp-and-breaks-a-scanning-tool)
- [Scenario 5: NEWNYM automation for rate limiting evasion](#scenario-5-newnym-automation-for-rate-limiting-evasion)

---

## Scenario 1: proxychains silently fails during a pentest

### Context

An operator was using `proxychains nmap -sT` for anonymous port scanning of the target.
The scan returned results, but a cross-check showed that some
packets were not going through Tor - they were exiting with the operator's real IP.

### Problem

nmap, when invoked with `proxychains`, does not route all traffic via
SOCKS. Specifically:
- ICMP pings (if not disabled with `-Pn`) bypass proxychains
- Raw socket connections are not intercepted by LD_PRELOAD
- nmap uses direct syscalls that circumvent proxychains hooking

### Diagnosis

```bash
# Monitor outgoing traffic while scanning
sudo tcpdump -i eth0 not port 9050 and host TARGET_IP -n

# Output:
# 10:23:45 IP 192.168.1.100 > TARGET_IP: ICMP echo request
# → ICMP exits directly, not via Tor!
```

### Solution

```bash
# 1. Always use -Pn with nmap via proxychains (no ping)
proxychains nmap -sT -Pn -p80,443,22 target.example.com

# 2. Safer alternative: torsocks (blocks UDP and ICMP)
torsocks nmap -sT -Pn target.example.com

# 3. Maximum security alternative: transparent proxy with iptables
# that captures ALL outgoing traffic
```

### Lesson learned

proxychains only intercepts `connect()` and `getaddrinfo()` via LD_PRELOAD - it does not
capture raw sockets, ICMP, or direct syscalls. For anonymous scanning, always use
`-Pn` and prefer `-sT` (TCP connect). See [proxychains-guida-completa.md](proxychains-guida-completa.md)
for the limitations of LD_PRELOAD.

---

## Scenario 2: DNS leak detected with tcpdump during reconnaissance

### Context

The team was conducting OSINT on a target via Tor. A custom Python tool
used `requests` with a SOCKS5 proxy, but DNS was leaking to the ISP.

### Diagnosis

```bash
# Terminal 1: monitor outgoing DNS
sudo tcpdump -i eth0 port 53 -n

# Terminal 2: run the tool
proxychains python3 osint-tool.py --target example.com

# tcpdump output:
# 10:30:12 IP 192.168.1.100.43210 > 8.8.8.8.53: A? api.target.com
# → DNS leak! The tool resolves before sending to the proxy
```

The problem: the tool was using `requests.get(url, proxies=...)` with `socks5://`
instead of `socks5h://`. The `h` at the end indicates "resolve hostname via proxy".

### Fix

```python
# WRONG - resolves DNS locally
proxies = {"https": "socks5://127.0.0.1:9050"}

# CORRECT - resolves DNS via Tor
proxies = {"https": "socks5h://127.0.0.1:9050"}
```

### Lesson learned

The difference between `socks5://` and `socks5h://` is critical. Without the `h`, the
library resolves the hostname locally before sending the IP to the proxy - DNS
exits in the clear. See [dns-avanzato-e-hardening.md](dns-avanzato-e-hardening.md)
for all DNS leak scenarios.

---

## Scenario 3: Nyx reveals a compromised guard during an engagement

### Context

An operator had Tor running for 3 weeks during a long-term engagement.
Checking Nyx occasionally, they noticed that latency to the guard had
gone from 50ms to 800ms, and bandwidth had dropped.

### Analysis with Nyx

```
# Connections screen in Nyx:
#  Guard $AAAA~SlowGuard  → latency: 823ms  bandwidth: 120 KB/s
#  (3 weeks ago it was 50ms and 2 MB/s)
```

Checking on Relay Search:
```bash
torsocks curl -s "https://onionoo.torproject.org/details?lookup=$AAAA" | python3 -c "
import json, sys
r = json.load(sys.stdin)['relays'][0]
print(f'Flags: {r.get(\"flags\",[])}')
print(f'Bandwidth: {r.get(\"observed_bandwidth\",0)//1024} KB/s')
"
# Flags: ['Running', 'Valid'] ← LOST the Guard and Stable flags!
```

The guard had lost the Guard and Stable flags - probably hardware or
network issues on the server. But Tor continued using it because it was still in the `state` file.

### Solution

```bash
# Force guard rotation (only in justified cases)
sudo systemctl stop tor@default.service
sudo rm /var/lib/tor/state
sudo systemctl start tor@default.service

# Verify the new guard in Nyx
nyx  # → Connections → guard with Guard+Stable flags and latency <100ms
```

### Lesson learned

Nyx (see [nyx-e-monitoraggio.md](nyx-e-monitoraggio.md)) is the best tool
for monitoring circuit health over time. In long-term engagements,
periodically verify that the guard still has appropriate flags.

---

## Scenario 4: torsocks blocks UDP and breaks a scanning tool

### Context

An operator was trying to use `torsocks` with a DNS enumeration tool that
used direct UDP queries (not via the C library resolver).

### Problem

```bash
torsocks fierce --domain target.com
# WARNING torsocks[12345]: [syscall] Unsupported syscall number 44. Denying...
# No DNS results
```

torsocks blocks all UDP syscalls (`sendto()` on SOCK_DGRAM sockets) because
Tor does not support UDP. But the tool depends on UDP for DNS queries.

### Solution

```bash
# Option 1: use proxychains (does not block UDP, but does not route it either)
# PRO: the tool works
# CON: DNS queries exit in the clear (leak!)
proxychains fierce --domain target.com

# Option 2: use Tor's DNSPort + configure the tool
# Configure the system to use 127.0.0.1:5353 as DNS
# Queries will be resolved by Tor

# Option 3: use a DNS-over-TCP tool
# dig +tcp @127.0.0.1 -p 5353 target.com ANY
```

### Lesson learned

torsocks is more secure than proxychains (blocks UDP instead of letting it through),
but this breaks tools that depend on UDP. The choice between proxychains and torsocks
depends on context: security vs compatibility. See
[torsocks-avanzato.md](torsocks-avanzato.md) for the detailed comparison.

---

## Scenario 5: NEWNYM automation for rate limiting evasion

### Context

The team needed to enumerate endpoints of an API protected by IP-based rate limiting
(max 100 requests per IP, then a 5-minute block). 3000 requests were needed.

### Solution with automated NEWNYM

```bash
#!/bin/bash
# rotate-and-query.sh - Execute requests with automatic IP rotation

COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
ENDPOINT="https://api.target.com/v1/users"
BATCH_SIZE=90  # under the 100 limit

for batch in $(seq 1 34); do  # 34 batches × 90 = 3060 requests
    echo "[Batch $batch] Rotating IP..."
    printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
    sleep 3  # wait for new circuit construction

    NEW_IP=$(proxychains curl -s https://api.ipify.org 2>/dev/null)
    echo "[Batch $batch] New IP: $NEW_IP"

    for i in $(seq 1 $BATCH_SIZE); do
        proxychains curl -s "$ENDPOINT?page=$((($batch-1)*$BATCH_SIZE+$i))" \
          >> results.json 2>/dev/null
    done
done
```

### NEWNYM rate limit

NEWNYM has an internal rate limit: Tor accepts NEWNYM signals at most every
10 seconds. More frequent signals are silently ignored.

```bash
# Verify that the circuit actually changed
OLD_IP=$(proxychains curl -s https://api.ipify.org)
printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
sleep 3
NEW_IP=$(proxychains curl -s https://api.ipify.org)

if [ "$OLD_IP" = "$NEW_IP" ]; then
    echo "[!] IP did not change - few exits available for this port"
fi
```

### Lesson learned

The ControlPort and NEWNYM (see [controllo-circuiti-e-newnym.md](controllo-circuiti-e-newnym.md))
enable advanced automation. The 10-second rate limit must be respected -
more frequent signals are silently ignored. Furthermore, NEWNYM does not
guarantee a different exit: with few exits available for the target port,
the same exit can be reselected.

---

## Summary

| Scenario | Tool | Risk mitigated |
|----------|------|----------------|
| proxychains + nmap | proxychains | ICMP leak with real IP |
| Python DNS leak | socks5h:// | Cleartext DNS queries to ISP |
| Degraded guard | Nyx | Slow circuits due to compromised guard |
| torsocks + UDP | torsocks | Broken DNS tool, security vs compatibility trade-off |
| Rate limiting | ControlPort/NEWNYM | IP block after too many requests |

---

## See also

- [ProxyChains - Complete Guide](proxychains-guida-completa.md) - LD_PRELOAD limitations
- [torsocks](torsocks.md) - UDP blocking, edge cases
- [Nyx and Monitoring](nyx-e-monitoraggio.md) - Circuit monitoring
- [Circuit Control and NEWNYM](controllo-circuiti-e-newnym.md) - ControlPort automation
- [Advanced DNS and Hardening](dns-avanzato-e-hardening.md) - All DNS leak scenarios
