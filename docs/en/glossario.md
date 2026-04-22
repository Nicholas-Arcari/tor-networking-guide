> **Lingua / Language**: [Italiano](../glossario.md) | English

# Glossary

Technical terminology used in this guide, with definitions specific to the
Tor and network anonymity context.

---

| Term | Definition |
|------|------------|
| **AES-128-CTR** | Symmetric cipher used by Tor to encrypt cells in circuits. Counter mode, 128-bit key. |
| **AppArmor** | Linux security framework that confines processes (including Tor) by limiting access to files and resources. |
| **AutomapHostsOnResolve** | torrc directive that maps hostnames to virtual IPs for transparent proxying. |
| **Bandwidth Authority** | Server that measures actual relay bandwidth for the consensus (sbws). |
| **Bridge** | Tor relay not publicly listed, used to circumvent censorship. |
| **Cell** | Tor's data unit: fixed 514 bytes (4B CircID + 1B Command + 509B Payload). |
| **CircID** | Circuit identifier (4 bytes), different at each hop of the circuit. |
| **Circuit** | Path of 3 relays (Guard → Middle → Exit) through the Tor network. |
| **Consensus** | Document signed by Directory Authorities listing all relays and their properties. |
| **ControlPort** | TCP port (default 9051) for programmatic control of Tor. |
| **CookieAuthentication** | ControlPort authentication method via cookie file. |
| **CREATE2/CREATED2** | Cells for circuit creation (ntor handshake). |
| **Curve25519** | Elliptic curve used for key exchange in Tor's ntor handshake. |
| **Deanonymization** | Process of identifying a Tor user, defeating anonymity. |
| **Directory Authority (DA)** | One of 9 trusted servers that vote to create the network consensus. |
| **DNSPort** | UDP port where Tor accepts DNS queries and resolves them via circuit. |
| **DPI (Deep Packet Inspection)** | Traffic analysis technique that examines packet contents. |
| **Ed25519** | Digital signature algorithm used by Tor for identity keys and onion services v3. |
| **Exit Node** | The last relay in the circuit, which connects to the final destination. |
| **Exit Policy** | Rules defining which destinations an exit node accepts. |
| **Fingerprint** | SHA-1 hash of a relay's public key (40 hex characters). |
| **First-Party Isolation (FPI)** | Per-first-party-domain isolation in Tor Browser (cookies, cache, etc.). |
| **Flag** | Property assigned to a relay in the consensus (Guard, Exit, Fast, Stable, HSDir, etc.). |
| **Guard Node** | First relay in the circuit, chosen with persistence (~2-3 months). Sees your real IP. |
| **HKDF** | Hash-based Key Derivation Function, used to derive session keys. |
| **HMAC-SHA256** | Message Authentication Code used to verify cell integrity. |
| **HSDir** | Relay responsible for storing onion service descriptors. |
| **iat-mode** | obfs4 mode for resistance to inter-packet timing analysis. |
| **Introduction Point** | Relay where an onion service waits for client connections. |
| **IsolateSOCKSAuth** | SocksPort flag that isolates circuits based on SOCKS5 credentials. |
| **LD_PRELOAD** | Linux mechanism to load libraries before libc, used by proxychains and torsocks. |
| **MaxCircuitDirtiness** | Maximum time (seconds) before a circuit is closed and recreated (default 600). |
| **meek** | Pluggable transport using domain fronting (CDN) to disguise Tor traffic. |
| **Middle Relay** | Second relay in the circuit. Sees neither the client's IP nor the destination. |
| **NEWNYM** | ControlPort signal to change identity (new circuits, new exit IPs). |
| **nftables** | Modern Linux firewall framework, successor to iptables. |
| **ntor** | Tor's cryptographic handshake based on Curve25519 for circuit creation. |
| **Nyx** | TUI monitor for Tor (successor to `arm`). Displays circuits, bandwidth, logs. |
| **obfs4** | Pluggable transport that obfuscates Tor traffic to resist DPI. |
| **Onion Service** | Service accessible only via Tor (.onion address), without an exit node. |
| **OONI** | Open Observatory of Network Interference - measures global Internet censorship. |
| **OR Port** | Port used by relays to communicate with each other (default 9001). |
| **Path Bias** | Tor mechanism that detects circuits failing too often (possible attack). |
| **Pluggable Transport (PT)** | Protocol that transforms Tor traffic to avoid detection. |
| **proxychains** | LD_PRELOAD wrapper that forces applications to use a SOCKS/HTTP proxy. |
| **RELAY_BEGIN** | Relay cell that opens a stream to a destination. |
| **RELAY_DATA** | Relay cell that carries application data. |
| **RELAY_RESOLVE** | Relay cell for resolving DNS via Tor circuit. |
| **Rendezvous Point** | Relay where client and onion service meet to communicate. |
| **SENDME** | Cell for Tor flow control (acknowledges receipt, prevents congestion). |
| **SessionGroup** | Mechanism for grouping streams into isolation groups on SocksPort. |
| **Snowflake** | Pluggable transport based on WebRTC, uses volunteer browsers as proxies. |
| **SO_ORIGINAL_DST** | Linux socket option to retrieve the original destination after iptables REDIRECT. |
| **SocksPort** | Port where Tor accepts SOCKS5 connections from applications (default 9050). |
| **Stem** | Python library for controlling Tor via ControlPort. |
| **Stream** | Individual TCP connection within a Tor circuit. |
| **Stream Isolation** | Separation of streams into different circuits to prevent correlation. |
| **Stylometry** | Writing style analysis to deanonymize the author of a text. |
| **Sybil Attack** | Attack where an adversary controls many relays to dominate the network. |
| **torsocks** | Tor-specific LD_PRELOAD wrapper, actively blocks UDP. |
| **TransPort** | Tor port for transparent proxying (accepts native TCP, not SOCKS). |
| **Vanguards** | Multi-layer persistent relay system to protect onion services. |
| **VirtualAddrNetwork** | Virtual IP range used by AutomapHosts to map hostnames (default 10.192.0.0/10). |
| **Website Fingerprinting** | Attack that identifies which sites a Tor user is visiting by analyzing traffic patterns. |
