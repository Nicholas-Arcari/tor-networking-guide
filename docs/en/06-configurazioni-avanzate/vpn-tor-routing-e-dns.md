> **Lingua / Language**: [Italiano](../../06-configurazioni-avanzate/vpn-tor-routing-e-dns.md) | English

# VPN and Tor - Selective Routing, DNS and Kill Switch

Selective per-application routing, DNS management in hybrid configurations,
VPN and Tor kill switches, WireGuard vs OpenVPN comparison, ExitNodes and
forced geolocation, comparison table.

> **Extracted from**: [VPN and Tor - Hybrid Configurations](vpn-e-tor-ibrido.md)
> for architectural differences and VPN->Tor and Tor->VPN configurations.

---

## Selective per-application routing

### My approach

```
Browser (anonymous browsing)  -> proxychains -> Tor -> Internet
Terminal (tests, curl)        -> proxychains -> Tor -> Internet
System updates                -> normal network        -> Internet
Streaming/video               -> VPN (optional)        -> Internet
Sensitive apps                -> normal network         -> Internet
Banking                       -> normal network (NEVER Tor) -> Internet
Gaming                        -> normal network         -> Internet
```

### Practical implementation

```bash
# ~/.zshrc or ~/.bashrc

# Tor aliases
alias curltor='curl --socks5-hostname 127.0.0.1:9050'
alias pcurl='proxychains curl -s'
alias pfirefox='proxychains firefox -no-remote -P tor-proxy &>/dev/null & disown'

# Status check function
torcheck() {
    echo -n "Tor IP: "
    curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 https://api.ipify.org
    echo ""
    echo -n "IsTor: "
    curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 \
        https://check.torproject.org/api/ip | grep -o '"IsTor":[a-z]*'
}

# Git via Tor (only for specific repositories)
alias gittor='git -c http.proxy=socks5h://127.0.0.1:9050 -c https.proxy=socks5h://127.0.0.1:9050'
```

### Advantages

- Maximum flexibility: each app uses the best channel
- Does not overload Tor with unnecessary traffic
- Does not break applications that require UDP
- Optimal performance for each type of traffic
- Granular control over what is anonymous and what is not

### Disadvantages

- Requires discipline (remembering to use proxychains)
- Possible leaks if you forget to proxy an application
- Not automatic: human error is the main risk
- Not suitable for high-risk scenarios (use Whonix/Tails instead)

---

## DNS management in hybrid configurations

### DNS in VPN -> Tor

```
Problem:
  The VPN configures its own DNS (e.g., via DHCP push)
  Tor uses its own DNSPort to resolve
  Who resolves first?

Correct flow:
  App -> proxychains -> SOCKS5 hostname -> Tor -> Exit (resolves DNS)
  The VPN and its DNS are not involved for Tor traffic

Problematic flow:
  App -> VPN DNS -> cleartext response to the VPN
  -> then -> connection via Tor
  The VPN saw the domain! Privacy partially compromised

Solution:
  1. Always use --socks5-hostname (not --socks5)
  2. Enable proxy_dns in proxychains
  3. In Firefox: network.proxy.socks_remote_dns = true
  4. Do not use the VPN's DNS push for Tor traffic
```

### DNS in TransPort

```
Flow:
  App -> local DNS query -> iptables REDIRECT -> Tor DNSPort
  -> Tor resolves via circuit -> response to app
  -> App connects -> iptables REDIRECT -> Tor TransPort
  -> Connection via Tor

All DNS is forced via Tor. No leak possible
(unless there are bugs in the iptables rules).
```

### DNS in selective routing

```
My setup:
  With proxychains: DNS resolved via Tor (proxy_dns)
  Without proxychains: DNS resolved by ISP router (192.168.1.1)

Risk: if I forget proxychains, DNS goes out in cleartext
Mitigation: iptables blocking direct DNS (port 53) for my user
```

---

## Kill switch and leak protection

### Kill switch for VPN -> Tor

If the VPN disconnects, Tor would connect directly -> the ISP sees Tor.

```bash
#!/bin/bash
# vpn-killswitch.sh - Block traffic if VPN drops

VPN_IFACE="wg0"  # or tun0 for OpenVPN
VPN_SERVER="85.x.x.x"  # VPN server IP

# Allow only traffic to the VPN server (to maintain the connection)
sudo iptables -A OUTPUT -d $VPN_SERVER -j ACCEPT

# Allow traffic on the VPN
sudo iptables -A OUTPUT -o $VPN_IFACE -j ACCEPT

# Allow localhost
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Allow local traffic
sudo iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# Block EVERYTHING else (kill switch)
sudo iptables -A OUTPUT -j DROP

# If the VPN drops -> tun0/wg0 disappears -> traffic dropped -> no leak
```

### Kill switch for Tor alone

```bash
#!/bin/bash
# tor-killswitch.sh - Block non-Tor traffic

TOR_USER="debian-tor"

# Allow traffic from the Tor process
sudo iptables -A OUTPUT -m owner --uid-owner $TOR_USER -j ACCEPT

# Allow localhost
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Allow LAN
sudo iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# Block everything else
sudo iptables -A OUTPUT -j REJECT --reject-with icmp-port-unreachable

# If Tor stalls -> applications cannot reach the outside -> no leak
# But also: no updates, NTP, etc.
```

---

## WireGuard vs OpenVPN with Tor

### WireGuard

```
Advantages with Tor:
  + Fast connection (handshake in 1 RTT)
  + Low overhead (less latency added to Tor)
  + Simple configuration
  + Stays connected even after sleep/resume

Disadvantages:
  - UDP-only (can be blocked by firewalls)
  - Assigns fixed IP to peer (fingerprint if provider logs)
  - Less obfuscation (WireGuard is easily identifiable by DPI)
```

### OpenVPN

```
Advantages with Tor:
  + TCP mode available (bypasses firewalls that block UDP)
  + Supports obfuscation (obfsproxy, stunnel)
  + More flexible configuration

Disadvantages:
  - Slower handshake (multi-RTT)
  - Higher overhead
  - Slower reconnection after disconnection
```

### Recommendation

```
For general use (VPN -> Tor): WireGuard (faster, less overhead)
For restrictive networks: OpenVPN TCP (bypasses firewalls)
For maximum obfuscation: OpenVPN + obfsproxy (looks like HTTPS)
```

---

## ExitNodes and forced geolocation

### The problem

I tried to force exit through a specific country:
```ini
ExitNodes {it}
StrictNodes 1
```

Results:
- Very few Italian exits available (~10-20 out of ~2000 total)
- Saturated and slow circuits (all users with {it} share few exits)
- IP still changed with every circuit renewal
- Easy fingerprinting ("this user ALWAYS exits from Italy")

### Why it does not work

Tor is designed for **randomization**. Forcing a country:
- Reduces the exit pool (less privacy, less bandwidth)
- Makes traffic more recognizable
- Does not guarantee the same IP over time (circuits are renewed)
- Creates a reduced anonymity set (only users with ExitNodes {it})

### Alternatives

```
For geolocation:
  -> VPN with a server in the desired country (fixed IP, fast)

For anonymity + specific country (rare):
  -> Tor -> VPN in the desired country (but see problems above)

For testing from specific countries:
  -> ExitNodes {cc} temporarily, then remove
  -> Do not use for daily browsing
```

---

## Comparison table

| Configuration | Privacy | Anonymity | Speed | Reliability | Complexity | Secure DNS |
|--------------|---------|-----------|-------|-------------|------------|-----------|
| Tor only | High | Very high | Low | Medium | Low | With config |
| VPN only | Medium | Low | High | High | Low | Depends |
| VPN -> Tor | High | High | Very low | Medium | Medium | With config |
| Tor -> VPN | Low | Low | Low | Low | High | Problematic |
| TransPort+iptables | High | High | Low | Low | High | Forced |
| Selective routing | High | High (for proxied apps) | Variable | High | Medium | With config |

---

## In my experience

**My choice**: selective routing. It is the best compromise between security,
usability, and daily practicality.

```
My workflow:
1. Tor daemon always running (systemd)
2. obfs4 bridge configured (hides Tor from ISP Comeser)
3. proxychains for browsing and testing
4. Normal network for everything else
5. No VPN (I do not need one for my threat model)
```

If I had to add a VPN, I would use it for:
- Geolocated streaming (Netflix, etc.)
- Public WiFi (general protection, not anonymity)
- Fallback if Tor is too slow for a specific operation

I would NOT use it for:
- Adding "security" to Tor (it adds nothing significant)
- Replacing obfs4 bridges (bridges are better for hiding Tor)

---

## See also

- [Transparent Proxy](transparent-proxy.md) - Complete iptables/nftables TransPort setup
- [Multi-Instance and Stream Isolation](multi-istanza-e-stream-isolation.md) - Per-app circuit isolation
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - DNS leak prevention in every configuration
- [Bridges and Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Alternative to VPN for hiding Tor
- [Isolation and Compartmentalization](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Whonix, Tails, Qubes
- [Protocol Limitations](../07-limitazioni-e-attacchi/limitazioni-protocollo.md) - Why Tor does not support UDP
