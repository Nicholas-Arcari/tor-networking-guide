> **Lingua / Language**: [Italiano](../../07-limitazioni-e-attacchi/limitazioni-applicazioni.md) | English

# Application Limitations - What Works and What Doesn't with Tor

This document catalogs the behavior of specific applications when used
through Tor: web apps, desktop applications, cloud services, development tools,
and security tools. For each category it analyzes why they work or don't work,
available workarounds, session management with variable IPs, and CAPTCHA strategies.

Based on my direct experience testing various applications via
proxychains and Tor on Kali Linux.

---

## Table of Contents

- [Why applications have problems with Tor](#why-applications-have-problems-with-tor)
- [Web Applications](#web-applications)
- [Sites that block Tor - Strategies](#sites-that-block-tor---strategies)
- [Desktop Applications](#desktop-applications)
- **Deep dives** (dedicated files)
  - [Tools, Cloud and Sessions via Tor](limitazioni-applicazioni-pratica.md)

---

## Why applications have problems with Tor

Applications fail with Tor for five fundamental reasons:

```
1. Protocol: they use UDP, ICMP, or raw sockets
   → Tor supports ONLY TCP
   → UDP: VoIP, gaming, direct DNS, QUIC, NTP
   → ICMP: ping, traceroute
   → Raw socket: nmap -sS, ping

2. Proxy architecture: they do not respect SOCKS5
   → Statically linked apps: ignore LD_PRELOAD
   → Electron apps: their own network stack (Node.js)
   → Apps with hardcoded DNS: bypass proxy_dns
   → Apps with raw sockets: cannot be proxied

3. Anti-abuse security: they block Tor exit IPs
   → The exit list is public (check.torproject.org/torbulkexitlist)
   → Exit IPs have low reputation (used for spam, attacks)
   → CAPTCHAs, blocks, account suspension

4. IP-bound sessions: invalidated by IP changes
   → Tor changes exit every ~10 min (MaxCircuitDirtiness)
   → The site sees a different IP → session invalidated
   → Forced logout, cart emptied, etc.

5. Performance: insufficient latency and bandwidth
   → 3 hops = 200-500ms RTT
   → Limited bandwidth (typically 1-10 Mbps via Tor)
   → Timeouts for applications with aggressive timers
```

---

## Web Applications

### Sites that block or limit Tor

#### Google (Search, Maps, Gmail)

**Behavior**: aggressive and repeated CAPTCHAs. Sometimes total block with
the message "unusual traffic from your computer network".

**Reason**: Google receives enormous amounts of automated traffic (bots, scraping)
from Tor exits. To protect itself, it requires human verification.

**In my experience**: Google searches via Tor are often frustrating.
Every 2-3 searches a CAPTCHA appears. Sometimes the CAPTCHA is endless.

**Workaround**:
```
1. Use DuckDuckGo (https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion)
2. Use Startpage (anonymous Google proxy)
3. NEWNYM to change exit and retry
4. Google has an experimental .onion: not always available
```

#### Amazon

**Behavior**: browsing works. Login may fail with
"suspicious activity". Purchases are often blocked.

**Reason**: Amazon blocks logins from IPs with low reputation.

**Workaround**: do not use Tor for purchases. Use the regular network.

#### PayPal

**Behavior**: login blocked immediately. Account may be
temporarily suspended.

**Reason**: PayPal has aggressive anti-fraud policies. Tor exit = high risk.

**Workaround**: none. Do not use PayPal via Tor.

#### Instagram / Meta

**Behavior**: login very difficult. Identity verification requested, SMS, selfie.
Often complete account lockout.

**Workaround**: do not use Meta via Tor for personal accounts.
Facebook has an official .onion for anonymous browsing.

#### Reddit

**Behavior**: works for reading. Login required more frequently.
Some subreddits block posts/comments from Tor.

**Workaround**: use old.reddit.com (less JavaScript, works better).

#### Wikipedia

**Behavior**: reading works perfectly. **Editing is blocked** for all Tor
exit IPs (anti-vandalism policy).

**Workaround**: request an IP block exemption for
trusted accounts. A lengthy but possible process.

#### GitHub

**Behavior**: generally works well. Occasionally requires
additional authentication. Push/pull via HTTPS work with proxychains.

```bash
# Clone via Tor:
proxychains git clone https://github.com/user/repo

# Push via Tor:
proxychains git push origin main

# Or permanent configuration:
git config --global http.proxy socks5h://127.0.0.1:9050
```

#### Stack Overflow

**Behavior**: works well for reading and searching. Login and posting may
require extra verification.

#### Italian banks (home banking)

**Behavior**: **total block** in my experience. Banking anti-fraud systems
immediately block connections from Tor/datacenter IPs. The account is often
temporarily locked, requiring a call to customer support.

**Rule**: NEVER use Tor to access banking services.

#### Cloudflare-protected sites

**Behavior**: many sites use Cloudflare as CDN/WAF. Cloudflare
implements additional checks for Tor IPs:
```
- "Checking your browser..." page (JavaScript challenge)
- hCaptcha or Turnstile CAPTCHA
- Complete block for some sites
- Behavior depends on the site's configuration
```

**Workaround**:
```
1. NEWNYM and retry (different exit = different reputation)
2. Wait for the JavaScript challenge to complete (5-10 seconds)
3. Use Tor Browser (handles challenges better than Firefox+proxychains)
4. There is no universal solution: it depends on the site
```

---

## Sites that block Tor - Strategies

### Strategy 1: change exit

```bash
# Change exit node via ControlPort
echo -e "AUTHENTICATE \"password\"\r\nSIGNAL NEWNYM\r\nQUIT" | nc 127.0.0.1 9051

# Wait ~5 seconds for the new circuit
sleep 5

# Retry
proxychains curl -s https://problematic-site.com
```

### Strategy 2: force exits from specific countries (temporary)

```ini
# In torrc (temporarily):
ExitNodes {de},{nl},{ch}    # Exits from countries with high reputation
StrictNodes 1

# WARNING: reduces anonymity! Use only for temporary tests.
# Remove after use.
```

### Strategy 3: personal exit node

```
If you run an exit node, its IP has better reputation
(less abused than shared exits). But:
- Cost and management complexity
- Your exit is linkable to you
- Not recommended for personal anonymity
```

### Strategy 4: accept the compromise

Some sites will never work well via Tor. Accept that Tor is not
suited for everything and use the regular network for those sites.

---

## Desktop Applications

### Tor Browser vs Firefox with SOCKS proxy

| Aspect | Tor Browser | Firefox + proxychains |
|--------|-------------|----------------------|
| Anonymous IP | YES | YES |
| DNS via Tor | Automatic | Requires proxy_dns |
| Anti-fingerprinting | Complete (300+ patches) | Minimal (resistFingerprinting) |
| WebRTC protection | Automatic | Manual (about:config) |
| Per-domain circuits | Automatic (FPI) | No |
| Ease of use | High | Medium |
| Flexibility | Low | High |

### Applications that DO NOT work with proxychains

| Application | Reason | Alternative |
|------------|--------|-------------|
| Discord | Uses WebSocket + UDP for voice | No alternative via Tor |
| Telegram Desktop | Proprietary network stack | SOCKS5 proxy in settings |
| Steam | Uses UDP for gaming, TCP for store | Store works poorly via browser |
| Spotify | Proprietary streaming protocol | Not practical via Tor |
| Electron apps (VS Code, Slack) | Often ignore LD_PRELOAD | Depends on the app |
| Desktop email clients (Thunderbird) | SMTP port 25 blocked by exits | Internal SOCKS5 config + SMTP on 587 |
| Zoom/Teams | UDP for video/voice | Not practical via Tor |
| VLC streaming | UDP/RTP | Not practical |
| Dropbox client | Proprietary protocol | Web interface via Tor Browser |
| OneDrive/Google Drive sync | Background system services | Web interface via Tor Browser |

### Applications that work with proxychains

| Application | Quality | Notes |
|------------|---------|-------|
| curl | Excellent | My primary tool (`--socks5-hostname`) |
| wget | Good | Downloads work, watch out for redirects |
| git (HTTPS) | Good | Clone, pull, push (`socks5h://`) |
| ssh | Acceptable | Slow but functional, keep-alive recommended |
| pip | Good | Installs Python packages via Tor |
| npm | Good | Installs Node.js packages via Tor |
| gem | Good | Installs Ruby gems via Tor |
| rsync (via SSH) | Acceptable | Slow for large files |
| lynx/w3m | Good | Text browsers, no JavaScript |
| aria2c | Good | Downloads with resume via proxy |

### Statically linked Go applications

```
Problem: many Go applications are statically compiled.
LD_PRELOAD (used by proxychains) does not work with static binaries.

Examples: hugo, terraform, kubectl, docker (CLI), gh (GitHub CLI)

Solutions:
1. Use torsocks (may work where proxychains fails)
2. Configure environment variables:
   export HTTP_PROXY=socks5://127.0.0.1:9050
   export HTTPS_PROXY=socks5://127.0.0.1:9050
   export ALL_PROXY=socks5://127.0.0.1:9050
3. Use TransPort (transparent proxy at the iptables level)
4. Use network namespace
```

---

> **Continues in** [Application Limitations - Tools, Cloud and Sessions](limitazioni-applicazioni-pratica.md)
> - nmap, nikto, sqlmap, Burp Suite, Metasploit, package managers, Docker via Tor,
> cloud services and APIs, web sessions with variable IPs, CAPTCHA management.

---

## See also

- [Tor Browser and Applications](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Tor Browser internals
- [ProxyChains - Complete Guide](../04-strumenti-operativi/proxychains-guida-completa.md) - LD_PRELOAD, configuration
- [torsocks](../04-strumenti-operativi/torsocks.md) - Alternative to proxychains
- [Protocol Limitations](limitazioni-protocollo.md) - TCP-only, latency, bandwidth
