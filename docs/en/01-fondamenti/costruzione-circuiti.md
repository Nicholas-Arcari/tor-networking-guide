> **Lingua / Language**: [Italiano](../../01-fondamenti/costruzione-circuiti.md) | English

# Circuit Construction - Path Selection, ntor Handshake and Data Transmission

How Tor selects nodes, negotiates cryptographic keys with CREATE2/EXTEND2,
and transmits data encrypted layer by layer through the circuit.

Extracted from the [Tor Architecture](architettura-tor.md) section for in-depth analysis.

---

## Table of Contents

- [How Tor builds a circuit](#how-tor-builds-a-circuit--protocol-detail)
- [Tor Cells - The transport unit](#tor-cells--the-transport-unit)
- [TLS connections between relays](#tls-connections-between-relays)

---

## How Tor builds a circuit - Protocol detail

Circuit construction is the heart of Tor's architecture. Here's what actually happens
at the protocol level:

### Phase 1: Node selection

The path selection algorithm works as follows:

1. **Guard selection**: the client maintains a set of 1-3 persistent guards (saved in
   the `state` file at `/var/lib/tor/state`). If it has none, it selects from the consensus
   among relays with `Guard` + `Stable` + `Fast` flags. Selection is weighted by bandwidth.

2. **Exit selection**: among relays with the `Exit` flag, Tor chooses those whose exit policy
   allows the requested destination port. If you want to reach port 443, you need exits
   that accept `:443`. Selection is also weighted by bandwidth.

3. **Middle selection**: any relay that is neither the selected guard nor exit.
   Selection is weighted by bandwidth. Tor avoids selecting two nodes in the same
   `/16` subnet or in the same declared family.

### Phase 2: Circuit creation (CREATE2 -> CREATED2 -> EXTEND2 -> EXTENDED2)

```
Client                   Guard                   Middle                  Exit
  |                        |                       |                      |
  |--- CREATE2 ----------->|                       |                      |
  |    (ntor handshake     |                       |                      |
  |     client->guard)     |                       |                      |
  |                        |                       |                      |
  |<-- CREATED2 ---------- |                       |                      |
  |    (guard->client      |                       |                      |
  |     handshake done)    |                       |                      |
  |                        |                       |                      |
  | Now: shared key with Guard (Kf_guard, Kb_guard)                       |
  |                        |                       |                      |
  |--- RELAY_EARLY ------->|--- EXTEND2 --------->|                      |
  |    {EXTEND2 encrypted  |    (ntor handshake    |                      |
  |     with Kf_guard}     |     client->middle)   |                      |
  |                        |                       |                      |
  |<-- RELAY --------------|<-- EXTENDED2 ---------|                      |
  |    {EXTENDED2 encrypted|    (middle->client    |                      |
  |     with Kb_guard}     |     handshake done)   |                      |
  |                        |                       |                      |
  | Now: shared key also with Middle (Kf_middle, Kb_middle)               |
  |                        |                       |                      |
  |--- RELAY_EARLY ------->|--- RELAY ------------>|--- EXTEND2 -------->|
  |    {EXTEND2 encrypted  |    {EXTEND2 encrypted |    (ntor handshake  |
  |     2 layers}          |     1 layer}          |     client->exit)   |
  |                        |                       |                      |
  |<-- RELAY --------------|<-- RELAY -------------|<-- EXTENDED2 -------|
  |    {EXTENDED2 encrypted|    {EXTENDED2 encrypted|    (exit->client   |
  |     2 layers}          |     1 layer}          |     handshake done) |
  |                        |                       |                      |
  | Now: 3 independent shared keys                                        |
```

#### ntor handshake detail

The ntor handshake is the cryptographic mechanism that Tor uses to negotiate keys with
each node in the circuit. It uses:

- **Curve25519** - for Elliptic Curve Diffie-Hellman
- **HMAC-SHA256** - for key derivation
- **HKDF** (HMAC-based Key Derivation Function) - to generate the final symmetric keys

The process for each hop:

1. The client generates an ephemeral Curve25519 pair (x, X = x*G)
2. The client knows the relay's public onion key (B) from the consensus
3. The client sends X in the CREATE2/EXTEND2 cell
4. The relay has the private key b corresponding to B
5. The relay generates its own ephemeral pair (y, Y = y*G)
6. Both compute: secret = x*Y = y*X (ECDH property)
7. From the secret, symmetric keys are derived via HKDF:
   - `Kf` - key for forward encryption (client -> relay)
   - `Kb` - key for backward encryption (relay -> client)
   - `Df`, `Db` - digests for integrity

The resulting keys are used with **AES-128-CTR** for symmetric data encryption.

### Phase 3: Data transmission

When the circuit is ready and an application sends data:

1. **The client encrypts 3 times**: first with the Exit's key, then the Middle's, then
   the Guard's. Data is wrapped in RELAY_DATA cells.

2. **The Guard decrypts the first layer** and forwards to the Middle.

3. **The Middle decrypts the second layer** and forwards to the Exit.

4. **The Exit decrypts the third layer** and sees the plaintext data (unless it's
   HTTPS/TLS, in which case it sees TLS-encrypted traffic toward the destination).

5. **On the return path**: the Exit encrypts with its key, the Middle adds its layer,
   the Guard adds its. The client decrypts all 3 layers.

---

## Tor Cells - The transport unit

All Tor traffic is carried in fixed-size **cells**: **514 bytes**.
The fixed size is an anti-traffic-analysis choice: an observer cannot distinguish
the cell type from its size.

### Cell structure

```
+----------+----------+------------------------------------------+
| CircID   | Command  | Payload                                  |
| (4 byte) | (1 byte) | (509 byte)                               |
+----------+----------+------------------------------------------+
```

- **CircID** (Circuit ID): identifies the circuit on the TLS connection between two nodes.
  Each TLS connection between two relays can carry hundreds of circuits, each with its
  own CircID.

- **Command**: cell type. The main ones:

  | Command | Value | Description |
  |---------|-------|-------------|
  | PADDING | 0 | Padding cell (anti traffic analysis) |
  | CREATE2 | 10 | Start circuit creation |
  | CREATED2 | 11 | Response to CREATE2 |
  | RELAY | 3 | Relay cell (carries data and relay commands) |
  | RELAY_EARLY | 9 | Like RELAY but used only during circuit extension |
  | DESTROY | 4 | Destroys a circuit |

### RELAY Cells - The transport subsystem

RELAY cells have a structured payload:

```
+-----------+-----------+----------+---------+---------------------+
| RelayCmd  | Recognized| StreamID | Digest  | Data                |
| (1 byte)  | (2 byte)  | (2 byte) | (4 byte)| (498 byte)         |
+-----------+-----------+----------+---------+---------------------+
```

- **RelayCmd**: the relay command type:

  | Command | Description |
  |---------|-------------|
  | RELAY_BEGIN | Opens a new TCP stream to a destination |
  | RELAY_DATA | Carries stream data |
  | RELAY_END | Closes a stream |
  | RELAY_CONNECTED | Confirms the stream is connected |
  | RELAY_RESOLVE | Resolves a hostname |
  | RELAY_RESOLVED | Response to RESOLVE |
  | RELAY_BEGIN_DIR | Opens a stream to the relay's directory |
  | RELAY_EXTEND2 | Extends the circuit to a new hop |
  | RELAY_EXTENDED2 | Confirms the extension |

- **StreamID**: identifies the specific stream within the circuit. A circuit can have
  many active streams simultaneously (e.g., multiple browser tabs on the same circuit).

- **Recognized + Digest**: used to verify that the cell is destined for this node.
  Each intermediate node sees `Recognized` different from zero (cell not for it) and
  forwards it. Only the final recipient sees `Recognized = 0` and the correct digest.

---

## TLS connections between relays

All Tor relays communicate with each other via persistent TLS connections. These
connections:

- **Are multiplexed**: a single TLS connection between two relays can carry hundreds
  of circuits from different users.

- **Use TLS 1.3** (or 1.2 minimum): with negotiated ciphersuites that include forward
  secrecy (ECDHE).

- **Have a special handshake**: Tor uses an in-band authentication protocol where relays
  exchange their Ed25519 identity keys after the TLS handshake. This allows Tor to hide
  the relay's identity from passive observers (the TLS certificate doesn't contain the
  relay's identity).

### Implication: what the ISP sees

When my Tor client connects to the Guard Node, my ISP sees:

1. A TLS connection to the Guard's IP (or the bridge if using obfs4)
2. The Guard's TLS certificate - which does **not** contain explicit Tor identifiers
   (but DAs publish the IP list, so the ISP can correlate)
3. With obfs4: not even this. The traffic appears as random noise.

In my experience in Parma, my ISP (Comeser) never showed signs of interfering with direct
Tor. But on university networks, firewalls blocked connections to known relays, making
obfs4 bridges necessary.


---

## See also

- [Tor Architecture](architettura-tor.md) - Overview and components
- [Isolation and Threat Model](isolamento-e-modello-minaccia.md) - Stream isolation, threat model
- [Cryptography and Handshake](crittografia-e-handshake.md) - ntor, AES-128-CTR, SENDME flow control
- [Consensus and Directory Authorities](consenso-e-directory-authorities.md) - How relays are selected
