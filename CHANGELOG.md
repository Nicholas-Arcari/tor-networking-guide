# Changelog

Tutte le modifiche rilevanti al progetto sono documentate in questo file.

Il formato segue [Keep a Changelog](https://keepachangelog.com/it/1.1.0/).
Questo progetto usa versionamento basato su data.

## [Non rilasciato]

### Aggiunto
- Localizzazione inglese completa: `docs/en/` con 99 documenti tradotti (mirror integrale)
- Language switcher (Italiano | English) su tutti i 98 documenti italiani e 99 inglesi
- `docs/en/README.md` come hub di navigazione inglese
- Glossario inglese (`docs/en/glossario.md`) con 60+ termini tecnici
- Sezione `docs/10-laboratorio-pratico/` con 5 esercizi pratici (lab-01 a lab-05)
- Split file dedicati per sezioni 01-08 (hub + approfondimento per ogni documento >500 righe)
- README indice per tutte le 10 sezioni con tabelle categorizzate
- Scenari reali (3-5 casi operativi da senior pentester) per tutte le 10 sezioni
- Diagrammi Mermaid e cheat sheet nei documenti chiave
- Cross-reference (`## Vedi anche`) e indici (`## Indice`) in tutti i documenti
- CI/CD: GitHub Action per validazione automatica su push/PR
- Makefile con target: validate, test, smoke, stats, lint, setup, clean
- CHANGELOG.md (questo file)

### Modificato
- `tests/validate-docs.sh`: aggiornato con check documenti EN (esistenza, H1, H2, cross-ref)
- `Makefile`: target `stats` con conteggi separati IT/EN
- `README.md`: aggiunto language selector verso versione inglese
- Hub files troncati con puntatore "Continua in" verso file dedicati
- Indice dei documenti aggiornato con sezione "Approfondimenti (file dedicati)"

## [2026-04-04]

### Aggiunto
- Struttura completa del progetto: 10 sezioni, 40 documenti
- Sezione 01 - Fondamenti: architettura Tor, circuiti/crittografia, consenso e directory authorities
- Sezione 02 - Installazione: guida installazione, torrc completa, gestione servizio systemd
- Sezione 03 - Nodi: guard, middle, exit, bridges/pluggable transports, onion services v3, monitoring relay
- Sezione 04 - Strumenti: proxychains, torsocks, ControlPort/NEWNYM, verifica leak, nyx, Tor Browser, DNS
- Sezione 05 - Sicurezza: DNS leak, traffic analysis, fingerprinting, OPSEC, isolamento, hardening, forense
- Sezione 06 - Avanzate: VPN+Tor, transparent proxy, multi-istanza/stream isolation, localhost
- Sezione 07 - Limitazioni: protocollo, applicazioni, attacchi noti
- Sezione 08 - Legale: aspetti legali Italia/UE, etica e responsabilita
- Sezione 09 - Scenari: ricognizione anonima, comunicazione sicura, sviluppo/test, incident response
- Glossario con 60+ termini tecnici
- 8 script operativi (`.example`) in `scripts/`
- 6 config di esempio in `config-examples/` (torrc, proxychains, iptables)
- `setup.sh` - installazione automatica completa
- `tests/validate-docs.sh` - validazione struttura documentazione (188 check)
- `tests/smoke-test-tor.sh` - smoke test runtime Tor (10 sezioni, SOCKS5, ControlPort, DNS)
- README.md con struttura completa e comandi rapidi
- Licenza MIT

## [2025-12-04]

### Aggiunto
- Note iniziali sulle limitazioni di Tor
- Primi contenuti sulla rete e il protocollo

## [2025-12-03]

### Aggiunto
- Commit iniziale - struttura base del progetto
