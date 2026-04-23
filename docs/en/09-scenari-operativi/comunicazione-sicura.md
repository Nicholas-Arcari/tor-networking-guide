> **Lingua / Language**: [Italiano](../../09-scenari-operativi/comunicazione-sicura.md) | English

# Secure Communication via Tor

This document analyzes how to use Tor for secure and anonymous communications:
anonymous email, messaging, file sharing, and dedicated platforms such as
SecureDrop and OnionShare.

> **See also**: [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md),
> [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md),
> [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md).

---

## Table of Contents

- [Threat model for communication](#threat-model-for-communication)
- [Anonymous email via Tor](#anonymous-email-via-tor)
- [Messaging via Tor](#messaging-via-tor)
- [SecureDrop - whistleblowing](#securedrop--whistleblowing)
- [OnionShare - file sharing](#onionshare--file-sharing)
- [SSH via Tor](#ssh-via-tor)
- [IRC and chat via Tor](#irc-and-chat-via-tor)
- [OPSEC for secure communication](#opsec-for-secure-communication)
- [In my experience](#in-my-experience)

---

## Threat model for communication

### What Tor protects in communication

| Aspect | Protected by Tor? | Notes |
|--------|:---:|------|
| Who communicates with whom | Partial | Protects the sender, not always the recipient |
| Message content | No (routing only) | End-to-end encryption required (TLS, PGP) |
| Sender's IP | Yes | The exit/rendezvous hides the real IP |
| Temporal metadata | No | Timing analysis possible |
| Existence of communication | Partial | Tor traffic is visible, not its content |

### Protection levels

```
Level 1: Email via Tor (ProtonMail/Tutanota)
  → Protects sender's IP
  → Provider sees content if not E2E
  
Level 2: E2E messaging via Tor (Signal via Tor, Briar)
  → Protects IP + content
  → Server sees metadata (who talks to whom)
  
Level 3: Communication via onion service (Ricochet, OnionShare)
  → Protects IP + content + metadata
  → No central server
  → P2P via rendezvous
```

---

## Anonymous email via Tor

### ProtonMail via Tor

ProtonMail supports access via Tor:

```
Onion: https://protonmailrmez3lotccipshtkleegetolb73fuirgj7r4o4vfu7ozyd.onion
Web: https://proton.me (via Tor Browser or proxychains)
```

Setup:
```bash
# Access via Tor Browser (recommended)
# Navigate to the .onion address above

# Access via Firefox tor-proxy
proxychains firefox -no-remote -P tor-proxy &
# Navigate to https://proton.me
```

**Limitations**:
- Registration requires verification (email or phone)
- ProtonMail sees metadata (sender, recipient, timestamp)
- Content is E2E encrypted only to other ProtonMail users (or with PGP)

### Tutanota via Tor

```
Web: https://app.tuta.com (via Tor)
```

- Registration without phone (but with rate limiting)
- E2E encrypted to other Tuta users
- For external recipients: shared password to encrypt the message

### Creating an anonymous email account

For a truly anonymous email account:

1. **Use Tor Browser** (not Firefox tor-proxy - less fingerprinting)
2. **Do not use real information** in any field
3. **Never access without Tor** (a single direct access links your IP)
4. **Do not link to your real identity** (no forwarding, no known contacts)
5. **Create the account from a dedicated Tor session** (new NEWNYM identity first)

### PGP via Tor

To encrypt email with PGP:

```bash
# Generate PGP key (do this OFFLINE or via Tor)
torsocks gpg --gen-key

# Publish the key to a keyserver via Tor
torsocks gpg --keyserver hkps://keys.openpgp.org --send-keys KEY_ID

# Search for others' keys via Tor
torsocks gpg --keyserver hkps://keys.openpgp.org --search-keys target@email.com
```

---

## Messaging via Tor

### Signal via Tor (limited)

Signal does not natively support Tor, but it can be configured on Android
with Orbot (Tor proxy):

```
Signal → Settings → Advanced → Proxy → Use SOCKS5 proxy
  Address: 127.0.0.1
  Port: 9050
```

**Limitations**: Signal requires a phone number - not anonymous.

### Briar

Briar is a messenger designed for censorship resistance:
- Can communicate via Tor (onion routing)
- Can communicate via WiFi/Bluetooth (mesh, no Internet needed)
- No central server
- Messages synchronized via Tor P2P bridges

```
Briar architecture:
[User A] ←→ [Tor onion service] ←→ [User B]
  Each user is an onion service
  P2P communication without a server
```

### Ricochet Refresh

Successor to Ricochet, uses Tor onion services for P2P chat:

```
Ricochet architecture:
[User A: abcdef.onion] ←→ [rendezvous] ←→ [User B: ghijkl.onion]
  No central server
  No account
  No metadata
  Identity = .onion address
```

### Messaging comparison

| Platform | Anonymity | E2E | Metadata | Decentralized |
|----------|:---------:|:---:|:--------:|:-------------:|
| Email (ProtonMail) | IP hidden | Yes (between users) | Provider sees them | No |
| Signal via Tor | IP hidden | Yes | Server sees them | No |
| Briar | Strong | Yes | None | Yes |
| Ricochet Refresh | Strong | Yes | None | Yes |
| IRC via Tor | IP hidden | No (without OTR) | Server sees them | Depends |
| XMPP via Tor + OMEMO | IP hidden | Yes | Server sees them | Federated |

---

## SecureDrop - whistleblowing

### What is SecureDrop

SecureDrop is an open-source platform for anonymous whistleblowing, used by
newspapers and organizations to receive documents securely:

```
SecureDrop architecture:
[Whistleblower] → [Tor Browser] → [.onion SecureDrop]
  → Upload encrypted document
  → Journalist accesses from air-gapped network
  → Bidirectional anonymous communication via codename
```

### How it works

1. The whistleblower accesses the newspaper's `.onion` address via Tor Browser
2. Receives a unique **codename** (e.g., "autumn elephant notebook")
3. Uploads documents and messages
4. The journalist downloads from an air-gapped system (Tails on dedicated hardware)
5. The whistleblower can return with the codename to read responses

### Notable SecureDrop instances

| Organization | Use |
|-------------|-----|
| The New York Times | Investigative journalism |
| The Washington Post | Whistleblowing |
| The Guardian | Investigative journalism |
| WikiLeaks | Document leaks |
| ProPublica | Investigations |

### OPSEC for SecureDrop

- **Use Tails** (officially recommended), not Kali with Tor
- **Never access from the whistleblower's corporate network**
- **Do not mention identifying details** in messages
- **Memorize the codename**, do not write it down

---

## OnionShare - file sharing

### What is OnionShare

OnionShare creates a temporary onion service to share files P2P:

```bash
# Installation
sudo apt install onionshare-cli

# Share a file
onionshare-cli --receive  # receive files
onionshare-cli file.zip   # share a file
```

### How it works

```
[Sender] → OnionShare creates a temporary onion service
  → Generates .onion URL + password
  → Shares URL with recipient (via secure channel)

[Recipient] → Tor Browser → .onion URL
  → Downloads file directly from the sender's computer
  → No intermediary server
  → File never on cloud or third parties
```

### Modes

| Mode | Command | Description |
|------|---------|-------------|
| Share | `onionshare-cli file.zip` | Share files (others download from you) |
| Receive | `onionshare-cli --receive` | Receive files (others upload to you) |
| Website | `onionshare-cli --website ./site/` | Temporary .onion hosting |
| Chat | `onionshare-cli --chat` | Temporary anonymous chat room |

### Advantages vs alternatives

| Method | Server required | E2E | Anonymity | Size limits |
|--------|:-:|:-:|:-:|:-:|
| OnionShare | No (P2P) | Yes (TLS .onion) | Native Tor | None |
| Email + PGP | Yes (SMTP) | Yes | With Tor | ~25 MB |
| Signal | Yes | Yes | With Tor | 100 MB |
| Cloud (GDrive) | Yes | No | No | Varies |

---

## SSH via Tor

### Anonymous SSH connection

```bash
# Via torsocks (recommended for IsolatePID)
torsocks ssh user@server.com

# Via proxychains
proxychains ssh user@server.com

# Via native SSH ProxyCommand
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:9050 %h %p" user@server.com

# Persistent in ~/.ssh/config
Host anonymous-server
    HostName server.com
    User user
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

### SSH to an onion service

```bash
# Direct connection to .onion (no exit node involved)
torsocks ssh user@abcdef...xyz.onion

# In ~/.ssh/config
Host hidden-server
    HostName abcdef...xyz.onion
    User user
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

### SSH via Tor security considerations

| Aspect | Risk | Mitigation |
|--------|------|------------|
| Host key fingerprint | Malicious exit could MITM | Verify fingerprint out-of-band |
| Latency | ~200-500ms per hop - slow for interactive use | Use mosh (not via Tor) |
| Session persistence | Circuit changes - disconnection | ClientKeepAlive, high MaxCircuitDirtiness |
| Username exposure | Exit sees username (if not .onion) | Use key auth, not password |

---

## IRC and chat via Tor

### IRC via Tor

```bash
# IRC connection via torsocks
torsocks irssi -c irc.libera.chat -p 6697 --ssl

# Or via proxychains
proxychains weechat
# Then: /server add libera irc.libera.chat/6697 -ssl
```

**Note**: many IRC servers block connections from Tor exit nodes. Alternatives:
- Use servers with onion services (OFTC, Libera Chat have .onion addresses)
- Use SASL auth to be authorized despite Tor

### Matrix via Tor

```bash
# Element (Matrix client) via Tor
proxychains element-desktop &

# Homeserver via Tor: the IP is hidden
# But: the homeserver sees messages (if not E2E)
# With E2E active: the homeserver sees only metadata
```

---

## OPSEC for secure communication

### Fundamental rules

1. **Never mix identities**: one Tor session = one identity
2. **NEWNYM between different identities**: change circuit between different activities
3. **Do not use identifiable services in the same session**: if you access Gmail,
   do not use the same circuit for anonymous communication
4. **Always verify the IP before communicating**: `proxychains curl https://api.ipify.org`
5. **Encrypt when possible**: Tor protects routing, not content

### Writing patterns

**Stylometry** (writing style analysis) can deanonymize:
- Average sentence length
- Characteristic punctuation
- Recurring grammatical errors
- Specific vocabulary
- Use of regional expressions

**Mitigation**: for critical communications, use neutral and formal language,
avoid personal expressions, review the text before sending.

---

## In my experience

I have tested various communication methods via Tor:

**ProtonMail via .onion**: works well, the .onion address loads more
slowly but is the most secure method. I used it to register an email
account dedicated to study.

**OnionShare**: I tested it to share files between two machines on the
same network (one with Tor Browser, the other with onionshare-cli). It works
perfectly, although the transfer is slow due to the 6 total hops
(3 from sender to rendezvous + 3 from receiver to rendezvous).

**SSH via Tor**: I use `torsocks ssh` for connections where I do not want to
expose my IP. The latency is noticeable (~300ms per hop), making interactive
use uncomfortable. For long sessions, the expiring circuit (MaxCircuitDirtiness 600s)
can cause disconnections - I had to increase `ServerAliveInterval` in the
SSH config.

**IRC via Tor**: I tried connecting to Libera Chat via Tor. The connection
is blocked by default (Tor exit nodes are banned). I had to use SASL auth
and request an exception. Alternative: use the OFTC .onion address.

The takeaway: Tor is excellent for protecting the sender's IP, but it is not
sufficient on its own. End-to-end encryption is needed for content, rigorous
OPSEC for metadata, and identity separation to prevent correlation.

---

## See also

- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Mistakes in anonymous communication
- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) - Rendezvous protocol for hidden services
- [Isolation and Compartmentalization](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Tails for high-risk communication
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) - Fingerprinting risks in communications
