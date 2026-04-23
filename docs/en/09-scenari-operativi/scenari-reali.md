> **Lingua / Language**: [Italiano](../../09-scenari-operativi/scenari-reali.md) | English

# Real-World Scenarios - Tor Operations in a Professional Context

Operational cases where anonymous reconnaissance, secure communication,
development via Tor, and incident response had concrete impact
during professional engagements.

---

## Table of Contents

- [Scenario 1: Cross-target OSINT - correlation from shared exit](#scenario-1-cross-target-osint--correlation-from-shared-exit)
- [Scenario 2: SecureDrop used to receive IOCs during incident response](#scenario-2-securedrop-used-to-receive-iocs-during-incident-response)
- [Scenario 3: CI/CD pipeline via Tor slows down critical release](#scenario-3-cicd-pipeline-via-tor-slows-down-critical-release)
- [Scenario 4: Darknet monitoring reveals data breach before the client](#scenario-4-darknet-monitoring-reveals-data-breach-before-the-client)

---

## Scenario 1: Cross-target OSINT - correlation from shared exit

### Context

A CTI (Cyber Threat Intelligence) team was monitoring two distinct threat
actors for two different clients. The same analyst conducted OSINT
reconnaissance on both targets using the same Tor instance
with SocksPort 9050 without isolation flags.

### Problem

Both reconnaissance activities shared the same Tor circuits. In one case,
one of the threat actors also operated a web service that logged
visitor IPs:

```
Threat actor's log (forum they operated):
  Exit 185.220.101.x → visits profile "actor_A" at 10:15
  Exit 185.220.101.x → visits profile "actor_B" at 10:18
  (same exit, same minute)

Deduction:
  → Someone is investigating both actor_A and actor_B
  → Probably a CTI analyst working on both cases
  → If actor_A and actor_B communicate: "someone is watching us"
```

The lack of stream isolation correlated two investigations that should
have remained completely separate.

### Fix

```ini
# torrc: stream isolation per activity
SocksPort 9050 IsolateSOCKSAuth

# Or: separate Tor instances
SocksPort 9050   # Client A
SocksPort 9052   # Client B
```

```bash
# Research on target A → circuit A
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "clientA:osint" https://forum-actor-a.com/

# Research on target B → circuit B (different exit)
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "clientB:osint" https://forum-actor-b.com/
```

### Lesson learned

Every engagement/client must have separate Tor circuits. Without
`IsolateSOCKSAuth` or dedicated instances, an exit node (or the threat actor
who controls an endpoint) can correlate activities that should be
independent. See [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md).

---

## Scenario 2: SecureDrop used to receive IOCs during incident response

### Context

During an incident response for an Italian company that had suffered
a data breach, the IR team needed to receive information from
an internal source who feared retaliation. The source had identified
the attacker's entry point but did not want to be associated with the
report for fear of being considered complicit.

### Problem

```
Channels evaluated:
  Corporate email    → Logged by the compromised mail server
  Corporate phone    → Call logs accessible to management
  Personal email     → Potentially monitored by the attacker
  Physical meeting   → The source feared being seen

Solution: the source used Tor Browser to contact the IR team
through a temporary GlobaLeaks instance.
```

The IR team deployed a GlobaLeaks instance on an external server,
accessible only via .onion:

```bash
# Rapid GlobaLeaks setup (on the IR team's server)
# → Generates a .onion address
# → The source accesses via Tor Browser
# → Uploads documents with evidence (screenshots, logs)
# → Bidirectional anonymous communication

# The source provided:
# - Screenshot of the compromised server with backdoor path
# - Logs showing the entry point (VPN credential stuffing)
# - Internal attack timeline
```

### Result

The source shared critical IOCs that accelerated containment
by 48 hours. The source's identity was never revealed to the
client's management. After the incident response, the GlobaLeaks
instance was destroyed.

### Lesson learned

For incident response where internal sources fear retaliation, an
anonymous channel via .onion is essential. GlobaLeaks and SecureDrop enable
bidirectional anonymous communication. The IR team must have the capability
to rapidly deploy a temporary .onion service. See
[Secure Communication](comunicazione-sicura.md) and
[Onion Services v3](../03-nodi-e-rete/onion-services-v3.md).

---

## Scenario 3: CI/CD pipeline via Tor slows down critical release

### Context

A development team had configured their CI pipeline to download
dependencies via Tor (proxychains + npm/pip), to prevent the CI
server from revealing the corporate IP to public registries. It worked for
normal builds (5-10 dependencies, small).

### Problem

A critical release required updating 47 npm dependencies
(including a UI framework at 80 MB). The pipeline via Tor took
42 minutes instead of the usual 3:

```
Build without Tor:  npm install → 2 min 15 sec
Build with Tor:     proxychains npm install → 42 min 08 sec
  - Each package: SOCKS5 download → slow
  - Large packages: timeout, retry, timeout, retry
  - npm audit: timeout (API rate-limited for Tor exits)
  - The critical release was delayed by nearly 1 hour

The CTO: "Why is the build taking 40 minutes?"
```

### Fix

```bash
# Hybrid approach: local cache + Tor only for sensitive builds

# 1. Local npm mirror (Verdaccio)
docker run -d --name verdaccio -p 4873:4873 verdaccio/verdaccio
npm set registry http://localhost:4873

# 2. Verdaccio upstream via Tor (only for updating the cache)
# verdaccio config: proxy upstream via SOCKS5

# 3. CI pipeline: uses the local mirror (fast)
# The mirror updates in the background via Tor (slow but non-blocking)

# Result:
# Build from local mirror: 2 min 30 sec (almost the same as without Tor)
# Mirror update via Tor: in the background, non-blocking
```

### Lesson learned

Tor is not suitable for CI pipelines with many dependencies in direct
download. The solution is a local mirror/cache that updates via Tor
in the background. Direct download via Tor is acceptable only for
a few small dependencies. See [Development and Testing](sviluppo-e-test.md)
for CI/CD configurations.

---

## Scenario 4: Darknet monitoring reveals data breach before the client

### Context

A CTI team was monitoring .onion forums and marketplaces on behalf of
various clients. The monitoring used automated Python scripts that accessed
known .onion sites via Tor, downloaded listings, and analyzed them for
client keywords.

### Discovery

```python
# The script found a listing on a marketplace:
# "DB dump - azienda_italiana_spa - 2.3M records"
# - Email, password hash (bcrypt), names, addresses
# - Price: $500
# - Published: 3 hours ago
# - Vendor with 4.8/5 rating (reliable vendor)

# Verification: the sample in the listing contained
# records with @azienda_italiana_spa.it domain
# → Breach confirmed
```

The CTI team notified the client before the breach became
public. The client was not aware they had been compromised.

### Handling

```
Timeline:
  t=0h:    Script finds the listing
  t=0.5h:  Analyst verifies the sample (real data, breach confirmed)
  t=1h:    Notification to the client's CISO via secure channel
  t=2h:    The client initiates incident response
  t=4h:    Containment (credential reset, log analysis)
  t=24h:   The listing is removed from the marketplace (vendor pulls it)
  t=48h:   Notification to the Data Protection Authority (GDPR obligation, 72 hours)

Without darknet monitoring:
  → The breach would have been discovered weeks later
  → Perhaps only when the data had already been resold
  → The Authority would have received the notification past the deadline
```

### Lesson learned

Proactive monitoring of .onion marketplaces is essential operational CTI.
Tor access is the only way to reach these services. Automation
(scripts + Tor) enables continuous monitoring of hundreds of sources.
The timeliness of the notification allowed the client to comply with
GDPR deadlines (72 hours). See
[Incident Response](incident-response.md) for the complete workflow.

---

## Summary

| Scenario | Area | Risk mitigated |
|----------|------|----------------|
| Cross-target OSINT without isolation | Reconnaissance | Correlation between separate investigations |
| SecureDrop for IR with internal source | Communication | Source identity protection during breach |
| CI/CD via Tor too slow | Development | Release delay due to Tor downloads |
| Darknet monitoring pre-breach | Incident Response | Breach discovery before public disclosure |

---

## See also

- [Anonymous Reconnaissance](ricognizione-anonima.md) - OSINT via Tor
- [Secure Communication](comunicazione-sicura.md) - SecureDrop, GlobaLeaks, messaging
- [Development and Testing](sviluppo-e-test.md) - CI/CD, Docker, dependency management
- [Incident Response](incident-response.md) - Threat intelligence, darknet monitoring
- [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Circuit isolation
