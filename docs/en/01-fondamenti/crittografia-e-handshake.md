> **Lingua / Language**: [Italiano](../../01-fondamenti/crittografia-e-handshake.md) | English

# Circuit Cryptography, Flow Control and ntor Handshake

AES-128-CTR encryption layer by layer, SENDME mechanism for flow control,
and cryptographic details of the ntor handshake (Curve25519 + HKDF).

Extracted from [Circuits, Cryptography and Cells](circuiti-crittografia-e-celle.md).

---

## Table of Contents

- [Circuit cryptography - Layer by layer](#circuit-cryptography--layer-by-layer)
- [Flow Control - SENDME cells](#flow-control--sendme-cells)
- [ntor Handshake - Cryptographic detail](#ntor-handshake--cryptographic-detail)

---

## Circuit cryptography - Layer by layer

### Key setup after the handshake

After the ntor handshake with each hop is completed, the client possesses for each
relay in the circuit:

```
For each hop i (i=1 Guard, i=2 Middle, i=3 Exit):
  Kf_i  - AES-128-CTR forward key (client -> exit)
  Kb_i  - AES-128-CTR backward key (exit -> client)
  Df_i  - forward digest key (running SHA-1)
  Db_i  - backward digest key (running SHA-1)
```

### Forward encryption (client -> internet)

When the client wants to send data:

```
1. Takes the plaintext RELAY payload
2. Computes the digest with Df_3 (exit) -> inserts it in the Digest field
3. Encrypts with Kf_3 (exit key) -> first layer
4. Encrypts with Kf_2 (middle key) -> second layer
5. Encrypts with Kf_1 (guard key) -> third layer
6. Sends the cell to the Guard
```

The Guard:
```
1. Decrypts with Kf_1 -> removes its layer
2. Checks Recognized: not 0 -> cell not for it
3. Forwards to the Middle
```

The Middle:
```
1. Decrypts with Kf_2 -> removes its layer
2. Checks Recognized: not 0 -> cell not for it
3. Forwards to the Exit
```

The Exit:
```
1. Decrypts with Kf_3 -> removes the last layer
2. Checks Recognized: is 0 + valid Digest -> cell is for it
3. Reads the RELAY command and executes it (e.g., RELAY_DATA -> sends data to destination)
```

### Backward encryption (internet -> client)

When the Exit receives data from the destination:

```
1. Constructs the RELAY payload with the received data
2. Computes the digest with Db_3
3. Encrypts with Kb_3 -> one layer only
4. Sends to the Middle
```

The Middle:
```
1. Encrypts with Kb_2 -> adds its layer (does not decrypt!)
2. Forwards to the Guard
```

The Guard:
```
1. Encrypts with Kb_1 -> adds its layer
2. Forwards to the Client
```

The Client:
```
1. Decrypts with Kb_1 -> removes Guard's layer
2. Decrypts with Kb_2 -> removes Middle's layer
3. Decrypts with Kb_3 -> removes Exit's layer
4. Verifies Recognized == 0 and valid Digest
5. Reads the plaintext data
```

#### Critical note: AES-CTR and state

AES-128-CTR is a stream cipher. Each key (Kf_i, Kb_i) maintains a **counter** that
advances with each cell. This means:

- Cell order is fundamental
- If a cell is lost or reordered, decryption of all subsequent cells fails
- This is handled by the fact that Tor operates on TCP, which guarantees order and delivery

---

## Flow Control - SENDME cells

Tor implements a flow control mechanism to prevent a fast endpoint from flooding a slow
one. The mechanism uses RELAY_SENDME cells:

### Circuit-level flow control

- The client starts with a **window of 1000 cells** per circuit
- Each RELAY_DATA cell sent decrements the window by 1
- When the window reaches 0, the client stops sending
- The destination relay sends a circuit-level RELAY_SENDME (StreamID=0) every 100
  cells received
- Each SENDME increments the window by 100

### Stream-level flow control

- Each stream starts with a window of 500 cells
- The mechanism is analogous: SENDME every 50 cells received
- Prevents a single stream from monopolizing the circuit

### In my experience

Flow control is transparent to the user, but its effects are visible:

- **Large downloads via Tor**: speed fluctuates because flow control adapts to the
  bandwidth of the slowest node in the chain
- **NEWNYM during a download**: does not interrupt the ongoing download (the stream
  continues on the old circuit), but new connections use a new circuit

---

## ntor Handshake - Cryptographic detail

The ntor handshake is the heart of Tor's security. Here is the complete protocol:

### Parameters

```
G    = Curve25519 group generator
b    = relay's onion private key (long-term)
B    = b*G = relay's onion public key (in the consensus)
ID   = relay identity (Ed25519 fingerprint)
```

### Protocol

```
Client:                                  Relay:
1. Generates x (random, private)
   X = x*G (ephemeral public)
2. Sends: CREATE2(X, ID, B)
                                ---------------------->
                                         3. Verifies that ID and B match
                                         4. Generates y (random, private)
                                            Y = y*G (ephemeral public)
                                         5. Computes:
                                            secret_input = x*Y | x*B | ID | B | X | Y | "ntor"
                                            (where | = concatenation)
                                         6. Derives keys:
                                            KEY_SEED = HMAC-SHA256(secret_input, t_key)
                                            verify   = HMAC-SHA256(secret_input, t_verify)
                                            auth     = HMAC-SHA256(verify | ID | B | Y | X | "ntor" | "Server")
                                         7. Sends: CREATED2(Y, auth)
                                <----------------------
8. Computes:
   secret_input = y*X | B*x | ID | B | X | Y | "ntor"
   (DH property: x*Y = y*X, x*B = B*x? No: x*B = b*X)
   Effectively:
   secret_input = EXP(Y,x) | EXP(B,x) | ID | B | X | Y | "ntor"
9. Verifies auth
10. If valid, derives the same keys:
    KEY_SEED -> HKDF -> Kf, Kb, Df, Db
```

### Security properties

- **Forward secrecy**: even if the long-term key `b` is compromised in the future,
  past sessions cannot be decrypted (because x and y are also needed, which are
  ephemeral and not saved).

- **Relay authentication**: the client verifies `auth`, which can only be computed by
  someone possessing `b` (the relay's onion private key). This prevents MITM attacks
  where an intermediate node impersonates the next hop.

- **Key confirmation**: `auth` proves that the relay computed the same secret.

---


---

## See also

- [Circuits, Cryptography and Cells](circuiti-crittografia-e-celle.md) - Protocol hierarchy, cells, RELAY
- [Streams, Padding and Practice](stream-padding-e-pratica.md) - RELAY_BEGIN, padding, observation
- [Circuit Construction](costruzione-circuiti.md) - Path selection, CREATE2/EXTEND2
- [Real-World Scenarios](scenari-reali.md) - Operational pentesting cases
