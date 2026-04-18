> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/README.md) | English

# Section 02 - Installation and Configuration

Installing Tor on Debian/Kali, complete torrc configuration,
systemd service management, and operational maintenance.

---

## Documents

### Installation

| Document | Contents |
|----------|----------|
| [Installation and Verification](installazione-e-verifica.md) | Prerequisites, packages, binary and permission verification |
| [Initial Configuration](configurazione-iniziale.md) | Minimal torrc, debian-tor group, Firefox profile |
| [Troubleshooting and Structure](troubleshooting-e-struttura.md) | Common issues, installed file map, upgrading |

### torrc Configuration

| Document | Contents |
|----------|----------|
| [torrc - Complete Guide](torrc-guida-completa.md) | Structure and syntax, ports (SocksPort, DNSPort, ControlPort), logging |
| [Bridge and Security in torrc](torrc-bridge-e-sicurezza.md) | Bridge obfs4, pluggable transports, ExitNodes, ExcludeNodes, padding |
| [Performance, Relay and Full Config](torrc-performance-e-relay.md) | Timeout, guard, relay, hidden services, annotated torrc |

### Service Management

| Document | Contents |
|----------|----------|
| [Service Management](gestione-del-servizio.md) | systemd, logs, bootstrap, debugging common issues |
| [Maintenance and Monitoring](manutenzione-e-monitoraggio.md) | Unix signals, health checks, cache cleanup, post-install verification |

### Operational Scenarios

| Document | Contents |
|----------|----------|
| [Real-World Scenarios](scenari-reali.md) | Practical pentester cases: field configuration, operational troubleshooting |

---

## Recommended reading path

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

## Related sections

- [01 - Fundamentals](../01-fondamenti/) - Required theory before installation
- [03 - Nodes and Network](../03-nodi-e-rete/) - Bridges, relays, exits: what gets configured in the torrc
- [04 - Operational Tools](../04-strumenti-operativi/) - ProxyChains, torsocks, nyx after installation
- [10 - Hands-on Lab](../10-laboratorio-pratico/) - Lab-01 (setup and verification) applies this section
