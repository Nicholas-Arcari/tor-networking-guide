# Sezione 05 - Sicurezza Operativa

DNS leak, fingerprinting, traffic analysis, OPSEC, isolamento, hardening
di sistema e analisi forense: tutto ciò che serve per operare in modo sicuro
attraverso la rete Tor.

---

## Documenti

### DNS e leak

| Documento | Contenuto |
|-----------|-----------|
| [DNS Leak](dns-leak.md) | Cos'è, anatomia query, scenari di leak, verifica pratica |
| [DNS Leak - Prevenzione e Hardening](dns-leak-prevenzione-e-hardening.md) | Mitigazioni multilivello, iptables/nftables, systemd-resolved, DoH/DoT, forensics |

### Fingerprinting

| Documento | Contenuto |
|-----------|-----------|
| [Fingerprinting](fingerprinting.md) | Browser fingerprinting, entropia, canvas, WebGL, font, TLS/JA3/JA4 |
| [Fingerprinting Avanzato](fingerprinting-avanzato.md) | HTTP/2, OS, tracking senza cookie, strumenti, configurazioni difensive |

### Traffic analysis

| Documento | Contenuto |
|-----------|-----------|
| [Traffic Analysis](traffic-analysis.md) | Modello minaccia Tor, correlazione end-to-end, website fingerprinting |
| [Traffic Analysis - Timing, NetFlow e Difese](traffic-analysis-attacchi-e-difese.md) | Timing attacks, NetFlow, attacchi attivi, circuit padding, difese |

### OPSEC

| Documento | Contenuto |
|-----------|-----------|
| [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) | Principio OPSEC, 10 errori, metadata e correlazione |
| [OPSEC - Casi Reali, Stylometry e Difese](opsec-casi-reali-e-difese.md) | Silk Road, AlphaBay, LulzSec, stylometry, crypto, checklist, threat model |

### Isolamento

| Documento | Contenuto |
|-----------|-----------|
| [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) | Perché isolare, matrice comparativa, Whonix, Tails |
| [Isolamento Avanzato](isolamento-avanzato.md) | Qubes OS, network namespaces, Docker, transparent proxy, confronto threat model |

### Hardening

| Documento | Contenuto |
|-----------|-----------|
| [Hardening di Sistema](hardening-sistema.md) | Threat model, kernel sysctl, firewall nftables/iptables, IPv6, AppArmor |
| [Hardening Avanzato](hardening-avanzato.md) | Servizi, MAC/hostname, filesystem, logging, Firefox tor-proxy, checklist |

### Analisi forense

| Documento | Contenuto |
|-----------|-----------|
| [Analisi Forense e Artefatti](analisi-forense-e-artefatti.md) | Prospettiva forense, disco, log, RAM, rete |
| [Analisi Forense - Browser e Mitigazione](forense-browser-e-mitigazione.md) | Browser, proxychains/torsocks, timeline, mitigazione, strumenti |

### Scenari operativi

| Documento | Contenuto |
|-----------|-----------|
| [Scenari Reali](scenari-reali.md) | Casi pratici: DNS leak in engagement, JA3 mismatch, forensics post-op, OPSEC failure |

---

## Sezioni correlate

- [04 - Strumenti Operativi](../04-strumenti-operativi/) - proxychains, torsocks, Nyx, DNS
- [06 - Configurazioni Avanzate](../06-configurazioni-avanzate/) - Transparent proxy, multi-istanza
- [07 - Limitazioni e Attacchi](../07-limitazioni-e-attacchi/) - Attacchi noti, limitazioni protocollo
- [08 - Aspetti Legali ed Etici](../08-aspetti-legali-ed-etici/) - Etica e responsabilità
- [10 - Laboratorio Pratico](../10-laboratorio-pratico/) - Lab-03 (DNS leak testing)
