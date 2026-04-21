> **Lingua / Language**: [Italiano](../../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) | English

# Multi-Instance Tor and Stream Isolation

This document analyzes how to run multiple Tor instances to separate traffic
from different applications, and how to configure stream isolation to maximize
privacy. It covers both complete separation (multiple instances) and logical
isolation on a single instance (stream isolation flags).

> **See also**: [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md)
> for ControlPort, [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) for the implications
> of guard selection, [Isolation and Compartmentalization](../05-sicurezza-operativa/isolamento-e-compartimentazione.md)
> for system-level isolation, [torrc Complete Guide](../02-installazione-e-configurazione/torrc-guida-completa.md)
> for SocksPort flags.

---

## Table of Contents

- [Why multiple instances - threat model](#why-multiple-instances--threat-model)
- [Configuration with systemd templates](#configuration-with-systemd-templates)
- [Multi-instance architectures for real-world scenarios](#multi-instance-architectures-for-real-world-scenarios)
- [Stream isolation on a single instance](#stream-isolation-on-a-single-instance)
- [Isolation flags - deep dive](#isolation-flags--deep-dive)
**Deep dives** (dedicated files):
- [Advanced Stream Isolation](stream-isolation-avanzato.md) - Tor Browser, SessionGroup, curl/Python, operational management

---

## Why multiple instances - threat model

### The problem: stream correlation

A single Tor process shares circuits among all connected applications.
This creates a correlation risk:

```
Scenario with a single instance:
[Firefox] -->  SocksPort 9050 -->  Circuit A -->  Exit Node X
[curl]    -->  SocksPort 9050 -->  Circuit A -->  Exit Node X
[script]  -->  SocksPort 9050 -->  Circuit A -->  Exit Node X

Exit Node X sees:
  - Browser HTTP traffic (Facebook, Gmail)
  - curl query to api.ipify.org
  - Automated script traffic
  -> Can correlate EVERYTHING to the same user
```

### Concrete deanonymization example

1. You browse an anonymous forum via Tor Browser
2. Simultaneously, a curl script checks your email via Tor
3. Both use the same exit node (same Tor circuit)
4. The exit node (if malicious) sees:
   - `POST anonymous-forum.onion/reply` (your anonymous post)
   - `GET mail.provider.com/inbox?user=yourname@email.com` (your real identity)
5. **Correlation**: your anonymous post is now linked to your email

### With separate instances

```
[Firefox]  -->  Instance 1 (SocksPort 9050) -->  Circuit A -->  Exit X
[curl]     -->  Instance 2 (SocksPort 9060) -->  Circuit B -->  Exit Y
[script]   -->  Instance 3 (SocksPort 9070) -->  Circuit C -->  Exit Z

Exit X sees only browser traffic
Exit Y sees only curl queries
Exit Z sees only script traffic
-> No correlation possible between activities
```

---

## Configuration with systemd templates

### The correct way on Debian/Kali

Debian (and Kali) natively supports multiple Tor instances through the
systemd template system `tor@.service`:

```bash
# Create a new instance
sudo tor-instance-create cli

# Automatically created structure:
/etc/tor/instances/cli/torrc       <- configuration
/var/lib/tor-instances/cli/        <- data directory
# User: _tor-cli (created automatically)
# Group: _tor-cli
```

### Instance configuration

#### Instance 1: Browser navigation

```ini
# /etc/tor/instances/browser/torrc
SocksPort 9050 IsolateDestAddr IsolateDestPort
DNSPort 5353
ControlPort 9051
CookieAuthentication 1
DataDirectory /var/lib/tor-instances/browser
ClientUseIPv6 0
```

#### Instance 2: CLI and scripts

```ini
# /etc/tor/instances/cli/torrc
SocksPort 9060 IsolateSOCKSAuth
DNSPort 5363
ControlPort 9061
CookieAuthentication 1
DataDirectory /var/lib/tor-instances/cli
ClientUseIPv6 0
```

#### Instance 3: Secure communication

```ini
# /etc/tor/instances/secure/torrc
SocksPort 9070 IsolateDestAddr IsolateDestPort IsolateSOCKSAuth
DNSPort 5373
ControlPort 9071
CookieAuthentication 1
DataDirectory /var/lib/tor-instances/secure
ClientUseIPv6 0
```

### Management with systemctl

```bash
# Start/stop instances
sudo systemctl start tor@browser.service
sudo systemctl start tor@cli.service
sudo systemctl start tor@secure.service

# Status
sudo systemctl status tor@browser.service

# Enable auto-start
sudo systemctl enable tor@browser.service

# Restart a single instance (without touching the others)
sudo systemctl restart tor@cli.service

# Logs for a specific instance
sudo journalctl -u tor@cli.service -f
```

### Port verification

```bash
# Verify all instances are listening
ss -tlnp | grep tor
# LISTEN 127.0.0.1:9050  ... tor (browser)
# LISTEN 127.0.0.1:9060  ... tor (cli)
# LISTEN 127.0.0.1:9070  ... tor (secure)
```

### Usage

```bash
# Browser uses instance 1
proxychains firefox -no-remote -P tor-proxy & disown
# (proxychains4.conf points to 9050)

# CLI uses instance 2
curl --socks5-hostname 127.0.0.1:9060 https://api.ipify.org

# Secure communication uses instance 3
torsocks -P 9070 thunderbird &
```

---

## Multi-instance architectures for real-world scenarios

### Scenario: OSINT + Browsing + Communication + Development

```
+-----------------------------------------------------+
|                  Kali Linux Host                     |
|                                                      |
|  +----------+  +----------+  +----------+  +-----+  |
|  | Firefox  |  | curl/    |  | Thunder- |  | Dev |  |
|  | tor-proxy|  | scripts  |  | bird     |  | test|  |
|  +----+-----+  +----+-----+  +----+-----+  +--+--+  |
|       |              |              |           |     |
|  SocksPort      SocksPort      SocksPort   SocksPort |
|    9050           9060           9070        9080     |
|       |              |              |           |     |
|  +----+-----+  +----+-----+  +----+-----+  +--+--+  |
|  | Tor #1   |  | Tor #2   |  | Tor #3   |  |Tor#4|  |
|  | browser  |  | cli      |  | secure   |  | dev |  |
|  | Guard A  |  | Guard B  |  | Guard C  |  |Grd D|  |
|  +----------+  +----------+  +----------+  +-----+  |
|                                                      |
|  Each instance: different guard, independent circuits |
|  No correlation possible between instances            |
+-----------------------------------------------------+
```

### Port table

| Instance | SocksPort | DNSPort | ControlPort | Use |
|----------|-----------|---------|-------------|-----|
| browser | 9050 | 5353 | 9051 | Firefox, web browsing |
| cli | 9060 | 5363 | 9061 | curl, wget, scripts |
| secure | 9070 | 5373 | 9071 | Email, chat, communication |
| dev | 9080 | 5383 | 9081 | Testing, development |

---

## Stream isolation on a single instance

If you do not want to manage multiple instances, you can achieve partial
isolation with different SOCKS ports on the same instance:

```ini
# torrc - single instance, per-port isolation
SocksPort 9050 IsolateDestAddr IsolateDestPort           # browser
SocksPort 9052 IsolateSOCKSAuth                           # CLI with auth
SocksPort 9053 SessionGroup=1                             # script group 1
SocksPort 9054 SessionGroup=2                             # script group 2
```

### How it works internally

Tor associates each stream with a circuit based on an **isolation key**.
The key is constructed from:

```
isolation_key = (
    SocksPort,
    SessionGroup,
    IsolateDestAddr ? dest_ip : *,
    IsolateDestPort ? dest_port : *,
    IsolateSOCKSAuth ? socks_username : *,
    IsolateClientAddr ? client_ip : *,
    IsolateClientProtocol ? protocol : *
)

Streams with the same isolation_key -> same circuit
Streams with a different key -> different circuit
```

---

## Isolation flags - deep dive

### Complete table

| Flag | Key parameter | Effect |
|------|--------------|--------|
| `IsolateDestAddr` | Destination IP | google.com and github.com -> different circuits |
| `IsolateDestPort` | Destination port | :443 and :80 -> different circuits |
| `IsolateSOCKSAuth` | SOCKS5 credentials | Different users -> different circuits |
| `IsolateClientAddr` | Source IP | Clients from different IPs -> different circuits |
| `IsolateClientProtocol` | SOCKS4/5/HTTP | Different protocols -> different circuits |
| `SessionGroup=N` | Manual group | Only streams in the same group share circuits |

### Isolation matrix

Common combinations and their effect:

| Configuration | google.com:443 + google.com:80 | google.com:443 + github.com:443 |
|--------------|-------------------------------|-------------------------------|
| No flags | Same circuit | Same circuit |
| `IsolateDestAddr` | Same circuit | **Different** |
| `IsolateDestPort` | **Different** | Same circuit |
| `IsolateDestAddr IsolateDestPort` | **Different** | **Different** |
| `IsolateSOCKSAuth` | Depends on auth | Depends on auth |

### Observing isolation via ControlPort

```python
from stem.control import Controller

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    
    # Show all streams with associated circuits
    for stream in ctrl.get_info("stream-status").split("\n"):
        if stream.strip():
            # Format: StreamID Status CircuitID Target
            parts = stream.split()
            print(f"Stream {parts[0]}: circuit={parts[2]} target={parts[3]}")
```

Example output with `IsolateDestAddr`:
```
Stream 1: circuit=5  target=google.com:443
Stream 2: circuit=5  target=google.com:80     <- same circuit (same dest IP)
Stream 3: circuit=7  target=github.com:443    <- different circuit (different IP)
```

---

## How Tor Browser implements isolation

### SOCKS5 auth per domain

Tor Browser is the gold standard for isolation. It uses `IsolateSOCKSAuth` with
SOCKS5 credentials generated per-domain:


---

> **Continues in**: [Advanced Stream Isolation](stream-isolation-avanzato.md) for
> how Tor Browser implements isolation, SessionGroup, per-application isolation,
> and operational management.

---

## See also

- [Advanced Stream Isolation](stream-isolation-avanzato.md) - Tor Browser, SessionGroup, curl/Python, operational management
- [torrc - Complete Guide](../02-installazione-e-configurazione/torrc-guida-completa.md) - SocksPort directives and isolation
- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - NEWNYM per instance
- [VPN and Tor Hybrid](vpn-e-tor-ibrido.md) - Selective per-application routing
- [Real-World Scenarios](scenari-reali.md) - Operational cases from a pentester
