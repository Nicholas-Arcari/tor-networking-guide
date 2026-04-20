> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/tor-e-dns-risoluzione.md) | English

# Tor and DNS - Resolution, Leaks and Automapping

DNS resolution is one of the most underestimated deanonymization vectors when using
Tor. This document analyzes the entire DNS resolution chain when using
Tor: from the moment an application requests a hostname to the response that
arrives from the exit node.

> **See also**: [DNS Leak](../05-sicurezza-operativa/dns-leak.md) for leak
> prevention, [ProxyChains](./proxychains-guida-completa.md) for `proxy_dns`,
> [torrc Complete Guide](../02-installazione-e-configurazione/torrc-guida-completa.md)
> for DNSPort configuration.

---

## Table of Contents

- [How normal DNS resolution works](#how-normal-dns-resolution-works)
- [The problem: DNS and anonymity](#the-problem-dns-and-anonymity)
- [How Tor resolves DNS](#how-tor-resolves-dns)
- [DNSPort - Tor's local resolver](#dnsport---tors-local-resolver)
- [AutomapHostsOnResolve - the mapping mechanism](#automaphostsonresolve---the-mapping-mechanism)
- [SOCKS5 remote DNS resolution](#socks5-remote-dns-resolution)
- [Interaction with systemd-resolved](#interaction-with-systemd-resolved)
**Deep dives** (dedicated files):
- [Advanced DNS and Hardening](dns-avanzato-e-hardening.md) - resolv.conf, proxy_dns, .onion, detailed leaks, hardening

---

## How normal DNS resolution works

Before understanding how Tor handles DNS, it is essential to understand the normal flow:

```
Application calls getaddrinfo("example.com")
  → glibc reads /etc/nsswitch.conf
  → nsswitch: "hosts: files dns" → first /etc/hosts, then DNS
  → glibc reads /etc/resolv.conf → finds "nameserver 192.168.1.1"
  → UDP DNS query packet (port 53) → local router
  → router forwards to ISP DNS (e.g. Comeser: 62.94.0.1)
  → DNS response → IP 93.184.216.34
  → application calls connect(93.184.216.34)
```

Every step is a potential leak:

| Point | Who sees | What they see |
|-------|----------|---------------|
| `/etc/resolv.conf` | Local system | Which DNS server is configured |
| UDP port 53 → router | Router/ISP | Which domain you are resolving |
| ISP DNS | ISP (Comeser in my case) | All the domains you visit |
| DNS response | Anyone intercepting | hostname-to-IP association |

DNS is **in the clear** (UDP port 53) and **unauthenticated**. Any
observer between you and the DNS server sees exactly where you are browsing.

---

## The problem: DNS and anonymity

When you use Tor without DNS precautions:

```
DANGEROUS SCENARIO:
[App] → getaddrinfo("target.com") → DNS in the clear to your ISP ← LEAK!
[App] → connect(IP) → via SOCKS5 → Tor → exit → target.com

The ISP sees: "The user resolved target.com at 14:32"
Tor protects: the TCP connection to the IP
Result: the ISP knows exactly what you are visiting
```

Even if TCP traffic is anonymous via Tor, the DNS query reveals the destination.
This is the **DNS leak** in its most basic form: name resolution
occurs outside the Tor tunnel.

### DNS + timing correlation

An adversary observing both DNS and Tor traffic can:

1. See DNS query for `target.com` from your real IP
2. See Tor connection from the same IP 500ms later
3. Correlate with certainty: it is you visiting `target.com` via Tor

The correlation window is very narrow (milliseconds), making the attack
nearly deterministic.

---

## How Tor resolves DNS

Tor offers three mechanisms for resolving DNS securely:

### 1. SOCKS5 with hostname (remote resolution)

The preferred method. The application sends the hostname (not the IP) to the SOCKS5 proxy:

```
SOCKS5 flow with hostname:
  Client → SOCKS5 proxy (Tor): CONNECT "example.com:443"
  Tor receives the hostname as a string
  Tor forwards it in the circuit as RELAY_BEGIN
  The exit node resolves DNS locally
  The exit node connects to the resulting IP
  → No local DNS resolution
```

At the SOCKS5 protocol level:

```
Client → Tor:
  VER: 0x05
  CMD: 0x01 (CONNECT)
  ATYP: 0x03 (DOMAINNAME)  ← key: hostname, not IP
  DST.ADDR: length + "example.com"
  DST.PORT: 0x01BB (443)

Tor → Circuit:
  RELAY_BEGIN cell:
    Payload: "example.com:443\0"
    → The exit node receives the hostname and performs DNS resolution
```

### 2. DNSPort - dedicated local resolver

Tor exposes a UDP port that accepts standard DNS queries and resolves them via circuit:

```
[App] → DNS UDP query → 127.0.0.1:5353 (Tor DNSPort)
  → Tor encapsulates in RELAY_RESOLVE cell
  → Tor circuit → exit node
  → Exit node performs DNS query
  → DNS response returns in the circuit
  → Tor responds to the local UDP query
```

### 3. TransPort with AutomapHosts

For transparent proxy, Tor automatically maps hostnames to dummy IPs:

```
[App] → DNS query "example.com" → DNSPort
  → Tor assigns 10.192.0.42 as dummy IP
  → Responds to the app: "example.com = 10.192.0.42"
[App] → connect(10.192.0.42) → iptables REDIRECT → TransPort 9040
  → Tor sees 10.192.0.42 → knows it is "example.com"
  → RELAY_BEGIN "example.com:443"
```

---

## DNSPort - Tor's local resolver

### Configuration

```ini
# torrc
DNSPort 5353
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
```

### How it works internally

DNSPort opens a UDP socket on `127.0.0.1:5353`. When it receives a DNS query:

1. **Query parsing**: Tor decodes the DNS packet (RFC 1035 format)
2. **RELAY_RESOLVE creation**: generates a `RELAY_RESOLVE` cell with the hostname
3. **Circuit transmission**: the cell travels through Guard - Middle - Exit
4. **Remote resolution**: the exit node performs the DNS query with its resolver
5. **RELAY_RESOLVED response**: the exit sends the response in the circuit
6. **DNS response composition**: Tor constructs a DNS response packet
7. **Delivery to application**: UDP response to the requesting application

### Supported query types

| Type | Support | Notes |
|------|---------|-------|
| A (IPv4) | Full | Standard resolution |
| AAAA (IPv6) | Partial | Depends on `ClientUseIPv6` |
| PTR (reverse) | Full | For `.onion` and normal IPs |
| CNAME | Full | Follows the chain |
| MX, TXT, SRV | **No** | Not supported by the RELAY_RESOLVE protocol |
| DNSSEC | **No** | The exit resolves, it does not validate |

### Critical limitation: no DNSSEC

Tor does not support end-to-end DNSSEC. This means:
- The exit node could manipulate DNS responses (DNS spoofing)
- There is no way to verify the authenticity of the response
- HTTPS (TLS certificates) is the only protection against malicious exits

### Performance

DNS queries via Tor have significantly higher latency:

```
Direct DNS (ISP Comeser, Parma):       ~15ms
DNS via Tor (DNSPort):                 ~200-800ms
DNS via SOCKS5 remote:                 ~150-600ms
```

The difference is due to the 3 circuit hops + exit resolution time.

---

## AutomapHostsOnResolve - the mapping mechanism

### How it works

When `AutomapHostsOnResolve 1`, Tor maintains an internal table that maps
hostnames to dummy IPs from the `VirtualAddrNetworkIPv4` range:

```
AutomapHosts table (in memory):
  example.com      → 10.192.0.1
  github.com       → 10.192.0.2
  api.ipify.org    → 10.192.0.3
  duckduckgo.com   → 10.192.0.4
  abcxyz.onion     → 10.192.0.5
```

This table exists only in memory and is cleared on Tor restart.

### The VirtualAddrNetwork range

```ini
VirtualAddrNetworkIPv4 10.192.0.0/10
```

This defines 4,194,304 dummy IP addresses (from 10.192.0.0 to 10.255.255.255).
Each resolvable hostname gets an IP from this range.

**Warning**: the range must not overlap with real networks on your LAN. The default
`10.192.0.0/10` is safe for most configurations, but if your
network uses `10.0.0.0/8` you might have conflicts.

### Mapped suffixes

```ini
AutomapHostsSuffixes .onion,.exit
```

By default maps `.onion` and `.exit`. With `AutomapHostsOnResolve 1` it maps all
hostnames, which is necessary for transparent proxy.

### Lifecycle of a mapping

```
1. App: getaddrinfo("example.com") → query to DNSPort
2. Tor: hostname not in cache → assigns 10.192.0.42
3. Tor: responds with DNS A record: 10.192.0.42
4. App: connect(10.192.0.42:443)
5. Tor (TransPort): intercepts, looks up 10.192.0.42 in the table
6. Tor: finds "example.com", creates RELAY_BEGIN "example.com:443"
7. Circuit: exit actually resolves example.com and connects

If the app queries again:
8. App: getaddrinfo("example.com") → query to DNSPort
9. Tor: hostname in cache → returns 10.192.0.42 (same IP)
```

### TTL and cache

Tor manages the TTL of cached DNS responses:
- **Minimum TTL**: 60 seconds (hard-coded)
- **Maximum TTL**: 30 minutes for the internal cache
- **NEWNYM**: clears the DNS cache (important for identity changes)

---

## SOCKS5 remote DNS resolution

### The safest method

When an application correctly uses SOCKS5 with hostname:

```
curl --socks5-hostname 127.0.0.1:9050 https://example.com
                ↑
                "--socks5-hostname" is the key:
                sends the hostname to the proxy, does NOT resolve locally
```

Comparison:
```bash
# SAFE: hostname sent to Tor, remote DNS
curl --socks5-hostname 127.0.0.1:9050 https://example.com

# UNSAFE: local DNS, then IP sent to Tor
curl --socks5 127.0.0.1:9050 https://example.com
#     ↑ without "-hostname" → resolves locally first!
```

The difference is a single flag, but the privacy consequence is total.

### How applications send hostnames via SOCKS5

Not all applications support SOCKS5 with hostname. The behavior depends
on how the application handles the proxy:

| Application | Method | Remote DNS? |
|------------|--------|-------------|
| curl (`--socks5-hostname`) | ATYP=0x03 | Yes |
| curl (`--socks5`) | Resolves, ATYP=0x01 | **No** |
| Firefox (SOCKS5 proxy + remote DNS) | ATYP=0x03 | Yes |
| proxychains (`proxy_dns`) | DNS thread → SOCKS5 | Yes (with hack) |
| torsocks | Intercepts getaddrinfo | Yes |
| Python requests + PySocks | Depends on config | Depends |
| git (`socks5h://`) | ATYP=0x03 | Yes |
| ssh (`ProxyCommand nc -X 5`) | ATYP=0x03 | Yes |

---

## Interaction with systemd-resolved

Kali Linux (and many recent Debian-based distributions) use `systemd-resolved`
as the system DNS resolver.

### The problem

```
systemd-resolved listens on 127.0.0.53:53
/etc/resolv.conf → "nameserver 127.0.0.53"

When an app does DNS without going through Tor:
  App → getaddrinfo() → glibc → 127.0.0.53 → systemd-resolved
  systemd-resolved → upstream DNS (ISP) → LEAK!
```

### Status check

```bash
# Check if systemd-resolved is active
systemctl status systemd-resolved

# See current DNS configuration
resolvectl status

# Typical output on Kali:
# Link 2 (eth0):
#   Current Scopes: DNS
#   DefaultRoute setting: yes
#   LLMNR setting: yes        ← potential leak!
#   MulticastDNS setting: no
#   DNSOverTLS setting: no
#   DNSSEC setting: no
#   Current DNS Server: 192.168.1.1
```

### Mitigation

To prevent DNS leaks via systemd-resolved when using Tor:

```bash
# Option 1: Disable systemd-resolved (drastic)
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
# Create manual /etc/resolv.conf:
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

# Option 2: Configure resolved to use Tor's DNSPort
sudo mkdir -p /etc/systemd/resolved.conf.d/
cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/tor.conf
[Resolve]
DNS=127.0.0.1#5353
LLMNR=no
MulticastDNS=no
EOF
sudo systemctl restart systemd-resolved
```

### LLMNR and mDNS - silent leaks

`systemd-resolved` enables by default:
- **LLMNR** (Link-Local Multicast Name Resolution): resolves names on the LAN via multicast
- **mDNS** (Multicast DNS): service discovery on the local network

Both send multicast packets on the local network, revealing which hostnames
you are trying to resolve. Even with Tor active, an LLMNR query for a hostname
not in DNS can leak on the LAN.

---

---

> **Continues in**: [Advanced DNS and Hardening](dns-avanzato-e-hardening.md) for resolv.conf,
> proxy_dns internals, .onion resolution, DNS leak scenarios, and complete hardening.

---

## See also

- [Advanced DNS and Hardening](dns-avanzato-e-hardening.md) - resolv.conf, detailed leaks, hardening
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Leak scenarios and prevention
- [ProxyChains - Complete Guide](proxychains-guida-completa.md) - proxy_dns and DNS interception
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - DNSPort with TransPort
- [Real-World Scenarios](scenari-reali.md) - Operational pentester cases
