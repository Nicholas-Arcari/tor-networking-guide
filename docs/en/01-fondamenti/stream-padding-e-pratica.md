> **Lingua / Language**: [Italiano](../../01-fondamenti/stream-padding-e-pratica.md) | English

# Streams, Padding and Hands-On Circuit Observation

Opening TCP streams via RELAY_BEGIN, anti traffic analysis padding,
circuit destruction, and hands-on observation with ControlPort and logs.

Extracted from [Circuits, Cryptography and Cells](circuiti-crittografia-e-celle.md).

---

## Table of Contents

- [Opening a stream - RELAY_BEGIN -> RELAY_CONNECTED](#opening-a-stream--relay_begin--relay_connected)
- [Padding and traffic analysis resistance](#padding-and-traffic-analysis-resistance)
- [Circuit destruction](#circuit-destruction)
- [Observing circuits in practice](#observing-circuits-in-practice)
- [Summary of cryptographic guarantees](#summary-of-cryptographic-guarantees)

---

## Opening a stream - RELAY_BEGIN -> RELAY_CONNECTED

When proxychains asks Tor to connect to `api.ipify.org:443`:

### Step 1: Local SOCKS5 handshake

```
proxychains -> 127.0.0.1:9050:
  1. Client greeting: version=5, nauth=1, auth=0x00 (no auth)
  2. Server response: version=5, auth=0x00 (no auth selected)
  3. Connect request: version=5, cmd=CONNECT, addr_type=DOMAINNAME,
     dst.addr="api.ipify.org", dst.port=443
```

### Step 2: Tor creates a stream on the circuit

Tor selects a suitable circuit (with exit policy allowing port 443) and sends:

```
RELAY cell on the chosen circuit:
  RelayCmd: RELAY_BEGIN (1)
  StreamID: 0x0001 (new stream)
  Data: "api.ipify.org:443\0"
```

This cell is encrypted 3 times (guard, middle, exit layers) and sent.

### Step 3: The Exit Node opens the connection

The Exit Node:
1. Decrypts the cell
2. Reads `RELAY_BEGIN` with destination `api.ipify.org:443`
3. Verifies that its exit policy allows port 443
4. Resolves `api.ipify.org` via DNS (the exit's DNS, not ours)
5. Opens a TCP connection to the resolved IP on port 443
6. If successful: sends `RELAY_CONNECTED` to the client

```
Response cell:
  RelayCmd: RELAY_CONNECTED (4)
  StreamID: 0x0001
  Data: [exit's IP, TTL]
```

### Step 4: Data flow

The client TLS-handshakes with `api.ipify.org` (through Tor), then sends the HTTP
request. Each data chunk is wrapped in `RELAY_DATA` cells:

```
Client -> Exit (encrypted 3 layers):
  RELAY_DATA, StreamID=0x0001, Data=[TLS Client Hello]

Exit -> api.ipify.org (plaintext TLS):
  [TLS Client Hello]

api.ipify.org -> Exit:
  [TLS Server Hello, Certificate, ...]

Exit -> Client (encrypted 3 layers):
  RELAY_DATA, StreamID=0x0001, Data=[TLS Server Hello, ...]
```

### Step 5: Response to proxychains

When Tor receives the `RELAY_CONNECTED`:
1. Responds to the SOCKS5 connection with success
2. proxychains unblocks curl's `connect()`
3. curl sees the connection as established and proceeds with TLS/HTTP

---

## Padding and traffic analysis resistance

Tor implements several forms of padding to make traffic analysis harder:

### Connection padding (between relays)

TLS connections between relays can send `PADDING` or `VPADDING` cells to maintain a
constant data flow, making it harder for an observer to determine when there is real
traffic vs. padding.

### Circuit padding

Tor supports "circuit padding machines" - state machines that generate padding on
specific circuits. They are used for:

- **Rendezvous circuits** (hidden services): padding to mask traffic patterns typical
  of the rendezvous protocol
- **Client-side padding**: confuses observers about traffic direction

### Application-level padding

RELAY_DATA cells have a `Length` field indicating how many bytes of the `Data` field are
actual data. The rest is padding (zeros). If you send 100 bytes of data, the cell is
still 514 bytes.

### Padding limitations

Despite these mechanisms, Tor's padding is limited:

- **Not end-to-end at constant bitrate**: would be too expensive in bandwidth
- **Flow-level traffic patterns are still distinguishable**: the number of cells,
  direction and timing reveal information
- **Website fingerprinting**: an adversary monitoring the client->guard connection can
  correlate traffic patterns with known sites (website fingerprinting attack)

---

## Circuit destruction

A circuit is destroyed when:

1. **The client decides**: timeout, NEWNYM, or no longer needed
2. **A relay disconnects**: the TLS connection drops
3. **Error**: a relay cannot process a cell

Destruction happens with a `DESTROY` cell:

```
DESTROY cell:
  CircID: [circuit id]
  Reason: [error code]
    0 = NONE (no error)
    1 = PROTOCOL (protocol violation)
    2 = INTERNAL (internal error)
    3 = REQUESTED (requested by client)
    4 = HIBERNATING (relay hibernating)
    5 = RESOURCELIMIT (resources exhausted)
    6 = CONNECTFAILED (connection failed)
    7 = OR_IDENTITY (wrong relay identity)
    8 = CHANNEL_CLOSED (channel closed)
    9 = FINISHED (completed)
```

The `DESTROY` propagates hop by hop: the guard forwards it to the middle, the middle
to the exit. Each relay frees the resources associated with the circuit.

---

## Observing circuits in practice

### Via ControlPort

With the Tor control protocol (port 9051), I can inspect active circuits:

```bash
# Authentication
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')

# List circuits
printf "AUTHENTICATE %s\r\nGETINFO circuit-status\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
```

Typical output:
```
250+circuit-status=
1 BUILT $AAAA~GuardNick,$BBBB~MiddleNick,$CCCC~ExitNick BUILD_FLAGS=IS_INTERNAL,NEED_CAPACITY PURPOSE=GENERAL
2 BUILT $DDDD~Guard2,$EEEE~Middle2,$FFFF~Exit2 BUILD_FLAGS=NEED_CAPACITY PURPOSE=GENERAL
```

Each line shows:
- Local circuit ID
- State (LAUNCHED, BUILT, EXTENDED, FAILED, CLOSED)
- Fingerprint and nickname of each hop
- Build flags and purpose

### Via Nyx (formerly arm)

Nyx is a TUI monitor for Tor. It shows in real time:
- Active circuits with per-hop latency
- Bandwidth in/out
- Logs
- Connections

In my experience, Nyx is the best tool for understanding what Tor is doing at any given
moment. I install it with:

```bash
sudo apt install nyx
nyx
```

---

## Summary of cryptographic guarantees

| Property | Mechanism | Guarantee |
|----------|-----------|-----------|
| Per-hop confidentiality | AES-128-CTR with per-hop keys | Each relay only sees its own layer |
| Forward secrecy | Ephemeral Curve25519 keys | Future compromise doesn't decrypt the past |
| Relay authentication | ntor handshake with long-term key | No MITM possible without private key |
| Cell integrity | Running SHA-1 digest | Cell modifications are detected |
| Anti traffic analysis (partial) | Fixed 514-byte cells + padding | Constant size, configurable padding |
| CircID non-correlation | Per-connection local CircIDs | Not correlatable between different hops |
| Extension limits | RELAY_EARLY counter (max 8) | Prevents excessively long circuits |

---

## See also

- [Circuits, Cryptography and Cells](circuiti-crittografia-e-celle.md) - Protocol hierarchy, cells, RELAY
- [Cryptography and Handshake](crittografia-e-handshake.md) - AES-128-CTR, SENDME, ntor
- [Tor Architecture](architettura-tor.md) - Component overview
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - Circuit attacks and padding
- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - Observing active circuits
- [Real-World Scenarios](scenari-reali.md) - Operational pentesting cases
