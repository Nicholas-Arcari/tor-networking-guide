> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/fingerprinting-avanzato.md) | English

# Advanced Fingerprinting - HTTP/2, OS, Tracking and Defenses

Fingerprinting vectors beyond the browser: HTTP/2 SETTINGS, TCP/IP stack, cookieless
tracking (HSTS, ETag, favicon), server-side fingerprinting, and configurations
to reduce exposure.

> **Extracted from**: [Fingerprinting - Browser, Network and Operating System](fingerprinting.md)
> for browser fingerprinting and TLS/JA3.

---

## HTTP/2 Fingerprinting

### How it works

HTTP/2 adds a new fingerprinting layer through connection parameters:

```
HTTP/2 SETTINGS frame (sent at the start of the connection):
- HEADER_TABLE_SIZE
- ENABLE_PUSH
- MAX_CONCURRENT_STREAMS
- INITIAL_WINDOW_SIZE
- MAX_FRAME_SIZE
- MAX_HEADER_LIST_SIZE

Each browser sends different values:

Firefox: HEADER_TABLE_SIZE=65536, INITIAL_WINDOW_SIZE=131072,
         MAX_FRAME_SIZE=16384
Chrome:  HEADER_TABLE_SIZE=65536, INITIAL_WINDOW_SIZE=6291456,
         MAX_FRAME_SIZE=16384
Safari:  HEADER_TABLE_SIZE=4096, INITIAL_WINDOW_SIZE=4194304,
         MAX_FRAME_SIZE=16384

→ SETTINGS identify the browser
→ Combined with JA3 → very precise fingerprint
```

### HTTP/2 PRIORITY fingerprinting

```
Browsers send different priorities for resources:

Chrome: uses PRIORITY frame with complex dependency tree
Firefox: uses PRIORITY with weight-based scheme
Safari: uses PRIORITY differently

The priority pattern is an additional fingerprint.
```

---

## OS Fingerprinting

### TCP/IP Stack Fingerprinting

Every operating system has unique characteristics in its TCP/IP stack:

```
Analyzable parameters (passively, from the server):

Initial TTL:
  Linux: 64
  Windows: 128
  macOS: 64
  FreeBSD: 64

TCP Window Size:
  Linux (kernel 5.x+): 64240
  Windows 10/11: 64240 or 65535
  macOS: 65535

TCP Options (order and values):
  Linux: MSS, SackOK, TS val/ecr, NOP, WScale
  Windows: MSS, NOP, WScale, NOP, NOP, SackOK
  macOS: MSS, NOP, WScale, NOP, NOP, TS val/ecr, SackOK, EOL

DF bit (Don't Fragment):
  Linux: set
  Windows: set
  macOS: set

→ A server analyzing these parameters can determine your OS
  EVEN if the User-Agent declares a different OS
```

### Implication for Tor

```
Scenario:
  My Tor Browser (or Firefox with resistFingerprinting):
    User-Agent: "Windows NT 10.0"
    TCP/IP stack: TTL=64, Window=64240, Options=Linux-order
    → DISCREPANCY: User-Agent says Windows, TCP says Linux

The server sees:
  "This user declares Windows but has a Linux TCP stack"
  → Likely: Linux user spoofing the User-Agent
  → Reduces the anonymity set enormously

Tor Browser partially mitigates:
  → Normalizes some TCP parameters (WScale, MSS)
  → But TTL and TCP option order are difficult to spoof
    without kernel modification
```

### Defense: network namespace or VM

```
On Whonix:
  The Workstation is a VM → its TCP stack is that of the VM
  The Gateway transmits via Tor → the server sees the exit's TCP stack
  → The CLIENT's TCP fingerprint does not reach the server
  → Complete protection

On my setup:
  My TCP stack reaches the Tor exit
  The exit reconstructs the TCP connection to the server
  → The server sees the EXIT's TCP stack, not my PC's
  → Partially protected (but the guard sees my TCP)
```

---

## Advanced cookieless tracking

### HSTS Supercookie

```
A site can set HSTS for specific subdomains:
  a.example.com → HSTS = ON  (bit 1)
  b.example.com → HSTS = OFF (bit 0)
  c.example.com → HSTS = ON  (bit 1)
  d.example.com → HSTS = OFF (bit 0)

The HSTS pattern known to the browser: 1010 = unique tracking ID

On the next visit:
  The browser attempts HTTP for each subdomain
  a.example.com → redirect HTTPS (HSTS active → bit 1)
  b.example.com → no redirect (HSTS not active → bit 0)
  → Reconstructs the pattern → identifies the user

Mitigation: Tor Browser resets HSTS on close.
My Firefox: HSTS persists between sessions.
```

### ETag Tracking

```
1. First visit: server assigns unique ETag
   Response: ETag: "user-unique-id-abc123"
2. Second visit: browser includes the ETag
   Request: If-None-Match: "user-unique-id-abc123"
   → The server recognizes the user via the ETag
   → Works like a persistent but invisible cookie
```

### Favicon Caching

```
The browser caches favicons. A site can use unique URLs:
1. First access: the site sets favicon as /favicon-USER123.ico
2. The browser caches this specific favicon
3. Subsequent access: the browser requests /favicon-USER123.ico
   → The server sees that USER123 has returned
   → Tracking without cookies
```

### TLS Session Resumption

```
If the browser reuses TLS sessions (session ID or session ticket):
1. First connection: full TLS handshake
   Server assigns session ticket: "ticket-xyz"
2. Subsequent connection: browser presents "ticket-xyz"
   → Server recognizes the client → cross-session tracking

Tor Browser: disables session resumption
My Firefox: session resumption active
```

### DNS Cache Probing

```
A site can determine which sites you have recently visited:
1. The site includes resources from specific domains:
   <img src="https://visited-site.com/pixel.gif">
2. If the DNS for visited-site.com is in the cache → fast response
3. If not in the cache → slow response (DNS round-trip)
4. The timing difference reveals whether you visited visited-site.com

Mitigation: DNS via Tor (resolved by exit, not locally)
→ My setup is partially protected (with proxy_dns)
```

---

## Server-side fingerprinting

### Behavioral fingerprinting

```
A site can track user behavior:
- Typing speed (keystroke dynamics)
- Mouse movement patterns
- Scroll speed
- Click patterns
- Time spent on pages

These patterns are UNIQUE for each person
→ No technical tool protects against them
→ Only awareness and behavior variation
```

### Timing fingerprinting

```
The server measures the RTT (round-trip time) of requests:
- Constant RTT → same network location
- RTT variable in a pattern → specific ISP/network

Via Tor: the RTT is dominated by the 3 hops → varies with circuits
→ Less informative but not completely opaque
```

---

## Active vs passive fingerprinting

### Passive (server-side)

```
The server collects information without executing code in the browser:
- User-Agent header
- Accept-Language header
- TLS ClientHello (JA3/JA4)
- HTTP/2 SETTINGS
- TCP/IP stack parameters
- Timing

Defense: difficult, much of this information is necessary
for communication
```

### Active (JavaScript)

```
The server executes JavaScript in the browser:
- Canvas fingerprinting
- WebGL rendering
- AudioContext
- Font enumeration
- Screen dimensions
- navigator.* properties
- Battery API
- Gamepad API
- Performance.now() timing

Defense: Tor Browser neutralizes most of these
        Security Level "Safest" disables JavaScript → eliminates everything
```

---

## My real protection level

| Vector | Tor Browser | My Firefox+proxychains |
|--------|-------------|------------------------|
| User-Agent fingerprint | Protected (unified) | **Exposed** (reveals Linux/Kali) |
| Canvas fingerprint | Protected (randomized) | **Exposed** |
| WebGL fingerprint | Protected (disabled) | **Exposed** |
| Font fingerprint | Protected (limited fonts) | **Exposed** |
| TLS/JA3 fingerprint | Specific but uniform among TB users | **Unique** for my setup |
| HTTP/2 fingerprint | Uniform | **Specific** |
| Screen/Window size | Protected (letterboxing) | **Exposed** |
| Timezone | UTC | **Exposed** (Europe/Rome) |
| Language | en-US | **Exposed** (it-IT) |
| HSTS tracking | Reset | **Persistent** |
| Cookie tracking | Isolated per domain (FPI) | **Not isolated** |
| TCP/IP OS fingerprint | Partial (exit reconstructs) | Partial |
| AudioContext | Neutralized | **Exposed** |
| Behavioral | Not protected | Not protected |

**Conclusion**: my setup protects the IP but not the fingerprint. A
sufficiently sophisticated site can correlate my visits even if I change IP
with NEWNYM, because my fingerprint is constant and probably unique.

---

## Verification tools

### Sites to test your fingerprint

```bash
# AmIUnique - detailed fingerprint analysis
proxychains firefox https://amiunique.org/fingerprint

# Panopticlick (EFF) - uniqueness test
proxychains firefox https://coveryourtracks.eff.org/

# BrowserLeaks - test per specific vector
proxychains firefox https://browserleaks.com/

# CreepJS - advanced fingerprinting (canvas, WebGL, etc.)
proxychains firefox https://abrahamjuliot.github.io/creepjs/

# TLS fingerprint (JA3)
proxychains firefox https://ja3.io/
```

### Terminal tests

```bash
# Verify User-Agent
proxychains curl -s https://httpbin.org/headers | grep User-Agent

# Verify IP and geolocation
proxychains curl -s https://ipinfo.io

# Verify TLS fingerprint
proxychains curl -s https://ja3.io/json | python3 -m json.tool
```

---

## Configurations to reduce fingerprinting

In `about:config` of the `tor-proxy` profile:

```
# Base protection (enables many mitigations)
privacy.resistFingerprinting = true

# Disable dangerous APIs
media.peerconnection.enabled = false          # No WebRTC
webgl.disabled = true                         # No WebGL fingerprint
dom.battery.enabled = false                   # No Battery API
dom.gamepad.enabled = false                   # No Gamepad API
media.navigator.enabled = false               # No media devices
network.http.http3.enabled = false            # No QUIC/UDP

# Disable tracking vectors
network.http.http3.enabled = false            # No HTTP/3
browser.send_pings = false                    # No tracking pings
beacon.enabled = false                        # No Beacon API
```

`privacy.resistFingerprinting` enables many protections:
- Timezone forced to UTC
- Language forced to en-US
- Screen size spoofed
- Reduced precision for Performance.now() (anti-timing)
- Canvas readout blocked (with prompt)
- navigator.hardwareConcurrency forced to 2
- navigator.platform spoofed

**It is not equivalent to Tor Browser**, but it is better than nothing. JA3 and fonts
remain exposed, and the inconsistency between spoofed User-Agent and real TCP stack
can be more suspicious than not spoofing at all.

---

## In my experience

Fingerprinting is the Achilles' heel of my setup. I accept it
knowingly because my threat model does not require anonymity from
fingerprinting - I need privacy from the ISP (hiding destinations)
and from IP-based trackers.

For real fingerprinting anonymity: Tor Browser is the only solution.
For ISP privacy and testing: my Firefox+proxychains is sufficient.

---

## See also

- [Tor Browser and Applications](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - How Tor Browser mitigates fingerprinting
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Fingerprinting as an OPSEC mistake
- [Traffic Analysis](traffic-analysis.md) - Network traffic fingerprinting
- [DNS Leak](dns-leak.md) - DNS as a fingerprinting vector
- [System Hardening](hardening-sistema.md) - Firefox configurations in the tor-proxy profile
