> **Lingua / Language**: Italiano | [English](../en/07-limitazioni-e-attacchi/README.md)

# Sezione 07 - Limitazioni e Attacchi

Limitazioni architetturali del protocollo Tor, incompatibilità con le
applicazioni reali, e catalogo completo degli attacchi documentati con
le relative contromisure.

---

## Documenti

### Limitazioni del protocollo

| Documento | Contenuto |
|-----------|-----------|
| [Limitazioni del Protocollo](limitazioni-protocollo.md) | Solo TCP, latenza 3 hop, bandwidth, SOCKS5 limiti, IP variabili, MASQUE/Conflux |

### Limitazioni nelle applicazioni

| Documento | Contenuto |
|-----------|-----------|
| [Limitazioni nelle Applicazioni](limitazioni-applicazioni.md) | Perché le app hanno problemi, web app, siti che bloccano Tor, applicazioni desktop |
| [Limitazioni Applicazioni - Pratica](limitazioni-applicazioni-pratica.md) | nmap/nikto/sqlmap/Burp/Metasploit, package manager, Docker, cloud/API, sessioni, CAPTCHA |

### Attacchi noti

| Documento | Contenuto |
|-----------|-----------|
| [Attacchi Noti alla Rete Tor](attacchi-noti.md) | Timeline, Sybil (CMU/FBI, KAX17), relay early tagging, correlazione end-to-end, website fingerprinting |
| [Attacchi Noti - HSDir, DoS e Contromisure](attacchi-noti-avanzati.md) | HSDir enumeration, DoS, browser exploit (Freedom Hosting, Playpen), supply chain, BGP/RAPTOR, Sniper, Onion Services, matrice, cronologia |

### Scenari operativi

| Documento | Contenuto |
|-----------|-----------|
| [Scenari Reali](scenari-reali.md) | Casi pratici: nmap leak, exit bloccati durante pentest, exploit browser in engagement, 0-day timing |

---

## Sezioni correlate

- [01 - Fondamenti](../01-fondamenti/) - Architettura, circuiti, crittografia
- [03 - Nodi e Rete](../03-nodi-e-rete/) - Guard, exit, bridge, onion services
- [05 - Sicurezza Operativa](../05-sicurezza-operativa/) - Traffic analysis, fingerprinting, OPSEC
- [08 - Aspetti Legali ed Etici](../08-aspetti-legali-ed-etici/) - Responsabilità e legalità
