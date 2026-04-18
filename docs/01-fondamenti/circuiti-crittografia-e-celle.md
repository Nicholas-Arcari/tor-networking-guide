> **Lingua / Language**: Italiano | [English](../en/01-fondamenti/circuiti-crittografia-e-celle.md)

# Circuiti, Crittografia e Celle - Il Protocollo Tor a Livello di Pacchetto

Questo documento approfondisce il funzionamento interno del protocollo Tor a livello di
celle, stream, crittografia simmetrica e asimmetrica. Non è una panoramica: è un'analisi
dettagliata di come i dati viaggiano attraverso la rete Tor, byte per byte.

Include osservazioni dalla mia esperienza pratica nell'analisi dei circuiti tramite
ControlPort, Nyx e log di debug.

---
---

## Indice

- [Gerarchia del protocollo Tor](#gerarchia-del-protocollo-tor)
- [Celle - L'unità atomica del protocollo Tor](#celle-lunità-atomica-del-protocollo-tor)
- [Celle RELAY - Il cuore del trasporto dati](#celle-relay-il-cuore-del-trasporto-dati)
**Approfondimenti** (file dedicati):
- [Crittografia e Handshake](crittografia-e-handshake.md) - AES-128-CTR strato per strato, SENDME flow control, ntor
- [Stream, Padding e Pratica](stream-padding-e-pratica.md) - RELAY_BEGIN, padding anti traffic analysis, osservazione circuiti


## Gerarchia del protocollo Tor

Il protocollo Tor opera su diversi livelli sovrapposti:

```
┌─────────────────────────────────────────────────┐
│ Livello 5: Stream (connessioni TCP applicative) │
│   → curl, browser, SSH, ogni connessione SOCKS  │
├─────────────────────────────────────────────────┤
│ Livello 4: Circuito (tunnel multi-hop cifrato)  │
│   → 3 nodi, chiavi negoziate, multiplexing      │
├─────────────────────────────────────────────────┤
│ Livello 3: Celle (unità di trasporto fisse)     │
│   → 514 byte ciascuna, comandi tipizzati        │
├─────────────────────────────────────────────────┤
│ Livello 2: Connessione TLS (link tra relay)     │
│   → TLS 1.2/1.3 con forward secrecy             │
├─────────────────────────────────────────────────┤
│ Livello 1: TCP (trasporto di rete)              │
│   → connessioni TCP persistenti tra relay        │
└─────────────────────────────────────────────────┘
```

### Relazione tra i livelli

- **Una connessione TCP** tra due relay trasporta **una connessione TLS**.
- **Una connessione TLS** multiplica **centinaia di circuiti** (identificati da CircID).
- **Un circuito** multiplica **decine di stream** (identificati da StreamID).
- **Uno stream** corrisponde a **una connessione TCP** applicativa (es. una richiesta HTTP).

---

## Celle - L'unità atomica del protocollo Tor

### Struttura completa di una cella

Ogni cella Tor è **esattamente 514 byte**. Nessuna eccezione. Questa dimensione fissa
è fondamentale per la resistenza alla traffic analysis: un osservatore non può
distinguere il tipo di cella basandosi sulla dimensione.

```
Cella standard (514 byte):
┌──────────┬──────────┬───────────────────────────────────────────┐
│ CircID   │ Command  │ Payload                                   │
│ 4 byte   │ 1 byte   │ 509 byte                                  │
└──────────┴──────────┴───────────────────────────────────────────┘

Cella variabile (per versioni link protocol ≥ 4):
┌──────────┬──────────┬──────────┬────────────────────────────────┐
│ CircID   │ Command  │ Length   │ Payload                        │
│ 4 byte   │ 1 byte   │ 2 byte   │ variabile                      │
└──────────┴──────────┴──────────┴────────────────────────────────┘
```

Le celle variabili sono usate solo per comandi specifici (VERSIONS, VPADDING, AUTH_CHALLENGE,
CERTS, AUTHENTICATE, AUTHORIZE). Il traffico dati usa sempre celle fisse da 514 byte.

### CircID - Circuit Identifier

Il CircID è un identificatore locale alla connessione TLS tra due nodi. NON è globale:
lo stesso circuito ha CircID diversi su ogni hop.

```
Client ←→ Guard: CircID = 0x00000A3F
Guard ←→ Middle: CircID = 0x00005B12
Middle ←→ Exit:  CircID = 0x000023C7
```

Ogni nodo mantiene una tabella di mapping:
```
Guard: CircID 0x00000A3F (dal client) → CircID 0x00005B12 (verso il middle)
```

Questo impedisce a un osservatore di correlare il traffico tra due hop diversi
basandosi sul CircID.

### Comandi di cella - Catalogo completo

#### Celle di circuito (non cifrate a livello relay)

| Comando | Byte | Direzione | Descrizione |
|---------|------|-----------|-------------|
| PADDING | 0 | bidirezionale | Padding per anti traffic analysis. Ignorata dal destinatario |
| CREATE | 1 | client→relay | Crea circuito (handshake TAP - deprecato) |
| CREATED | 2 | relay→client | Risposta a CREATE |
| RELAY | 3 | bidirezionale | Trasporta dati e comandi relay cifrati |
| DESTROY | 4 | bidirezionale | Distrugge un circuito |
| CREATE_FAST | 5 | client→relay | Creazione rapida (solo per il primo hop) |
| CREATED_FAST | 6 | relay→client | Risposta a CREATE_FAST |
| VERSIONS | 7 | bidirezionale | Negoziazione versione link protocol |
| NETINFO | 8 | bidirezionale | Scambio info sulla rete (timestamp, indirizzi) |
| RELAY_EARLY | 9 | client→relay | Come RELAY ma conta per limitare estensioni |
| CREATE2 | 10 | client→relay | Crea circuito (handshake ntor - attuale) |
| CREATED2 | 11 | relay→client | Risposta a CREATE2 |
| PADDING_NEGOTIATE | 12 | bidirezionale | Negoziazione parametri di padding |
| VPADDING | 128 | bidirezionale | Padding a lunghezza variabile |
| CERTS | 129 | relay→client | Certificati del relay |
| AUTH_CHALLENGE | 130 | relay→client | Challenge per autenticazione relay |
| AUTHENTICATE | 131 | client→relay | Risposta di autenticazione |

#### RELAY_EARLY e il limite di estensione

Le celle `RELAY_EARLY` hanno lo stesso formato delle celle `RELAY`, ma il guard
le conta. Un circuito può avere al massimo **8 celle RELAY_EARLY**. Questo impedisce
a un client malevolo di creare circuiti con troppi hop (che potrebbero essere usati
per amplificazione di traffico o per deanonimizzazione).

Ogni `EXTEND2` durante la costruzione del circuito usa una cella `RELAY_EARLY`.
Con 3 hop standard, ne servono 2 (guard→middle e middle→exit). Per circuiti a 4 hop
(es. hidden services) ne servono 3.

---

## Celle RELAY - Il cuore del trasporto dati

Le celle RELAY trasportano tutto il traffico applicativo. Il payload di una cella
RELAY (cifrata) ha questa struttura:

```
Payload RELAY (509 byte):
┌───────────┬────────────┬──────────┬──────────┬───────────┬──────────┐
│ RelayCmd   │ Recognized │ StreamID │ Digest   │ Length    │ Data     │
│ 1 byte     │ 2 byte     │ 2 byte   │ 4 byte   │ 2 byte   │ 498 byte │
└───────────┴────────────┴──────────┴──────────┴───────────┴──────────┘
```

### Campo per campo

**RelayCmd** - Il tipo di comando relay:

| Comando | Byte | Descrizione |
|---------|------|-------------|
| RELAY_BEGIN | 1 | Apre stream TCP: `hostname:port\0` nel data |
| RELAY_DATA | 2 | Trasporta dati applicativi |
| RELAY_END | 3 | Chiude stream con codice motivo |
| RELAY_CONNECTED | 4 | Conferma apertura stream |
| RELAY_SENDME | 5 | Flow control: permette invio di più dati |
| RELAY_EXTEND | 6 | Estende circuito (TAP - deprecato) |
| RELAY_EXTENDED | 7 | Risposta a EXTEND |
| RELAY_TRUNCATE | 8 | Tronca circuito a un certo punto |
| RELAY_TRUNCATED | 9 | Conferma troncamento |
| RELAY_DROP | 10 | Cella da ignorare (usata per padding) |
| RELAY_RESOLVE | 11 | Richiesta DNS resolution |
| RELAY_RESOLVED | 12 | Risposta DNS |
| RELAY_BEGIN_DIR | 13 | Apre stream verso directory del relay |
| RELAY_EXTEND2 | 14 | Estende circuito (ntor) |
| RELAY_EXTENDED2 | 15 | Risposta a EXTEND2 |

**Recognized** - Quando un nodo intermedio riceve una cella RELAY, decifra il suo
strato. Se `Recognized == 0` E il `Digest` è corretto, la cella è destinata a lui.
Altrimenti, la cella è per un hop successivo e viene inoltrata.

**StreamID** - Identifica lo stream all'interno del circuito. Valore 0 è riservato
per comandi che riguardano l'intero circuito (non uno stream specifico), come
EXTEND2, EXTENDED2, SENDME a livello circuito.

**Digest** - Running digest (SHA-1, troncato a 4 byte) calcolato su tutte le celle
precedenti dello stream. Serve per verificare integrità e per il riconoscimento
(insieme a Recognized). SHA-1 è usato qui per compatibilità storica; la sicurezza
del circuito si basa su AES-CTR e sulla key derivation, non su questo hash.

**Length** - Lunghezza effettiva dei dati nel campo Data. Massimo 498 byte. Il resto
del campo Data è padding (zeri).

---


> **Continua in**: [Crittografia e Handshake](crittografia-e-handshake.md) per la cifratura
> strato per strato, e in [Stream, Padding e Pratica](stream-padding-e-pratica.md) per
> l'apertura degli stream, il padding e l'osservazione pratica dei circuiti.

---

## Vedi anche

- [Crittografia e Handshake](crittografia-e-handshake.md) - AES-128-CTR, SENDME, ntor Curve25519
- [Stream, Padding e Pratica](stream-padding-e-pratica.md) - RELAY_BEGIN, padding, osservazione circuiti
- [Architettura di Tor](architettura-tor.md) - Panoramica componenti
- [Costruzione Circuiti](costruzione-circuiti.md) - Path selection, CREATE2/EXTEND2
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
