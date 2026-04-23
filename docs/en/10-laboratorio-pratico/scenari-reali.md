> **Lingua / Language**: [Italiano](../../10-laboratorio-pratico/scenari-reali.md) | English

# Real-World Scenarios - Hands-On Lab in Operational Context

Cases where the practical skills from the labs (setup, circuit
analysis, DNS leak testing, onion service, stream isolation) made
a difference during real operations.

---

## Table of Contents

- [Scenario 1: Failed bootstrap blocks an engagement - debugging with Lab 01 skills](#scenario-1-failed-bootstrap-blocks-an-engagement--debugging-with-lab-01-skills)
- [Scenario 2: Circuit analysis reveals suspicious relay during an operation](#scenario-2-circuit-analysis-reveals-suspicious-relay-during-an-operation)
- [Scenario 3: Pre-engagement DNS leak test prevents compromise](#scenario-3-pre-engagement-dns-leak-test-prevents-compromise)

---

## Scenario 1: Failed bootstrap blocks an engagement - debugging with Lab 01 skills

### Context

An operator needed to start Tor on a test machine inside a corporate
network with a mandatory HTTP proxy. Tor could not bootstrap
and the engagement was blocked.

### Problem

```bash
sudo systemctl start tor
journalctl -u tor@default -n 20
# [warn] Proxy Client: unable to connect to 127.0.0.1:9050
# [warn] Problem bootstrapping. Stuck at 5% (conn)
# → The corporate network blocks direct connections to Tor ports
# → The corporate HTTP proxy is mandatory for all traffic
```

### Fix (Lab 01 skills)

```bash
# 1. Identify the corporate proxy
echo $http_proxy
# http://proxy.azienda.local:8080

# 2. Configure Tor to use the corporate proxy as a bridge
# /etc/tor/torrc:
UseBridges 1
Bridge obfs4 [bridge address from bridges.torproject.org]
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

# If the proxy requires authentication:
HTTPSProxy proxy.azienda.local:8080
HTTPSProxyAuthenticator user:password

# 3. Restart and verify bootstrap
sudo systemctl restart tor
watch -n 1 'cat /var/lib/tor/state | grep Bootstrap'
# Bootstrapped 100% (done)
```

### Lesson learned

The ability to diagnose bootstrap failures and configure bridges/proxies
is essential for operating in restrictive networks. Lab 01 teaches
exactly these skills: verifying service status, reading logs,
configuring torrc for different environments.

---

## Scenario 2: Circuit analysis reveals suspicious relay during an operation

### Context

During an extended OSINT operation (3 weeks), an analyst was
monitoring circuits with Nyx as a daily routine (Lab 02 skill).
They noticed an anomalous pattern.

### Problem

```
Observation on Nyx:
  - The same middle relay appeared in 40% of circuits
  - Relay: "SuspiciousRelay1234" (generic nickname)
  - AS: budget hosting provider in Eastern Europe
  - Declared bandwidth: very high (attracting traffic)
  - Uptime: 2 weeks (new to the network)

Anomalous pattern:
  - A legitimate relay should not appear this frequently
  - High bandwidth + recent → possible Sybil relay
  - Middle position: can observe the chosen Guard
```

### Action

```bash
# 1. Exclude the suspicious relay
# /etc/tor/torrc:
ExcludeNodes $FINGERPRINT_RELAY_SOSPETTO
# Restart Tor

# 2. Report to the Tor Project
# Email to bad-relays@lists.torproject.org with:
# - Relay fingerprint
# - Observed pattern (anomalous frequency)
# - Observation period
# - Nyx screenshot (optional)

# 3. Verify that circuits no longer use it
nyx  # → circuit list, verify the relay is absent
```

### Lesson learned

Active circuit monitoring with Nyx (Lab 02) is not just educational
- it is operational OPSEC. Suspicious relays can be identified
by anomalous selection patterns. Reporting to the Tor Project
helps protect the entire network. See
[Known Attacks](../07-limitazioni-e-attacchi/attacchi-noti.md) for
details on Sybil and KAX17 attacks.

---

## Scenario 3: Pre-engagement DNS leak test prevents compromise

### Context

A pentest team had a pre-engagement checklist that included
the DNS leak test (Lab 03 skill) before any activity via Tor.
Before an engagement on a sensitive target (financial sector),
the operator ran the routine test.

### Problem

```bash
# Pre-engagement DNS leak test:
sudo tcpdump -i eth0 port 53 -n &
proxychains curl -s https://check.torproject.org/ > /dev/null

# tcpdump output:
# 09:01:15 IP 192.168.1.50.41234 > 192.168.1.1.53: A? check.torproject.org
# → DNS LEAK! The system resolver is resolving in cleartext

# Cause: a system update had reset /etc/resolv.conf
# systemd-resolved had regained control of DNS
# proxychains proxy_dns was configured but resolv.conf pointed
# to the local resolver which was going out in cleartext
```

If the operator had not run the test, the DNS queries for the
target's domains would have gone out in cleartext to the ISP
resolver, revealing that someone was investigating the target.

### Fix

```bash
# 1. Force DNS via Tor
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
# With DNSPort 5353 in torrc + dnsmasq forwarding to 127.0.0.1:5353

# 2. Block direct DNS with iptables
sudo iptables -A OUTPUT -p udp --dport 53 -j DROP
sudo iptables -A OUTPUT -p tcp --dport 53 -j DROP
# Exception for Tor itself (uid debian-tor)
sudo iptables -I OUTPUT -m owner --uid-owner debian-tor -j ACCEPT

# 3. Re-test
sudo tcpdump -i eth0 port 53 -n &
proxychains curl -s https://check.torproject.org/ > /dev/null
# tcpdump: no output → DNS leak resolved
```

### Lesson learned

The DNS leak test (Lab 03) must be in the pre-engagement checklist,
not just a didactic exercise. System updates, configuration resets,
and changes to systemd-resolved can silently reintroduce DNS
leaks. See [DNS Leak](../05-sicurezza-operativa/dns-leak.md)
for all leak scenarios.

---

## Summary

| Scenario | Related lab | Mitigated risk |
|----------|-------------|----------------|
| Failed bootstrap in corporate network | Lab 01 - Setup | Engagement blocked due to configuration |
| Suspicious relay in circuits | Lab 02 - Circuit analysis | Possible Sybil/relay surveillance |
| Pre-engagement DNS leak | Lab 03 - DNS Leak Testing | Cleartext DNS queries toward the target |

---

## See also

- [Lab 01 - Setup and Verification](lab-01-setup-e-verifica.md)
- [Lab 02 - Circuit Analysis](lab-02-analisi-circuiti.md)
- [Lab 03 - DNS Leak Testing](lab-03-dns-leak-testing.md)
- [Lab 04 - Onion Service](lab-04-onion-service.md)
- [Lab 05 - Stream Isolation](lab-05-stream-isolation.md)
