> **Lingua / Language**: Italiano | [English](../en/04-strumenti-operativi/README.md)

# Sezione 04 - Strumenti Operativi

ProxyChains, torsocks, Nyx, ControlPort, DNS, Tor Browser: gli strumenti
quotidiani per operare attraverso la rete Tor.

---

## Documenti

### Proxy e instradamento

| Documento | Contenuto |
|-----------|-----------|
| [ProxyChains - Guida Completa](proxychains-guida-completa.md) | LD_PRELOAD, chain modes, proxy_dns, configurazione, debugging |
| [torsocks](torsocks.md) | Funzionamento interno, syscall, DNS, UDP, IsolatePID, shell |
| [torsocks Avanzato](torsocks-avanzato.md) | Variabili, edge cases, debugging, sicurezza, confronto con proxychains |

### Monitoring e controllo

| Documento | Contenuto |
|-----------|-----------|
| [Controllo Circuiti e NEWNYM](controllo-circuiti-e-newnym.md) | ControlPort, NEWNYM, comandi, Python Stem, sicurezza |
| [Nyx e Monitoraggio](nyx-e-monitoraggio.md) | Installazione, schermate (bandwidth, connections, config, log, interpretor) |
| [Nyx Avanzato](nyx-avanzato.md) | Navigazione, shortcut, configurazione, debugging, Stem, integrazione |

### Browser e applicazioni

| Documento | Contenuto |
|-----------|-----------|
| [Tor Browser e Applicazioni](tor-browser-e-applicazioni.md) | Architettura Tor Browser, fingerprinting, FPI, Firefox+proxychains |
| [Applicazioni via Tor](applicazioni-via-tor.md) | Instradamento app, matrice compatibilità, SOCKS5 nativo, problemi |

### DNS

| Documento | Contenuto |
|-----------|-----------|
| [Tor e DNS - Risoluzione](tor-e-dns-risoluzione.md) | DNS normale vs Tor, DNSPort, AutomapHosts, SOCKS5, systemd-resolved |
| [DNS Avanzato e Hardening](dns-avanzato-e-hardening.md) | resolv.conf, proxy_dns internals, .onion, leak scenari, hardening |

### Verifica

| Documento | Contenuto |
|-----------|-----------|
| [Verifica IP, DNS e Leak](verifica-ip-dns-e-leak.md) | Test IP, DNS leak, porte, tipi di leak, prevenzione |

### Scenari operativi

| Documento | Contenuto |
|-----------|-----------|
| [Scenari Reali](scenari-reali.md) | Casi pratici da pentester: proxychains in engagement, DNS leak detection |

---

## Sezioni correlate

- [02 - Installazione e Configurazione](../02-installazione-e-configurazione/) - torrc per SocksPort, DNSPort, ControlPort
- [05 - Sicurezza Operativa](../05-sicurezza-operativa/) - DNS leak, fingerprinting, OPSEC
- [06 - Configurazioni Avanzate](../06-configurazioni-avanzate/) - Transparent proxy, multi-istanza
- [10 - Laboratorio Pratico](../10-laboratorio-pratico/) - Lab-01, Lab-03 applicano questi strumenti
