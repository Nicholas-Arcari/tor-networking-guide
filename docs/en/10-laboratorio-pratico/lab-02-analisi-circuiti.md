> **Lingua / Language**: [Italiano](../../10-laboratorio-pratico/lab-02-analisi-circuiti.md) | English

# Lab 02 - Tor Circuit Analysis with Stem and nyx

A hands-on exercise to observe, analyze, and manipulate Tor circuits using
the ControlPort, the Python Stem library, and the nyx monitor.

**Estimated time**: 30-40 minutes
**Prerequisites**: Lab 01 completed, Python 3 with pip
**Difficulty**: Intermediate

---

## Table of Contents

- [Objectives](#objectives)
- [Phase 1: Stem setup](#phase-1-stem-setup)
- [Phase 2: Querying circuits](#phase-2-querying-circuits)
- [Phase 3: NEWNYM and IP change verification](#phase-3-newnym-and-ip-change-verification)
- [Phase 4: Monitoring events in real time](#phase-4-monitoring-events-in-real-time)
- [Phase 5: nyx - Visual monitor](#phase-5-nyx--visual-monitor)
- [Phase 6: Analysis exercise](#phase-6-analysis-exercise)
- [Final checklist](#final-checklist)

---

## Objectives

By the end of this lab, you will know how to:
1. Connect to the ControlPort with Python Stem
2. List active circuits and their relays (Guard, Middle, Exit)
3. Execute NEWNYM and verify the IP change
4. Monitor Tor events in real time
5. Use nyx for visual circuit analysis

---

## Phase 1: Stem setup

```bash
# Install Stem
pip install stem

# Verify
python3 -c "import stem; print(stem.__version__)"
# Expected output: 1.8.x or higher
```

---

## Phase 2: Querying circuits

Create the file `circuit-info.py`:

```python
#!/usr/bin/env python3
"""Visualizza i circuiti Tor attivi con dettagli di ogni relay."""

from stem import CircStatus
from stem.control import Controller

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    print(f"Tor version: {ctrl.get_version()}")
    print(f"Circuiti attivi:\n")

    for circ in sorted(ctrl.get_circuits()):
        if circ.status != CircStatus.BUILT:
            continue

        print(f"  Circuito #{circ.id} [{circ.purpose}]")
        for i, entry in enumerate(circ.path):
            fingerprint, nickname = entry
            desc = ctrl.get_network_status(fingerprint, None)
            role = ["Guard", "Middle", "Exit"][min(i, 2)]
            if desc:
                print(f"    {role}: {nickname} ({desc.address}:{desc.or_port})")
                print(f"           Flags: {', '.join(desc.flags)}")
                print(f"           Bandwidth: {desc.bandwidth} KB/s")
            else:
                print(f"    {role}: {nickname} (descriptor non disponibile)")
        print()
```

```bash
# Execute
python3 circuit-info.py

# Expected output:
# Tor version: 0.4.x.x
# Circuiti attivi:
#
#   Circuito #1 [GENERAL]
#     Guard: RelayName (IP:PORT)
#            Flags: Fast, Guard, HSDir, Running, Stable, Valid, V2Dir
#            Bandwidth: 15000 KB/s
#     Middle: RelayName (IP:PORT)
#            ...
#     Exit: RelayName (IP:PORT)
#            ...
```

**Exercise**: identify your persistent Guard. Run the script 3 times
at 5-minute intervals. The Guard should remain the same.

---

## Phase 3: NEWNYM and IP change verification

Create the file `newnym-verify.py`:

```python
#!/usr/bin/env python3
"""Esegue NEWNYM e verifica il cambio di exit IP."""

import time
import urllib.request
import socks
import socket
from stem.control import Controller
from stem import Signal

def get_tor_ip():
    """Ottieni l'IP di uscita via Tor."""
    socks.setdefaultproxy(socks.PROXY_TYPE_SOCKS5, "127.0.0.1", 9050)
    s = socks.socksocket()
    s.settimeout(15)
    try:
        s.connect(("api.ipify.org", 80))
        s.send(b"GET / HTTP/1.1\r\nHost: api.ipify.org\r\n\r\n")
        resp = s.recv(4096).decode()
        return resp.split("\r\n\r\n")[-1].strip()
    except:
        return "errore"
    finally:
        s.close()

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()

    ip_before = get_tor_ip()
    print(f"IP prima di NEWNYM: {ip_before}")

    ctrl.signal(Signal.NEWNYM)
    print("NEWNYM inviato, attendo 10 secondi...")
    time.sleep(10)

    ip_after = get_tor_ip()
    print(f"IP dopo NEWNYM:     {ip_after}")

    if ip_before != ip_after:
        print("✓ IP cambiato con successo")
    else:
        print("✗ IP non cambiato (può succedere se il pool di exit è piccolo)")
```

```bash
pip install PySocks  # if not installed
python3 newnym-verify.py
```

---

## Phase 4: Monitoring events in real time

Create the file `tor-events.py`:

```python
#!/usr/bin/env python3
"""Monitora eventi Tor in tempo reale (circuiti, stream, bandwidth)."""

import time
from stem.control import Controller, EventType

def circuit_event(event):
    if event.status == "BUILT":
        path = " → ".join([nick for fp, nick in event.path])
        print(f"  [CIRCUIT BUILT] #{event.id}: {path}")
    elif event.status == "CLOSED":
        print(f"  [CIRCUIT CLOSED] #{event.id} reason={event.reason}")

def stream_event(event):
    if event.status == "SUCCEEDED":
        print(f"  [STREAM] {event.target} via circuito #{event.circ_id}")

def bw_event(event):
    print(f"  [BW] Read: {event.read} B/s | Write: {event.written} B/s")

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    print("Monitoraggio eventi Tor (Ctrl+C per uscire)\n")

    ctrl.add_event_listener(circuit_event, EventType.CIRC)
    ctrl.add_event_listener(stream_event, EventType.STREAM)
    ctrl.add_event_listener(bw_event, EventType.BW)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nMonitoraggio terminato")
```

```bash
# In one terminal: run the monitor
python3 tor-events.py

# In another terminal: generate traffic
proxychains curl -s https://example.com > /dev/null
proxychains curl -s https://check.torproject.org > /dev/null

# Observe the events in the first terminal
```

---

## Phase 5: nyx - Visual monitor

```bash
# Launch nyx
nyx

# Screens (navigate with arrow keys):
# 1. Bandwidth graph: real-time graph
# 2. Connections: TLS connections to relays
# 3. Configuration: active torrc configuration
# 4. Torrc: torrc file with syntax highlighting
# 5. Log: real-time log

# Useful commands in nyx:
# n = NEWNYM (new identity)
# r = resolve hostname
# s = sort connections
# q = quit
```

**Exercise**: with nyx open, generate traffic using `proxychains curl` and observe
the bandwidth graph and new circuits in the Connections screen.

---

## Phase 6: Analysis exercise

1. **Identify your Guard**: use `circuit-info.py` and note the Guard.
   Verify it remains the same after 1 hour.

2. **Count circuits**: how many circuits are created during 5 minutes of
   browsing with `proxychains firefox`?

3. **NEWNYM timing**: how long does it take before NEWNYM actually changes
   the IP? Test with `newnym-verify.py`.

4. **Circuits per destination**: visit 3 different sites and observe whether Tor
   uses different circuits (with the event monitor).

---

## Troubleshooting

### Stem cannot connect to the ControlPort

```bash
# Error: stem.SocketError: [Errno 111] Connection refused
# → ControlPort not active. Verify:
grep "^ControlPort" /etc/tor/torrc
# Should show: ControlPort 9051

# Error: stem.connection.AuthenticationFailure
# → Cookie not readable. Verify:
ls -la /run/tor/control.authcookie
# Your user must be in the debian-tor group
```

### nyx does not start or shows a blank screen

```bash
# Error: "Unable to connect to tor"
# → Same cause: ControlPort not active or cookie permissions issue

# Black/blank screen after startup
# → The terminal is too small. nyx requires at least 80x24
# → Try: resize the terminal or use: stty rows 24 cols 80

# nyx not installed
pip3 install nyx
# or
sudo apt install nyx
```

### Circuits show "Purpose: GENERAL" but no "Purpose: HS_*"

```bash
# Normal if you are not using onion services at this moment.
# HS_* circuits only appear when you access a .onion address
# To trigger them:
curl --socks5-hostname 127.0.0.1:9050 -s http://2gzyxa5ihm7nsber... > /dev/null
# Now re-run the script and you will see HS_CLIENT_REND circuits
```

---

## Final checklist

- [ ] Stem installed and working
- [ ] Script circuit-info.py shows circuits with relay details
- [ ] NEWNYM changes the exit IP
- [ ] Event monitor detects circuits and streams in real time
- [ ] nyx launched and navigated through all 5 screens
- [ ] Persistent Guard identified and confirmed

---

## See also

- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - Complete ControlPort protocol
- [Nyx and Monitoring](../04-strumenti-operativi/nyx-e-monitoraggio.md) - 5 nyx screens in detail
- [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) - Why the Guard is persistent
