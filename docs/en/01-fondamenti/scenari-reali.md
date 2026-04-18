> **Lingua / Language**: [Italiano](../../01-fondamenti/scenari-reali.md) | English

# Real-World Scenarios - Tor Network Fundamentals in Action

Operational cases where knowledge of Tor fundamentals made the difference during
penetration testing, red teaming and security audit activities.

---

## Table of Contents

- [Scenario 1: Circuit analysis during an external pentest](#scenario-1-circuit-analysis-during-an-external-pentest)
- [Scenario 2: Detecting malicious relays in the chain](#scenario-2-detecting-malicious-relays-in-the-chain)
- [Scenario 3: Censorship bypass with bridges during an international audit](#scenario-3-censorship-bypass-with-bridges-during-an-international-audit)
- [Scenario 4: Verifying consensus integrity after suspected compromise](#scenario-4-verifying-consensus-integrity-after-suspected-compromise)
- [Scenario 5: Circuit correlation and identity leak in a red team](#scenario-5-circuit-correlation-and-identity-leak-in-a-red-team)

---

## Scenario 1: Circuit analysis during an external pentest

### Context

External penetration testing engagement against a target with an aggressive WAF that
blocked IPs after 3 suspicious requests. The team needed to rotate identities frequently
without losing visibility on active circuits.

### Problem

The WAF correlated requests by source IP. Using `SIGNAL NEWNYM` changed the circuit,
but the team wasn't verifying whether the exit node had actually changed. In some cases
the same exit was reselected (non-negligible probability with few exits available on
certain ports).

### Technical solution

```bash
#!/bin/bash
# Verify that the exit actually changes after NEWNYM

OLD_EXIT=$(printf 'AUTHENTICATE "password"\r\nGETINFO circuit-status\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051 | grep "BUILT" | head -1 | grep -oP '\$\w+~\w+' | tail -1)

printf 'AUTHENTICATE "password"\r\nSIGNAL NEWNYM\r\nQUIT\r\n' | nc 127.0.0.1 9051
sleep 2

NEW_EXIT=$(printf 'AUTHENTICATE "password"\r\nGETINFO circuit-status\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051 | grep "BUILT" | head -1 | grep -oP '\$\w+~\w+' | tail -1)

if [ "$OLD_EXIT" = "$NEW_EXIT" ]; then
    echo "[!] Exit unchanged: $OLD_EXIT - retry NEWNYM"
else
    echo "[+] Exit changed: $OLD_EXIT -> $NEW_EXIT"
fi
```

### Lesson learned

Circuit construction (covered in [costruzione-circuiti.md](costruzione-circuiti.md))
does not guarantee a different exit on every NEWNYM. The path selection algorithm balances
bandwidth and availability - if few exits allow the target port, the probability of
reselecting the same one is significant. In that engagement, only 12 exits allowed the
target's port 8443.

---

## Scenario 2: Detecting malicious relays in the chain

### Context

During a threat intelligence activity, the team was monitoring a suspicious onion service.
HTTPS responses contained anomalous headers that didn't match the real server - a possible
sign of MITM by a malicious exit.

### Problem

An exit node was modifying non-TLS HTTP responses (the team had started with HTTP for
initial crawling, before switching to HTTPS). Responses contained injected JavaScript
for tracking.

### Analysis with fundamentals

```bash
# Identify the current exit node
printf 'AUTHENTICATE "password"\r\nGETINFO circuit-status\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051

# Output:
# 42 BUILT $AAAA~GuardOK,$BBBB~MiddleOK,$CCCC~SuspectExit ...

# Verify the exit's flags in the consensus
proxychains curl -s http://128.31.0.34:9131/tor/status-vote/current/consensus \
  | grep -A2 "SuspectExit"

# Look for BadExit flag (not present = not yet reported)
```

Exit $CCCC didn't have the `BadExit` flag because it hadn't been reported yet. The team:
1. Verified the behavior with `ExcludeExitNodes $CCCC` in torrc
2. Confirmed that the injection disappeared with different exits
3. Reported the relay to the Directory Authorities

### Lesson learned

Knowing the consensus structure and flags (see [struttura-consenso-e-flag.md](struttura-consenso-e-flag.md))
allows real-time verification of whether a relay is already known to be malicious. The
`BadExit` flag is reactive, not preventive - DAs only assign it after a report. For
sensitive activities, always use end-to-end HTTPS in addition to Tor encryption.

---

## Scenario 3: Censorship bypass with bridges during an international audit

### Context

Security audit on a client's infrastructure with offices in a country that applies DPI
(Deep Packet Inspection) to block Tor. The team needed to operate from the local office
without revealing Tor usage to the national ISP.

### Problem

Direct connections to Tor relays were being reset by the national firewall within 2-3
seconds of the TLS handshake. The DPI recognized Tor's specific TLS pattern.

### Solution

```
# torrc with obfs4 bridge
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

Bridge obfs4 [IP:PORT] [FINGERPRINT] cert=[CERT] iat-mode=1
Bridge obfs4 [IP2:PORT] [FINGERPRINT2] cert=[CERT2] iat-mode=1
```

With `iat-mode=1`, obfs4 randomizes packet inter-arrival timings, making the traffic
indistinguishable from generic HTTPS for the DPI.

### Bootstrap monitoring

```bash
# Observe bootstrap via ControlPort
watch -n1 'printf "AUTHENTICATE \"password\"\r\nGETINFO status/bootstrap-phase\r\nQUIT\r\n" \
  | nc 127.0.0.1 9051'

# Progressive output:
# BOOTSTRAP PROGRESS=10 TAG=conn_done SUMMARY="Connected to a relay"
# BOOTSTRAP PROGRESS=50 TAG=loading_descriptors SUMMARY="Loading relay descriptors"
# BOOTSTRAP PROGRESS=75 TAG=enough_dirinfo SUMMARY="Loaded enough directory info..."
# BOOTSTRAP PROGRESS=100 TAG=done SUMMARY="Done"
```

Bootstrap with obfs4 bridges takes 30-60 additional seconds compared to a direct
connection, because the client must first connect to the bridge (which is not in the
consensus), then download the consensus and microdescriptors through the bridge.

### Lesson learned

Understanding the bootstrap process (see [architettura-tor.md](architettura-tor.md))
is critical for diagnosing connection issues in censored environments. Bootstrap is the
most vulnerable phase: if it fails at "loading_descriptors" (75%), the problem is almost
always the bridge (insufficient bandwidth or blocked). If it fails at "conn_done" (10%),
the DPI is still blocking the connection.

---

## Scenario 4: Verifying consensus integrity after suspected compromise

### Context

After incident response on a server operating as a Tor relay, the team suspected that an
adversary had manipulated the `state` file and consensus cache in `/var/lib/tor/` to force
selection of specific attacker-controlled guards.

### Forensic analysis

```bash
# 1. Verify state file integrity
cat /var/lib/tor/state | grep EntryGuard
# EntryGuard SuspiciousRelay FINGERPRINT_A DirCache
# EntryGuardAddedBy FINGERPRINT_A 0.4.8.10 2025-11-01 12:00:00

# 2. Compare with current consensus
proxychains curl -s http://128.31.0.34:9131/tor/status-vote/current/consensus \
  > /tmp/consensus-fresh.txt
grep "FINGERPRINT_A" /tmp/consensus-fresh.txt
# Verify that the guard is in the consensus and has Guard + Stable flags

# 3. Check the guard's addition date
# If the guard was added *after* the compromise, it's suspicious

# 4. Verify DA certificates in cache
ls -la /var/lib/tor/cached-certs
sha256sum /var/lib/tor/cached-certs
# Compare with known DA certificate hashes
```

### Indicators of compromise

- Guards added after the estimated compromise date
- Guards not in the current consensus (removed by DAs)
- Certificate cache with non-matching hashes
- `EntryGuardAddedBy` timestamp inconsistent with system logs

### Lesson learned

The persistence of the `state` file and consensus cache (see
[descriptor-cache-e-attacchi.md](descriptor-cache-e-attacchi.md)) can be attack vectors.
An adversary with root access to the system can modify the `state` file to force malicious
guards. In case of compromise, completely regenerating `/var/lib/tor/` and forcing a fresh
bootstrap is the only safe option - but it must be done consciously, as it loses the
protection of persistent guards.

---

## Scenario 5: Circuit correlation and identity leak in a red team

### Context

During a red team engagement, an operator used the same Tor circuit to access both the
target (anonymous reconnaissance) and a personal service (email). This created a
correlation risk: the exit node could see both streams on the same circuit.

### Technical problem

Without stream isolation, Tor multiplexes multiple streams on the same circuit (see
[circuiti-crittografia-e-celle.md](circuiti-crittografia-e-celle.md)). The exit node
observes all streams in plaintext (if not end-to-end encrypted):

```
Circuit 42:
  Stream 1: RELAY_BEGIN -> target.example.com:443 (reconnaissance)
  Stream 2: RELAY_BEGIN -> mail.personal.com:443 (personal email)
```

The exit node doesn't know the client's IP, but can correlate the two destinations
because they transit on the same circuit. If one reveals the operator's identity,
the other is also compromised.

### Applied mitigation

```
# torrc - isolation by SOCKS port
SocksPort 9050 IsolateDestAddr IsolateDestPort  # reconnaissance
SocksPort 9052 IsolateClientAddr                 # personal use

# proxychains for pentest
# /etc/proxychains4-pentest.conf
socks5 127.0.0.1 9050

# proxychains for personal use
# /etc/proxychains4-personal.conf
socks5 127.0.0.1 9052
```

With this configuration, connections to different destinations use different circuits.
The stream to the target and the one to email never share the same exit node.

### Lesson learned

Tor's threat model (see [isolamento-e-modello-minaccia.md](isolamento-e-modello-minaccia.md))
protects against IP correlation but not behavioral correlation. Stream isolation is not
active by default for all ports - it must be explicitly configured. In an engagement, the
rule is: one SocksPort per identity, `IsolateDestAddr` mandatory, never mix operational
and personal traffic.

---

## Summary

| Scenario | Fundamental applied | Risk mitigated |
|----------|-------------------|----------------|
| Circuit analysis | Path selection, ControlPort | Exit not rotated, WAF bypass failed |
| Malicious relays | Consensus flags, BadExit | MITM on HTTP traffic |
| Censorship bypass | Bootstrap, bridge, obfs4 | DPI detection, connection block |
| Consensus integrity | Cache state, persistent guards | Forced guards post-compromise |
| Stream correlation | Stream isolation, multiplexing | Operator identity leak |

---

## See also

- [Tor Architecture](architettura-tor.md) - Components and overview
- [Circuit Construction](costruzione-circuiti.md) - Path selection, NEWNYM
- [Isolation and Threat Model](isolamento-e-modello-minaccia.md) - Stream isolation, threat model
- [Consensus Structure and Flags](struttura-consenso-e-flag.md) - Flags and bandwidth authorities
- [Descriptors, Cache and Attacks](descriptor-cache-e-attacchi.md) - Cache, consensus attacks
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Operational errors to avoid
- [Anonymous Reconnaissance](../09-scenari-operativi/ricognizione-anonima.md) - Operational pentesting usage
