> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/torsocks.md) | English

# torsocks - Dedicated LD_PRELOAD Wrapper for Tor

torsocks is an LD_PRELOAD wrapper designed **specifically for Tor**. Unlike
proxychains (which supports generic proxy chains), torsocks is optimized for
a single scenario: routing TCP traffic through the local Tor daemon,
actively blocking all traffic that could cause leaks.

> **See also**: [ProxyChains - Complete Guide](./proxychains-guida-completa.md)
> for the comparison, [DNS Leak](../05-sicurezza-operativa/dns-leak.md) for
> leak prevention, [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md)
> for IsolatePID.

---

## Table of Contents

- [How it works internally](#how-it-works-internally)
- [Intercepted syscalls](#intercepted-syscalls)
- [DNS handling in torsocks](#dns-handling-in-torsocks)
- [UDP blocking - detailed analysis](#udp-blocking---detailed-analysis)
- [Configuration](#configuration)
- [IsolatePID - automatic stream isolation](#isolatepid---automatic-stream-isolation)
- [Practical usage](#practical-usage)
- [Torsocks-ified interactive shell](#torsocks-ified-interactive-shell)
- [torsocks on - permanent activation](#torsocks-on---permanent-activation)
**Deep dives** (dedicated files):
- [torsocks Advanced](torsocks-avanzato.md) - Variables, edge cases, debugging, security, comparison

---

## How it works internally

### LD_PRELOAD mechanism

When you run `torsocks curl example.com`, the operating system:

```
1. Shell reads the command "torsocks curl example.com"
2. torsocks is a wrapper script that executes:
   LD_PRELOAD=/usr/lib/x86_64-linux-gnu/torsocks/libtorsocks.so curl example.com
3. The dynamic linker (ld-linux.so) loads libtorsocks.so BEFORE libc.so
4. The functions in libtorsocks.so "shadow" the identically named functions in libc.so
5. When curl calls connect() → the torsocks version is executed
6. torsocks redirects the connection to 127.0.0.1:9050 via SOCKS5
```

### The complete connection flow

```
curl example.com
  │
  ├─ getaddrinfo("example.com")
  │   → libtorsocks intercepts
  │   → does NOT resolve locally
  │   → returns a placeholder (or uses direct SOCKS5 hostname)
  │
  ├─ connect(socket_fd, sockaddr{IP, port})
  │   → libtorsocks intercepts
  │   → instead of direct connect(), it performs:
  │     1. connect(127.0.0.1:9050)         [connection to Tor]
  │     2. SOCKS5 handshake (version, auth)
  │     3. SOCKS5 CONNECT "example.com:443" [ATYP=0x03, hostname]
  │     4. Tor receives the hostname, builds circuit
  │     5. Exit node resolves DNS and connects
  │
  ├─ send()/recv() → pass normally through the SOCKS5 socket
  │
  └─ close() → closes the socket, torsocks performs cleanup
```

---

## Intercepted syscalls

torsocks intercepts these library calls (not direct syscalls):

| libc function | torsocks action |
|---------------|-----------------|
| `connect()` | Redirects TCP to SOCKS5, blocks UDP |
| `getaddrinfo()` | Intercepts, resolves via SOCKS5 |
| `gethostbyname()` | Intercepts, resolves via SOCKS5 |
| `gethostbyname_r()` | Thread-safe variant, intercepted |
| `getaddrinfo()` | Intercepts with hints for IPv4/IPv6 |
| `sendto()` | Blocks if UDP (e.g. direct DNS) |
| `sendmsg()` | Blocks if UDP |
| `socket()` | Monitors socket creation (for tracking) |
| `close()` | Cleanup of tracked connections |
| `getpeername()` | Returns real address, not SOCKS5 |

### What is NOT intercepted

```
- Direct syscalls (syscall(__NR_connect, ...))
  → Bypass libtorsocks completely
  
- Raw I/O functions (read/write on already connected socket)
  → Pass directly (the socket is already connected via SOCKS5)
  
- Non-libc functions (custom DNS implementations, etc.)
  → If the app implements its own resolver, torsocks does not see it
```

This is the fundamental limitation of the LD_PRELOAD approach: it only works
for applications that use standard libc functions.

---

## DNS handling in torsocks

### Resolution mechanism

Unlike proxychains (which uses dummy IPs from the `remote_dns_subnet` range),
torsocks handles DNS more cleanly:

```
Proxychains:
  getaddrinfo("example.com") → dummy mapping 224.0.0.1
  connect(224.0.0.1) → recognizes dummy → SOCKS5 CONNECT "example.com"

torsocks:
  getaddrinfo("example.com") → intercepted directly
  → generates SOCKS5 CONNECT with hostname
  → no dummy IP needed
```

### OnionAddrRange

For `.onion` addresses, torsocks uses a dummy IP range:

```ini
# torsocks.conf
OnionAddrRange 127.42.42.0/24
```

When an application resolves a `.onion` address:
1. torsocks assigns an IP from the `127.42.42.0/24` range
2. The app receives this IP and calls `connect()`
3. torsocks recognizes the range - sends via SOCKS5 with the .onion hostname
4. Tor handles the connection to the hidden service

### Direct UDP DNS blocking

If an application attempts to send a DNS query via direct UDP:

```
App → sendto(8.8.8.8:53, DNS_query)
  → torsocks intercepts sendto()
  → detects: destination port 53, protocol UDP
  → BLOCKS and logs:
    [warn] torsocks[12345]: UDP connection is not supported.
    Dropping connection to 8.8.8.8:53 on port 53
```

---

## UDP blocking - detailed analysis

### Why Tor does not support UDP

Tor is based on TCP circuits. The cell protocol (514 bytes, transport over
TLS/TCP) has no mechanism to encapsulate UDP datagrams. This means:

| Protocol | Tor | Consequence |
|----------|-----|-------------|
| TCP | Supported | HTTP, HTTPS, SSH, etc. work |
| UDP | **Not supported** | DNS, NTP, QUIC, WebRTC, VoIP blocked |
| ICMP | **Not supported** | ping, traceroute do not work |

### Applications affected by UDP blocking

| Application/Protocol | Uses UDP for | Effect with torsocks |
|---------------------|-------------|---------------------|
| Direct DNS (dig, nslookup) | DNS queries port 53 | Blocked, warning |
| NTP (ntpdate, timedatectl) | Clock synchronization | Blocked |
| QUIC / HTTP/3 | Modern web transport | Blocked, fallback to TCP |
| WebRTC | Audio/video P2P | Blocked completely |
| VoIP (SIP) | Signaling and media | Blocked |
| Online gaming | Game state updates | Blocked |
| mDNS | LAN service discovery | Blocked |
| DHCP | Network configuration | Not affected (L2 level) |

### Security advantage over proxychains

```
With proxychains:
  App → sendto(8.8.8.8:53) → proxychains does NOT intercept UDP
  → The UDP packet exits in the clear → DNS LEAK!

With torsocks:
  App → sendto(8.8.8.8:53) → torsocks INTERCEPTS and BLOCKS
  → No packet exits → No leak
  → Warning in log: UDP not supported
```

This is the single most important advantage of torsocks over proxychains from
a security standpoint.

---

## Configuration

### Configuration file

```bash
# Default path
/etc/tor/torsocks.conf

# Per-user override
~/.torsocks.conf
```

### Complete directives

```ini
# /etc/tor/torsocks.conf

# Address and port of the Tor daemon
TorAddress 127.0.0.1
TorPort 9050

# IP range for .onion address mapping
OnionAddrRange 127.42.42.0/24

# Allow inbound connections (for local servers)
AllowInbound 1

# Allow connections to localhost (127.0.0.0/8)
AllowOutboundLocalhost 1

# Stream isolation by PID
IsolatePID 1
```

| Directive | Default | Description |
|-----------|---------|-------------|
| `TorAddress` | 127.0.0.1 | IP of the Tor daemon |
| `TorPort` | 9050 | Tor SOCKS port |
| `OnionAddrRange` | 127.42.42.0/24 | Dummy IP range for .onion |
| `AllowInbound` | 0 | Allow inbound connections |
| `AllowOutboundLocalhost` | 0 | Allow connections to localhost |
| `IsolatePID` | 0 | Isolate circuits by PID |

---

## IsolatePID - automatic stream isolation

### How it works

When `IsolatePID 1`, torsocks uses the process PID as the SOCKS5
authentication credential:

```
Process curl (PID 12345):
  torsocks → SOCKS5 AUTH: username="12345" password=""
  Tor (with IsolateSOCKSAuth) → dedicated circuit for PID 12345

Process wget (PID 12346):
  torsocks → SOCKS5 AUTH: username="12346" password=""
  Tor → DIFFERENT circuit for PID 12346
```

### torrc requirement

To work, `SocksPort` must have `IsolateSOCKSAuth`:

```ini
# torrc
SocksPort 9050 IsolateSOCKSAuth
```

### Implications

- Two runs of `torsocks curl` use different circuits (different PIDs)
- A browser and a terminal use different circuits
- Fork of the same process: the child inherits the parent's PID (and circuit) - be careful with multi-process applications

---

## Practical usage

### Common commands

```bash
# Verify IP via Tor
torsocks curl https://api.ipify.org

# Download via Tor
torsocks wget https://example.com/file.zip

# SSH via Tor
torsocks ssh user@server.com

# git via Tor
torsocks git clone https://github.com/user/repo.git

# pip via Tor
torsocks pip3 install package_name

# Python script via Tor
torsocks python3 myscript.py

# Access .onion services
torsocks curl http://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/
```

### Commands that do NOT work

```bash
# ping → ICMP, not TCP
torsocks ping example.com
# Error: ICMP not supported

# traceroute → ICMP/UDP
torsocks traceroute example.com
# Error

# dig → UDP port 53
torsocks dig example.com
# [warn] UDP not supported, dropping connection

# nmap → various protocols
torsocks nmap -sV example.com
# Works ONLY with -sT (TCP connect scan), not with SYN scan
```

---

## Torsocks-ified interactive shell

```bash
# Open a shell where EVERYTHING goes through Tor
torsocks bash

# Now every command in this shell uses Tor
$ curl https://api.ipify.org     # → Tor exit IP
$ wget https://example.com       # → via Tor
$ ssh user@server.com            # → via Tor
$ python3 -c "import urllib.request; print(urllib.request.urlopen('https://api.ipify.org').read())"
                                  # → via Tor

$ exit  # returns to normal shell
```

**Warning**: in the torsocks-ified shell, *all* commands go through Tor,
including those that should not (e.g. `apt update` will be extremely slow).

---

## torsocks on - permanent activation

### How it works

```bash
# Activate torsocks for the current session
source torsocks on
# or
. torsocks on

# Now ALL commands go through Tor automatically
curl https://api.ipify.org     # → Tor IP, without "torsocks" prefix
wget https://example.com       # → via Tor

# Check status
torsocks show
# Tor mode activated. Every command will be torified for this shell.

# Deactivate
source torsocks off
# or
. torsocks off
```

### Internally

`torsocks on` exports the `LD_PRELOAD` variable:

```bash
# After "source torsocks on":
echo $LD_PRELOAD
# /usr/lib/x86_64-linux-gnu/torsocks/libtorsocks.so

# After "source torsocks off":
echo $LD_PRELOAD
# (empty)
```

### Difference with `torsocks bash`

| Method | Scope | Nesting |
|--------|-------|---------|
| `torsocks bash` | New child shell | Does not affect the parent shell |
| `source torsocks on` | Current shell | Modifies the ongoing session |
| `torsocks command` | Single command | No persistent effect |

---

---

> **Continues in**: [torsocks Advanced](torsocks-avanzato.md) for environment
> variables, edge cases, advanced debugging, security analysis, and comparison with proxychains.

---

## See also

- [torsocks Advanced](torsocks-avanzato.md) - Variables, edge cases, debugging, comparison
- [ProxyChains - Complete Guide](proxychains-guida-completa.md) - Alternative to torsocks
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - torsocks and DNS leak prevention
- [Circuit Control and NEWNYM](controllo-circuiti-e-newnym.md) - IsolatePID and circuits
- [Real-World Scenarios](scenari-reali.md) - Operational pentester cases
