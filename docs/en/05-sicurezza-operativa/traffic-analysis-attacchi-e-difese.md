> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/traffic-analysis-attacchi-e-difese.md) | English

# Traffic Analysis - Timing, NetFlow and Defenses

Timing attacks (flow watermarking, clock skew, inter-packet), NetFlow analysis,
active attacks (replay, dropping, tagging), Tor's circuit padding framework,
documented practical attacks and countermeasures.

> **Extracted from**: [Traffic Analysis and Correlation Attacks](traffic-analysis.md)
> for end-to-end correlation and website fingerprinting.

---


### Flow watermarking

An adversary who controls an intermediate relay can "mark" the flow with artificial
timing patterns:

```
Original flow:  [pkt][pkt][pkt][pkt][pkt][pkt][pkt][pkt]
                ||||||||||||||||||||||||||||||||||||||||

Marked flow:    [pkt][DELAY 20ms][pkt][pkt][DELAY 20ms][pkt][pkt][DELAY 20ms]
                |||               ||||||               ||||||
                Pattern: 1-2-2-2-2-... (binary watermark)

The adversary:
1. The malicious middle relay inserts specific delays
2. The delay pattern encodes a "tag" (e.g., circuit ID)
3. An observer at another point in the network detects the pattern
4. The pattern survives through Tor hops
5. → Correlation: the marked circuit belongs to user X
```

### Clock skew fingerprinting

Every computer has a slightly different clock (clock skew). By measuring
TCP timestamps:

```
The server sends a packet and receives the response.
The RTT should be constant, but the client's clock skew
causes systematic variations.

Client A clock skew: +2.3 ppm (parts per million)
Client B clock skew: -1.7 ppm

If the adversary measures the clock skew of your Tor traffic
and compares it with non-Tor traffic from the same computer:
→ Correlation via clock skew
```

### Inter-packet timing analysis

```
Even with fixed-size cells (514 bytes), the TIMING between cells reveals:

1. Typing patterns (chat, SSH):
   - Each keystroke generates a packet
   - The delay between keystrokes is unique for each person
   - "the" → 3 packets with specific timing
   
2. Application behavior:
   - HTTP/1.1: sequential request-response → regular pattern
   - HTTP/2: multiplexed → irregular bursts
   - Video streaming: periodic bursts every X seconds
   
3. User interaction:
   - Click → pause → scroll → pause → click
   - The interaction pattern is a behavioral fingerprint
```

### Defenses against timing attacks

```
1. Fixed-size cells (already implemented in Tor):
   → No information from packet size
   → But timing between cells remains informative

2. Connection padding (implemented in Tor):
   → Dummy cells sent periodically on TLS connections between relays
   → Hides pauses in traffic
   → Contained overhead (~5%)

3. Circuit padding (partially implemented):
   → Circuit-specific dummy cells
   → Currently used to protect HS rendezvous
   → In the future: extension to general circuits

4. Multiplexing (already implemented):
   → Multiple circuits on the same TLS connection
   → Patterns from one circuit are mixed with those from others
   → But a sophisticated adversary can demultiplex
```

---

## NetFlow Analysis

### How it works

Backbone routers maintain NetFlow records that include:
- Source and destination IP
- Source and destination ports
- Number of packets and bytes
- Start and end timestamps
- Protocol

```
An adversary with access to NetFlow from multiple ISPs/IXPs can:

1. Identify client → Tor Guard flows (Guard IP is known)
2. Identify Tor Exit → destination server flows
3. Correlate by timing and volume

Example:
  NetFlow client ISP: 151.x.x.x → Guard (185.y.y.y)
    Start: 14:30:00, End: 14:45:00, Bytes: 2.3 MB
    
  NetFlow server ISP: Exit (104.z.z.z) → Server (93.w.w.w)
    Start: 14:30:05, End: 14:44:55, Bytes: 2.1 MB
    
  Correlation: similar timing, similar volume
  → High probability that 151.x.x.x is communicating with 93.w.w.w
```

### Effectiveness

```
Chakravarty et al. (2014): "Traffic Analysis against Low-Latency Anonymity Networks"
  - Uses NetFlow data from a single AS
  - ~81% true positive rate for long-duration flows (>5 minutes)
  
Johnson et al. (2013): "Users Get Routed"
  - Modeling with real AS paths
  - A single AS that observes many Tor connections
    can deanonymize a significant percentage of users
  - The AS hosting the Guard and the AS of the destination are critical points
```

### Why it is relevant

```
- NetFlow data is routinely retained by providers
- Intelligence agencies have access to backbone NetFlow
- The NSA "XKeyscore" program collected global network metadata
- NetFlow data does not require deep packet inspection
- Metadata alone (timing, volume, IP) is sufficient
```

---

## Active traffic manipulation attacks

### Replay attack

```
A malicious relay records cells and re-sends them later.
If the adversary observes the circuit at another point:
- Sees the duplicate cells
- Can correlate the two observation points

Countermeasure: Tor detects and discards duplicate cells through
sequence numbering (RELAY_EARLY counting, digest check)
```

### Dropping attack

```
A malicious relay selectively drops cells in specific circuits.
If the client creates a new circuit (because the first fails):
- The new circuit might pass through different relays
- The adversary observes the sequence of attempts
- Failure pattern → circuit fingerprint

Countermeasure: Path Bias (Tor monitors circuits that fail
too often and penalizes suspicious relays)
```

### Tagging attack

```
A malicious relay modifies data in cells (bit flip):
- Relay A flips a bit in the encrypted cell
- Relay B (controlled by the same adversary) checks the bit
- If the bit is flipped → the circuit passes through A and B
- → Correlation: the adversary knows this circuit is of interest

Countermeasure: the digest in RELAY cells detects modifications.
If the digest is wrong, the circuit is closed.
```

---

## Tor's circuit padding framework

### How it works

The Tor Project has implemented a "circuit padding framework" that allows
defining state machines for padding:

```
A padding machine defines:
- States (e.g., START, BURST_DETECTED, PADDING, END)
- State transitions (based on traffic events)
- Actions for each state (send padding, wait, etc.)
- Timing distributions for padding

Example (simplified):
  State: IDLE
    On: cells received from the other side → goto PADDING
  
  State: PADDING
    Action: send 5-15 dummy cells with 0-50ms delay
    On: 100ms timeout → goto IDLE
    On: real cells received → reset timer

Currently implemented:
1. HS rendezvous padding:
   - Protects circuits to hidden services
   - Adds padding during the rendezvous phase
   - Makes it harder to identify connections to .onion

2. Connection padding:
   - Padding cells on TLS connections between relays
   - Sent periodically during pauses
   - Hides the activity/inactivity pattern
```

### Current effectiveness

```
- Reduces website fingerprinting accuracy by ~10-20%
- Bandwidth overhead: ~5-10% for connection padding
- Significant protection for HS rendezvous
- NOT sufficient to completely defeat WF
- In continuous development: new padding machines planned
```

---

## Documented practical attacks

### Operation Onymous (2014)

Law enforcement seized dozens of hidden services (darknet markets).
The exact method was not disclosed, but a combination is suspected of:
- Malicious relays (relay early tagging)
- Traffic correlation
- Operator OPSEC errors
- Possible web application exploit (not Tor itself)

### Carnegie Mellon / FBI (2014)

Carnegie Mellon University researchers executed a Sybil attack
(~115 malicious relays) combined with relay early tagging to
deanonymize hidden service users:

```
Technique:
1. Inserted ~115 relays with HSDir and Guard flags
2. The relays used RELAY_EARLY tagging to mark circuits
3. When a client connected to an HS, the malicious relay
   inserted a tag in RELAY_EARLY cells
4. Another malicious relay recognized the tag
5. → Correlation: this client visits this hidden service

Consequences for Tor:
- RELAY_EARLY cells are now limited and monitored (max 8 per circuit)
- Guard selection has been improved
- Vanguards developed for hidden services
- Active monitoring for mass relay insertions
```

### RAPTOR (2015)

```
Sun et al. (2015): "RAPTOR: Routing Attacks on Privacy in Tor"
  
Attack that exploits BGP routing to direct Tor traffic
through adversary-controlled ASes:

1. BGP hijacking: the adversary announces more specific routes
   for Tor Guard IPs
2. Client→Guard traffic is redirected through the adversary's AS
3. The adversary can now observe ingress traffic
4. Combined with exit-side observation → end-to-end correlation

Effectiveness: >90% of Tor circuits vulnerable to BGP routing attacks
```

---

## Defenses and countermeasures

### What I can do to protect myself

**1. Use Tor Browser (not Firefox+proxychains)**
Tor Browser has built-in padding and anti-fingerprinting. Circuit padding
machines protect specific circuit types.

**2. Avoid predictable traffic patterns**
Do not always visit the same sites at the same time via Tor. Variation
in patterns makes correlation harder.

**3. Use obfs4 bridges**
They hide from the ISP that you are using Tor. The ISP does not even know
where to start traffic analysis because the traffic looks like generic HTTPS.

**4. Do not mix anonymous and non-anonymous traffic**
Do not use Tor and non-Tor on the same network simultaneously if you are
concerned about a local adversary.

**5. Consider Tails or Whonix**
For high-risk scenarios, dedicated operating systems offer complete
traffic isolation and prevent leaks.

**6. Short sessions**
Shorter sessions provide less data for correlation.
Use NEWNYM between different activities.

**7. Avoid prolonged interactive sessions**
Chat and SSH via Tor are particularly vulnerable to timing analysis
(each keystroke generates a packet with unique timing).

### What CANNOT protect me

```
No countermeasure can:
- Protect from a global passive adversary with mathematical certainty
- Completely eliminate website fingerprinting
- Make SSH sessions via Tor safe from timing analysis
- Prevent correlation if Guard AND Exit are compromised
```

---

## In my experience

For my use case (ISP privacy, security testing, study), traffic
analysis is not a primary concern. My main adversary is the ISP
and web trackers, not an intelligence agency. But understanding these attacks
is essential to correctly evaluate the level of protection Tor offers.

The key points I have internalized:
1. Tor protects against **mass** surveillance, not **targeted** surveillance
2. End-to-end correlation is the fundamental limitation of low-latency networks
3. Website fingerprinting is a real but mitigable risk (Tor Browser)
4. obfs4 bridge is the most practical defense against the local ISP
5. Human OPSEC matters more than any technical defense

---

## See also

- [Known Attacks](../07-limitazioni-e-attacchi/attacchi-noti.md) - CMU/FBI, Freedom Hosting, Sybil
- [Fingerprinting](fingerprinting.md) - Browser, TLS/JA3, OS fingerprinting
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Behavioral defenses
- [Protocol Limitations](../07-limitazioni-e-attacchi/limitazioni-protocollo.md) - Technical limits of Tor
- [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) - Whonix, Tails for high-risk scenarios
- [Bridges and Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - obfs4 bridge as ISP defense
