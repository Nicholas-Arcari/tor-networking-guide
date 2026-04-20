> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/torsocks-avanzato.md) | English

# torsocks Advanced - Variables, Edge Cases, Debugging and Comparison

Environment variables, edge cases and known issues, advanced debugging,
critical security analysis, and detailed comparison with proxychains.

Extracted from [torsocks](torsocks.md).

---

## Table of Contents

- [Environment variables](#environment-variables)
- [Edge cases and known issues](#edge-cases-and-known-issues)
- [Advanced debugging](#advanced-debugging)
- [torsocks security - critical analysis](#torsocks-security---critical-analysis)
- [torsocks vs proxychains - detailed comparison](#torsocks-vs-proxychains---detailed-comparison)

---

## Environment variables

```bash
# Custom configuration file
TORSOCKS_CONF_FILE=/path/to/custom.conf torsocks curl example.com

# Log level (1=error, 2=warn, 3=notice, 4=info, 5=debug)
TORSOCKS_LOG_LEVEL=5 torsocks curl example.com

# Log file (instead of stderr)
TORSOCKS_LOG_FILE_PATH=/tmp/torsocks.log torsocks curl example.com

# Allow inbound connections
TORSOCKS_ALLOW_INBOUND=1 torsocks ./myserver

# Override Tor address
TORSOCKS_TOR_ADDRESS=127.0.0.1 torsocks curl example.com

# Override Tor port
TORSOCKS_TOR_PORT=9060 torsocks curl example.com

# PID isolation
TORSOCKS_ISOLATE_PID=1 torsocks curl example.com

# SOCKS5 username for manual isolation
TORSOCKS_USERNAME="my-session-1" torsocks curl example.com
TORSOCKS_PASSWORD="random123" torsocks curl example.com
```

---

## Edge cases and known issues

### Statically linked Go binaries

Go compiles static binaries by default. They do not use the dynamic libc - LD_PRELOAD
does not work:

```bash
torsocks ./my-go-program
# The program connects DIRECTLY, bypassing torsocks!
# NO warning is shown - silently insecure

# Check if a binary is static:
file ./my-go-program
# my-go-program: ELF 64-bit, statically linked
# ↑ "statically linked" = torsocks does NOT work

ldd ./my-go-program
# not a dynamic executable
# ↑ Confirms: no dynamic library, torsocks is useless
```

**Workaround**: use transparent proxy (iptables) or configure the Go program
to use SOCKS5 natively (most Go HTTP clients support proxy).

### Java with JNI

Some Java applications use JNI for native networking. In these cases,
calls can bypass libc:

```bash
torsocks java -jar myapp.jar
# Might work for standard HTTP (via java.net)
# But custom JNI networking bypasses torsocks
```

### Node.js

Node.js uses libuv for I/O, which generally uses libc syscalls. It works
in most cases:

```bash
torsocks node myapp.js
# Generally works for HTTP/HTTPS
# BUT: DNS resolution in Node.js can use c-ares (not libc)
#     c-ares might not be intercepted
```

### Multi-process applications (fork)

When a process calls `fork()`:
- The child inherits `LD_PRELOAD` - torsocks works
- BUT: if the child calls `exec()` with a setuid binary - LD_PRELOAD is ignored for security

```bash
# Example: sudo inside torsocks
torsocks bash
$ sudo apt update    # sudo is setuid → LD_PRELOAD ignored → LEAK!
```

---

## Advanced debugging

### Verbose logging

```bash
# Level 5 (debug): shows every intercepted syscall
TORSOCKS_LOG_LEVEL=5 torsocks curl https://api.ipify.org

# Example output:
# [debug] torsocks[23456]: connect: Connection to 127.0.0.1:9050
# [debug] torsocks[23456]: SOCKS5 sending method for auth
# [debug] torsocks[23456]: SOCKS5 received method for auth: 00
# [debug] torsocks[23456]: SOCKS5 sending connect request to: api.ipify.org:443
# [debug] torsocks[23456]: SOCKS5 received connect reply success
# [debug] torsocks[23456]: connect: Connection to api.ipify.org:443 was successful
```

### Verify that libtorsocks is loaded

```bash
# Method 1: check /proc/PID/maps
torsocks bash -c 'cat /proc/self/maps | grep torsocks'
# 7f8a1234000-7f8a1238000 r-xp ... /usr/lib/.../libtorsocks.so

# Method 2: ldd (for dynamic binaries)
ldd $(which curl) | grep torsocks
# Will not show torsocks (LD_PRELOAD is not in ldd)
# But confirms that curl is dynamic (can be hooked)

# Method 3: strace to see the hooking
strace -e trace=connect torsocks curl https://api.ipify.org 2>&1 | head -20
# connect(3, {sa_family=AF_INET, sin_port=htons(9050), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
# ↑ The connection goes to 127.0.0.1:9050 (Tor), not the destination IP
```

### Verify there are no leaks

```bash
# In one terminal: tcpdump to capture non-Tor traffic
sudo tcpdump -i eth0 -n 'not port 9050 and not port 9001 and not port 443' &

# In another terminal: use torsocks
torsocks curl https://api.ipify.org

# If tcpdump shows packets → there is a leak
# If tcpdump is silent → torsocks is working correctly
```

---

## torsocks security - critical analysis

### What it protects

| Vector | Protected? | How |
|--------|-----------|------|
| TCP connections | Yes | Redirect via SOCKS5 |
| DNS via getaddrinfo | Yes | Intercepts and resolves via Tor |
| UDP | Yes (blocks) | Intercepts sendto/sendmsg, DROP |
| Direct UDP DNS | Yes (blocks) | Blocked with warning |

### What it does NOT protect

| Vector | Protected? | Why |
|--------|-----------|-----|
| Direct syscalls | **No** | LD_PRELOAD operates at libc level, not kernel |
| Static binaries | **No** | They do not use dynamic libc |
| setuid binaries | **No** | LD_PRELOAD ignored for security |
| io_uring | **No** | Kernel-level async I/O, bypasses libc |
| Raw socket | **No** | Requires root, does not go through connect() |
| ICMP | **No** | Does not use connect(), uses raw socket |
| Fork + exec setuid | **No** | Child loses LD_PRELOAD |

### Possible leak scenarios

1. **DNS before hooking**: if an application resolves DNS before torsocks
   can intercept (e.g. custom DNS library loaded before libtorsocks)

2. **Subprocess without LD_PRELOAD**: if a process spawns a child that resets
   the environment (rare, but possible with `env -i`)

3. **IPv6 not blocked**: torsocks blocks IPv4 UDP but might not intercept
   all IPv6 variants in some versions

### Mitigation: combine with iptables

For maximum security, torsocks should be combined with iptables rules
that block all non-Tor traffic:

```bash
# Block direct traffic (backup in case torsocks fails)
iptables -A OUTPUT -m owner --uid-owner $(id -u) -p tcp --dport 9050 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner $(id -u) -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner $(id -u) -j DROP
```

---

## torsocks vs proxychains - detailed comparison

| Criterion | torsocks | proxychains |
|-----------|----------|-------------|
| **UDP blocking** | Yes (active) | No (ignores) |
| **DNS handling** | Intercepts getaddrinfo | Dummy IP + mapping |
| **Proxy chaining** | No (Tor only) | Yes (multiple proxies) |
| **Output verbosity** | Minimal (warnings only) | Very verbose |
| **Stream isolation** | Automatic IsolatePID | Manual (SOCKS auth) |
| **App compatibility** | Same (both LD_PRELOAD) | Same |
| **Static binaries** | Does not work | Does not work |
| **Configuration** | Simple (Tor only) | More flexible |
| **SOCKS4 proxy** | No | Yes |
| **HTTP proxy** | No | Yes |
| **Maintenance** | Active (Tor Project) | Active (community) |
| **Installation** | apt install torsocks | apt install proxychains4 |
| **Shell mode** | `source torsocks on` | No equivalent |
| **DNS security** | Superior | Good with proxy_dns |
| **Debug** | TORSOCKS_LOG_LEVEL | PROXYCHAINS_DEBUG |

### When to use which

| Scenario | Choice | Rationale |
|----------|--------|-----------|
| Firefox browsing | proxychains | More tested, useful output |
| Automated scripts | torsocks | Less noise, UDP blocking |
| SSH via Tor | torsocks | IsolatePID, less overhead |
| Proxy chain (Tor - VPN - proxy) | proxychains | Supports chaining |
| Maximum security | torsocks + iptables | UDP blocking + fallback |
| Connection debugging | proxychains | Very detailed output |
| Full shell via Tor | torsocks | `source torsocks on` |
| .onion access | torsocks | Native OnionAddrRange |

---

## Automation with torsocks

### Wrapper script for periodic IP verification

```bash
#!/bin/bash
# check-tor-ip.sh - Periodic IP verification via torsocks

while true; do
    IP=$(torsocks curl -s --max-time 15 https://api.ipify.org 2>/dev/null)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ -n "$IP" ]; then
        echo "$TIMESTAMP | Tor IP: $IP"
    else
        echo "$TIMESTAMP | ERROR: unable to get IP via Tor"
    fi
    
    sleep 300  # every 5 minutes
done
```

### Anonymized cron job

```bash
# crontab -e
# Download report every day at 03:00 via Tor
0 3 * * * /usr/bin/torsocks /usr/bin/wget -q -O /tmp/report.html https://example.com/report 2>/dev/null
```

### systemd service with torsocks

```ini
# /etc/systemd/system/my-tor-service.service
[Unit]
Description=Service via Tor
After=tor@default.service
Requires=tor@default.service

[Service]
Type=simple
Environment=LD_PRELOAD=/usr/lib/x86_64-linux-gnu/torsocks/libtorsocks.so
ExecStart=/usr/bin/my-service
User=myuser
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

---

## Fundamental limitations

| Limitation | Description | Workaround |
|-----------|-------------|------------|
| LD_PRELOAD | Does not work with static or setuid binaries | Transparent proxy (iptables) |
| No direct syscalls | Programs that bypass libc are not covered | Network namespace |
| No UDP | UDP is blocked, not proxied | None (Tor does not support UDP) |
| No ICMP | ping and traceroute impossible | None |
| Multi-thread | Rare race conditions possible | IsolatePID mitigates |
| Setuid drop | sudo/su resets LD_PRELOAD | Use torsocks inside sudo |
| Performance | LD_PRELOAD overhead negligible, Tor latency significant | None |

---

## In my experience

I mainly use proxychains for my daily workflow on Kali because:
- I set it up first and am used to it
- The verbose output helps me with debugging during study
- I use it with Firefox through the `tor-proxy` profile

However, I recognize that torsocks is the better choice from a security
standpoint for one fundamental reason: **it actively blocks UDP**. With proxychains,
a DNS leak via UDP would go unnoticed. With torsocks, it is intercepted and
blocked with an explicit warning in the log.

For automated scripts and SSH, torsocks is superior:
- `torsocks ssh user@server.com` is cleaner than `proxychains ssh user@server.com`
  (less output noise, automatic IsolatePID)
- For cron jobs and automation, the minimal logging of torsocks is preferable

I tested both with static Go applications and neither works -
the binary connects directly, bypassing the wrapper. For those cases, the only
solution is the transparent proxy with iptables or a dedicated network namespace.

My advice: use proxychains for daily interactive work (browser, manual
curl, debugging), and torsocks for automation and scripts where UDP
security is a priority.

---

## See also

- [ProxyChains - Complete Guide](proxychains-guida-completa.md) - Detailed comparison with torsocks
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - torsocks and DNS leak prevention
- [IP, DNS and Leak Verification](verifica-ip-dns-e-leak.md) - Tests with torsocks
- [Circuit Control and NEWNYM](controllo-circuiti-e-newnym.md) - IsolatePID and circuits
- [Application Limitations](../07-limitazioni-e-attacchi/limitazioni-applicazioni.md) - Which apps work with torsocks
