> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/opsec-e-errori-comuni.md) | English

# OPSEC and Common Mistakes - What Can Deanonymize You

This document catalogs the most common OPSEC (Operational Security) mistakes
when using Tor, deanonymization techniques based on human behavior,
real-world cases where users were identified despite Tor, and a complete
operational checklist.

In my experience, most deanonymizations do not happen due to technical
vulnerabilities in Tor, but due to human errors. Tor is a tool: its
effectiveness depends on how you use it.

---

## Table of Contents

- [The fundamental OPSEC principle](#the-fundamental-opsec-principle)
- [OPSEC mistakes that nullify Tor's anonymity](#opsec-mistakes-that-nullify-tors-anonymity)
- [Advanced mistakes: metadata and correlation](#advanced-mistakes-metadata-and-correlation)
**Deep dives** (dedicated files):
- [OPSEC - Real-World Cases, Stylometry and Defenses](opsec-casi-reali-e-difese.md) - Real cases, stylometry, crypto, checklist, threat model

---

## The fundamental OPSEC principle

OPSEC is based on a simple concept: **a single mistake can nullify
months of correct behavior**. Anonymity is not a binary state but
a chain: it only takes one broken link to compromise everything.

```
OPSEC = min(security of each individual action)

100 anonymous connections + 1 connection with a leak = COMPROMISED
1 year of anonymity + 1 login with real account = COMPROMISED
Perfect setup + 1 post with personal information = COMPROMISED
```

The adversary does not need to break Tor. They only need to find your mistake.

### The 5 golden rules

1. **Never mix anonymous identities with real identities**
2. **Never rely on a single protection** (defense in depth)
3. **Behavior is a fingerprint** just as much as technology
4. **A past mistake can surface in the future** (logs exist)
5. **The adversary has more time and resources than you**

---

## OPSEC mistakes that nullify Tor's anonymity

### 1. Logging in with personal accounts

**The mistake**: you browse via Tor, then log in to Gmail, Facebook, or Amazon with
your personal account. Now the site knows who you are, even if your IP is the
exit node's.

**Why it is serious**: Tor's anonymity protects the IP. If you tell the site who you are
(login), the IP is irrelevant. Additionally, the site can correlate your anonymous
session with past/future sessions via cookies, browser fingerprint, or timing.

**Cross-session correlation**:
```
Session 1 (anonymous): visit forum-x.com, read specific threads
Session 2 (same time): login to Gmail from your PC
→ Google knows you use Tor and knows your temporal pattern
→ An adversary with access to both logs can correlate
```

**Rule**: NEVER log in to personal accounts on Tor. If you must access
a service, create an account dedicated exclusively for Tor use.

### 2. Using Tor and non-Tor simultaneously

**The mistake**: you have two browser windows open - one via Tor, one normal.
You visit the same site in both. The site correlates the sessions via cookies,
fingerprint, or timing.

**The specific scenario**:
```
Window 1 (Tor): visit forum.example.com from exit IP 185.220.101.x
Window 2 (normal): visit forum.example.com from your real IP 151.x.x.x
Timing: both connections occur at 14:32
→ The server sees two simultaneous sessions with the same browser fingerprint
→ Correlation: the user with IP 185.220.101.x is 151.x.x.x
```

**Rule**: if you use Tor for an activity, do NOT perform the same activity without Tor
simultaneously. Ideally, use separate computers or VMs.

### 3. Downloading and opening files without precautions

**The mistake**: you download a PDF via Tor, open it with the system's PDF reader.
The PDF reader makes HTTP requests (for fonts, external images, tracking pixels)
that go out WITHOUT passing through Tor → revealing your real IP.

**Dangerous files**:
```
PDF:   Can contain JavaScript, external links, tracking pixels
DOCX:  Can load remote templates, images from URLs
XLSX:  Can contain links to external data
HTML:  Obviously can load any external resource
SVG:   Can contain JavaScript and external references
ODT:   Can load remote resources
Torrent: DHT/PEX reveal the real IP (see mistake #8)
```

**Rule**: do not open files downloaded via Tor in applications that access the network.
Open them in a VM disconnected from the network, or convert them to a safe
format (e.g., PDF → image) before viewing.

### 4. Information in User-Agent and metadata

**The mistake**: your browser reveals OS (Kali Linux), architecture (x86_64),
exact version (Firefox 128). This information narrows the pool of
possible users.

**What my Firefox reveals**:
```
User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
→ OS: Linux (minority: ~2% of web users)
→ Arch: x86_64
→ Browser: Firefox 128 on Linux
→ Estimated pool: ~0.1% of web users

Tor Browser User-Agent: Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0
→ Pool: all Tor Browser users (millions)
→ Indistinguishable from other TB users
```

**Rule**: use Tor Browser (unified user-agent). Or at least enable
`privacy.resistFingerprinting` in Firefox for partial spoofing.

### 5. DNS leak

**The mistake**: DNS queries go out in cleartext to the ISP, revealing which
sites you are visiting.

**Rule**: `proxy_dns` in proxychains, `--socks5-hostname` with curl,
`DNSPort` in the torrc. See the dedicated DNS leak document.

### 6. WebRTC leak

**The mistake**: WebRTC in the browser reveals the real local and public IP,
even through a SOCKS5 proxy.

**How the leak works**:
```javascript
// JavaScript in the browser:
var pc = new RTCPeerConnection({iceServers: []});
pc.createDataChannel('');
pc.createOffer().then(offer => pc.setLocalDescription(offer));
pc.onicecandidate = event => {
    // event.candidate contains your real IP!
    // E.g.: "candidate:0 1 UDP 2122252543 192.168.1.100 44323 typ host"
    // The IP 192.168.1.100 is your local IP
};
```

**Rule**: `media.peerconnection.enabled = false` in about:config.
In Tor Browser it is already disabled.

### 7. Browser timezone and language

**The mistake**: the browser reveals timezone=Europe/Rome and language=it-IT.
With 33 bits of entropy you identify a person. Timezone + language
add ~8 bits, significantly narrowing the pool.

**Calculation**:
```
Estimated Tor users: ~2 million
Timezone Europe/Rome: ~3% → 60,000
Language it-IT: ~2% → 1,200
+ Kali Linux: ~0.5% → 6
→ With just timezone + language + OS, the pool is ~6 people
```

**Rule**: `privacy.resistFingerprinting = true` (forces UTC and en-US).

### 8. Torrenting via Tor

**The mistake**: you use BitTorrent via Tor. The BitTorrent client reveals your real IP
through DHT (Distributed Hash Table) and PEX (Peer Exchange), which
do not go through the proxy.

**The technical problem**:
```
BitTorrent tracker: communicates via TCP → can go through Tor
DHT: communicates via UDP → CANNOT go through Tor → real IP leak
PEX: exchanges IPs with other peers → contains your real IP
uTP: uses UDP → CANNOT go through Tor

Even disabling DHT/PEX/uTP, the client might:
- Send your real IP in the "ip" field of the tracker announce
- Make DNS requests for the tracker outside of Tor
```

**Rule**: NEVER use BitTorrent via Tor. Besides the leak, it overloads
the Tor network (which is designed for low-latency traffic, not file sharing).

### 9. Running untrusted JavaScript

**The mistake**: JavaScript from a malicious site can exploit browser
vulnerabilities to obtain your real IP.

**JavaScript attack vectors**:
```
WebRTC → reveals IP (if not disabled)
DNS rebinding → connection to localhost
Browser exploit → arbitrary code execution
Timing side-channel → deanonymization via timing
Canvas/WebGL → unique fingerprinting
Audio API → hardware fingerprinting
```

**Rule**: Tor Browser has a "Security Level" that limits JavaScript:
- **Standard**: JavaScript enabled (less secure, more usable)
- **Safer**: JavaScript disabled on non-HTTPS sites, no media
- **Safest**: JavaScript disabled everywhere, static content only

### 10. Unique behavioral patterns

**The mistake**: you always visit the same 5 sites, at the same time, with the
same navigation pattern. Even without a technical fingerprint, your
*behavior* is a fingerprint.

**Example**:
```
Pattern observed on Tor exit (or by the site):
- Every day at 08:30: news-site-a.com
- Every day at 09:00: forum-b.com, specific threads
- Every Monday at 14:00: service-c.com
- Language: Italian, timezone hints in posts
→ Even changing IP with NEWNYM, the pattern is identifiable
→ If the same pattern appears without Tor → correlation
```

**Rule**: vary patterns, do not use Tor for predictable routines.
Use NEWNYM between different sessions. Do not reveal timezone in posts.

---

## Advanced mistakes: metadata and correlation

### Metadata in documents

Files you upload contain invisible metadata:

```bash
# Metadata in a Word/LibreOffice document:
exiftool documento.docx
# Author: Nick Arcari
# Creator: LibreOffice 7.5
# Create Date: 2024-03-15 14:23:42+01:00  ← timezone!
# Producer: Kali Linux

# Metadata in an image:
exiftool foto.jpg
# GPS Latitude: 44.801485    ← exact location!
# GPS Longitude: 10.328946   ← Parma!
# Camera Model: iPhone 15 Pro
# Date/Time: 2024-03-15 09:45:23
```

**Rule**: clean ALL metadata before uploading files:
```bash
# Remove metadata from images
exiftool -all= foto.jpg

# Remove metadata from PDF
exiftool -all= documento.pdf

# For Office documents: save as PDF, then clean the PDF
# Or use mat2 (Metadata Anonymization Toolkit 2):
mat2 documento.docx
```

### Temporal correlation between sessions

```
The adversary observes:
1. Tor connection starts at 08:30 (visible to the ISP)
2. Anonymous post on forum at 08:32
3. Tor connection ends at 09:15
4. This pattern repeats every day

The adversary knows:
- The user is in the CET timezone (+01:00)
- The user is active 08:30-09:15 every day
- The ISP records that 151.x.x.x starts Tor at 08:30 every day
→ Correlation: the anonymous user is 151.x.x.x
```

### Correlation via response size

```
An ISP observing Tor traffic can see:
- Total volume of data downloaded in a session
- Burst patterns (e.g., page load = rapid burst)

If the ISP has access to the destination server logs:
- The server records response size for each request
- Correlation: the Tor session with volume X corresponds to request Y
```

### Compartmentalization failure

```
Identity A (anonymous): uses Tor, posts on forum X
Identity B (real): uses email, social media

MISTAKE: uses the same password for both identities
MISTAKE: uses the same writing style
MISTAKE: mentions the same personal information
MISTAKE: uses the same email provider (even with a different account)
MISTAKE: accesses both from the same WiFi network
```

---

---

> **Continues in**: [OPSEC - Real-World Cases, Stylometry and Defenses](opsec-casi-reali-e-difese.md)
> for deanonymization cases (Silk Road, AlphaBay), stylometry, cryptocurrency
> and operational checklist.

---

## See also

- [OPSEC - Real-World Cases, Stylometry and Defenses](opsec-casi-reali-e-difese.md) - Real cases, stylometry, crypto, checklist
- [DNS Leak](dns-leak.md) - Complete DNS leak prevention
- [Fingerprinting](fingerprinting.md) - Browser, network, OS fingerprinting vectors
- [Traffic Analysis](traffic-analysis.md) - End-to-end correlation, website fingerprinting
- [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) - Whonix, Tails, Qubes
- [Forensic Analysis and Artifacts](analisi-forense-e-artefatti.md) - What you leave on disk and in RAM
- [Real-World Scenarios](scenari-reali.md) - Operational cases from a pentester
