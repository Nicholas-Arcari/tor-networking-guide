> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/bridge-configurazione-e-alternative.md) | English

# Bridge Configuration, meek, Snowflake, and Comparison

Configuring bridges in torrc, debugging bootstrap, meek (CDN),
Snowflake (peer-to-peer), and comparison between pluggable transports.

Extracted from [Bridges and Pluggable Transports](bridges-e-pluggable-transports.md).

---

## Table of Contents

- [Configuring bridges in torrc](#configuring-bridges-in-torrc)
- [meek - CDN encapsulation](#meek--cdn-encapsulation)
- [Snowflake - Peer-to-peer bridge](#snowflake--peer-to-peer-bridge)
- [Comparison between Pluggable Transports](#comparison-between-pluggable-transports)

---

## Configuring bridges in torrc

### Complete configuration

```ini
# Enable bridges
UseBridges 1

# Register the pluggable transport
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

# Bridges (replace with real values)
Bridge obfs4 198.51.100.42:4431 AABBCCDD... cert=BASE64CERT... iat-mode=0
Bridge obfs4 203.0.113.88:13630 EEFFGGHH... cert=BASE64CERT... iat-mode=2
```

### Rules for Bridge lines

- The format is strict: `Bridge <transport> <IP>:<PORT> <FINGERPRINT> <parameters>`
- **No spaces** at the beginning of the line
- The fingerprint is hexadecimal, without separators (40 hex chars for SHA-1)
- `cert=` is base64 without spaces
- `iat-mode=` accepts 0, 1, or 2
- Multiple bridges can be specified: Tor tries them in order and uses the first one that responds

### Verification and debugging

```bash
# Verify the configuration
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config

# Restart and monitor
sudo systemctl restart tor@default.service
sudo journalctl -u tor@default.service -f
```

**Successful output**:
```
Bootstrapped 5% (conn): Connecting to a relay
Bootstrapped 10% (conn_done): Connected to a relay
... (progression up to 100%)
Bootstrapped 100% (done): Done
```

**Failure output**:
```
Bootstrapped 5% (conn): Connecting to a relay
[warn] Problem bootstrapping. Stuck at 5% (conn). (Connection timed out;
  NOROUTE; count 1; recommendation warn; host AABBCCDD at 198.51.100.42:4431)
```

If I see `Connection timed out` for all bridges:
1. I verify that `obfs4proxy` is installed and executable
2. I verify that the bridge format is correct
3. I test IP reachability: `nc -zv 198.51.100.42 4431 -w 5`
4. If everything is OK, the bridges are probably saturated → request new ones

---

## meek - CDN encapsulation

### How it works

meek hides Tor traffic inside normal HTTPS connections to CDNs like Amazon
CloudFront or Microsoft Azure:

```
[Client] ──HTTPS──► [Amazon CloudFront] ──► [meek bridge] ──► [Tor Network]
```

The censor only sees an HTTPS connection to `d2cly7j4zqgua7.cloudfront.net`
(Amazon). Blocking this would mean blocking all of Amazon CloudFront, causing
enormous collateral damage. This is the principle of **domain fronting**.

### meek limitations

- **Slow**: traffic passes through a CDN → additional latency
- **Expensive**: the Tor Project pays for CDN hosting
- **Domain fronting in decline**: some providers (Google, Amazon) have restricted
  domain fronting

### Configuration

```ini
UseBridges 1
ClientTransportPlugin meek_lite exec /usr/bin/obfs4proxy
Bridge meek_lite 192.0.2.18:80 ... url=https://meek.azureedge.net/ front=ajax.aspnetcdn.com
```

---

## Snowflake - Peer-to-peer bridge

### How it works

Snowflake uses volunteers who run a browser extension as "proxies":

```
[Client] ──WebRTC──► [Volunteer browser] ──► [Snowflake bridge] ──► [Tor Network]
```

1. The client contacts a broker (via domain fronting) to find a volunteer
2. It establishes a WebRTC connection with the volunteer
3. Tor traffic is encapsulated in the WebRTC channel
4. The volunteer forwards it to the Snowflake bridge
5. The bridge feeds it into the Tor network

### Advantages

- The "bridges" are millions of volunteer browsers → impossible to block them all
- No manual bridge configuration needed
- Works even in countries with extreme censorship

### Disadvantages

- Depends on volunteer availability
- Bandwidth limited by the volunteer's connection
- WebRTC can have NAT traversal issues
- Variable latency

---

## Comparison between Pluggable Transports

| Characteristic | obfs4 | meek | Snowflake |
|---------------|-------|------|-----------|
| DPI resistance | High | Very high | High |
| Active probing resistance | High | Very high | High |
| Speed | Good | Poor | Variable |
| Stability | Good | Good | Medium |
| Ease of configuration | Medium | Medium | Easy |
| Requires manual bridges | Yes | No | No |
| Collateral damage for censor | Low | High (blocking CDN) | High (blocking WebRTC) |
| Availability | Depends on bridges | Limited by costs | Depends on volunteers |

### My choice

I use obfs4 because:
- It offers the best trade-off between speed and security
- I have configured and working bridges
- On university networks where I tested it, it was sufficient
- I do not need the anti-censorship level of meek/Snowflake (I am not in China/Iran)

For extreme censorship scenarios, meek or Snowflake would be the better choice
because they do not require specific bridges that can be discovered and blocked.

---

## See also

- [Bridges and Pluggable Transports](bridges-e-pluggable-transports.md) - Why bridges, obfs4, censorship resistance
- [torrc - Complete Guide](../02-installazione-e-configurazione/torrc-guida-completa.md) - Bridge configuration
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - DPI and bridges
- [VPN and Hybrid Tor](../06-configurazioni-avanzate/vpn-e-tor-ibrido.md) - Bridges vs VPN
- [Real-World Scenarios](scenari-reali.md) - Practical operational cases from a pentester
