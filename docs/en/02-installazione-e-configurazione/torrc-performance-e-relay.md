> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/torrc-performance-e-relay.md) | English

# Performance, Relay, and Full torrc Configuration

Performance and tuning directives, relay configuration (middle, bridge, exit),
onion services, and a fully annotated torrc configuration.

Extracted from [torrc - Complete Guide](torrc-guida-completa.md).

---

## Table of Contents

- [Performance and tuning](#performance-and-tuning)
- [Relay configuration](#relay-configuration)
- [Hidden Services (Onion Services v3)](#hidden-services-onion-services-v3)
- [My complete configuration](#my-complete-configuration)

---

## Performance and tuning

### CircuitBuildTimeout

```ini
CircuitBuildTimeout 60
```

**What it does**: timeout in seconds for building a circuit. If a circuit is not
built within this time, it is abandoned and Tor tries another one.

**Default**: Tor dynamically calculates this value based on past experience.
Setting it manually overrides the adaptive calculation.

### LearnCircuitBuildTimeout

```ini
LearnCircuitBuildTimeout 1
```

**What it does**: allows Tor to adapt the timeout based on real-world experience.
If the network is slow (e.g., via obfs4 bridges), Tor increases the timeout. If it
is fast, it reduces it.

### NumEntryGuards

```ini
NumEntryGuards 1
```

**What it does**: number of persistent guards to maintain. The default is 1 (it used to be 3).

**Why 1 is better than 3**: with a single guard, there is a 1 in ~1000 chance that the
guard is malicious. With 3 guards, there are 3 chances in ~1000. Fewer guards = less
risk of having a malicious guard over time.

### MaxCircuitDirtiness

```ini
MaxCircuitDirtiness 600
```

**What it does**: time in seconds after which a "dirty" circuit (one that has carried
at least one stream) is not reused for new streams. Default: 600 (10 minutes).

**Implication**: after 10 minutes, new connections will use a new circuit
(potentially with a new exit and a new IP). This is why your visible
IP changes periodically even without NEWNYM.

---

## Relay configuration

These directives are for those who want to contribute to the Tor network by operating a relay.
I have not enabled them in my configuration, but I document them for completeness.

### ORPort

```ini
ORPort 9001
# or with specific binding
ORPort 443 NoListen
ORPort 127.0.0.1:9001 NoAdvertise
```

**What it does**: opens the Onion Router port, which accepts connections from other Tor relays.
Enabling ORPort turns your system into a Tor relay.

### Relay Bandwidth

```ini
RelayBandwidthRate 1 MB    # Throttle to 1 MB/s
RelayBandwidthBurst 2 MB   # Burst up to 2 MB/s
AccountingMax 500 GB       # Maximum 500 GB per period
AccountingStart month 1 00:00  # Monthly period
```

### Relay as bridge

```ini
BridgeRelay 1
PublishServerDescriptor 0   # Do not publish in the consensus (private bridge)
ServerTransportPlugin obfs4 exec /usr/bin/obfs4proxy
ServerTransportListenAddr obfs4 0.0.0.0:8443
ExtORPort auto
```

### Exit Policy (if the relay is an exit)

```ini
# Allow web only
ExitPolicy accept *:80
ExitPolicy accept *:443
ExitPolicy reject *:*

# Or: restrictive but allow common services
ExitPolicy accept *:20-23     # FTP, SSH, Telnet
ExitPolicy accept *:53        # DNS
ExitPolicy accept *:80        # HTTP
ExitPolicy accept *:443       # HTTPS
ExitPolicy accept *:993       # IMAPS
ExitPolicy accept *:995       # POP3S
ExitPolicy reject *:*
```

---

## Hidden Services (Onion Services v3)

```ini
HiddenServiceDir /var/lib/tor/hidden_service/
HiddenServicePort 80 127.0.0.1:8080
```

**What it does**: configures an onion service that makes a local service
(port 8080) reachable via a `.onion` address on port 80.

**Internal details**:
- Tor generates an Ed25519 key pair in `HiddenServiceDir`
- The `.onion` address is derived from the public key (56 characters for v3)
- Tor publishes encrypted descriptors on HSDir nodes within the Tor network
- Clients that know the `.onion` address use the descriptor to establish
  a rendezvous circuit

This is covered in depth in the dedicated onion services document.

---

## My complete configuration

Here is my complete torrc, with comments explaining every choice:

```ini
# === Client ports ===
SocksPort 9050                    # Primary SOCKS5 proxy
DNSPort 5353                      # DNS via Tor
AutomapHostsOnResolve 1           # Automatic .onion and hostname mapping

# === Control ===
ControlPort 9051                  # For NEWNYM and monitoring
CookieAuthentication 1            # Auth via cookie file

# === Security ===
ClientUseIPv6 0                   # No IPv6 (prevents leaks)

# === Data ===
DataDirectory /var/lib/tor

# === Logging ===
Log notice file /var/log/tor/notices.log

# === Bridge obfs4 ===
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
Bridge obfs4 xxx.xxx.xxx.xxx:4431 F829D395093B... cert=... iat-mode=0
Bridge obfs4 xxx.xxx.xxx.xxx:13630 A3D55AA6178... cert=... iat-mode=2
```

This configuration:
- Routes traffic through obfs4 bridges (hides Tor usage from the ISP)
- Prevents DNS leaks (DNSPort + AutomapHostsOnResolve)
- Prevents IPv6 leaks (ClientUseIPv6 0)
- Allows IP rotation via ControlPort (NEWNYM)
- Logs at notice level for troubleshooting without compromising privacy

---

## See also

- [torrc - Complete Guide](torrc-guida-completa.md) - Structure, ports, logging
- [Bridge and Security in torrc](torrc-bridge-e-sicurezza.md) - Bridges, pluggable transports, security
- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) - Onion services deep dive
- [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Multiple SocksPort
- [Relay Monitoring and Metrics](../03-nodi-e-rete/relay-monitoring-e-metriche.md) - Relay monitoring
- [Real-World Scenarios](scenari-reali.md) - Pentester operational cases
