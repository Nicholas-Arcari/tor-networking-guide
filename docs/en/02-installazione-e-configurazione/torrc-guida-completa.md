> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/torrc-guida-completa.md) | English

# torrc Configuration - Complete Guide to Every Directive

This document provides an in-depth analysis of the Tor configuration file (`/etc/tor/torrc`),
explaining every relevant directive with its low-level meaning, security implications,
and the values I have used in my practical experience on Kali Linux.

This is not a list of options: it is a reasoned guide on what each directive does internally
and why certain values are better than others.

---
---

## Table of Contents

- [The torrc file - Structure and syntax](#the-torrc-file---structure-and-syntax)
- [Section 1: Ports and network interfaces](#section-1-ports-and-network-interfaces)
- [Section 2: Logging](#section-2-logging)
**Deep dives** (dedicated files):
- [Bridge and Security in torrc](torrc-bridge-e-sicurezza.md) - Bridges, pluggable transports, advanced security
- [Performance, Relay and Full Configuration](torrc-performance-e-relay.md) - Tuning, relay, hidden services, complete torrc


## The torrc file - Structure and syntax

The `/etc/tor/torrc` file is Tor's main configuration file. The syntax is:

```ini
# Comments start with #
DirectiveName value
DirectiveName value1 value2   # some directives accept multiple values
```

- One directive per line
- Boolean values accept `0`/`1` or `true`/`false`
- File paths accept absolute paths
- Ports accept numbers or `auto`
- External files can be included with `%include /path/to/file`

### Configuration verification

Before restarting Tor, **always** verify:
```bash
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
```

This validates the syntax and values without starting the daemon. In my experience,
it has saved me multiple times from typos in bridge lines.

---

## Section 1: Ports and network interfaces

### SocksPort

```ini
SocksPort 9050
```

**What it does**: opens a SOCKS5 server on `127.0.0.1:9050`. Applications connect
here to route traffic through Tor.

**Internal details**:
- The SOCKS5 protocol negotiates the connection type (CONNECT, BIND, UDP ASSOCIATE)
- Tor only supports `CONNECT` (TCP). `UDP ASSOCIATE` is rejected.
- The client can specify the destination as a hostname (DOMAINNAME) or IP
- If the client sends a hostname, Tor resolves it via DNS through the Tor network
  (DNS never leaves the local machine)

**Advanced configurations**:
```ini
# Port with specific binding (not just localhost)
SocksPort 192.168.1.100:9050

# Port with isolation flags
SocksPort 9050 IsolateDestAddr IsolateDestPort

# Port with SOCKS authentication (for per-app isolation)
SocksPort 9050 IsolateSOCKSAuth

# Port without isolation (all streams share circuits)
SocksPort 9053 SessionGroup=1

# Port with SOCKS5 only (no SOCKS4)
SocksPort 9050 PreferSOCKSNoAuth

# Port with custom timeout
SocksPort 9050 KeepAliveIsolateSOCKSAuth
```

**Available isolation flags**:

| Flag | Effect |
|------|--------|
| `IsolateDestAddr` | Streams to different destinations -> different circuits |
| `IsolateDestPort` | Streams to different ports -> different circuits |
| `IsolateSOCKSAuth` | Different SOCKS username/password -> different circuits |
| `IsolateClientAddr` | Connections from different local IPs -> different circuits |
| `IsolateClientProtocol` | Different protocols (SOCKS4 vs SOCKS5) -> different circuits |
| `SessionGroup=N` | Groups streams into manual sessions |

**In my experience**: I use only `SocksPort 9050` without extra flags. Tor applies
reasonable default isolation. For a more advanced setup (e.g., browser separate
from CLI), I would configure multiple ports.

### DNSPort

```ini
DNSPort 5353
```

**What it does**: opens a DNS server on `127.0.0.1:5353`. DNS queries sent here are
resolved through the Tor network, not through the system DNS.

**Internal details**:
- Tor intercepts DNS queries and sends them as `RELAY_RESOLVE` cells through the
  circuit. The Exit Node resolves the hostname and responds with `RELAY_RESOLVED`.
- Port 5353 is used intentionally because it is not the standard DNS port (53).
  This avoids conflicts with local resolvers (systemd-resolved, dnsmasq).
- To make the system use this DNS, configure the resolver:
  ```bash
  # In /etc/resolv.conf (or equivalent)
  nameserver 127.0.0.1
  ```
  Then redirect port 53 to 5353, or use `DNSPort 53` (requires root).

**Why it matters**: without DNSPort, system DNS queries go out in cleartext
to the ISP's DNS. Even if HTTP traffic goes through Tor, DNS reveals which
sites you are visiting. This is a **DNS leak**.

**In my experience**: I use `DNSPort 5353` together with `proxy_dns` in proxychains.
When I use `proxychains curl`, DNS is resolved by Tor (the hostname is
sent in the SOCKS5 CONNECT as DOMAINNAME, not as IP). But applications that do not
go through proxychains can still cause DNS leaks.

### AutomapHostsOnResolve

```ini
AutomapHostsOnResolve 1
```

**What it does**: when an application requests resolution of a `.onion` hostname or
any hostname via DNSPort, Tor automatically assigns a fictitious IP address
(in the `VirtualAddrNetworkIPv4` range, default `127.192.0.0/10`) and
maintains an internal hostname -> fictitious IP mapping.

**Internal details**:
- The fictitious IP is never used on the network. It serves only as a local placeholder.
- When the application connects to the fictitious IP via SocksPort, Tor remaps
  it to the original hostname and resolves it through the Tor network.
- Essential for `.onion` addresses, which have no real IP.

### ControlPort

```ini
ControlPort 9051
CookieAuthentication 1
```

**What it does**: opens a control interface on `127.0.0.1:9051` that allows:
- Sending signals (NEWNYM, DORMANT, ACTIVE, HEARTBEAT, etc.)
- Querying circuit status
- Reading configuration information
- Monitoring events in real time

**Authentication methods**:

1. **CookieAuthentication** (recommended for local use):
   ```ini
   CookieAuthentication 1
   ```
   Tor generates a 32-byte cookie file at `/run/tor/control.authcookie`. To
   authenticate, the client reads the cookie and sends it as hex:
   ```
   AUTHENTICATE <32 bytes in hex>
   ```

2. **HashedControlPassword** (for remote or shared access):
   ```bash
   > tor --hash-password "MyPassword"
   16:872860B76453A77D60CA2BB8C1A7042072093276A3D701AD684053EC4C
   ```
   ```ini
   HashedControlPassword 16:872860B76453A77D60CA2BB8C1A7042072093276A3D701AD684053EC4C
   ```

**ControlPort protocol**: the protocol is text-based, similar to SMTP:
```
AUTHENTICATE <credentials>\r\n
250 OK\r\n
SIGNAL NEWNYM\r\n
250 OK\r\n
GETINFO circuit-status\r\n
250+circuit-status=
1 BUILT $FINGERPRINT1~Nick1,...
.\r\n
250 OK\r\n
QUIT\r\n
250 closing connection\r\n
```

**In my experience**, I use CookieAuthentication because it is more secure (the cookie
changes at every Tor restart) and does not require memorizing a password. My
`newnym` script reads the cookie like this:
```bash
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
```

### ClientUseIPv6

```ini
ClientUseIPv6 0
```

**What it does**: prevents Tor from using IPv6 connections to relays.

**Why to disable it**:
- Many networks do not properly support IPv6 -> failed connections
- IPv6 can reveal your network prefix (/64) which is often tied to your
  physical address
- If the system has IPv6 enabled but not properly configured, IPv6 connections
  can fail silently, slowing down bootstrap

**Technical detail**: when `ClientUseIPv6 0`, Tor filters out relays with only
IPv6 addresses from selection. This does not affect application traffic (which is
always TCP over IPv4 to the local SocksPort).

---

## Section 2: Logging

```ini
Log notice file /var/log/tor/notices.log
```

**Available log levels**:

| Level | Verbosity | Use |
|-------|-----------|-----|
| `err` | Fatal errors only | Production, automated monitoring |
| `warn` | Errors + warnings | Recommended for normal operations |
| `notice` | Warn + important normal events | **My default** |
| `info` | Notice + operational details | Light debugging |
| `debug` | Everything | Development only (WARNING: may log sensitive data) |

**Log destinations**:
```ini
Log notice file /var/log/tor/notices.log     # to file
Log notice syslog                            # to system syslog
Log notice stderr                            # to standard error
```

**WARNING about info and debug levels**: they can log request hostnames,
circuits with relay fingerprints, and connection timing. In a security context,
never use levels above `notice` in production.

**In my experience**, `notice` is the right level. It lets me see:
- Bootstrap progress
- Successful/failed bridge connections
- Configuration errors
- Guard changes

But it does not show details that could compromise anonymity if logs were
acquired.

### Monitoring logs in real time

```bash
sudo journalctl -u tor@default.service -f
# or
sudo tail -f /var/log/tor/notices.log
```

---

> **Continues in**: [Bridge and Security in torrc](torrc-bridge-e-sicurezza.md) for bridges,
> pluggable transports, and security directives, and in [Performance, Relay and Full
> Configuration](torrc-performance-e-relay.md) for tuning, relay configuration, and onion services.

---

## See also

- [Bridge and Security in torrc](torrc-bridge-e-sicurezza.md) - Bridges, pluggable transports, security
- [Performance, Relay and Full Configuration](torrc-performance-e-relay.md) - Tuning, relay, hidden services
- [Installation and Verification](installazione-e-verifica.md) - Initial setup before torrc
- [Service Management](gestione-del-servizio.md) - Restarting Tor after torrc changes
- [Real-World Scenarios](scenari-reali.md) - Pentester operational cases

---

## Cheat Sheet - Essential torrc directives

| Directive | Value | Description |
|-----------|-------|-------------|
| `SocksPort` | `9050` | SOCKS5 port for applications |
| `DNSPort` | `5353` | Local DNS port (resolves via Tor) |
| `ControlPort` | `9051` | Port to control Tor (Stem, nyx) |
| `CookieAuthentication` | `1` | Cookie authentication for ControlPort |
| `TransPort` | `9040` | Port for transparent proxy |
| `AutomapHostsOnResolve` | `1` | Maps hostnames to fictitious IPs |
| `ClientUseIPv6` | `0` | Disables IPv6 for clients |
| `UseBridges` | `1` | Enables bridge usage |
| `Bridge` | `obfs4 IP:PORT ...` | Configures an obfs4 bridge |
| `MaxCircuitDirtiness` | `600` | Seconds before circuit renewal |
| `ExitNodes` | `{cc}` | Forces exit from a country (not recommended) |
| `StrictNodes` | `1` | Enforces node selection (not recommended) |
| `Log` | `notice file /var/log/tor/tor.log` | Log file |
