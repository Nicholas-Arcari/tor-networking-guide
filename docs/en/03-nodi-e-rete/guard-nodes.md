> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/guard-nodes.md) | English

# Guard Nodes - The First Link in the Chain

This document provides an in-depth analysis of the role, selection, persistence, and
risks of Guard Nodes (Entry Nodes) in the Tor network. Guards are the most critical
component of the circuit from a user security perspective, because they are the only
node that knows our real IP address.

It includes observations from my experience with guard selection, guard changes after
resets, and performance impact.

---
---

## Table of Contents

- [Role of the Guard Node](#role-of-the-guard-node)
- [Entry Guard: the persistence mechanism](#entry-guard-the-persistence-mechanism)
- [The state file and Guard persistence](#the-state-file-and-guard-persistence)
- [Requirements to be a Guard Node](#requirements-to-be-a-guard-node)
- [Path Bias Detection](#path-bias-detection)
- [Vanguards - Advanced protection for Hidden Services](#vanguards-advanced-protection-for-hidden-services)
- [Attacks targeting Guard Nodes](#attacks-targeting-guard-nodes)
- [Guard impact on performance](#guard-impact-on-performance)


## Role of the Guard Node

The Guard Node is the **first node** in the Tor circuit:

```
[You: real IP] ──TLS──► [Guard Node] ──TLS──► [Middle] ──TLS──► [Exit] ──► Internet
```

### What the Guard knows

| Information | Visible to the Guard? |
|-------------|----------------------|
| Your real IP | **YES** - it is the direct TCP connection |
| Your geographic location | **YES** - derivable from the IP |
| Your ISP | **YES** - derivable from the IP |
| When you connect | **YES** - sees the connection timing |
| How much data you send | **YES** - sees the traffic volume |
| The final destination | **NO** - only sees the Middle's IP |
| The traffic content | **NO** - only sees encrypted cells |

### Why the Guard is critical

If an adversary controls the Guard Node you are using, they know:
- Who you are (your IP)
- When you use Tor
- The traffic volume

If the same adversary **also** controls the Exit Node of your circuit, they can
correlate the timing of inbound and outbound traffic to deanonymize you
(**end-to-end correlation attack**). This is why guard selection is designed to
minimize this risk.

---

## Entry Guard: the persistence mechanism

### The problem with random selection

In early versions of Tor, the first node was chosen randomly for each circuit.
This had a fatal flaw:

- Suppose an adversary controls 5% of the relays
- Each new circuit has a 5% chance of using a malicious relay as entry
- In 14 circuits, the probability of at least one with a malicious entry is ~50%
- In a day, an active user builds hundreds of circuits
- **Sooner or later**, the adversary becomes your entry node

### The solution: persistent Entry Guards

Starting with Tor 0.2.4, the client selects a small number of guards and reuses
them for an extended period (months):

- If the guard is "good" (not controlled by the adversary), you are protected for months
- If the guard is "malicious", you are exposed - but the risk is a one-time event,
  not cumulative over time
- With 1 guard, you have ~adversary_probability of exposure, not 1-(1-p)^n

**The principle**: it is better to have a small constant risk than a growing
cumulative risk.

### Current parameters (Tor 0.4.x)

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `NumEntryGuards` | 1 | A single primary guard |
| Guard rotation period | ~2-3 months | After this period, a new guard is chosen |
| Sampling period | 27 days | Period for sampling candidate guards |
| Number of guards in the "sample" | ~20 | Pool of candidate guards |

### How selection works

1. **Sampling**: Tor creates a "sampled set" of ~20 guards from the consensus. These
   are relays with the `Guard` + `Stable` + `Fast` flags.

2. **Primary selection**: from the sampled set, 1 guard is selected as primary.
   The selection is weighted by bandwidth.

3. **Usage**: all circuits use this guard. If the guard becomes unreachable, Tor
   tries the "backup" guards in the sampled set.

4. **Rotation**: after the rotation period (~2-3 months), the primary guard is
   replaced. The new guard is chosen from the sampled set (which is also
   updated periodically).

---

## The state file and Guard persistence

The selected guards are saved in the file `/var/lib/tor/state`:

```
Guard in 2025-01-15 12:00:00 name=MyGuard id=FINGERPRINT
GuardReachable=1
GuardConfirmedIdx=0
GuardLastSampled 2025-01-01 00:00:00
GuardAddedBy 0.4.8.10 2025-01-01 00:00:00
GuardPathBias 500 0 0 0 500 0
```

### Important fields

- **GuardReachable**: 1 if the guard is currently reachable
- **GuardConfirmedIdx**: position in the preference order
- **GuardLastSampled**: when the guard was added to the sample
- **GuardPathBias**: counters for path bias detection

### Practical consequences

- **Reinstalling Tor**: if you delete `/var/lib/tor/state`, Tor selects new guards.
  This **temporarily reduces security** because you lose guards that have proven
  to be reliable.

- **System migration**: if you move the Tor configuration to another system,
  also copy `/var/lib/tor/state` to maintain the guards.

- **Suspected compromised guard**: if you have reason to believe your guard is
  controlled by an adversary, deleting `state` is justified.

### In my experience

After configuring Tor for the first time, I reset `/var/lib/tor/state` several
times during the testing and configuration phases. In production, I never touch
the state file. I have observed that my guard changes approximately every 2-3
months by watching the logs:

```bash
sudo journalctl -u tor@default.service | grep "guard"
```

---

## Requirements to be a Guard Node

Not all relays can become guards. The Directory Authorities assign the `Guard`
flag only to relays that satisfy:

1. **`Stable` flag**: MTBF (Mean Time Between Failures) above the network median,
   or at least 7 days

2. **`Fast` flag**: bandwidth above the median or at least 100 KB/s

3. **Minimum uptime**: at least 8 days of continuous operation

4. **Minimum bandwidth**: at least the network median or at least 2 MB/s

5. **Reachability**: verified by the DAs with periodic probes

### Why these requirements?

- **Stability**: a guard that goes offline frequently forces the client to use
  backup guards, increasing exposure
- **Bandwidth**: a slow guard becomes a bottleneck for all of the user's traffic
- **Uptime**: a newly appeared relay does not have enough history to be trusted

### Security implication

The stringent requirements mean that:
- It is expensive for an adversary to maintain malicious guards (they need stable,
  fast servers with high uptime)
- The guard pool is relatively small (~1000-2000 relays out of ~7000 total)
- This makes bandwidth-weighted random selection reasonably secure

---

## Path Bias Detection

Tor monitors the success rate of circuits for each guard to detect malicious guards:

### How it works

For each guard, Tor tracks:
- How many circuits were attempted
- How many were built successfully
- How many were used successfully
- How many failed in a suspicious manner

If the failure rate is anomalous, Tor suspects the guard is interfering:

```
[warn] Your guard FINGERPRINT is failing an extremely high fraction of circuits.
If this persists, Tor will stop using it.
```

### Thresholds

| Metric | Warn threshold | Extreme threshold |
|--------|---------------|-------------------|
| Failed circuits | > 30% | > 70% |
| Collapsed circuits | > 30% | > 70% |

If the "extreme" threshold is exceeded, Tor marks the guard as unusable and
selects a new one.

### What it can indicate

- **Malicious guard**: selectively interfering with circuits
- **Overloaded guard**: unable to handle the traffic
- **Network problem**: the connection to the guard is unstable

---

## Vanguards - Advanced protection for Hidden Services

For onion services (hidden services), guards are even more critical because an
adversary could attempt to enumerate guards to deanonymize the server.

### The problem

An adversary who controls some relays in the Tor network could:
1. Repeatedly connect to the onion service
2. Observe which guard the onion service uses
3. With enough observations, narrow the candidate down to a few guards
4. Correlate the guard with an IP

### The solution: Vanguards

Vanguards adds layers of protection:

- **Layer 1 guards** (actual guards): rotate slowly (months)
- **Layer 2 guards** (persistent middles): rotate moderately (days)
- **Layer 3 guards** (variable middles): rotate frequently (hours)

The circuit of an onion service with vanguards is:
```
HS → Layer1 Guard → Layer2 Middle → Layer3 Middle → ... → Client
```

This prevents the adversary from getting close to the real guard of the onion
service by only observing relays in the circuit.

### Activation

Starting with version 0.4.7+, vanguards is integrated into Tor:
```ini
# In torrc (for onion services)
VanguardsEnabled 1
```

---

## Attacks targeting Guard Nodes

### 1. Guard Discovery Attack

**Scenario**: the adversary wants to discover which guard a specific user uses.

**Method**: if the adversary controls an Exit Node and can force the user to
reconnect (e.g., by causing errors), they observe the first hop of the circuit.
By repeating many times, they confirm that the user always uses the same guard.

**Mitigation**: the user uses only 1 guard for months. The adversary discovers
the guard, but this does not directly reveal the user's IP (unless they also
control the guard itself).

### 2. Guard Enumeration (for Hidden Services)

**Scenario**: the adversary wants to discover all the guards of an onion service.

**Method**: the adversary operates middle/exit relays and monitors connections
to the onion service for weeks/months, recording the first hop.

**Mitigation**: Vanguards (see above).

### 3. Denial of Service to force guard change

**Scenario**: the adversary DDoS-es the user's guard to force them to select a
new one (potentially controlled by the adversary).

**Method**: traffic flood toward the guard → the guard becomes unreachable →
the user switches to a backup guard.

**Mitigation**: Tor does not abandon a guard immediately. There are progressive
retries and timeouts. Furthermore, the new guard is chosen from the existing
sampled set, which was selected at a previous time (not at the time of the attack).

---

## Guard impact on performance

The guard is the bottleneck of the circuit. Its bandwidth and latency directly
affect the performance of all Tor connections.

### In my experience

I noticed that after certain guard renewals, performance changes significantly:

```bash
# Speed test with old guard
> time proxychains curl -s https://api.ipify.org
185.220.101.143
real    0m2.342s

# After guard rotation (slower)
> time proxychains curl -s https://api.ipify.org  
104.244.76.13
real    0m5.891s
```

The difference is due to the bandwidth and latency of the new guard. There is not
much to do: wait for the next rotation or reset the state (not recommended for
security reasons).

### Guard and bridge

When using obfs4 bridges, the bridge acts as the guard. This means that:
- The bridge's bandwidth becomes the bottleneck
- The additional obfs4 latency is added to the circuit's latency
- Bridges are often less performant than regular guards (less bandwidth, more load)

In my tests:
- Direct guard: ~2-4 seconds for an HTTPS request
- obfs4 bridge: ~4-8 seconds for the same request

The trade-off is clear: greater privacy (hiding Tor usage from the ISP) vs.
worse performance.

---

## See also

- [Middle Relay](middle-relay.md) - Second hop of the circuit
- [Exit Nodes](exit-nodes.md) - Third hop and exit from the network
- [Tor Architecture](../01-fondamenti/architettura-tor.md) - Role of the Guard in the architecture
- [Known Attacks](../07-limitazioni-e-attacchi/attacchi-noti.md) - Attacks on Guards (Sybil, correlation)
- [Onion Services v3](onion-services-v3.md) - Vanguards as persistent Guards for HS
