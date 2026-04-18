> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/configurazione-iniziale.md) | English

# Initial Configuration - Minimal Torrc, debian-tor Group, and Firefox

Minimal initial torrc configuration, debian-tor group management
for ControlPort access, and a dedicated Firefox profile for Tor.

Extracted from [Installation and Verification](installazione-e-verifica.md).

---

## Table of Contents

- [systemd service management](#systemd-service-management)
- [Minimal initial configuration](#minimal-initial-configuration)
- [debian-tor group configuration](#debian-tor-group-configuration)
- [Firefox profile configuration for Tor](#firefox-profile-configuration-for-tor)

---

## systemd service management

### Tor systemd unit

Tor on Debian uses a systemd template unit: `tor@default.service`. This allows
running multiple Tor instances with different configurations.

```bash
# Start Tor
sudo systemctl start tor@default.service

# Stop Tor
sudo systemctl stop tor@default.service

# Restart Tor (stops and restarts the daemon)
sudo systemctl restart tor@default.service

# Reload configuration (SIGHUP - does not stop the daemon)
sudo systemctl reload tor@default.service

# Enable Tor at system boot
sudo systemctl enable tor@default.service

# Disable automatic startup
sudo systemctl disable tor@default.service

# Current status
sudo systemctl status tor@default.service
```

### Difference between restart and reload

| Operation | What it does | Circuits | Connections |
|-----------|-------------|----------|-------------|
| `restart` | Stops and restarts the daemon | All destroyed | Interrupted |
| `reload` | Sends SIGHUP, re-reads torrc | Preserved (if possible) | Preserved |
| `NEWNYM` | Signal via ControlPort | Marked as dirty | Preserved |

In my experience, I use:
- `restart` when I change bridge configuration or enable/disable features
- `reload` when I modify minor parameters
- `NEWNYM` to change IP without interrupting anything

---

## Minimal initial configuration

### The `/etc/tor/torrc` file

After installation, the torrc contains only comments. The minimal configuration
for my setup is:

```ini
# === Listening ports ===
SocksPort 9050                  # SOCKS5 proxy for applications
DNSPort 5353                    # DNS via Tor (prevents DNS leaks)
AutomapHostsOnResolve 1         # Automatically resolves .onion and hostnames via Tor
ControlPort 9051                # Control port for NEWNYM and monitoring
CookieAuthentication 1          # ControlPort authentication via cookie file

# === Security ===
ClientUseIPv6 0                 # Disable IPv6 (prevents leaks)

# === Logging ===
Log notice file /var/log/tor/notices.log

# === Data directory ===
DataDirectory /var/lib/tor
```

After saving:
```bash
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
sudo systemctl restart tor@default.service
```

### Verify that everything works

```bash
# Verify that ports are listening
> sudo netstat -tlnp | grep tor
tcp   0  0  127.0.0.1:9050   0.0.0.0:*  LISTEN  1234/tor
tcp   0  0  127.0.0.1:9051   0.0.0.0:*  LISTEN  1234/tor

> sudo netstat -ulnp | grep tor
udp   0  0  127.0.0.1:5353   0.0.0.0:*         1234/tor

# Verify bootstrap
> sudo journalctl -u tor@default.service -n 20
...
Bootstrapped 100% (done): Done

# Verify that Tor works
> curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
185.220.101.143

> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
185.220.101.143
```

If the returned IP is different from your real IP, Tor is working.

---

## debian-tor group configuration

To use the ControlPort without sudo, the user must be in the `debian-tor` group.
This group has access to the authentication cookie file.

```bash
# Add the current user to the group
sudo usermod -aG debian-tor $USER

# IMPORTANT: the group change requires a new login
# Option 1: restart the session
# Option 2: force logout
pkill -KILL -u $USER

# After login, verify
> groups
... debian-tor ...

# Verify access to the cookie
> ls -la /run/tor/control.authcookie
-rw-r----- 1 debian-tor debian-tor 32 ... /run/tor/control.authcookie

> xxd -p /run/tor/control.authcookie | tr -d '\n'
a1b2c3d4e5f6...  (32 bytes in hex)
```

### In my experience

This step initially blocked me. When I ran my `newnym` script:
```bash
> ~/scripts/newnym
514 Authentication required
```

The 514 error meant the cookie was unreadable because my user was not in the
`debian-tor` group. After `sudo usermod -aG debian-tor $USER` and a session
restart (`pkill -KILL -u $USER`), the issue was resolved:
```bash
> ~/scripts/newnym
250 OK
250 closing connection
```

---

## Firefox profile configuration for Tor

To browse via Tor without Tor Browser, I created a dedicated Firefox profile:

```bash
# Create the profile
firefox -no-remote -CreateProfile tor-proxy

# Launch Firefox with the Tor profile via proxychains
proxychains firefox -no-remote -P tor-proxy & disown
```

The `-no-remote` flag is essential: it prevents Firefox from connecting to an
already running instance (which might not route through Tor).

Alternative for processes that must survive logout:
```bash
nohup proxychains firefox -no-remote -P tor-proxy >/dev/null 2>&1 &
```

### Warning

Using Firefox with a dedicated profile via proxychains **is NOT** equivalent to Tor Browser.
Standard Firefox has:
- A different User-Agent
- No anti-fingerprinting protections
- WebRTC potentially active (IP leak)
- Canvas, WebGL, and fonts not spoofed

I use it for convenience and testing, not for maximum anonymity.

---

## See also

- [Installation and Verification](installazione-e-verifica.md) - Prerequisites, installation, verification
- [Troubleshooting and Structure](troubleshooting-e-struttura.md) - Common issues, file structure
- [torrc - Complete Guide](torrc-guida-completa.md) - All torrc directives
- [Service Management](gestione-del-servizio.md) - Advanced systemd, logs, debugging
- [Tor Browser and Applications](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Firefox vs Tor Browser
- [Real-World Scenarios](scenari-reali.md) - Pentester operational cases
