> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/dns-avanzato-e-hardening.md) | English

# Advanced DNS - resolv.conf, Detailed Leaks and Hardening

Interaction with /etc/resolv.conf, DNS internals of proxychains and torsocks,
resolution via ControlPort, .onion, DNS leak scenarios, and complete hardening.

Extracted from [Tor and DNS - Resolution](tor-e-dns-risoluzione.md).

---

## Table of Contents

- [Interaction with /etc/resolv.conf](#interaction-with-etcresolvconf)
- [DNS and proxychains - proxy_dns internals](#dns-and-proxychains---proxy_dns-internals)
- [DNS and torsocks](#dns-and-torsocks)
- [DNS via ControlPort - manual resolution](#dns-via-controlport---manual-resolution)
- [.onion resolution](#onion-resolution)
- [DNS leak - detailed scenarios](#dns-leak---detailed-scenarios)
- [Complete DNS hardening](#complete-dns-hardening)

---

## Interaction with /etc/resolv.conf

### Anatomy of the file

```bash
cat /etc/resolv.conf
# On my Kali (Parma, Comeser ISP):
# nameserver 192.168.1.1     ← local router
# nameserver 127.0.0.53      ← systemd-resolved (if active)
```

### The problem with NetworkManager

NetworkManager rewrites `/etc/resolv.conf` on every network connection:

```
WiFi connection → DHCP → obtain ISP DNS → NetworkManager updates resolv.conf
```

Any manual configuration (e.g. pointing to 127.0.0.1 for Tor) gets
overwritten. Solutions:

```bash
# Option 1: Make resolv.conf immutable
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
sudo chattr +i /etc/resolv.conf

# Option 2: Configure NetworkManager to not touch DNS
# /etc/NetworkManager/conf.d/dns.conf
[main]
dns=none

# Option 3: Use /etc/NetworkManager/dispatcher.d/ for post-connection override
```

---

## DNS and proxychains - proxy_dns internals

### How proxy_dns works

When `proxy_dns` is enabled in `/etc/proxychains4.conf`:

```
proxychains curl https://example.com

1. curl calls getaddrinfo("example.com")
2. proxychains intercepts getaddrinfo() via LD_PRELOAD
3. Instead of resolving locally, proxychains:
   a. Generates a dummy IP from the remote_dns_subnet range (224.x.x.x)
   b. Stores: 224.0.0.1 → "example.com"
   c. Returns 224.0.0.1 to curl
4. curl calls connect(224.0.0.1:443)
5. proxychains intercepts connect()
6. Recognizes 224.0.0.1 → looks up in the table → finds "example.com"
7. Sends to Tor via SOCKS5: CONNECT "example.com:443" (ATYP=0x03)
8. Tor resolves "example.com" via exit node
```

### The remote_dns_subnet range

```ini
# /etc/proxychains4.conf
remote_dns_subnet 224
```

The value `224` means dummy IPs are in the `224.0.0.0/8` range
(which is normally multicast, so it does not conflict with real IPs).

### Limitation: DNS race condition

If an application performs DNS in a separate thread before the connect(), proxychains
might not intercept the query. This is a rare edge case but possible
with complex multi-threaded applications.

---

## DNS and torsocks

### Mechanism

torsocks intercepts DNS calls at a lower level than proxychains:

```
torsocks curl https://example.com

1. curl calls getaddrinfo("example.com")
2. libtorsocks.so intercepts getaddrinfo()
3. torsocks does NOT resolve locally
4. torsocks sends directly to Tor via SOCKS5 with hostname
5. No dummy mapping needed: the hostname goes directly into the circuit
```

Key difference: torsocks does not use dummy IPs. It sends the hostname directly
to the SOCKS5 proxy, which is the cleanest and safest method.

### UDP DNS blocking

torsocks actively blocks direct UDP DNS queries:

```
[warn] torsocks[12345]: sendto: Connection to a DNS server (8.8.8.8:53)
  is not allowed. UDP is not supported by Tor, dropping connection
```

---

## DNS via ControlPort - manual resolution

### RESOLVE command

The ControlPort supports manual DNS resolution:

```
$ echo -e "AUTHENTICATE\r\nRESOLVE example.com\r\nQUIT\r\n" | nc 127.0.0.1 9051
250 OK
250 CNAME=example.com
250-address=93.184.216.34
250 OK
```

### Python with Stem

```python
from stem.control import Controller

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    
    # DNS resolution via Tor
    result = ctrl.resolve("example.com")
    print(f"example.com → {result}")
    
    # Reverse resolution
    result = ctrl.resolve("93.184.216.34", reverse=True)
    print(f"93.184.216.34 → {result}")
```

Useful for scripts that need to resolve hostnames via Tor without using
proxychains or torsocks.

---

## .onion resolution

`.onion` addresses do not exist in the public DNS. Resolution works
differently:

```
1. App requests: "abcdef...xyz.onion"
2. Tor recognizes the .onion suffix
3. Does NOT perform a DNS query
4. Extracts the public key from the address (Ed25519 for v3)
5. Computes the hash to find the HSDirs (responsible HSDirs)
6. Downloads the service descriptor from the HSDirs
7. Decrypts the descriptor with the public key
8. Obtains the introduction points
9. Builds a rendezvous circuit
```

### .onion resolution with AutomapHosts

When `AutomapHostsOnResolve 1`:

```
getaddrinfo("abcdef...xyz.onion")
  → Tor responds: 10.192.0.42 (dummy IP)
  → App connects to 10.192.0.42
  → Tor recognizes the mapping → initiates rendezvous protocol
```

This allows applications that do not natively support `.onion` to
access hidden services via the transparent proxy or DNSPort.

---

## DNS leak - detailed scenarios

### Scenario 1: Application that ignores the proxy

```
Firefox with SOCKS5 proxy configured BUT "DNS over SOCKS" disabled:
  Firefox → getaddrinfo("target.com") → ISP DNS (LEAK!)
  Firefox → connect(IP) → SOCKS5 → Tor → exit → target
  
  Fix: network.proxy.socks_remote_dns = true in about:config
```

### Scenario 2: Dual-stack IPv6

```
System with IPv6 enabled:
  App → DNS AAAA query "target.com" → IPv6 DNS (not intercepted by Tor!)
  
  Fix: disable IPv6 or filter with ip6tables
```

### Scenario 3: Browser DNS prefetch

```
Browser with prefetch enabled:
  Page contains link to "other-site.com"
  Browser performs DNS prefetch → direct DNS query (LEAK!)
  
  Fix: network.dns.disablePrefetch = true
```

### Scenario 4: WebRTC

```
Browser with WebRTC:
  STUN request → reveals local and public IP → LEAK
  
  Fix: media.peerconnection.enabled = false
```

### Scenario 5: Captive portal detection

```
NetworkManager/systemd-networkd:
  Checks connectivity → DNS + HTTP in the clear → LEAK
  
  Fix: disable connectivity check
```

---

## Complete DNS hardening

### Level 1: torrc

```ini
DNSPort 5353
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
ClientUseIPv6 0
```

### Level 2: System

```bash
# Block direct DNS with iptables
# Allow only DNS to 127.0.0.1:5353 (Tor DNSPort)
iptables -A OUTPUT -p udp --dport 53 -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j DROP
iptables -A OUTPUT -p tcp --dport 53 -j DROP
```

### Level 3: Application

```
Firefox about:config:
  network.proxy.socks_remote_dns = true
  network.dns.disablePrefetch = true
  network.dns.disableIPv6 = true
  
proxychains4.conf:
  proxy_dns
  remote_dns_subnet 224
```

### Level 4: Monitoring

```bash
# Monitor outgoing DNS queries (should be zero if everything is configured)
sudo tcpdump -i eth0 port 53 -n

# If you see packets → there is a leak to investigate
```

---

## In my experience

DNS configuration was the trickiest part of my Tor setup on Kali.
The problems I encountered:

1. **systemd-resolved overwriting everything**: after every WiFi reconnection,
   `/etc/resolv.conf` reverted to the router's DNS. I resolved it with `chattr +i`
   after manually configuring the file.

2. **Firefox with DNS leak despite SOCKS5 proxy**: I had configured the proxy
   manually in Firefox but had not enabled `network.proxy.socks_remote_dns`.
   Result: HTTP traffic passed through Tor, but DNS went directly to my ISP
   (Comeser, Parma). I discovered it with `tcpdump -i eth0 port 53` - I could see
   cleartext DNS queries for every site I visited.

3. **proxychains and proxy_dns**: in the initial configuration I had commented out
   `proxy_dns` in `proxychains4.conf`. Everything appeared to work, but every
   hostname was being resolved locally before being passed to Tor. I verified with
   `PROXYCHAINS_DEBUG=1 proxychains curl https://check.torproject.org` - the debug
   output showed local resolution.

4. **DNSPort 5353 vs 53**: I chose 5353 to avoid running Tor as root
   (ports below 1024 require privileges). It works perfectly with the
   iptables redirect rule, but applications that hardcode DNS on port 53
   must be intercepted with iptables REDIRECT.

The golden rule: **never trust that DNS goes through Tor - always verify with
tcpdump**. A single DNS leak nullifies the entire protection of the Tor circuit.

---

## See also

- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Leak scenarios and multi-level prevention
- [ProxyChains - Complete Guide](proxychains-guida-completa.md) - proxy_dns and DNS interception
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - DNSPort with TransPort
- [IP, DNS and Leak Verification](verifica-ip-dns-e-leak.md) - DNS leak testing with tcpdump
- [System Hardening](../05-sicurezza-operativa/hardening-sistema.md) - systemd-resolved and iptables DNS
