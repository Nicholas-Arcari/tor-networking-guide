> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/gestione-del-servizio.md) | English

# Tor Service Management - systemd, Debugging, and Operations

This document covers the operational management of the Tor daemon on Debian/Kali systems:
systemd commands, reading logs, debugging problems, maintenance operations,
and procedures for handling anomalous situations.

Includes troubleshooting based on my real-world experience with bootstrap,
bridge, permission, and configuration issues.

---
---

## Table of Contents

- [systemd and Tor - How it works](#systemd-and-tor---how-it-works)
- [Logs and monitoring](#logs-and-monitoring)
- [Debugging common problems](#debugging-common-problems)
**Deep dives** (dedicated files):
- [Maintenance and Monitoring](manutenzione-e-monitoraggio.md) - Signals, health checks, procedures, post-install verification


## systemd and Tor - How it works

### The template unit

Tor on Debian uses a systemd **template** unit: `tor@.service`. This allows
multiple instances with different names:

```bash
# Default instance (the one we normally use)
tor@default.service

# Custom instances (if multiple Tor processes are needed)
tor@secondary.service
```

The `default` instance uses the standard torrc at `/etc/tor/torrc`. Custom instances
would look for `/etc/tor/instances/<name>/torrc`.

### systemd unit file

```bash
> systemctl cat tor@default.service
```

The unit specifies:
- `User=debian-tor` - the daemon runs as an unprivileged user
- `Type=notify` - systemd uses `sd_notify` to know when Tor is ready
- `ExecStart=/usr/bin/tor ...` - the startup command with parameters
- `ExecReload=/bin/kill -HUP $MAINPID` - reload sends SIGHUP

### Day-to-day operational commands

```bash
# === Status ===
sudo systemctl status tor@default.service
# Shows: active/inactive, PID, recent logs, uptime

# === Start/Stop/Restart ===
sudo systemctl start tor@default.service
sudo systemctl stop tor@default.service
sudo systemctl restart tor@default.service

# === Reload (re-reads torrc without restarting) ===
sudo systemctl reload tor@default.service
# Equivalent to: kill -HUP $(pidof tor)
# Tor re-reads the torrc but keeps existing circuits

# === Enable/Disable at boot ===
sudo systemctl enable tor@default.service    # starts at boot
sudo systemctl disable tor@default.service   # does not start at boot

# === Check if enabled ===
sudo systemctl is-enabled tor@default.service
```

### In my experience

I have not enabled Tor at boot (`enable`) because I do not always want Tor
to be active. I prefer to start it manually when I need it:

```bash
sudo systemctl start tor@default.service
# ... work with Tor ...
sudo systemctl stop tor@default.service
```

This reduces the attack surface when I am not using Tor and avoids unnecessary traffic.

---

## Logs and monitoring

### Viewing logs in real time

```bash
# Via journalctl (recommended)
sudo journalctl -u tor@default.service -f

# Via log file (if configured in the torrc)
sudo tail -f /var/log/tor/notices.log
```

### Viewing the last N messages

```bash
sudo journalctl -u tor@default.service -n 50
```

### Filtering logs by level

```bash
# Errors only
sudo journalctl -u tor@default.service -p err

# Errors and warnings
sudo journalctl -u tor@default.service -p warning

# From a specific date
sudo journalctl -u tor@default.service --since "2025-01-15 10:00:00"
```

### Bootstrap log

The bootstrap is the most important phase to monitor. Here are the messages and their meaning:

```
Bootstrapped   0% (starting): Starting
Bootstrapped   5% (conn): Connecting to a relay
   -> Tor is attempting a TCP connection to the guard/bridge
Bootstrapped  10% (conn_done): Connected to a relay
   -> TCP connection established
Bootstrapped  14% (handshake): Handshaking with a relay
   -> TLS handshake in progress
Bootstrapped  15% (handshake_done): Handshake with a relay done
   -> TLS handshake completed successfully
Bootstrapped  20% (onehop_create): Establishing a one-hop circuit
   -> Creating a 1-hop circuit to download the consensus
Bootstrapped  25% (requesting_status): Asking for networkstatus consensus
   -> Requesting the consensus document
Bootstrapped  40% (loading_status): Loading networkstatus consensus
   -> Downloading the consensus
Bootstrapped  45% (loading_keys): Loading authority key certs
   -> Downloading Directory Authority certificates
Bootstrapped  50% (loading_descriptors): Loading relay descriptors
   -> Downloading relay microdescriptors
Bootstrapped  75% (enough_dirinfo): Loaded enough directory info to build circuits
   -> Enough descriptors to build circuits (not all, but sufficient)
Bootstrapped  80% (ap_conn): Connecting to a relay to build circuits
   -> Building the first complete circuit
Bootstrapped  85% (ap_conn_done): Connected to a relay to build circuits
   -> Connection to the first circuit's guard established
Bootstrapped  89% (ap_handshake): Finishing handshake with a relay to build circuits
   -> ntor handshake in progress for the first circuit
Bootstrapped  90% (ap_handshake_done): Handshake finished with a relay to build circuits
   -> Handshake completed
Bootstrapped  95% (circuit_create): Establishing a Tor circuit
   -> Extending the circuit (guard -> middle -> exit)
Bootstrapped 100% (done): Done
   -> Tor is ready. SocksPort is accepting connections.
```

### In my experience

Bootstrap with obfs4 bridges is significantly slower than direct bootstrap.
Typical times I have observed:

| Configuration | Bootstrap time |
|--------------|---------------|
| Direct connection (no bridge) | 5-15 seconds |
| obfs4 bridge (nearby bridge) | 15-30 seconds |
| obfs4 bridge (distant/slow bridge) | 30-120 seconds |
| obfs4 bridge on restrictive network | Up to 3 minutes |

If bootstrap is stuck for more than 2-3 minutes, the bridge is probably saturated or
unreachable. I verify with:
```bash
sudo journalctl -u tor@default.service -f
# If I see repeatedly:
# "Connection timed out to bridge xxx.xxx.xxx.xxx:port"
# -> The bridge is not working, I need to replace it
```

---

## Debugging common problems

### Problem 1: "Torrc error" on restart

```
[warn] Failed to parse/validate config: ...
```

**Diagnosis**:
```bash
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
```

**Common causes**:
- Bridge with incorrect format (missing spaces, truncated cert=)
- Misspelled directive (case-sensitive)
- Non-existent path for DataDirectory or Log
- Port already in use

### Problem 2: "Permission denied" on DataDirectory

```
[warn] Directory /var/lib/tor cannot be read: Permission denied
```

**Solution**:
```bash
sudo chown -R debian-tor:debian-tor /var/lib/tor
sudo chmod 700 /var/lib/tor
```

### Problem 3: "Clock skew" - Clock out of sync

```
[warn] Received a consensus that is X hours in the future
```

**Solution**:
```bash
timedatectl                          # Verify
sudo timedatectl set-ntp true        # Enable NTP
sudo systemctl restart systemd-timesyncd
date                                 # Verify that it is correct
```

### Problem 4: Bootstrap stuck with bridges

```
Bootstrapped 10% (conn): Connecting to a relay
... (no progress for 2+ minutes)
```

**Step-by-step diagnosis**:

1. **Verify that obfs4proxy exists and is executable**:
   ```bash
   ls -la /usr/bin/obfs4proxy
   # If missing: sudo apt install obfs4proxy
   ```

2. **Verify the bridge format in the torrc**:
   ```bash
   grep "^Bridge" /etc/tor/torrc
   # Must be exactly:
   # Bridge obfs4 IP:PORT FINGERPRINT cert=CERT iat-mode=N
   ```

3. **Test bridge reachability**:
   ```bash
   # The bridge must be reachable on the specified port
   nc -zv <IP_BRIDGE> <PORTA> -w 5
   # If timeout -> the bridge is unreachable from your network
   ```

4. **Try different bridges**:
   Request new bridges from `https://bridges.torproject.org/options`

5. **Try without bridges** (temporarily):
   ```bash
   # Comment out the bridge lines in the torrc
   # UseBridges 1 -> #UseBridges 1
   sudo systemctl restart tor@default.service
   ```
   If it works without bridges, the problem is with the configured bridges.

### Problem 5: Tor starts but proxychains does not work

```
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  timeout
```

**Diagnosis**:

1. **Verify that port 9050 is listening**:
   ```bash
   sudo ss -tlnp | grep 9050
   # Must show: LISTEN ... 127.0.0.1:9050 ... tor
   ```

2. **Verify bootstrap**:
   ```bash
   sudo journalctl -u tor@default.service | grep Bootstrapped
   # Must show "Bootstrapped 100%"
   ```

3. **Test without proxychains**:
   ```bash
   curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
   ```

4. **Verify proxychains.conf**:
   ```bash
   grep -v "^#" /etc/proxychains4.conf | grep -v "^$"
   # Must contain:
   # dynamic_chain
   # proxy_dns
   # socks5 127.0.0.1 9050
   ```

---

> **Continues in**: [Maintenance and Monitoring](manutenzione-e-monitoraggio.md) for Unix
> signals, health monitoring, maintenance procedures, and post-install verification.

---

## See also

- [Maintenance and Monitoring](manutenzione-e-monitoraggio.md) - Signals, health checks, maintenance
- [Installation and Verification](installazione-e-verifica.md) - Initial setup
- [torrc - Complete Guide](torrc-guida-completa.md) - Configuration to reload
- [Nyx and Monitoring](../04-strumenti-operativi/nyx-e-monitoraggio.md) - TUI monitor for the service
- [Real-World Scenarios](scenari-reali.md) - Pentester operational cases

---

## Cheat Sheet - systemd Commands for Tor

| Command | Description |
|---------|-------------|
| `sudo systemctl start tor@default.service` | Start Tor |
| `sudo systemctl stop tor@default.service` | Stop Tor |
| `sudo systemctl restart tor@default.service` | Restart Tor |
| `sudo systemctl reload tor@default.service` | Reload torrc (SIGHUP) |
| `sudo systemctl status tor@default.service` | Service status |
| `sudo systemctl enable tor@default.service` | Auto-start at boot |
| `sudo journalctl -u tor@default.service -f` | Real-time logs |
| `sudo journalctl -u tor@default.service \| grep Bootstrap` | Bootstrap status |
| `sudo kill -HUP $(pidof tor)` | Reload torrc (alternative) |
| `sudo kill -USR1 $(pidof tor)` | Log statistics |
| `nyx` | TUI monitor (requires ControlPort) |
