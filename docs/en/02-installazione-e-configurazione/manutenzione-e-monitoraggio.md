> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/manutenzione-e-monitoraggio.md) | English

# Signals, Monitoring, and Maintenance of Tor

Unix signals for the Tor process, periodic service health checks,
maintenance procedures (cache cleanup, guard reset), and post-installation checklist.

Extracted from [Service Management](gestione-del-servizio.md).

---

## Table of Contents

- [Tor process signals](#tor-process-signals)
- [Tor health monitoring](#tor-health-monitoring)
- [Maintenance procedures](#maintenance-procedures)
- [Complete post-installation verification](#complete-post-installation-verification)

---

## Tor process signals

In addition to systemd commands, Tor responds to Unix signals:

| Signal | Effect | systemd equivalent |
|--------|--------|-------------------|
| SIGHUP | Reloads torrc, preserves circuits | `systemctl reload` |
| SIGINT | Clean shutdown (waits for circuits) | `systemctl stop` |
| SIGTERM | Clean shutdown | `systemctl stop` |
| SIGUSR1 | Logs current statistics | (none) |
| SIGUSR2 | Switches to debug log level | (none) |

### SIGHUP vs restart

`SIGHUP` (reload) is preferable when:
- Changing minor parameters (logging, timeouts)
- Updating bridges
- Modifying exit/entry nodes

`restart` is necessary when:
- Changing ControlPort or SocksPort
- Changing DataDirectory
- Adding/removing features (relay, hidden service)

### In my experience

I use `reload` when changing bridges:
```bash
# 1. Edit the torrc with the new bridges
sudo nano /etc/tor/torrc

# 2. Verify the configuration
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config

# 3. Reload (preserves existing circuits)
sudo systemctl reload tor@default.service

# 4. Verify in the logs that the new bridges work
sudo journalctl -u tor@default.service -f
```

---

## Tor health monitoring

### Periodic checks

```bash
# 1. Is Tor active?
systemctl is-active tor@default.service

# 2. Are the ports listening?
sudo ss -tlnp | grep -E "9050|9051"
sudo ss -ulnp | grep 5353

# 3. Is bootstrap at 100%?
sudo journalctl -u tor@default.service | grep "Bootstrapped 100%"

# 4. Are there recent errors?
sudo journalctl -u tor@default.service -p err --since "1 hour ago"

# 5. Is Tor routing working?
curl --socks5-hostname 127.0.0.1:9050 -s https://check.torproject.org/api/ip
# Expected response: {"IsTor":true,"IP":"..."}

# 6. Does NEWNYM work?
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
# Expected response: 250 OK
```

### Monitoring resources

```bash
# CPU and memory of the Tor process
ps aux | grep /usr/bin/tor

# Active network connections
sudo ss -tnp | grep tor | wc -l

# Disk space used by cache
du -sh /var/lib/tor/
```

---

## Maintenance procedures

### Cache cleanup and reset

If Tor is behaving abnormally (consistently slow circuits, repeated bootstrap
failures), clearing the cache can help:

```bash
# 1. Stop Tor
sudo systemctl stop tor@default.service

# 2. Clean the cache (keeps keys and state)
sudo rm -f /var/lib/tor/cached-*

# 3. Restart
sudo systemctl start tor@default.service
# The next bootstrap will be slower because it downloads everything from scratch
```

### Full reset (including guards)

**WARNING**: this resets the guard selection. Only do this if you suspect that
the guard is compromised.

```bash
sudo systemctl stop tor@default.service
sudo rm -f /var/lib/tor/cached-* /var/lib/tor/state
sudo systemctl start tor@default.service
```

### Configuration backup

```bash
# Backup the torrc and bridges
sudo cp /etc/tor/torrc /etc/tor/torrc.backup.$(date +%Y%m%d)

# Backup the state (guard selection)
sudo cp /var/lib/tor/state /var/lib/tor/state.backup.$(date +%Y%m%d)
```

---

## Complete post-installation verification

Checklist to run after every installation or significant change:

```bash
# 1. Valid configuration
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
echo "Config: OK"

# 2. Active service
sudo systemctl restart tor@default.service
sleep 5
systemctl is-active tor@default.service
echo "Service: OK"

# 3. Ports listening
sudo ss -tlnp | grep 9050 && echo "SocksPort: OK"
sudo ss -tlnp | grep 9051 && echo "ControlPort: OK"
sudo ss -ulnp | grep 5353 && echo "DNSPort: OK"

# 4. Bootstrap completed (wait up to 2 minutes)
timeout 120 bash -c 'while ! sudo journalctl -u tor@default.service | grep -q "Bootstrapped 100%"; do sleep 2; done'
echo "Bootstrap: OK"

# 5. Working Tor connection
IP=$(curl --socks5-hostname 127.0.0.1:9050 -s https://api.ipify.org)
echo "Tor exit IP: $IP"

# 6. Working ControlPort
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
RESULT=$(printf "AUTHENTICATE %s\r\nGETINFO version\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051 | head -3)
echo "ControlPort: $RESULT"
```

---

## See also

- [Service Management](gestione-del-servizio.md) - systemd, logs, debugging
- [Troubleshooting and Structure](troubleshooting-e-struttura.md) - Common issues, file structure
- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - ControlPort and signals
- [Nyx and Monitoring](../04-strumenti-operativi/nyx-e-monitoraggio.md) - TUI monitor
- [Real-World Scenarios](scenari-reali.md) - Pentester operational cases
