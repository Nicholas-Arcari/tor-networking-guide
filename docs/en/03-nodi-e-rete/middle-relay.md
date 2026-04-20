> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/middle-relay.md) | English

# Middle Relay - The Invisible Node

This document analyzes the role of Middle Relays in the Tor circuit, the selection
algorithm, bandwidth weighting, and why middle nodes are fundamental to anonymity
despite being the least "visible" component of the architecture.

---
---

## Table of Contents

- [Role of the Middle Relay](#role-of-the-middle-relay)
- [Middle Relay selection algorithm](#middle-relay-selection-algorithm)
- [Bandwidth Weights and balancing](#bandwidth-weights-and-balancing)
- [Middle Relays in extended circuits](#middle-relays-in-extended-circuits)
- [Attacks involving Middle Relays](#attacks-involving-middle-relays)
- [Contributing as a Middle Relay](#contributing-as-a-middle-relay)
- [Summary](#summary)


## Role of the Middle Relay

The Middle Relay is the **second node** in the standard 3-hop Tor circuit:

```
[You] ──► [Guard] ──► [Middle] ──► [Exit] ──► [Internet]
```

### What the Middle knows

| Information | Visible to the Middle? |
|-------------|----------------------|
| Your real IP | **NO** - only sees the Guard's IP |
| The final destination | **NO** - only sees the Exit's IP |
| The traffic content | **NO** - sees cells encrypted with 2 layers |
| The traffic volume | **YES** - sees the number of cells transiting |
| The traffic timing | **YES** - sees when cells transit |
| The Guard's identity | **YES** - it is the direct TLS connection |
| The Exit's identity | **YES** - it is the direct TLS connection |

### The separation function

The Middle Relay exists to **separate** the Guard from the Exit. Without the middle:

```
2-hop circuit (INSECURE):
[You] ──► [Guard+Exit] ──► [Internet]
The Guard knows both you and the destination → no anonymity
```

With the middle:
```
3-hop circuit:
[You] ──► [Guard] ──► [Middle] ──► [Exit] ──► [Internet]
Guard knows you but not the destination
Exit knows the destination but not you
Middle knows neither
```

The middle prevents the Guard from correlating your traffic with the destination,
and the Exit from tracing back to you.

---

## Middle Relay selection algorithm

### Bandwidth-weighted selection

The middle is chosen from the consensus with probability proportional to the
relay's **measured bandwidth**. A relay with 10 MB/s of bandwidth has 10 times
the probability of being selected compared to a relay with 1 MB/s.

Simplified formula:
```
P(relay_i as middle) = BW_i * Wmm / Σ(BW_j * Wmj for all eligible relays j)
```

Where:
- `BW_i` = bandwidth of relay i in the consensus
- `Wmm` = bandwidth weight for middle relay (from the consensus)

### Selection constraints

Tor applies constraints to prevent the circuit from being compromised:

1. **Not in the same family**: if the Guard and the candidate middle have declared
   a common `MyFamily`, the candidate is excluded.

2. **Not in the same /16 subnet**: if the Guard is in `198.51.100.0/16` and the
   candidate middle is in `198.51.200.0/16`, it is excluded. This reduces the risk
   that both are in the same datacenter/ISP.

3. **Not the same relay**: obviously, the middle cannot be the same relay as the
   guard or the exit.

4. **No flag required**: unlike guards and exits, a middle relay does not require
   specific flags. Any relay with `Running` and `Valid` can be a middle.

### Why middles have no dedicated flag

Guards have the `Guard` flag (requires stability). Exits have the `Exit` flag
(requires an exit policy). Middles have no special requirements because:

- Their function is pure transit - no particular properties are needed
- Having a broad pool of middles improves anonymity (more possible relays)
- Bandwidth-weighted selection automatically balances the load

---

## Bandwidth Weights and balancing

### The balancing problem

The Tor network has unbalanced proportions of guards, middles, and exits:
- **Guard**: ~40% of relays with the Guard flag
- **Exit**: ~15-20% of relays with the Exit flag (exits are few because they
  require a permissive exit policy, which exposes the operator to legal risks)
- **Middle**: all relays

If selection were purely proportional to bandwidth, exits would be overloaded
(few relays, heavy traffic). The **bandwidth weights** in the consensus solve this:

```
bandwidth-weights Wbd=0 Wbe=0 Wbg=4203 Wbm=10000 Wdb=10000 Web=10000 
Wed=10000 Weg=10000 Wem=10000 Wgb=10000 Wgd=0 Wgg=5797 Wgm=5797 
Wmb=10000 Wmd=10000 Wme=10000 Wmg=4203 Wmm=10000
```

### Meaning of the weights

- `Wgg=5797` → a relay with the Guard flag is selected as guard with weight 5797/10000
- `Wmg=4203` → a relay with the Guard flag is selected as middle with weight 4203/10000
- `Wmm=10000` → a relay without Guard/Exit flags is selected as middle with full weight

This means that relays with the Guard flag are also used as middles (but with
reduced weight), to balance the load. Similarly, Exit relays can be used as middles.

### Practical implication

The relay acting as middle in your circuit could be:
- A "pure" relay without any particular flags
- A relay with the Guard flag (but selected as middle this time)
- A relay with the Exit flag (but selected as middle this time)

---

## Middle Relays in extended circuits

### 3-hop circuits (standard)

For normal internet traffic, the circuit is always 3 hops: guard → middle → exit.
A single middle relay.

### Hidden Service circuits (up to 6 hops)

When a client connects to an onion service, the circuits are longer:

```
Client → Guard → Middle → Rendezvous Point
                                   ↕
Hidden Service → Guard → Middle → Rendezvous Point
```

In this case there are **two middle relays** (one for the client's circuit, one for
the hidden service's circuit), plus the rendezvous point (which is also a relay).

### Circuits with Vanguards

With vanguards active, the "middles" become more structured:

```
Client → Guard (L1) → Middle L2 → Middle L3 → Exit/RP
```

The L2 and L3 middles have different rotation times, adding complexity for anyone
attempting to correlate traffic.

---

## Attacks involving Middle Relays

### 1. Correlation attack via controlled middle

If the adversary controls a middle and observes traffic between guard and middle
and between middle and exit, they can correlate temporal patterns to link client
and destination.

**Mitigation**: the volume of multiplexed traffic on each TLS connection makes
per-circuit correlation very difficult (hundreds of circuits on the same connection).

### 2. Middle as a sniffing point

A malicious middle could attempt to:
- Count cells to estimate traffic volume
- Measure latency toward the guard and exit
- Collect statistical metadata

But it **cannot** decrypt the content (encrypted with 2 layers of AES-128-CTR
that it does not possess).

### 3. Relay early tagging attack

Historically (before Tor 0.2.4.23), a middle relay could send forged `RELAY_EARLY`
cells to "tag" a circuit. A malicious exit could recognize the tag and confirm that
a certain client was using that circuit.

This attack was used in 2014 to deanonymize users of hidden services. Since then:
- RELAY_EARLY cells are counted and limited
- Relays that send anomalous RELAY_EARLY cells are flagged
- The client verifies cell consistency

---

## Contributing as a Middle Relay

Operating a middle relay is the safest way to contribute to the Tor network:

- **No legal risk**: traffic that transits is always encrypted. You cannot see
  nor be held responsible for the content.
- **Minimal hardware requirements**: even an inexpensive VPS can be a useful middle relay.
- **Helps the network**: more middle relays = more diversity = more anonymity for everyone.

### Minimal configuration for a middle relay

```ini
# torrc for middle relay (non-exit)
ORPort 9001
Nickname MyMiddleRelay
ContactInfo email@example.com
ExitPolicy reject *:*           # Do NOT be an exit
RelayBandwidthRate 1 MB
RelayBandwidthBurst 2 MB
```

I have not activated a relay in my configuration because I use Tor as a client, but it
is an interesting option for contributing to the network.

---

## Summary

| Property | Guard | Middle | Exit |
|----------|-------|--------|------|
| Knows your IP | YES | NO | NO |
| Knows the destination | NO | NO | YES |
| Sees the content | NO | NO | Only if not HTTPS |
| Required flag | Guard | None | Exit |
| Persistence | Months | None (changes every circuit) | None |
| Candidate pool | ~1500 | ~6000+ | ~1000-1500 |
| Risk for the operator | Low | Minimal | High (possible abuse) |

---

## See also

- [Guard Nodes](guard-nodes.md) - First hop of the circuit
- [Exit Nodes](exit-nodes.md) - Third hop of the circuit
- [Consensus and Directory Authorities](../01-fondamenti/consenso-e-directory-authorities.md) - Bandwidth weights and selection
- [Relay Monitoring and Metrics](relay-monitoring-e-metriche.md) - Monitoring your own middle relay
- [Known Attacks](../07-limitazioni-e-attacchi/attacchi-noti.md) - Relay early tagging from the middle
