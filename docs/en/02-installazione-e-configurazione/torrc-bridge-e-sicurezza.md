> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/torrc-bridge-e-sicurezza.md) | English

# Bridges, Pluggable Transports, and Security Directives in the torrc

Configuring obfs4 bridges, pluggable transports, and advanced security
directives: node selection, exclusions, padding, and network restrictions.

Extracted from [torrc - Complete Guide](torrc-guida-completa.md).

---

## Table of Contents

- [Bridges and Pluggable Transports](#bridges-and-pluggable-transports)
- [Advanced security directives](#advanced-security-directives)

---

## Bridges and Pluggable Transports

### UseBridges

```ini
UseBridges 1
```

**What it does**: tells Tor to connect to the network through bridges instead of
public relays. Tor will not attempt to connect directly to guards in the consensus.

**When to enable it**:
- The ISP blocks connections to known Tor relays
- You want to hide Tor usage from the ISP
- The network has DPI that identifies and blocks Tor traffic
- You are in a country with active censorship

### ClientTransportPlugin

```ini
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
```

**What it does**: registers `obfs4proxy` as an available pluggable transport. When Tor
needs to connect to an obfs4 bridge, it invokes `/usr/bin/obfs4proxy` as a child
process.

**Internal details**:
- Tor communicates with obfs4proxy via the PT (Pluggable Transport) protocol
- obfs4proxy opens a local port (dynamically chosen)
- Tor connects to this local port
- obfs4proxy obfuscates the traffic and forwards it to the remote bridge
- The remote bridge has a server-side obfs4proxy instance that de-obfuscates

### Bridge Directives

```ini
Bridge obfs4 <IP>:<PORT> <FINGERPRINT> cert=<CERT> iat-mode=<0|1|2>
```

**Components**:
- `obfs4` - pluggable transport type
- `<IP>:<PORT>` - bridge address (IPv4 or IPv6)
- `<FINGERPRINT>` - bridge relay fingerprint (20 bytes hex)
- `cert=<CERT>` - obfs4 certificate of the bridge (base64)
- `iat-mode` - timing mode:
  - `0` - no temporal padding (faster, less secure)
  - `1` - moderate temporal padding (recommended)
  - `2` - maximum temporal padding (slower, maximum DPI resistance)

**In my experience**:
```ini
Bridge obfs4 xxx.xxx.xxx.xxx:4431 F829D395093B... cert=... iat-mode=0
Bridge obfs4 xxx.xxx.xxx.xxx:13630 A3D55AA6178... cert=... iat-mode=2
```

I configured two bridges with different iat-mode values. The first (iat-mode=0) is faster
and I use it as the primary. The second (iat-mode=2) is the fallback for situations where
DPI is aggressive.

**How to obtain bridges**:
1. `https://bridges.torproject.org/options` - official website (requires CAPTCHA)
2. Email `bridges@torproject.org` with body `get transport obfs4` (from Gmail or Riseup)
3. Snowflake - bridges via volunteer browsers (less stable)

**Note from my experience**: initially I used an incorrect URL for bridges
(`https://bridges.torproject.org/bridges`, suggested by ChatGPT). The correct URL is
`https://bridges.torproject.org/options`. The received bridges must be inserted exactly
as provided, including the full certificate.

---

## Advanced security directives

### ExitNodes, EntryNodes, StrictNodes

```ini
# Force exits in a specific country
ExitNodes {de},{nl}
StrictNodes 1

# Exclude exits from certain countries
ExcludeExitNodes {ru},{cn},{ir}

# Force specific entries
EntryNodes {se},{ch}
```

**WARNING**: using `ExitNodes` with `StrictNodes 1` is generally **not recommended**:
- Drastically reduces the pool of available exits
- Increases the probability of saturating the few remaining exits
- Makes traffic more recognizable (fingerprinting: "this user always exits from Germany")
- If the few available exits are offline, Tor stops working

**In my experience**, I tried `ExitNodes {it}` to exit with an Italian IP.
The result was:
- Very few available Italian exits
- Worse latency (paradoxically, because the few exits were overloaded)
- Unstable circuits
- I removed the directive and let Tor choose freely

### ExcludeNodes

```ini
ExcludeNodes {cn},{ru},{ir},{kp}
```

**What it does**: completely excludes relays in these countries from any position
in the circuit (guard, middle, exit). More reasonable than `ExitNodes` because it
does not limit to a few relays but excludes some.

### MapAddress

```ini
MapAddress www.example.com www.example.com.torproject.org
MapAddress 10.0.0.0/8 0.0.0.0/8
```

**What it does**: allows redirecting hostnames or IP ranges at the Tor level. Useful
for testing or for forcing the routing of certain destinations.

### ReachableAddresses

```ini
ReachableAddresses *:80, *:443
ReachableAddresses reject *:*
```

**What it does**: limits the ports Tor can use to reach relays.
Useful if you are behind a firewall that only allows HTTP/HTTPS traffic.

**Detail**: this concerns the Tor->relay connection, not application traffic.
If your firewall only allows ports 80 and 443, configure `ReachableAddresses`
accordingly and Tor will select only relays with ORPort on those ports.

### ConnectionPadding

```ini
ConnectionPadding 1      # Enable padding between relays (default: auto)
ReducedConnectionPadding 0  # Do not reduce padding (default)
```

**What it does**: Tor sends padding cells on connections between relays to mask
traffic patterns. `ConnectionPadding 1` forces padding even when it would not
otherwise be activated.

---

## See also

- [torrc - Complete Guide](torrc-guida-completa.md) - Structure, ports, logging
- [Performance, Relay and Full Configuration](torrc-performance-e-relay.md) - Tuning, relay, hidden services
- [Bridges and Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Deep dive on bridges and obfs4
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - Padding and traffic analysis resistance
- [Real-World Scenarios](scenari-reali.md) - Pentester operational cases
