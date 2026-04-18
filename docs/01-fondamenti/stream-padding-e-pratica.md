> **Lingua / Language**: Italiano | [English](../en/01-fondamenti/stream-padding-e-pratica.md)

# Stream, Padding e Osservazione Pratica dei Circuiti

Apertura di stream TCP via RELAY_BEGIN, padding anti traffic analysis,
distruzione dei circuiti, e osservazione pratica con ControlPort e log.

Estratto da [Circuiti, Crittografia e Celle](circuiti-crittografia-e-celle.md).

---

## Indice

- [Apertura di uno stream - RELAY_BEGIN → RELAY_CONNECTED](#apertura-di-uno-stream--relay_begin--relay_connected)
- [Padding e resistenza alla traffic analysis](#padding-e-resistenza-alla-traffic-analysis)
- [Distruzione di un circuito](#distruzione-di-un-circuito)
- [Osservare i circuiti nella pratica](#osservare-i-circuiti-nella-pratica)
- [Riepilogo delle garanzie crittografiche](#riepilogo-delle-garanzie-crittografiche)

---

## Apertura di uno stream - RELAY_BEGIN → RELAY_CONNECTED

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

Tor supporta "circuit padding machines" - macchine a stati che generano padding su
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

- [Circuiti, Crittografia e Celle](circuiti-crittografia-e-celle.md) - Gerarchia protocollo, celle, RELAY
- [Crittografia e Handshake](crittografia-e-handshake.md) - AES-128-CTR, SENDME, ntor
- [Architettura di Tor](architettura-tor.md) - Visione d'insieme dei componenti
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - Attacchi ai circuiti e padding
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - Osservare circuiti attivi
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
