> **Lingua / Language**: [Italiano](../../10-laboratorio-pratico/lab-01-setup-e-verifica.md) | English

# Lab 01 - Complete Tor Setup and Verification

A hands-on exercise to install, configure, and verify a complete Tor setup
on Kali Linux (Debian-based). Each step includes the command, expected output,
and what to verify.

**Estimated time**: 30-45 minutes
**Prerequisites**: Kali Linux, root access, Internet connection
**Difficulty**: Basic

---

## Table of Contents

- [Objectives](#objectives)
- [Phase 1: Package installation](#phase-1-package-installation)
- [Phase 2: torrc configuration](#phase-2-torrc-configuration)
- [Phase 3: Startup and bootstrap](#phase-3-startup-and-bootstrap)
- [Phase 4: Connection verification](#phase-4-connection-verification)
- [Phase 5: ControlPort test](#phase-5-controlport-test)
- [Phase 6: DNS verification](#phase-6-dns-verification)
- [Phase 7: Firefox profile](#phase-7-firefox-profile)
- [Final checklist](#final-checklist)

---

## Objectives

By the end of this lab, you will have:
1. Tor installed and running as a systemd service
2. SocksPort, ControlPort, and DNSPort configured
3. proxychains4 configured with proxy_dns
4. A dedicated Firefox profile for browsing via Tor
5. All verification tests passed

---

## Phase 1: Package installation

```bash
# Install Tor and required tools
sudo apt update
sudo apt install -y tor proxychains4 torsocks nyx curl netcat-openbsd xxd

# Verify the installation
tor --version
# Expected output: Tor version 0.4.x.x
proxychains4 -h 2>&1 | head -1
# Expected output: ProxyChains-4.x
```

**Verification**: all packages installed without errors.

---

## Phase 2: torrc configuration

```bash
# Back up the original torrc
sudo cp /etc/tor/torrc /etc/tor/torrc.backup

# Add the required configurations
sudo tee -a /etc/tor/torrc << 'EOF'

# === Lab 01 Config ===
SocksPort 9050
DNSPort 5353
ControlPort 9051
CookieAuthentication 1
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
ClientUseIPv6 0
Log notice file /var/log/tor/tor.log
EOF

# Add the user to the debian-tor group
sudo usermod -aG debian-tor $USER
# NOTE: the group becomes active on next login or with: newgrp debian-tor
```

**Verification**: `grep -c "^[^#]" /etc/tor/torrc` should show the active directives.

---

## Phase 3: Startup and bootstrap

```bash
# Restart Tor with the new configuration
sudo systemctl restart tor@default.service

# Check the status
sudo systemctl status tor@default.service
# Expected output: active (running)

# Verify the bootstrap
sudo journalctl -u tor@default.service --no-pager | grep "Bootstrapped"
# Expected output: Bootstrapped 100% (done): Done
```

**Verification**: the bootstrap reaches 100%. If it stalls, check:
- Active Internet connection
- No firewall blocking outbound connections
- Logs: `sudo tail -20 /var/log/tor/tor.log`

---

## Phase 4: Connection verification

```bash
# Test 1: IP via Tor (direct SOCKS5)
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://api.ipify.org
# Expected output: an IP different from your real IP

# Test 2: IsTor verification
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://check.torproject.org/api/ip
# Expected output: {"IsTor":true,"IP":"xxx.xxx.xxx.xxx"}

# Test 3: proxychains
proxychains curl -s --max-time 20 https://api.ipify.org
# Expected output: a Tor exit IP (may differ from test 1)

# Test 4: IP comparison
echo "Real IP: $(curl -s https://api.ipify.org)"
echo "Tor IP:  $(curl --socks5-hostname 127.0.0.1:9050 -s https://api.ipify.org)"
# The two IPs MUST be different
```

**Verification**: all 4 tests show Tor IPs different from your real IP.

---

## Phase 5: ControlPort test

```bash
# Verify that the cookie is readable
ls -la /run/tor/control.authcookie
# Output: the file must exist and your user must be able to read it

# Authentication and query
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
printf "AUTHENTICATE %s\r\nGETINFO version\r\nQUIT\r\n" "$COOKIE" | \
    nc -w 5 127.0.0.1 9051
# Expected output:
# 250 OK
# 250-version=0.4.x.x
# 250 OK
# 250 closing connection

# NEWNYM test
printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | \
    nc -w 5 127.0.0.1 9051
# Expected output: two "250 OK" lines
```

**Verification**: authentication and NEWNYM work correctly.

---

## Phase 6: DNS verification

```bash
# tor-resolve test
tor-resolve example.com
# Expected output: an IP (e.g., 93.184.216.34)

# DNS leak test: capture DNS while using Tor
sudo tcpdump -i eth0 port 53 -c 5 -n &
TCPDUMP_PID=$!
sleep 1
curl --socks5-hostname 127.0.0.1:9050 -s https://example.com > /dev/null
sleep 3
sudo kill $TCPDUMP_PID 2>/dev/null
# Expected output: NO DNS queries captured (0 packets)
# If queries appear → there is a DNS leak → review the configuration
```

**Verification**: no DNS queries captured by tcpdump during the Tor connection.

---

## Phase 7: Firefox profile

```bash
# Create a dedicated profile
firefox -no-remote -CreateProfile tor-proxy

# Launch Firefox with the profile via proxychains
proxychains firefox -no-remote -P tor-proxy &

# In Firefox, configure about:config:
# media.peerconnection.enabled = false
# network.dns.disablePrefetch = true
# network.prefetch-next = false
# privacy.resistFingerprinting = true
# webgl.disabled = true
# network.http.http3.enabled = false
# network.proxy.socks_remote_dns = true
```

**Verification**: visit https://check.torproject.org - it should display "Congratulations. This browser is configured to use Tor."

---

## Troubleshooting

### Bootstrap stalled (does not reach 100%)

```bash
# Check the logs to understand where it stalls
sudo journalctl -u tor@default.service --no-pager | tail -30

# Common causes:
# "Problem bootstrapping. Stuck at X%: Connecting to a relay"
# → Firewall or ISP blocking Tor connections (port 443/9001)
# → Solution: use an obfs4 bridge

# "Clock skew detected"
# → System clock is off (Tor requires ±30 minutes accuracy)
# → Solution:
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# "Could not bind to 127.0.0.1:9050: Address already in use"
# → Another Tor instance is already running
# → Solution:
sudo systemctl stop tor@default.service
sudo killall tor 2>/dev/null
sudo systemctl start tor@default.service
```

### ControlPort not responding

```bash
# Verify that the port is listening
ss -tlnp | grep 9051
# If empty → ControlPort not configured in torrc

# Verify cookie permissions
ls -la /run/tor/control.authcookie
# If "Permission denied" → user is not in the debian-tor group
groups $USER | grep debian-tor || echo "MISSING: run sudo usermod -aG debian-tor $USER and re-login"
```

### proxychains shows "connection refused"

```bash
# Verify that Tor is active and the SOCKS port is open
ss -tlnp | grep 9050
# If empty → Tor is not running or SocksPort is not configured

# Verify the proxychains configuration
grep -v "^#" /etc/proxychains4.conf | grep socks
# Should show: socks5 127.0.0.1 9050
```

---

## Final checklist

- [ ] Tor installed and service active
- [ ] Bootstrap at 100%
- [ ] SocksPort 9050 working
- [ ] ControlPort 9051 working with cookie auth
- [ ] DNSPort 5353 configured
- [ ] NEWNYM accepted
- [ ] proxychains working with proxy_dns
- [ ] No DNS leak detected with tcpdump
- [ ] Firefox tor-proxy profile created and configured
- [ ] check.torproject.org confirms browsing via Tor

---

## See also

- [Installation and Verification](../02-installazione-e-configurazione/installazione-e-verifica.md) - Complete installation guide
- [torrc - Complete Guide](../02-installazione-e-configurazione/torrc-guida-completa.md) - All directives
- [IP, DNS, and Leak Verification](../04-strumenti-operativi/verifica-ip-dns-e-leak.md) - In-depth tests
