> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/README.md) | English

# Section 04 - Operational Tools

ProxyChains, torsocks, Nyx, ControlPort, DNS, Tor Browser: the everyday tools
for operating through the Tor network.

---

## Documents

### Proxy and routing

| Document | Contents |
|----------|----------|
| [ProxyChains - Complete Guide](proxychains-guida-completa.md) | LD_PRELOAD, chain modes, proxy_dns, configuration, debugging |
| [torsocks](torsocks.md) | Internal workings, syscalls, DNS, UDP, IsolatePID, shell |
| [torsocks Advanced](torsocks-avanzato.md) | Variables, edge cases, debugging, security, comparison with proxychains |

### Monitoring and control

| Document | Contents |
|----------|----------|
| [Circuit Control and NEWNYM](controllo-circuiti-e-newnym.md) | ControlPort, NEWNYM, commands, Python Stem, security |
| [Nyx and Monitoring](nyx-e-monitoraggio.md) | Installation, screens (bandwidth, connections, config, log, interpretor) |
| [Nyx Advanced](nyx-avanzato.md) | Navigation, shortcuts, configuration, debugging, Stem, integration |

### Browser and applications

| Document | Contents |
|----------|----------|
| [Tor Browser and Applications](tor-browser-e-applicazioni.md) | Tor Browser architecture, fingerprinting, FPI, Firefox+proxychains |
| [Applications via Tor](applicazioni-via-tor.md) | App routing, compatibility matrix, native SOCKS5, issues |

### DNS

| Document | Contents |
|----------|----------|
| [Tor and DNS - Resolution](tor-e-dns-risoluzione.md) | Normal DNS vs Tor, DNSPort, AutomapHosts, SOCKS5, systemd-resolved |
| [Advanced DNS and Hardening](dns-avanzato-e-hardening.md) | resolv.conf, proxy_dns internals, .onion, leak scenarios, hardening |

### Verification

| Document | Contents |
|----------|----------|
| [IP, DNS and Leak Verification](verifica-ip-dns-e-leak.md) | IP tests, DNS leak, ports, leak types, prevention |

### Operational scenarios

| Document | Contents |
|----------|----------|
| [Real-World Scenarios](scenari-reali.md) | Practical pentester cases: proxychains in engagements, DNS leak detection |

---

## Related sections

- [02 - Installation and Configuration](../02-installazione-e-configurazione/) - torrc for SocksPort, DNSPort, ControlPort
- [05 - Operational Security](../05-sicurezza-operativa/) - DNS leak, fingerprinting, OPSEC
- [06 - Advanced Configurations](../06-configurazioni-avanzate/) - Transparent proxy, multi-instance
- [10 - Practical Lab](../10-laboratorio-pratico/) - Lab-01, Lab-03 apply these tools
