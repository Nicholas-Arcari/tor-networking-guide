> **Lingua / Language**: [Italiano](../../01-fondamenti/consenso-e-directory-authorities.md) | English

# Consensus and Directory Authorities - Tor's Nervous System

This document analyzes in detail how the Tor network maintains a shared view of its own
state: the consensus mechanism, the role of Directory Authorities, the voting process,
relay descriptors, and the security implications.

Includes observations from my experience analyzing Tor logs during bootstrap and
understanding why certain relays get selected.

---
---

## Table of Contents

- [Why is a consensus needed?](#why-is-a-consensus-needed)
- [Directory Authorities - Who they are and what they do](#directory-authorities--who-they-are-and-what-they-do)
- [The voting process - Hour by hour](#the-voting-process--hour-by-hour)
- [Consensus document structure](#consensus-document-structure)
- [Consensus flags - In-depth analysis](#consensus-flags--in-depth-analysis)
- [Bandwidth Authorities and bandwidth measurement](#bandwidth-authorities-and-bandwidth-measurement)
- [Server Descriptors - A relay's identity](#server-descriptors--a-relays-identity)
- [Microdescriptor vs Server Descriptor](#microdescriptor-vs-server-descriptor)
- [Consensus cache and persistence](#consensus-cache-and-persistence)
- [Attacks on the consensus system](#attacks-on-the-consensus-system)
- [Querying the consensus manually](#querying-the-consensus-manually)
- [Summary](#summary)


## Why is a consensus needed?

Tor is a decentralized network of ~7000 volunteer relays. The client needs to know:

- Which relays exist and are active
- What their IP addresses and ports are
- Which public keys they use (for the ntor handshake)
- How much bandwidth they offer (for weighted selection)
- What exit policy they have (to choose the correct exit)
- Which flags they have (Guard, Exit, Stable, Fast, etc.)

Without this information, the client cannot build circuits. The **consensus** is the
document that contains all of this.

---

## Directory Authorities - Who they are and what they do

### The 9 Directory Authorities

The DAs are servers hardcoded in the Tor source code. At the time of writing, they are
operated by:

| Name | Operator | Jurisdiction |
|------|----------|-------------|
| moria1 | MIT (Roger Dingledine) | USA |
| tor26 | Peter Palfrader | Austria |
| dizum | Alex de Joode | Netherlands |
| Serge | Serge Hallyn | USA |
| gabelmoo | Sebastian Hahn | Germany |
| dannenberg | CCC | Germany |
| maatuska | Linus Nordberg | Sweden |
| Faravahar | Sina Rabbani | USA |
| longclaw | Riseup | USA |

These 9 authorities **vote every hour** to produce the consensus. The consensus is valid
only if signed by at least **5 of 9** DAs (simple majority).

### Bridge Authority

There is also a separate **bridge authority** (currently `Serge` also fills this role)
that manages the bridge database. Bridges do not appear in the public consensus - they
are distributed via `https://bridges.torproject.org` and other channels.

### Fallback Directories

To reduce load on the DAs during initial bootstrap, Tor includes a list of hardcoded
**fallback directory mirrors**. These are normal relays with the `V2Dir` flag that have
a copy of the consensus. The client uses them for the first download, then switches to DAs.

In my experience, bootstrap almost always uses fallbacks. I can see it in the logs:
```
Bootstrapped 5% (conn): Connecting to a relay
```
That "relay" is a fallback directory, not a DA. DAs are contacted directly only if the
fallbacks don't respond.

---

## The voting process - Hour by hour

Every hour, the consensus is renewed. The process is:

### Phase 1: Vote publication (T+0 min)

Each DA produces its own **vote** based on the relays it has tested:

```
A single DA's vote contains:
- List of all relays known to the DA
- Flags assigned to each relay
- Measured bandwidth (if the DA is also a bandwidth authority)
- Validity timestamp
- DA's signature
```

Votes are published and shared among the DAs.

### Phase 2: Consensus computation (T+5 min)

Each DA computes the consensus by combining all received votes:

1. **For each relay**: included in the consensus only if **at least half of the DAs**
   that voted include it.

2. **For each flag**: a relay receives a flag if **at least half of the DAs** that know
   it assign that flag.

3. **For bandwidth**: if there are measurements from bandwidth authorities, these
   override the self-reported bandwidth from the relay.

4. **Signature**: each DA signs the resulting consensus.

### Phase 3: Publication (T+10 min)

The signed consensus is published. Clients (and relays) download it.

### Complete consensus timeline

```
Hour X + 00:00  -> DAs start collecting votes
Hour X + 00:05  -> DAs compute the consensus
Hour X + 00:10  -> Consensus is published
Hour X + 01:00  -> New voting cycle

The consensus is valid for 3 hours from publication time,
with a "fresh" period of 1 hour. This allows clients with
slow connections to use a slightly dated consensus.
```

### In my experience

Downloading the consensus is the first thing Tor does at bootstrap. If the consensus is
corrupted, expired, or unreachable, bootstrap fails. I've seen this error:

```
[warn] Our clock is 3 hours behind the consensus published time.
```

This happened on a VM where NTP wasn't configured. The clock was 3 hours behind, and
Tor rejected the consensus because it was outside the validity window. The fix was:

```bash
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
```

---


---

> **Continues in**: [Consensus Structure and Flags](struttura-consenso-e-flag.md) for the document
> format and flags, and in [Descriptors, Cache and Attacks](descriptor-cache-e-attacchi.md)
> for server descriptors, cache and consensus attacks.

---

## See also

- [Consensus Structure and Flags](struttura-consenso-e-flag.md) - Document format, flags, bandwidth auth
- [Descriptors, Cache and Attacks](descriptor-cache-e-attacchi.md) - Server descriptors, cache, consensus attacks
- [Tor Architecture](architettura-tor.md) - Components and overview
- [Circuit Construction](costruzione-circuiti.md) - How the consensus is used for path selection
- [Real-World Scenarios](scenari-reali.md) - Operational pentesting cases
