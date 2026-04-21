> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/opsec-casi-reali-e-difese.md) | English

# OPSEC - Real-World Cases, Stylometry and Defenses

Real deanonymization cases (Silk Road, AlphaBay, LulzSec, Freedom Hosting),
stylometric analysis, cryptocurrency tracing, complete operational checklist
and threat model for self-assessment.

> **Extracted from**: [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) for
> OPSEC mistakes and metadata correlation.

---

### Ross Ulbricht (Silk Road, 2013)

**Who he was**: creator and operator of Silk Road, the first major darknet
marketplace, operational from 2011 to 2013.

**How he was found**: NOT through a vulnerability in Tor, but through
a chain of OPSEC mistakes:

```
Mistake 1 (January 2011):
  Ulbricht had posted on Shroomery.org (with his real name)
  asking for information about how to create a .onion site

Mistake 2 (March 2011):
  Had used the nickname "altoid" both on Silk Road and on
  Stack Overflow, where he was registered as "Ross Ulbricht"
  with email rossulbricht@gmail.com

Mistake 3 (2012):
  Had ordered fake documents (driver's licenses) that were
  intercepted by customs → linked to his real address

Mistake 4 (2013):
  The Silk Road server leaked the real IP through a
  misconfiguration in the login interface (CAPTCHA loaded
  from direct IP, not via .onion)

Mistake 5 (arrest):
  He was arrested in a public library while logged in
  as the Silk Road admin on his laptop
```

**Lesson learned**: Tor was intact. Every mistake was human. The combination
of mistakes over a 2+ year span enabled identification.

### Alexandre Cazes (AlphaBay, 2017)

**Who he was**: founder and admin of AlphaBay, the largest darknet marketplace
succeeding Silk Road.

**How he was found**:

```
Mistake 1:
  The recovery email for the AlphaBay forum was "pimp_alex_91@hotmail.com"
  → "Alex" + "91" (birth year)
  → Personal email linked to his real name

Mistake 2:
  The AlphaBay welcome message contained "Welcome to AlphaBay"
  → The same header had been used on a personal website of Cazes
  → Same PHP/MySQL configurations

Mistake 3:
  Cazes lived in Thailand with a lavish lifestyle
  (Lamborghini, villas) without a known job
  → Authorities correlated the financial profile

Mistake 4:
  The server had a configuration that leaked the IP in
  case of web server error (Apache default page)
```

**Lesson learned**: a single personal email address used by mistake
started the entire investigative chain.

### Hector Monsegur (LulzSec/Anonymous, 2012)

**How he was found**: he connected to an IRC server **once without Tor**
(he had forgotten to activate the VPN). A single connection revealed his
real IP.

**Details**:
```
Monsegur used Tor for all communications with LulzSec
But one evening, tired, he connected to the IRC server without Tor
The server logged his real IP: a New York address
The FBI correlated the IP with his apartment
→ A single connection = complete identification
```

**Lesson learned**: a single connection without Tor is enough to be identified.
OPSEC must be maintained at 100%, not 99.99%.

### Freedom Hosting (2013)

**How it was found**: the FBI exploited a browser vulnerability
(Firefox ESR 17) to inject JavaScript that sent the real IP and MAC
address to an FBI server.

**Technical details of the exploit**:
```javascript
// The exploit was injected into pages hosted on Freedom Hosting
// Exploited CVE-2013-1690 (Firefox ESR 17)
// The payload:
// 1. Bypassed the browser sandbox
// 2. Executed native code
// 3. Retrieved the real IP and MAC address
// 4. Sent the data to an FBI server (outside Tor)
// 5. Only worked on Windows (the payload was a PE)
```

**Lesson learned**: the browser is the primary attack surface. Keeping
Tor Browser updated is critical. On Tails/Whonix, even a browser exploit
does not reveal the IP (traffic is forced through Tor at the firewall level).

### Eldo Kim (Harvard bomb threat, 2013)

**How he was found**:

```
Kim used Tor to send bomb threat emails to Harvard
to avoid an exam.

Mistake: he used Tor from Harvard's WiFi network
→ Harvard had logs of who was connected to Tor at that time
→ Only 1-2 people on the Harvard network were using Tor at 08:30
→ Kim was the only student connected to Tor at that time

The FBI interrogated him and he immediately confessed.
```

**Lesson learned**: if you are the only Tor user on your local network, the simple
fact of using Tor makes you a suspect. obfs4 bridges hide Tor usage.

### Jeremy Hammond (Anonymous/Stratfor, 2012)

**How he was found**: betrayal by an informant (Sabu/Monsegur,
who was cooperating with the FBI) and correlation of chat logs.

**Lesson learned**: trust in people is an attack vector.
No technology protects against an infiltrator.

---

## Behavioral patterns and stylometry

### What is stylometry

Stylometry analyzes writing style to identify the author.
Every person has a unique "linguistic fingerprint":

```
Analyzed elements:
- Average sentence length
- Punctuation distribution (use of - vs - vs ... )
- Common words used (e.g., "however" vs "nevertheless" vs "though")
- Recurring grammatical errors
- Paragraph structure
- Use of emoticons/emoji
- Specific technical vocabulary
- Formatting (markdown, HTML, spaces)
```

### Stylometry accuracy

```
- With 5,000 words of sample: ~80% accuracy on 50 authors
- With 10,000 words: ~90% accuracy
- With cross-language analysis (same author, different languages): ~60%
- Machine learning (BERT, GPT): >95% on sufficient samples
```

### Mitigation

```
1. Write differently for each identity
   → Difficult to maintain over time
   
2. Use an automatic translator as a "style filter"
   → Write in Italian → translate to English → re-translate to Italian
   → The style gets "flattened"
   
3. Use an LLM to rewrite
   → "Rewrite this text in a neutral and generic style"
   → Removes personal stylistic characteristics
   
4. Use only English for anonymous activities
   → Larger pool (most widely used language online)
   → Less identifiable compared to Italian
```

### Temporal patterns as fingerprint

```
Analysis of anonymous forum posts:
- The user posts between 08:00 and 23:00 CET
- Never on Sundays (likely a regular worker)
- Activity peaks at 13:00 and 21:00
- Holidays in August and December (Italian pattern)
→ Timezone: CET
→ Profession: regular job with lunch break
→ Nationality: probably Italian
```

---

## Cryptocurrency and financial tracing

### Bitcoin is not anonymous

```
Bitcoin is PSEUDONYMOUS, not anonymous:
- Every transaction is public on the blockchain
- Addresses are linkable through flow analysis
- Exchanges require KYC (Know Your Customer)
- A single transaction from a KYC exchange to an
  "anonymous" address compromises the entire address chain

Blockchain analysis tools:
- Chainalysis (used by FBI, IRS, Europol)
- Elliptic
- CipherTrace
→ Can correlate addresses, mixers, and movements
```

### Common cryptocurrency mistakes

```
Mistake 1: buying BTC on an exchange with your name,
          then using them for anonymous transactions
          → 100% traceable

Mistake 2: using the same wallet for anonymous
          and non-anonymous transactions
          → Direct link

Mistake 3: not using Tor to access the wallet
          → The exchange/node sees your real IP

Mistake 4: specific amounts (e.g., 0.12345678 BTC)
          → Traceable as a unique amount
```

### Partial mitigation

```
- Monero (XMR): privacy by default (ring signatures, stealth addresses)
- CoinJoin/Wasabi Wallet: Bitcoin transaction mixing
- Never reuse addresses
- Never link anonymous wallets to KYC exchanges
- Access wallets only via Tor
- Do not use recognizable specific amounts
```

---

## Complete OPSEC checklist

### Before starting an anonymous session

- [ ] Is Tor active and bootstrapped to 100%?
- [ ] Is ProxyChains configured with `proxy_dns`?
- [ ] Is WebRTC disabled in the browser (`media.peerconnection.enabled = false`)?
- [ ] Is IPv6 disabled (`net.ipv6.conf.all.disable_ipv6=1`)?
- [ ] Is the browser profile dedicated to Tor (not shared with normal browsing)?
- [ ] `privacy.resistFingerprinting = true` in the Tor profile?
- [ ] DNS prefetch disabled (`network.dns.disablePrefetch = true`)?
- [ ] No personal account logged in the Tor browser?
- [ ] No other browser/app using the same network for non-anonymous activities?
- [ ] obfs4 bridge active if needed (hide Tor usage from ISP)?

### During use

- [ ] Do NOT log in with personal accounts
- [ ] Do NOT open downloaded files with network applications
- [ ] Do NOT use the same site via Tor and non-Tor simultaneously
- [ ] Do NOT reveal personal information (name, city, job, etc.)
- [ ] Do NOT use the same writing style as your real identity
- [ ] Do NOT upload files with uncleaned metadata
- [ ] Do NOT use Bitcoin from KYC exchanges for anonymous transactions
- [ ] Do NOT post at predictable times that reveal the timezone
- [ ] Periodically verify the IP with `proxychains curl https://api.ipify.org`
- [ ] Use NEWNYM between different/uncorrelated activities

### After use

- [ ] Close all Tor applications
- [ ] Clear browser history (or use private browsing)
- [ ] NEWNYM to invalidate circuits
- [ ] If high risk: shut down the computer (RAM contains traces)
- [ ] If Tails: reboot (RAM is overwritten)

### Mistakes to NEVER make

| Mistake | Consequence | Reversible? |
|---------|-------------|------------|
| Login with personal account | Identity revealed to the site | NO - logs exist |
| One connection without Tor | Real IP logged | NO |
| Files with personal metadata | Name/location exposed | NO - if saved by others |
| Same crypto wallet anonymous/real | Financial link | NO - blockchain is permanent |
| Post with personal info | Correlation possible | PARTIAL - if deleted quickly |
| DNS leak | Visited domains known to ISP | NO - ISP logs by law |

---

## Threat model and self-assessment

### Define your adversary

The necessary OPSEC depends on your threat model:

| Adversary | Capability | Required OPSEC |
|-----------|-----------|----------------|
| Web trackers (Google, Facebook) | Cookies, fingerprint, pixels | Tor Browser, FPI |
| ISP (in my case: Comeser) | Sees destinations, timing, volume | Tor + obfs4 bridge |
| Local network admin | Like ISP + DHCP, ARP | Tor + bridge + MAC spoofing |
| National law enforcement | Court orders to ISP, exchanges | Tor + rigorous OPSEC |
| Intelligence (NSA, GCHQ) | Global surveillance, correlation | Tails/Whonix + perfect OPSEC |
| Adversary with physical access | Disk and RAM forensics | Full disk encryption + Tails |

### My threat model

```
Adversary: ISP + web trackers
Objective: privacy from commercial profiling, security testing
Risk: low (legal activities, no active adversary)

Adequate OPSEC:
✓ Tor + proxychains (hides destinations from ISP)
✓ obfs4 bridge (hides Tor usage from ISP)
✓ Dedicated Firefox profile (separates Tor browsing from normal)
✓ proxy_dns + DNSPort (prevents DNS leak)
✓ WebRTC disabled (prevents IP leak)

NOT necessary for my threat model:
✗ Tails/Whonix (my adversary does not do forensics)
✗ Extreme compartmentalization (I have no anonymous identities to protect)
✗ MAC spoofing (I do not connect to unknown networks)
✗ Stylometry defense (I do not write anonymous posts)
```

---

## In my experience

I am aware that my setup (Firefox+proxychains on Kali) is not fingerprinting-proof.
I use it for:
- ISP privacy (hiding the sites I visit)
- Security testing (verifying behavior from different IPs)
- Studying the Tor network

I do NOT use it for:
- Activities requiring absolute anonymity
- Logging in to personal accounts via Tor
- Illegal activities

For scenarios requiring real anonymity, I would use Tor Browser on Tails or Whonix.

The most common OPSEC mistake I have seen (not that I committed, fortunately):
forgetting that `curl` without `--socks5-hostname` leaks DNS. It is an easy,
silent, and devastating mistake. That is why I created aliases:

```bash
# In my .zshrc:
alias curltor='curl --socks5-hostname 127.0.0.1:9050'
alias pcurl='proxychains curl'
```

---

## See also

- [DNS Leak](dns-leak.md) - Complete DNS leak prevention
- [Fingerprinting](fingerprinting.md) - Browser, network, OS fingerprinting vectors
- [Traffic Analysis](traffic-analysis.md) - End-to-end correlation, website fingerprinting
- [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) - Whonix, Tails, Qubes
- [Forensic Analysis and Artifacts](analisi-forense-e-artefatti.md) - What you leave on disk and in RAM
- [Known Attacks](../07-limitazioni-e-attacchi/attacchi-noti.md) - CMU/FBI, Freedom Hosting, exploits
- [Ethics and Responsibility](../08-aspetti-legali-ed-etici/etica-e-responsabilita.md) - Responsible use of Tor
