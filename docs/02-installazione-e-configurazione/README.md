> **Lingua / Language**: Italiano | [English](../en/02-installazione-e-configurazione/README.md)

# Sezione 02 - Installazione e Configurazione

Installazione di Tor su Debian/Kali, configurazione completa del torrc,
gestione del servizio systemd e manutenzione operativa.

---

## Documenti

### Installazione

| Documento | Contenuto |
|-----------|-----------|
| [Installazione e Verifica](installazione-e-verifica.md) | Prerequisiti, pacchetti, verifica binari e permessi |
| [Configurazione Iniziale](configurazione-iniziale.md) | Torrc minimo, gruppo debian-tor, profilo Firefox |
| [Troubleshooting e Struttura](troubleshooting-e-struttura.md) | Problemi comuni, mappa file installati, aggiornamento |

### Configurazione torrc

| Documento | Contenuto |
|-----------|-----------|
| [torrc - Guida Completa](torrc-guida-completa.md) | Struttura e sintassi, porte (SocksPort, DNSPort, ControlPort), logging |
| [Bridge e Sicurezza nel torrc](torrc-bridge-e-sicurezza.md) | Bridge obfs4, pluggable transports, ExitNodes, ExcludeNodes, padding |
| [Performance, Relay e Config Completa](torrc-performance-e-relay.md) | Timeout, guard, relay, hidden services, torrc commentato |

### Gestione del servizio

| Documento | Contenuto |
|-----------|-----------|
| [Gestione del Servizio](gestione-del-servizio.md) | systemd, log, bootstrap, debug problemi comuni |
| [Manutenzione e Monitoraggio](manutenzione-e-monitoraggio.md) | Segnali Unix, health check, pulizia cache, verifica post-install |

### Scenari operativi

| Documento | Contenuto |
|-----------|-----------|
| [Scenari Reali](scenari-reali.md) | Casi pratici da pentester: configurazione in campo, troubleshooting operativo |

---

## Percorso di lettura consigliato

```
installazione-e-verifica.md
  ├── configurazione-iniziale.md
  └── troubleshooting-e-struttura.md
torrc-guida-completa.md
  ├── torrc-bridge-e-sicurezza.md
  └── torrc-performance-e-relay.md
gestione-del-servizio.md
  └── manutenzione-e-monitoraggio.md
```

---

## Sezioni correlate

- [01 - Fondamenti](../01-fondamenti/) - Teoria necessaria prima dell'installazione
- [03 - Nodi e Rete](../03-nodi-e-rete/) - Bridge, relay, exit: cosa si configura nel torrc
- [04 - Strumenti Operativi](../04-strumenti-operativi/) - ProxyChains, torsocks, nyx dopo l'installazione
- [10 - Laboratorio Pratico](../10-laboratorio-pratico/) - Lab-01 (setup e verifica) applica questa sezione
