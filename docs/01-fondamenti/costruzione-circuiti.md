> **Lingua / Language**: Italiano | [English](../en/01-fondamenti/costruzione-circuiti.md)

# Costruzione dei Circuiti - Path Selection, ntor Handshake e Trasmissione Dati

Come Tor seleziona i nodi, negozia le chiavi crittografiche con CREATE2/EXTEND2,
e trasmette dati cifrati strato per strato attraverso il circuito.

Estratto dalla sezione [Architettura di Tor](architettura-tor.md) per approfondimento.

---

## Indice

- [Come Tor costruisce un circuito](#come-tor-costruisce-un-circuito--dettaglio-protocollo)
- [Celle Tor - L'unità di trasporto](#celle-tor--lunità-di-trasporto)
- [Connessioni TLS tra relay](#connessioni-tls-tra-relay)

---

## Come Tor costruisce un circuito - Dettaglio protocollo

La costruzione di un circuito è il cuore dell'architettura Tor. Ecco cosa succede
realmente a livello di protocollo:

### Fase 1: Selezione dei nodi

L'algoritmo di path selection opera così:

1. **Guard selection**: il client mantiene un set di 1-3 guard persistenti (salvati
   nel file `state` in `/var/lib/tor/state`). Se non ne ha, ne seleziona dal consenso
   tra i relay con flag `Guard` + `Stable` + `Fast`. La selezione è pesata per bandwidth.

2. **Exit selection**: tra i relay con flag `Exit`, Tor sceglie quelli la cui exit policy
   permette la porta di destinazione richiesta. Se vuoi raggiungere la porta 443,
   servono exit che accettano `:443`. Anche qui la selezione è pesata per bandwidth.

3. **Middle selection**: qualsiasi relay che non sia il guard o l'exit selezionato.
   La selezione è pesata per bandwidth. Tor evita di selezionare due nodi nella stessa
   `/16` subnet o nella stessa famiglia dichiarata.

### Fase 2: Creazione del circuito (CREATE2 → CREATED2 → EXTEND2 → EXTENDED2)

```
Client                   Guard                   Middle                  Exit
  |                        |                       |                      |
  |--- CREATE2 ----------->|                       |                      |
  |    (ntor handshake     |                       |                      |
  |     client→guard)      |                       |                      |
  |                        |                       |                      |
  |<-- CREATED2 ---------- |                       |                      |
  |    (guard→client       |                       |                      |
  |     handshake done)    |                       |                      |
  |                        |                       |                      |
  | Ora: chiave condivisa con Guard (Kf_guard, Kb_guard)                  |
  |                        |                       |                      |
  |--- RELAY_EARLY ------->|--- EXTEND2 --------->|                      |
  |    {EXTEND2 cifrato    |    (ntor handshake    |                      |
  |     con Kf_guard}      |     client→middle)    |                      |
  |                        |                       |                      |
  |<-- RELAY --------------|<-- EXTENDED2 ---------|                      |
  |    {EXTENDED2 cifrato  |    (middle→client     |                      |
  |     con Kb_guard}      |     handshake done)   |                      |
  |                        |                       |                      |
  | Ora: chiave condivisa anche con Middle (Kf_middle, Kb_middle)         |
  |                        |                       |                      |
  |--- RELAY_EARLY ------->|--- RELAY ------------>|--- EXTEND2 -------->|
  |    {EXTEND2 cifrato    |    {EXTEND2 cifrato   |    (ntor handshake  |
  |     2 strati}          |     1 strato}         |     client→exit)    |
  |                        |                       |                      |
  |<-- RELAY --------------|<-- RELAY -------------|<-- EXTENDED2 -------|
  |    {EXTENDED2 cifrato  |    {EXTENDED2 cifrato |    (exit→client     |
  |     2 strati}          |     1 strato}         |     handshake done) |
  |                        |                       |                      |
  | Ora: 3 chiavi condivise indipendenti                                  |
```

#### Dettaglio dell'handshake ntor

L'handshake ntor è il meccanismo crittografico che Tor usa per negoziare chiavi con
ogni nodo del circuito. Usa:

- **Curve25519** - per il Diffie-Hellman su curva ellittica
- **HMAC-SHA256** - per la derivazione delle chiavi
- **HKDF** (HMAC-based Key Derivation Function) - per generare le chiavi simmetriche
  finali

Il processo per ogni hop:

1. Il client genera una coppia ephemeral Curve25519 (x, X = x*G)
2. Il client conosce la chiave onion pubblica del relay (B) dal consenso
3. Il client invia X nella cella CREATE2/EXTEND2
4. Il relay ha la chiave privata b corrispondente a B
5. Il relay genera la sua coppia ephemeral (y, Y = y*G)
6. Entrambi calcolano: secret = x*Y = y*X (proprietà ECDH)
7. Dalla secret vengono derivate le chiavi simmetriche tramite HKDF:
   - `Kf` - chiave per cifratura forward (client → relay)
   - `Kb` - chiave per cifratura backward (relay → client)
   - `Df`, `Db` - digest per integrità

Le chiavi risultanti sono usate con **AES-128-CTR** per la cifratura simmetrica dei dati.

### Fase 3: Trasmissione dati

Quando il circuito è pronto e un'applicazione invia dati:

1. **Il client cifra 3 volte**: prima con la chiave dell'Exit, poi del Middle, poi
   del Guard. I dati sono wrappati in celle RELAY_DATA.

2. **Il Guard decifra il primo strato** e inoltra al Middle.

3. **Il Middle decifra il secondo strato** e inoltra all'Exit.

4. **L'Exit decifra il terzo strato** e vede i dati in chiaro (a meno che non siano
   HTTPS/TLS, nel qual caso vede il traffico TLS cifrato verso la destinazione).

5. **Al ritorno**: l'Exit cifra con la sua chiave, il Middle aggiunge il suo strato,
   il Guard aggiunge il suo. Il client decifra tutti e 3 gli strati.

---

## Celle Tor - L'unità di trasporto

Tutto il traffico Tor è trasportato in **celle** di dimensione fissa: **514 byte**.
La dimensione fissa è una scelta anti-traffic-analysis: un osservatore non può
distinguere il tipo di cella dalla sua dimensione.

### Struttura di una cella

```
+----------+----------+------------------------------------------+
| CircID   | Command  | Payload                                  |
| (4 byte) | (1 byte) | (509 byte)                               |
+----------+----------+------------------------------------------+
```

- **CircID** (Circuit ID): identifica il circuito sulla connessione TLS tra due nodi.
  Ogni connessione TLS tra due relay può trasportare centinaia di circuiti, ognuno con
  il suo CircID.

- **Command**: tipo di cella. I principali:

  | Comando | Valore | Descrizione |
  |---------|--------|-------------|
  | PADDING | 0 | Cella di padding (anti traffic analysis) |
  | CREATE2 | 10 | Inizio creazione circuito |
  | CREATED2 | 11 | Risposta a CREATE2 |
  | RELAY | 3 | Cella relay (trasporta dati e comandi relay) |
  | RELAY_EARLY | 9 | Come RELAY ma usata solo durante l'estensione del circuito |
  | DESTROY | 4 | Distrugge un circuito |

### Celle RELAY - Il sottosistema di trasporto

Le celle RELAY hanno un payload strutturato:

```
+-----------+-----------+----------+---------+---------------------+
| RelayCmd  | Recognized| StreamID | Digest  | Data                |
| (1 byte)  | (2 byte)  | (2 byte) | (4 byte)| (498 byte)         |
+-----------+-----------+----------+---------+---------------------+
```

- **RelayCmd**: il tipo di comando relay:

  | Comando | Descrizione |
  |---------|-------------|
  | RELAY_BEGIN | Apre un nuovo stream TCP verso una destinazione |
  | RELAY_DATA | Trasporta dati del stream |
  | RELAY_END | Chiude uno stream |
  | RELAY_CONNECTED | Conferma che lo stream è connesso |
  | RELAY_RESOLVE | Risolve un hostname |
  | RELAY_RESOLVED | Risposta a RESOLVE |
  | RELAY_BEGIN_DIR | Apre uno stream verso la directory del relay |
  | RELAY_EXTEND2 | Estende il circuito a un nuovo hop |
  | RELAY_EXTENDED2 | Conferma l'estensione |

- **StreamID**: identifica lo stream specifico all'interno del circuito. Un circuito
  può avere molti stream attivi contemporaneamente (es. più tab del browser sullo
  stesso circuito).

- **Recognized + Digest**: usati per verificare che la cella sia destinata a questo
  nodo. Ogni nodo intermedio vede `Recognized` diverso da zero (cella non per lui)
  e la inoltra. Solo il destinatario finale vede `Recognized = 0` e il digest corretto.

---

## Connessioni TLS tra relay

Tutti i relay Tor comunicano tra loro tramite connessioni TLS persistenti. Queste
connessioni:

- **Sono multiplexate**: una singola connessione TLS tra due relay può trasportare
  centinaia di circuiti di utenti diversi.

- **Usano TLS 1.3** (o 1.2 minimo): con ciphersuite negoziate che includono forward
  secrecy (ECDHE).

- **Hanno un handshake speciale**: Tor usa un protocollo di autenticazione in-band
  dove i relay si scambiano le loro chiavi d'identità Ed25519 dopo il TLS handshake.
  Questo permette a Tor di nascondere l'identità del relay a osservatori passivi
  (il certificato TLS non contiene l'identità del relay).

### Implicazione: cosa vede l'ISP

Quando il mio client Tor si connette al Guard Node, il mio ISP vede:

1. Una connessione TLS verso l'IP del Guard (o del bridge se uso obfs4)
2. Il certificato TLS del Guard - che **non** contiene identificatori Tor espliciti
   (ma le DA pubblicano la lista degli IP, quindi l'ISP può correlare)
3. Con obfs4: nemmeno questo. Il traffico appare come rumore casuale.

Nella mia esperienza a Parma, il mio ISP (Comeser) non ha mai mostrato segni di
interferenza con Tor diretto. Ma su reti universitarie, i firewall bloccavano le
connessioni ai relay noti, rendendo i bridge obfs4 necessari.


---

## Vedi anche

- [Architettura di Tor](architettura-tor.md) - Panoramica e componenti
- [Isolamento e Modello di Minaccia](isolamento-e-modello-minaccia.md) - Stream isolation, threat model
- [Crittografia e Handshake](crittografia-e-handshake.md) - ntor, AES-128-CTR, SENDME flow control
- [Consenso e Directory Authorities](consenso-e-directory-authorities.md) - Come vengono selezionati i relay
