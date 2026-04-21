> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/dns-leak-prevenzione-e-hardening.md) | English

# DNS Leak - Prevention and Hardening

Multi-layer mitigations for DNS leaks: Tor configuration, proxychains, application-level,
operating system, iptables/nftables firewall, systemd-resolved, DoH/DoT, and forensic verification.

> **Extracted from**: [DNS Leak - How They Happen and How to Prevent Them](dns-leak.md)
> for leak scenarios and practical verification.

---

### Level 1: Tor Configuration (torrc)

```ini
# Tor as a local DNS resolver
DNSPort 5353                    # Tor responds to DNS queries on port 5353/UDP
AutomapHostsOnResolve 1         # Automatic hostname-to-fake-IP mapping
VirtualAddrNetworkIPv4 10.192.0.0/10  # Range for mapped fake IPs
```

How it works:
```
1. An application requests to resolve "example.com"
2. The query reaches 127.0.0.1:5353 (Tor DNSPort)
3. Tor creates a circuit and resolves the DNS on the exit node
4. With AutomapHosts: Tor maps "example.com" → 10.192.x.x
5. The application connects to 10.192.x.x
6. Tor intercepts the connection (TransPort) and sends it to the real IP
```

### Level 2: ProxyChains Configuration

```ini
# /etc/proxychains4.conf
proxy_dns                       # Intercepts DNS calls via LD_PRELOAD
remote_dns_subnet 224           # Subnet for DNS mapping fake IPs

# How proxy_dns works:
# 1. proxychains intercepts getaddrinfo() via LD_PRELOAD
# 2. Instead of resolving, assigns an IP in the 224.x.x.x range
# 3. When the app connects to 224.x.x.x:
#    proxychains sends the original hostname to the SOCKS5 proxy
# 4. Tor resolves the DNS on the exit node
```

### Level 3: Application-level Configuration

```bash
# curl: ALWAYS --socks5-hostname, NEVER --socks5
curl --socks5-hostname 127.0.0.1:9050 https://example.com
# Alternative:
curl -x socks5h://127.0.0.1:9050 https://example.com

# wget: via proxychains (wget does not natively support SOCKS)
proxychains wget https://example.com

# Firefox: "Proxy DNS when using SOCKS v5" enabled in proxy settings
# about:config → network.proxy.socks_remote_dns = true

# git: use socks5h (h = hostname resolution via proxy)
git config --global http.proxy socks5h://127.0.0.1:9050
git config --global https.proxy socks5h://127.0.0.1:9050

# pip: via proxychains
proxychains pip install package_name

# SSH: configure in ~/.ssh/config
# Host *.onion
#     ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

### Level 4: System-level Configuration

```bash
# 1. Disable IPv6 (prevents AAAA leaks)
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
# Make persistent:
echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee -a /etc/sysctl.d/99-tor-hardening.conf
echo "net.ipv6.conf.default.disable_ipv6=1" | sudo tee -a /etc/sysctl.d/99-tor-hardening.conf

# 2. Configure /etc/resolv.conf to use only Tor DNS
# WARNING: if Tor is not running, DNS will not work!
# Useful only for system-wide setups
sudo bash -c 'echo "nameserver 127.0.0.1" > /etc/resolv.conf'
# And protect the file from being overwritten:
sudo chattr +i /etc/resolv.conf

# 3. Disable systemd-resolved if not needed
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

### Level 5: Firewall (maximum protection)

To physically prevent DNS queries from going out without passing through Tor:

```bash
# Block all outgoing DNS except Tor's
sudo iptables -A OUTPUT -p udp --dport 53 -m owner --uid-owner debian-tor -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -m owner --uid-owner debian-tor -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 53 -j DROP
sudo iptables -A OUTPUT -p tcp --dport 53 -j DROP

# Also allow DNS to the local DNSPort
sudo iptables -A OUTPUT -p udp -d 127.0.0.1 --dport 5353 -j ACCEPT
```

This blocks all DNS queries (port 53) that do not originate from the Tor process
(user `debian-tor`). Any application that attempts direct DNS is
silently blocked.

---

## Advanced hardening with iptables/nftables

### Complete anti-DNS-leak iptables rules

```bash
#!/bin/bash
# dns-leak-firewall.sh - Complete anti-DNS-leak rules

# Variables
TOR_USER="debian-tor"
DNS_PORT=5353
TRANS_PORT=9040

# Flush existing rules for the DNS chain
sudo iptables -D OUTPUT -p udp --dport 53 -j DNS_LEAK_PROTECT 2>/dev/null
sudo iptables -F DNS_LEAK_PROTECT 2>/dev/null
sudo iptables -X DNS_LEAK_PROTECT 2>/dev/null

# Create dedicated chain
sudo iptables -N DNS_LEAK_PROTECT

# Allow DNS from the Tor process
sudo iptables -A DNS_LEAK_PROTECT -m owner --uid-owner $TOR_USER -j ACCEPT

# Allow DNS to localhost (DNSPort)
sudo iptables -A DNS_LEAK_PROTECT -d 127.0.0.1 -j ACCEPT

# Log and block everything else
sudo iptables -A DNS_LEAK_PROTECT -j LOG --log-prefix "DNS_LEAK_BLOCKED: " --log-level warning
sudo iptables -A DNS_LEAK_PROTECT -j DROP

# Apply the chain
sudo iptables -A OUTPUT -p udp --dport 53 -j DNS_LEAK_PROTECT
sudo iptables -A OUTPUT -p tcp --dport 53 -j DNS_LEAK_PROTECT

# Also block DoH (DNS-over-HTTPS) to known resolvers
# This prevents Chrome/apps from using DoH to bypass
for doh_ip in 8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 9.9.9.9; do
    sudo iptables -A OUTPUT -d "$doh_ip" -p tcp --dport 443 \
        -m owner ! --uid-owner $TOR_USER -j DROP
done

echo "Anti-DNS-leak rules activated"
echo "Verify with: sudo iptables -L DNS_LEAK_PROTECT -v -n"
```

### nftables equivalent

```
table inet dns_leak_protect {
    chain output {
        type filter hook output priority 0; policy accept;
        
        # Allow DNS from the Tor process
        meta skuid debian-tor udp dport 53 accept
        meta skuid debian-tor tcp dport 53 accept
        
        # Allow DNS to localhost
        ip daddr 127.0.0.1 udp dport 5353 accept
        
        # Log and block direct DNS
        udp dport 53 log prefix "DNS_LEAK: " drop
        tcp dport 53 log prefix "DNS_LEAK: " drop
        
        # Block DoH to known resolvers
        ip daddr { 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1 } tcp dport 443 \
            meta skuid != debian-tor drop
    }
}
```

### Rule verification

```bash
# Verify that rules are active
sudo iptables -L DNS_LEAK_PROTECT -v -n

# Check block logs
sudo journalctl -k | grep DNS_LEAK_BLOCKED

# Test: try direct DNS (should be blocked)
dig example.com @8.8.8.8
# → timeout (blocked by firewall)

# Test: try via Tor (should work)
proxychains curl -s https://check.torproject.org/api/ip
# → {"IsTor":true,...} (DNS resolved via Tor)
```

---

## systemd-resolved and interaction with Tor

### The problem

`systemd-resolved` is the default DNS resolver on many Linux distributions.
It creates complications with Tor:

```bash
# systemd-resolved listens on 127.0.0.53:53
# /etc/resolv.conf points to 127.0.0.53
# Applications resolve DNS through systemd-resolved
# systemd-resolved forwards queries to upstream resolvers (ISP)

# Even with proxychains, there are cases where systemd-resolved
# resolves BEFORE proxychains intercepts:
# - NSS (Name Service Switch) can use systemd-resolved directly
# - Some libraries do not use the standard getaddrinfo()
```

### Solution 1: Disable systemd-resolved

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm /etc/resolv.conf  # Remove the symlink
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
# Now DNS uses only the local resolver (Tor DNSPort if configured)
```

### Solution 2: Configure systemd-resolved to use Tor

```ini
# /etc/systemd/resolved.conf
[Resolve]
DNS=127.0.0.1#5353     # Use Tor's DNSPort
FallbackDNS=            # NO fallback (if Tor is down, DNS does not work)
DNSOverTLS=no           # Do not use DoT (Tor handles encryption)
DNSSEC=no               # Tor does not support end-to-end DNSSEC
Cache=no                # Do not cache (responses change with exit nodes)
```

```bash
sudo systemctl restart systemd-resolved
# Verify:
resolvectl status
# Should show: DNS Servers: 127.0.0.1#5353
```

### Solution 3: Hybrid configuration (my approach)

```bash
# On Kali Linux, systemd-resolved is not active by default
# Verify:
systemctl is-active systemd-resolved
# inactive → no problem

# My /etc/resolv.conf uses the ISP router DNS:
cat /etc/resolv.conf
# nameserver 192.168.1.1

# This means:
# - Without proxychains: DNS resolved by ISP router (normal)
# - With proxychains + proxy_dns: DNS resolved via Tor (protected)
# - The leak occurs ONLY if I forget proxychains or use --socks5 without -hostname
```

---

## DNS over HTTPS/TLS and implications for Tor

### DoH (DNS-over-HTTPS)

DoH encrypts DNS queries inside HTTPS (port 443). It sounds good for privacy,
but creates problems with Tor:

```
Problem 1: DoH bypasses proxychains
  Firefox with DoH enabled → DNS HTTPS query to Cloudflare (1.1.1.1:443)
  proxychains does not intercept this HTTPS connection
  → DNS queries go out in cleartext (encrypted with TLS, but not via Tor)
  → The DoH provider (Cloudflare/Google) sees all your domains

Problem 2: DoH does not go through Tor
  The DoH connection is a separate HTTPS connection
  If it is not proxied, it goes out directly
  Even if proxied, it adds latency (DoH + Tor = double overhead)

Solution: disable DoH when using Tor
  Firefox: about:config → network.trr.mode = 5 (disabled)
  Chrome: chrome://settings → Security → "Use secure DNS" → OFF
```

### DoT (DNS-over-TLS)

DoT encrypts DNS queries with TLS on port 853. Same problem:

```
# If systemd-resolved uses DoT:
[Resolve]
DNSOverTLS=yes
DNS=1.1.1.1#cloudflare-dns.com

# Queries go to Cloudflare via TLS on port 853
# → They do not go through Tor
# → Cloudflare sees all your domains (even if encrypted in transit)
```

### Recommendation

When using Tor, disable DoH and DoT. DNS must go through Tor,
which handles its own encryption. Adding DoH/DoT on top of Tor
does not add security and can cause leaks.

---

## Forensic detection of DNS leaks

### How a forensic analyst detects DNS leaks

An investigator with access to ISP logs or a network capture
can identify DNS leaks:

```
Evidence 1: Cleartext DNS queries
  - pcap with DNS UDP:53 queries to the ISP resolver
  - Contains visited domains, with timestamps

Evidence 2: Temporal correlation
  - t=0.00: DNS query for "sensitive-site.com" (in cleartext)
  - t=0.05: TLS connection to Tor Guard
  - Correlation: the user visited sensitive-site.com via Tor

Evidence 3: Leak patterns
  - The first queries of a session are often in cleartext
    (before proxychains initializes)
  - Queries for internal domains (.local, .internal) often leak
  - Browsers prefetch DNS before the user clicks
```

### Self-audit for DNS leaks

```bash
#!/bin/bash
# audit-dns-leak.sh - Check if there have been DNS leaks
# Analyzes a pcap file captured during a Tor session

PCAP_FILE="${1:-/tmp/session-capture.pcap}"

echo "=== DNS Leak Audit ==="
echo "File: $PCAP_FILE"

# Count outgoing DNS queries (not from Tor)
TOTAL_DNS=$(tcpdump -r "$PCAP_FILE" -n 'udp port 53 and not src host 127.0.0.1' 2>/dev/null | wc -l)
echo "Outgoing DNS queries (non-localhost): $TOTAL_DNS"

# List requested domains
echo ""
echo "Domains requested in cleartext:"
tcpdump -r "$PCAP_FILE" -n 'udp port 53' 2>/dev/null | \
    grep -oP '(?<=A\? )[^ ]+' | sort -u

# Check for connections to known resolvers (DoH)
echo ""
echo "Connections to known DNS resolvers (possible DoH):"
for ip in 8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 9.9.9.9; do
    COUNT=$(tcpdump -r "$PCAP_FILE" -n "host $ip" 2>/dev/null | wc -l)
    [ "$COUNT" -gt 0 ] && echo "  $ip: $COUNT packets"
done
```

---

## In my experience

My configuration prevents DNS leaks at three levels:
1. **proxy_dns in proxychains** (intercepts DNS at the application level)
2. **DNSPort 5353 in the torrc** (Tor as local DNS resolver)
3. **IPv6 disabled** (prevents leaks via AAAA queries)

I have not implemented the iptables firewall because I use Tor only for specific
applications (not system-wide). But for a setup where I want maximum protection,
the firewall would be the next step.

The quick test I use regularly:
```bash
# Quick DNS leak test
sudo tcpdump -i eth0 port 53 -c 5 -n &
proxychains curl -s https://check.torproject.org/api/ip | grep IsTor
# If tcpdump captures nothing and IsTor is true → no leak
```

The most insidious leak I encountered: **Firefox with DNS prefetch enabled**.
Even with proxychains, Firefox was pre-resolving DNS for the links on the page.
The solution was `network.dns.disablePrefetch = true` in the tor-proxy profile.

---

## See also

- [Tor and DNS - Resolution](../04-strumenti-operativi/tor-e-dns-risoluzione.md) - DNSPort, AutomapHosts, complete DNS configuration
- [IP, DNS and Leak Verification](../04-strumenti-operativi/verifica-ip-dns-e-leak.md) - IP test, DNS leak, IPv6 leak, WebRTC leak
- [System Hardening](hardening-sistema.md) - sysctl, nftables, firewall rules
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - DNS leak as an OPSEC mistake
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - TransPort to force all traffic via Tor
- [ProxyChains - Complete Guide](../04-strumenti-operativi/proxychains-guida-completa.md) - proxy_dns and configuration
