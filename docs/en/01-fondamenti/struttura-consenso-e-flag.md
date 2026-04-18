> **Lingua / Language**: [Italiano](../../01-fondamenti/struttura-consenso-e-flag.md) | English

# Consensus Structure, Flags and Bandwidth Authorities

The consensus document, flags assigned to relays, and the bandwidth measurement
system that prevents amplification attacks.

Extracted from [Consensus and Directory Authorities](consenso-e-directory-authorities.md).

---

## Table of Contents

- [Consensus document structure](#consensus-document-structure)
- [Consensus flags - In-depth analysis](#consensus-flags--in-depth-analysis)
- [Bandwidth Authorities and bandwidth measurement](#bandwidth-authorities-and-bandwidth-measurement)

---

## Consensus document structure

The consensus is a text document of approximately 2-3 MB. Here is its simplified structure:

### Header

```
network-status-version 3
vote-status consensus
consensus-method 32
valid-after 2025-01-15 12:00:00
fresh-until 2025-01-15 13:00:00
valid-until 2025-01-15 15:00:00
voting-delay 300 300
...
```

- `valid-after`: when the consensus becomes valid
- `fresh-until`: by when the client should look for a more recent consensus
- `valid-until`: after this date the consensus is considered expired
- `voting-delay`: time for vote upload and computation

### DA section

```
dir-source moria1 ...
contact Roger Dingledine
vote-digest ABCDEF1234...
...
```

### Relay section (the heart of the consensus)

For each relay:

```
r ExitRelay1 ABCDef123 2025-01-15 11:45:33 198.51.100.42 9001 0
s Exit Fast Guard HSDir Running Stable V2Dir Valid
w Bandwidth=15000
p accept 20-23,43,53,79-81,88,110,143,194,220,389,443,464-465,531,543-544,554,563,587,636,706,749,853,873,902-904,981,989-995,1194,1220,1293,1500,1533,1677,1723,1755,1863,2082-2083,2086-2087,2095-2096,2102-2104,3128,3389,3690,4321,4443,5050,5190,5222-5223,5228,5900,6660-6669,6679,6697,8000-8003,8080,8332-8333,8443,8888,9418,11371,19294,19638
```

Line-by-line explanation:

- **r** (router): nickname, fingerprint (base64), publication date, IP, ORPort, DirPort
- **s** (status flags): flags assigned by the consensus
- **w** (weight): bandwidth in KB/s (weighted and measured)
- **p** (exit policy summary): compressed version of the exit policy

### Signature section

```
directory-signature sha256 FINGERPRINT_DA
-----BEGIN SIGNATURE-----
...
-----END SIGNATURE-----
```

---

## Consensus flags - In-depth analysis

Flags determine how the client uses each relay. Their assignment is critical for
network security.

### `Guard` flag

**Requirements**: the relay must be:
- `Stable` (uptime above the median of Stable-eligible relays)
- `Fast` (bandwidth above the median)
- Running for at least 8 days
- With sufficient bandwidth (at least the median or at least 2 MB/s)

**Implication**: only relays with the Guard flag can be chosen as entry nodes by the
client. This limits the entry pool to reliable, high-bandwidth relays, reducing the
risk that a malicious relay gets chosen as guard.

### `Exit` flag

**Requirements**: the relay's exit policy allows connections to at least port 80 and 443
of at least 2 /8 address blocks.

**Implication**: only relays with the Exit flag are considered for the last hop. A relay
without the Exit flag but with a partial exit policy is not selected as exit by the client
(but could still function if forced).

### `Stable` flag

**Requirements**: MTBF (Mean Time Between Failures) above the median of relays with uptime > 1 day, OR above 7 days.

**Implication**: used for circuits that require long-lived connections (SSH, IRC, etc.).
Tor selects Stable relays for streams on ports known for persistent connections.

### `Fast` flag

**Requirements**: measured bandwidth above the median of active relays, OR at least 100 KB/s.

**Implication**: increases the selection probability for that relay (more bandwidth ->
more traffic routed through it).

### `HSDir` flag

**Requirements**: the relay supports the directory protocol for hidden services.

**Implication**: can store and serve hidden service descriptors (.onion). Important for
the reachability of onion services.

### `BadExit` flag

**Requirements**: manually assigned by the DAs when an exit node has been identified as
malicious (sniffing, injection, MITM).

**Implication**: the client **never selects** a relay with the BadExit flag as exit node.
It can still be used as a middle.

### In my experience

I've never had to interact directly with flags, but I see them when using Nyx or when
inspecting circuits via ControlPort. Knowing that my guard has the `Guard` and `Stable`
flags gives me more confidence in circuit stability.

---

## Bandwidth Authorities and bandwidth measurement

### The self-reported bandwidth problem

Each relay can declare any bandwidth value in its own descriptor. A malicious relay
could declare 100 MB/s when it only has 1 MB/s, to attract more traffic and increase
its selection probability.

### The solution: bandwidth authorities

A subset of the DAs performs independent bandwidth measurements using the **sbws**
(Simple Bandwidth Scanner) software:

1. **sbws** connects to each relay and measures actual bandwidth
2. Generates a vote file with measured bandwidths
3. During voting, measured bandwidths override self-reported ones
4. The consensus contains measured bandwidth, not declared bandwidth

### Bandwidth weights in the consensus

The consensus also includes **bandwidth weights** - global coefficients that determine
how to distribute traffic among guards, middles, exits:

```
bandwidth-weights Wbd=0 Wbe=0 Wbg=4203 Wbm=10000 Wdb=10000 Web=10000 Wed=10000
Weg=10000 Wem=10000 Wgb=10000 Wgd=0 Wgg=5797 Wgm=5797 Wmb=10000 Wmd=10000
Wme=10000 Wmg=4203 Wmm=10000
```

These weights serve to balance traffic: if there are few exits compared to guards,
the weights are adjusted to route more traffic through the available exits.

---


---

## See also

- [Consensus and Directory Authorities](consenso-e-directory-authorities.md) - Why consensus, DAs, voting
- [Descriptors, Cache and Attacks](descriptor-cache-e-attacchi.md) - Server descriptors, cache, consensus attacks
- [Tor Architecture](architettura-tor.md) - Components and overview
- [Real-World Scenarios](scenari-reali.md) - Operational pentesting cases
