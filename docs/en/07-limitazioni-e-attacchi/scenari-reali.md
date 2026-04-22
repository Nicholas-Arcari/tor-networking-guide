> **Lingua / Language**: [Italiano](../../07-limitazioni-e-attacchi/scenari-reali.md) | English

# Real-World Scenarios - Tor Limitations and Attacks in Action

Operational cases where Tor protocol limitations, application incompatibilities,
and known attacks had a concrete impact during penetration tests, red team
engagements, and reconnaissance activities.

---

## Table of Contents

- [Scenario 1: nmap SYN scan leaks real IP during pentest](#scenario-1-nmap-syn-scan-leaks-real-ip-during-pentest)
- [Scenario 2: Tor exits blocked by WAF during web app assessment](#scenario-2-tor-exits-blocked-by-waf-during-web-app-assessment)
- [Scenario 3: Temporal correlation deanonymizes OSINT operator](#scenario-3-temporal-correlation-deanonymizes-osint-operator)
- [Scenario 4: Web session invalidated during exploitation via Tor](#scenario-4-web-session-invalidated-during-exploitation-via-tor)

---

## Scenario 1: nmap SYN scan leaks real IP during pentest

### Context

A junior pentester needed to perform anonymous port scanning on an external
target. They had configured proxychains with Tor and launched nmap with the
flags they habitually used.

### Problem

```bash
# The pentester ran:
proxychains nmap -sS -Pn target.com -p 1-1000
# tcpdump on the interface shows:
# SYN packets going directly to target.com from eth0 → REAL IP!
```

nmap with `-sS` (SYN scan) uses **raw sockets** at the kernel level, completely
bypassing the userspace TCP stack. `proxychains` operates via
`LD_PRELOAD` intercepting only standard socket() calls - raw
sockets are not intercepted.

```
Flow with -sS:
  nmap → raw socket (kernel) → IP stack → target
  proxychains DOES NOT intercept → direct traffic with real IP

Flow with -sT:
  nmap → connect() → proxychains intercepts → SOCKS5 → Tor → target
```

### Fix

```bash
# CORRECT: TCP connect scan (the only one compatible with SOCKS)
proxychains nmap -sT -Pn target.com -p 80,443,8080,8443

# To prevent future mistakes: alias in .zshrc
alias nmap-tor='proxychains nmap -sT -Pn'

# Verify that no traffic goes out directly:
sudo iptables -A OUTPUT -d target.com -j LOG --log-prefix "DIRECT: "
```

### Lesson learned

With Tor, nmap works **only** with `-sT` (TCP connect). The flags `-sS`,
`-sU`, `-sn`, `-O` require raw sockets or ICMP and bypass any
SOCKS proxy. Alternatively, use an iptables transparent proxy to capture
raw socket traffic as well. See [Application Limitations](limitazioni-applicazioni.md)
for the complete nmap+Tor matrix.

---

## Scenario 2: Tor exits blocked by WAF during web app assessment

### Context

A pentest team had received authorization for a web application
assessment on a corporate portal protected by a Cloudflare WAF. The assessment
had to be anonymous (the client also wanted to test their SOC's detection
capability). The team was using Burp Suite configured with SOCKS5 over Tor.

### Problem

After the first 20 requests, the WAF blocked the Tor exit IP:

```
1. Burp Intruder: first 20 requests → 200 OK responses
2. Request 21 → 403 Forbidden "Access denied | Cloudflare"
3. NEWNYM → new exit IP → another 15 requests → 403
4. NEWNYM → another exit → 10 requests → 403
→ Cloudflare was blocking all IPs from the public Tor exit list
```

The Tor exit list is **public** (`check.torproject.org/torbulkexitlist`).
Cloudflare automatically imports it and applies challenges or blocks.

### Operational solution

```bash
# 1. Change approach: ExitNodes from countries with better reputation
# torrc (temporary, reduces anonymity):
ExitNodes {ch},{is},{no}
StrictNodes 1

# 2. Alternative: use a proxy chain Tor → VPS → target
# The VPS has a "clean" IP not on the Tor exit list
ssh -D 1080 user@vps-clean-ip
# Configure Burp on localhost:1080

# 3. For Intruder: manual rate limiting
# Burp → Settings → Network → Connections → Throttle: 1 req/sec
# + NEWNYM every 50 requests
```

### Lesson learned

For web app assessments on targets with advanced WAFs, Tor alone is not enough.
Exit IPs are public and preemptively blocked. The solution
is a Tor→VPS chain with a dedicated IP, or negotiating with the client
to whitelist the test IP. See [Sites that block Tor](limitazioni-applicazioni.md#sites-that-block-tor---strategies)
for bypass strategies.

---

## Scenario 3: Temporal correlation deanonymizes OSINT operator

### Context

An OSINT analyst was using Tor to monitor an underground forum where the
target threat actor was active. The analyst visited the forum every day
during working hours, using NEWNYM before each session.

### Problem

The threat actor managed the forum and had access to the web server logs.
They noticed a pattern:

```
Web server log (threat actor side):
  Tor visitor, same browser fingerprint:
  - Mon-Fri, 09:30-10:00 and 14:00-14:30 (CET)
  - Never weekends, never Italian holidays
  - Always from European exits
  - Browsing: always "marketplace" and "leaks" sections
  - Timing: started 3 days after company X's data breach

Threat actor's deduction:
  → Someone is investigating company X's breach
  → Italian working hours → probably an Italian analyst
  → Started after the breach → connected to incident response
  → The threat actor changed their behavior
```

The analyst was deanonymized not technically (Tor was working) but
**behaviorally**: temporal patterns and correlation with
known events revealed their role.

### Procedural fix

```
1. Vary access times: include evening/weekend sessions
2. Randomize the start: don't begin the day after the event
3. Create noise: visit irrelevant sections, other similar forums
4. Vary the fingerprint: alternate between Tor Browser and curl
5. Use dead drops: download forum snapshots and analyze offline
   → Reduces direct visits to a minimum
```

### Lesson learned

Tor protects the IP but not behavior. An adversary with access to
server logs can correlate temporal, browsing, and fingerprint patterns
to identify investigators. End-to-end correlation
does not always require a global adversary - control of a single
endpoint is enough. See [Correlation attacks](attacchi-noti.md#3-end-to-end-correlation-attack)
and [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md).

---

## Scenario 4: Web session invalidated during exploitation via Tor

### Context

During an authorized pentest, an operator had found a SQL injection
on a target portal. The exploitation required multiple sequential steps:
login → navigate to vulnerable page → injection → data extraction.
The operator was using sqlmap via Tor with a SOCKS5 proxy.

### Problem

```bash
# First attempt:
sqlmap -u "https://target.com/app?id=1" --proxy=socks5://127.0.0.1:9050 \
    --cookie="JSESSIONID=abc123" --dump

# sqlmap output:
# [WARNING] target URL appears to be non-injectable
# HTTP error 302 (redirect to login page)
```

The Tor circuit changed during exploitation (MaxCircuitDirtiness
default: 10 minutes). The new exit has a different IP → the server
invalidated the session (JSESSIONID tied to the IP) → redirect to login
→ sqlmap no longer finds the vulnerability.

```
Timeline:
  t=0:00  Login with exit 185.220.101.x → JSESSIONID created for that IP
  t=8:00  sqlmap finds SQLi, begins extraction
  t=10:02 Circuit changes → new exit 104.244.76.x
  t=10:03 Server: different IP for JSESSIONID → session invalidated → 302
  t=10:04 sqlmap: "non-injectable" (because it now sees the login page)
```

### Fix

```ini
# torrc: increase MaxCircuitDirtiness for exploitation
MaxCircuitDirtiness 3600    # 1 hour (sufficient to complete the exploit)

# Or: use IsolateDestAddr to stabilize the circuit per-target
SocksPort 9050 IsolateDestAddr
```

```bash
# Relaunch sqlmap with a stable circuit:
sqlmap -u "https://target.com/app?id=1" --proxy=socks5://127.0.0.1:9050 \
    --cookie="JSESSIONID=abc123" --dump --threads=1
# → With MaxCircuitDirtiness 3600, the circuit remains stable for 1 hour
```

### Lesson learned

Web sessions tied to the IP are incompatible with Tor's circuit
rotation. For multi-step exploitation, increase `MaxCircuitDirtiness`
or use `IsolateDestAddr` to maintain the same exit for the same
target. Remember to restore the default value after the operation.
See [Protocol Limitations](limitazioni-protocollo.md#multiple-circuits-and-variable-ips)
for the technical details.

---

## Summary

| Scenario | Limitation | Mitigated risk |
|----------|-----------|---------------|
| nmap -sS via proxychains | Raw socket bypasses SOCKS | Real IP leak during scan |
| WAF blocks Tor exits | Public exit list | Assessment blocked after few requests |
| OSINT temporal patterns | Behavioral correlation | Deanonymization through access patterns |
| Session invalidated during exploit | Variable IPs / MaxCircuitDirtiness | Exploitation failed due to circuit change |

---

## See also

- [Protocol Limitations](limitazioni-protocollo.md) - TCP-only, latency, bandwidth
- [Application Limitations](limitazioni-applicazioni.md) - What works and what doesn't via Tor
- [Known Attacks](attacchi-noti.md) - Sybil, correlation, website fingerprinting
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Behavioral errors
- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - MaxCircuitDirtiness, NEWNYM
