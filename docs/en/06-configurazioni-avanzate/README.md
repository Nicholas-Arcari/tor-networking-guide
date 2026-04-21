> **Lingua / Language**: [Italiano](../../06-configurazioni-avanzate/README.md) | English

# Section 06 - Advanced Configurations

Transparent proxy, VPN+Tor hybrid, multi-instance with stream isolation,
and localhost/Docker management: advanced configurations for specific
operational scenarios.

---

## Documents

### Transparent proxy

| Document | Contents |
|----------|----------|
| [Transparent Proxy](transparent-proxy.md) | TransPort, iptables line by line, nftables, IPv6, kernel mechanism |
| [Advanced Transparent Proxy](transparent-proxy-avanzato.md) | LAN gateway, troubleshooting, hardening, production-ready script, Whonix/Tails comparison |

### VPN and Tor

| Document | Contents |
|----------|----------|
| [VPN and Tor - Hybrid Configurations](vpn-e-tor-ibrido.md) | Tor vs VPN, VPN->Tor, Tor->VPN (discouraged), TransPort quasi-VPN |
| [VPN and Tor - Routing, DNS and Kill Switch](vpn-tor-routing-e-dns.md) | Selective routing, hybrid DNS, kill switch, WireGuard/OpenVPN, ExitNodes |

### Multi-instance and isolation

| Document | Contents |
|----------|----------|
| [Multi-Instance and Stream Isolation](multi-istanza-e-stream-isolation.md) | Threat model, systemd templates, architectures, isolation flags |
| [Advanced Stream Isolation](stream-isolation-avanzato.md) | Tor Browser SOCKS auth, SessionGroup, curl/Python, operational management |

### Localhost and Docker

| Document | Contents |
|----------|----------|
| [Tor and Localhost](tor-e-localhost.md) | Localhost problem, Local Service Discovery attack, technical block, solutions |
| [Tor and Localhost - Docker and Development](localhost-docker-e-sviluppo.md) | Docker via Tor, local web development, onion services, compatibility matrix |

### Operational scenarios

| Document | Contents |
|----------|----------|
| [Real-World Scenarios](scenari-reali.md) | Practical cases: transparent proxy in engagements, stream isolation leak, VPN+Tor failure |

---

## Related sections

- [02 - Installation and Configuration](../02-installazione-e-configurazione/) - torrc for TransPort, SocksPort, DNSPort
- [04 - Operational Tools](../04-strumenti-operativi/) - proxychains, torsocks, ControlPort
- [05 - Operational Security](../05-sicurezza-operativa/) - DNS leak, isolation, hardening
- [10 - Hands-On Lab](../10-laboratorio-pratico/) - Lab-05 (stream isolation)
