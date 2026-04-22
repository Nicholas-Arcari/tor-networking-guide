> **Lingua / Language**: [Italiano](../../07-limitazioni-e-attacchi/attacchi-noti-avanzati.md) | English

# Known Attacks - HSDir, DoS, Browser Exploits and Countermeasures

HSDir enumeration, Denial of Service, browser exploits (Freedom Hosting,
Playpen), supply chain, BGP/RAPTOR, Sniper Attack, attacks on Onion Services,
complete attack matrix and timeline of countermeasures adopted by Tor.

> **Extracted from** [Known Attacks on the Tor Network](attacchi-noti.md) - which also covers
> Sybil attack, relay early tagging, end-to-end correlation and website
> fingerprinting.

---

## 5. HSDir Enumeration

### How it works

HSDirs (Hidden Service Directories) are relays that store onion service
descriptors. An adversary that controls HSDirs can:

```
Onion Services v2 (deprecated):
  1. The HSDir is determined by the combination of:
     .onion address + current date + position in the DHT
  2. An adversary can calculate WHICH HSDirs will contain
     the descriptor for a given .onion
  3. By positioning relays in those positions:
     → Sees the requests for that descriptor
     → Knows when the descriptor is updated
     → Can correlate requests with circuits

2016 - Researchers enumerated ~110,000 v2 onion services
  by analyzing requests to HSDirs
```

### Countermeasures (Onion Service v3)

```
v3 resolved many v2 vulnerabilities:

1. Encrypted descriptors:
   - The descriptor is encrypted with the HS's public key
   - The HSDir CANNOT read the descriptor contents
   - It does not know which .onion it is serving

2. HSDir rotation:
   - HSDirs change every 24 hours (time period based)
   - The adversary must continuously reposition relays

3. Key blinding:
   - The key used for the DHT is derived (blinded)
   - It is not possible to trace back to the .onion address from the DHT

4. Authenticated requests:
   - The client must know the .onion address to calculate
     which HSDir to contact
   - A random HSDir cannot discover new .onion addresses

5. Client authorization:
   - The HS can require client authentication
   - Only authorized clients can download the descriptor
```

---

## 6. Denial of Service (DoS) on the Tor network

### Attacks on relays

```
An adversary can:
1. DDoS specific relays to force guard rotation
   - The user must choose a new guard
   - If the new guard is malicious → compromise
   - "Guard rotation attack"

2. Overload exit nodes
   - Reduces exit options → less anonymity
   - Forces traffic onto remaining exits → congestion

3. Overload the Directory Authorities
   - Prevents consensus updates
   - Clients cannot obtain network information
```

### Attacks on hidden services (2021-2023)

```
Since 2021, the Tor network has suffered significant DoS attacks
targeting onion services:

Technique:
  - Flood of requests toward Introduction Points
  - The HS must process each request (expensive)
  - The attacker pays no cost
  → Asymmetry: low cost for the attacker, high for the HS

Impact:
  - Many .onion sites unreachable for hours/days
  - Performance degradation of the entire network
  - Impact on legitimate services (.onion news sites, SecureDrop)
```

### Countermeasures

```
1. Proof-of-Work (PoW) for onion services (Tor 0.4.8+):
   - Clients must solve a computational puzzle
   - The puzzle scales with the HS's load
   - Under load: the puzzle becomes harder
   - The attacker must spend CPU for each request
   - Implementation: EquiX (Equihash-based)

2. Rate limiting on Directory Authorities:
   - Limits requests per IP
   - Prevents consensus flooding

3. Introduction Point diversification:
   - The HS can have multiple Introduction Points
   - If one is under attack, the others still function

4. Vanguards:
   - Persistent multi-layer relays to protect the path
     to Introduction Points
   - Prevents the adversary from discovering the HS's IP via
     selective DoS of Introduction Points
```

---

## 7. Browser attacks (exploits)

### Freedom Hosting (2013)

The FBI compromised the Freedom Hosting server (which hosted hidden services)
and injected a JavaScript exploit into the Tor Browser (based on Firefox ESR 17):

```
Technique:
  1. The FBI gained control of the Freedom Hosting server
  2. Injected malicious JavaScript code into served pages
  3. The exploit leveraged CVE-2013-1690 (Firefox ESR 17)
  4. The payload:
     a. Bypassed the browser sandbox
     b. Executed native code (shellcode)
     c. Retrieved the victim's real IP
     d. Retrieved the MAC address
     e. Retrieved the computer's hostname
     f. Sent the data to an FBI server (IP: 65.222.202.54)
  5. Worked only on Windows (the payload was a PE)
  6. On Linux/macOS: the exploit had no effect

Result:
  - Hundreds of Freedom Hosting users identified
  - Multiple arrests for CSAM possession
  - Eric Eoin Marques (Freedom Hosting operator) arrested
```

### Playpen (2015)

```
The FBI used a similar technique to identify Playpen users:
  1. Took control of the Playpen server (CSAM hidden service)
  2. Operated the site for 13 days
  3. Deployed a NIT (Network Investigative Technique)
     via browser exploit
  4. The NIT retrieved real IP, MAC, hostname
  5. ~8,700 IPs collected, 137 indicted

Legal controversy:
  - The FBI operated a CSAM site for 13 days
  - Debate over the legality of the operation
  - NITs were challenged in court
  - Some cases dismissed for Fourth Amendment violations
```

### Countermeasures

```
1. Frequent updates:
   - Tor Browser follows the Firefox ESR cycle (~6 weeks)
   - Security patches applied immediately
   - RULE: ALWAYS update as soon as available

2. Security Level:
   - "Safest" disables JavaScript → eliminates the attack surface
   - "Safer" disables JIT → eliminates JIT-based exploits

3. Sandboxing:
   - Tor Browser uses Firefox sandboxing (seccomp-bpf on Linux)
   - Limits the syscalls available to the exploit
   - Not impenetrable but raises the bar

4. System isolation:
   - On Tails/Whonix: even a browser exploit does not reveal the IP
   - The system firewall forces all traffic through Tor
   - The exploit cannot bypass the Gateway firewall

5. NoScript:
   - Blocks JavaScript by default at Safer/Safest levels
   - Drastically reduces the attack surface
```

---

## 8. Supply chain attacks

### Scenario

An adversary compromises the build process of Tor or Tor Browser to insert
backdoors in the distributed software.

```
Possible vectors:
  1. Compromise of the Git repository
  2. Compromise of the build server
  3. Compromise of maintainers (social engineering, coercion)
  4. Compromise of the distribution channel (mirrors, CDN)
  5. Insertion of malicious dependencies (dependency confusion)
```

### Countermeasures

```
1. Reproducible builds:
   - Tor Browser supports reproducible builds
   - Anyone can recompile the source code
   - The resulting binary must be bit-for-bit identical
   - If it doesn't match → the build has been compromised

2. GPG signatures:
   - All downloads are signed with the Tor Project's keys
   - Keys are published and verifiable
   - The Tor Browser download manager verifies the signature

3. Open source code:
   - The code is public and auditable
   - Developer community that reviews changes
   - Bug bounty program

4. Documented build process:
   - The build process is publicly documented
   - Uses Docker containers for isolation
   - Verifiable build logs
```

---

## 9. BGP routing attacks (RAPTOR)

### How it works

```
Sun et al. (2015): "RAPTOR: Routing Attacks on Privacy in Tor"

The adversary exploits the BGP protocol to observe Tor traffic:

Attack 1 - BGP Hijacking:
  1. The adversary announces more specific BGP routes
     for a Tor Guard's IP range
  2. Client→Guard traffic is redirected through
     the adversary's AS (man-in-the-middle at the routing level)
  3. The adversary observes incoming traffic
  4. Combined with egress-side observation → correlation

Attack 2 - Asymmetric routing:
  1. BGP paths are often asymmetric
     (A→B passes through different ASes than B→A)
  2. The adversary can observe only one direction
  3. But even one direction is sufficient for correlation

Attack 3 - BGP interception:
  1. The adversary redirects traffic, observes it, and releases it
  2. The client notices nothing (slightly increased latency)
  3. Completely passive attack from the victim's perspective
```

### Effectiveness

```
- >90% of Tor circuits vulnerable to routing attacks
- A single AS in a strategic position can observe
  a significant percentage of Tor traffic
- Does not require control of Tor relays
- Difficult to detect from the client
```

### Countermeasures

```
- Persistent guard: reduces the vulnerability window
  (the adversary must maintain the BGP hijack for weeks)
- RPKI (Resource Public Key Infrastructure):
  - Cryptographic signing of BGP routes
  - Prevents unauthorized BGP hijacking
  - Adoption growing but not universal
- BGP monitoring:
  - RIPE RIS, RouteViews monitor BGP routes
  - Routing anomalies can be detected
- AS-diversity-based relay selection:
  - Tor selects relays in different ASes
  - Reduces the probability that a single AS observes the entire circuit
```

---

## 10. Sniper Attack

### How it works

```
Jansen et al. (2014): "The Sniper Attack"

The adversary forces a Tor relay to exhaust its memory (OOM kill):

1. The adversary creates a circuit through the victim relay
2. Sends data to the relay but DOES NOT read the response
3. Data accumulates in the relay's buffers
4. The relay exhausts its memory → crash or OOM kill
5. If the relay is the victim's Guard:
   → The victim must choose a new Guard
   → If the new Guard is malicious → compromise

Cost for the adversary: minimal (sends data, does not read)
Cost for the victim: relay crash, loss of circuits
```

### Countermeasures

```
- Improved flow control (SENDME cells):
  - Relays no longer send more data than the receiver acknowledges
  - Prevents infinite data accumulation in buffers
  
- OOM handler:
  - Tor detects memory exhaustion
  - Closes the most problematic circuits instead of crashing
  
- Circuit-level flow control (Prop #324):
  - Congestion control at the circuit level
  - Prevents a single circuit from monopolizing resources
```

---

## 11. Attacks on Onion Services

### Vanguards

```
Problem:
  An adversary who controls the HS Directory can observe
  requests and correlate with circuits.
  Selective DoS of Introduction Points can reveal
  the HS's location.

Solution - Vanguards (Tor 0.4.1+):
  The HS uses persistent "vanguard" relays for circuits
  toward Introduction Points:

  HS → [Layer 1 Vanguard] → [Layer 2 Vanguard] → [Introduction Point]
  
  - Layer 1: persists for months (like a Guard)
  - Layer 2: persists for days
  - The adversary must compromise both layers
  - Much harder than compromising a single relay

Vanguards-lite (Tor 0.4.7+):
  - Simplified version enabled by default
  - Protects all onion services
  - A single vanguard layer
```

### Onion Service Directory (HSDirs) Attack

```
The adversary positions relays as HSDir for a given .onion:

v2 (vulnerable):
  - The adversary calculates which relays will be HSDir for a .onion
  - Positions relays in those slots
  - Sees every request for that .onion
  → Enumeration and surveillance possible

v3 (mitigated):
  - Encrypted descriptors (HSDir cannot read)
  - Blinded keys (HSDir does not know which .onion)
  - Rotation based on time period
  → The attack is much harder/costlier
```

---

## Attack and countermeasure matrix

| Attack | Required adversary | Tor countermeasure | Countermeasure effectiveness | Year discovered |
|--------|-------------------|-------------------|----------------------------|----------------|
| Sybil | Resources for ~100+ relays | DA monitoring, family, /16 rule | Medium | 2014 |
| Relay Early Tagging | Control of middle+exit relays | RELAY_EARLY counting, conversion | High | 2014 |
| End-to-end correlation | Observation of ingress+egress | Padding (limited) | Low | 2004 |
| Website Fingerprinting | Local observation (ISP) | Circuit padding (in development) | Medium | 2011 |
| HSDir Enumeration | Control of HSDir relays | v3 encrypted descriptors, rotation | High | 2016 |
| Relay DoS | Bandwidth for DDoS | PoW, rate limiting | Medium | 2021 |
| Browser exploit | 0-day in the browser | Updates, Security Level | Medium | 2013 |
| Supply chain | Access to the build system | Reproducible builds, GPG | High | - |
| BGP routing | Control of AS/IXP | Persistent guard, AS diversity | Low | 2015 |
| Sniper attack | Malicious circuit | Flow control, OOM handler | High | 2014 |
| HS enumeration | HSDir relays | Onion Services v3 | High | 2016 |

---

## Tor countermeasure timeline

```
2012  Persistent Guard (reduces exposure to malicious relays)
2014  RELAY_EARLY counting (anti-tagging)
2014  Removal of CMU/FBI relays
2015  Improved Guard selection (path bias tracking)
2017  Onion Services v3 (encrypted descriptors, blinded keys)
2018  Connection padding (dummy cells between relays)
2019  Vanguards for onion services
2020  Circuit padding framework
2021  Removal of KAX17 relays
2021  Vanguards-lite (default for all HS)
2022  Congestion control (Prop #324)
2023  Proof-of-Work for onion services (anti-DoS)
2024  Continued removal of malicious relays
```

---

## Practical conclusion

No system is invulnerable. Tor offers significant protection against mass
surveillance and local adversaries, but has documented limitations against
adversaries with significant resources.

### For my use case

For ISP privacy and security testing, Tor's protections are more than
sufficient. The most likely adversary (ISP, web trackers) does not have the
resources for the attacks described above.

### For high-risk scenarios

For journalism in authoritarian regimes, whistleblowing, or activism,
additional countermeasures are necessary:
- Tails or Whonix (protection from browser exploits)
- Rigorous OPSEC (technology does not compensate for human errors)
- Tor Browser at Safest level (no JavaScript)
- obfs4 or Snowflake bridges (hide Tor usage)
- Immediate updates (security patches)

The most important lesson from the history of attacks: **in the majority of
cases, deanonymization occurs due to OPSEC mistakes, not technical
vulnerabilities in Tor**.

---

## See also

- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - End-to-end correlation, website fingerprinting
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Human errors that cause deanonymization
- [Protocol Limitations](limitazioni-protocollo.md) - Architectural limits of Tor
- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) - v3 protections against HSDir attacks
- [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) - Persistent selection as a defense
- [Bridges and Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Defense from censorship and DPI
- [Isolation and Compartmentalization](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Whonix/Tails as defense from exploits
