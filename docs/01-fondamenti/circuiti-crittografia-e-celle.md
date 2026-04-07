# Circuiti, Crittografia e Celle — Il Protocollo Tor a Livello di Pacchetto

Questo documento approfondisce il funzionamento interno del protocollo Tor a livello di
celle, stream, crittografia simmetrica e asimmetrica. Non è una panoramica: è un'analisi
dettagliata di come i dati viaggiano attraverso la rete Tor, byte per byte.

Include osservazioni dalla mia esperienza pratica nell'analisi dei circuiti tramite
ControlPort, Nyx e log di debug.

---
---

## Indice

- [Gerarchia del protocollo Tor](#gerarchia-del-protocollo-tor)
- [Celle — L'unità atomica del protocollo Tor](#celle-lunità-atomica-del-protocollo-tor)
- [Celle RELAY — Il cuore del trasporto dati](#celle-relay-il-cuore-del-trasporto-dati)
- [Crittografia dei circuiti — Strato per strato](#crittografia-dei-circuiti-strato-per-strato)
- [Flow Control — SENDME cells](#flow-control-sendme-cells)
- [Handshake ntor — Dettaglio crittografico](#handshake-ntor-dettaglio-crittografico)
- [Apertura di uno stream — RELAY_BEGIN → RELAY_CONNECTED](#apertura-di-uno-stream-relaybegin-relayconnected)
- [Padding e resistenza alla traffic analysis](#padding-e-resistenza-alla-traffic-analysis)
- [Distruzione di un circuito](#distruzione-di-un-circuito)
- [Osservare i circuiti nella pratica](#osservare-i-circuiti-nella-pratica)
- [Riepilogo delle garanzie crittografiche](#riepilogo-delle-garanzie-crittografiche)


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

## Celle — L'unità atomica del protocollo Tor

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

### CircID — Circuit Identifier

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

### Comandi di cella — Catalogo completo

#### Celle di circuito (non cifrate a livello relay)

| Comando | Byte | Direzione | Descrizione |
|---------|------|-----------|-------------|
| PADDING | 0 | bidirezionale | Padding per anti traffic analysis. Ignorata dal destinatario |
| CREATE | 1 | client→relay | Crea circuito (handshake TAP — deprecato) |
| CREATED | 2 | relay→client | Risposta a CREATE |
| RELAY | 3 | bidirezionale | Trasporta dati e comandi relay cifrati |
| DESTROY | 4 | bidirezionale | Distrugge un circuito |
| CREATE_FAST | 5 | client→relay | Creazione rapida (solo per il primo hop) |
| CREATED_FAST | 6 | relay→client | Risposta a CREATE_FAST |
| VERSIONS | 7 | bidirezionale | Negoziazione versione link protocol |
| NETINFO | 8 | bidirezionale | Scambio info sulla rete (timestamp, indirizzi) |
| RELAY_EARLY | 9 | client→relay | Come RELAY ma conta per limitare estensioni |
| CREATE2 | 10 | client→relay | Crea circuito (handshake ntor — attuale) |
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

## Celle RELAY — Il cuore del trasporto dati

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

**RelayCmd** — Il tipo di comando relay:

| Comando | Byte | Descrizione |
|---------|------|-------------|
| RELAY_BEGIN | 1 | Apre stream TCP: `hostname:port\0` nel data |
| RELAY_DATA | 2 | Trasporta dati applicativi |
| RELAY_END | 3 | Chiude stream con codice motivo |
| RELAY_CONNECTED | 4 | Conferma apertura stream |
| RELAY_SENDME | 5 | Flow control: permette invio di più dati |
| RELAY_EXTEND | 6 | Estende circuito (TAP — deprecato) |
| RELAY_EXTENDED | 7 | Risposta a EXTEND |
| RELAY_TRUNCATE | 8 | Tronca circuito a un certo punto |
| RELAY_TRUNCATED | 9 | Conferma troncamento |
| RELAY_DROP | 10 | Cella da ignorare (usata per padding) |
| RELAY_RESOLVE | 11 | Richiesta DNS resolution |
| RELAY_RESOLVED | 12 | Risposta DNS |
| RELAY_BEGIN_DIR | 13 | Apre stream verso directory del relay |
| RELAY_EXTEND2 | 14 | Estende circuito (ntor) |
| RELAY_EXTENDED2 | 15 | Risposta a EXTEND2 |

**Recognized** — Quando un nodo intermedio riceve una cella RELAY, decifra il suo
strato. Se `Recognized == 0` E il `Digest` è corretto, la cella è destinata a lui.
Altrimenti, la cella è per un hop successivo e viene inoltrata.

**StreamID** — Identifica lo stream all'interno del circuito. Valore 0 è riservato
per comandi che riguardano l'intero circuito (non uno stream specifico), come
EXTEND2, EXTENDED2, SENDME a livello circuito.

**Digest** — Running digest (SHA-1, troncato a 4 byte) calcolato su tutte le celle
precedenti dello stream. Serve per verificare integrità e per il riconoscimento
(insieme a Recognized). SHA-1 è usato qui per compatibilità storica; la sicurezza
del circuito si basa su AES-CTR e sulla key derivation, non su questo hash.

**Length** — Lunghezza effettiva dei dati nel campo Data. Massimo 498 byte. Il resto
del campo Data è padding (zeri).

---

## Crittografia dei circuiti — Strato per strato

### Setup delle chiavi dopo il handshake

Dopo che il handshake ntor con ogni hop è completato, il client possiede per ogni
relay del circuito:

```
Per ogni hop i (i=1 Guard, i=2 Middle, i=3 Exit):
  Kf_i  — chiave AES-128-CTR forward (client → exit)
  Kb_i  — chiave AES-128-CTR backward (exit → client)
  Df_i  — digest key forward (running SHA-1)
  Db_i  — digest key backward (running SHA-1)
```

### Cifratura forward (client → internet)

Quando il client vuole inviare dati:

```
1. Prende il payload RELAY in chiaro
2. Calcola il digest con Df_3 (exit) → lo inserisce nel campo Digest
3. Cifra con Kf_3 (chiave exit) → primo strato
4. Cifra con Kf_2 (chiave middle) → secondo strato
5. Cifra con Kf_1 (chiave guard) → terzo strato
6. Invia la cella al Guard
```

Il Guard:
```
1. Decifra con Kf_1 → rimuove il suo strato
2. Controlla Recognized: non è 0 → cella non per lui
3. Inoltra al Middle
```

Il Middle:
```
1. Decifra con Kf_2 → rimuove il suo strato
2. Controlla Recognized: non è 0 → cella non per lui
3. Inoltra all'Exit
```

L'Exit:
```
1. Decifra con Kf_3 → rimuove l'ultimo strato
2. Controlla Recognized: è 0 + Digest valido → cella per lui
3. Legge il comando RELAY e lo esegue (es. RELAY_DATA → invia dati alla destinazione)
```

### Cifratura backward (internet → client)

Quando l'Exit riceve dati dalla destinazione:

```
1. Costruisce il payload RELAY con i dati ricevuti
2. Calcola il digest con Db_3
3. Cifra con Kb_3 → un solo strato
4. Invia al Middle
```

Il Middle:
```
1. Cifra con Kb_2 → aggiunge il suo strato (non decifra!)
2. Inoltra al Guard
```

Il Guard:
```
1. Cifra con Kb_1 → aggiunge il suo strato
2. Inoltra al Client
```

Il Client:
```
1. Decifra con Kb_1 → rimuove strato del Guard
2. Decifra con Kb_2 → rimuove strato del Middle
3. Decifra con Kb_3 → rimuove strato dell'Exit
4. Verifica Recognized == 0 e Digest valido
5. Legge i dati in chiaro
```

#### Nota critica: AES-CTR e stato

AES-128-CTR è un cifrario a stream. Ogni chiave (Kf_i, Kb_i) mantiene un **contatore**
che avanza con ogni cella. Questo significa che:

- L'ordine delle celle è fondamentale
- Se una cella viene persa o riordinata, la decifratura di tutte le celle successive
  fallisce
- Questo è gestito dal fatto che Tor opera su TCP, che garantisce ordine e consegna

---

## Flow Control — SENDME cells

Tor implementa un meccanismo di flow control per evitare che un endpoint veloce
inondi uno lento. Il meccanismo usa celle RELAY_SENDME:

### Flow control a livello di circuito

- Il client inizia con una **finestra di 1000 celle** per circuito
- Ogni cella RELAY_DATA inviata decrementa la finestra di 1
- Quando la finestra raggiunge 0, il client smette di inviare
- Il relay di destinazione invia un RELAY_SENDME a livello circuito (StreamID=0)
  ogni 100 celle ricevute
- Ogni SENDME incrementa la finestra di 100

### Flow control a livello di stream

- Ogni stream inizia con una finestra di 500 celle
- Il meccanismo è analogo: SENDME ogni 50 celle ricevute
- Previene che un singolo stream monopolizzi il circuito

### Nella mia esperienza

Il flow control è trasparente all'utente, ma i suoi effetti sono visibili:

- **Download grandi via Tor**: la velocità fluttua perché il flow control si adatta
  alla bandwidth del nodo più lento nella catena
- **NEWNYM durante un download**: non interrompe il download in corso (lo stream
  continua sul vecchio circuito), ma le nuove connessioni usano un nuovo circuito

---

## Handshake ntor — Dettaglio crittografico

L'handshake ntor è il cuore della sicurezza di Tor. Ecco il protocollo completo:

### Parametri

```
G    = generatore del gruppo Curve25519
b    = chiave privata onion del relay (long-term)
B    = b*G = chiave pubblica onion del relay (nel consenso)
ID   = identità del relay (fingerprint Ed25519)
```

### Protocollo

```
Client:                                  Relay:
1. Genera x (random, privata)
   X = x*G (pubblica ephemeral)
2. Invia: CREATE2(X, ID, B)
                                ──────────────────►
                                         3. Verifica che ID e B corrispondano
                                         4. Genera y (random, privata)
                                            Y = y*G (pubblica ephemeral)
                                         5. Calcola:
                                            secret_input = x*Y | x*B | ID | B | X | Y | "ntor"
                                            (dove | = concatenazione)
                                         6. Deriva chiavi:
                                            KEY_SEED = HMAC-SHA256(secret_input, t_key)
                                            verify   = HMAC-SHA256(secret_input, t_verify)
                                            auth     = HMAC-SHA256(verify | ID | B | Y | X | "ntor" | "Server")
                                         7. Invia: CREATED2(Y, auth)
                                ◄──────────────────
8. Calcola:
   secret_input = y*X | B*x | ID | B | X | Y | "ntor"
   (proprietà DH: x*Y = y*X, x*B = B*x? No: x*B = b*X)
   Effettivamente:
   secret_input = EXP(Y,x) | EXP(B,x) | ID | B | X | Y | "ntor"
9. Verifica auth
10. Se valido, deriva le stesse chiavi:
    KEY_SEED → HKDF → Kf, Kb, Df, Db
```

### Proprietà di sicurezza

- **Forward secrecy**: anche se la chiave long-term `b` viene compromessa in futuro,
  le sessioni passate non possono essere decifrate (perché servono anche x e y, che
  sono ephemeral e non salvate).

- **Autenticazione del relay**: il client verifica `auth`, che può essere calcolato
  solo da chi possiede `b` (la chiave privata onion del relay). Questo previene
  attacchi MITM dove un nodo intermedio si spaccia per l'hop successivo.

- **Key confirmation**: `auth` dimostra che il relay ha calcolato lo stesso secret.

---

## Apertura di uno stream — RELAY_BEGIN → RELAY_CONNECTED

Quando proxychains chiede a Tor di connettersi a `api.ipify.org:443`:

### Passo 1: SOCKS5 handshake locale

```
proxychains → 127.0.0.1:9050:
  1. Client greeting: version=5, nauth=1, auth=0x00 (no auth)
  2. Server response: version=5, auth=0x00 (no auth selected)
  3. Connect request: version=5, cmd=CONNECT, addr_type=DOMAINNAME,
     dst.addr="api.ipify.org", dst.port=443
```

### Passo 2: Tor crea uno stream sul circuito

Tor seleziona un circuito adatto (con exit policy che permette porta 443) e invia:

```
Cella RELAY sul circuito scelto:
  RelayCmd: RELAY_BEGIN (1)
  StreamID: 0x0001 (nuovo stream)
  Data: "api.ipify.org:443\0"
```

Questa cella viene cifrata 3 volte (strati guard, middle, exit) e inviata.

### Passo 3: L'Exit Node apre la connessione

L'Exit Node:
1. Decifra la cella
2. Legge `RELAY_BEGIN` con destinazione `api.ipify.org:443`
3. Verifica che la sua exit policy permetta la porta 443
4. Risolve `api.ipify.org` via DNS (il DNS dell'exit, non il nostro)
5. Apre una connessione TCP verso l'IP risolto porta 443
6. Se successo: invia `RELAY_CONNECTED` al client

```
Cella di risposta:
  RelayCmd: RELAY_CONNECTED (4)
  StreamID: 0x0001
  Data: [IP dell'exit, TTL]
```

### Passo 4: Flusso dati

Il client TLS-handshake con `api.ipify.org` (attraverso Tor), poi invia la richiesta
HTTP. Ogni chunk di dati è wrappato in celle `RELAY_DATA`:

```
Client → Exit (cifrato 3 strati):
  RELAY_DATA, StreamID=0x0001, Data=[TLS Client Hello]

Exit → api.ipify.org (in chiaro TLS):
  [TLS Client Hello]

api.ipify.org → Exit:
  [TLS Server Hello, Certificate, ...]

Exit → Client (cifrato 3 strati):
  RELAY_DATA, StreamID=0x0001, Data=[TLS Server Hello, ...]
```

### Passo 5: Risposta a proxychains

Quando Tor riceve il `RELAY_CONNECTED`:
1. Risponde alla connessione SOCKS5 con successo
2. proxychains sblocca la `connect()` di curl
3. curl vede la connessione come stabilita e procede con TLS/HTTP

---

## Padding e resistenza alla traffic analysis

Tor implementa diverse forme di padding per rendere più difficile l'analisi del traffico:

### Connection padding (tra relay)

Le connessioni TLS tra relay possono inviare celle `PADDING` o `VPADDING` per mantenere
un flusso costante di dati, rendendo più difficile a un osservatore determinare quando
c'è traffico reale vs. padding.

### Circuit padding

Tor supporta "circuit padding machines" — macchine a stati che generano padding su
circuiti specifici. Sono usate per:

- **Rendez-vous circuits** (hidden services): padding per mascherare i pattern di
  traffico tipici del protocollo rendezvous
- **Client-side padding**: confonde gli osservatori sulla direzione del traffico

### Padding applicativo

Le celle RELAY_DATA hanno un campo `Length` che indica quanti byte del campo `Data`
sono effettivi. Il resto è padding (zeri). Se invii 100 byte di dati, la cella è
comunque 514 byte.

### Limitazioni del padding

Nonostante questi meccanismi, il padding di Tor è limitato:

- **Non è end-to-end a bitrate costante**: sarebbe troppo costoso in bandwidth
- **Il pattern di traffico a livello di flusso è ancora distinguibile**: il numero
  di celle, la direzione e il timing rivelano informazioni
- **Website fingerprinting**: un avversario che monitora la connessione client→guard
  può correlare i pattern di traffico con siti noti (attacco di website fingerprinting)

---

## Distruzione di un circuito

Un circuito viene distrutto quando:

1. **Il client lo decide**: timeout, NEWNYM, o non più necessario
2. **Un relay si disconnette**: la connessione TLS cade
3. **Errore**: un relay non riesce a processare una cella

La distruzione avviene con una cella `DESTROY`:

```
DESTROY cell:
  CircID: [id del circuito]
  Reason: [codice errore]
    0 = NONE (nessun errore)
    1 = PROTOCOL (violazione protocollo)
    2 = INTERNAL (errore interno)
    3 = REQUESTED (richiesto dal client)
    4 = HIBERNATING (relay in ibernazione)
    5 = RESOURCELIMIT (risorse esaurite)
    6 = CONNECTFAILED (connessione fallita)
    7 = OR_IDENTITY (identità relay errata)
    8 = CHANNEL_CLOSED (canale chiuso)
    9 = FINISHED (completato)
```

Il `DESTROY` si propaga hop per hop: il guard lo inoltra al middle, il middle all'exit.
Ogni relay libera le risorse associate al circuito.

---

## Osservare i circuiti nella pratica

### Tramite ControlPort

Con il protocollo di controllo Tor (porta 9051), posso ispezionare i circuiti attivi:

```bash
# Autenticazione
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')

# Lista circuiti
printf "AUTHENTICATE %s\r\nGETINFO circuit-status\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
```

Output tipico:
```
250+circuit-status=
1 BUILT $AAAA~GuardNick,$BBBB~MiddleNick,$CCCC~ExitNick BUILD_FLAGS=IS_INTERNAL,NEED_CAPACITY PURPOSE=GENERAL
2 BUILT $DDDD~Guard2,$EEEE~Middle2,$FFFF~Exit2 BUILD_FLAGS=NEED_CAPACITY PURPOSE=GENERAL
```

Ogni riga mostra:
- ID del circuito locale
- Stato (LAUNCHED, BUILT, EXTENDED, FAILED, CLOSED)
- Fingerprint e nickname di ogni hop
- Flag di costruzione e scopo

### Tramite Nyx (ex arm)

Nyx è un monitor TUI per Tor. Mostra in tempo reale:
- Circuiti attivi con latenza per hop
- Bandwidth in/out
- Log
- Connessioni

Nella mia esperienza, Nyx è lo strumento migliore per capire cosa sta facendo Tor
in un dato momento. Lo installo con:

```bash
sudo apt install nyx
nyx
```

---

## Riepilogo delle garanzie crittografiche

| Proprietà | Meccanismo | Garanzia |
|-----------|-----------|----------|
| Confidenzialità per hop | AES-128-CTR con chiavi per-hop | Ogni relay vede solo il suo strato |
| Forward secrecy | Chiavi ephemeral Curve25519 | Compromissione futura non decifra il passato |
| Autenticazione relay | ntor handshake con chiave long-term | Nessun MITM possibile senza chiave privata |
| Integrità celle | Running digest SHA-1 | Modifiche alle celle vengono rilevate |
| Anti traffic analysis (parziale) | Celle fisse 514 byte + padding | Dimensione costante, padding configurabile |
| Non-correlazione CircID | CircID locali per connessione | Non correlabili tra hop diversi |
| Limiti di estensione | RELAY_EARLY counter (max 8) | Previene circuiti eccessivamente lunghi |

---

## Vedi anche

- [Architettura di Tor](architettura-tor.md) — Visione d'insieme dei componenti
- [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) — Primo hop, handshake ntor
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) — Osservare circuiti attivi
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) — Attacchi ai circuiti e padding
- [Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md) — Relay early tagging, correlazione
