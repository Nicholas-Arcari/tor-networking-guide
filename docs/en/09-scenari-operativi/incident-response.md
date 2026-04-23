> **Lingua / Language**: [Italiano](../../09-scenari-operativi/incident-response.md) | English

# Incident Response - Compromise and Recovery

This document analyzes how to handle security incidents related to Tor usage:
guard compromise, real IP leaks, malicious exit nodes, and post-incident
recovery procedures.

> **See also**: [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) for guard selection,
> [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md),
> [Known Attacks](../07-limitazioni-e-attacchi/attacchi-noti.md),
> [Forensic Analysis and Artifacts](../05-sicurezza-operativa/analisi-forense-e-artefatti.md).

---

## Table of Contents

- [Types of Tor incidents](#types-of-tor-incidents)
- [Incident 1: IP leak](#incident-1-ip-leak)
- [Incident 2: Compromised guard](#incident-2-compromised-guard)
- [Incident 3: Malicious exit node](#incident-3-malicious-exit-node)
- [Incident 4: DNS leak discovered](#incident-4-dns-leak-discovered)
- [Incident 5: Partial deanonymization](#incident-5-partial-deanonymization)
- [Generic recovery procedures](#generic-recovery-procedures)
- [Prevention: continuous monitoring](#prevention-continuous-monitoring)
- [In my experience](#in-my-experience)

---

## Types of Tor incidents

### Classification by severity

| Severity | Type | Example | Action |
|----------|------|---------|--------|
| **Critical** | IP leak during sensitive activity | WebRTC leak, DNS leak | Immediate stop, assess damage |
| **High** | Compromised/malicious guard | Guard logs your IP | Guard rotation, identity change |
| **High** | Malicious exit | SSL stripping, injection | Change circuit, verify data |
| **Medium** | Non-correlatable DNS leak | DNS query to ISP without context | Fix configuration, verify |
| **Low** | Browser fingerprinting | Canvas fingerprint leaked | Review browser config |

---

## Incident 1: IP leak

### Detection

```bash
# Discover a leak during a session:
# 1. Tcpdump shows direct traffic (not via Tor)
sudo tcpdump -i eth0 -n 'not port 9001 and not port 443 and host not 127.0.0.1'
# Output: packets to external IPs → ACTIVE LEAK

# 2. A site shows your real IP instead of the Tor exit
proxychains curl https://api.ipify.org
# → shows your REAL IP → LEAK!

# 3. WebRTC leak detected
# The browser exposed the local IP via WebRTC
```

### Immediate response (first 60 seconds)

```bash
# 1. STOP: halt ALL activity
# Close the browser immediately

# 2. CONTAIN: block direct traffic
iptables -A OUTPUT -j DROP  # block everything
iptables -I OUTPUT -m owner --uid-owner $(id -u debian-tor) -j ACCEPT  # Tor only
iptables -I OUTPUT -d 127.0.0.0/8 -j ACCEPT  # localhost

# 3. VERIFY: confirm the leak has stopped
sudo tcpdump -i eth0 -c 10 -n 'not port 9001 and not port 443'
# Should be silent now
```

### Damage assessment

Questions to answer:
1. **How long did the leak last?** - check logs, timestamps
2. **What data was exposed?** - URLs visited, DNS queries
3. **Who could have observed?** - ISP, local network, destination server
4. **Is the leak correlatable with Tor activity?** - timing, destination

```bash
# Check ISP DNS logs (not accessible, but estimate from timing)
# If you had tcpdump running, analyze the capture:
tcpdump -r capture.pcap -n 'port 53' | head -20
# Shows leaked DNS queries

# Check shell history to understand what you were doing
tail -50 ~/.zsh_history
```

### Recovery

```
If the leak was brief and non-critical:
  → Fix the cause (configuration, disable WebRTC, etc.)
  → NEWNYM to dissociate the session
  → Continue with additional precautions

If the leak was significant:
  → Change guard (delete /var/lib/tor/state)
  → Consider the anonymous activity as compromised
  → DO NOT access the same services from the same setup
  → Evaluate whether the linked identity should be abandoned
```

---

## Incident 2: Compromised guard

### How to know if the guard is compromised

You cannot know for certain. Indirect signals:

| Signal | Possible cause | Verification |
|--------|---------------|--------------|
| Guard removed from consensus with `BadExit` flag | Malicious behavior detected | Check Relay Search |
| Guard disappeared from consensus | Offline, removed, or compromised | Check metrics.torproject.org |
| Malicious relay notification from the community | Public report | Check tor-relays mailing list |
| Path bias warnings in logs | Circuits failing too often | `journalctl -u tor | grep "path bias"` |

### Response

```bash
# 1. Check which guard you are using
cat /var/lib/tor/state | grep "^Guard"
# Guard in EntryGuard MyGuardName AABBCCDD... ...

# 2. Check the guard's status in the consensus
# Via ControlPort:
echo -e "AUTHENTICATE\r\nGETINFO ns/id/AABBCCDD...\r\nQUIT\r\n" | nc 127.0.0.1 9051
# If not found → the guard has been removed from the consensus

# 3. Force guard rotation
sudo systemctl stop tor@default.service

# Remove guard information (forces new selection)
sudo rm /var/lib/tor/state

# Restart
sudo systemctl start tor@default.service
# Tor will select a new guard

# 4. Verify the new guard
cat /var/lib/tor/state | grep "^Guard"
```

### Implications

If the guard was indeed malicious:
- It saw your real IP (always, for every connection)
- It saw the timing of every circuit (but not the destination)
- It could have correlated your IP with traffic patterns
- It did **not** see the content of circuits (encrypted)
- It did **not** see the destination (only the middle node sees it, encrypted)

---

## Incident 3: Malicious exit node

### Detection

```bash
# Signs of a malicious exit:
# 1. TLS certificate different from expected (SSL stripping)
# 2. Modified content (HTML/JS injection)
# 3. Unexpected redirects

# Verify certificate
proxychains curl -sv https://target.com 2>&1 | grep "SSL certificate"
# Compare with the expected certificate

# Verify response integrity
proxychains curl -s https://target.com | sha256sum
# Compare with known hash
```

### Types of malicious exit attacks

```
1. SSL Stripping:
   You → Tor → Exit → HTTPS downgrade to HTTP → target
   Exit sees: all traffic in cleartext
   Detection: browser does not show HTTPS padlock

2. Injection:
   You → Tor → Exit → target responds with HTML
   Exit modifies HTML adding malicious <script>
   Detection: different content hash, unknown scripts

3. DNS spoofing:
   You → Tor → Exit → resolves target.com → fake IP
   Detection: IP different from expected

4. Credential harvesting:
   Exit logs unencrypted HTTP credentials
   Detection: impossible to detect in real time
```

### Response

```bash
# 1. Change circuit immediately
echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051

# 2. Identify the malicious exit
# From connections in Nyx:
nyx
# Connections screen → note the exit fingerprint before NEWNYM

# 3. Report
# Email: bad-relays@lists.torproject.org
# GitLab: https://gitlab.torproject.org/tpo/network-health/team/-/issues

# 4. Change credentials if exposed
# If you sent passwords via HTTP (not HTTPS) → change them ALL
```

### Prevention

- **ALWAYS use HTTPS**: Tor protects routing, not content
- **HSTS**: verify that critical sites use HSTS
- **Verify certificates**: compare certificate fingerprints
- **Never enter credentials via HTTP**: never, especially via Tor

---

## Incident 4: DNS leak discovered

### Detection

```bash
# 1. Tcpdump shows outgoing DNS queries
sudo tcpdump -i eth0 -n port 53
# If you see packets → ACTIVE DNS LEAK

# 2. Online test
proxychains curl -s https://check.torproject.org/api/ip
# Compare with:
curl -s https://api.ipify.org  # direct IP
# If different but DNS resolves the same hostnames → DNS leak
```

### Response

```bash
# 1. Block direct DNS immediately
iptables -I OUTPUT -p udp --dport 53 -j DROP
iptables -I OUTPUT -p tcp --dport 53 -j DROP
# Except toward Tor's DNSPort:
iptables -I OUTPUT -p udp --dport 53 -d 127.0.0.1 -j ACCEPT

# 2. Identify the cause
# a. proxychains without proxy_dns?
grep "proxy_dns" /etc/proxychains4.conf
# If commented out → CAUSE FOUND

# b. Firefox without remote DNS?
# about:config → network.proxy.socks_remote_dns must be true

# c. Application bypassing the proxy?
# Some apps perform direct DNS before connect()

# 3. Fix the cause and verify
sudo tcpdump -i eth0 -n port 53 -c 10
# Should be silent
```

### Impact

A DNS leak reveals:
- **Which sites you are visiting** (hostnames in DNS queries)
- **Timing of visits** (query timestamps)
- **Browsing patterns** (sequence of DNS queries)
- **Correlation with Tor traffic** (DNS query + Tor connection = you)

The damage depends on who is observing:
- ISP: sees all DNS queries - knows where you browse
- Local network: if unencrypted, anyone can see the queries
- DNS server: logs queries (Google DNS, Cloudflare, ISP)

---

## Incident 5: Partial deanonymization

### Scenarios

```
Scenario: a site has determined that you are "the same person" as a previous
visit (fingerprinting), but does not know your real identity.

Severity: medium (they do not have your IP, but can correlate activity)

Response:
  1. New NEWNYM identity
  2. Modify browser fingerprint:
     - Resize the window (window size is a vector)
     - Clear cookies/localStorage
     - Change User-Agent
  3. For future sessions: use Tor Browser (better anti-fingerprinting)
```

```
Scenario: end-to-end correlation (ISP sees Tor connection + server sees
traffic → timing match).

Severity: high (they can potentially identify you)

Response:
  1. There is no retroactive remedy (the damage is done)
  2. Future prevention: obfs4 bridge to hide Tor usage from ISP
  3. Padding: enable ConnectionPadding 1 in torrc
  4. Cover traffic: use Tor for non-sensitive activities as well
```

---

## Generic recovery procedures

### Standard post-incident procedure

```
PHASE 1: CONTAINMENT (minutes)
  □ Stop the ongoing activity
  □ Activate restrictive firewall (Tor only)
  □ Verify with tcpdump that there are no active leaks

PHASE 2: ANALYSIS (hours)
  □ Determine incident type and duration
  □ Identify exposed data
  □ Assess who could have observed
  □ Document timeline

PHASE 3: RECOVERY (hours-days)
  □ Fix the technical cause
  □ Change compromised credentials
  □ Guard rotation (if necessary)
  □ NEWNYM to dissociate the session
  □ Verify the fix with testing

PHASE 4: PREVENTION (ongoing)
  □ Implement monitoring (tcpdump, alerting)
  □ Update configuration to prevent recurrence
  □ Document the incident and the solution
  □ Review the overall configuration
```

### When to abandon an identity

The identity (onion address, pseudonym, account) must be abandoned when:

- Your real IP was exposed in correlation with the identity
- You logged into identifiable services (real email, social media) from the same session
- The adversary has motive and capability to correlate (nation-state, cooperating ISP)
- OPSEC was violated in a non-recoverable way

---

## Prevention: continuous monitoring

### Monitoring script

```bash
#!/bin/bash
# tor-leak-monitor.sh - Monitor for leaks in background

LOG="/var/log/tor-leak-monitor.log"

echo "$(date): Monitoring started" >> "$LOG"

while true; do
    # Check 1: DNS leak
    DNS_LEAK=$(sudo timeout 5 tcpdump -i eth0 -c 1 -n port 53 2>/dev/null)
    if [ -n "$DNS_LEAK" ]; then
        echo "$(date): ALERT - DNS LEAK DETECTED: $DNS_LEAK" >> "$LOG"
        # Optional: desktop notification
        notify-send "TOR ALERT" "DNS Leak detected!" 2>/dev/null
    fi
    
    # Check 2: non-Tor traffic
    NON_TOR=$(sudo timeout 5 tcpdump -i eth0 -c 1 -n \
        'not port 9001 and not port 443 and not port 80 and not arp and not port 53' 2>/dev/null)
    if [ -n "$NON_TOR" ]; then
        echo "$(date): ALERT - Non-Tor traffic: $NON_TOR" >> "$LOG"
    fi
    
    # Check 3: Tor is running
    if ! systemctl is-active --quiet tor@default.service; then
        echo "$(date): ALERT - Tor NOT active!" >> "$LOG"
        notify-send "TOR ALERT" "Tor service down!" 2>/dev/null
    fi
    
    sleep 30
done
```

### Automated alerting

```python
#!/usr/bin/env python3
"""Tor monitor with alerting via ControlPort."""

import functools
from stem.control import Controller

def warn_handler(event):
    """Handler for warnings and errors."""
    if "circuit" in str(event.message).lower() and "failed" in str(event.message).lower():
        print(f"[ALERT] Circuit failure: {event.message}")
    if "path bias" in str(event.message).lower():
        print(f"[ALERT] Path bias: {event.message}")
    if "clock" in str(event.message).lower():
        print(f"[ALERT] Clock issue: {event.message}")

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    ctrl.add_event_listener(warn_handler, "WARN")
    ctrl.add_event_listener(warn_handler, "ERR")
    
    print("Monitoring active... (Ctrl+C to exit)")
    import time
    while True:
        time.sleep(1)
```

---

## In my experience

My most significant incident was a DNS leak: I had configured
proxychains for Firefox but had not enabled `proxy_dns` in the
configuration file. For weeks, every hostname I visited via "Tor" was
first resolved in cleartext by my ISP (Comeser, Parma).

I discovered it by chance, running `tcpdump -i eth0 port 53` for a different
test. I saw dozens of plaintext DNS queries for the sites I was visiting
via proxychains. The fix was simple (uncommenting `proxy_dns` in
`proxychains4.conf`), but the damage was done: my ISP had a complete log
of all sites visited "via Tor" for weeks.

From that experience I learned:
1. **ALWAYS verify with tcpdump** after configuring something
2. **Do not trust that "it works"** - verify that it works CORRECTLY
3. **Monitor periodically** - leaks can appear after updates
4. **DNS is the most common and most dangerous leak vector**

Now my workflow always includes a post-configuration check:
```bash
# After every modification to the Tor configuration:
sudo tcpdump -i eth0 -n port 53 -c 5 &
proxychains curl https://example.com > /dev/null 2>&1
# If tcpdump shows packets → leak, fix before using
```

---

## See also

- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Preventing incidents
- [Forensic Analysis and Artifacts](../05-sicurezza-operativa/analisi-forense-e-artefatti.md) - What remains after an incident
- [IP, DNS, and Leak Verification](../04-strumenti-operativi/verifica-ip-dns-e-leak.md) - Complete post-incident tests
- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - Circuit recovery
- [Known Attacks](../07-limitazioni-e-attacchi/attacchi-noti.md) - Documented attack scenarios
