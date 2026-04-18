> **Lingua / Language**: Italiano | [English](../en/01-fondamenti/crittografia-e-handshake.md)

# Crittografia dei Circuiti, Flow Control e Handshake ntor

Cifratura AES-128-CTR strato per strato, meccanismo SENDME per flow control,
e dettaglio crittografico dell'handshake ntor (Curve25519 + HKDF).

Estratto da [Circuiti, Crittografia e Celle](circuiti-crittografia-e-celle.md).

---

## Indice

- [Crittografia dei circuiti - Strato per strato](#crittografia-dei-circuiti--strato-per-strato)
- [Flow Control - SENDME cells](#flow-control--sendme-cells)
- [Handshake ntor - Dettaglio crittografico](#handshake-ntor--dettaglio-crittografico)

---

## Crittografia dei circuiti - Strato per strato

### Setup delle chiavi dopo il handshake

Dopo che il handshake ntor con ogni hop è completato, il client possiede per ogni
relay del circuito:

```
Per ogni hop i (i=1 Guard, i=2 Middle, i=3 Exit):
  Kf_i  - chiave AES-128-CTR forward (client → exit)
  Kb_i  - chiave AES-128-CTR backward (exit → client)
  Df_i  - digest key forward (running SHA-1)
  Db_i  - digest key backward (running SHA-1)
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

## Flow Control - SENDME cells

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

## Handshake ntor - Dettaglio crittografico

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


---

## Vedi anche

- [Circuiti, Crittografia e Celle](circuiti-crittografia-e-celle.md) - Gerarchia protocollo, celle, RELAY
- [Stream, Padding e Pratica](stream-padding-e-pratica.md) - RELAY_BEGIN, padding, osservazione
- [Costruzione Circuiti](costruzione-circuiti.md) - Path selection, CREATE2/EXTEND2
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
