> **Lingua / Language**: [Italiano](../../06-configurazioni-avanzate/stream-isolation-avanzato.md) | English

# Advanced Stream Isolation - Tor Browser, SessionGroup and Operational Management

How Tor Browser implements per-domain SOCKS5 isolation, SessionGroup for
manual grouping, isolation via curl/Python/Firefox Container Tabs,
multi-instance operational management, and trade-offs.

> **Extracted from**: [Multi-Instance Tor and Stream Isolation](multi-istanza-e-stream-isolation.md)
> for the threat model, systemd templates, and isolation flags.

---

  SOCKS5 CONNECT google.com:443
  Auth: username="google.com" password="<random_nonce_1>"
  -> Circuit A

Tab 2 (github.com):
  SOCKS5 CONNECT github.com:443
  Auth: username="github.com" password="<random_nonce_2>"
  -> Circuit B (different from A, because different auth)

Tab 3 (google.com again):
  SOCKS5 CONNECT google.com:443
  Auth: username="google.com" password="<random_nonce_1>"  <- same!
  -> Circuit A (same, because same auth)
```

### First-Party Isolation (FPI)

Tor Browser also implements FPI at the Firefox level:
- Cookies: isolated per first-party domain
- Cache: isolated per domain
- SessionStorage: isolated per domain
- HSTS: isolated per domain

### The Torbutton code

The Torbutton component of Tor Browser generates the credentials:

```javascript
// Simplified logic
function getProxyCredentials(url) {
    let domain = extractFirstPartyDomain(url);
    let nonce = getOrCreateNonce(domain);
    return { username: domain, password: nonce };
}
```

---

## SessionGroup - deep dive

### How it works

`SessionGroup` is a manual stream grouping mechanism:

```ini
SocksPort 9050 SessionGroup=0    # Group 0: browser
SocksPort 9052 SessionGroup=1    # Group 1: OSINT scripts
SocksPort 9053 SessionGroup=1    # Group 1: same group -> share circuits
SocksPort 9054 SessionGroup=2    # Group 2: communication
```

### Rules

- Streams in the **same SessionGroup** and **same port** can share circuits
- Streams in **different SessionGroups** NEVER share circuits
- `SessionGroup` combines with other isolation flags
- Each port without an explicit `SessionGroup` has an implicit unique group

### When to use it

- **Group related activities**: if two scripts need to appear as the same
  "user" (same exit IP), put them in the same SessionGroup
- **Separate unrelated activities**: activities that must not be correlated
  go in different SessionGroups

---

## Stream isolation via application

### curl with SOCKS5 auth

```bash
# Each domain with different credentials -> different circuits
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "google.com:session1" \
     https://www.google.com

curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "github.com:session2" \
     https://github.com

# Verification: different IPs
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "check1:test" \
     https://api.ipify.org
# -> 185.220.100.240

curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "check2:test" \
     https://api.ipify.org
# -> 109.70.100.13 (different!)
```

### Python requests with isolation

```python
import requests

def tor_session(username="default", password="default"):
    """Create a Tor session with SOCKS auth isolation."""
    session = requests.Session()
    session.proxies = {
        'http': f'socks5h://{username}:{password}@127.0.0.1:9050',
        'https': f'socks5h://{username}:{password}@127.0.0.1:9050',
    }
    return session

# Session 1: research
s1 = tor_session("research", "task1")
ip1 = s1.get("https://api.ipify.org").text

# Session 2: communication
s2 = tor_session("comm", "task2")
ip2 = s2.get("https://api.ipify.org").text

print(f"Research IP: {ip1}")    # -> Exit IP A
print(f"Communication IP: {ip2}")  # -> Exit IP B (different)
```

### Firefox Container Tabs

With the tor-proxy profile and the Multi-Account Containers extension:
- Each container can have different proxy credentials
- Result: per-container isolation without multiple instances

---

## Multi-instance operational management

### Monitoring

```bash
# Status of all instances
for inst in browser cli secure; do
    STATUS=$(systemctl is-active tor@${inst}.service 2>/dev/null)
    echo "tor@${inst}: $STATUS"
done

# Nyx for a specific instance
nyx -i 127.0.0.1:9051    # browser
nyx -i 127.0.0.1:9061    # cli
nyx -i 127.0.0.1:9071    # secure
```

### NEWNYM for a specific instance

```bash
# Change identity only on the CLI instance
echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9061

# Script for NEWNYM on all instances
for port in 9051 9061 9071; do
    echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 $port
    echo "NEWNYM sent to port $port"
done
```

### System resources

Each Tor instance consumes additional resources:

| Resource | Per instance | 4 instances |
|----------|-------------|-------------|
| RAM | ~30-60 MB | ~120-240 MB |
| CPU | Minimal (idle) | Minimal |
| File descriptors | ~200 | ~800 |
| TCP connections | 3-5 (guard+directory) | 12-20 |
| Disk (state/cache) | ~50-100 MB | ~200-400 MB |

---

## Limitations and trade-offs

### More guards = larger attack surface

Each Tor instance selects its own guard. With 4 instances you have 4 different guards:

```
Single instance: 1 guard -> 1 observation point for the adversary
4 instances: 4 guards -> 4 observation points

An adversary controlling even just 1 of the 4 guards
sees 25% of your total traffic
```

This is a real trade-off: more isolation between activities, but more guards
involved in your overall activity.

### When isolation is NOT needed

- **Single-purpose machine**: if you use Tor for only one activity (e.g., browsing only),
  a single instance is sufficient
- **Whonix/Tails**: already provide isolation at the VM/OS level
- **Occasional use**: if you use Tor rarely, the complexity is not justified

### Management complexity

- More instances = more torrc files to maintain
- Tor updates: all instances must be restarted
- Monitoring: each instance needs to be monitored separately
- Bridges: each instance may need its own bridges

---

## In my experience

I use a single Tor instance with the default port 9050. My usage is
relatively simple:
- Firefox with the `tor-proxy` profile via proxychains for browsing
- curl via proxychains or torsocks for testing and verification
- Python scripts for automation

I have not configured advanced stream isolation or multiple instances because my
threat model does not require it: I do not combine identifiable activities with
anonymous activities on the same system. When I do research via Tor, it is the only
active activity.

For a more serious setup (e.g., a journalist with sources to protect, or professional
OSINT), I would configure at least two instances:
1. **Browsing**: with `IsolateDestAddr` to isolate each site
2. **Communication**: a separate instance with a different guard

The systemd template system (`tor@instance.service`) makes management much
simpler compared to launching Tor processes manually. I recommend it for anyone
who needs more than a single instance.

---

## See also

- [torrc - Complete Guide](../02-installazione-e-configurazione/torrc-guida-completa.md) - SocksPort directives and isolation
- [ProxyChains - Complete Guide](../04-strumenti-operativi/proxychains-guida-completa.md) - Proxying apps on different instances
- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - NEWNYM per instance
- [VPN and Tor Hybrid](vpn-e-tor-ibrido.md) - Selective per-application routing
- [Service Management](../02-installazione-e-configurazione/gestione-del-servizio.md) - systemd templates
