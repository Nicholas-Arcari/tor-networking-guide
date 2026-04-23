> **Lingua / Language**: [Italiano](../../10-laboratorio-pratico/lab-05-stream-isolation.md) | English

# Lab 05 - Stream Isolation and Multi-Instance Tor

A hands-on exercise to configure stream isolation with multiple SocksPorts,
separate Tor instances, and verify that traffic from different applications
travels over independent circuits.

**Estimated time**: 40-50 minutes
**Prerequisites**: Lab 01 completed, root access, Python 3
**Difficulty**: Advanced

---

## Table of Contents

- [Objectives](#objectives)
- [Phase 1: Understanding stream isolation](#phase-1-understanding-stream-isolation)
- [Phase 2: Multiple SocksPorts with IsolateDestAddr](#phase-2-multiple-socksports-with-isolatedestaddr)
- [Phase 3: Verifying isolation](#phase-3-verifying-isolation)
- [Phase 4: Multi-instance Tor](#phase-4-multi-instance-tor)
- [Phase 5: Routing applications to different instances](#phase-5-routing-applications-to-different-instances)
- [Phase 6: Automated verification script](#phase-6-automated-verification-script)
- [Phase 7: Operational scenario - separate identities](#phase-7-operational-scenario--separate-identities)
- [Final checklist](#final-checklist)

---

## Objectives

By the end of this lab, you will know how to:
1. Configure multiple SocksPorts with different isolation flags
2. Verify that different circuits are actually being used
3. Configure and manage independent Tor instances with systemd
4. Assign applications to specific instances/ports
5. Implement identity separation at the network level

---

## Phase 1: Understanding stream isolation

```
Without isolation:
  Browser ──┐
  curl    ──┼── SocksPort 9050 ──→ Circuit A ──→ Exit X
  wget    ──┘

With isolation (IsolateDestAddr):
  Browser → example.com ──→ SocksPort 9050 ──→ Circuit A ──→ Exit X
  Browser → torproject.org ──→ SocksPort 9050 ──→ Circuit B ──→ Exit Y
  (same SocksPort, different circuits for different destinations)

With multiple SocksPorts:
  Browser ──→ SocksPort 9050 ──→ Circuit A ──→ Exit X
  curl    ──→ SocksPort 9052 ──→ Circuit B ──→ Exit Y
  wget    ──→ SocksPort 9054 ──→ Circuit C ──→ Exit Z
  (different ports = guaranteed independent circuits)
```

```bash
# Check the current configuration
grep "SocksPort" /etc/tor/torrc
# Likely output: SocksPort 9050

# Check the default isolation flags
# Tor automatically applies: IsolateClientAddr IsolateSOCKSAuth IsolateClientProtocol IsolateDestPort
# This means that connections from the same app to the same destination
# port use the same circuit
```

---

## Phase 2: Multiple SocksPorts with IsolateDestAddr

```bash
# Configure dedicated SocksPorts for different purposes
sudo tee -a /etc/tor/torrc << 'EOF'

# === Lab 05 - Stream Isolation ===
# Generic port (standard isolation)
# SocksPort 9050 already configured

# Port for browser (isolate by destination address)
SocksPort 9052 IsolateDestAddr IsolateDestPort

# Port for communications (isolate by SOCKS authentication)
SocksPort 9054 IsolateSOCKSAuth

# Port for downloads (no isolation - maximum circuit reuse)
SocksPort 9056 NoIsolateClientAddr NoIsolateSOCKSAuth NoIsolateClientProtocol NoIsolateDestPort NoIsolateDestAddr

# Port for sensitive operations (maximum isolation)
SocksPort 9058 IsolateClientAddr IsolateSOCKSAuth IsolateClientProtocol IsolateDestPort IsolateDestAddr
EOF

# Restart Tor
sudo systemctl restart tor@default.service
sleep 3

# Verify that all ports are active
for port in 9050 9052 9054 9056 9058; do
    if ss -tlnp | grep -q ":$port "; then
        echo "SocksPort $port: ACTIVE"
    else
        echo "SocksPort $port: NOT ACTIVE - check the logs"
    fi
done
```

**Verification**: all 5 ports respond.

---

## Phase 3: Verifying isolation

```bash
# Test 1: Standard SocksPort (9050) - same circuit for same destination
echo "=== SocksPort 9050 (default) ==="
IP1=$(curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://api.ipify.org)
IP2=$(curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://api.ipify.org)
echo "Request 1: $IP1"
echo "Request 2: $IP2"
echo "Same IP (same circuit reused): $([ "$IP1" = "$IP2" ] && echo YES || echo NO)"

# Test 2: SocksPort 9052 (IsolateDestAddr) - different circuits for different hosts
echo ""
echo "=== SocksPort 9052 (IsolateDestAddr) ==="
IP_A=$(curl --socks5-hostname 127.0.0.1:9052 -s --max-time 20 https://api.ipify.org)
IP_B=$(curl --socks5-hostname 127.0.0.1:9052 -s --max-time 20 https://httpbin.org/ip | grep -oP '"origin":\s*"\K[^"]+')
echo "api.ipify.org sees: $IP_A"
echo "httpbin.org sees:   $IP_B"
echo "Different IPs (isolation OK): $([ "$IP_A" != "$IP_B" ] && echo YES || echo NO)"

# Test 3: SocksPort 9058 (maximum isolation) - always different circuits
echo ""
echo "=== SocksPort 9058 (max isolation) ==="
for i in 1 2 3; do
    IP=$(curl --socks5-hostname 127.0.0.1:9058 -s --max-time 20 https://api.ipify.org)
    echo "Request $i: $IP"
done
echo "(May be different on each request)"
```

```bash
# Test 4: Observe circuits with Stem
python3 << 'PYEOF'
import stem
from stem.control import Controller
import time

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()

    print("Active circuits:")
    print("-" * 60)
    for circ in ctrl.get_circuits():
        if circ.status == "BUILT":
            path = " → ".join([
                f"{nick}({fp[:8]})"
                for fp, nick in circ.path
            ])
            print(f"  Circuit {circ.id}: {path}")
            if circ.purpose:
                print(f"    Purpose: {circ.purpose}")
    print(f"\nTotal built circuits: {sum(1 for c in ctrl.get_circuits() if c.status == 'BUILT')}")
PYEOF
```

**Exercise**: how many circuits do you see after running all 4 tests?
Can you correlate each circuit with the tests performed?

---

## Phase 4: Multi-instance Tor

```bash
# Create a second completely independent Tor instance
# Each instance has: separate torrc, DataDirectory, SocksPort, ControlPort

# 1. Create the data directory
sudo mkdir -p /var/lib/tor-instances/lab05
sudo chown debian-tor:debian-tor /var/lib/tor-instances/lab05
sudo chmod 700 /var/lib/tor-instances/lab05

# 2. Create the dedicated torrc
sudo tee /etc/tor/instances/lab05/torrc << 'EOF'
# Second Tor instance - independent from the main one
SocksPort 9060
ControlPort 9061
CookieAuthentication 1

# DataDirectory managed automatically by tor@lab05
# /var/lib/tor-instances/lab05/

Log notice file /var/log/tor/tor-lab05.log
EOF

# 3. Create the configuration directory (Debian/Kali)
sudo mkdir -p /etc/tor/instances/lab05

# 4. Start the second instance
sudo systemctl start tor@lab05.service
sudo systemctl status tor@lab05.service
# Expected output: active (running)

# 5. Verify the bootstrap
sleep 10
sudo journalctl -u tor@lab05.service --no-pager | grep "Bootstrapped 100%"
```

```bash
# Verify that the two instances are independent
echo "=== Main instance (9050) ==="
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://api.ipify.org

echo "=== Lab05 instance (9060) ==="
curl --socks5-hostname 127.0.0.1:9060 -s --max-time 20 https://api.ipify.org

# The two instances have completely independent circuits
# They do not share guard nodes, circuits, or state
```

```bash
# Compare the guard nodes of the two instances
python3 << 'PYEOF'
from stem.control import Controller

for name, port in [("Main", 9051), ("Lab05", 9061)]:
    try:
        with Controller.from_port(port=port) as ctrl:
            ctrl.authenticate()
            guards = set()
            for circ in ctrl.get_circuits():
                if circ.status == "BUILT" and circ.path:
                    guards.add(circ.path[0][1])  # guard nickname
            print(f"Instance {name} (:{port}) - Guard nodes: {guards or 'none yet'}")
    except Exception as e:
        print(f"Instance {name} (:{port}) - Error: {e}")
PYEOF
# The guard nodes MUST be different (independent instances)
```

---

## Phase 5: Routing applications to different instances

```bash
# Scenario: separate browser traffic from CLI traffic

# Configure proxychains for each instance
# Profile 1: main instance (browser)
sudo tee /etc/proxychains-browser.conf << 'EOF'
strict_chain
proxy_dns
[ProxyList]
socks5 127.0.0.1 9050
EOF

# Profile 2: lab05 instance (CLI and downloads)
sudo tee /etc/proxychains-cli.conf << 'EOF'
strict_chain
proxy_dns
[ProxyList]
socks5 127.0.0.1 9060
EOF

# Use specific profiles
echo "Browser (instance 1):"
proxychains -f /etc/proxychains-browser.conf curl -s --max-time 20 https://api.ipify.org

echo "CLI (instance 2):"
proxychains -f /etc/proxychains-cli.conf curl -s --max-time 20 https://api.ipify.org
# Different IPs = independent instances confirmed
```

```bash
# Practical example: browser and terminal on separate identities
# Terminal 1 - Firefox on main instance
proxychains -f /etc/proxychains-browser.conf firefox -no-remote -P tor-proxy &

# Terminal 2 - CLI operations on separate instance
PROXYCHAINS_CONF_FILE=/etc/proxychains-cli.conf proxychains wget -q \
    -O /dev/null https://check.torproject.org

# The browser and terminal use different exit nodes
# → they cannot be correlated by an observer
```

---

## Phase 6: Automated verification script

Create the file `test-stream-isolation.sh`:

```bash
#!/bin/bash
# test-stream-isolation.sh - Verify stream isolation and multi-instance
set -euo pipefail

PASS=0
FAIL=0
TIMEOUT=25

green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }

check() {
    local desc="$1" result="$2"
    if [ "$result" = "OK" ]; then
        green "  ✓ $desc"
        PASS=$((PASS+1))
    else
        red "  ✗ $desc - $result"
        FAIL=$((FAIL+1))
    fi
}

echo "=== Stream Isolation Test ==="
echo ""

# Test 1: all ports active
echo "--- SocksPort Ports ---"
for port in 9050 9052 9054 9056 9058 9060; do
    if ss -tlnp | grep -q ":$port "; then
        check "SocksPort $port active" "OK"
    else
        check "SocksPort $port active" "FAIL: port not listening"
    fi
done

echo ""
echo "--- Isolation by destination (SocksPort 9052) ---"
IP_A=$(curl --socks5-hostname 127.0.0.1:9052 -s --max-time $TIMEOUT https://api.ipify.org 2>/dev/null || echo "ERROR")
IP_B=$(curl --socks5-hostname 127.0.0.1:9052 -s --max-time $TIMEOUT https://httpbin.org/ip 2>/dev/null | grep -oP '"origin":\s*"\K[^"]+' || echo "ERROR")
if [ "$IP_A" != "$IP_B" ] && [ "$IP_A" != "ERROR" ] && [ "$IP_B" != "ERROR" ]; then
    check "IsolateDestAddr: different IPs for different hosts ($IP_A ≠ $IP_B)" "OK"
else
    check "IsolateDestAddr: different IPs for different hosts" "FAIL: $IP_A vs $IP_B"
fi

echo ""
echo "--- Isolation between instances ---"
IP_MAIN=$(curl --socks5-hostname 127.0.0.1:9050 -s --max-time $TIMEOUT https://api.ipify.org 2>/dev/null || echo "ERROR")
IP_LAB=$(curl --socks5-hostname 127.0.0.1:9060 -s --max-time $TIMEOUT https://api.ipify.org 2>/dev/null || echo "ERROR")
if [ "$IP_MAIN" != "$IP_LAB" ] && [ "$IP_MAIN" != "ERROR" ] && [ "$IP_LAB" != "ERROR" ]; then
    check "Independent instances: different IPs ($IP_MAIN ≠ $IP_LAB)" "OK"
elif [ "$IP_MAIN" = "ERROR" ] || [ "$IP_LAB" = "ERROR" ]; then
    check "Independent instances" "FAIL: connection failed"
else
    check "Independent instances" "WARN: same IP (can happen, repeat the test)"
fi

echo ""
echo "--- Results ---"
echo "PASS: $PASS  FAIL: $FAIL"
[ $FAIL -eq 0 ] && green "All tests passed!" || red "Some tests failed."
```

```bash
chmod +x test-stream-isolation.sh
./test-stream-isolation.sh
```

---

## Phase 7: Operational scenario - separate identities

Scenario: a researcher needs to maintain two completely separate online
identities - one for collecting public information, the other for
communicating with sources.

```bash
# Architecture:
#
# Identity A (OSINT)            Identity B (Communication)
#   Firefox profile osint         Firefox profile comms
#        ↓                            ↓
#   proxychains 9050             proxychains 9060
#        ↓                            ↓
#   tor@default                  tor@lab05
#   Guard: G1                    Guard: G2
#   Exit: different              Exit: different
#
# The two identities DO NOT share:
# - Guard node
# - Circuits
# - Session cookies (separate Firefox profiles)
# - Usage time (using them at different times reduces correlation)

# Preparation for identity A
firefox -no-remote -CreateProfile osint 2>/dev/null
proxychains -f /etc/proxychains-browser.conf firefox -no-remote -P osint &

# Preparation for identity B (in another terminal)
firefox -no-remote -CreateProfile comms 2>/dev/null
proxychains -f /etc/proxychains-cli.conf firefox -no-remote -P comms &
```

**Operational rules**:
1. **Never** use both identities simultaneously on the same network
2. **Never** access the same accounts from both identities
3. Change circuit (NEWNYM) before switching from one identity to the other
4. Maintain different writing styles and behaviors
5. Use different connection times when possible

---

## Troubleshooting

### Extra ports do not activate

```bash
# Verify configuration errors
sudo tor --verify-config 2>&1 | grep -i error

# Common cause: port conflict with other services
for port in 9052 9054 9056 9058; do
    if ss -tlnp | grep -q ":$port "; then
        echo "Port $port: OK"
    else
        echo "Port $port: CONFLICT - something is already using it?"
        ss -tlnp | grep ":$port " || echo "  (port free but Tor is not using it - check torrc)"
    fi
done

# If Tor does not start at all after torrc changes:
sudo journalctl -u tor@default.service --no-pager | tail -20
# Look for: "Failed to parse" or "Could not bind"
```

### Isolation does not work (same IP on different ports)

```bash
# IsolateDestAddr isolates by DESTINATION, not by request.
# If you request the same URL on different ports with IsolateDestAddr,
# Tor may reuse the same circuit (same destination!)

# For reliable tests, use DIFFERENT destinations:
curl --socks5-hostname 127.0.0.1:9052 -s https://api.ipify.org      # site A
curl --socks5-hostname 127.0.0.1:9052 -s https://httpbin.org/ip      # site B
# These MUST give different IPs with IsolateDestAddr

# To force different circuits even to the same site,
# use the port with maximum isolation (9058)
```

### The second Tor instance does not bootstrap

```bash
# Verify that the configuration directory exists
ls -la /etc/tor/instances/lab05/torrc

# Verify that the DataDirectory has correct permissions
sudo ls -la /var/lib/tor-instances/lab05/
# Should be: owner debian-tor, permissions 700

# Check the instance-specific logs
sudo journalctl -u tor@lab05.service --no-pager | tail -20

# If the error is "No such file": Debian/Kali uses the tor@<name> pattern
# Configuration must be in /etc/tor/instances/<name>/torrc
```

---

## Cleanup

```bash
# Stop the lab05 instance
sudo systemctl stop tor@lab05.service
sudo systemctl disable tor@lab05.service 2>/dev/null

# Remove the multi-instance configuration
sudo rm -rf /etc/tor/instances/lab05/
sudo rm -rf /var/lib/tor-instances/lab05/
sudo rm -f /var/log/tor/tor-lab05.log

# Remove the extra ports from the main torrc
sudo sed -i '/# === Lab 05/,/^$/d' /etc/tor/torrc
sudo sed -i '/SocksPort 905[2468]/d' /etc/tor/torrc

# Remove the extra proxychains files
sudo rm -f /etc/proxychains-browser.conf /etc/proxychains-cli.conf

# Restart Tor with the clean configuration
sudo systemctl restart tor@default.service

# Remove the lab Firefox profiles
rm -rf ~/.mozilla/firefox/*osint* ~/.mozilla/firefox/*comms*
```

---

## Final checklist

- [ ] Multiple SocksPorts (9050, 9052, 9054, 9056, 9058) configured and active
- [ ] IsolateDestAddr verified: different hosts produce different exit nodes
- [ ] IsolateSOCKSAuth understood and tested
- [ ] Second Tor instance (tor@lab05) started on SocksPort 9060
- [ ] Different guard nodes between the two instances verified with Stem
- [ ] Separate proxychains profiles working
- [ ] Automated test script executed successfully
- [ ] Separate identities scenario understood and configured
- [ ] Cleanup performed, configuration restored

---

## See also

- [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Complete configuration
- [Isolation and Compartmentalization](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Separation strategies
- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - Circuit management
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Correlation errors
