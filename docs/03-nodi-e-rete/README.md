> **Lingua / Language**: Italiano | [English](../en/03-nodi-e-rete/README.md)

# Sezione 03 - Nodi e Rete

Guard, middle, exit, bridge, onion services: ruolo di ogni tipo di nodo nella rete Tor,
monitoraggio relay e metriche di rete.

---

## Documenti

### Tipi di nodo

| Documento | Contenuto |
|-----------|-----------|
| [Guard Nodes](guard-nodes.md) | Primo hop, persistenza, file state, vanguards, attacchi |
| [Middle Relay](middle-relay.md) | Secondo hop, bandwidth weights, selezione, contribuire alla rete |
| [Exit Nodes](exit-nodes.md) | Ultimo hop, exit policy, rischi, verifica IP |
| [Exit Nodes nella Pratica](exit-nodes-pratica.md) | Blocchi/CAPTCHA, DNS dall'exit, selettività, identificazione |

### Bridge e anti-censura

| Documento | Contenuto |
|-----------|-----------|
| [Bridges e Pluggable Transports](bridges-e-pluggable-transports.md) | Perché i bridge, protocollo, obfs4, resistenza censura, come ottenerne |
| [Configurazione Bridge e Alternative](bridge-configurazione-e-alternative.md) | Config torrc, meek (CDN), Snowflake (P2P), confronto transports |

### Onion services

| Documento | Contenuto |
|-----------|-----------|
| [Onion Services v3](onion-services-v3.md) | Architettura, crittografia Ed25519, configurazione, sicurezza |

### Monitoring e metriche

| Documento | Contenuto |
|-----------|-----------|
| [Relay Monitoring e Metriche](relay-monitoring-e-metriche.md) | Tor Metrics, metriche relay, ControlPort e Stem |
| [Monitoring Avanzato](monitoring-avanzato.md) | Prometheus/Grafana, bandwidth accounting, Relay Search, OONI, script |

### Scenari operativi

| Documento | Contenuto |
|-----------|-----------|
| [Scenari Reali](scenari-reali.md) | Casi pratici da pentester: exit malevoli, bridge sotto DPI, guard analysis |

---

## Percorso di lettura consigliato

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

## Sezioni correlate

- [01 - Fondamenti](../01-fondamenti/) - Consenso, flag e selezione dei relay
- [02 - Installazione e Configurazione](../02-installazione-e-configurazione/) - torrc per bridge, relay, exit policy
- [04 - Strumenti Operativi](../04-strumenti-operativi/) - Nyx per monitorare i nodi
- [07 - Limitazioni e Attacchi](../07-limitazioni-e-attacchi/) - Attacchi ai nodi, Sybil, correlation
