> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/fingerprinting.md) | English

# Fingerprinting - Browser, Network and Operating System

This document analyzes all fingerprinting vectors that can compromise the
anonymity of a Tor user: from browser fingerprinting to TLS fingerprinting,
through OS fingerprinting, HTTP/2 fingerprinting, and advanced cookieless
tracking techniques. For each vector, I analyze how it works, how much
entropy it contributes, and how Tor Browser mitigates it compared to my
Firefox+proxychains setup.

Based on my awareness that my setup (Firefox+proxychains) does NOT protect
against fingerprinting, unlike Tor Browser.

---

## Table of Contents

- [What is fingerprinting](#what-is-fingerprinting)
- [Browser Fingerprinting](#browser-fingerprinting)
- [TLS Fingerprinting (JA3/JA4)](#tls-fingerprinting-ja3ja4)
**Deep dives** (dedicated files):
- [Advanced Fingerprinting](fingerprinting-avanzato.md) - HTTP/2, OS, cookieless tracking, tools, configurations

---

## What is fingerprinting

Fingerprinting is a technique that uniquely identifies a browser (and therefore
a user) based on its technical characteristics, **without using cookies,
localStorage or any explicit storage mechanism**.

### Why it is effective

```
Entropy needed to identify a person:
  - World population: 8 billion → 33 bits of entropy
  - Internet users: 5 billion → 32.2 bits
  - Tor users: ~2-4 million → 21-22 bits

A typical browser fingerprint: 50-70 bits of entropy
→ More than enough to UNIQUELY identify
  any person on Earth

The problem: every browser "choice" adds entropy
  - OS: Linux → ~2% of web users → 5.6 bits
  - Language: it-IT → ~2% → 5.6 bits
  - Timezone: CET → ~3% → 5 bits
  - Installed fonts: unique combination → 8-12 bits
  - Canvas: unique rendering → 8-10 bits
  Partial total: already ~30 bits with 5 characteristics
```

### Two approaches to fingerprinting

```
1. Make the fingerprint UNIQUE (the problem):
   Every browser has different characteristics
   → Unique identification possible
   → Persistent tracking without cookies

2. Make the fingerprint UNIFORM (Tor Browser's solution):
   All Tor Browser users have the SAME fingerprint
   → The user "hides in the crowd"
   → The fingerprint identifies "a Tor Browser user" but not WHICH user
```

---

## Browser Fingerprinting

### Main vectors

**1. User-Agent**

```
Normal Firefox (mine):
  Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
  → Reveals: Linux, x86_64, Firefox 128
  → Pool: ~0.1% of web users

Tor Browser:
  Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0
  → Masquerades as Windows even on Linux
  → Pool: all Tor Browser users (millions)
  → Indistinguishable from other TB users

Entropy: 10-12 bits
```

**2. Canvas Fingerprinting**

A site can ask the browser to render an image on a `<canvas>` element.
The result depends on: GPU, driver, OS, font rendering engine, antialiasing.

```javascript
// The site executes:
var canvas = document.createElement('canvas');
var ctx = canvas.getContext('2d');
ctx.textBaseline = "top";
ctx.font = "14px 'Arial'";
ctx.fillStyle = "#f60";
ctx.fillRect(125, 1, 62, 20);
ctx.fillStyle = "#069";
ctx.fillText("Cwm fjordbank", 2, 15);
var hash = canvas.toDataURL().hashCode();
// hash is UNIQUE per GPU+driver+OS+rendering combination

// Two computers with the same GPU but different drivers
// produce DIFFERENT canvas → unique fingerprint
```

```
Tor Browser: randomizes canvas output or prompts for confirmation
  → Each session produces a different hash → no tracking
  → Prompt: "This site wants to extract canvas data. Allow?"

My Firefox: no protection
  → The canvas hash is constant → persistent tracking

Entropy: 8-10 bits
```

**3. WebGL Fingerprinting**

Similar to canvas but uses 3D rendering:

```javascript
var gl = canvas.getContext('webgl');
var debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
var vendor = gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL);
var renderer = gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
// vendor: "Intel Inc."
// renderer: "Intel(R) UHD Graphics 630"
// → Identifies the exact GPU
```

Information revealed:
- Exact GPU model
- Driver version
- Supported WebGL extensions (unique list per GPU)
- Performance characteristics (rendering timing)
- Shader precision format

```
Tor Browser: WebGL disabled or spoofed
My Firefox: fully exposed

Entropy: 6-8 bits
```

**4. Font Fingerprinting**

The site measures the rendering size of text in hundreds of fonts:

```javascript
// The site creates a <span> element with reference text
// Renders it in a fallback font (e.g., monospace)
// Then changes the font to a specific one (e.g., "Courier New")
// If dimensions change → the font is installed
// The LIST of installed fonts is a fingerprint

// Common fonts on Linux (my case):
// DejaVu Sans, Liberation Mono, Cantarell, etc.
// Common fonts on Windows:
// Arial, Calibri, Cambria, Comic Sans, etc.
// → The list is different per OS → unique fingerprint
```

```
Tor Browser: loads only a limited set of bundled fonts
  → All TB users have the same fonts → no fingerprint
My Firefox: all system fonts are visible

Entropy: 8-12 bits
```

**5. Audio Fingerprinting (AudioContext)**

```javascript
var audioCtx = new (window.AudioContext || window.webkitAudioContext)();
var oscillator = audioCtx.createOscillator();
var analyser = audioCtx.createAnalyser();
var gain = audioCtx.createGain();

oscillator.connect(analyser);
analyser.connect(gain);
gain.connect(audioCtx.destination);

// The audio output depends on audio hardware
// The fingerprint is a hash of the processed output
// Different for each hardware/driver combination
```

```
Tor Browser: AudioContext API neutralized
My Firefox: fully exposed

Entropy: 4-6 bits
```

**6. Window dimensions**

```
The browser window size reveals:
- Screen resolution
- Active toolbars
- DPI scaling
- Number of monitors (with window.screen)
- Window position

Tor Browser: "letterboxing" - adds gray borders to round dimensions
  Actual window: 1367 x 843
  Reported to site: 1200 x 800 (multiple of 200 x 100)
  → All users with similar windows have the same value

My Firefox: real dimensions exposed

Entropy: 4-6 bits
```

**7. Navigator properties**

```javascript
navigator.hardwareConcurrency  // Number of logical CPUs
// Mine: 8 → reveals CPU class
// Tor Browser: always 2

navigator.deviceMemory         // RAM in GB (approximate)
// Mine: 16 → reveals computer class
// Tor Browser: not exposed

navigator.maxTouchPoints       // Touchscreen
// Desktop: 0, Tablet: 5-10
// Tor Browser: always 0

navigator.languages            // Preferred languages
// Mine: ["it-IT", "it", "en-US", "en"]
// Tor Browser: ["en-US", "en"]

navigator.platform             // Platform
// Mine: "Linux x86_64"
// Tor Browser: "Win32" (even on Linux!)
```

### Total fingerprint entropy

| Vector | Entropy bits (approx) | Tor Browser | My Firefox |
|--------|----------------------|-------------|------------|
| User-Agent | 10-12 bits | Uniform | **Exposed** |
| Canvas | 8-10 bits | Randomized | **Exposed** |
| WebGL | 6-8 bits | Disabled | **Exposed** |
| Fonts | 8-12 bits | Limited | **Exposed** |
| Screen/Window | 4-6 bits | Letterboxing | **Exposed** |
| Timezone | 3-5 bits | UTC | **Exposed** (CET) |
| Language | 3-4 bits | en-US | **Exposed** (it-IT) |
| AudioContext | 4-6 bits | Neutralized | **Exposed** |
| Plugins | 4-8 bits | None visible | **Exposed** |
| navigator.* | 4-6 bits | Fixed values | **Exposed** |
| **Total** | **~55-80 bits** | **~5-8 bits** (uniform) | **~55-80 bits** (unique) |

With Tor Browser: ~5-8 bits → "you are a Tor Browser user" (millions of people).
With my Firefox: ~55-80 bits → "you are YOU" (probably unique in the world).

---

## TLS Fingerprinting (JA3/JA4)

### How it works

When a browser opens an HTTPS connection, it sends a TLS ClientHello.
This packet contains parameters unique to each browser:

```
TLS ClientHello contains:
- Supported TLS version
- Cipher suites (ordered list of cryptographic algorithms)
- TLS extensions (ordered list)
- Supported groups (elliptic curves)
- Signature algorithms
- ALPN (application protocols: h2, http/1.1)
- Key share groups

Each browser has a UNIQUE ClientHello:

Firefox 128 (Linux):
  TLS 1.3, cipher_suites=[0x1301,0x1302,0x1303,0xc02b,0xc02f,...],
  extensions=[0x0000,0x0017,0x002b,...], groups=[x25519,secp256r1,...]

Chrome 120 (Windows):
  TLS 1.3, cipher_suites=[0x1301,0x1303,0xc02b,...],
  extensions=[0x0000,0x0017,...], groups=[x25519,secp256r1,secp384r1,...]

Tor Browser:
  TLS 1.3, cipher_suites=[identical to Firefox ESR on Windows]
  → Consistent with the declared user-agent
```

### JA3 Hash

```
JA3 = MD5(
    TLSVersion,
    Ciphers (ordered list),
    Extensions (ordered list),
    EllipticCurves,
    EllipticCurveFormats
)

Example:
  JA3 of my Firefox on Kali: e7d705a3286e19ea42f587b344ee6865
  JA3 of Tor Browser: 839bbe3ed07fed922ded5aaf714d6842
  JA3 of Chrome on Windows: b32309a26951912be7dba376398abc3b

→ A server that calculates JA3 can:
  1. Identify the browser type
  2. Verify consistency with the declared User-Agent
  3. Block specific browsers/clients
```

### JA4 (successor to JA3)

```
JA4 is more granular:
- Uses SHA256 (not MD5)
- Includes ALPN, signature algorithms
- Readable format: "t13d1517h2_8daaf6152771_b0da82dd1658"
  t = TLS, 13 = version, d = protocol, 15 = cipher count,
  17 = extension count, h2 = ALPN
- More precise for fingerprinting
```

### Implications for my setup

```
My Firefox on Kali:
  JA3: specific to Firefox on Linux
  → Different from the Tor Browser population (Firefox ESR on Windows)
  → A server/CDN can distinguish me from Tor Browser users

The consistency problem:
  User-Agent: "Linux x86_64" (if not spoofed)
  JA3: Firefox on Linux
  → Consistent, but identifies as "Firefox Linux" not "Tor Browser"

With resistFingerprinting:
  User-Agent: spoofed to "Windows NT 10.0" (partial)
  JA3: remains Firefox Linux (not spoofable at browser level)
  → INCONSISTENCY: User-Agent says Windows, JA3 says Linux
  → More suspicious than without spoofing!
```

There is no simple mitigation for JA3: the TLS fingerprint is determined by
the browser and platform at the compiled code level.

---

> **Continues in**: [Advanced Fingerprinting](fingerprinting-avanzato.md) for HTTP/2,
> OS fingerprinting, cookieless tracking, verification tools and defensive configurations.

---

## See also

- [Advanced Fingerprinting](fingerprinting-avanzato.md) - HTTP/2, OS, tracking, tools, configurations
- [Tor Browser and Applications](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - How Tor Browser mitigates fingerprinting
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Fingerprinting as an OPSEC mistake
- [Traffic Analysis](traffic-analysis.md) - Network traffic fingerprinting
- [System Hardening](hardening-sistema.md) - Firefox configurations in the tor-proxy profile
- [Real-World Scenarios](scenari-reali.md) - Operational cases from a pentester
