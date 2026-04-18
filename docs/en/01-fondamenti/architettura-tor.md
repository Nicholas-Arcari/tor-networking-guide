> **Lingua / Language**: [Italiano](../../01-fondamenti/architettura-tor.md) | English

# Tor Architecture - Low-Level Analysis

This document describes the internal architecture of the Tor network at a level of detail
that goes beyond the classic "3 nodes and onion encryption" explanation. Here we analyze how
Tor actually works at the protocol level, which software components interact, how the Tor
daemon manages connections, circuits and streams, and the practical implications of each
architectural choice.

Includes notes from my direct experience using Tor on Kali Linux (Debian), with
proxychains, ControlPort, obfs4 bridges and custom scripts.

---
---

## Table of Contents

- [Overview: what happens when you launch Tor](#overview-what-happens-when-you-launch-tor)
- [Tor architecture components](#tor-architecture-components)

**Deep dives** (dedicated files):
- [Circuit Construction](costruzione-circuiti.md) - Path selection, CREATE2/EXTEND2, ntor, cells, TLS
- [Isolation and Threat Model](isolamento-e-modello-minaccia.md) - Stream isolation, circuit lifecycle, threat model


## Overview: what happens when you launch Tor

When you run `sudo systemctl start tor@default.service`, the `tor` daemon performs these
operations in sequence:

1. **Reading torrc** - the `/etc/tor/torrc` file is parsed. Each directive is validated.
   If there's a syntax error, Tor refuses to start (verifiable with
   `tor -f /etc/tor/torrc --verify-config`).

2. **Opening local ports** - Tor opens listening sockets:
   - `SocksPort 9050` - SOCKS5 proxy for client applications
   - `DNSPort 5353` - local DNS resolver routing queries through Tor
   - `ControlPort 9051` - control interface for external scripts and tools

3. **Connecting to the Tor network** - The daemon contacts the Directory Authorities (or a
   fallback mirror) to download the **consensus** (network consensus), a signed document
   listing all active relays with their properties.

4. **Bootstrap** - Tor builds the initial circuits. The process is visible in the logs:
   ```
   Bootstrapped 5% (conn): Connecting to a relay
   Bootstrapped 10% (conn_done): Connected to a relay
   Bootstrapped 14% (handshake): Handshaking with a relay
   Bootstrapped 15% (handshake_done): Handshake with a relay done
   Bootstrapped 75% (enough_dirinfo): Loaded enough directory info to build circuits
   Bootstrapped 90% (ap_handshake_done): Handshake finished with a relay to build circuits
   Bootstrapped 95% (circuit_create): Establishing a Tor circuit
   Bootstrapped 100% (done): Done
   ```

5. **Ready for traffic** - Once 100% is reached, the SocksPort accepts connections.
   ProxyChains, curl, Firefox can route traffic through it.

### In my experience

Bootstrap is the most critical moment. I've seen failures in several situations:

- **Saturated bridges**: when the obfs4 bridges configured in torrc were overloaded,
  bootstrap would stall at 10-15% with `Connection timed out`. Solution: request fresh
  bridges from `https://bridges.torproject.org/options`.

- **Blocked DNS**: on some university networks DNS was filtered, preventing the daemon
  from resolving fallback directories. With obfs4 bridges the problem was bypassed since
  the connection goes directly to the bridge IP.

- **System clock skew**: Tor verifies TLS certificates and the consensus has a temporal
  validity window. If the clock is off by more than a few hours, Tor rejects the consensus.
  This happened to me on a freshly installed VM where NTP wasn't configured.

---

## Tor architecture components

### 1. Onion Proxy (OP) - The client

The Onion Proxy is the software running on the user's machine. On Linux it's the `tor`
daemon. Its responsibilities are:

- **Download and maintain the updated consensus** - The consensus is refreshed every hour.
  It contains the list of all relays with flags, bandwidth, exit policy, public keys.

- **Build circuits** - The OP selects nodes (Guard, Middle, Exit) and negotiates
  cryptographic keys with each through the ntor handshake.

- **Multiplex streams on circuits** - A single circuit can carry multiple simultaneous TCP
  streams. Each SOCKS5 connection to port 9050 generates a new stream, but may reuse an
  existing circuit.

- **Manage isolation** - Tor decides when to create new circuits based on isolation criteria
  (by destination port, by SOCKS source address, etc.).

- **Expose local interfaces** - SocksPort, DNSPort, TransPort, ControlPort.

#### Detail: the flow of a SOCKS5 request

When proxychains runs `curl https://api.ipify.org`:

```
1. curl -> proxychains (LD_PRELOAD intercepts connect())
2. proxychains -> 127.0.0.1:9050 (SOCKS5 handshake)
3. SOCKS5 CONNECT api.ipify.org:443
4. Tor daemon receives the request
5. Tor selects a circuit (or creates a new one)
6. Tor creates a stream on the circuit -> RELAY_BEGIN cell
7. The Exit Node opens a TCP connection to api.ipify.org:443
8. The Exit Node responds -> RELAY_CONNECTED cell
9. Data flows bidirectionally through RELAY_DATA cells
10. curl receives the response (exit node's IP)
```

In my experience, I verify this flow like this:
```bash
> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
185.220.101.143
```

The returned IP is the Exit Node's, not mine (which is an Italian IP from Parma).

### 2. Directory Authorities (DA)

The Directory Authorities are 9 servers hardcoded in the Tor source code (+ 1 bridge
authority). Their role is fundamental:

- **Collect relay descriptors** - Each relay periodically publishes a server descriptor
  containing: public keys, exit policy, declared bandwidth, relay family, operator contact.

- **Vote on the consensus** - Every hour, the DAs vote on which relays to include in the
  consensus and which flags to assign to each. The result is a document signed by the
  majority of DAs.

- **Assign flags** - Flags determine the relay's behavior in the network:

  | Flag | Meaning |
  |------|---------|
  | `Guard` | Can be used as an entry node |
  | `Exit` | Has an exit policy allowing outbound traffic |
  | `Stable` | Long and reliable uptime |
  | `Fast` | Bandwidth above the median |
  | `HSDir` | Can host hidden service descriptors |
  | `V2Dir` | Supports directory protocol v2 |
  | `Running` | The relay is currently reachable |
  | `Valid` | The relay has been verified as functional |
  | `BadExit` | Exit node known for malicious behavior |

- **Bandwidth Authorities** - A subset of the DAs performs independent bandwidth
  measurements (via the `sbws` software). These measurements override the self-reported
  bandwidth from relays, preventing attacks where a malicious relay declares very high
  bandwidth to attract more traffic.

#### Practical implication

The DAs are a centralization point. If an adversary compromised 5 of the 9 DAs, they could
manipulate the consensus. However:
- The DAs are operated by independent organizations in different jurisdictions
- The code verifies multiple signatures
- The community monitors anomalies in the consensus

### 3. Relays (Tor nodes)

Relays are volunteer servers that carry Tor traffic. Each relay has:

- **Identity key** (Ed25519) - permanently identifies the relay
- **Onion key** (Curve25519) - used for the ntor handshake (circuit key negotiation)
- **Signing key** - signs descriptors
- **TLS key** - for the TLS connection between relays

#### Relay types

**Guard Node (Entry)**
- First node in the circuit
- Knows the client's real IP
- Does NOT know the final destination
- Selected from a restricted pool of "entry guards" that the client maintains for months
- Rationale for persistent guards: if the client chose random entries every time, an
  adversary controlling some relays would eventually be selected as entry (seeing the
  client's IP). With persistent guards, either you're unlucky from the first selection,
  or you're protected for months.

**Middle Relay**
- Intermediate node
- Does NOT know either the client or the destination
- Only sees encrypted traffic from the guard and forwards it to the exit
- Selected with probability proportional to bandwidth

**Exit Node**
- Last node, exits to the Internet
- Knows the destination (domain + port)
- Does NOT know the client's IP
- Its IP is the one visible to websites
- Defines an exit policy that limits which ports/destinations are allowed

### 4. Bridge Relay

Bridges are relays not listed in the public consensus. They exist to circumvent censorship:

- The ISP cannot block them by consulting the public relay list
- They use pluggable transports (obfs4, meek, Snowflake) to obfuscate traffic
- They are distributed through limited channels (website with CAPTCHA, email, Snowflake)

In my experience, obfs4 bridges have been essential for:
- Bypassing university firewalls that blocked direct connections to Tor relays
- Hiding from the ISP the fact that I was using Tor
- Avoiding throttling applied by some ISPs to recognized Tor traffic

---

> **Continues in**: [Circuit Construction](costruzione-circuiti.md) for the CREATE2/EXTEND2 protocol,
> cells, TLS, and in [Isolation and Threat Model](isolamento-e-modello-minaccia.md) for
> stream isolation, circuit lifecycle and threat model.

---

## See also

- [Circuit Construction](costruzione-circuiti.md) - Path selection, ntor handshake, cells and TLS
- [Isolation and Threat Model](isolamento-e-modello-minaccia.md) - Stream isolation, lifecycle, threat model
- [Circuits, Cryptography and Cells](circuiti-crittografia-e-celle.md) - Packet-level protocol
- [Consensus and Directory Authorities](consenso-e-directory-authorities.md) - Voting, flags, relay selection
- [Real-World Scenarios](scenari-reali.md) - Operational pentesting cases
