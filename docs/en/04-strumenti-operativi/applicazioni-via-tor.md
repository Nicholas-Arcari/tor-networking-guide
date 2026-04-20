> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/applicazioni-via-tor.md) | English

# Applications via Tor - Routing, Compatibility and Issues

Methods for routing applications through Tor (proxychains, torsocks,
native SOCKS5, env vars), compatibility matrix, and common issues.

Extracted from [Tor Browser and Applications](tor-browser-e-applicazioni.md).

---

## Table of Contents

- [Routing applications through Tor](#routing-applications-through-tor)
- [Complete compatibility matrix](#complete-compatibility-matrix)
- [Applications with native SOCKS5](#applications-with-native-socks5)
- [Common problems and solutions](#common-problems-and-solutions)

---

## Routing applications through Tor

### Method 1: proxychains (LD_PRELOAD)

```bash
# proxychains intercepts network calls via LD_PRELOAD
# Works with most dynamically linked applications

proxychains curl https://example.com
proxychains firefox -no-remote -P tor-proxy
proxychains git clone https://github.com/user/repo
proxychains ssh user@host
proxychains nmap -sT -Pn target.com
```

**When it works**: applications that use glibc and make standard network calls
(connect, getaddrinfo, etc.).

**When it does NOT work**:
- Statically linked applications (Go binaries, Rust binaries)
- Applications that use raw sockets (nmap -sS, ping)
- Applications that handle sockets directly (bypass glibc)
- Electron applications (have their own networking stack)

### Method 2: torsocks (specialized LD_PRELOAD)

```bash
# torsocks is specific to Tor, more secure than proxychains
# Actively blocks non-TCP (UDP) connections instead of ignoring them

torsocks curl https://example.com
torsocks ssh user@host
torsocks wget https://example.com/file

# Advantage: if an app attempts UDP, torsocks BLOCKS it
# proxychains: would silently ignore the UDP attempt
```

### Method 3: native SOCKS5 configuration in the app

```bash
# Some applications support SOCKS5 proxy in their configuration
# This is more reliable than LD_PRELOAD

# Native curl:
curl --socks5-hostname 127.0.0.1:9050 https://example.com
# or
curl -x socks5h://127.0.0.1:9050 https://example.com

# Native git:
git config --global http.proxy socks5h://127.0.0.1:9050
git config --global https.proxy socks5h://127.0.0.1:9050
# IMPORTANT: "socks5h" (with h) → resolve hostname via proxy

# SSH via ProxyCommand:
# In ~/.ssh/config:
Host *.onion
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

### Method 4: TransPort (transparent proxy)

```bash
# For system-wide use, iptables redirects all TCP traffic to Tor
# See docs/06-configurazioni-avanzate/transparent-proxy.md

# Advantages: ALL applications go through Tor, no per-app configuration
# Disadvantages: UDP blocked, degraded performance, fragile
```

---

## Complete compatibility matrix

### CLI applications

| Application | Method | Works? | Safe DNS? | Notes |
|------------|--------|--------|-----------|-------|
| curl | `--socks5-hostname` | YES | YES | Perfect, my primary tool |
| curl | `--socks5` (without h) | YES but DNS LEAK | **NO** | Never use without -hostname |
| wget | proxychains | YES | YES (with proxy_dns) | Downloads work well |
| git (HTTPS) | proxychains or config | YES | YES | Clone, pull, push |
| git (SSH) | proxychains | Partial | YES | Slow, timeouts possible |
| ssh | proxychains or ProxyCommand | YES | YES | Slow but functional |
| pip | proxychains | YES | YES | Install Python packages via Tor |
| npm | proxychains | YES | YES | Install Node.js packages via Tor |
| gem | proxychains | YES | YES | Install Ruby gems via Tor |
| cargo | proxychains | Partial | YES | Rust: static linking can cause issues |
| rsync | proxychains | YES | YES | File synchronization |
| scp | proxychains | YES | YES | File copy via SSH |

### Security tools

| Application | Method | Works? | Notes |
|------------|--------|--------|-------|
| nmap -sT | proxychains | YES | TCP connect scan only, -Pn required |
| nmap -sS | proxychains | **NO** | SYN scan requires raw sockets |
| nmap -sU | proxychains | **NO** | UDP not supported by Tor |
| nmap -sn | proxychains | **NO** | Ping uses ICMP |
| nikto | proxychains | YES | Slow but functional |
| dirb/gobuster | proxychains | YES | Directory enumeration via Tor |
| sqlmap | proxychains or --proxy | YES | Supports SOCKS5 natively |
| Burp Suite | internal proxy config | YES | SOCKS proxy in settings |
| wfuzz | proxychains | YES | Web fuzzing via Tor |
| hydra | proxychains | Partial | TCP protocols only, very slow |
| ping | Not supported | **NO** | ICMP not supported |
| traceroute | Not supported | **NO** | ICMP/UDP |

### Desktop applications

| Application | Method | Works? | Notes |
|------------|--------|--------|-------|
| Firefox | proxychains + profile | YES | Without complete anti-fingerprint protections |
| Tor Browser | Integrated | YES | Complete setup, recommended |
| Chromium | proxychains | Partial | DoH can bypass, high fingerprint |
| Thunderbird | SOCKS5 proxy config | YES | Email via Tor possible |
| Discord | proxychains | **NO** | Uses WebSocket + UDP for voice |
| Telegram Desktop | internal proxy config | YES | Configure SOCKS5 in settings |
| Signal Desktop | proxychains | Partial | Works for messages, not calls |
| Steam | proxychains | **NO** | Uses UDP for gaming |
| Spotify | proxychains | **NO** | Proprietary protocol, streaming |
| VLC (streaming) | proxychains | **NO** | Uses UDP for streaming |
| Electron apps | proxychains | Partial | Often ignore LD_PRELOAD |
| VS Code | proxychains | Partial | Electron, extensions can bypass |
| Email clients (SMTP) | proxychains | Partial | Port 25 blocked by most exits |

### Specific services

| Service | Via Tor Browser | Via proxychains | Notes |
|---------|----------------|-----------------|-------|
| Google Search | YES (with CAPTCHA) | YES (with CAPTCHA) | Use DuckDuckGo/Startpage |
| Gmail | YES (difficult) | YES (difficult) | Requires phone verification |
| GitHub | YES | YES | Generally works well |
| Stack Overflow | YES | YES | Reading perfect, posting with verification |
| Wikipedia | YES (reading) | YES (reading) | Editing blocked from Tor IPs |
| Reddit | YES | YES | Login required more often |
| Amazon | YES (browsing) | YES (browsing) | Purchases often blocked |
| Banking | **NO** | **NO** | Blocked, possible account lock |
| PayPal | **NO** | **NO** | Blocked, possible suspension |
| Netflix | Partial | **NO** | Blocks many exit IPs |

---

## Applications with native SOCKS5

### Firefox (in the `tor-proxy` profile)

```
Settings → Network Settings → Manual proxy configuration
  SOCKS Host: 127.0.0.1
  SOCKS Port: 9050
  SOCKS v5
  ☑ Proxy DNS when using SOCKS v5

Or in about:config:
  network.proxy.type = 1
  network.proxy.socks = "127.0.0.1"
  network.proxy.socks_port = 9050
  network.proxy.socks_version = 5
  network.proxy.socks_remote_dns = true
```

### git

```bash
# Global configuration
git config --global http.proxy socks5h://127.0.0.1:9050
git config --global https.proxy socks5h://127.0.0.1:9050

# For a specific repository only
cd /path/to/repo
git config http.proxy socks5h://127.0.0.1:9050

# Remove the proxy
git config --global --unset http.proxy
git config --global --unset https.proxy

# IMPORTANT: "socks5h" with the 'h' = hostname resolved by the proxy
# "socks5" without 'h' = hostname resolved locally (DNS leak!)
```

### SSH

```
# ~/.ssh/config
Host *.onion
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p

# For any host via Tor:
Host tor-*
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p

# Usage:
ssh tor-myserver.com    # Goes through Tor
ssh myserver.com        # Direct connection
```

### Telegram Desktop

```
Settings → Advanced → Connection type → Use custom proxy
  Type: SOCKS5
  Hostname: 127.0.0.1
  Port: 9050
  Username: (empty)
  Password: (empty)
```

### Burp Suite

```
Settings → Network → Connections → SOCKS proxy
  Host: 127.0.0.1
  Port: 9050
  ☑ Use SOCKS proxy
  ☑ Do DNS lookups over SOCKS proxy
```

### sqlmap

```bash
# Via --proxy option
sqlmap -u "https://target.com/page?id=1" --proxy=socks5://127.0.0.1:9050

# Or via proxychains
proxychains sqlmap -u "https://target.com/page?id=1"
```

---

## Common problems and solutions

### Problem: application ignores proxychains

```bash
# Symptom: application connects directly (real IP exposed)
# Cause: statically linked application or uses raw sockets

# Check if the application is dynamically linked:
ldd /usr/bin/app_name
# If it shows "not a dynamic executable" → proxychains will not work

# Solution 1: use torsocks (may work where proxychains fails)
torsocks app_name

# Solution 2: configure the proxy in the application
# Solution 3: use TransPort/transparent proxy (iptables)
# Solution 4: use network namespace
```

### Problem: frequent timeouts

```bash
# Symptom: "Connection timed out" after a few seconds
# Cause: application has timeouts too short for Tor

# For curl: increase the timeout
curl --socks5-hostname 127.0.0.1:9050 --max-time 60 https://example.com

# For git: increase timeouts
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 60

# For SSH: keep-alive
# ~/.ssh/config
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ConnectTimeout 60
```

### Problem: DNS leak despite proxychains

```bash
# Symptom: tcpdump shows outgoing DNS queries
# Cause: proxy_dns not active, or app bypasses LD_PRELOAD

# Check 1: proxy_dns in config
grep proxy_dns /etc/proxychains4.conf
# Must show: proxy_dns (not commented out)

# Check 2: test with tcpdump
sudo tcpdump -i eth0 port 53 -n &
proxychains curl -s https://example.com > /dev/null
# If tcpdump shows queries → leak

# Solution: add anti-leak iptables rules
sudo iptables -A OUTPUT -p udp --dport 53 -m owner ! --uid-owner debian-tor -j DROP
```

### Problem: infinite CAPTCHAs

```
Symptom: Google/Cloudflare shows CAPTCHAs on every page
Cause: the Tor exit IP is on a blocklist

Solutions:
1. Change exit: NEWNYM (via ControlPort or nyx)
2. Use Tor-friendly search engines (DuckDuckGo, Startpage)
3. For Cloudflare: no universal solution, depends on the site
4. Force an exit from a specific country (NOT recommended for privacy):
   ExitNodes {de},{nl}  # Exit from Germany/Netherlands (less blocked)
```

---

## In my experience

### My daily workflow

```bash
# Anonymous web browsing:
proxychains firefox -no-remote -P tor-proxy & disown

# Quick checks:
proxychains curl -s https://api.ipify.org  # Verify IP

# Security testing:
proxychains nmap -sT -Pn -p 80,443,8080 target.com

# Git via Tor:
proxychains git clone https://github.com/user/repo

# Everything else: normal network
firefox  # Default profile, no proxy
```

### Tor Browser vs my setup - Final summary

| Aspect | Tor Browser | My setup (Firefox+proxychains) |
|--------|-------------|-------------------------------|
| IP anonymity | Excellent | Excellent |
| Anti-fingerprinting | Excellent | Poor |
| DNS leak prevention | Automatic | Requires config (proxy_dns) |
| WebRTC protection | Automatic | Manual (about:config) |
| Cross-site tracking | FPI (automatic) | No native protection |
| Circuits per domain | Automatic | No (same circuit for all) |
| Ease of use | Download and run | Manual configuration |
| Flexibility | Limited (it is a browser) | High (any app) |
| For maximum anonymity | **YES** | NO |
| For testing and development | Not practical | **YES** |

My setup is a conscious compromise: I sacrifice anti-fingerprinting to
have the flexibility of using Tor with any CLI tool and with Firefox
in a development environment.

---

## See also

- [ProxyChains - Complete Guide](proxychains-guida-completa.md) - LD_PRELOAD, chain modes, proxy_dns
- [torsocks](torsocks.md) - Comparison with proxychains, UDP blocking, edge cases
- [IP, DNS and Leak Verification](verifica-ip-dns-e-leak.md) - Complete tests to verify protection
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) - All fingerprinting vectors
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Complete DNS leak prevention
- [Circuit Control and NEWNYM](controllo-circuiti-e-newnym.md) - Circuit management and IP changes
