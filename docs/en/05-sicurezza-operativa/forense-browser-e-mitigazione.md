> **Lingua / Language**: [Italiano](../../05-sicurezza-operativa/forense-browser-e-mitigazione.md) | English

# Forensic Analysis - Browser, Mitigation and Tools

Browser artifacts (Firefox, Tor Browser), proxychains and torsocks traces,
forensic timeline of a Tor session, 4-level mitigation (configuration,
cleanup, tmpfs, amnesic system) and analysis tools.

> **Extracted from**: [Forensic Analysis and Tor Artifacts](analisi-forense-e-artefatti.md)
> for disk, log, RAM and network artifacts.

---


### Firefox tor-proxy profile

```
~/.mozilla/firefox/xxxxxxxx.tor-proxy/
├── places.sqlite          ← History and bookmarks (if not cleared)
├── cookies.sqlite         ← Cookies
├── formhistory.sqlite     ← Filled form data
├── webappsstore.sqlite    ← localStorage
├── cache2/               ← HTTP cache
├── sessionstore.jsonlz4   ← Open tabs (session restore)
├── prefs.js              ← Settings (reveals proxy config)
├── cert9.db              ← Saved certificates
└── logins.json           ← Saved passwords (if not empty)
```

**prefs.js** is particularly informative:

```javascript
// reveals the proxy configuration:
user_pref("network.proxy.socks", "127.0.0.1");
user_pref("network.proxy.socks_port", 9050);
user_pref("network.proxy.socks_remote_dns", true);
// ↑ Confirms use of Tor as SOCKS5 proxy
```

### Download directory

```bash
# Files downloaded via Tor Browser or Firefox tor-proxy
ls -la ~/Downloads/
# File metadata (creation time, source URL) may be preserved
```

### Tor Browser download evidence

```bash
# The Tor Browser directory itself
ls ~/tor-browser/
# Its mere existence is evidence
# The creation date indicates when it was installed
stat ~/tor-browser/start-tor-browser
```

---

## Proxychains and torsocks artifacts

### proxychains

```
/etc/proxychains4.conf
  ↑ Configuration with Tor proxy (socks5 127.0.0.1 9050)
  ↑ Reveals use of proxychains to torify applications

~/.proxychains/proxychains.conf
  ↑ User config (if present)
```

The proxychains output (if not suppressed) is written to stderr:
```
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
```

If captured in a log file → evidence of use.

### torsocks

```
/etc/tor/torsocks.conf
  ↑ torsocks configuration

# torsocks log (if logged to file)
/var/log/torsocks.log  ← if TORSOCKS_LOG_FILE_PATH is configured
```

### Shell history

```bash
# ~/.bash_history or ~/.zsh_history
proxychains curl https://target-site.com
torsocks ssh user@hidden-server.com
nyx
~/scripts/newnym
# ↑ Every command with proxychains/torsocks/nyx in the history
```

**Mitigation**: `HISTFILE=/dev/null` or `unset HISTFILE` before the session.

---

## Forensic timeline of a Tor session

An analyst reconstructs the timeline from multiple sources:

```
09:20:00  apt history: "apt install tor obfs4proxy nyx"
          ↑ Tor package installation

09:22:00  /etc/tor/torrc: mtime = 09:22:00
          ↑ torrc configuration modified

09:23:01  journalctl: "Starting Tor..."
09:23:41  journalctl: "Bootstrapped 100% (done)"
          ↑ Tor started and connected

09:23:45  /var/lib/tor/state: "LastWritten 09:23:45"
          ↑ State file updated

09:25:00  ss -tnp: connection to 198.51.100.42:9001
          ↑ Connection to guard node

09:30:00  .bash_history: "proxychains curl https://target.com"
          ↑ Command executed via Tor

14:32:15  journalctl: "NEWNYM command received"
          ↑ Identity change

14:32:20  /var/lib/tor/state: Guard changed
          ↑ New circuit built

18:00:00  journalctl: "Tor daemon shutting down"
          ↑ Tor shutdown
```

---

## Artifact mitigation

### Level 1: Base configuration

```ini
# torrc - minimize logging
Log notice file /var/log/tor/notices.log
# Do NOT use debug or info

# Or: log only to stdout (not to file)
Log notice stdout
```

```bash
# Disable shell history for the session
unset HISTFILE
# or
export HISTFILE=/dev/null
```

### Level 2: Post-session cleanup

```bash
# Clear Tor artifacts
sudo systemctl stop tor@default.service
sudo rm -rf /var/lib/tor/cached-*
sudo rm -f /var/log/tor/*
# Do NOT delete /var/lib/tor/state if you want to keep the guard

# Clear browser artifacts
rm -rf ~/.mozilla/firefox/*.tor-proxy/cache2/
rm -f ~/.mozilla/firefox/*.tor-proxy/places.sqlite
rm -f ~/.mozilla/firefox/*.tor-proxy/cookies.sqlite

# Clear history
rm -f ~/.bash_history ~/.zsh_history
```

### Level 3: tmpfs and RAM-only

```bash
# Mount Tor's DataDirectory in tmpfs
# /etc/fstab:
tmpfs /var/lib/tor tmpfs defaults,noatime,size=256M 0 0

# Effect: all Tor state is in RAM
# On reboot: everything automatically cleared
# Downside: guard changes on every reboot (bad for security)
```

### Level 4: Amnesic system

**Tails**: the entire operating system runs in RAM. On shutdown, zero artifacts
on disk. It is the definitive solution for zero-evidence.

**Whonix**: not amnesic by default, but the Workstation can use tmpfs
for sensitive directories.

---

## Forensic analysis tools

### For an analyst looking for Tor artifacts

| Tool | Use |
|------|-----|
| `strings` | Search for Tor strings in files/RAM dumps |
| `find / -name "*tor*"` | Search for Tor-related files |
| `grep -r "9050\|9051\|SocksPort" /etc/` | Search for proxy configurations |
| `journalctl -u tor*` | Tor service logs |
| `sqlite3 places.sqlite` | Analyze Firefox history |
| `volatility` | RAM dump analysis |
| `autopsy/sleuthkit` | Disk analysis |
| `log2timeline` | Timeline reconstruction |

### Specific forensic queries

```bash
# Search for evidence of Tor on disk
find / -name "torrc" -o -name "torsocks.conf" -o -name "proxychains*.conf" 2>/dev/null

# Search in command history
grep -r "proxychains\|torsocks\|tor-browser\|newnym\|nyx" /home/*/.*history 2>/dev/null

# Search for running Tor processes
ps aux | grep -i tor

# Search for connections to Tor ports
ss -tnp | grep -E ":(9050|9051|9001|9040) "

# Search for installed Tor packages
dpkg -l | grep -iE "^ii.*(tor |torsocks|obfs4|nyx|proxychains)"
```

---

## In my experience

Studying Tor's forensic artifacts was essential to understand my
level of exposure. I did a practical exercise: after a Tor session
on my Kali, I systematically searched for all the artifacts that an analyst
would have found.

**What I found**:
- `/var/lib/tor/state` with the fingerprint of my guard and the timestamp of last use
- `journalctl` with precise timestamps of every start, NEWNYM, and shutdown of Tor
- `.zsh_history` full of `proxychains curl ...` and `nyx` commands
- `prefs.js` of the tor-proxy profile with the SOCKS5 configuration
- `torrc` with the configured obfs4 bridges
- `dpkg -l` output clearly showing tor, obfs4proxy, nyx, torsocks, proxychains

**What I mitigated**:
- Shell history: I now use `HISTFILE=/dev/null` during sensitive sessions
- Log retention: reduced to 1 week in journald.conf
- Browser: I periodically clear the tor-proxy profile cache

**What I did not mitigate** (accepted as risk):
- Installed packages are visible (does not worry me, I use Tor legally)
- The torrc with bridges is on disk (I could encrypt the partition)
- The Tor state file exists (needed to maintain the guard)

For a scenario where evidence of Tor usage is a problem (journalists in
hostile countries, activists), the answer is Tails: no artifacts on disk, everything
in RAM, shutdown = total erasure.

---

## See also

- [OPSEC and Common Mistakes](opsec-e-errori-comuni.md) - Mistakes that leave forensic traces
- [System Hardening](hardening-sistema.md) - Reducing the forensic surface with sysctl and AppArmor
- [Isolation and Compartmentalization](isolamento-e-compartimentazione.md) - Tails, Whonix, Qubes for amnesia
- [DNS Leak](dns-leak.md) - DNS artifacts in system logs
- [Tor Browser and Applications](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Browser artifacts
