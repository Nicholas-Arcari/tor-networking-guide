> **Lingua / Language**: [Italiano](../../09-scenari-operativi/ricognizione-anonima.md) | English

# Anonymous Reconnaissance - OSINT via Tor

This document analyzes how to use Tor for anonymous reconnaissance and
OSINT (Open Source Intelligence) activities: gathering information from
public sources without revealing your identity or interest.

> **See also**: [ProxyChains](../04-strumenti-operativi/proxychains-guida-completa.md),
> [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md),
> [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md).

---

## Table of Contents

- [OSINT and anonymity - why it matters](#osint-and-anonymity--why-it-matters)
- [Setup for anonymous reconnaissance](#setup-for-anonymous-reconnaissance)
- [OSINT tools via Tor](#osint-tools-via-tor)
- [Web reconnaissance](#web-reconnaissance)
- [DNS and domain reconnaissance](#dns-and-domain-reconnaissance)
- [Social media reconnaissance](#social-media-reconnaissance)
- [Gathering information on targets](#gathering-information-on-targets)
- [Anti-detection and rate limiting](#anti-detection-and-rate-limiting)
- [Identity management](#identity-management)
- [OPSEC for OSINT](#opsec-for-osint)
- [In my experience](#in-my-experience)

---

## OSINT and anonymity - why it matters

### The problem: tipping off

When you perform reconnaissance on a target, your queries leave traces:

```
Without Tor:
  You (IP: 93.x.x.x, Comeser ISP, Parma) → DNS query "target.com"
  You → HTTP request to target.com → the server logs your IP
  You → Google search "target.com vulnerabilities" → Google logs the query
  You → Shodan query for target IP → Shodan logs your IP

If the target monitors their logs:
  "Someone from IP 93.x.x.x is performing reconnaissance on us"
  → They can trace back to you (ISP → logs → identity)
```

With Tor, each query arrives from a different exit node:
- The target sees no coherent pattern
- They cannot trace back to your identity
- They cannot determine that the queries originate from the same person

### Legitimate scenarios

| Scenario | Why anonymity is needed |
|----------|----------------------|
| Pentest (reconnaissance phase) | Avoid alerting the target before the test |
| Bug bounty | Preliminary reconnaissance without tipping off |
| Threat intelligence | Monitor threat actors without being noticed |
| Corporate investigation | Verify vendors/partners without revealing interest |
| Academic research | Study infrastructures without bias |
| Investigative journalism | Protect sources and ongoing investigations |

---

## Setup for anonymous reconnaissance

### Basic configuration

```bash
# 1. Tor active with full bootstrap
sudo systemctl start tor@default.service
sudo journalctl -u tor@default.service | grep "Bootstrapped 100%"

# 2. Verify connection
proxychains curl -s https://api.ipify.org
# → Tor exit IP (not yours)

# 3. Verify that the IP is recognized as Tor
proxychains curl -s https://check.torproject.org/api/ip | grep IsTor
# → "IsTor":true
```

### Restrictive firewall (recommended for OSINT)

```bash
# Block all direct traffic - only Tor can reach the outside
TOR_UID=$(id -u debian-tor)
iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -j DROP
```

### Stream isolation for OSINT

To prevent correlation between different reconnaissance phases:

```bash
# DNS queries: one session
curl --socks5-hostname 127.0.0.1:9050 --proxy-user "dns-recon:1" https://...

# Web scraping: different session
curl --socks5-hostname 127.0.0.1:9050 --proxy-user "web-recon:2" https://...

# Social media: yet another session
curl --socks5-hostname 127.0.0.1:9050 --proxy-user "social-recon:3" https://...
```

---

## OSINT tools via Tor

### Tools compatible with Tor

| Tool | Via proxychains | Via torsocks | Natively | Notes |
|------|:---:|:---:|:---:|------|
| curl | ✓ | ✓ | ✓ (--socks5-hostname) | Most reliable method |
| wget | ✓ | ✓ | ✗ | Beware of DNS leak |
| theHarvester | ✓ | ✓ | ✗ | Slow via Tor |
| Recon-ng | ✓ | ✗ | ✗ | Some modules do not work |
| Maltego | ✗ | ✗ | Limited | Java GUI, problematic |
| Shodan CLI | ✓ | ✓ | ✗ | API key required |
| Amass | Partial | Partial | ✗ | Go binary, direct DNS |
| whois | ✓ | ✓ | ✗ | TCP port 43 |
| nmap | ✓ | ✗ | ✓ (--proxy) | Only -sT (TCP connect) |
| dig | ✗ | ✗ | ✗ | UDP, does not work |
| nslookup | ✗ | ✗ | ✗ | UDP |

### DNS via Tor

Since `dig` and `nslookup` use UDP (not compatible with Tor):

```bash
# Alternative 1: tor-resolve (included with Tor)
tor-resolve example.com
# 93.184.216.34

# Alternative 2: curl with DNS-over-HTTPS
proxychains curl -s "https://dns.google/resolve?name=example.com&type=A" | python3 -m json.tool

# Alternative 3: Python with socket via torsocks
torsocks python3 -c "import socket; print(socket.getaddrinfo('example.com', 443))"
```

---

## Web reconnaissance

### Basic information gathering

```bash
# HTTP headers
proxychains curl -sI https://target.com | head -20

# TLS certificate
proxychains curl -sv https://target.com 2>&1 | grep -E "subject:|issuer:|expire"

# robots.txt
proxychains curl -s https://target.com/robots.txt

# sitemap.xml
proxychains curl -s https://target.com/sitemap.xml

# Security headers
proxychains curl -sI https://target.com | grep -iE "x-frame|x-content|strict-transport|content-security"
```

### Technologies and frameworks

```bash
# Wappalyzer-style detection via headers
proxychains curl -sI https://target.com | grep -iE "^(server|x-powered-by|x-aspnet|x-generator):"

# CMS check
proxychains curl -s https://target.com/wp-login.php > /dev/null && echo "WordPress"
proxychains curl -s https://target.com/administrator/ > /dev/null && echo "Joomla"
```

### Wayback Machine

```bash
# Archived pages (Tor not required for Wayback, but used to avoid revealing interest)
proxychains curl -s "https://web.archive.org/web/timemap/json?url=target.com&limit=10" | python3 -m json.tool
```

---

## DNS and domain reconnaissance

### Subdomain enumeration

```bash
# Via crt.sh (Certificate Transparency logs)
proxychains curl -s "https://crt.sh/?q=%.target.com&output=json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
domains = set(entry['name_value'] for entry in data)
for d in sorted(domains):
    print(d)
"

# Via VirusTotal API (requires API key)
proxychains curl -s "https://www.virustotal.com/api/v3/domains/target.com/subdomains" \
  -H "x-apikey: YOUR_KEY"
```

### WHOIS via Tor

```bash
# Direct WHOIS (TCP port 43, works via proxychains)
proxychains whois target.com

# Or via web API
proxychains curl -s "https://www.whoisxmlapi.com/whoisserver/WhoisService?domainName=target.com&outputFormat=JSON"
```

### Reverse DNS

```bash
# Reverse lookup via DoH
proxychains curl -s "https://dns.google/resolve?name=34.216.184.93.in-addr.arpa&type=PTR"
```

---

## Social media reconnaissance

### OSINT on public profiles

```bash
# GitHub
proxychains curl -s "https://api.github.com/users/targetuser" | python3 -m json.tool

# LinkedIn (via public search)
proxychains curl -s "https://www.google.com/search?q=site:linkedin.com+%22targetname%22"

# Twitter/X (via public profile)
# Social media platforms often block Tor → use APIs when possible
```

### Issues with social media and Tor

| Platform | Tor blocked? | Workaround |
|----------|:---:|------------|
| Google | Frequent captcha | Use APIs, DuckDuckGo |
| LinkedIn | Often blocked | Limited public API |
| Twitter/X | Partially | API with token |
| Facebook | Blocked | .onion: facebookwkhpilnemxj7asaniu7vnjjbiltxjqhye3mhbshg7kx5tfyd.onion |
| GitHub | Works | Public API |
| Reddit | Works | API with rate limiting |
| Instagram | Blocked | Limited |

### DuckDuckGo as a Google alternative

```bash
# DuckDuckGo does not block Tor and does not track
proxychains curl -s "https://html.duckduckgo.com/html/?q=target+info" | grep -oP 'href="[^"]*"'

# DuckDuckGo also has an onion service
# https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/
```

---

## Gathering information on targets

### Infrastructure

```bash
# IP and hosting
proxychains curl -s "https://ipinfo.io/$(tor-resolve target.com)" | python3 -m json.tool

# ASN lookup
proxychains curl -s "https://api.bgpview.io/ip/$(tor-resolve target.com)"

# Open ports (SLOW via Tor, TCP only)
proxychains nmap -sT -Pn --top-ports 100 target.com
# WARNING: nmap via Tor is very slow and may timeout
```

### Email and contacts

```bash
# theHarvester via Tor
proxychains theHarvester -d target.com -b google,bing,duckduckgo

# hunter.io (requires API key)
proxychains curl -s "https://api.hunter.io/v2/domain-search?domain=target.com&api_key=KEY"
```

---

## Anti-detection and rate limiting

### The problem: Tor exit = shared IP

Tor exit nodes are used by thousands of people. Many sites:
- Rate-limit Tor IPs
- Show captchas
- Block them entirely

### Strategies

```bash
# Rotate IP between queries (NEWNYM)
for url in "${URLS[@]}"; do
    # Change IP
    echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051
    sleep 10  # wait for NEWNYM cooldown
    
    # Query with new IP
    proxychains curl -s "$url" >> results.txt
    
    # Delay between queries (avoid rate limiting)
    sleep $((RANDOM % 10 + 5))
done

# Randomize User-Agent
UA_LIST=(
    "Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0"
    "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15"
)
UA="${UA_LIST[$RANDOM % ${#UA_LIST[@]}]}"
proxychains curl -s -H "User-Agent: $UA" https://target.com
```

### Timing and patterns

```
WRONG: query every 1 second exactly → detectable pattern
RIGHT: random delay 3-15 seconds → human-like pattern
```

---

## Identity management

### Identity separation

For professional OSINT, each "operational identity" should have:

| Aspect | Identity A (research) | Identity B (social) |
|--------|---------------------|---------------------|
| SocksPort | 9050 | 9060 |
| Browser | Firefox profile tor-a | Firefox profile tor-b |
| Exit node | Separate (isolation) | Separate |
| Account | None | Dedicated account |
| Email | None | ProtonMail via Tor |

### Fatal separation mistakes

- Logging into a personal account from the same Tor instance used for OSINT
- Using the same browser/profile for different identities
- Logging into identifiable services during the OSINT session
- Not changing IP (NEWNYM) between activities of different identities

---

## OPSEC for OSINT

### Pre-session checklist

- [ ] Restrictive firewall active (Tor only)
- [ ] Verified Tor IP (`proxychains curl https://api.ipify.org`)
- [ ] Shell history disabled (`unset HISTFILE`)
- [ ] Clean browser (no cookies, no cache, no logins)
- [ ] Stream isolation configured
- [ ] No personal accounts open in the browser
- [ ] NTP/DNS not leaking

### Post-session checklist

- [ ] Clear browser cache
- [ ] Delete temporary downloads
- [ ] Verify that no downloaded file contains metadata with your IP
- [ ] Final NEWNYM to dissociate the session
- [ ] Disable restrictive firewall (if temporary)

---

## In my experience

I use Tor for anonymous reconnaissance when studying infrastructures and
technologies. My typical workflow:

1. **Preparation**: start Tor, verify bootstrap, verify IP
2. **Research**: use `proxychains curl` for HTTP queries, `tor-resolve` for DNS
3. **Archival**: save results locally, never to the cloud during the session
4. **Cleanup**: delete cache, history, temporary files

The main issues I have encountered:
- **Google captcha**: nearly unusable via Tor. I switched to DuckDuckGo
  for OSINT searches, which works perfectly via Tor (and has a .onion)
- **Rate limiting**: some services (crt.sh, Shodan) rate-limit Tor IPs.
  Rotation with NEWNYM helps, but the 10-second cooldown slows things down
- **nmap via Tor**: extremely slow. For port scanning, I prefer to run it from
  an anonymous VPS rather than via Tor. Tor is great for web recon, less so for
  network scanning
- **Go tools (amass, etc.)**: static binaries that bypass proxychains/torsocks.
  For these tools, transparent proxy (iptables) is the only reliable solution

---

## See also

- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Avoiding deanonymization during OSINT
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) - Fingerprint risks during reconnaissance
- [ProxyChains - Complete Guide](../04-strumenti-operativi/proxychains-guida-completa.md) - Proxying OSINT tools
- [Application Limitations](../07-limitazioni-e-attacchi/limitazioni-applicazioni.md) - Tool compatibility with Tor
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - Forcing Go/static tools through Tor
