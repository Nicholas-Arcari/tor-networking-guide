> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/tor-browser-e-applicazioni.md) | English

# Tor Browser and Application Routing

This document analyzes Tor Browser (its internal protections, how patches work,
the update mechanism), the difference with Firefox+proxychains, how to route
different applications through Tor, and strategies for each type of application
in the real world.

Based on my experience with Firefox + `tor-proxy` profile via proxychains,
and the awareness of the limitations of this approach compared to Tor Browser.

---

## Table of Contents

- [Tor Browser - Internal architecture](#tor-browser---internal-architecture)
- [Anti-fingerprinting protections in detail](#anti-fingerprinting-protections-in-detail)
- [Network protections](#network-protections)
- [Security Level and NoScript](#security-level-and-noscript)
- [Update mechanism](#update-mechanism)
- [First-Party Isolation in depth](#first-party-isolation-in-depth)
- [Firefox + proxychains - My setup and its limitations](#firefox--proxychains---my-setup-and-its-limitations)
**Deep dives** (dedicated files):
- [Applications via Tor](applicazioni-via-tor.md) - Routing, compatibility, native SOCKS5, issues

---

## Tor Browser - Internal architecture

Tor Browser is a modified Firefox ESR with specific patches. It is not "Firefox with
a SOCKS proxy configured". The differences are deep and touch the browser's
source code.

### Tor Browser components

```
Tor Browser Bundle contains:
├── firefox (Firefox ESR patched with ~300 modifications)
├── tor (integrated Tor daemon)
├── torrc-defaults (minimal Tor configuration)
├── pluggable_transports/
│   ├── obfs4proxy (obfs4 bridge)
│   ├── snowflake-client
│   └── meek-client
├── TorButton (integrated extension)
│   ├── Identity management (New Identity)
│   ├── Circuit management (per-tab circuit display)
│   └── Security Level UI
└── NoScript (extension to block JavaScript)
```

### How Tor Browser connects

```
1. The user starts Tor Browser
2. The integrated Tor daemon starts and bootstraps
3. Firefox connects to Tor via local SocksPort (127.0.0.1:9150)
   NOTE: port 9150, NOT 9050 (to avoid conflict with system Tor)
4. Each tab uses different SOCKS credentials
   → Tab 1: user="tab1-unique-id" pass="random"
   → Tab 2: user="tab2-unique-id" pass="random"
5. Tor creates different circuits for different credentials
   → Each domain has its own circuit
   → No cross-tab correlation at the network level
```

### Difference with system Tor

```
Tor Browser (integrated):
  - SocksPort 9150 (not 9050)
  - ControlPort 9151 (not 9051)
  - Tor configured for the browser, not for general use
  - Shuts down with the browser
  - Does not share circuits with other applications

System Tor (my setup):
  - SocksPort 9050
  - ControlPort 9051
  - Tor shared among all applications (curl, Firefox, git, etc.)
  - Remains active as a systemd service
  - Circuits are shared (unless IsolateSOCKSAuth)
```

---

## Anti-fingerprinting protections in detail

### Complete comparison table

| Fingerprinting vector | Normal Firefox | Tor Browser | How TB mitigates it |
|-----------------------|---------------|-------------|---------------------|
| User-Agent | Reveals OS, version, architecture | Unified | Always "Windows NT 10.0" |
| Window dimensions | Reflects the real monitor | Rounded | Letterboxing (gray borders) |
| Canvas | Reveals GPU and drivers | Randomized | Built-in Canvas Blocker |
| WebGL | Reveals GPU model | Disabled/spoofed | `webgl.disabled = true` |
| Fonts | Reveals installed fonts (unique per OS) | Standard fonts only | Bundled font list |
| Timezone | Reveals your timezone | Always UTC | `privacy.resistFingerprinting` |
| Language | Reveals system language | Always en-US | Fixed Accept-Language header |
| Screen resolution | Reveals real monitor | Spoofed | Reported as standard multiple |
| AudioContext | Audio hardware fingerprint | Neutralized | Modified API |
| Battery API | Reveals battery status | Disabled | API removed |
| Connection API | Reveals connection type | Disabled | API removed |
| Plugins/Extensions | List of installed extensions | None visible | `plugins.enumerable_names = ""` |
| navigator.hardwareConcurrency | Reveals CPU count | Fixed at 2 | Hardcoded value |
| navigator.deviceMemory | Reveals RAM | Not exposed | API unavailable |
| Math precision | Differences between CPUs | Unified | Normalized results |
| Performance.now() | High-precision timer | Reduced | Precision at 100ms |

### Letterboxing in detail

Tor Browser does not resize the web page to the exact window dimensions.
It adds gray borders to round dimensions to multiples of 200x100 pixels:

```
Real window: 1367 x 843 pixels
Size reported to site: 1200 x 800 pixels (multiple of 200x100)
Gray border: 167px horizontal, 43px vertical

This ensures that all users with windows between 1200x800 and 1399x899
have the same reported size → same fingerprint for this metric.
```

### Canvas fingerprinting - how TB blocks it

```
Without protection:
  1. The site draws text/shapes on a <canvas>
  2. Calls canvas.toDataURL() to read the pixels
  3. Pixels depend on GPU, drivers, font rendering → unique fingerprint

With Tor Browser:
  1. The site draws on <canvas> (allowed)
  2. When it calls toDataURL():
     - TB shows a prompt: "This site wants to extract data from the canvas"
     - If the user denies: returns empty data
     - If the user allows: returns slightly randomized data
  3. Randomization differs per session → no persistent tracking
```

---

## Network protections

### Network comparison table

| Protection | Normal Firefox | Tor Browser |
|-----------|---------------|-------------|
| WebRTC | Active (real IP leak!) | **Disabled** |
| DNS | Uses system resolver | Always via Tor (SOCKS5) |
| DNS Prefetch | Active (preloads DNS) | **Disabled** |
| HTTP/3 (QUIC) | Active (uses UDP) | **Disabled** |
| Speculative connections | Active | **Disabled** |
| HSTS tracking | Possible (supercookie) | Reset on close |
| OCSP requests | In the clear to the CA | Disabled (CRL stapled) |
| TLS session resumption | Active (tracking vector) | **Disabled** |
| HTTP referrer | Full | Truncated to domain |
| Safe browsing | Connects to Google | **Disabled** |
| Telemetry | Active | **Completely removed** |
| Crash reporter | Active | **Removed** |
| Geolocation API | Active | **Disabled** |
| Search suggestions | Sent in real time | **Disabled** |
| Page prefetch | Active | **Disabled** |
| Beacon API | Active (tracking) | **Disabled** |

### WebRTC - why it is so dangerous

```javascript
// Without protection, any website can execute:
var pc = new RTCPeerConnection({iceServers: [{urls: "stun:stun.l.google.com:19302"}]});
pc.createDataChannel('');
pc.createOffer().then(offer => pc.setLocalDescription(offer));
pc.onicecandidate = function(event) {
    if (event.candidate) {
        var ip = event.candidate.candidate.match(/(\d+\.\d+\.\d+\.\d+)/);
        // ip[1] contains your REAL IP (local or public)
        // This completely bypasses the SOCKS5 proxy!
    }
};
// Result on unprotected Firefox:
//   "candidate:0 1 UDP 2122252543 192.168.1.100 44323 typ host"
//   → 192.168.1.100 is your real local IP
```

Tor Browser: `media.peerconnection.enabled = false` - the API does not exist.

---

## Security Level and NoScript

### The three security levels

Tor Browser has a "Security Level" accessible from the shield in the toolbar:

**Standard (default)**:
```
- JavaScript: enabled
- Canvas: prompt before extraction
- Audio/Video: enabled
- Remote fonts: loaded
- MathML: enabled
→ Maximum usability, baseline protection
→ For general browsing on trusted sites
```

**Safer**:
```
- JavaScript: disabled on HTTP sites (not HTTPS)
- Audio/Video: click-to-play
- Remote fonts: blocked
- MathML: disabled
- Some dangerous JS features: disabled (JIT, WASM)
→ Good security/usability compromise
→ For browsing on mixed sites
```

**Safest**:
```
- JavaScript: completely disabled EVERYWHERE
- Images: loaded but no scripts
- Audio/Video: disabled
- Remote fonts: blocked
- CSS: reduced functionality
→ Maximum security, many sites will not work
→ For sensitive .onion sites or high-risk browsing
```

### Impact on security

```
Standard: vulnerable to JavaScript exploits (e.g. Freedom Hosting 2013)
Safer: protected from most JS exploits (no JIT = no JIT exploits)
Safest: protected from nearly all web exploits (no JS = minimal surface)

Trade-off:
  Standard → 90% of sites work → medium risk
  Safer → 70% of sites work → low risk
  Safest → 30% of sites work → minimal risk
```

### NoScript in Tor Browser

NoScript is integrated in Tor Browser and controlled by the Security Level:

```
Standard: NoScript is present but allows everything
Safer: NoScript blocks JS on HTTP, allows on HTTPS
Safest: NoScript blocks everything (JS, fonts, media, frames)

IMPORTANT: do not manually modify NoScript rules
→ Custom rules create a unique fingerprint
→ All TB users at the "Standard" level have the same rules
→ Customizing = standing out from the group
```

---

## Update mechanism

### How Tor Browser updates

```
1. Tor Browser periodically checks
   https://aus1.torproject.org/torbrowser/update_3/
   (via Tor, not in the clear)

2. If an update is available:
   - Shows a notification in the toolbar
   - Automatic background download (via Tor)
   - The user can apply with one click

3. Integrity verification:
   - The update is signed with Tor Project keys
   - SHA256 hash verified
   - If verification fails → update rejected
```

### Why updates are critical

```
Tor Browser is based on Firefox ESR (Extended Support Release)
Firefox ESR receives security patches every ~6 weeks
Tor Browser follows the same cycle

If you do NOT update:
  - Known vulnerabilities (CVEs) are unpatched
  - Public exploits are available
  - Freedom Hosting case (2013): exploit on unpatched Firefox ESR 17
  
RULE: update Tor Browser IMMEDIATELY when available
```

---

## First-Party Isolation in depth

### How FPI works

Tor Browser implements **First-Party Isolation (FPI)**, which isolates all
browser state by first-party domain:

```
Without FPI (normal Firefox):
  tracker.com on site-a.com → cookie tracker.com = "user123"
  tracker.com on site-b.com → reads cookie tracker.com = "user123"
  → tracker.com knows you visited both site-a and site-b

With FPI (Tor Browser):
  tracker.com on site-a.com → cookie {site-a.com, tracker.com} = "user123"
  tracker.com on site-b.com → cookie {site-b.com, tracker.com} = EMPTY
  → tracker.com CANNOT correlate the visits
```

### What is isolated by domain

```
- Cookies: isolated by first-party domain
- HTTP cache: isolated by first-party domain
- Image/font cache: isolated
- TLS connections: separate sessions per domain
- HSTS state: isolated per domain
- OCSP responses: isolated
- SharedWorkers: isolated
- Service Workers: disabled
- Favicon cache: isolated
- Alt-Svc: isolated (no cross-site HTTP/2 push)
- Tor circuit: different per domain (via SOCKS auth)
```

### Circuits per domain

```
Tab 1: visits site-a.com
  → SOCKS auth: user="site-a.com" pass="random1"
  → Tor uses circuit A (Guard X → Middle Y → Exit Z)

Tab 2: visits site-b.com
  → SOCKS auth: user="site-b.com" pass="random2"
  → Tor uses circuit B (Guard X → Middle W → Exit V)

Tab 3: visits site-a.com/other-page
  → SOCKS auth: user="site-a.com" pass="random1" (same domain)
  → Reuses circuit A
  
→ Different exits for different domains
→ The destination server cannot correlate visits to different sites
→ Even the exit node cannot correlate
```

---

## Firefox + proxychains - My setup and its limitations

### How I configured my setup

```bash
# 1. Create a dedicated profile (one-time)
firefox -no-remote -CreateProfile tor-proxy

# 2. Start Firefox with the profile, via proxychains
proxychains firefox -no-remote -P tor-proxy & disown
```

The `-no-remote` flag prevents Firefox from connecting to an existing instance
(which might not go through Tor).

### Manual configurations needed in the profile

In `about:config` of the `tor-proxy` profile:

```
# Network protection
media.peerconnection.enabled = false        # Disable WebRTC (prevents IP leak)
network.http.http3.enabled = false           # Disable QUIC/HTTP3 (uses UDP)
network.dns.disablePrefetch = true           # No DNS prefetch
network.prefetch-next = false                # No page prefetch
network.predictor.enabled = false            # No speculative connections
browser.send_pings = false                   # No tracking pings
geo.enabled = false                          # No geolocation

# Anti-fingerprinting
privacy.resistFingerprinting = true          # Basic protection (timezone, locale, etc.)
webgl.disabled = true                        # No WebGL fingerprint
dom.battery.enabled = false                  # No Battery API
dom.gamepad.enabled = false                  # No Gamepad API
media.navigator.enabled = false              # No media device enumeration

# Privacy
privacy.trackingprotection.enabled = true    # Tracking protection
network.cookie.cookieBehavior = 1            # First-party cookies only
browser.safebrowsing.enabled = false         # No connections to Google
browser.safebrowsing.malware.enabled = false # No connections to Google
toolkit.telemetry.enabled = false            # No telemetry

# DNS
network.proxy.socks_remote_dns = true        # DNS via SOCKS5
network.trr.mode = 5                         # Disable DoH completely
```

### What this setup does NOT protect

Even with these configurations, normal Firefox:

| Protection | Tor Browser | My Firefox |
|-----------|-------------|------------|
| Unified User-Agent | YES (all TB users identical) | NO (reveals Linux/Kali) |
| Letterboxing | YES | NO (real dimensions) |
| Cookie isolation by domain | YES (FPI) | NO (cross-site shared cookies) |
| Timezone spoofing | YES (UTC) | PARTIAL (with resistFingerprinting) |
| Unified fonts | YES (bundled fonts only) | NO (system fonts visible) |
| Canvas protection | YES (prompt + randomization) | PARTIAL (with resistFingerprinting) |
| Circuits per domain | YES (different SOCKS auth per domain) | NO (same circuit for all sites) |
| New Identity | YES (one click resets everything) | NO (must close and reopen) |
| Hidden extensions | YES | NO (extensions detectable) |

**Conclusion**: I use this setup for convenience and testing, not for maximum anonymity.
For real anonymity, Tor Browser must be used.

---

---

> **Continues in**: [Applications via Tor](applicazioni-via-tor.md) for routing
> methods, compatibility matrix, native SOCKS5, and common issues.

---

## See also

- [Applications via Tor](applicazioni-via-tor.md) - Routing, compatibility, issues
- [ProxyChains - Complete Guide](proxychains-guida-completa.md) - LD_PRELOAD, chain modes
- [torsocks](torsocks.md) - Comparison with proxychains, UDP blocking
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) - Fingerprinting vectors
- [Real-World Scenarios](scenari-reali.md) - Operational pentester cases
