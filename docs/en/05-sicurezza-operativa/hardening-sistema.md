> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/hardening-sistema.md) | English

# System Hardening for Tor Usage

This document covers system-level hardening measures to maximize security
when using Tor. It includes kernel configuration, firewall, AppArmor profiles,
services to disable, and OS-level leak prevention.

> **See also**: [DNS Leak](./dns-leak.md) for DNS prevention,
> [Isolation and Compartmentalization](./isolamento-e-compartimentazione.md) for VM/containers,
> [OPSEC and Common Mistakes](./opsec-e-errori-comuni.md) for operational errors,
> [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) for iptables.

---

## Table of Contents

- [Threat model overview](#threat-model-overview)
- [Kernel hardening - sysctl](#kernel-hardening--sysctl)
- [Firewall - nftables/iptables](#firewall--nftablesiptables)
- [Disable IPv6](#disable-ipv6)
- [AppArmor for Tor](#apparmor-for-tor)
**Deep dives** (dedicated files):
- [Advanced Hardening](hardening-avanzato.md) - Services, network, filesystem, logging, Firefox, checklist

---

## Threat model overview

System hardening protects against:

| Threat | Without hardening | With hardening |
|--------|------------------|---------------|
| DNS leak via UDP | Possible | Blocked (iptables) |
| IPv6 leak | Possible | Blocked (sysctl + iptables) |
| Services communicating in cleartext | Active by default | Disabled |
| Kernel info leak | Exposed | Reduced (sysctl) |
| Traffic correlation via timing | Possible | Reduced (disable NTP leak) |
| Crash dump with sensitive data | Active | Disabled |
| Temporary files on disk | Persistent | tmpfs / shred |

---

## Kernel hardening - sysctl

### Network parameters

```bash
# /etc/sysctl.d/99-tor-hardening.conf

# --- IPv6: disable completely ---
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# --- Prevent network information leaks ---
# Disable ICMP redirect (could bypass Tor routing)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Disable source routing (attack to bypass routing)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Enable reverse path filtering (anti-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore broadcast ICMP (smurf attack prevention)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore ICMP bogus error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable IP forwarding (unless acting as Tor gateway)
net.ipv4.ip_forward = 0

# Log martian packets (impossible packets)
net.ipv4.conf.all.log_martians = 1
```

### Generic kernel parameters

```bash
# --- Kernel protection ---
# Hide kernel pointers in logs
kernel.kptr_restrict = 2

# Restrict access to dmesg
kernel.dmesg_restrict = 1

# Disable SysRq (prevent dump)
kernel.sysrq = 0

# Restrict ptrace (prevent process attachment)
kernel.yama.ptrace_scope = 2

# Maximum ASLR
kernel.randomize_va_space = 2

# Disable core dump (could contain sensitive data)
fs.suid_dumpable = 0
```

### Apply

```bash
# Apply immediately
sudo sysctl --system

# Verify
sysctl net.ipv6.conf.all.disable_ipv6
# net.ipv6.conf.all.disable_ipv6 = 1
```

---

## Firewall - nftables/iptables

### Strategy: deny-all, allow-Tor

The goal is to block ALL traffic that does not go through Tor:

```bash
#!/bin/bash
# tor-firewall.sh - Restrictive firewall for Tor usage

TOR_UID=$(id -u debian-tor)

# === OUTPUT: what can go out ===

# Flush
iptables -F OUTPUT

# Allow Tor traffic (the daemon itself)
iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT

# Allow localhost (ControlPort, SocksPort, DNSPort)
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT

# Allow LAN (optional, for DHCP, printers, NAS)
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# Block EVERYTHING else
iptables -A OUTPUT -j LOG --log-prefix "[TOR-FW-DROP] " --log-level 4
iptables -A OUTPUT -j DROP

# === IPv6: block everything ===
ip6tables -F OUTPUT
ip6tables -A OUTPUT -j DROP

echo "Tor firewall active. Only traffic via Tor allowed."
```

### Difference from transparent proxy

```
Transparent proxy:
  → All TCP traffic is REDIRECTED to Tor (TransPort)
  → Apps are unaware they are using Tor
  → UDP blocked

Restrictive firewall:
  → Direct traffic is BLOCKED
  → Apps must be configured to use SocksPort
  → If an app does not use the proxy → connection blocked → NO leak
  → More conservative approach
```

The restrictive firewall is a **complement** to proxychains/torsocks, not a
substitute. It catches everything that escapes the LD_PRELOAD wrapper.

### Rules for specific scenarios

```bash
# Allow NTP (accept timing leak to have correct clock)
iptables -I OUTPUT -p udp --dport 123 -j ACCEPT

# Allow apt update without Tor (much faster)
APT_UID=$(id -u _apt)
iptables -I OUTPUT -m owner --uid-owner $APT_UID -j ACCEPT

# Allow a specific user to bypass the firewall
iptables -I OUTPUT -m owner --uid-owner 1001 -j ACCEPT
```

---

## Disable IPv6

IPv6 is a critical leak vector because:
- Tor has limited IPv6 support (client-side)
- iptables does not cover IPv6 (separate ip6tables needed)
- Many applications prefer IPv6 when available

### Complete method

```bash
# 1. sysctl (already covered above)
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1

# 2. ip6tables (firewall-level block)
sudo ip6tables -P INPUT DROP
sudo ip6tables -P OUTPUT DROP
sudo ip6tables -P FORWARD DROP

# 3. GRUB (disable at kernel boot level)
# /etc/default/grub:
# GRUB_CMDLINE_LINUX="ipv6.disable=1"
# sudo update-grub

# 4. Verify
ip -6 addr show
# No output = IPv6 disabled

cat /proc/sys/net/ipv6/conf/all/disable_ipv6
# 1
```

---

## AppArmor for Tor

### AppArmor profile for Tor daemon

Kali/Debian includes an AppArmor profile for Tor. Verify:

```bash
# AppArmor status
sudo aa-status | grep tor
# /usr/bin/tor (enforce)

# If not active:
sudo aa-enforce /etc/apparmor.d/system_tor
```

### What the profile limits

The AppArmor profile for Tor:
- Limits filesystem access: only `/var/lib/tor/`, `/var/log/tor/`, config
- Prevents access to home directories, `/tmp`, and other paths
- Limits network capabilities
- Prevents access to other processes

### More restrictive custom profile

```
# /etc/apparmor.d/local/system_tor
# Local override for additional restrictions

# Deny access to devices
deny /dev/** rw,

# Deny access to proc (except necessary)
deny /proc/*/maps r,
deny /proc/*/status r,

# Allow only necessary ports
network tcp,
# Implicitly denies raw sockets, UDP (except internal DNS)
```


---

> **Continues in**: [Advanced Hardening](hardening-avanzato.md) for services to
> disable, MAC/hostname randomization, filesystem, logging and Firefox hardening.

---

## See also

- [Advanced Hardening](hardening-avanzato.md) - Services, network, filesystem, Firefox, checklist
- [DNS Leak](dns-leak.md) - DNS leak prevention with firewall
- [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) - Whonix, Tails, network namespaces
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - iptables/nftables for system-wide Tor
- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Hardening as part of OPSEC
- [Forensic Analysis and Artifacts](analisi-forense-e-artefatti.md) - Reducing artifacts with hardening
- [Real-World Scenarios](scenari-reali.md) - Operational cases from a pentester
