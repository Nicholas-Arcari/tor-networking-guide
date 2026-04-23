> **Lingua / Language**: [Italiano](../../10-laboratorio-pratico/README.md) | English

# Section 10 - Hands-On Lab

Five progressive hands-on labs: from basic setup to advanced stream
isolation. Each lab includes objectives, prerequisites, commands
to execute, result verification, and troubleshooting.

---

## Labs

| Lab | Document | Content |
|-----|----------|---------|
| 01 | [Setup and Verification](lab-01-setup-e-verifica.md) | Tor installation, connection verification, ControlPort, first NEWNYM |
| 02 | [Circuit Analysis](lab-02-analisi-circuiti.md) | Nyx, circuit inspection, guard/middle/exit, NEWNYM and circuit change |
| 03 | [DNS Leak Testing](lab-03-dns-leak-testing.md) | DNS leak verification, tcpdump, DNSPort, iptables anti-leak |
| 04 | [Onion Service](lab-04-onion-service.md) | Creating a v3 onion service, HiddenServiceDir, client authorization |
| 05 | [Stream Isolation](lab-05-stream-isolation.md) | IsolateSOCKSAuth, multi-SocksPort, verifying separate circuits |

---

## Recommended Path

```
Lab 01 → Lab 02 → Lab 03 → Lab 04 → Lab 05
  ↓         ↓         ↓         ↓         ↓
Setup    Circuits   DNS Leak  Onion Svc  Isolation
(base)   (analysis) (defense) (server)   (advanced)
```

Each lab is self-contained but assumes knowledge from the previous labs.

---

## Prerequisites

- Kali Linux (or Debian-based) with Tor installed
- Root access for iptables and torrc configuration
- `nyx`, `proxychains`, `torsocks`, `curl` installed
- Basic Linux terminal knowledge

---

## Related sections

- [02 - Installation and Configuration](../02-installazione-e-configurazione/) - torrc, ControlPort, service
- [04 - Operational Tools](../04-strumenti-operativi/) - proxychains, torsocks, Nyx, NEWNYM
- [05 - Operational Security](../05-sicurezza-operativa/) - DNS leak, isolation
- [06 - Advanced Configurations](../06-configurazioni-avanzate/) - Stream isolation, multi-instance
