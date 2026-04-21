> **Lingua / Language**: [Italiano](../../06-configurazioni-avanzate/scenari-reali.md) | English

# Real-World Scenarios - Advanced Tor Configurations in Action

Operational cases where transparent proxy, VPN+Tor, multi-instance, stream isolation,
and localhost management made the difference during penetration tests and
red team engagements.

---

## Table of Contents

- [Scenario 1: Transparent proxy blocks leak from non-cooperative tool](#scenario-1-transparent-proxy-blocks-leak-from-non-cooperative-tool)
- [Scenario 2: Missing stream isolation correlates identities during OSINT](#scenario-2-missing-stream-isolation-correlates-identities-during-osint)
- [Scenario 3: VPN drops and Tor exposes usage to ISP](#scenario-3-vpn-drops-and-tor-exposes-usage-to-isp)
- [Scenario 4: Docker container leaks real IP via hardcoded DNS](#scenario-4-docker-container-leaks-real-ip-via-hardcoded-dns)

---

## Scenario 1: Transparent proxy blocks leak from non-cooperative tool

### Context

During a pentest, the team was using a commercial vulnerability scanning tool
that did not support SOCKS5 proxy. The tool had to scan the target via Tor
to hide the team's IP.

### Problem

The tool ignored `proxychains` (it used raw sockets for some operations) and
did not respect proxy environment variables:

```bash
proxychains vuln-scanner --target api.target.com
# tcpdump shows: direct SYN packets toward api.target.com
# -> The tool was bypassing proxychains with direct syscalls
```

### Solution: temporary transparent proxy

```bash
# Activate the transparent proxy
sudo ./tor-transparent-proxy.sh start
# -> All system TCP forced via Tor
# -> Even the tool's raw sockets go through TransPort

# Run the scan
vuln-scanner --target api.target.com
# tcpdump: no direct traffic toward the target
# Everything redirected to TransPort 9040

# Deactivate after the scan
sudo ./tor-transparent-proxy.sh stop
```

### Lesson learned

The transparent proxy is the solution for tools that do not support proxies or
that bypass LD_PRELOAD. The iptables rules capture **all** TCP traffic
at the kernel level, regardless of how the application creates its
connections. See [Transparent Proxy](transparent-proxy.md) for the complete setup
and [Advanced Transparent Proxy](transparent-proxy-avanzato.md) for
the production-ready script.

---

## Scenario 2: Missing stream isolation correlates identities during OSINT

### Context

An OSINT operator was gathering information on two separate targets: an
individual and a company. They used a single Tor instance with SocksPort 9050
without isolation flags.

### Problem

Both investigations shared the same Tor circuit (same exit node):

```
[Browser tab 1: target person's LinkedIn] -> Exit 185.220.101.x
[Browser tab 2: target company website]   -> Exit 185.220.101.x
[curl: OSINT API for person]              -> Exit 185.220.101.x

The exit node (or an observer) sees:
  - LinkedIn search for "Mario Rossi"
  - Visit to target-company.com
  - OSINT API query for "Mario Rossi"
-> Correlates: someone is investigating Mario Rossi and his company
```

### Fix: IsolateSOCKSAuth with per-domain credentials

```ini
# torrc
SocksPort 9050 IsolateSOCKSAuth
```

```bash
# Research on person -> circuit A
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "persona:osint1" \
     https://api.osint-tool.com/search?name=target

# Research on company -> circuit B (different)
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "azienda:osint2" \
     https://target-azienda.com/
```

### Lesson learned

Without `IsolateSOCKSAuth` or `IsolateDestAddr`, a single malicious exit can
correlate all of the operator's activities. For OSINT on multiple targets,
use different SOCKS5 credentials for each target or separate Tor instances.
See [Multi-Instance and Stream Isolation](multi-istanza-e-stream-isolation.md)
for the multi-instance setup.

---

## Scenario 3: VPN drops and Tor exposes usage to ISP

### Context

An operator was using the VPN->Tor configuration to hide Tor usage from
the corporate ISP (which monitored traffic). The WireGuard VPN was connected
to the corporate server, and Tor was routed through the VPN.

### Problem

The WireGuard connection dropped (server timeout) during an active Tor
session. Tor automatically reconnected to the guard node **without the VPN**,
directly exposing Tor traffic to the ISP:

```
BEFORE (VPN active):
  Client -> [WireGuard] -> VPN Server -> Tor Guard
  ISP sees: WireGuard traffic (does not know it is Tor)

AFTER (VPN dropped):
  Client -> Tor Guard (directly)
  ISP sees: direct connection to known Tor relay IP
  -> ISP alert: "user connected to Tor relay"
```

### Fix: iptables kill switch

```bash
#!/bin/bash
# Block all traffic if VPN is not active
VPN_IFACE="wg0"
VPN_SERVER_IP="85.x.x.x"

# Allow only toward the VPN server
iptables -A OUTPUT -d $VPN_SERVER_IP -j ACCEPT
# Allow traffic on the VPN
iptables -A OUTPUT -o $VPN_IFACE -j ACCEPT
# Allow localhost
iptables -A OUTPUT -o lo -j ACCEPT
# DROP everything else
iptables -A OUTPUT -j DROP

# If wg0 drops -> rule 2 does not match -> everything dropped -> no leak
```

### Lesson learned

VPN->Tor without a kill switch is dangerous. If the VPN drops, Tor reconnects
directly, exposing its usage to the ISP. An iptables kill switch is **mandatory**
for this configuration. Alternatively, use obfs4 bridges (no VPN required,
and they mask Tor traffic as HTTPS). See
[VPN and Tor - Hybrid Configurations](vpn-e-tor-ibrido.md) for the architectures.

---

## Scenario 4: Docker container leaks real IP via hardcoded DNS

### Context

A reconnaissance tool was containerized in Docker with SOCKS5 proxy
configured via environment variable. The container was supposed to exit via Tor.

### Problem

```yaml
# docker-compose.yml
services:
  recon:
    image: recon-tool:latest
    environment:
      - HTTPS_PROXY=socks5h://host.docker.internal:9050
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

The tool respected the `HTTPS_PROXY` variable for HTTP connections, but
used an internal DNS resolver with hardcoded Google DNS (`8.8.8.8`) for
some operations. DNS queries went out from the container directly:

```bash
# From the host, monitoring:
sudo tcpdump -i docker0 port 53
# 10:15:32 IP 172.17.0.2.45123 > 8.8.8.8.53: A? target.com
# -> DNS leak from the container!
```

### Solution: network isolation + forced DNS

```yaml
services:
  recon:
    image: recon-tool:latest
    environment:
      - HTTPS_PROXY=socks5h://tor:9050
    networks:
      - tor-net
    dns: 172.18.0.2  # IP of the Tor container (DNSPort)

  tor:
    image: tor-proxy:latest
    networks:
      - tor-net

networks:
  tor-net:
    driver: bridge
    internal: true  # NO direct Internet access
```

With `internal: true`, the `recon` container cannot reach the Internet
directly - everything must go through the `tor` container.

### Lesson learned

Proxy environment variables do not control DNS in all cases.
Containers with hardcoded resolvers bypass the proxy for DNS queries.
Use Docker network `internal: true` to force network isolation,
combined with a dedicated Tor container as the sole exit point. See
[Tor and Localhost - Docker and Development](localhost-docker-e-sviluppo.md) for
Docker scenarios.

---

## Summary

| Scenario | Tool | Mitigated risk |
|----------|------|----------------|
| Non-cooperative tool | Transparent proxy | IP leak from raw sockets/direct syscalls |
| Multi-target OSINT | IsolateSOCKSAuth | Correlation between different targets |
| VPN drop without kill switch | iptables kill switch | Exposure of Tor usage to ISP |
| Docker hardcoded DNS | Docker internal network | DNS leak from container |

---

## See also

- [Transparent Proxy](transparent-proxy.md) - iptables/nftables setup
- [Multi-Instance and Stream Isolation](multi-istanza-e-stream-isolation.md) - Circuit isolation
- [VPN and Tor - Hybrid Configurations](vpn-e-tor-ibrido.md) - VPN->Tor, kill switch
- [Tor and Localhost](tor-e-localhost.md) - Docker and local services
