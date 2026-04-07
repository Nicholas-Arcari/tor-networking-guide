# Changelog

Tutte le modifiche rilevanti al progetto sono documentate in questo file.

Il formato segue [Keep a Changelog](https://keepachangelog.com/it/1.1.0/).
Questo progetto usa versionamento basato su data.

## [Non rilasciato]

### Aggiunto
- Sezione `docs/10-laboratorio-pratico/` con 5 esercizi pratici (lab-01 a lab-05)
- Diagrammi Mermaid e cheat sheet nei documenti chiave
- Cross-reference (`## Vedi anche`) e indici (`## Indice`) in tutti i 45 documenti
- CI/CD: GitHub Action per validazione automatica su push/PR
- Makefile con target: validate, test, smoke, stats, lint, setup, clean
- CHANGELOG.md (questo file)

### Modificato
- Espansi 10 documenti nelle sezioni 05, 06, 07, 08 (da ~150 a ~350+ righe ciascuno)
- `tests/validate-docs.sh`: aggiunto supporto per sezione 10 e glossario (~206 check)

## [2026-04-04]

### Aggiunto
- Struttura completa del progetto: 10 sezioni, 40 documenti
- Sezione 01 — Fondamenti: architettura Tor, circuiti/crittografia, consenso e directory authorities
- Sezione 02 — Installazione: guida installazione, torrc completa, gestione servizio systemd
- Sezione 03 — Nodi: guard, middle, exit, bridges/pluggable transports, onion services v3, monitoring relay
- Sezione 04 — Strumenti: proxychains, torsocks, ControlPort/NEWNYM, verifica leak, nyx, Tor Browser, DNS
- Sezione 05 — Sicurezza: DNS leak, traffic analysis, fingerprinting, OPSEC, isolamento, hardening, forense
- Sezione 06 — Avanzate: VPN+Tor, transparent proxy, multi-istanza/stream isolation, localhost
- Sezione 07 — Limitazioni: protocollo, applicazioni, attacchi noti
- Sezione 08 — Legale: aspetti legali Italia/UE, etica e responsabilita
- Sezione 09 — Scenari: ricognizione anonima, comunicazione sicura, sviluppo/test, incident response
- Glossario con 60+ termini tecnici
- 8 script operativi (`.example`) in `scripts/`
- 6 config di esempio in `config-examples/` (torrc, proxychains, iptables)
- `setup.sh` — installazione automatica completa
- `tests/validate-docs.sh` — validazione struttura documentazione (188 check)
- `tests/smoke-test-tor.sh` — smoke test runtime Tor (10 sezioni, SOCKS5, ControlPort, DNS)
- README.md con struttura completa e comandi rapidi
- Licenza MIT

## [2025-12-04]

### Aggiunto
- Note iniziali sulle limitazioni di Tor
- Primi contenuti sulla rete e il protocollo

## [2025-12-03]

### Aggiunto
- Commit iniziale — struttura base del progetto
