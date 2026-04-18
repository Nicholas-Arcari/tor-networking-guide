> **Lingua / Language**: [Italiano](../../01-fondamenti/circuiti-crittografia-e-celle.md) | English

# Circuits, Cryptography and Cells - The Tor Protocol at Packet Level

This document dives deep into the inner workings of the Tor protocol at the level of
cells, streams, symmetric and asymmetric cryptography. This is not an overview: it's a
detailed analysis of how data travels through the Tor network, byte by byte.

Includes observations from my hands-on experience analyzing circuits via ControlPort,
Nyx and debug logs.

---
---

## Table of Contents

- [Tor protocol hierarchy](#tor-protocol-hierarchy)
- [Cells - The atomic unit of the Tor protocol](#cells--the-atomic-unit-of-the-tor-protocol)
- [RELAY Cells - The heart of data transport](#relay-cells--the-heart-of-data-transport)
**Deep dives** (dedicated files):
- [Cryptography and Handshake](crittografia-e-handshake.md) - AES-128-CTR layer by layer, SENDME flow control, ntor
- [Streams, Padding and Practice](stream-padding-e-pratica.md) - RELAY_BEGIN, anti traffic analysis padding, circuit observation


## Tor protocol hierarchy

The Tor protocol operates on several layered levels:

```
+---------------------------------------------------+
| Level 5: Streams (application TCP connections)     |
|   -> curl, browser, SSH, every SOCKS connection    |
+---------------------------------------------------+
| Level 4: Circuit (encrypted multi-hop tunnel)      |
|   -> 3 nodes, negotiated keys, multiplexing        |
+---------------------------------------------------+
| Level 3: Cells (fixed transport units)             |
|   -> 514 bytes each, typed commands                |
+---------------------------------------------------+
| Level 2: TLS Connection (link between relays)      |
|   -> TLS 1.2/1.3 with forward secrecy             |
+---------------------------------------------------+
| Level 1: TCP (network transport)                   |
|   -> persistent TCP connections between relays     |
+---------------------------------------------------+
```

### Relationship between levels

- **One TCP connection** between two relays carries **one TLS connection**.
- **One TLS connection** multiplexes **hundreds of circuits** (identified by CircID).
- **One circuit** multiplexes **dozens of streams** (identified by StreamID).
- **One stream** corresponds to **one application TCP connection** (e.g., one HTTP request).

---

## Cells - The atomic unit of the Tor protocol

### Complete cell structure

Every Tor cell is **exactly 514 bytes**. No exceptions. This fixed size is fundamental
for traffic analysis resistance: an observer cannot distinguish the cell type based on
its size.

```
Standard cell (514 bytes):
+----------+----------+-------------------------------------------+
| CircID   | Command  | Payload                                   |
| 4 bytes  | 1 byte   | 509 bytes                                 |
+----------+----------+-------------------------------------------+

Variable-length cell (for link protocol versions >= 4):
+----------+----------+----------+----------------------------------+
| CircID   | Command  | Length   | Payload                          |
| 4 bytes  | 1 byte   | 2 bytes  | variable                         |
+----------+----------+----------+----------------------------------+
```

Variable-length cells are used only for specific commands (VERSIONS, VPADDING, AUTH_CHALLENGE,
CERTS, AUTHENTICATE, AUTHORIZE). Data traffic always uses fixed 514-byte cells.

### CircID - Circuit Identifier

The CircID is an identifier local to the TLS connection between two nodes. It is NOT global:
the same circuit has different CircIDs on each hop.

```
Client <-> Guard: CircID = 0x00000A3F
Guard <-> Middle: CircID = 0x00005B12
Middle <-> Exit:  CircID = 0x000023C7
```

Each node maintains a mapping table:
```
Guard: CircID 0x00000A3F (from client) -> CircID 0x00005B12 (toward middle)
```

This prevents an observer from correlating traffic between two different hops based on
the CircID.

### Cell commands - Complete catalog

#### Circuit cells (not encrypted at relay level)

| Command | Byte | Direction | Description |
|---------|------|-----------|-------------|
| PADDING | 0 | bidirectional | Padding for anti traffic analysis. Ignored by recipient |
| CREATE | 1 | client->relay | Create circuit (TAP handshake - deprecated) |
| CREATED | 2 | relay->client | Response to CREATE |
| RELAY | 3 | bidirectional | Carries encrypted relay data and commands |
| DESTROY | 4 | bidirectional | Destroys a circuit |
| CREATE_FAST | 5 | client->relay | Fast creation (first hop only) |
| CREATED_FAST | 6 | relay->client | Response to CREATE_FAST |
| VERSIONS | 7 | bidirectional | Link protocol version negotiation |
| NETINFO | 8 | bidirectional | Network info exchange (timestamp, addresses) |
| RELAY_EARLY | 9 | client->relay | Like RELAY but counts to limit extensions |
| CREATE2 | 10 | client->relay | Create circuit (ntor handshake - current) |
| CREATED2 | 11 | relay->client | Response to CREATE2 |
| PADDING_NEGOTIATE | 12 | bidirectional | Padding parameter negotiation |
| VPADDING | 128 | bidirectional | Variable-length padding |
| CERTS | 129 | relay->client | Relay certificates |
| AUTH_CHALLENGE | 130 | relay->client | Relay authentication challenge |
| AUTHENTICATE | 131 | client->relay | Authentication response |

#### RELAY_EARLY and the extension limit

`RELAY_EARLY` cells have the same format as `RELAY` cells, but the guard counts them.
A circuit can have at most **8 RELAY_EARLY cells**. This prevents a malicious client from
creating circuits with too many hops (which could be used for traffic amplification or
deanonymization).

Each `EXTEND2` during circuit construction uses a `RELAY_EARLY` cell. With 3 standard
hops, 2 are needed (guard->middle and middle->exit). For 4-hop circuits (e.g., hidden
services) 3 are needed.

---

## RELAY Cells - The heart of data transport

RELAY cells carry all application traffic. The payload of an encrypted RELAY cell has
this structure:

```
RELAY Payload (509 bytes):
+-----------+------------+----------+----------+-----------+----------+
| RelayCmd  | Recognized | StreamID | Digest   | Length    | Data     |
| 1 byte    | 2 bytes    | 2 bytes  | 4 bytes  | 2 bytes   | 498 bytes|
+-----------+------------+----------+----------+-----------+----------+
```

### Field by field

**RelayCmd** - The relay command type:

| Command | Byte | Description |
|---------|------|-------------|
| RELAY_BEGIN | 1 | Opens TCP stream: `hostname:port\0` in data |
| RELAY_DATA | 2 | Carries application data |
| RELAY_END | 3 | Closes stream with reason code |
| RELAY_CONNECTED | 4 | Confirms stream opening |
| RELAY_SENDME | 5 | Flow control: permits sending more data |
| RELAY_EXTEND | 6 | Extends circuit (TAP - deprecated) |
| RELAY_EXTENDED | 7 | Response to EXTEND |
| RELAY_TRUNCATE | 8 | Truncates circuit at a certain point |
| RELAY_TRUNCATED | 9 | Confirms truncation |
| RELAY_DROP | 10 | Cell to be ignored (used for padding) |
| RELAY_RESOLVE | 11 | DNS resolution request |
| RELAY_RESOLVED | 12 | DNS response |
| RELAY_BEGIN_DIR | 13 | Opens stream to relay's directory |
| RELAY_EXTEND2 | 14 | Extends circuit (ntor) |
| RELAY_EXTENDED2 | 15 | Response to EXTEND2 |

**Recognized** - When an intermediate node receives a RELAY cell, it decrypts its layer.
If `Recognized == 0` AND the `Digest` is correct, the cell is destined for it. Otherwise,
the cell is for a subsequent hop and is forwarded.

**StreamID** - Identifies the stream within the circuit. Value 0 is reserved for commands
concerning the entire circuit (not a specific stream), like EXTEND2, EXTENDED2, circuit-level
SENDME.

**Digest** - Running digest (SHA-1, truncated to 4 bytes) computed over all previous cells
in the stream. Used to verify integrity and for recognition (together with Recognized).
SHA-1 is used here for historical compatibility; the circuit's security relies on AES-CTR
and key derivation, not on this hash.

**Length** - Actual data length in the Data field. Maximum 498 bytes. The rest of the Data
field is padding (zeros).

---


> **Continues in**: [Cryptography and Handshake](crittografia-e-handshake.md) for layer-by-layer
> encryption, and in [Streams, Padding and Practice](stream-padding-e-pratica.md) for
> stream opening, padding and hands-on circuit observation.

---

## See also

- [Cryptography and Handshake](crittografia-e-handshake.md) - AES-128-CTR, SENDME, ntor Curve25519
- [Streams, Padding and Practice](stream-padding-e-pratica.md) - RELAY_BEGIN, padding, circuit observation
- [Tor Architecture](architettura-tor.md) - Component overview
- [Circuit Construction](costruzione-circuiti.md) - Path selection, CREATE2/EXTEND2
- [Real-World Scenarios](scenari-reali.md) - Operational pentesting cases
