> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/nyx-e-monitoraggio.md) | English

# Nyx - Real-Time Tor Monitoring

Nyx (formerly called `arm`) is a TUI (Text User Interface) monitor for the
Tor daemon. It allows real-time visualization of circuits, bandwidth, connections,
logs, and configuration. It is the essential tool for understanding what Tor
is doing at any given moment.

> **See also**: [Circuit Control and NEWNYM](./controllo-circuiti-e-newnym.md) for
> the ControlPort protocol, [Service Management](../02-installazione-e-configurazione/gestione-del-servizio.md)
> for bootstrap and logs, [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) for guard selection.

---

## Table of Contents

- [Installation and dependencies](#installation-and-dependencies)
- [Internal architecture of Nyx](#internal-architecture-of-nyx)
- [Screen 1: Bandwidth Graph](#screen-1-bandwidth-graph)
- [Screen 2: Connections](#screen-2-connections)
- [Screen 3: Configuration](#screen-3-configuration)
- [Screen 4: Log](#screen-4-log)
- [Screen 5: Interpretor](#screen-5-interpretor)
**Deep dives** (dedicated files):
- [Nyx Advanced](nyx-avanzato.md) - Navigation, configuration, debugging, Stem, integration

---

## Installation and dependencies

### Installation on Kali/Debian

```bash
# Method 1: apt (recommended on Kali)
sudo apt install nyx

# Method 2: pip (more recent version)
pip3 install nyx

# Verify version
nyx --version
# nyx version 2.1.0 (stem 1.8.1)
```

### Dependencies

Nyx depends on:
- **Stem** (Python library for the Tor ControlPort) - installed automatically
- **Python 3.5+** - present by default on Kali
- **curses** - TUI library, part of the Python standard library

### Tor requirements

Nyx requires access to the ControlPort:

```ini
# torrc - necessary for nyx
ControlPort 9051
CookieAuthentication 1
```

The user must be in the `debian-tor` group to read the cookie:

```bash
# Verify group membership
groups | grep debian-tor

# If not present:
sudo usermod -aG debian-tor $USER
# → logout and login required
```

### Startup

```bash
# Default connection (127.0.0.1:9051)
nyx

# Specify port
nyx -i 127.0.0.1:9051

# Specify socket file
nyx -s /run/tor/control

# With password (if not using CookieAuthentication)
nyx -i 127.0.0.1:9051 -p "your_password"
```

---

## Internal architecture of Nyx

### How Nyx communicates with Tor

Nyx uses the Stem library to connect to Tor's ControlPort. The flow:

```
[Nyx TUI] → [Stem library] → [ControlPort TCP 9051] → [Tor daemon]
                                    ↓
                         Text-based protocol:
                         AUTHENTICATE <cookie>
                         SETEVENTS BW CIRC STREAM ORCONN
                         GETINFO circuit-status
                         GETCONF SocksPort
```

### Subscribed events

At startup, Nyx registers to receive real-time events:

| Event | Description | Use in Nyx |
|-------|-------------|------------|
| `BW` | Bandwidth read/written (every second) | Bandwidth graph |
| `CIRC` | Circuit state changes | Circuit list |
| `STREAM` | Stream state changes | Active connections |
| `ORCONN` | OR connections (relay-to-relay) | Connection list |
| `NEWDESC` | New descriptors available | Relay info update |
| `NOTICE` / `WARN` / `ERR` | Log events | Log screen |

### GETINFO commands used

```
GETINFO version                    → Tor version
GETINFO circuit-status             → All circuits
GETINFO stream-status              → All streams
GETINFO orconn-status              → OR connections
GETINFO ns/all                     → Network status (consensus)
GETINFO traffic/read               → Total bytes read
GETINFO traffic/written            → Total bytes written
GETINFO process/pid                → Tor daemon PID
GETINFO process/descriptor-limit   → File descriptor limit
```

### Refresh rate

Nyx updates the interface:
- **Bandwidth**: every 1 second (based on `BW` event)
- **Connections**: every 5 seconds (polling `GETINFO orconn-status`)
- **Circuits**: event-driven (updated on every `CIRC` event)
- **Log**: event-driven (updated on every log event)

---

## Screen 1: Bandwidth Graph

The first screen shows an ASCII bandwidth graph in real time:

```
┌──────────────────────────────────────────────────────────────┐
│ Tor Bandwidth (since 2024-12-15 09:23:41):                   │
│                                                              │
│ 250 KB/s ┤                                                   │
│ 200 KB/s ┤        ▄▆                                         │
│ 150 KB/s ┤   ▂▄▆▇██▇▅                                       │
│ 100 KB/s ┤ ▄████████████▇▅▃                                  │
│  50 KB/s ┤████████████████████▇▅▃▂▁     ▂▃▅                  │
│   0 KB/s ┤██████████████████████████▇▅▃▂█████▇▅▃▂▁           │
│          └──────────────────────────────────────────          │
│                                                              │
│ Download: 127 KB/s   Upload: 43 KB/s                         │
│ Total: 1.2 GB down, 456 MB up (this session)                 │
│ Avg: 89 KB/s down, 31 KB/s up                                │
└──────────────────────────────────────────────────────────────┘
```

### Displayed statistics

| Statistic | Description |
|-----------|-------------|
| Current | Instantaneous bandwidth (last second) |
| Average | Average since session start |
| Total | Total bytes transferred |
| Min/Max | Minimum and maximum peaks |

### Aggregation periods

Press `s` on the bandwidth screen:

| Period | Granularity | Usage |
|--------|-------------|-------|
| 1 second | Real-time | Live monitoring |
| 5 seconds | Moving average | Traffic patterns |
| 30 seconds | Short trend | Connection stability |
| 10 minutes | Medium trend | Circuit performance |
| 1 hour | Long trend | Full session |
| 1 day | Overview | Relay operators |

### Accounting (for relay operators)

If you operate a relay with bandwidth accounting:

```ini
# torrc relay
AccountingMax 50 GBytes
AccountingStart month 1 00:00
```

Nyx shows on the bandwidth screen:
- Used quota / total quota
- Time remaining in the period
- Hibernate state (if quota reached)

---

## Screen 2: Connections

Shows all active TCP connections of the Tor daemon:

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Connections (ctrl+l: resolve, s: sort, enter: details)                   │
│                                                                          │
│ Type    Address               Fingerprint     Nickname      Time  Circ   │
│ ──────────────────────────────────────────────────────────────────────    │
│ Guard   198.51.100.42:9001    AABB...CC01     MyGuardNode   3h   5,7,12 │
│ Middle  203.0.113.88:443      EEFF...GG02     FastMiddle    45m  5      │
│ Middle  192.0.2.77:9001       1122...3344     TorRelay99    12m  7      │
│ Exit    45.33.32.156:443      5566...7788     ExitDE        45m  5      │
│ Exit    104.244.76.13:443     99AA...BB01     ExitFR        12m  7      │
│ Dir     128.31.0.34:9131      CC00...DD02     moria1        2h   -      │
│ Control 127.0.0.1:9051        -               -             3h   -      │
│ Socks   127.0.0.1:45678       -               -             2m   5      │
│                                                                          │
│ 8 connections (3 relays, 2 exits, 1 directory, 1 control, 1 client)      │
└──────────────────────────────────────────────────────────────────────────┘
```

### Available columns

| Column | Description |
|--------|-------------|
| Type | Guard, Middle, Exit, Directory, Control, Socks, Bridge |
| Address | IP:port of the remote relay |
| Fingerprint | SHA-1 hash of the identity key (truncated) |
| Nickname | Name chosen by the relay operator |
| Time | Connection duration |
| Circuit | IDs of circuits using this connection |

### Connection details (Enter)

Press Enter on a connection:

```
Connection Details:
  Address:     198.51.100.42:9001
  Fingerprint: AABBCCDD11223344556677889900AABBCCDD1122
  Nickname:    MyGuardNode
  Type:        Guard
  
  Country:     Germany (DE)
  AS:          AS24940 (Hetzner Online GmbH)
  Platform:    Tor 0.4.8.10 on Linux
  
  Flags:       Fast, Guard, HSDir, Running, Stable, V2Dir, Valid
  Bandwidth:   45000 KB/s (advertised), 38000 KB/s (measured)
  Uptime:      45 days, 12 hours
  
  Circuits using this connection: 5, 7, 12
```

### GeoIP and resolution

Nyx uses Tor's GeoIP database to show:
- Relay country (ISO code)
- ASN (Autonomous System Number)
- Organization (ISP/hosting provider)

```bash
# Tor's GeoIP database:
/usr/share/tor/geoip
/usr/share/tor/geoip6
```

### Filters and sorting

| Shortcut | Action |
|----------|--------|
| `s` | Sort by column (type, address, fingerprint, bandwidth, country) |
| `u` | Filter by type (relay, exit, directory, control) |
| `/` | Search by nickname or fingerprint |

---

## Screen 3: Configuration

Shows all torrc directives with current values:

```
┌──────────────────────────────────────────────────────────────┐
│ Configuration (enter: edit, s: sort, /: search)               │
│                                                               │
│ Directive              Value              Type     Is Set     │
│ ──────────────────────────────────────────────────────────    │
│ SocksPort              9050               Port     Yes        │
│ DNSPort                5353               Port     Yes        │
│ ControlPort            9051               Port     Yes        │
│ CookieAuthentication   1                  Boolean  Yes        │
│ ClientUseIPv6          0                  Boolean  Yes        │
│ UseBridges             1                  Boolean  Yes        │
│ ConnectionPadding      1                  Boolean  Default    │
│ CircuitBuildTimeout    60                 Interval Default    │
│ MaxCircuitDirtiness    600                Interval Default    │
│ NumEntryGuards         1                  Integer  Default    │
│ ...                                                           │
└──────────────────────────────────────────────────────────────┘
```

### Information for each directive

- **Directive**: torrc directive name
- **Value**: current (runtime) value
- **Type**: data type (Port, Boolean, Interval, String, etc.)
- **Is Set**: whether it is explicitly in the torrc or using the default

### Runtime modification

Nyx allows modifying some directives without restart via `SETCONF`:

```
# Example: change MaxCircuitDirtiness at runtime
SETCONF MaxCircuitDirtiness=300
```

**Warning**: not all directives are modifiable at runtime. Those that
require restart (such as `SocksPort`, `ControlPort`) cannot be changed.

---

## Screen 4: Log

Shows Tor logs in real time with filters:

```
┌──────────────────────────────────────────────────────────────────┐
│ Log (filter: NOTICE+, s: select level, /: search, c: clear)      │
│                                                                   │
│ 09:23:41 [NOTICE] Bootstrapped 100% (done): Done                 │
│ 09:24:02 [NOTICE] New control connection opened from 127.0.0.1   │
│ 09:25:15 [NOTICE] Tried for 120 seconds to get a connection to   │
│          [scrubbed]:443. Giving up. (waiting for circuit)         │
│ 09:26:01 [WARN] Problem bootstrapping. Stuck at 10% (Handshaking │
│          with a]relay): TIMEOUT. (1 attempts so far.)             │
│ 09:26:45 [NOTICE] NEWNYM command received. Closing circuits.      │
│ 09:26:46 [NOTICE] New circuit built successfully.                 │
│ 09:27:12 [NOTICE] Heartbeat: Tor's uptime is 3:45 hours.         │
│          Tor has successfully opened 1 circuit. In the last hour  │
│          we relayed 0 cells and 0 connections.                    │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Log levels

| Level | Color in Nyx | Typical content |
|-------|-------------|-----------------|
| `ERR` | Red | Critical errors, unable to operate |
| `WARN` | Yellow | Bootstrap failed, timeouts, network issues |
| `NOTICE` | White | Bootstrap, NEWNYM, heartbeat, new circuits |
| `INFO` | Cyan | Operational details, relay selection, circuit build |
| `DEBUG` | Gray | Every single operation (very verbose) |

### Log filters

```
Shortcut 's' → select minimum level:
  ERR      → critical errors only
  WARN     → warnings + errors
  NOTICE   → notices + warnings + errors (default)
  INFO     → very detailed
  DEBUG    → extremely verbose
```

### Log search

`/` to search with regex in the logs. Useful for:
- Searching bootstrap errors: `/bootstrap`
- Finding circuit issues: `/circuit.*failed`
- Verifying NEWNYM: `/NEWNYM`

### Log during bootstrap

The log is essential for diagnosing startup issues:

```
[NOTICE] Bootstrapped 0% (starting): Starting
[NOTICE] Bootstrapped 5% (conn_dir): Connecting to a directory server
[NOTICE] Bootstrapped 10% (handshake_dir): Finishing handshake with directory server
[NOTICE] Bootstrapped 15% (onehop_create): Establishing an encrypted directory connection
[NOTICE] Bootstrapped 20% (requesting_status): Asking for networkstatus consensus
[NOTICE] Bootstrapped 25% (loading_status): Loading networkstatus consensus
[NOTICE] Bootstrapped 40% (loading_keys): Loading authority key certs
[NOTICE] Bootstrapped 45% (requesting_descriptors): Asking for relay descriptors
[NOTICE] Bootstrapped 50% (loading_descriptors): Loading relay descriptors
[NOTICE] Bootstrapped 80% (conn_or): Connecting to the Tor network
[NOTICE] Bootstrapped 85% (handshake_or): Finishing handshake with first hop
[NOTICE] Bootstrapped 90% (circuit_create): Establishing a Tor circuit
[NOTICE] Bootstrapped 100% (done): Done
```

If bootstrap stalls at a specific point, the Nyx log shows exactly where.

---

## Screen 5: Interpretor

The built-in REPL for direct ControlPort commands. Accessible by pressing `→` until
the fifth screen:

```
┌──────────────────────────────────────────────────────────────┐
│ Interpretor (enter command, tab: autocomplete)                │
│                                                               │
│ >>> GETINFO version                                           │
│ 250-version=0.4.8.10                                          │
│ 250 OK                                                        │
│                                                               │
│ >>> GETINFO circuit-status                                    │
│ 250+circuit-status=                                           │
│ 5 BUILT $AABB...01~Guard,$EEFF...02~Middle,$5566...03~Exit   │
│    PURPOSE=GENERAL TIME_CREATED=2024-12-15T09:25:01           │
│ 7 BUILT $AABB...01~Guard,$1122...04~Middle,$99AA...05~Exit   │
│    PURPOSE=GENERAL TIME_CREATED=2024-12-15T09:26:45           │
│ 250 OK                                                        │
│                                                               │
│ >>> SIGNAL NEWNYM                                             │
│ 250 OK                                                        │
│                                                               │
│ >>> _                                                          │
└──────────────────────────────────────────────────────────────┘
```

### Useful interpretor commands

```
# System information
GETINFO version
GETINFO process/pid
GETINFO traffic/read
GETINFO traffic/written

# Circuits and streams
GETINFO circuit-status
GETINFO stream-status
GETINFO orconn-status

# Network status
GETINFO ns/all                    # all relays in the consensus
GETINFO ns/name/MyRelay           # info on a specific relay
GETINFO ns/id/AABBCCDD...         # info by fingerprint

# Signals
SIGNAL NEWNYM                     # new identity
SIGNAL RELOAD                     # reload torrc
SIGNAL SHUTDOWN                   # clean shutdown

# Configuration
GETCONF SocksPort
GETCONF ExitNodes
SETCONF MaxCircuitDirtiness=300

# DNS resolution
RESOLVE example.com
```

The interpretor has Tab autocompletion, which lists all available commands and
options.

---

---

> **Continues in**: [Nyx Advanced](nyx-avanzato.md) for navigation, shortcuts,
> advanced configuration, debugging scenarios, and scripting with Stem.

---

## See also

- [Nyx Advanced](nyx-avanzato.md) - Navigation, configuration, debugging, Stem
- [Circuit Control and NEWNYM](controllo-circuiti-e-newnym.md) - ControlPort and Stem scripting
- [Relay Monitoring and Metrics](../03-nodi-e-rete/relay-monitoring-e-metriche.md) - Relay monitoring
- [Service Management](../02-installazione-e-configurazione/gestione-del-servizio.md) - systemd, logs, debug
- [Real-World Scenarios](scenari-reali.md) - Operational pentester cases
