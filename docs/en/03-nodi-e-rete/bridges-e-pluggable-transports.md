> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/bridges-e-pluggable-transports.md) | English

# Bridges and Pluggable Transports - Circumventing Censorship and DPI

This document provides an in-depth analysis of Tor Bridges, Pluggable Transports (PT),
and obfs4 in particular: how they work at the protocol level, how they resist Deep
Packet Inspection, how to configure them, and the real-world limitations in daily use.

It includes my direct experience in requesting bridges, configuring them in torrc,
debugging failed connections, and using them on restrictive networks (university
networks, public hotspots).

---
---

## Table of Contents

- [Why Bridges exist](#why-bridges-exist)
- [How Bridges work at the protocol level](#how-bridges-work-at-the-protocol-level)
- [Pluggable Transports - The obfuscation protocols](#pluggable-transports-the-obfuscation-protocols)
- [obfs4 - In-depth technical analysis](#obfs4-in-depth-technical-analysis)
- [Censorship resistance - How obfs4 survives censors](#censorship-resistance-how-obfs4-survives-censors)
- [How to obtain bridges - Practical experience](#how-to-obtain-bridges-practical-experience)
**Deep dives** (dedicated files):
- [Bridge Configuration and Alternatives](bridge-configurazione-e-alternative.md) - torrc config, meek, Snowflake, comparison


## Why Bridges exist

Normal Tor relays are listed in the **public consensus**. Anyone can download the
list of all ~7000 relays with their IPs. This means that:

1. **An ISP can block all Tor relays**: download the consensus, extract the IPs,
   add them to a firewall blacklist.

2. **A government with DPI can identify Tor traffic**: even without blocking the
   IPs, packet analysis can detect patterns typical of the Tor protocol
   (specific TLS handshake, cell format, timing).

3. **A passive observer knows you use Tor**: your ISP sees a connection to an
   IP known to be a Tor relay.

Bridges solve these problems because:
- **They are not in the public consensus** → cannot be blocked by list
- **They use Pluggable Transports** → traffic does not look like Tor
- **They are distributed in a limited fashion** → harder for a censor to discover

---

## How Bridges work at the protocol level

### Architecture of a bridge

A bridge is a Tor relay with two differences:
1. It does not publish its descriptor in the public consensus
2. It publishes the descriptor only to the **Bridge Authority**
3. It supports Pluggable Transports to obfuscate traffic

```
Connection via normal relay:
[Tor Client] ──TLS──► [Public Guard] ──TLS──► [Middle] ──► [Exit]
  The ISP sees: TLS connection to an IP known as a Tor relay

Connection via obfs4 bridge:
[Tor Client] ──PT──► [obfs4proxy client] ──obfs4──► [Bridge] ──► [Middle] ──► [Exit]
  The ISP sees: traffic that looks like random noise to an unknown IP
```

### The flow with obfs4

1. The Tor client reads the line `Bridge obfs4 IP:PORT FINGERPRINT cert=... iat-mode=N`
2. It starts `obfs4proxy` as a child process using the PT (Pluggable Transport) protocol
3. obfs4proxy opens a local port (e.g., 127.0.0.1:47832)
4. Tor connects to this local port as if it were a relay
5. obfs4proxy receives the data, obfuscates it, and sends it to the remote bridge
6. The remote bridge has obfs4proxy server-side that deobfuscates the data
7. The bridge processes the Tor traffic normally
8. The circuit continues: bridge → middle → exit → internet

---

## Pluggable Transports - The obfuscation protocols

### What is a Pluggable Transport

A PT is a program that **transforms Tor traffic** into something that does not
look like Tor. It sits between the client and the bridge:

```
[Tor daemon] ←SOCKS→ [PT client-side] ←obfuscated→ [PT server-side] ←→ [Tor Bridge]
```

PTs communicate with Tor via the **PT protocol** (specified in `pt-spec.txt`):
- Tor sets environment variables (`TOR_PT_MANAGED_TRANSPORT_VER`, `TOR_PT_CLIENT_TRANSPORTS`, etc.)
- The PT prints to stdout the ports it has opened (e.g., `CMETHOD obfs4 socks5 127.0.0.1:47832`)
- Tor connects to these ports

### Types of Pluggable Transports

| Transport | Technique | DPI Resistance | Speed | Status |
|-----------|-----------|---------------|-------|--------|
| **obfs4** | Cryptographic obfuscation, looks like noise | High | Good | **Recommended** |
| **meek** | Encapsulates in HTTPS to CDN (Amazon, Azure) | Very high | Slow | Active |
| **Snowflake** | Uses WebRTC via volunteer browsers | High | Variable | Active |
| **webtunnel** | Looks like normal HTTPS traffic | High | Good | New |
| obfs3 | Simple obfuscation | Low | Good | Deprecated |
| ScrambleSuit | Obfuscation with shared secret | Medium | Good | Deprecated |
| FTE | Format-Transforming Encryption | Medium | Medium | Deprecated |

---

## obfs4 - In-depth technical analysis

### How the obfuscation works

obfs4 (Obfuscation version 4) transforms Tor traffic into data that:
- **Has no recognizable patterns** - no header, magic bytes, or structure
- **Looks like random noise** - uniform byte distribution
- **Has no predictable packet sizes** - variable padding
- **Has no predictable timing** - with iat-mode, timing is randomized

### The obfs4 protocol step-by-step

**Phase 1: Handshake**

```
Client                                    Server (Bridge)
  |                                          |
  | The client knows:                        |
  | - node-id (bridge fingerprint)           |
  | - public-key (server Curve25519 key)     |
  | (both from the bridge's cert= field)     |
  |                                          |
  | 1. Generates ephemeral Curve25519 keypair|
  | 2. Computes mark = HMAC(keypair, node-id)|
  | 3. Sends: X (pubkey) + padding + mark    |
  |─────────────────────────────────────────►|
  |                                          | 4. Receives, finds mark in stream
  |                                          | 5. Verifies that X is valid
  |                                          | 6. Generates ephemeral keypair
  |                                          | 7. Computes shared secret (ECDH)
  |                                          | 8. Sends: Y (pubkey) + auth + padding
  |◄─────────────────────────────────────────|
  | 9. Computes shared secret (ECDH)         |
  | 10. Verifies auth                        |
  | 11. Derives symmetric keys               |
  |                                          |
  | Now both have keys for                   |
  | NaCl secretbox (XSalsa20+Poly1305)       |
```

**Phase 2: Obfuscated data transfer**

After the handshake, each packet is:
```
[length (2 bytes, encrypted)] [payload (encrypted with NaCl secretbox)] [padding]
```

- The length is encrypted → an observer does not know how large the payload is
- The payload is encrypted and authenticated (Poly1305)
- The padding is variable → packet sizes are unpredictable

### iat-mode - Inter-Arrival Time obfuscation

The `iat-mode` parameter in the bridge controls temporal obfuscation:

**iat-mode=0**: no temporal padding. Packets are sent when data is ready. An
observer can analyze packet timing to correlate with known patterns.

**iat-mode=1**: moderate temporal padding. obfs4 adds a random delay between
packets to break obvious temporal patterns.

**iat-mode=2**: maximum temporal padding. obfs4 adds delays and dummy packets
to make the timing completely random. Increases latency but improves resistance
to advanced traffic analysis.

### In my experience

I used bridges with different iat-modes:

```ini
Bridge obfs4 xxx.xxx.xxx.xxx:4431 F829D395093B... cert=... iat-mode=0
Bridge obfs4 xxx.xxx.xxx.xxx:13630 A3D55AA6178... cert=... iat-mode=2
```

- `iat-mode=0`: faster, sufficient for hiding Tor traffic from the ISP
- `iat-mode=2`: slower but necessary on networks with aggressive DPI

On university networks with heavy firewalling, `iat-mode=0` was sufficient.
The firewall was not analyzing timing, only the protocol type.

---

## Censorship resistance - How obfs4 survives censors

### Level 1: IP blocking

**Attack**: the censor blocks the IPs of known Tor relays.

**obfs4 defense**: bridges are not in the public consensus. Bridge IPs are
distributed through limited channels. The censor does not have a complete list.

**Limitation**: if the censor obtains a bridge (by requesting it from the site or
via email), they can block its IP. This is why bridges are distributed in a limited
fashion (CAPTCHA, rate limiting, etc.).

### Level 2: Deep Packet Inspection (DPI)

**Attack**: the censor analyzes packet contents to recognize the Tor protocol
(magic bytes, handshake patterns, byte distribution).

**obfs4 defense**:
- No recognizable magic bytes or headers
- The handshake looks like random noise (uniform distribution)
- Encrypted data is indistinguishable from noise
- Packet sizes are variable and do not follow patterns

### Level 3: Active Probing

**Attack**: the censor suspects an IP is a bridge. It opens a connection and
tries to perform the Tor handshake. If the server responds like a Tor relay, it
blocks it.

**obfs4 defense**:
- The obfs4 server does not respond to connections that do not present the correct
  `mark` in the handshake
- The `mark` is derived from the server's public key, which only legitimate clients
  know (from the `cert=` field)
- A censor that does not know `cert` cannot complete the handshake
- The server simply does not respond or closes the connection

### Level 4: Statistical Analysis

**Attack**: the censor analyzes statistical properties of the traffic (packet size
distribution, entropy, timing) to distinguish obfs4 from legitimate traffic.

**obfs4 defense**:
- High entropy (looks like random noise - but noise also has high entropy)
- iat-mode to randomize timing
- Padding to vary sizes

**Limitation**: a sophisticated censor could notice that the traffic has unusually
high entropy (normal web traffic has structured patterns, not pure noise). This is
an active area of research.

---

## How to obtain bridges - Practical experience

### Method 1: Official website

URL: `https://bridges.torproject.org/options`

1. Go to the site
2. Select the transport type (obfs4)
3. Solve the CAPTCHA
4. Receive 2-3 bridge lines

In my experience:
- The site works but is sometimes slow
- The bridges provided may already be saturated (many users request them)
- In contexts with DNS filtering, the domain `bridges.torproject.org` may be
  blocked → use an alternative DNS or Tor itself to access the site

**Note**: I initially used the URL `https://bridges.torproject.org/bridges`
(suggested by ChatGPT), which did not work. The correct URL is `.../options`.

### Method 2: Email

Send an email to `bridges@torproject.org` from a Gmail or Riseup address.

Email body:
```
get transport obfs4
```

Response (within a few hours):
```
Bridge obfs4 IP1:PORT1 FINGERPRINT1 cert=CERT1 iat-mode=0
Bridge obfs4 IP2:PORT2 FINGERPRINT2 cert=CERT2 iat-mode=0
Bridge obfs4 IP3:PORT3 FINGERPRINT3 cert=CERT3 iat-mode=0
```

Advantages: works even if the site is blocked.
Disadvantages: not immediate, requires a specific email account.

### Method 3: Snowflake (alternative, not obfs4)

Snowflake uses volunteer browsers as temporary bridges via WebRTC:

```ini
UseBridges 1
ClientTransportPlugin snowflake exec /usr/bin/snowflake-client
Bridge snowflake 192.0.2.3:80 ... fingerprint ... url=...
```

In my experience, Snowflake is:
- Less stable (depends on which volunteers are online)
- Slower (bandwidth depends on the volunteer's connection)
- Useful as a fallback when obfs4 bridges are not working

---

> **Continues in**: [Bridge Configuration and Alternatives](bridge-configurazione-e-alternative.md) for
> torrc configuration, meek (CDN), Snowflake (peer-to-peer), and the comparison between transports.

---

## See also

- [Bridge Configuration and Alternatives](bridge-configurazione-e-alternative.md) - torrc config, meek, Snowflake, comparison
- [torrc - Complete Guide](../02-installazione-e-configurazione/torrc-guida-completa.md) - Bridge configuration in torrc
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - Bridges as DPI defense
- [VPN and Hybrid Tor](../06-configurazioni-avanzate/vpn-e-tor-ibrido.md) - Bridges vs VPN for hiding Tor
- [Real-World Scenarios](scenari-reali.md) - Practical operational cases from a pentester
