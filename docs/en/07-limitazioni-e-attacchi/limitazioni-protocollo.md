> **Lingua / Language**: [Italiano](../../07-limitazioni-e-attacchi/limitazioni-protocollo.md) | English

# Tor Protocol Limitations - Complete Technical Analysis

This document provides an in-depth analysis of all architectural and protocol
limitations of Tor: why it supports only TCP, what happens to UDP traffic,
the consequences for real-world applications, and possible solutions.

Based on my direct experience with Tor's limitations on Kali Linux,
where I encountered firsthand the impossibility of using certain protocols and services.

---
---

## Table of Contents

- [Fundamental limitation: TCP only](#fundamental-limitation-tcp-only)
- [Latency - The cost of 3 hops](#latency---the-cost-of-3-hops)
- [Bandwidth - Unpredictable and limited](#bandwidth---unpredictable-and-limited)
- [SOCKS5 protocol limitations](#socks5-protocol-limitations)
- [Multiple circuits and variable IPs](#multiple-circuits-and-variable-ips)
- [Problematic protocols and applications - Summary](#problematic-protocols-and-applications---summary)
- [Possible future developments](#possible-future-developments)


## Fundamental limitation: TCP only

### Why Tor supports only TCP

Tor operates at the TCP stream level. The Tor protocol carries data in 514-byte
cells that travel over TLS connections (which in turn travel over TCP).
The chain is:

```
Application data → Tor cells → TLS → TCP → IP → physical network
```

TCP guarantees:
- **Packet ordering**: essential for AES-CTR encryption (the counter
  must advance in order)
- **Reliable delivery**: if a cell is lost, TCP retransmits it
- **Flow control**: TCP handles rate limiting

UDP does not guarantee any of these properties. Implementing reliable transport
over UDP would require reimplementing TCP inside Tor, negating the advantage of UDP.

### Concrete consequences

#### Native DNS (UDP port 53) - Blocked

Standard DNS uses UDP. Without special configuration, DNS queries do not pass
through Tor:

```
Problem:
[App] → DNS query (UDP:53) → ISP resolver → LEAK!

Tor solution:
[App] → SOCKS5 CONNECT (hostname as string) → Tor → Exit (resolves DNS)
or:
[App] → DNSPort 5353 (Tor resolves) → Tor → Exit (resolves DNS)
```

In my experience, the `DNSPort 5353` + `proxy_dns` configuration in proxychains
completely solves this problem for the applications I use.

#### VoIP / RTP (UDP) - Non-functional

```
Protocol: RTP over UDP (dynamic ports)
Status on Tor: IMPOSSIBLE
Reason: Tor does not carry UDP. Even with TCP encapsulation, the 3-hop
  latency (200-1000ms) renders calls unusable.
Impact: no voice calls, no VoIP, no SIP
```

#### WebRTC (UDP + STUN/TURN) - Disabled for security

```
Protocol: WebRTC uses UDP for media, STUN/TURN for NAT traversal
Status on Tor: DISABLED in Tor Browser (media.peerconnection.enabled=false)
Dual reason:
  1. WebRTC reveals the real IP via STUN (leaks even with proxy)
  2. Tor does not carry UDP
Impact: no video calls in browser (Google Meet, Zoom web, Discord web)
```

In my Firefox tor-proxy configuration, I manually disabled WebRTC
in about:config to prevent IP leaks.

#### HTTP/3 (QUIC - UDP) - Blocked

```
Protocol: QUIC (HTTP/3 over UDP port 443)
Status on Tor: BLOCKED (the browser falls back to HTTP/2 or HTTP/1.1)
Reason: QUIC uses UDP
Impact:
  - Worse performance on modern CDNs (Cloudflare, Google)
  - Slower page loads compared to normal browsers
  - No QUIC stream multiplexing (HTTP/2 multiplexing is used instead)
```

In Firefox tor-proxy: `network.http.http3.enabled = false` to avoid
failed QUIC attempts.

#### Online gaming (UDP + low latency) - Impossible

```
Protocols: UDP game protocol, anti-cheat, NAT traversal
Status on Tor: TOTALLY IMPOSSIBLE
Reasons:
  1. No UDP
  2. 200-1000ms latency (games require <50ms)
  3. Variable bandwidth (games require stable bandwidth)
  4. IP-based anti-cheat (blocks Tor)
  5. NAT traversal (STUN/TURN) does not work
```

#### NTP (UDP port 123) - Blocked

```
Protocol: NTP (Network Time Protocol, UDP port 123)
Status on Tor: BLOCKED
Impact: system clock does not synchronize automatically
Risk: if the clock drifts, Tor may reject the consensus
Solution: use ntpdate occasionally without Tor, or configure
  chrony with NTS support (which uses TCP)
```

#### ICMP (ping, traceroute) - Not supported

```
Protocol: ICMP (neither TCP nor UDP)
Status on Tor: IMPOSSIBLE
Impact: ping and traceroute do not work
Solution: none. To verify reachability via Tor, use:
  proxychains curl -I https://target.com
```

---

## Latency - The cost of 3 hops

### Latency analysis

Every Tor connection traverses 3 hops, each with its own latency:

```
Total latency ≈ L(client→guard) + L(guard→middle) + L(middle→exit) + L(exit→destination)
                + TLS overhead per hop
                + encryption/decryption overhead per cell
                + Tor protocol overhead (handshake, flow control)
```

### Measurements from my experience

```bash
# Without Tor:
> time curl -s https://api.ipify.org > /dev/null
real    0m0.245s

# With Tor (good circuit):
> time proxychains curl -s https://api.ipify.org > /dev/null 2>&1
real    0m2.342s

# With Tor (slow circuit):
> time proxychains curl -s https://api.ipify.org > /dev/null 2>&1
real    0m5.891s

# With Tor + obfs4 bridge:
> time proxychains curl -s https://api.ipify.org > /dev/null 2>&1
real    0m4.567s
```

| Configuration | Typical latency | Factor vs direct |
|--------------|----------------|-----------------|
| Direct (no Tor) | 100-300ms | 1x |
| Tor (fast circuit) | 500-2000ms | 5-10x |
| Tor (average circuit) | 2000-5000ms | 10-20x |
| Tor (slow circuit) | 5000-15000ms | 20-50x |
| Tor + obfs4 bridge | 1000-8000ms | 10-30x |

### Why latency varies

- Relays are volunteers with variable bandwidth
- Relays may be geographically distant (e.g., guard in Europe, middle
  in Asia, exit in the Americas)
- Traffic from other users on the same relays causes congestion
- Tor's flow control (SENDME cells) adds pauses
- Initial circuit construction (ntor handshake x 3) is expensive

---

## Bandwidth - Unpredictable and limited

### Why bandwidth is low

The Tor network has ~7000 relays, but total bandwidth is limited:
- Relays are run by volunteers with home connections or cheap VPS instances
- Bandwidth is shared among all users of circuits traversing the relay
- The slowest relay in the chain determines the circuit's maximum speed
- Tor's flow control further limits throughput

### Typical throughput

| Operation type | Throughput via Tor | Direct throughput |
|---------------|-------------------|-------------------|
| Web browsing | 100-500 KB/s | 10+ MB/s |
| File download | 200-800 KB/s | 10+ MB/s |
| Video streaming | Nearly impossible | 5+ MB/s |
| apt update | 50-200 KB/s | 5+ MB/s |

### Congestion control (recent)

Starting with Tor 0.4.7, a new congestion control algorithm was introduced
that significantly improves throughput. It replaces the old fixed-window
mechanism with an adaptive algorithm similar to BBR/CUBIC.

---

## SOCKS5 protocol limitations

### What SOCKS5 supports

- `CONNECT`: opens a TCP connection to a destination → **supported**
- `BIND`: opens a listener for incoming connections → **not supported by Tor**
- `UDP ASSOCIATE`: proxies UDP packets → **not supported by Tor**

### Consequences of unsupported BIND

FTP in active mode requires the server to connect to the client (BIND).
This does not work via Tor. FTP in passive mode (the client connects to the server)
works but is unstable because it requires a second TCP stream on a dynamic port.

### Consequences of unsupported UDP ASSOCIATE

Any application that attempts `UDP ASSOCIATE` via SOCKS5 receives an error.
This includes DNS clients, VoIP applications, and any software that tries to
use UDP through the proxy.

---

## Multiple circuits and variable IPs

### The problem for applications

With a VPN, you have a fixed IP. With Tor:
- Each circuit can have a different exit → different IP
- Different circuits for different streams (stream isolation)
- The IP changes every ~10 minutes (MaxCircuitDirtiness)
- NEWNYM forces an immediate change

### Consequences

1. **Unstable web sessions**: a website may invalidate the session if the IP changes
   (anti-fraud, security tokens tied to the IP)
2. **Rate limiting**: many sites limit requests per IP. With Tor, "your" IP
   is shared with thousands of users → rate limit reached quickly
3. **Inconsistent geolocation**: one request exits from the Netherlands, the next
   from Germany → sites that verify geographic consistency flag anomalies
4. **Endless CAPTCHAs**: sites see traffic from a known Tor IP → repeated CAPTCHAs

### In my experience

CAPTCHAs are the most frequent problem. Google in particular is aggressive:
sometimes it is impossible to perform a search via Tor without solving 3-4 CAPTCHAs.
Amazon, PayPal, and Italian banks directly block login attempts.

---

## Problematic protocols and applications - Summary

| Protocol/App | Problem | Works via Tor? | Alternative |
|-------------|---------|---------------|-------------|
| DNS (UDP) | Tor does not carry UDP | With DNSPort/proxy_dns YES | SOCKS5 hostname |
| HTTP/HTTPS | None | **YES** | - |
| SSH | High latency, timeouts | **Partially** | Increase timeouts |
| FTP | Problematic data channel | **Poorly** | SFTP |
| SMTP | Port 25 blocked by most exits | **Poorly** | Webmail |
| IRC | Many servers block Tor | **Partially** | Servers that accept Tor |
| BitTorrent | DHT/PEX leak IP, exit policy blocks, Tor discourages it | **NO** | - |
| VoIP/SIP | UDP, latency | **NO** | - |
| Gaming | UDP, latency, anti-cheat | **NO** | - |
| Video streaming | Bandwidth, latency | **Nearly NO** | Low quality maybe |
| NTP | UDP | **NO** | NTS over TCP |
| ICMP | Not TCP/UDP | **NO** | curl for reachability testing |
| WebRTC | UDP, IP leak | **Disabled** | - |
| QUIC/HTTP3 | UDP | **Falls back to HTTP/2** | - |
| Generic P2P | UDP, NAT, IP reveal | **NO** | - |

---

## Possible future developments

### MASQUE (UDP over Tor)

The Tor Project is exploring the MASQUE protocol (based on HTTP/3) to
carry UDP over Tor. This could one day enable:
- Native DNS via Tor
- QUIC/HTTP3 via Tor
- Possibly VoIP (though latency would remain a problem)

The work is in its early stages and not yet available in stable releases.

### Conflux (multi-path circuits)

Conflux allows a single stream to use multiple circuits simultaneously,
improving throughput and reliability. Available starting with Tor 0.4.8.

---

## See also

- [Tor Architecture](../01-fondamenti/architettura-tor.md) - Design choices that cause the limitations
- [Application Limitations](limitazioni-applicazioni.md) - Practical impact of the limitations
- [VPN and Tor Hybrid](../06-configurazioni-avanzate/vpn-e-tor-ibrido.md) - VPN to overcome some limitations
- [Known Attacks](attacchi-noti.md) - Attacks that exploit the limitations
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - Limits of correlation protection
