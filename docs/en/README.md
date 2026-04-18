> **Lingua / Language**: [Italiano](../../README.md) | English

# Tor Networking Guide - English Documentation

In-depth technical documentation on the Tor network: protocol-level architecture,
circuit cryptography, operational configuration, analysis tools, operational security,
known attacks and defenses, legal aspects, real-world operational scenarios.

This project collects all technical work and hands-on experience accumulated during the
study and real-world use of the Tor network on Kali Linux (Debian), with proxychains,
obfs4 bridges, ControlPort, automation scripts, and circuit analysis.

**This is not a high-level guide**: every document dives deep into the protocol, cells,
cryptography, and real interactions with the operating system and the network.

---

## Project Structure

### 01 - Fundamentals
Tor internal architecture, cell protocol, ntor handshake, AES-128-CTR/Curve25519
cryptography, consensus and Directory Authorities.

- [Tor Architecture](01-fondamenti/architettura-tor.md) - Bootstrap, components, circuits, stream isolation, threat model
- [Circuits, Cryptography and Cells](01-fondamenti/circuiti-crittografia-e-celle.md) - 514-byte cells, RELAY commands, layered encryption, flow control, ntor handshake
- [Consensus and Directory Authorities](01-fondamenti/consenso-e-directory-authorities.md) - Voting, flags, bandwidth authorities, descriptors, cache

### 02 - Installation and Configuration
Installation, complete torrc configuration (every directive explained), systemd management.

- [Installation and Verification](02-installazione-e-configurazione/installazione-e-verifica.md) - Packages, permissions, debian-tor group, Firefox profile, troubleshooting
- [torrc - Complete Guide](02-installazione-e-configurazione/torrc-guida-completa.md) - SocksPort, DNSPort, ControlPort, bridge, isolation, exit policy, relay config
- [Service Management](02-installazione-e-configurazione/gestione-del-servizio.md) - systemd, logs, bootstrap, signals, debug, maintenance

### 03 - Nodes and Network
Detailed analysis of each node type, bridges and pluggable transports, onion services v3,
monitoring and metrics.

- [Guard Nodes](03-nodi-e-rete/guard-nodes.md) - Persistent selection, state file, path bias, vanguards, attacks
- [Middle Relay](03-nodi-e-rete/middle-relay.md) - Weighted selection, bandwidth weights, separation role
- [Exit Nodes](03-nodi-e-rete/exit-nodes.md) - Exit policy, risks (sniffing, MITM, injection), IP verification, blocks
- [Bridges and Pluggable Transports](03-nodi-e-rete/bridges-e-pluggable-transports.md) - obfs4 internals, meek, Snowflake, DPI resistance, active probing
- [Onion Services v3](03-nodi-e-rete/onion-services-v3.md) - Rendezvous protocol, introduction points, encrypted descriptors
- [Relay Monitoring and Metrics](03-nodi-e-rete/relay-monitoring-e-metriche.md) - Tor Metrics, Prometheus/Grafana, bandwidth accounting, OONI

### 04 - Operational Tools
Practical use of proxychains, torsocks, ControlPort, NEWNYM, leak verification, nyx, browser, DNS.

- [ProxyChains - Complete Guide](04-strumenti-operativi/proxychains-guida-completa.md) - LD_PRELOAD, chain modes, proxy_dns, debugging
- [torsocks](04-strumenti-operativi/torsocks.md) - UDP blocking, IsolatePID, detailed comparison with proxychains, edge cases
- [Circuit Control and NEWNYM](04-strumenti-operativi/controllo-circuiti-e-newnym.md) - ControlPort protocol, commands, Stem (Python), scripts
- [IP, DNS and Leak Verification](04-strumenti-operativi/verifica-ip-dns-e-leak.md) - IP test, DNS leak, IPv6 leak, WebRTC leak, firewall
- [Nyx and Monitoring](04-strumenti-operativi/nyx-e-monitoraggio.md) - TUI monitor, 5 screens, debugging scenarios, Stem scripting
- [Tor Browser and Applications](04-strumenti-operativi/tor-browser-e-applicazioni.md) - Anti-fingerprinting, FPI, application routing, compatibility matrix
- [Tor and DNS - Resolution](04-strumenti-operativi/tor-e-dns-risoluzione.md) - DNSPort, AutomapHosts, SOCKS5 remote DNS, systemd-resolved, DNS hardening

### 05 - Operational Security
DNS leak, traffic analysis, fingerprinting, OPSEC, isolation, hardening, forensics.

- [DNS Leak](05-sicurezza-operativa/dns-leak.md) - Leak scenarios, multilayer prevention, iptables firewall
- [Traffic Analysis](05-sicurezza-operativa/traffic-analysis.md) - End-to-end correlation, website fingerprinting, timing attacks
- [Fingerprinting](05-sicurezza-operativa/fingerprinting.md) - Browser, TLS/JA3, OS, canvas, WebGL, cookieless tracking
- [OPSEC and Common Mistakes](05-sicurezza-operativa/opsec-e-errori-comuni.md) - 10 fatal mistakes, real deanonymization cases, checklist
- [Isolation and Compartmentalization](05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Whonix, Tails, Qubes, network namespaces, Docker
- [System Hardening](05-sicurezza-operativa/hardening-sistema.md) - sysctl, kernel params, AppArmor, nftables, services to disable
- [Digital Forensics and Artifacts](05-sicurezza-operativa/analisi-forense-e-artefatti.md) - Disk, RAM, network, browser artifacts, forensic timeline, mitigation

### 06 - Advanced Configurations
VPN+Tor hybrid, transparent proxy, multi-instance, localhost.

- [VPN and Tor Hybrid](06-configurazioni-avanzate/vpn-e-tor-ibrido.md) - VPN->Tor, Tor->VPN, TransPort, selective routing, ExitNodes
- [Transparent Proxy](06-configurazioni-avanzate/transparent-proxy.md) - iptables/nftables, TransPort internals, IPv6, LAN gateway, troubleshooting, hardening
- [Multi-Instance and Stream Isolation](06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - systemd templates, isolation flags, SessionGroup, Tor Browser model
- [Tor and Localhost](06-configurazioni-avanzate/tor-e-localhost.md) - Local Service Discovery Attack, Docker, web development, local onion services

### 07 - Limitations and Attacks
Protocol limitations, application incompatibilities, documented attacks.

- [Protocol Limitations](07-limitazioni-e-attacchi/limitazioni-protocollo.md) - TCP-only, latency, bandwidth, SOCKS5, multiple circuits
- [Application Limitations](07-limitazioni-e-attacchi/limitazioni-applicazioni.md) - Sites blocking Tor, desktop apps, security tools
- [Known Attacks](07-limitazioni-e-attacchi/attacchi-noti.md) - Sybil, relay early, correlation, website fingerprinting, HSDir, DoS

### 08 - Legal and Ethical Aspects
Legal framework Italy/EU, ethics of anonymity, responsibilities.

- [Legal Aspects](08-aspetti-legali-ed-etici/aspetti-legali.md) - Legality in Italy, GDPR, exit node, bridge, precedents
- [Ethics and Responsibility](08-aspetti-legali-ed-etici/etica-e-responsabilita.md) - Ethical dilemma, case studies, relay operators, surveillance, network contributions

### 09 - Operational Scenarios
Practical Tor usage scenarios in real-world contexts.

- [Anonymous Reconnaissance](09-scenari-operativi/ricognizione-anonima.md) - OSINT via Tor, compatible tools, anti-detection, identity management
- [Secure Communication](09-scenari-operativi/comunicazione-sicura.md) - Anonymous email, SecureDrop, OnionShare, SSH via Tor, messaging
- [Development and Testing](09-scenari-operativi/sviluppo-e-test.md) - Multi-IP testing, geolocation, rate limiting, CI/CD, API debug
- [Incident Response](09-scenari-operativi/incident-response.md) - IP leak recovery, compromised guard, malicious exit, monitoring

### 10 - Practical Lab
Step-by-step guided exercises, from basic setup to advanced isolation.

- [Lab 01 - Setup and Verification](10-laboratorio-pratico/lab-01-setup-e-verifica.md) - Full installation, bootstrap, SocksPort, ControlPort, Firefox profile
- [Lab 02 - Circuit Analysis](10-laboratorio-pratico/lab-02-analisi-circuiti.md) - Stem, nyx, circuit inspection, Python manipulation
- [Lab 03 - DNS Leak Testing](10-laboratorio-pratico/lab-03-dns-leak-testing.md) - tcpdump, --socks5 vs --socks5-hostname, iptables anti-leak
- [Lab 04 - Onion Service](10-laboratorio-pratico/lab-04-onion-service.md) - Onion Service v3, ed25519 keys, x25519 client auth, hardening
- [Lab 05 - Stream Isolation](10-laboratorio-pratico/lab-05-stream-isolation.md) - Multiple SocksPort, multi-instance Tor, separate identities

### [Glossary](glossario.md)
Technical terminology: cells, circuits, handshake, flags, tools, attacks.

---

## See also

- [Italian documentation](../../README.md) - Full Italian version with configs, scripts, and setup
