> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/analisi-forense-e-artefatti.md) | English

# Forensic Analysis and Tor Artifacts

This document analyzes the artifacts that Tor leaves on a system from the
perspective of a forensic analyst. Understanding what Tor writes to disk, in memory,
and in logs is essential both for those who want to minimize traces and for those
who must investigate Tor usage on a system.

> **See also**: [OPSEC and Common Mistakes](./opsec-e-errori-comuni.md) for operational
> errors, [System Hardening](./hardening-sistema.md) for mitigations,
> [Isolation and Compartmentalization](./isolamento-e-compartimentazione.md) for
> amnesic environments.

---
 
## Table of Contents

- [Forensic analysis perspective](#forensic-analysis-perspective)
- [Disk artifacts](#disk-artifacts)
- [System log artifacts](#system-log-artifacts)
- [Memory (RAM) artifacts](#memory-ram-artifacts)
- [Network artifacts](#network-artifacts)
**Deep dives** (dedicated files):
- [Forensic Analysis - Browser, Mitigation and Tools](forense-browser-e-mitigazione.md) - Browser, timeline, mitigation, tools

---

## Forensic analysis perspective

A forensic analyst examining a system looks for evidence that answers:

1. **Is Tor installed?** → packages, binaries, configuration
2. **Has Tor been used?** → logs, state file, cache, timestamps
3. **When was it used?** → log timestamps, file modification times
4. **How was it configured?** → torrc, bridges, exit policy
5. **What was done via Tor?** → browser cache, history, downloads

The answer to these questions depends on the configuration and the
minimization measures adopted by the user.

---

## Disk artifacts

### Tor directory

```
/var/lib/tor/                          ← Main DataDirectory
├── cached-certs                       ← Directory Authorities certificates
├── cached-microdesc-consensus         ← Last downloaded consensus
├── cached-microdescs                  ← Relay microdescriptors
├── cached-microdescs.new              ← Buffer for new microdescriptors
├── state                              ← Persistent state file
├── lock                               ← Lock file (indicates Tor is running)
├── keys/                              ← Relay keys (if configured)
│   ├── ed25519_master_id_secret_key
│   ├── ed25519_signing_secret_key
│   └── secret_onion_key_ntor
└── hidden_service/                    ← Onion service directory (if configured)
    ├── hostname                       ← .onion address
    ├── hs_ed25519_public_key
    └── hs_ed25519_secret_key
```

### State file - critical information

The `state` file contains persistent information:

```
# /var/lib/tor/state
TorVersion 0.4.8.10
LastWritten 2024-12-15 09:23:41
TotalBuildTimes ...
CircuitBuildAbandonedCount 3
Guard in EntryGuard MyGuardNode AABBCCDD... DirCache ...
  ↑ Name and fingerprint of the chosen guard
  ↑ Reveals which guard you used (correlatable with timing)

TransportProxy obfs4 exec /usr/bin/obfs4proxy
  ↑ Reveals use of obfs4 bridge
```

**Forensic significance**: the state file reveals:
- Exact version of Tor used
- Last usage (LastWritten timestamp)
- Chosen guard node (fingerprint → IP derivable from consensus)
- Whether bridges and pluggable transports are used

### Cached consensus

```
/var/lib/tor/cached-microdesc-consensus
```

Contains the entire Tor network consensus (list of all relays).
It is not incriminating per se, but confirms that Tor was used
and indicates the date of the last consensus download.

### torrc configuration

```
/etc/tor/torrc
/etc/tor/instances/*/torrc
```

Reveals:
- Configured ports (SocksPort, ControlPort, DNSPort)
- Bridges used (IP addresses and fingerprints)
- Exit policy (if relay)
- Configured hidden services
- Stream isolation settings

**Bridges in the torrc are particularly sensitive**: they contain bridge IPs
that can be correlated with the user's identity (who requested
those specific bridges?).

### Tor Browser

```
~/tor-browser/
├── Browser/
│   ├── TorBrowser/
│   │   ├── Data/
│   │   │   ├── Browser/profile.default/
│   │   │   │   ├── bookmarks.html          ← bookmarks
│   │   │   │   ├── places.sqlite           ← history + bookmarks DB
│   │   │   │   ├── cookies.sqlite          ← cookies (should be empty)
│   │   │   │   ├── formhistory.sqlite      ← form history
│   │   │   │   ├── permissions.sqlite      ← site permissions
│   │   │   │   ├── webappsstore.sqlite     ← localStorage
│   │   │   │   └── cache2/                 ← HTTP cache
│   │   │   └── Tor/
│   │   │       ├── torrc                   ← integrated Tor config
│   │   │       └── data/                   ← state, consensus, etc.
│   │   └── UpdateInfo/
│   └── start-tor-browser
└── Desktop/
```

Tor Browser is designed to minimize artifacts:
- History and cookies are cleared on close
- Cache in RAM (not on disk by default)
- But: downloading the Tor Browser directory itself is evidence

### Installed packages

```bash
# Evidence of Tor installation
dpkg -l | grep -i tor
# ii  tor         0.4.8.10-1  amd64  anonymizing overlay network
# ii  tor-geoipdb  0.4.8.10-1  all    GeoIP database for Tor
# ii  obfs4proxy   0.0.14-1   amd64  pluggable transport proxy
# ii  nyx          2.1.0-2    all    command-line Tor relay monitor
# ii  torsocks     2.4.0-1    amd64  use SOCKS-friendly apps with Tor

# apt history also reveals when Tor was installed:
grep -i tor /var/log/apt/history.log
```

---

## System log artifacts

### journalctl / syslog

```bash
# Tor service logs
sudo journalctl -u tor@default.service

# Contains:
# - Timestamp of every start/stop
# - Bootstrap messages (connection confirmation)
# - NEWNYM events
# - Warnings and errors
# - Bridge connection attempts
```

Example of incriminating log:

```
Dec 15 09:23:01 kali tor[1234]: Bootstrapped 0% (starting): Starting
Dec 15 09:23:05 kali tor[1234]: Bootstrapped 10% (conn_pt): ...
  ↑ "conn_pt" reveals use of pluggable transport (bridge)
Dec 15 09:23:41 kali tor[1234]: Bootstrapped 100% (done): Done
  ↑ Exact timestamp of when Tor became operational
Dec 15 14:32:15 kali tor[1234]: Received reload signal (hup). ...
Dec 15 14:32:20 kali tor[1234]: NEWNYM command received.
  ↑ Timestamp of identity change → correlatable with activity
```

### auth.log

```bash
# Access to the debian-tor group
grep debian-tor /var/log/auth.log
# Reveals which users have ControlPort access
```

### iptables logs

```bash
# If the transparent proxy with logging is active
grep "TOR-DROP" /var/log/kern.log
# Reveals blocked connection attempts
```

---

## Memory (RAM) artifacts

### What Tor keeps in RAM

When Tor is running, RAM contains:

- **Current circuit keys**: the AES-128-CTR keys for each hop
- **Circuit table**: circuit ID → nodes → associated streams
- **DNS cache**: hostname → IPs resolved via Tor
- **Buffer contents**: data in transit in circuits
- **Consensus**: complete list of relays with flags and bandwidth
- **In-memory state**: chosen guards, circuit build times

### RAM forensics

A RAM dump (e.g., via LiME on Linux) can reveal:

```
# Relevant strings in memory
strings /proc/$(pgrep -f "tor")/mem | grep -i "onion\|circuit\|guard\|relay"

# Note: requires root and unrestricted ptrace
```

Potentially recoverable data:
- Visited .onion URLs (if Tor Browser is open)
- Hostnames resolved via DNS
- Session keys (if captured before deallocation)
- Partial web page content in buffers

### RAM mitigation

- `kernel.yama.ptrace_scope = 2` → prevents ptrace (memory dump)
- Disable crash dump → no core files
- Encrypted or disabled swap → no paging to disk
- Tails: uses RAM only, no persistence

---

## Network artifacts

### Traffic capture

A network observer (ISP, LAN administrator) sees:

```
Direct connection to Tor (without bridge):
  local_IP:random_port → guard_IP:9001 (TLS)
  ↑ The guard's TLS certificate contains the Tor key
  ↑ Identifiable as Tor traffic through:
    - Port 9001 (standard OR port)
    - TLS certificate with specific format
    - Traffic pattern (514-byte cells)

With obfs4 bridge:
  local_IP:random_port → bridge_IP:random_port
  ↑ Obfuscated traffic, NOT identifiable as Tor
  ↑ But: the bridge IP is known (if the ISP knows the bridges)
```

### Conntrack / netstat history

```bash
# Current connections (while Tor is active)
ss -tnp | grep tor
# tcp  ESTAB  127.0.0.1:45678  198.51.100.42:9001  users:(("tor",pid=1234))
# ↑ Reveals the IP of the guard in use
```

### DNS leak evidence

```bash
# If there was a DNS leak, the ISP's DNS server has the logs:
# ISP log: "2024-12-15 14:32:15 client_IP query target-site.com"
# This is permanent and beyond the user's control
```

---

---

> **Continues in**: [Forensic Analysis - Browser, Mitigation and Tools](forense-browser-e-mitigazione.md)
> for browser artifacts, proxychains/torsocks, timeline, mitigation and forensic tools.

---

## See also

- [Forensic Analysis - Browser, Mitigation and Tools](forense-browser-e-mitigazione.md) - Browser, timeline, mitigation, tools
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Mistakes that leave forensic traces
- [System Hardening](hardening-sistema.md) - Reducing the forensic surface with sysctl and AppArmor
- [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) - Tails, Whonix, Qubes for amnesia
- [DNS Leak](dns-leak.md) - DNS artifacts in system logs
- [Real-World Scenarios](scenari-reali.md) - Operational cases from a pentester
