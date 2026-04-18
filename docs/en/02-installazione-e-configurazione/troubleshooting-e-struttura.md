> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/troubleshooting-e-struttura.md) | English

# Troubleshooting, File Structure, and Upgrading Tor

Resolving common installation issues, a complete map of installed files
with their permissions, and safe upgrade procedures.

Extracted from [Installation and Verification](installazione-e-verifica.md).

---

## Table of Contents

- [Installation troubleshooting](#installation-troubleshooting)
- [Tor file structure after installation](#tor-file-structure-after-installation)
- [Upgrading Tor](#upgrading-tor)

---

## Installation troubleshooting

### Problem: Tor does not start

```bash
> sudo systemctl status tor@default.service
● tor@default.service - Anonymizing overlay network for TCP
   Active: failed
```

**Common causes and solutions**:

1. **Incorrect permissions on DataDirectory**:
   ```bash
   sudo chown -R debian-tor:debian-tor /var/lib/tor
   sudo chmod 700 /var/lib/tor
   ```

2. **Another Tor instance is already running**:
   ```bash
   # Check for a lock file
   ls -la /var/lib/tor/lock
   # If the process no longer exists, remove the lock
   sudo rm /var/lib/tor/lock
   ```

3. **Errors in the torrc**:
   ```bash
   sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
   ```

4. **Port conflict**:
   ```bash
   # Check if port 9050 is already in use
   sudo ss -tlnp | grep 9050
   ```

### Problem: Bootstrap stuck

```bash
> sudo journalctl -u tor@default.service -f
Bootstrapped 10% (conn): Connecting to a relay
... (stays here)
```

**Common causes**:

1. **Firewall blocking Tor connections**:
   - If you are on a restrictive network, you need to use obfs4 bridges
   - Verify: `curl -s https://check.torproject.org` (without Tor) -- if the site
     is reachable, the network does not completely block Tor

2. **DNS not working**:
   ```bash
   # Verify that system DNS works
   nslookup torproject.org
   ```

3. **Non-functional bridges**:
   ```bash
   # In the logs you will see:
   Connection timed out to bridge xxx.xxx.xxx.xxx:port
   ```
   Solution: request fresh bridges from `https://bridges.torproject.org/options`

4. **Incorrect system clock**:
   ```bash
   # Verify
   timedatectl
   # If the clock is wrong
   sudo timedatectl set-ntp true
   ```

### Problem: proxychains gives "need more proxies"

```
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  timeout
!!! need more proxies !!!
```

This means Tor is not running or has not completed bootstrap:
```bash
sudo systemctl status tor@default.service
sudo systemctl start tor@default.service
```

In my experience, this error appears when I forget to start Tor after a system
reboot (if I have not enabled `systemctl enable`).

---

## Tor file structure after installation

```
/etc/tor/
├── torrc                        # Main configuration file (to be modified)
├── torrc.d/                     # Directory for modular configurations
└── torsocks.conf                # torsocks configuration

/usr/bin/
├── tor                          # Tor daemon
├── obfs4proxy                   # obfs4 pluggable transport
├── proxychains4                 # Proxy wrapper
├── torsocks                     # SOCKS wrapper (alternative to proxychains)
└── nyx                          # TUI monitor

/var/lib/tor/                    # Persistent data (cache, keys, state)
├── cached-certs
├── cached-microdesc
├── cached-microdesc.new
├── cached-consensus
├── state                        # Guard selection and persistent state
└── lock                         # Lock file (one process at a time)

/var/log/tor/
└── notices.log                  # Log (if configured in the torrc)

/run/tor/
├── control.authcookie           # Cookie for ControlPort (32 bytes)
├── tor.pid                      # Process PID
└── socks                        # Unix domain socket (if configured)

/usr/share/tor/
├── geoip                        # GeoIP IPv4 database
└── geoip6                       # GeoIP IPv6 database
```

### Critical permissions

| File/Directory | Owner | Permissions | Notes |
|---------------|-------|-------------|-------|
| `/var/lib/tor/` | debian-tor:debian-tor | 700 | Only Tor can read/write |
| `/run/tor/control.authcookie` | debian-tor:debian-tor | 640 | Readable by the debian-tor group |
| `/etc/tor/torrc` | root:root | 644 | Readable by all, writable by root |
| `/var/log/tor/` | debian-tor:adm | 2750 | setgid for group adm |

---

## Upgrading Tor

### Upgrading from repositories

```bash
sudo apt update
sudo apt upgrade tor
```

After upgrading, Tor is automatically restarted by systemd (if the service
was active).

### Verify after upgrading

```bash
tor --version
sudo systemctl status tor@default.service
sudo journalctl -u tor@default.service -n 10
```

### Security considerations for upgrades

Upgrading Tor promptly is important because vulnerabilities are discovered
and patched regularly. Outdated versions may have:
- Bugs in the handshake protocol
- Vulnerabilities in guard selection
- Memory safety issues
- Isolation bypasses

Tor's security policy: end-of-life versions do not receive patches.
Always check the [release page](https://www.torproject.org/download/tor/)
to ensure you are running a supported version.

---

## See also

- [Installation and Verification](installazione-e-verifica.md) - Prerequisites, installation, verification
- [Initial Configuration](configurazione-iniziale.md) - Minimal torrc, debian-tor, Firefox
- [Service Management](gestione-del-servizio.md) - systemd, logs, in-depth debugging
- [Real-World Scenarios](scenari-reali.md) - Pentester operational cases
