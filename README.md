# Tor Networking Guide

Documentazione tecnica approfondita sulla rete Tor: architettura a livello di protocollo,
crittografia dei circuiti, configurazione operativa, strumenti di analisi, sicurezza
operativa, attacchi noti e difese, aspetti legali, scenari operativi reali.

Questo progetto raccoglie tutto il lavoro tecnico e l'esperienza personale accumulata
durante lo studio e l'uso reale della rete Tor su Kali Linux (Debian), con proxychains,
bridge obfs4, ControlPort, script di automazione e analisi dei circuiti.

**Non è una guida ad alto livello**: ogni documento scende nel dettaglio del protocollo,
delle celle, della crittografia, delle interazioni reali con il sistema operativo e con
la rete.

---

## Quick Start

```bash
# Setup completo (installa tutto, configura torrc, crea profilo Firefox)
sudo ./setup.sh

# Verificare che tutto funzioni
./tests/smoke-test-tor.sh
```

---

## Struttura del progetto

### docs/01-fondamenti/
Architettura interna di Tor, protocollo delle celle, handshake ntor, crittografia
AES-128-CTR/Curve25519, consenso e Directory Authorities.

- [Architettura di Tor](docs/01-fondamenti/architettura-tor.md) - Bootstrap, componenti, circuiti, stream isolation, modello di minaccia
- [Circuiti, Crittografia e Celle](docs/01-fondamenti/circuiti-crittografia-e-celle.md) - Celle 514 byte, RELAY commands, cifratura strato per strato, flow control, handshake ntor
- [Consenso e Directory Authorities](docs/01-fondamenti/consenso-e-directory-authorities.md) - Votazione, flag, bandwidth authorities, descriptor, cache

### docs/02-installazione-e-configurazione/
Installazione, configurazione torrc completa (ogni direttiva spiegata), gestione systemd.

- [Installazione e Verifica](docs/02-installazione-e-configurazione/installazione-e-verifica.md) - Pacchetti, permessi, gruppo debian-tor, profilo Firefox, troubleshooting
- [torrc - Guida Completa](docs/02-installazione-e-configurazione/torrc-guida-completa.md) - SocksPort, DNSPort, ControlPort, bridge, isolamento, exit policy, relay config
- [Gestione del Servizio](docs/02-installazione-e-configurazione/gestione-del-servizio.md) - systemd, log, bootstrap, segnali, debug, manutenzione

### docs/03-nodi-e-rete/
Analisi dettagliata di ogni tipo di nodo, bridge e pluggable transports, onion services v3,
monitoring e metriche.

- [Guard Nodes](docs/03-nodi-e-rete/guard-nodes.md) - Selezione persistente, file state, path bias, vanguards, attacchi
- [Middle Relay](docs/03-nodi-e-rete/middle-relay.md) - Selezione pesata, bandwidth weights, ruolo di separazione
- [Exit Nodes](docs/03-nodi-e-rete/exit-nodes.md) - Exit policy, rischi (sniffing, MITM, injection), verifica IP, blocchi
- [Bridges e Pluggable Transports](docs/03-nodi-e-rete/bridges-e-pluggable-transports.md) - obfs4 internals, meek, Snowflake, resistenza DPI, active probing
- [Onion Services v3](docs/03-nodi-e-rete/onion-services-v3.md) - Protocollo rendezvous, introduction points, descriptor cifrati
- [Relay Monitoring e Metriche](docs/03-nodi-e-rete/relay-monitoring-e-metriche.md) - Tor Metrics, Prometheus/Grafana, bandwidth accounting, OONI

### docs/04-strumenti-operativi/
Uso pratico di proxychains, torsocks, ControlPort, NEWNYM, verifica leak, nyx, browser, DNS.

- [ProxyChains - Guida Completa](docs/04-strumenti-operativi/proxychains-guida-completa.md) - LD_PRELOAD, chain modes, proxy_dns, debugging
- [torsocks](docs/04-strumenti-operativi/torsocks.md) - Blocco UDP, IsolatePID, confronto dettagliato con proxychains, edge cases
- [Controllo Circuiti e NEWNYM](docs/04-strumenti-operativi/controllo-circuiti-e-newnym.md) - Protocollo ControlPort, comandi, Stem (Python), script
- [Verifica IP, DNS e Leak](docs/04-strumenti-operativi/verifica-ip-dns-e-leak.md) - Test IP, DNS leak, IPv6 leak, WebRTC leak, firewall
- [Nyx e Monitoraggio](docs/04-strumenti-operativi/nyx-e-monitoraggio.md) - Monitor TUI, 5 schermate, debugging scenari, Stem scripting
- [Tor Browser e Applicazioni](docs/04-strumenti-operativi/tor-browser-e-applicazioni.md) - Anti-fingerprinting, FPI, routing applicazioni, matrice compatibilità
- [Tor e DNS - Risoluzione](docs/04-strumenti-operativi/tor-e-dns-risoluzione.md) - DNSPort, AutomapHosts, SOCKS5 remote DNS, systemd-resolved, hardening DNS

### docs/05-sicurezza-operativa/
DNS leak, traffic analysis, fingerprinting, OPSEC, isolamento, hardening, forensics.

- [DNS Leak](docs/05-sicurezza-operativa/dns-leak.md) - Scenari di leak, prevenzione multilivello, firewall iptables
- [Traffic Analysis](docs/05-sicurezza-operativa/traffic-analysis.md) - Correlazione end-to-end, website fingerprinting, timing attacks
- [Fingerprinting](docs/05-sicurezza-operativa/fingerprinting.md) - Browser, TLS/JA3, OS, canvas, WebGL, tracking senza cookie
- [OPSEC e Errori Comuni](docs/05-sicurezza-operativa/opsec-e-errori-comuni.md) - 10 errori fatali, casi reali di deanonimizzazione, checklist
- [Isolamento e Compartimentazione](docs/05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Whonix, Tails, Qubes, network namespaces, Docker
- [Hardening di Sistema](docs/05-sicurezza-operativa/hardening-sistema.md) - sysctl, kernel params, AppArmor, nftables, servizi da disabilitare
- [Analisi Forense e Artefatti](docs/05-sicurezza-operativa/analisi-forense-e-artefatti.md) - Artefatti disco, RAM, rete, browser, timeline forense, mitigazione

### docs/06-configurazioni-avanzate/
VPN+Tor ibrido, transparent proxy, multi-istanza, localhost.

- [VPN e Tor Ibrido](docs/06-configurazioni-avanzate/vpn-e-tor-ibrido.md) - VPN→Tor, Tor→VPN, TransPort, routing selettivo, ExitNodes
- [Transparent Proxy](docs/06-configurazioni-avanzate/transparent-proxy.md) - iptables/nftables, TransPort internals, IPv6, gateway LAN, troubleshooting, hardening
- [Multi-Istanza e Stream Isolation](docs/06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - systemd templates, flag isolamento, SessionGroup, Tor Browser model
- [Tor e Localhost](docs/06-configurazioni-avanzate/tor-e-localhost.md) - Local Service Discovery Attack, Docker, sviluppo web, onion services locali

### docs/07-limitazioni-e-attacchi/
Limitazioni del protocollo, incompatibilità applicative, attacchi documentati.

- [Limitazioni del Protocollo](docs/07-limitazioni-e-attacchi/limitazioni-protocollo.md) - TCP-only, latenza, bandwidth, SOCKS5, circuiti multipli
- [Limitazioni nelle Applicazioni](docs/07-limitazioni-e-attacchi/limitazioni-applicazioni.md) - Siti che bloccano Tor, app desktop, strumenti di sicurezza
- [Attacchi Noti](docs/07-limitazioni-e-attacchi/attacchi-noti.md) - Sybil, relay early, correlazione, website fingerprinting, HSDir, DoS

### docs/08-aspetti-legali-ed-etici/
Quadro legale Italia/UE, etica dell'anonimato, responsabilità.

- [Aspetti Legali](docs/08-aspetti-legali-ed-etici/aspetti-legali.md) - Legalità in Italia, GDPR, exit node, bridge, precedenti
- [Etica e Responsabilità](docs/08-aspetti-legali-ed-etici/etica-e-responsabilita.md) - Dilemma etico, casi studio, relay operator, sorveglianza, contributi alla rete

### docs/09-scenari-operativi/
Scenari pratici di utilizzo di Tor in contesti reali.

- [Ricognizione Anonima](docs/09-scenari-operativi/ricognizione-anonima.md) - OSINT via Tor, strumenti compatibili, anti-detection, gestione identità
- [Comunicazione Sicura](docs/09-scenari-operativi/comunicazione-sicura.md) - Email anonima, SecureDrop, OnionShare, SSH via Tor, messaggistica
- [Sviluppo e Test](docs/09-scenari-operativi/sviluppo-e-test.md) - Test multi-IP, geolocalizzazione, rate limiting, CI/CD, debug API
- [Incident Response](docs/09-scenari-operativi/incident-response.md) - IP leak recovery, guard compromesso, exit malevolo, monitoring

### docs/10-laboratorio-pratico/
Esercizi pratici guidati passo a passo, dalla configurazione base all'isolamento avanzato.

- [Lab 01 - Setup e Verifica](docs/10-laboratorio-pratico/lab-01-setup-e-verifica.md) - Installazione completa, bootstrap, SocksPort, ControlPort, profilo Firefox
- [Lab 02 - Analisi Circuiti](docs/10-laboratorio-pratico/lab-02-analisi-circuiti.md) - Stem, nyx, ispezione circuiti, manipolazione con Python
- [Lab 03 - DNS Leak Testing](docs/10-laboratorio-pratico/lab-03-dns-leak-testing.md) - tcpdump, --socks5 vs --socks5-hostname, iptables anti-leak
- [Lab 04 - Onion Service](docs/10-laboratorio-pratico/lab-04-onion-service.md) - Onion Service v3, chiavi ed25519, autenticazione client x25519, hardening
- [Lab 05 - Stream Isolation](docs/10-laboratorio-pratico/lab-05-stream-isolation.md) - SocksPort multipli, multi-istanza Tor, identità separate

### [Glossario](docs/glossario.md)
Terminologia tecnica: celle, circuiti, handshake, flag, strumenti, attacchi.

---

## Config examples

| File | Descrizione |
|------|-------------|
| [torrc-client.example](config-examples/torrc/torrc-client.example) | Configurazione client con bridge obfs4 |
| [torrc.example](config-examples/torrc/torrc.example) | Template torrc di default con annotazioni |
| [torrc-relay.example](config-examples/torrc/torrc-relay.example) | Configurazione relay (middle, non exit) |
| [torrc-hidden-service.example](config-examples/torrc/torrc-hidden-service.example) | Configurazione onion service v3 |
| [torrc-bridge.example](config-examples/torrc/torrc-bridge.example) | Configurazione bridge server con obfs4 |
| [torrc-exit.example](config-examples/torrc/torrc-exit.example) | Configurazione exit node (reduced exit policy) |
| [proxychains4.conf.example](config-examples/proxychains/proxychains4.conf.example) | Configurazione ProxyChains per Tor |
| [transparent-proxy.sh.example](config-examples/iptables/transparent-proxy.sh.example) | Script iptables per transparent proxy |

## Scripts

| File | Descrizione |
|------|-------------|
| [newnym.example](scripts/newnym.example) | Rotazione IP via ControlPort (cookie auth) |
| [newnym-with-verify.sh.example](scripts/newnym-with-verify.sh.example) | NEWNYM con verifica cambio IP e retry |
| [check-dns-leak.sh.example](scripts/check-dns-leak.sh.example) | Test automatico DNS leak |
| [verify-tor-connection.sh.example](scripts/verify-tor-connection.sh.example) | Verifica completa stato Tor |
| [tor-circuit-info.py.example](scripts/tor-circuit-info.py.example) | Visualizza circuiti attivi (Python/Stem) |
| [tor-health-monitor.sh.example](scripts/tor-health-monitor.sh.example) | Monitoring continuo con notifiche |
| [setup-tor-profile.sh.example](scripts/setup-tor-profile.sh.example) | Crea profilo Firefox tor-proxy configurato |
| [tor-newip.sh.example](scripts/tor-newip.sh.example) | Rotazione IP continua con intervallo configurabile |

## Tests

| File | Descrizione |
|------|-------------|
| [validate-docs.sh](tests/validate-docs.sh) | Valida struttura e contenuto documentazione |
| [smoke-test-tor.sh](tests/smoke-test-tor.sh) | Smoke test completo funzionamento Tor |

## Setup

```bash
# Installazione completa automatica
sudo ./setup.sh
```

---

## Comandi rapidi

```bash
# Avviare Tor
sudo systemctl start tor@default.service

# Verificare il bootstrap
sudo journalctl -u tor@default.service | grep "Bootstrapped 100%"

# Verificare l'IP via Tor
proxychains curl https://api.ipify.org

# Cambiare IP (NEWNYM con verifica)
~/scripts/newnym-with-verify.sh

# Navigare via Tor (Firefox con profilo dedicato)
proxychains firefox -no-remote -P tor-proxy & disown

# Monitorare Tor in tempo reale
nyx
```

## Automazione

```bash
# Mostra comandi disponibili
make help

# Validare la documentazione (212 check)
make validate

# Smoke test Tor (richiede Tor attivo)
make smoke

# Statistiche del progetto
make stats

# Installazione completa
make setup
```

Vedi anche: [CHANGELOG.md](CHANGELOG.md) per la cronologia delle modifiche.

---

## Ambiente

- **OS**: Kali Linux (Debian-based)
- **Tor**: daemon + bridge obfs4 + ControlPort
- **Strumenti**: proxychains4, torsocks, nyx, curl, Firefox (profilo tor-proxy)
- **Localizzazione**: Parma, Italia

---

## Licenza

[MIT](LICENSE)
