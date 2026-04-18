> **Lingua / Language**: Italiano | [English](../en/01-fondamenti/README.md)

# Sezione 01 - Fondamenti della Rete Tor

Architettura, protocollo, crittografia e consenso: le basi teoriche e operative
per comprendere il funzionamento interno di Tor.

---

## Documenti

### Architettura e componenti

| Documento | Contenuto |
|-----------|-----------|
| [Architettura di Tor](architettura-tor.md) | Componenti (OP, DA, relay, bridge), bootstrap, panoramica della rete |
| [Costruzione Circuiti](costruzione-circuiti.md) | Path selection, CREATE2/EXTEND2, ntor handshake, celle e TLS |
| [Isolamento e Modello di Minaccia](isolamento-e-modello-minaccia.md) | Stream isolation, ciclo di vita dei circuiti, threat model |

### Protocollo e crittografia

| Documento | Contenuto |
|-----------|-----------|
| [Circuiti, Crittografia e Celle](circuiti-crittografia-e-celle.md) | Gerarchia del protocollo, celle 514 byte, RELAY cells, CircID |
| [Crittografia e Handshake](crittografia-e-handshake.md) | AES-128-CTR strato per strato, SENDME flow control, ntor Curve25519 |
| [Stream, Padding e Pratica](stream-padding-e-pratica.md) | RELAY_BEGIN, padding anti traffic analysis, osservazione circuiti |

### Consenso e directory

| Documento | Contenuto |
|-----------|-----------|
| [Consenso e Directory Authorities](consenso-e-directory-authorities.md) | Perché il consenso, le 9 DA, processo di votazione |
| [Struttura Consenso e Flag](struttura-consenso-e-flag.md) | Formato del documento, flag (Guard, Exit, Stable, Fast), bandwidth auth |
| [Descriptor, Cache e Attacchi](descriptor-cache-e-attacchi.md) | Server descriptor, microdescriptor, cache locale, attacchi al consenso |

### Scenari operativi

| Documento | Contenuto |
|-----------|-----------|
| [Scenari Reali](scenari-reali.md) | Casi pratici da pentester: analisi circuiti, verifica consenso, relay malevoli |

---

## Percorso di lettura consigliato

```
architettura-tor.md
  ├── costruzione-circuiti.md
  │     └── isolamento-e-modello-minaccia.md
  ├── circuiti-crittografia-e-celle.md
  │     ├── crittografia-e-handshake.md
  │     └── stream-padding-e-pratica.md
  └── consenso-e-directory-authorities.md
        ├── struttura-consenso-e-flag.md
        └── descriptor-cache-e-attacchi.md
```

Iniziare da `architettura-tor.md` per la panoramica, poi seguire i link
"Continua in" di ogni documento per approfondire.

---

## Sezioni correlate

- [02 - Installazione e Configurazione](../02-installazione-e-configurazione/) - Mettere in pratica quanto appreso
- [03 - Nodi e Rete](../03-nodi-e-rete/) - Guard, middle, exit, bridge, onion services
- [07 - Limitazioni e Attacchi](../07-limitazioni-e-attacchi/) - Limiti del protocollo e attacchi noti
- [10 - Laboratorio Pratico](../10-laboratorio-pratico/) - Lab-02 (analisi circuiti) applica direttamente questi fondamenti
