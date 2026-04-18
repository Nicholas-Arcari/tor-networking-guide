> **Lingua / Language**: [Italiano](../../01-fondamenti/README.md) | English

# Section 01 - Tor Network Fundamentals

Architecture, protocol, cryptography and consensus: the theoretical and operational
foundations for understanding Tor's internal workings.

---

## Documents

### Architecture and components

| Document | Content |
|----------|---------|
| [Tor Architecture](architettura-tor.md) | Components (OP, DA, relays, bridges), bootstrap, network overview |
| [Circuit Construction](costruzione-circuiti.md) | Path selection, CREATE2/EXTEND2, ntor handshake, cells and TLS |
| [Isolation and Threat Model](isolamento-e-modello-minaccia.md) | Stream isolation, circuit lifecycle, threat model |

### Protocol and cryptography

| Document | Content |
|----------|---------|
| [Circuits, Cryptography and Cells](circuiti-crittografia-e-celle.md) | Protocol hierarchy, 514-byte cells, RELAY cells, CircID |
| [Cryptography and Handshake](crittografia-e-handshake.md) | AES-128-CTR layer by layer, SENDME flow control, ntor Curve25519 |
| [Streams, Padding and Practice](stream-padding-e-pratica.md) | RELAY_BEGIN, anti traffic analysis padding, circuit observation |

### Consensus and directory

| Document | Content |
|----------|---------|
| [Consensus and Directory Authorities](consenso-e-directory-authorities.md) | Why consensus, the 9 DAs, voting process |
| [Consensus Structure and Flags](struttura-consenso-e-flag.md) | Document format, flags (Guard, Exit, Stable, Fast), bandwidth auth |
| [Descriptors, Cache and Attacks](descriptor-cache-e-attacchi.md) | Server descriptors, microdescriptors, local cache, consensus attacks |

### Operational scenarios

| Document | Content |
|----------|---------|
| [Real-World Scenarios](scenari-reali.md) | Pentesting cases: circuit analysis, consensus verification, malicious relays |

---

## Recommended reading path

```
architettura-tor.md
  +-- costruzione-circuiti.md
  |     +-- isolamento-e-modello-minaccia.md
  +-- circuiti-crittografia-e-celle.md
  |     +-- crittografia-e-handshake.md
  |     +-- stream-padding-e-pratica.md
  +-- consenso-e-directory-authorities.md
        +-- struttura-consenso-e-flag.md
        +-- descriptor-cache-e-attacchi.md
```

Start with `architettura-tor.md` for the overview, then follow the "Continues in"
links in each document for deeper dives.

---

## Related sections

- [02 - Installation and Configuration](../02-installazione-e-configurazione/) - Putting the fundamentals into practice
- [03 - Nodes and Network](../03-nodi-e-rete/) - Guard, middle, exit, bridge, onion services
- [07 - Limitations and Attacks](../07-limitazioni-e-attacchi/) - Protocol limitations and known attacks
- [10 - Practical Lab](../10-laboratorio-pratico/) - Lab-02 (circuit analysis) directly applies these fundamentals
