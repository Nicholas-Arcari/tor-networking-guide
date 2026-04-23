> **Lingua / Language**: [Italiano](../../10-laboratorio-pratico/lab-03-dns-leak-testing.md) | English

# Lab 03 - DNS Leak Detection and Prevention

A hands-on exercise to understand, detect, and prevent DNS leaks when using
Tor. Includes capture with tcpdump, automated tests, and hardening with iptables.

**Estimated time**: 25-35 minutes
**Prerequisites**: Lab 01 completed, root access for tcpdump and iptables
**Difficulty**: Intermediate

---

## Table of Contents

- [Objectives](#objectives)
- [Phase 1: Understanding DNS leaks](#phase-1-understanding-dns-leaks)
- [Phase 2: Triggering a DNS leak](#phase-2-triggering-a-dns-leak)
- [Phase 3: Verifying protection](#phase-3-verifying-protection)
- [Phase 4: Hardening with iptables](#phase-4-hardening-with-iptables)
- [Phase 5: Automated test script](#phase-5-automated-test-script)
- [Final checklist](#final-checklist)

---

## Objectives

By the end of this lab, you will know how to:
1. Capture DNS leaks with tcpdump
2. Distinguish between `--socks5` (leak) and `--socks5-hostname` (safe)
3. Verify that `proxy_dns` in proxychains works
4. Implement iptables anti-DNS-leak rules
5. Create an automated test script

---

## Phase 1: Understanding DNS leaks

```bash
# First, let's see what our current DNS resolver is
cat /etc/resolv.conf
# Output: nameserver 192.168.1.1 (or similar - your router/ISP)

# This resolver is the one that receives queries when we are NOT using Tor
# If a DNS query goes out without passing through Tor, it goes to this resolver
# → The ISP sees which domain you are trying to reach
```

---

## Phase 2: Triggering a DNS leak

```bash
# Open TWO terminals

# TERMINAL 1: capture DNS
sudo tcpdump -i eth0 port 53 -n -l

# TERMINAL 2: trigger a leak
# Use --socks5 (WITHOUT hostname) → resolves DNS locally → LEAK!
curl --socks5 127.0.0.1:9050 -s --max-time 15 https://example.com > /dev/null

# TERMINAL 1: you should see something like:
# 14:23:45.123 IP 192.168.1.100.43521 > 192.168.1.1.53: A? example.com
# → This is the cleartext DNS query that reveals "example.com" to your ISP

# Now try the CORRECT method:
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 15 https://example.com > /dev/null

# TERMINAL 1: no DNS query visible → no leak!
```

**Exercise**: note the difference between `--socks5` and `--socks5-hostname`.
With `--socks5`, how many DNS queries do you see? Which IP do they go to?

---

## Phase 3: Verifying protection

```bash
# Test 1: proxychains with proxy_dns (must be active)
grep "proxy_dns" /etc/proxychains4.conf
# Should show: proxy_dns (not commented out)

# TERMINAL 1: tcpdump active
sudo tcpdump -i eth0 port 53 -n -l

# TERMINAL 2: test with proxychains
proxychains curl -s --max-time 15 https://check.torproject.org > /dev/null

# TERMINAL 1: no DNS query should appear

# Test 2: what happens WITHOUT proxy_dns?
# (DO NOT do this on a production system - lab only)
# Temporarily comment out proxy_dns in /etc/proxychains4.conf
# Repeat the test → you should see cleartext DNS queries
# REMEMBER to re-enable proxy_dns after the test!
```

---

## Phase 4: Hardening with iptables

```bash
# Implement anti-DNS-leak rules

# 1. Allow DNS only from the Tor process
sudo iptables -A OUTPUT -p udp --dport 53 -m owner --uid-owner debian-tor -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -m owner --uid-owner debian-tor -j ACCEPT

# 2. Allow DNS to the local DNSPort
sudo iptables -A OUTPUT -p udp -d 127.0.0.1 --dport 5353 -j ACCEPT

# 3. Block all remaining DNS
sudo iptables -A OUTPUT -p udp --dport 53 -j LOG --log-prefix "DNS_LEAK: "
sudo iptables -A OUTPUT -p udp --dport 53 -j DROP
sudo iptables -A OUTPUT -p tcp --dport 53 -j DROP

# Verify the rules
sudo iptables -L OUTPUT -n -v | grep -E "53|DNS"

# Test: try direct DNS (should fail)
dig example.com @8.8.8.8
# → Timeout (blocked by the rules)

# Test: Tor still works
proxychains curl -s https://api.ipify.org
# → Shows Tor IP (works because Tor resolves internally)

# To remove the rules (end of lab):
sudo iptables -F OUTPUT
```

---

## Phase 5: Automated test script

Create the file `test-dns-leak.sh`:

```bash
#!/bin/bash
# test-dns-leak.sh - Automated DNS leak test

IFACE="${1:-eth0}"
PASS=0
FAIL=0

echo "=== DNS Leak Test ==="
echo "Interface: $IFACE"
echo ""

run_test() {
    local desc="$1"
    local cmd="$2"
    local expect_leak="$3"

    echo -n "Test: $desc ... "

    # Capture DNS in the background
    PCAP="/tmp/dns-test-$$.pcap"
    sudo tcpdump -i "$IFACE" port 53 -w "$PCAP" -c 10 &>/dev/null &
    PID=$!
    sleep 1

    # Execute the command
    eval "$cmd" > /dev/null 2>&1
    sleep 2

    # Stop capture
    sudo kill $PID 2>/dev/null; wait $PID 2>/dev/null
    QUERIES=$(sudo tcpdump -r "$PCAP" -n 2>/dev/null | grep -c "A?")
    rm -f "$PCAP"

    if [ "$expect_leak" = "leak" ] && [ "$QUERIES" -gt 0 ]; then
        echo "LEAK detected ($QUERIES queries) - expected"
        PASS=$((PASS+1))
    elif [ "$expect_leak" = "noleak" ] && [ "$QUERIES" -eq 0 ]; then
        echo "No leak - OK"
        PASS=$((PASS+1))
    else
        echo "UNEXPECTED RESULT ($QUERIES queries)"
        FAIL=$((FAIL+1))
    fi
}

run_test "curl --socks5 (expected: leak)" \
    "curl --socks5 127.0.0.1:9050 -s --max-time 10 https://example.com" "leak"

run_test "curl --socks5-hostname (expected: no leak)" \
    "curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 https://example.com" "noleak"

run_test "proxychains curl (expected: no leak)" \
    "proxychains curl -s --max-time 10 https://example.com" "noleak"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
```

```bash
chmod +x test-dns-leak.sh
sudo ./test-dns-leak.sh eth0
```

---

## Troubleshooting

### tcpdump captures nothing (0 packets)

```bash
# Verify the correct interface
ip route get 8.8.8.8 | grep -oP 'dev \K\S+'
# If it is not "eth0", pass the correct interface:
sudo tcpdump -i <correct_interface> port 53 -n -l

# On VMs/containers the interface may be "ens33", "wlan0", etc.
```

### tcpdump shows DNS queries even with --socks5-hostname

```bash
# Possible causes:
# 1. systemd-resolved intercepts queries before Tor
systemctl status systemd-resolved
# If active, it may resolve from cache. For the test:
sudo systemd-resolve --flush-caches

# 2. The browser (not curl) does DNS prefetch in the background
# → Disable network.dns.disablePrefetch in about:config

# 3. IPv6 DNS leak - the system uses IPv6 DNS not covered by the rules
# → Add ip6tables rules or disable IPv6:
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
```

### iptables rules also block legitimate traffic

```bash
# If you lose connectivity after applying the anti-DNS-leak rules:
# You probably also blocked DNS for Tor itself

# Verify current rules
sudo iptables -L OUTPUT -n -v --line-numbers

# Remove all OUTPUT rules (quick restore)
sudo iptables -F OUTPUT

# Make sure the ACCEPT rule for debian-tor is BEFORE the DROP rule
# Rule ordering is critical in iptables
```

---

## Final checklist

- [ ] DNS leak triggered and captured with tcpdump
- [ ] Difference between --socks5 vs --socks5-hostname understood
- [ ] proxy_dns verified in proxychains
- [ ] iptables anti-DNS-leak rules implemented and tested
- [ ] Automated test script working

---

## See also

- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Complete DNS leak analysis
- [Tor and DNS - Resolution](../04-strumenti-operativi/tor-e-dns-risoluzione.md) - DNSPort and configuration
- [System Hardening](../05-sicurezza-operativa/hardening-sistema.md) - Permanent firewall rules
