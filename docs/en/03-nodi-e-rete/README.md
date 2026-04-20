> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/README.md) | English

# Section 03 - Nodes and Network

Guard, middle, exit, bridge, onion services: role of each node type in the Tor network,
relay monitoring, and network metrics.

---

## Documents

### Node types

| Document | Content |
|----------|---------|
| [Guard Nodes](guard-nodes.md) | First hop, persistence, state file, vanguards, attacks |
| [Middle Relay](middle-relay.md) | Second hop, bandwidth weights, selection, contributing to the network |
| [Exit Nodes](exit-nodes.md) | Last hop, exit policy, risks, IP verification |
| [Exit Nodes in Practice](exit-nodes-pratica.md) | Blocks/CAPTCHAs, DNS from exit, selectivity, identification |

### Bridges and anti-censorship

| Document | Content |
|----------|---------|
| [Bridges and Pluggable Transports](bridges-e-pluggable-transports.md) | Why bridges, protocol, obfs4, censorship resistance, how to obtain them |
| [Bridge Configuration and Alternatives](bridge-configurazione-e-alternative.md) | torrc config, meek (CDN), Snowflake (P2P), transport comparison |

### Onion services

| Document | Content |
|----------|---------|
| [Onion Services v3](onion-services-v3.md) | Architecture, Ed25519 cryptography, configuration, security |

### Monitoring and metrics

| Document | Content |
|----------|---------|
| [Relay Monitoring and Metrics](relay-monitoring-e-metriche.md) | Tor Metrics, relay metrics, ControlPort and Stem |
| [Advanced Monitoring](monitoring-avanzato.md) | Prometheus/Grafana, bandwidth accounting, Relay Search, OONI, scripts |

### Operational scenarios

| Document | Content |
|----------|---------|
| [Real-World Scenarios](scenari-reali.md) | Practical cases from a pentester: malicious exits, bridges under DPI, guard analysis |

---

## Recommended reading path

```
guard-nodes.md
middle-relay.md
exit-nodes.md
  └── exit-nodes-pratica.md
bridges-e-pluggable-transports.md
  └── bridge-configurazione-e-alternative.md
onion-services-v3.md
relay-monitoring-e-metriche.md
  └── monitoring-avanzato.md
```

---

## Related sections

- [01 - Fundamentals](../01-fondamenti/) - Consensus, flags, and relay selection
- [02 - Installation and Configuration](../02-installazione-e-configurazione/) - torrc for bridges, relays, exit policies
- [04 - Operational Tools](../04-strumenti-operativi/) - Nyx for node monitoring
- [07 - Limitations and Attacks](../07-limitazioni-e-attacchi/) - Attacks on nodes, Sybil, correlation
