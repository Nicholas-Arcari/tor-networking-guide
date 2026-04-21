> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/isolamento-avanzato.md) | English

# Advanced Isolation - Qubes, Namespaces, Docker and Comparison

Advanced isolation solutions for Tor: Qubes OS with multi-identity
compartmentalization, Linux network namespaces, Docker, transparent proxy with iptables,
and threat model comparison.

> **Extracted from**: [Isolation and Compartmentalization](isolamento-e-compartimentazione.md)
> for Whonix, Tails and the comparative matrix.

---

## Qubes OS - Extreme compartmentalization

### Architecture

Qubes OS uses Xen virtualization to compartmentalize the system into "qubes"
(lightweight VMs) that are completely isolated:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Qubes OS (Xen hypervisor)                 │
│                                                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐│
│  │  Personal │  │   Work   │  │  Vault   │  │  Disposable VM   ││
│  │  (green)  │  │  (blue)  │  │  (black) │  │  (red)           ││
│  │           │  │          │  │          │  │                  ││
│  │ Browser   │  │ Browser  │  │ KeePass  │  │ Suspicious files ││
│  │ Email     │  │ IDE      │  │ GPG keys │  │ Untrusted links  ││
│  │ Social    │  │ Git      │  │ No net   │  │ Self-destruct    ││
│  └─────┬─────┘  └────┬─────┘  └──────────┘  └────────┬─────────┘│
│        │              │                               │          │
│  ┌─────▼──────────────▼───────────────────────────────▼────────┐│
│  │                    sys-firewall                              ││
│  │            (firewall rules for each qube)                   ││
│  └─────────────────────────┬───────────────────────────────────┘│
│                            │                                     │
│  ┌─────────────────────────▼───────────────────────────────────┐│
│  │                      sys-net                                 ││
│  │              (network drivers, WiFi, eth)                    ││
│  └─────────────────────────┬───────────────────────────────────┘│
└────────────────────────────┼─────────────────────────────────────┘
                             │
                         Internet


For Tor traffic, add sys-whonix:
  [Tor Qube] → [sys-whonix (Whonix Gateway)] → [sys-firewall] → [sys-net]
  [Personal Qube] → [sys-firewall] → [sys-net]  (normal network)
```

### Identity compartmentalization

```
Real-world Qubes scenario:

Qube "personal":
  - Personal email, social media, banking
  - Normal network via sys-firewall

Qube "work":
  - Work email, IDE, repositories
  - Normal network or VPN via sys-firewall

Qube "anon-browsing":
  - Tor Browser, anonymous browsing
  - Network via sys-whonix (forced through Tor)

Qube "anon-comm":
  - Anonymous communication (email, chat)
  - Network via sys-whonix

Qube "vault":
  - Passwords, GPG keys, sensitive documents
  - NO network (completely isolated)

Qube "untrusted":
  - Open downloaded files, suspicious links
  - Disposable: self-destructs on close

Each qube is a completely isolated Xen VM:
  - If "untrusted" is compromised → other qubes are intact
  - If "anon-browsing" is compromised → cannot access "personal"
  - "vault" has no network → impossible to exfiltrate data
```

### Hardware requirements

```
Minimum:
  - CPU: 64-bit Intel/AMD with VT-x/AMD-V and VT-d/AMD-Vi (IOMMU)
  - RAM: 16 GB (practical minimum for 4-5 qubes)
  - Disk: 256 GB SSD (each qube takes space)
  - GPU: Intel integrated (NVIDIA/AMD have issues)

Recommended:
  - RAM: 32 GB (for 8+ simultaneous qubes)
  - Disk: 512 GB SSD NVMe
  - TPM 2.0 for anti-evil-maid

Certified hardware:
  - Purism Librem 14/15 (open hardware)
  - Lenovo ThinkPad T480/X1 Carbon (well supported)
  - Dell Latitude (various models)
  - See: https://www.qubes-os.org/hcl/
```

### When to use Qubes

```
✓ You need multi-identity compartmentalization
✓ You want to completely separate work, personal, anonymous
✓ You have sufficient hardware resources (16+ GB RAM)
✓ You want protection even from kernel exploits
✓ You are willing to invest time in the learning curve

✗ You have less than 16 GB of RAM
✗ Your CPU does not support VT-d/IOMMU
✗ You need gaming or GPU passthrough
✗ You want a simple system to use
```

---

## Linux Network Namespaces

### Architecture

Linux network namespaces allow creating isolated network environments
without virtualization. They are a native kernel mechanism:

```
┌─────────────────────────────────────────────┐
│                  Host Linux                  │
│                                              │
│  Namespace "default" (host)                  │
│  ┌────────────────────────────────────────┐  │
│  │ eth0: 192.168.1.100 (real network)     │  │
│  │ veth0: 10.200.1.1 (bridge to ns)      │  │
│  │ Tor daemon (SocksPort 9050)            │  │
│  └───────────────┬────────────────────────┘  │
│                  │ veth pair                  │
│  Namespace "tor_ns" (isolated)               │
│  ┌───────────────┴────────────────────────┐  │
│  │ veth1: 10.200.1.2 (only interface)     │  │
│  │ Default GW: 10.200.1.1                 │  │
│  │                                        │  │
│  │ App → veth1 → veth0 → host             │  │
│  │       (all traffic passes through       │  │
│  │        the host, where Tor captures it) │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

### Complete step-by-step setup

```bash
#!/bin/bash
# tor-namespace-setup.sh - Create an isolated network namespace for Tor

# 1. Create the namespace
sudo ip netns add tor_ns

# 2. Create a veth interface pair
sudo ip link add veth-host type veth peer name veth-tor

# 3. Move one end into the namespace
sudo ip link set veth-tor netns tor_ns

# 4. Configure the interfaces
# Host side:
sudo ip addr add 10.200.1.1/24 dev veth-host
sudo ip link set veth-host up

# Namespace side:
sudo ip netns exec tor_ns ip addr add 10.200.1.2/24 dev veth-tor
sudo ip netns exec tor_ns ip link set veth-tor up
sudo ip netns exec tor_ns ip link set lo up

# 5. Configure routing in the namespace
sudo ip netns exec tor_ns ip route add default via 10.200.1.1

# 6. Enable IP forwarding on the host
sudo sysctl -w net.ipv4.ip_forward=1

# 7. Configure iptables on the host to force through Tor
# All traffic from namespace → Tor's TransPort
sudo iptables -t nat -A PREROUTING -s 10.200.1.0/24 -p tcp \
    -j REDIRECT --to-ports 9040
sudo iptables -t nat -A PREROUTING -s 10.200.1.0/24 -p udp --dport 53 \
    -j REDIRECT --to-ports 5353

# Block all direct traffic from namespace
sudo iptables -A FORWARD -s 10.200.1.0/24 -j DROP

# 8. Configure DNS in the namespace
sudo mkdir -p /etc/netns/tor_ns
echo "nameserver 10.200.1.1" | sudo tee /etc/netns/tor_ns/resolv.conf

# 9. Test: execute commands in the namespace
sudo ip netns exec tor_ns curl --max-time 30 https://check.torproject.org/api/ip
# Should show {"IsTor":true,...}

# 10. To run a browser in the namespace:
sudo ip netns exec tor_ns sudo -u $USER firefox -no-remote -P tor-ns
```

### Cleanup script

```bash
#!/bin/bash
# tor-namespace-cleanup.sh - Remove the Tor namespace

sudo ip netns exec tor_ns ip link set veth-tor down 2>/dev/null
sudo ip link set veth-host down 2>/dev/null
sudo ip link del veth-host 2>/dev/null
sudo ip netns del tor_ns 2>/dev/null

# Remove iptables rules
sudo iptables -t nat -D PREROUTING -s 10.200.1.0/24 -p tcp \
    -j REDIRECT --to-ports 9040 2>/dev/null
sudo iptables -t nat -D PREROUTING -s 10.200.1.0/24 -p udp --dport 53 \
    -j REDIRECT --to-ports 5353 2>/dev/null
sudo iptables -D FORWARD -s 10.200.1.0/24 -j DROP 2>/dev/null

echo "Namespace tor_ns removed"
```

### Advantages and limitations

```
Advantages:
  + No virtualization needed (zero overhead)
  + Native Linux (kernel feature)
  + Complete network isolation
  + Combinable with cgroups to limit resources
  + Lightweight: creation/destruction in milliseconds

Limitations:
  - Complex manual configuration
  - If iptables rules are wrong → leak possible
  - Not amnesic (host's disk and RAM are accessible)
  - Does not protect from kernel exploits (shares the kernel)
  - Requires root for configuration
  - Does not isolate the filesystem (the namespace sees host files)
```

---

## Docker and containerization

### Tor in Docker

```dockerfile
# Dockerfile for an isolated Tor container
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tor \
    proxychains4 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY torrc /etc/tor/torrc
COPY proxychains4.conf /etc/proxychains4.conf

# Tor runs as debian-tor user
USER debian-tor
EXPOSE 9050

CMD ["tor", "-f", "/etc/tor/torrc"]
```

### Docker Compose with browser

```yaml
# docker-compose.yml
version: '3.8'

services:
  tor:
    build: .
    container_name: tor-proxy
    networks:
      - tor-net
    ports:
      - "127.0.0.1:9050:9050"  # SocksPort (localhost only)
    restart: unless-stopped

  browser:
    image: jlesage/firefox:latest
    container_name: tor-browser
    networks:
      - tor-net
    environment:
      - http_proxy=socks5h://tor:9050
      - https_proxy=socks5h://tor:9050
    ports:
      - "127.0.0.1:5800:5800"  # Web UI
    depends_on:
      - tor
    # No direct Internet access
    # Only via the tor-net network → tor container

networks:
  tor-net:
    driver: bridge
    internal: true  # NO direct Internet access
    # Containers can communicate with each other
    # but CANNOT reach the Internet directly
```

### Docker limitations for anonymity

```
Docker is NOT designed for security:
  - The Docker daemon runs as root
  - Container escapes are possible (multiple CVEs)
  - Docker network policies are not designed for anonymity
  - Docker logs can contain sensitive information
  - Isolation is not at the hypervisor level (shares the kernel)

Docker is useful for:
  ✓ Reproducible and portable environments
  ✓ Lightweight isolation for testing
  ✓ CI/CD with Tor
  ✓ Application separation

Docker is NOT sufficient for:
  ✗ High-risk anonymity
  ✗ Protection from kernel exploits
  ✗ Protection from sophisticated adversaries
```

---

## Transparent proxy with iptables

### Quick setup for system-wide use

```bash
#!/bin/bash
# transparent-tor.sh - Force all TCP traffic through Tor

TOR_USER="debian-tor"
TRANS_PORT=9040
DNS_PORT=5353

# Allow Tor's traffic
sudo iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_USER -j RETURN

# DNS via Tor
sudo iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $DNS_PORT

# TCP via TransPort
sudo iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TRANS_PORT

# Block direct (non-Tor) traffic
sudo iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m owner --uid-owner $TOR_USER -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A OUTPUT -j DROP

echo "Transparent proxy active. All TCP goes through Tor."
echo "WARNING: UDP blocked (no NTP, QUIC, VoIP)"
```

### Advantages and limitations

```
Advantages:
  + All TCP traffic goes through Tor without app configuration
  + DNS forced through Tor (no leak possible)
  + Firewall-level leak prevention

Limitations:
  - UDP completely blocked (NTP, direct DNS, QUIC, VoIP)
  - If Tor stalls → all networking is blocked
  - Fragile: a rule error → leak
  - Degraded performance (all traffic over 3 hops)
  - Does not isolate applications from each other
```

For a complete guide, see `docs/06-configurazioni-avanzate/transparent-proxy.md`.

---

## Comparison by threat model

### Adversary: Web trackers (Google, Facebook)

```
Required protection: hide IP, prevent fingerprinting
Minimum solution: Tor Browser
Recommended solution: Tor Browser
Notes: system isolation is not necessary for this threat model
```

### Adversary: ISP

```
Required protection: hide destinations and Tor usage
Minimum solution: Tor + obfs4 bridge
Recommended solution: Tor + obfs4 bridge + proxy_dns
Notes: my use case. proxychains is sufficient.
```

### Adversary: hostile local network (public WiFi, hotel)

```
Required protection: hide all traffic, MAC spoofing
Minimum solution: VPN + Tor Browser
Recommended solution: Tails (randomized MAC + everything via Tor)
Notes: Tails is ideal for untrusted networks
```

### Adversary: national law enforcement

```
Required protection: complete anonymity, amnesia, rigorous OPSEC
Minimum solution: Whonix
Recommended solution: Tails (amnesic) or Qubes+Whonix
Notes: human OPSEC is more important than technology
```

### Adversary: intelligence (NSA, GCHQ)

```
Required protection: all of the above + defense from global correlation
Minimum solution: Qubes + Whonix + perfect OPSEC
Recommended solution: Qubes + Whonix + Tails for specific sessions
Notes: against a global adversary, no solution is guaranteed
```

| Scenario | Recommended solution |
|----------|---------------------|
| Study and testing (my case) | Tor + proxychains |
| ISP privacy | Tor + proxychains + obfs4 bridge |
| Serious anonymous browsing | Tor Browser |
| High risk (journalism, activism) | Tails or Whonix |
| Multi-identity compartmentalization | Qubes OS + Whonix |
| Lightweight system-wide protection | iptables transparent proxy |
| Reproducible test environments | Docker + Tor |
| Untrusted local network | Tails (USB live) |

---

## My position

For my use case (study, testing, ISP privacy), the current setup
(Tor daemon + proxychains on Kali) is sufficient. Isolation solutions
are for scenarios where anonymity is critical.

The choice depends on the threat model. There is no "best" solution
in absolute terms - there is the solution suited to the specific risk.

If I needed to scale my setup for a higher risk, the progression would be:
1. **Current**: proxychains + obfs4 bridge (ISP privacy)
2. **Intermediate**: transparent proxy with iptables (leak prevention)
3. **High**: Whonix on KVM (complete isolation)
4. **Critical**: Tails from USB (amnesia + isolation)
5. **Maximum**: Qubes + Whonix (compartmentalization + isolation)

---

## See also

- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - Complete iptables/nftables setup
- [System Hardening](hardening-sistema.md) - sysctl, AppArmor, nftables
- [DNS Leak](dns-leak.md) - DNS leak prevention at all levels
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Isolation does not replace OPSEC
- [Forensic Analysis and Artifacts](analisi-forense-e-artefatti.md) - What leaves traces on disk and RAM
- [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Circuit isolation
