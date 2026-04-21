> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/traffic-analysis.md) | English

# Traffic Analysis and Correlation Attacks

This document analyzes how an adversary can attempt to deanonymize Tor users
through traffic analysis, even without decrypting the content. It includes end-to-end
correlation attacks, website fingerprinting, timing attacks, and the defenses
implemented by Tor. For each attack, I analyze the technique, the effectiveness
documented by academic research, and the available countermeasures.

---

## Table of Contents

- [Tor's threat model](#tors-threat-model)
- [End-to-end correlation attack](#end-to-end-correlation-attack)
- [Website Fingerprinting](#website-fingerprinting)
**Deep dives** (dedicated files):
- [Traffic Analysis - Timing, NetFlow and Defenses](traffic-analysis-attacchi-e-difese.md) - Timing, NetFlow, active attacks, circuit padding, defenses

---

## Tor's threat model

Tor is designed to resist an adversary that:
- Can observe **part** of the network (not all of it)
- Controls **some** relays (not the majority)
- Can analyze traffic passively

Tor is **NOT** designed to resist an adversary that:
- Observes **all** Internet traffic (global passive adversary - GPA)
- Controls both the Guard and the Exit of your circuit
- Can perform large-scale correlation in real time
- Has active traffic manipulation capabilities

### The formal threat model

```
Tor provides:
✓ Sender anonymity (the server does not know who you are)
✓ Recipient anonymity (onion services)
✓ Resistance to mass surveillance (too costly to correlate everyone)
✓ Unlinkability (different sessions are not correlatable)

Tor does NOT provide:
✗ Resistance to the global adversary (who sees everything)
✗ Resistance to end-to-end correlation (who sees ingress and egress)
✗ Resistance to perfect website fingerprinting (local attack)
✗ Resistance to active attacks (traffic manipulation)
```

---

## End-to-end correlation attack

### How it works

If the adversary can observe traffic **entering** at the Guard and **exiting**
from the Exit, they can correlate the temporal patterns:

```
Observation on client side (Guard):
t=0.000  [burst: 5 cells in, 0 out]
t=0.050  [burst: 3 cells in, 2 out]
t=0.120  [burst: 8 cells in, 0 out]
t=0.500  [pause: 380ms without traffic]
t=0.550  [burst: 2 cells in, 5 out]

Observation on server side (Exit):
t=0.150  [burst: 5 cells in, 0 out]    ← +150ms
t=0.200  [burst: 3 cells in, 2 out]    ← +150ms
t=0.270  [burst: 8 cells in, 0 out]    ← +150ms
t=0.650  [pause: 380ms without traffic] ← same duration!
t=0.700  [burst: 2 cells in, 5 out]    ← +150ms

Statistical correlation:
  - Patterns are identical with a ~150ms delay
  - Pause distribution is identical
  - Burst direction is identical
  → >95% probability that they are the same flow
  → The user at the Guard is communicating with the server observed at the Exit
```

### Why it works

Tor cells have a fixed size (514 bytes), but this is not enough to prevent
correlation. The information that leaks:

```
1. Volume: the NUMBER of cells per unit of time varies
   → A web page with 50 images generates more cells than one with 2
   → Volume reveals the "weight" of the communication

2. Direction: the DIRECTION of cells (in vs out) creates a pattern
   → Download: many cells in, few out
   → Upload: many cells out, few in
   → Chat: balanced distribution

3. Timing: PAUSES between bursts are correlatable
   → User clicks a link → pause → data burst
   → The human interaction pattern is unique
   → Even network jitter does not hide macro-pauses

4. Burst structure: the STRUCTURE of bursts
   → HTTP/1.1: request → response → request → response
   → HTTP/2: multiplexed requests → complex burst
   → The application protocol creates specific patterns
```

### Required conditions

The adversary must control or observe:

```
Scenario 1 (passive observation):
  - The link between the client and the Guard (e.g., the client's ISP)
  - The link between the Exit and the destination (e.g., the server's ISP)
  → Possible for collaborating ISPs

Scenario 2 (malicious relays):
  - Control the Guard relay itself
  - Control the Exit relay itself
  → Possible with Sybil attack (see attacchi-noti.md)

Scenario 3 (CDN):
  - Cloudflare sees ~15-20% of web traffic
  - If your ISP collaborates AND the site uses Cloudflare → correlation
  → Possible for an adversary with access to CDN + ISP

Scenario 4 (IXP):
  - An Internet Exchange Point sees traffic from many ISPs
  - A large IXP can observe both the Guard side and the Exit side
  → Possible for adversaries with IXP access
```

### Documented effectiveness

Academic research shows:

```
Murdoch & Danezis (2005): first correlation attacks
  - ~50% true positive with a few minutes of observation
  
Levine et al. (2004): "Timing Attacks in Low-Latency Mix Systems"
  - >80% true positive rate
  - Cell-level padding is not sufficient

Johnson et al. (2013): "Users Get Routed"
  - Simulation on real Tor network
  - >80% of users deanonymized in 6 months
  - Persistent Guard helps but does not eliminate the risk

Nasr et al. (2018): "DeepCorr"
  - Deep learning for correlation
  - >96% true positive with <0.1% false positive
  - Works even with Tor circuit padding
  - Requires only 25 seconds of observation
```

### Fundamental limitation

**Tor is not designed to resist end-to-end correlation.**
This is a declared, known limitation that is probably unsolvable
for a low-latency network. Countermeasures (padding, batching) make
the attack more costly but do not prevent it.

---

## Website Fingerprinting

### How it works

An adversary who can observe only the client→Guard link (e.g., the ISP) can
determine which site you are visiting based on **traffic patterns**:

```
Training phase:
1. The adversary visits thousands of websites via Tor
2. For each site, records the traffic "fingerprint":
   - Sequence of packet sizes
   - Sequence of directions (in/out)
   - Timing between packets
   - Total number of packets
   - Burst patterns
3. Trains a classifier (machine learning) on these fingerprints

Attack phase:
1. The adversary observes your client→Guard traffic
2. Extracts the same features
3. The classifier compares with known fingerprints
4. Returns: "The user is visiting Site X with 93% probability"
```

### Why it works

Every website has a unique "traffic fingerprint":

```
Google.com:
  [in: 5 cells] [out: 2] [in: 15] [out: 3] [in: 50] [out: 5]
  Total: ~80 cells, in/out ratio: 7:1

Wikipedia.org (long article):
  [in: 5 cells] [out: 2] [in: 200] [out: 8] [in: 30] [out: 2]
  Total: ~247 cells, in/out ratio: 23:1

GitHub.com (repository):
  [in: 5 cells] [out: 3] [in: 40] [out: 10] [in: 60] [out: 15]
  Total: ~133 cells, in/out ratio: 3.5:1

Fingerprints differ based on:
- Number of loaded resources (CSS, JS, images)
- Resource sizes
- Loading order (determined by HTML)
- HTTP/1.1 vs HTTP/2 protocol (different multiplexing)
```

### Accuracy (from academic research)

**Closed world** (the adversary knows all possible sites):

```
Panchenko et al. (2016): "Website Fingerprinting at Internet Scale"
  - SVM classifier
  - >90% accuracy on 100 monitored sites

Sirinam et al. (2018): "Deep Fingerprinting"
  - CNN (deep learning)
  - >98% accuracy on 95 sites (closed world)
  - ~95% with multiple tabbing

Rahman et al. (2020): "Tik-Tok"
  - Uses timing features
  - >96% accuracy
```

**Open world** (the user can visit any site):

```
In real-world conditions:
  - 60-80% true positive rate (identifies the correct site)
  - 5-15% false positive rate
  - Degrades significantly with:
    → Multi-tab browsing (noise from concurrent traffic)
    → Background traffic (downloads, updates)
    → CDN and A/B testing (pages served differently)
    → Dynamic and personalized content
    → Different ads per session
  - Computational cost is high for large-scale monitoring
```

### Defenses against website fingerprinting

**Circuit-level padding**: Tor can insert dummy cells to alter patterns.
"Circuit padding machines" add configurable padding for specific circuit
types (e.g., rendezvous for hidden services).

**WTF-PAD** (Wang & Goldberg, 2017):
```
- Adds adaptive padding based on a state machine
- Observes gaps between packets and inserts padding in the gaps
- Reduces WF accuracy by ~20-30%
- Bandwidth overhead: ~60%
```

**FRONT** (Gong & Wang, 2020):
```
- Adds padding only to the "front" of the trace (first packets)
- Classifiers depend heavily on the first packets
- Reduces accuracy by ~40% with only ~30% overhead
```

**Practical limitation**: padding sufficient to defeat website fingerprinting
would require a significant bandwidth increase (~50-100%), which volunteers
cannot sustain. The Tor Project balances security and cost.


---

> **Continues in**: [Traffic Analysis - Timing, NetFlow and Defenses](traffic-analysis-attacchi-e-difese.md)
> for timing attacks, NetFlow, active attacks, circuit padding and countermeasures.

---

## See also

- [Traffic Analysis - Timing, NetFlow and Defenses](traffic-analysis-attacchi-e-difese.md) - Timing, NetFlow, attacks, padding, defenses
- [Known Attacks](../07-limitazioni-e-attacchi/attacchi-noti.md) - CMU/FBI, Freedom Hosting, Sybil
- [Fingerprinting](fingerprinting.md) - Browser, TLS/JA3, OS fingerprinting
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Behavioral defenses
- [Protocol Limitations](../07-limitazioni-e-attacchi/limitazioni-protocollo.md) - Technical limits of Tor
- [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) - Whonix, Tails for high-risk scenarios
- [Real-World Scenarios](scenari-reali.md) - Operational cases from a pentester
