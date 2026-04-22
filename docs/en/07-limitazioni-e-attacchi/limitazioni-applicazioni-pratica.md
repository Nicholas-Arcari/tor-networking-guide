> **Lingua / Language**: [Italiano](../../07-limitazioni-e-attacchi/limitazioni-applicazioni-pratica.md) | English

# Application Limitations - Tools, Cloud and Sessions via Tor

Security tools (nmap, nikto, sqlmap, Burp, Metasploit), development
tools (pip, npm, Docker), cloud services and APIs, session management
with variable IPs, and CAPTCHA strategies.

> **Extracted from** [Application Limitations](limitazioni-applicazioni.md) -
> which also covers why apps have problems with Tor, sites that block Tor,
> and desktop applications.

---

## Security tools via Tor

### nmap

```bash
# WORKS: TCP connect scan
proxychains nmap -sT -Pn target.com -p 80,443,8080
# -sT = TCP connect (uses normal sockets, SOCKS-compatible)
# -Pn = no ping (ICMP not supported)

# DOES NOT WORK: SYN scan (requires raw socket)
proxychains nmap -sS target.com  # FAILS

# DOES NOT WORK: UDP scan
proxychains nmap -sU target.com  # FAILS

# DOES NOT WORK: ping scan
proxychains nmap -sn target.com  # FAILS (ICMP)

# DOES NOT WORK: OS detection
proxychains nmap -O target.com   # FAILS (requires raw socket)
```

nmap limitations via Tor:
```
- Only -sT (TCP connect) works
- -Pn is mandatory (skip host discovery)
- Very slow (each port = separate SOCKS connection)
- Multi-port scans are extremely slow
- Many exits block non-standard ports → false negatives
- -sV (version detection) works but is very slow
- NSE scripts: some work, others don't (depends on whether they use raw sockets)
```

Typical performance:
```
Without Tor: 1000 ports in ~2 seconds
With Tor:    1000 ports in ~15-30 minutes
→ Factor ~500x slower

Recommendation: scan only known specific ports
proxychains nmap -sT -Pn -p 22,80,443,8080,8443 target.com
```

### nikto / dirb / gobuster

```bash
# Web enumeration via Tor - slow but functional
proxychains nikto -h https://target.com
proxychains dirb https://target.com /usr/share/dirb/wordlists/common.txt
proxychains gobuster dir -u https://target.com -w /usr/share/wordlists/common.txt

# Performance: ~10-50 requests/second (vs 500+ without Tor)
# For large wordlists: periodic NEWNYM to avoid overloading a single exit
```

### sqlmap

```bash
# Works via proxychains
proxychains sqlmap -u "https://target.com/page?id=1"

# Or using the built-in proxy (more efficient)
sqlmap -u "https://target.com/page?id=1" --proxy=socks5://127.0.0.1:9050

# With integrated tor-check:
sqlmap -u "https://target.com/page?id=1" --proxy=socks5://127.0.0.1:9050 \
    --check-tor --tor-type=SOCKS5
```

### Burp Suite

```
Configuration in Burp:
Settings → Network → Connections → SOCKS proxy
  Host: 127.0.0.1
  Port: 9050
  ☑ Use SOCKS proxy
  ☑ Do DNS lookups over SOCKS proxy

Considerations:
  - All Burp traffic passes through Tor
  - Intruder/Scanner are very slow via Tor
  - Target may block the exit IP during testing
  - NEWNYM between different phases of the test
```

### Metasploit

```bash
# Metasploit via proxychains
proxychains msfconsole

# Or configure the proxy in Metasploit
msf6> setg Proxies socks5:127.0.0.1:9050
msf6> setg ReverseAllowProxy true

# WARNING: many exploits/payloads require direct connections
# Reverse shell DOES NOT work via Tor (requires inbound connection)
# Bind shell: very slow and unreliable via Tor
# Web exploits (SQLi, etc.): work
```

---

## Development tools via Tor

### Package managers

```bash
# pip (Python)
proxychains pip install requests
# Works well, slow for large packages

# npm (Node.js)
proxychains npm install express
# Works, but npm is already slow → via Tor it's very slow

# gem (Ruby)
proxychains gem install rails
# Works

# cargo (Rust) - PROBLEMATIC
proxychains cargo build
# cargo is often statically compiled → LD_PRELOAD does not work
# Solution: environment variables
export HTTPS_PROXY=socks5h://127.0.0.1:9050
cargo build

# apt - NOT RECOMMENDED via proxychains
# Better to use Tor APT transport:
# https://onion.debian.org/
```

### Docker via Tor

```bash
# Docker daemon does not use LD_PRELOAD
# Configure the proxy in the daemon:

# /etc/docker/daemon.json
{
  "proxies": {
    "http-proxy": "socks5://127.0.0.1:9050",
    "https-proxy": "socks5://127.0.0.1:9050"
  }
}

# Restart Docker
sudo systemctl restart docker

# Now docker pull goes through Tor
docker pull debian:bookworm
# SLOW but functional
```

---

## Cloud services and APIs

### APIs with rate limiting

```
Problem: APIs limit requests per IP.
Tor exits are shared among thousands of users.
→ The rate limit is already nearly exhausted for "your" exit IP.

Example:
  GitHub API: 60 requests/hour per unauthenticated IP
  But from exit 185.220.101.x, other users have already used 55 requests
  → You have only 5 requests left

Solution:
  1. Frequent NEWNYM (change exit = new rate limit)
  2. API authentication (rate limit per account, not per IP)
  3. Use the regular network for high-volume API calls
```

### Cloud providers (AWS, GCP, Azure)

```
AWS Console: works via Tor Browser, possible CAPTCHAs
AWS CLI: proxychains aws ... → works but slow
GCP Console: works, possible additional verification
Azure: works, possible blocks for new accounts

WARNING: do not create cloud accounts from a Tor IP
→ Accounts are often blocked immediately for suspected abuse
→ Create accounts from the regular network, then use via Tor if needed
```

---

## Web sessions and variable IPs

### The problem

Tor changes IPs periodically (every ~10 minutes or with NEWNYM). Many websites
bind the session to the IP:

```
1. Login with IP 185.220.101.143 → session created, cookie set
2. Circuit changes → new IP 104.244.76.13
3. Site sees different IP → invalidates session → forced logout

Most affected sites:
  - Banking: immediate logout on IP change
  - Shopping: cart emptied, session invalidated
  - Email: re-authentication required
  - Social media: "suspicious login from new location"
  - SaaS: MFA required on every IP change
```

### Mitigation: MaxCircuitDirtiness

```ini
# In torrc: increase time before circuit renewal
MaxCircuitDirtiness 1800    # 30 minutes instead of 10 (default 600)
```

**Trade-off**: more time with the same IP = more trackable.
For non-sensitive browsing: 1800 is acceptable.
For maximum anonymity: keep the default 600.

### Mitigation: circuit isolation

```ini
# SocksPort with per-destination isolation
SocksPort 9050 IsolateDestAddr IsolateDestPort

# This makes connections to the SAME site use the SAME circuit
# but DIFFERENT sites use different circuits
# → The session is more stable for a single site
# → But different sites have different exits
```

---

## CAPTCHA management

### Why CAPTCHAs appear

```
1. IP reputation: Tor exits have low reputation
   (used for spam, scraping, attacks)
2. Anomalous traffic: many requests from the same IP
   (shared among thousands of users)
3. Missing fingerprint: Tor Browser does not send previous
   session cookies → "first-time visitor" every time
4. Cloudflare/Akamai: CDNs implement challenges for suspicious IPs
```

### Strategies

```
1. NEWNYM: change exit, may get an IP with better reputation
2. Tor-friendly search engines:
   - DuckDuckGo (also via .onion)
   - Startpage (Google proxy)
   - SearXNG (self-hosted meta-search engine)
3. Sites with .onion: completely bypass CAPTCHAs
   (Facebook, NYT, BBC, DuckDuckGo)
4. Patience: complete the CAPTCHAs (slow but works)
5. Tor Browser: handles JavaScript challenges better than Firefox
```

---

## The fundamental trade-off

Using Tor with real-world applications requires accepting compromises:

```
1. Speed:          everything is slower (5-50x)
2. Compatibility:  many apps don't work (UDP, raw socket)
3. Blocks:         many sites block or limit Tor
4. Sessions:       unstable due to IP changes
5. Functionality:  no video calls, no voice, no gaming, no streaming
6. CAPTCHAs:       frequent and frustrating
7. Rate limit:     shared with other users on the same exit
```

Tor is designed for **anonymity**, not convenience. The limitations are
direct consequences of the architectural choices that guarantee anonymity
(3 hops, circuit rotation, no UDP, exit policies).

In my experience, the best strategy is:
- **Tor for what requires anonymity**: sensitive browsing, research, testing
- **Regular network/VPN for the rest**: banking, shopping, streaming, gaming
- **Never mix** the two in the same session

---

## In my experience

Applications I use daily via Tor:
```
curl:    ★★★★★  Perfect, my primary tool
Firefox: ★★★★☆  Works well with tor-proxy profile
git:     ★★★★☆  Clone/push work, a bit slow
ssh:     ★★★☆☆  Slow but functional with keep-alive
nmap:    ★★☆☆☆  Only -sT, extremely slow
wget:    ★★★★☆  Downloads work well
```

Applications I NEVER use via Tor:
```
Banking, PayPal, Amazon → blocks and account lock risk
Discord, Zoom, Teams → UDP required
Spotify, Netflix → too slow / blocked
Steam → UDP required
```

---

## See also

- [Tor Browser and Applications](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Tor Browser internals, compatibility matrix
- [ProxyChains - Complete Guide](../04-strumenti-operativi/proxychains-guida-completa.md) - LD_PRELOAD, configuration
- [torsocks](../04-strumenti-operativi/torsocks.md) - Alternative to proxychains
- [Protocol Limitations](limitazioni-protocollo.md) - TCP-only, latency, bandwidth
- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - NEWNYM for changing exits
- [Anonymous Reconnaissance](../09-scenari-operativi/ricognizione-anonima.md) - OSINT via Tor
