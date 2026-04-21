> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/README.md) | English

# Section 05 - Operational Security

DNS leak, fingerprinting, traffic analysis, OPSEC, isolation, system
hardening and forensic analysis: everything you need to operate securely
through the Tor network.

---

## Documents

### DNS and leak

| Document | Content |
|----------|---------|
| [DNS Leak](dns-leak.md) | What it is, query anatomy, leak scenarios, practical verification |
| [DNS Leak - Prevention and Hardening](dns-leak-prevenzione-e-hardening.md) | Multi-layer mitigations, iptables/nftables, systemd-resolved, DoH/DoT, forensics |

### Fingerprinting

| Document | Content |
|----------|---------|
| [Fingerprinting](fingerprinting.md) | Browser fingerprinting, entropy, canvas, WebGL, fonts, TLS/JA3/JA4 |
| [Advanced Fingerprinting](fingerprinting-avanzato.md) | HTTP/2, OS, cookieless tracking, tools, defensive configurations |

### Traffic analysis

| Document | Content |
|----------|---------|
| [Traffic Analysis](traffic-analysis.md) | Tor threat model, end-to-end correlation, website fingerprinting |
| [Traffic Analysis - Timing, NetFlow and Defenses](traffic-analysis-attacchi-e-difese.md) | Timing attacks, NetFlow, active attacks, circuit padding, defenses |

### OPSEC

| Document | Content |
|----------|---------|
| [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) | OPSEC principle, 10 mistakes, metadata and correlation |
| [OPSEC - Real-World Cases, Stylometry and Defenses](opsec-casi-reali-e-difese.md) | Silk Road, AlphaBay, LulzSec, stylometry, crypto, checklist, threat model |

### Isolation

| Document | Content |
|----------|---------|
| [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) | Why isolate, comparative matrix, Whonix, Tails |
| [Advanced Isolation](isolamento-avanzato.md) | Qubes OS, network namespaces, Docker, transparent proxy, threat model comparison |

### Hardening

| Document | Content |
|----------|---------|
| [System Hardening](hardening-sistema.md) | Threat model, kernel sysctl, nftables/iptables firewall, IPv6, AppArmor |
| [Advanced Hardening](hardening-avanzato.md) | Services, MAC/hostname, filesystem, logging, Firefox tor-proxy, checklist |

### Forensic analysis

| Document | Content |
|----------|---------|
| [Forensic Analysis and Artifacts](analisi-forense-e-artefatti.md) | Forensic perspective, disk, logs, RAM, network |
| [Forensic Analysis - Browser and Mitigation](forense-browser-e-mitigazione.md) | Browser, proxychains/torsocks, timeline, mitigation, tools |

### Operational scenarios

| Document | Content |
|----------|---------|
| [Real-World Scenarios](scenari-reali.md) | Practical cases: DNS leak in engagement, JA3 mismatch, post-op forensics, OPSEC failure |

---

## Related sections

- [04 - Operational Tools](../04-strumenti-operativi/) - proxychains, torsocks, Nyx, DNS
- [06 - Advanced Configurations](../06-configurazioni-avanzate/) - Transparent proxy, multi-instance
- [07 - Limitations and Attacks](../07-limitazioni-e-attacchi/) - Known attacks, protocol limitations
- [08 - Legal and Ethical Aspects](../08-aspetti-legali-ed-etici/) - Ethics and responsibility
- [10 - Practical Lab](../10-laboratorio-pratico/) - Lab-03 (DNS leak testing)
