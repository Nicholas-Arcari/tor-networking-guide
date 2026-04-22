> **Lingua / Language**: [Italiano](../../07-limitazioni-e-attacchi/README.md) | English

# Section 07 - Limitations and Attacks

Architectural limitations of the Tor protocol, incompatibilities with
real-world applications, and a complete catalog of documented attacks with
their respective countermeasures.

---

## Documents

### Protocol limitations

| Document | Contents |
|----------|----------|
| [Protocol Limitations](limitazioni-protocollo.md) | TCP-only, 3-hop latency, bandwidth, SOCKS5 limits, variable IPs, MASQUE/Conflux |

### Application limitations

| Document | Contents |
|----------|----------|
| [Application Limitations](limitazioni-applicazioni.md) | Why apps have issues, web apps, sites that block Tor, desktop applications |
| [Application Limitations - Hands-On](limitazioni-applicazioni-pratica.md) | nmap/nikto/sqlmap/Burp/Metasploit, package managers, Docker, cloud/APIs, sessions, CAPTCHAs |

### Known attacks

| Document | Contents |
|----------|----------|
| [Known Attacks on the Tor Network](attacchi-noti.md) | Timeline, Sybil (CMU/FBI, KAX17), relay early tagging, end-to-end correlation, website fingerprinting |
| [Known Attacks - HSDir, DoS and Countermeasures](attacchi-noti-avanzati.md) | HSDir enumeration, DoS, browser exploits (Freedom Hosting, Playpen), supply chain, BGP/RAPTOR, Sniper, Onion Services, matrix, timeline |

### Operational scenarios

| Document | Contents |
|----------|----------|
| [Real-World Scenarios](scenari-reali.md) | Practical cases: nmap leak, blocked exits during pentest, browser exploit in engagement, 0-day timing |

---

## Related sections

- [01 - Fundamentals](../01-fondamenti/) - Architecture, circuits, cryptography
- [03 - Nodes and Network](../03-nodi-e-rete/) - Guard, exit, bridge, onion services
- [05 - Operational Security](../05-sicurezza-operativa/) - Traffic analysis, fingerprinting, OPSEC
- [08 - Legal and Ethical Aspects](../08-aspetti-legali-ed-etici/) - Responsibility and legality
