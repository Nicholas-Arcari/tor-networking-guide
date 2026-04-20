> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/scenari-reali.md) | English

# Real-World Scenarios - Tor Nodes and Network in Action

Operational cases where knowledge of Tor nodes (guard, exit, bridge) and
monitoring made the difference in real security engagements.

---

## Table of Contents

- [Scenario 1: Malicious exit injects JavaScript during an assessment](#scenario-1-malicious-exit-injects-javascript-during-an-assessment)
- [Scenario 2: Slow guard compromises a time-sensitive reconnaissance](#scenario-2-slow-guard-compromises-a-time-sensitive-reconnaissance)
- [Scenario 3: Bridges blocked during an audit in a censored country](#scenario-3-bridges-blocked-during-an-audit-in-a-censored-country)
- [Scenario 4: Identifying suspicious relays in the chain with Relay Search](#scenario-4-identifying-suspicious-relays-in-the-chain-with-relay-search)

---

## Scenario 1: Malicious exit injects JavaScript during an assessment

### Context

During a web application assessment, the team was using Tor to test the target's
defenses from different perspectives. While analyzing HTTP responses, an operator
noticed a `<script>` tag not present in the site's original source - injected only
when traffic passed through a specific exit.

### Analysis

```bash
# 1. Identify the current exit
printf 'AUTHENTICATE "password"\r\nGETINFO circuit-status\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051 | grep BUILT | head -1
# Output: 12 BUILT $AAAA~Guard,$BBBB~Middle,$CCCC~SuspectExit ...

# 2. Compare responses with different exits
for i in $(seq 1 5); do
    printf 'AUTHENTICATE "password"\r\nSIGNAL NEWNYM\r\nQUIT\r\n' | nc 127.0.0.1 9051
    sleep 3
    proxychains curl -s http://target.example.com | sha256sum
done

# Responses have different hashes when passing through exit $CCCC
# → the exit is modifying HTTP content
```

### Verification in the consensus

```bash
# Check if the exit has the BadExit flag
proxychains curl -s http://128.31.0.34:9131/tor/status-vote/current/consensus \
  | grep -A1 "SuspectExit"
# If it does NOT have BadExit → not yet reported to the DAs
```

### Mitigation

```ini
# torrc - exclude the specific exit
ExcludeExitNodes $CCCC
```

The team then reported the relay to the Directory Authorities via the
bad-relays@lists.torproject.org channel.

### Lesson learned

A malicious exit can only modify **HTTP** unencrypted traffic - end-to-end TLS
protects against this attack. See [exit-nodes.md](exit-nodes.md) for the list
of risks. The rule for every engagement: never send sensitive data via HTTP
through Tor, even for "simple" tests.

---

## Scenario 2: Slow guard compromises a time-sensitive reconnaissance

### Context

Reconnaissance engagement with a limited time window (4 hours). The operator had
Tor configured for weeks with the same guard - which in the meantime had become
overloaded (bandwidth dropped from 5 MB/s to 200 KB/s).

### Problem

Every HTTP request was taking 8-15 seconds instead of the usual 2-3. The operator
was losing precious time during the reconnaissance window.

### Diagnosis

```bash
# Check the current guard
grep EntryGuard /var/lib/tor/state
# EntryGuard SlowRelay FINGERPRINT_SLOW DirCache

# Check the guard's bandwidth on Relay Search
torsocks curl -s "https://onionoo.torproject.org/details?lookup=FINGERPRINT_SLOW" \
  | python3 -c "
import json, sys
r = json.load(sys.stdin)['relays'][0]
print(f'Bandwidth: {r.get(\"observed_bandwidth\",0)//1024} KB/s')
print(f'Flags: {r.get(\"flags\",[])}')
"
# Output: Bandwidth: 180 KB/s  ← very low
```

### Solution (emergency)

```bash
# Reset the guard (only for operational emergencies)
sudo systemctl stop tor@default.service
sudo rm /var/lib/tor/state
sudo systemctl start tor@default.service

# Verify the new guard
grep EntryGuard /var/lib/tor/state
# EntryGuard FastRelay FINGERPRINT_FAST DirCache

# Speed test
time proxychains curl -s https://api.ipify.org
# real 0m2.1s  ← much better
```

### Lesson learned

Guard persistence (see [guard-nodes.md](guard-nodes.md)) is a security feature -
but it can become an operational problem if the guard degrades. In a time-sensitive
engagement, resetting the guard is justifiable. Under normal conditions, it should
never be done because it exposes you to the possibility of selecting a malicious guard.

---

## Scenario 3: Bridges blocked during an audit in a censored country

### Context

The team was operating in a country that had just implemented a new DPI system.
The obfs4 bridges configured in the torrc stopped working every 4-6 hours - the
DPI was identifying them and blocking the IPs.

### Pattern analysis

```bash
# Tor logs during the block
sudo journalctl -u tor@default.service -f
# [warn] Problem bootstrapping. Stuck at 5% (conn). Connection timed out to bridge X
# [warn] Problem bootstrapping. Stuck at 5% (conn). Connection timed out to bridge Y
# → Both bridges blocked
```

The DPI was not blocking obfs4 itself (the protocol is resistant), but was
identifying and blacklisting bridge IPs after an observation period.

### Multi-layer strategy

```ini
# Days 1-2: obfs4 with iat-mode=2 (maximum timing obfuscation)
Bridge obfs4 IP1:PORT1 FP1 cert=CERT1 iat-mode=2
Bridge obfs4 IP2:PORT2 FP2 cert=CERT2 iat-mode=2

# When blocked: Snowflake (IPs change constantly)
ClientTransportPlugin snowflake exec /usr/bin/snowflake-client
Bridge snowflake 192.0.2.3:80 ...

# Final fallback: meek-azure (traffic indistinguishable from Azure CDN)
ClientTransportPlugin meek_lite exec /usr/bin/obfs4proxy
Bridge meek_lite 0.0.2.0:2 ... url=https://meek.azureedge.net/
```

The team maintained 3 ready torrc configurations and switched as needed:
```bash
sudo cp /etc/tor/torrc.obfs4 /etc/tor/torrc && sudo systemctl restart tor
sudo cp /etc/tor/torrc.snowflake /etc/tor/torrc && sudo systemctl restart tor
sudo cp /etc/tor/torrc.meek /etc/tor/torrc && sudo systemctl restart tor
```

### Lesson learned

Censorship resistance is not binary - it must be managed as defense in depth.
The comparison between transports (see [bridge-configurazione-e-alternative.md](bridge-configurazione-e-alternative.md))
shows that each transport has advantages in different scenarios. Preparing multiple
configurations before the engagement is essential.

---

## Scenario 4: Identifying suspicious relays in the chain with Relay Search

### Context

Threat intelligence engagement: the team was monitoring traffic from a threat actor
using onion services. While analyzing circuits with Nyx, they noticed that a middle
relay appeared with anomalous frequency in circuits - statistically improbable
given the network's size.

### Analysis with Onionoo API

```bash
# Relay seen in too many circuits
SUSPECT_FP="AABBCCDD11223344..."

torsocks curl -s "https://onionoo.torproject.org/details?lookup=$SUSPECT_FP" \
  | python3 -c "
import json, sys
r = json.load(sys.stdin)['relays'][0]
print(f'Nickname: {r[\"nickname\"]}')
print(f'AS: {r.get(\"as\",\"?\")}')
print(f'Contact: {r.get(\"contact\",\"none\")}')
print(f'Bandwidth: {r.get(\"observed_bandwidth\",0)//1024} KB/s')
print(f'First seen: {r.get(\"first_seen\",\"?\")}')
print(f'Family: {r.get(\"effective_family\",[])}')
"
```

### Indicators of a suspicious relay

- **Very high bandwidth** without apparent reason (inflated to attract traffic)
- **Recently first seen** + high bandwidth = possible Sybil attack
- **No contact info** + high bandwidth = suspicious
- **Same /16 subnet** as other relays from the same operator (MyFamily not declared)
- **Empty effective family** but relays on the same AS = not declaring MyFamily

### Mitigation

```ini
# torrc - exclude suspicious relays
ExcludeNodes $AABBCCDD11223344...
```

### Lesson learned

Relay monitoring (see [relay-monitoring-e-metriche.md](relay-monitoring-e-metriche.md)
and [monitoring-avanzato.md](monitoring-avanzato.md)) is not only for relay operators.
During threat intelligence, verifying the nodes in the chain is part of OPSEC.
Relay Search and the Onionoo API are tools every pentester should know.

---

## Summary

| Scenario | Node involved | Risk mitigated |
|----------|--------------|----------------|
| Malicious exit | Exit Node | Content injection on HTTP |
| Slow guard | Guard Node | Degraded performance in operational window |
| Blocked bridges | Bridge/PT | Progressive DPI censorship |
| Suspicious relay | Middle Relay | Sybil attack, correlation |

---

## See also

- [Exit Nodes](exit-nodes.md) - Role, risks, exit policy
- [Guard Nodes](guard-nodes.md) - Persistence, selection, attacks
- [Bridges and Pluggable Transports](bridges-e-pluggable-transports.md) - obfs4, censorship resistance
- [Advanced Monitoring](monitoring-avanzato.md) - Relay Search, OONI, scripts
- [Known Attacks](../07-limitazioni-e-attacchi/attacchi-noti.md) - Sybil, malicious exits, correlation
