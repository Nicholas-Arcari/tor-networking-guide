> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/verifica-ip-dns-e-leak.md) | English

# IP, DNS and Leak Verification - Complete Security Tests for Tor

This document covers all methods for verifying that traffic is actually
passing through Tor, that there are no DNS leaks, and that your real identity
is not exposed. It includes manual, automated, and analysis tests for every
possible type of leak.

Based on my experience verifying exit IPs, comparing my real IP
(Parma, Italy) with the Tor IP, and diagnosing leak issues.

---
---

## Table of Contents

- [IP verification - Complete methods](#ip-verification---complete-methods)
- [DNS leak testing](#dns-leak-testing)
- [Listening port verification](#listening-port-verification)
- [Leak types and how to prevent them](#leak-types-and-how-to-prevent-them)
- [In my experience](#in-my-experience)


## IP verification - Complete methods

### 1. Real IP (without Tor)

```bash
> curl https://api.ipify.org
xxx.xxx.xxx.xxx    # my real IP (redacted - ISP Comeser, Parma)
```

### 2. IP via Tor (direct curl)

```bash
> curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
185.220.101.143    # IP of the Tor exit node
```

The `--socks5-hostname` flag is **essential**: it sends the hostname to the SOCKS5
proxy (Tor), which resolves it via the Tor network. Without `hostname`:

```bash
# WRONG - causes DNS leak
> curl --socks5 127.0.0.1:9050 https://api.ipify.org
# curl resolves "api.ipify.org" LOCALLY before sending to Tor → DNS leak
```

### 3. IP via Tor (proxychains)

```bash
> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
185.220.101.143
```

With `proxy_dns` enabled in proxychains.conf, DNS is resolved via Tor (no leak).

### 4. Detailed IP information

```bash
> proxychains curl -s https://ipinfo.io
{
  "ip": "185.220.101.143",
  "hostname": "tor-exit-relay.example.com",
  "city": "Amsterdam",
  "region": "North Holland",
  "country": "NL",
  "loc": "52.3676,4.9041",
  "org": "AS60729 Stichting Tor Exit",
  "timezone": "Europe/Amsterdam"
}
```

Useful information:
- `ip` - IP of the exit node (not mine)
- `org` - often contains "Tor Exit" in the name
- `country` - the exit node country (changes with each circuit/NEWNYM)

### 5. Confirm the IP is a Tor exit

```bash
> proxychains curl -s https://check.torproject.org/api/ip
{"IsTor":true,"IP":"185.220.101.143"}
```

`IsTor: true` - confirms that traffic exits from a known Tor exit node.

---

## DNS leak testing

### What is a DNS leak

A DNS leak occurs when DNS queries exit outside the Tor network, revealing
to your ISP which sites you are visiting, even if HTTP/HTTPS traffic passes through Tor.

```
Without DNS leak:
  You → Tor → Exit Node (resolves DNS) → Site

With DNS leak:
  You → ISP DNS (resolves the name in the clear!) → [then] → Tor → Exit Node → Site
  The ISP sees that you are looking up "example.com"
```

### How to test for DNS leaks

#### Test 1: dnsleaktest.com

```bash
> proxychains curl -s https://dnsleaktest.com/
# View the page to verify which DNS server is being used
```

#### Test 2: ipleak.net (JSON API)

```bash
> proxychains curl -s https://ipleak.net/json/
{
  "ip": "185.220.101.143",
  "country_code": "NL",
  ...
}
```

If the IP and country correspond to a Tor exit (not your ISP), there is no IP leak.
To specifically verify DNS, the site performs multiple DNS requests and shows
which resolver handles them.

#### Test 3: Manual test with dig

```bash
# DNS without Tor (shows your ISP resolver)
> dig +short whoami.akamai.net @ns1-1.akamaitech.net
xxx.xxx.xxx.xxx    # IP of your DNS resolver (your ISP)

# DNS via torsocks (should show the exit's resolver)
> torsocks dig +short whoami.akamai.net @ns1-1.akamaitech.net
# Note: dig uses UDP by default, torsocks blocks UDP
# Use: torsocks dig +tcp whoami.akamai.net @ns1-1.akamaitech.net
```

#### Test 4: Verification script

```bash
#!/bin/bash
echo "=== DNS Leak Test ==="

# IP without Tor
REAL_IP=$(curl -s https://api.ipify.org)
echo "Real IP: $REAL_IP"

# IP with Tor
TOR_IP=$(proxychains curl -s https://api.ipify.org 2>/dev/null)
echo "Tor IP: $TOR_IP"

# Comparison
if [ "$REAL_IP" != "$TOR_IP" ]; then
    echo "✓ Different IPs - Tor is working"
else
    echo "✗ WARNING - same IP! Tor might not be working"
fi

# Tor verification
IS_TOR=$(proxychains curl -s https://check.torproject.org/api/ip 2>/dev/null | grep -o '"IsTor":true')
if [ -n "$IS_TOR" ]; then
    echo "✓ Confirmed: traffic exits from Tor exit"
else
    echo "✗ WARNING - traffic is NOT exiting from Tor"
fi
```

---

## Listening port verification

To confirm that the Tor daemon is active and ports are configured:

```bash
> sudo ss -tlnp | grep -E "9050|9051"
LISTEN  0  4096  127.0.0.1:9050  0.0.0.0:*  users:(("tor",pid=1234,fd=6))
LISTEN  0  4096  127.0.0.1:9051  0.0.0.0:*  users:(("tor",pid=1234,fd=7))

> sudo ss -ulnp | grep 5353
UNCONN  0  0  127.0.0.1:5353  0.0.0.0:*  users:(("tor",pid=1234,fd=8))
```

Expected ports:
- `9050 TCP` - SocksPort (SOCKS5 proxy)
- `9051 TCP` - ControlPort
- `5353 UDP` - DNSPort

If a port is missing, verify the torrc and restart Tor.

---

## Leak types and how to prevent them

### 1. DNS Leak

**Cause**: the application resolves hostnames locally (via ISP DNS) before
sending them to the SOCKS proxy.

**Prevention**:
- `proxy_dns` in proxychains.conf
- `--socks5-hostname` with curl (not `--socks5`)
- `DNSPort 5353` in torrc + `AutomapHostsOnResolve 1`
- torsocks (intercepts DNS automatically)

### 2. IPv6 Leak

**Cause**: the system has IPv6 enabled and some connections exit via IPv6,
bypassing Tor (which operates on IPv4).

**Prevention**:
- `ClientUseIPv6 0` in torrc
- Disable IPv6 at the system level:
  ```bash
  sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
  ```

### 3. WebRTC Leak

**Cause**: WebRTC in the browser can reveal the local IP and the real public IP,
bypassing the proxy.

**Prevention**:
- In Firefox: `media.peerconnection.enabled = false` in `about:config`
- Tor Browser disables it by default
- With my `tor-proxy` Firefox profile: I must disable it manually

### 4. Non-proxy traffic

**Cause**: applications that do not respect the SOCKS proxy (e.g. NTP, system
updates, background services).

**Prevention**:
- Use proxychains/torsocks for each specific application
- For system-wide protection: transparent proxy with iptables (see advanced section)
- Use Whonix or Tails for total isolation

### 5. Leak via non-TCP protocols

**Cause**: Tor only supports TCP. UDP traffic (native DNS, QUIC, WebRTC, NTP, STUN)
does not pass through Tor.

**Prevention**:
- torsocks actively blocks UDP
- `DNSPort` in torrc redirects DNS
- Disable QUIC in the browser (`network.http.http3.enabled = false` in Firefox)

---

## In my experience

### Daily testing

My typical verification flow:

```bash
# 1. Verify Tor is active
systemctl is-active tor@default.service

# 2. Verify IP via Tor
proxychains curl -s https://api.ipify.org

# 3. Verify it is a Tor exit
proxychains curl -s https://check.torproject.org/api/ip

# 4. If I need to change IP
~/scripts/newnym
proxychains curl -s https://api.ipify.org    # verify it changed
```

### Typical results

```
Real IP: xxx.xxx.xxx.xxx (Parma, IT, Comeser S.r.l.)
Tor IP:  185.220.101.143 (Amsterdam, NL, Stichting Tor Exit)
IsTor:   true
```

The IP via Tor is always different from my real IP, in a different country, with a
different operator. This confirms that traffic correctly passes through
the Tor network.

---

## See also

- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - In-depth DNS leak analysis
- [ProxyChains - Complete Guide](proxychains-guida-completa.md) - proxy_dns configuration
- [Tor and DNS - Resolution](tor-e-dns-risoluzione.md) - DNSPort and resolution via Tor
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) - WebRTC leak and fingerprinting
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Leaks as OPSEC errors

---

## Cheat Sheet - Quick verification

| Test | Command |
|------|---------|
| IP via Tor | `curl --socks5-hostname 127.0.0.1:9050 -s https://api.ipify.org` |
| IsTor check | `curl --socks5-hostname 127.0.0.1:9050 -s https://check.torproject.org/api/ip` |
| DNS leak (tcpdump) | `sudo tcpdump -i eth0 port 53 -n` |
| IP with proxychains | `proxychains curl -s https://api.ipify.org` |
| WebRTC check | Visit `https://browserleaks.com/webrtc` via Tor |
| IPv6 check | `curl --socks5-hostname 127.0.0.1:9050 -s https://api6.ipify.org` (must fail) |
| Bootstrap | `sudo journalctl -u tor@default.service \| grep "Bootstrapped 100%"` |
| Tor ports | `ss -tlnp \| grep -E '905[01]\|5353'` |
| tor-resolve | `tor-resolve example.com` |
| DNS via Tor | `proxychains dig example.com` |
