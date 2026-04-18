> **Lingua / Language**: [Italiano](../../02-installazione-e-configurazione/installazione-e-verifica.md) | English

# Tor Installation and Verification - Complete Guide for Debian/Kali

This document covers the installation of Tor and its associated components (obfs4proxy,
proxychains, torsocks, nyx) on Debian-based systems such as Kali Linux. It includes
installation verification, troubleshooting for the most common issues, and the minimal
initial configuration needed to get a working system.

Based on my direct experience on Kali Linux (Debian-based), where I configured
Tor for use with proxychains, obfs4 bridges, and ControlPort.

---
---

## Table of Contents

- [System prerequisites](#system-prerequisites)
- [Package installation](#package-installation)
- [Installation verification](#installation-verification)
**Deep dives** (dedicated files):
- [Initial Configuration](configurazione-iniziale.md) - Minimal torrc, debian-tor, Firefox profile
- [Troubleshooting and Structure](troubleshooting-e-struttura.md) - Common issues, file structure, upgrading


## System prerequisites

### Operating system

Tor natively supports:
- Debian, Ubuntu, Kali Linux (`.deb` packages)
- Fedora, CentOS, RHEL (`.rpm` packages)
- Arch Linux (`pacman` packages)
- macOS (via Homebrew)
- Windows (Tor Browser or Expert Bundle only)

This guide focuses on **Debian/Kali** because that is the system I use.

### Minimum hardware requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 256 MB | 512 MB+ |
| Disk | 50 MB for Tor + ~200 MB for descriptor cache | 500 MB+ |
| CPU | Any x86_64 or ARM | Multi-core for relays |
| Network | Any TCP connection | Stable bandwidth for relays |

For a **client** (our use case), the requirements are minimal. For a **relay**, more
resources are needed, especially stable bandwidth.

---

## Package installation

### Method 1: System repositories (simplest)

```bash
sudo apt update
sudo apt install tor obfs4proxy proxychains4 torsocks nyx
```

This installs:
- `tor` - the Tor daemon
- `obfs4proxy` - pluggable transport for traffic obfuscation
- `proxychains4` - wrapper to force applications through a proxy
- `torsocks` - alternative to proxychains based on LD_PRELOAD
- `nyx` - TUI monitor for Tor (formerly `arm`)

### In my experience

On Kali Linux, all these packages are available in the standard repositories:
```bash
> sudo apt install tor obfs4proxy
Reading package lists... Done
Building dependency tree... Done
The following NEW packages will be installed:
  obfs4proxy tor tor-geoipdb
...
```

The `tor-geoipdb` package is installed as a dependency and contains the GeoIP
database for relay geolocation.

### Method 2: Official Tor Project repository (more up-to-date)

Debian repositories may carry slightly outdated versions of Tor. For the most
recent version, use the official repository:

```bash
# Install repository dependencies
sudo apt install apt-transport-https gpg

# Add the Tor Project GPG key
wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | sudo tee /usr/share/keyrings/tor-archive-keyring.gpg > /dev/null

# Add the repository (replace "bookworm" with your release)
echo "deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org bookworm main" | sudo tee /etc/apt/sources.list.d/tor.list

# For Kali (which is based on Debian testing/sid):
echo "deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org sid main" | sudo tee /etc/apt/sources.list.d/tor.list

# Update and install
sudo apt update
sudo apt install tor deb.torproject.org-keyring
```

### Verifying the installed version

```bash
> tor --version
Tor version 0.4.8.10.
```

The version matters because it determines:
- Which protocols are supported (ntor, hs-v3, congestion control, etc.)
- Which known vulnerabilities have been patched
- Which consensus format is supported

---

## Installation verification

### 1. Verify that the tor binary is installed correctly

```bash
> which tor
/usr/bin/tor

> which obfs4proxy
/usr/bin/obfs4proxy

> which proxychains4
/usr/bin/proxychains4

> which torsocks
/usr/bin/torsocks
```

### 2. Verify permissions

Tor runs as the `debian-tor` user on Debian systems. Directories must have the
correct permissions:

```bash
> ls -la /var/lib/tor/
total 24
drwx--S--- 3 debian-tor debian-tor 4096 ... .
...

> ls -la /var/log/tor/
total 8
drwxr-s--- 2 debian-tor adm 4096 ... .
...

> ls -la /run/tor/
total 4
drwxr-sr-x 2 debian-tor debian-tor 100 ... .
-rw------- 1 debian-tor debian-tor  32 ... control.authcookie
```

### 3. Verify obfs4proxy

```bash
> obfs4proxy --version
obfs4proxy-0.0.14

> ls -la /usr/bin/obfs4proxy
-rwxr-xr-x 1 root root 7061504 ... /usr/bin/obfs4proxy
```

obfs4proxy must be executable. If it is not:
```bash
sudo chmod +x /usr/bin/obfs4proxy
```

### 4. Verify the configuration (without starting Tor)

```bash
> sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
...
Configuration was valid
```

If there are errors:
```bash
> sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
[warn] Unrecognized option 'InvalidOption'
...
```

In my experience, the most common errors at this stage are:
- Malformed bridge lines (missing `cert=` or incorrect fingerprint)
- Wrong path for `obfs4proxy`
- Incorrect permissions on `/var/lib/tor/`

---

> **Continues in**: [Initial Configuration](configurazione-iniziale.md) for the minimal
> torrc configuration, the debian-tor group, and the Firefox profile, and in
> [Troubleshooting and Structure](troubleshooting-e-struttura.md) for common issues,
> file structure, and upgrading.

---

## See also

- [Initial Configuration](configurazione-iniziale.md) - Minimal torrc, debian-tor, Firefox profile
- [Troubleshooting and Structure](troubleshooting-e-struttura.md) - Common issues, file structure, upgrading
- [torrc - Complete Guide](torrc-guida-completa.md) - Full configuration after installation
- [Service Management](gestione-del-servizio.md) - systemd, logs, troubleshooting
- [Real-World Scenarios](scenari-reali.md) - Pentester operational cases
