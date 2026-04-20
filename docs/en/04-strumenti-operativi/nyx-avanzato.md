> **Lingua / Language**: [Italiano](../../04-strumenti-operativi/nyx-avanzato.md) | English

# Nyx Advanced - Navigation, Configuration and Scripting

Navigation shortcuts, advanced Nyx configuration (.nyx/config),
debugging scenarios, comparison with alternatives, and scripting with Stem.

Extracted from [Nyx and Monitoring](nyx-e-monitoraggio.md).

---

## Table of Contents

- [Navigation and shortcuts](#navigation-and-shortcuts)
- [Advanced Nyx configuration](#advanced-nyx-configuration)
- [Debugging scenarios with Nyx](#debugging-scenarios-with-nyx)
- [Nyx vs alternatives](#nyx-vs-alternatives)
- [Scripting with Stem as an alternative](#scripting-with-stem-as-an-alternative)
- [Integration with other tools](#integration-with-other-tools)

---

## Navigation and shortcuts

### Global shortcuts

| Key | Action |
|-----|--------|
| ← → | Switch screen (1-5) |
| ↑ ↓ | Scroll in the current list |
| Page Up/Down | Fast scrolling |
| Home/End | Beginning/end of list |
| Enter | Details of the selected item |
| p | Pause/resume updates |
| h | Show help |
| q | Exit Nyx |

### Per-screen shortcuts

| Screen | Key | Action |
|--------|-----|--------|
| Bandwidth | s | Change aggregation period |
| Bandwidth | b | Toggle download/upload/both |
| Connections | s | Sort by column |
| Connections | u | Filter by connection type |
| Connections | d | Toggle DNS resolver |
| Configuration | / | Search directive |
| Configuration | Enter | Edit value |
| Log | s | Select minimum level |
| Log | / | Search in logs |
| Log | c | Clear displayed logs |
| Interpretor | Tab | Autocompletion |
| Interpretor | ↑ | Previous command (history) |

---

## Advanced Nyx configuration

### Configuration file

```bash
# Config path
~/.nyx/config
# or
~/.nyx/nyxrc
```

### Configurable options

```ini
# ~/.nyx/config

# Refresh rate (seconds)
redraw_rate 1

# Interface color
color_override false

# Maximum width (0 = auto)
max_line_wrap 0

# Log: initial minimum level
log_filter NOTICE

# Connections: DNS resolver enabled
resolve_dns true

# Connections: show GeoIP
show_locale true

# Bandwidth: initial period
bandwidth_rate 1

# Interpretor: history file
config_log ~/.nyx/log
```

### Startup flags

```bash
# Blind mode (no colors, for output redirect)
nyx --blind

# Verbose logging of nyx itself
nyx --log ~/.nyx/debug.log

# Specify custom config
nyx --config /path/to/custom/nyxrc
```

---

## Debugging scenarios with Nyx

### Scenario 1: Slow circuit

**Symptom**: browsing via Tor very slow, frequent timeouts.

```
1. Open Nyx → Connections screen
2. Identify the Guard → press Enter for details
3. Check:
   - Guard bandwidth: if < 1000 KB/s → slow guard
   - Flags: must have Fast, Stable, Guard
   - Uptime: unstable guard if low uptime
4. Bandwidth screen: verify effective throughput
   - If graph shows < 50 KB/s constantly → bottleneck
5. Solution: SIGNAL NEWNYM in the Interpretor for new circuits
   - If the problem persists → the guard is the bottleneck
   - Last resort: delete /var/lib/tor/state to force a new guard
```

### Scenario 2: Guard changing unexpectedly

**Symptom**: in the Connections screen, the Guard IP is different from usual.

```
1. Connections → verify the new Guard (fingerprint, nickname)
2. Interpretor: GETINFO entry-guards
   - Shows all guards in the list with status
3. Possible causes:
   - Previous guard offline (verify on metrics.torproject.org)
   - Natural rotation (~2-3 months)
   - Path bias detection discarded the guard
4. Verify /var/lib/tor/state:
   Guard in EntryGuard {nickname} {fingerprint} ... 
```

### Scenario 3: Bridge not connecting

**Symptom**: bootstrap stuck at 10-15%.

```
1. Log screen → filter for WARN:
   - "Could not connect to bridge" → bridge offline or blocked
   - "Connection refused" → port blocked by firewall/ISP
   - "TLS handshake failed" → DPI is interfering
2. Connections → no active OR connections
3. Interpretor: GETINFO status/bootstrap-phase
   - Shows exactly where it is stuck
4. Solutions:
   - Try a different bridge
   - Change pluggable transport (obfs4 → meek → Snowflake)
   - Verify that obfs4proxy is installed
```

### Scenario 4: Anomalous bandwidth after NEWNYM

**Symptom**: after NEWNYM, bandwidth drops and does not recover.

```
1. Bandwidth → compare before/after NEWNYM
2. Connections → verify the new relays in the circuit
3. If a relay has very low bandwidth in the consensus:
   - The circuit was built with a slow relay
   - NEWNYM again to attempt a better circuit
4. If bandwidth stays low after multiple NEWNYMs:
   - Check the guard (it might be the fixed bottleneck)
   - Check the local network (speed test without Tor)
```

### Scenario 5: Connection lost after resume from suspend

**Symptom**: after waking the laptop, Tor does not reconnect.

```
1. Log → search for "connection refused" or "timeout"
2. Bootstrap → may have gone back to 0%
3. Quick solution in the Interpretor:
   SIGNAL RELOAD    → reload config and reconnect
4. If that does not work:
   - Check network (ping router)
   - sudo systemctl restart tor@default.service
5. Nyx reconnects automatically to the ControlPort after restart
```

---

## Nyx vs alternatives

### arm (predecessor)

Nyx is the modern rewrite of `arm` (anonymizing relay monitor):

| Feature | arm | Nyx |
|---------|-----|-----|
| Python | 2.x | 3.x |
| Stem version | 1.x | 1.8+ |
| Maintenance | Abandoned | Active |
| UI | Basic curses | Improved curses |
| Interpretor | No | Yes |
| Performance | Slow with many relays | Optimized |

### Stem CLI scripts

For programmatic monitoring, Stem offers more flexibility:

| Scenario | Nyx | Stem script |
|----------|-----|-------------|
| Interactive monitoring | Excellent | Not suitable |
| Automatic logging | Limited | Excellent |
| Alerts/notifications | No | Yes (with code) |
| Historical graphs | Session only | Save to file/DB |
| CI/CD integration | No | Yes |

### Grafana + Prometheus

For relay operators who need 24/7 monitoring:

```
Tor daemon → ControlPort → Prometheus exporter → Grafana dashboard
```

Advantages: unlimited history, alerts, graphical dashboards, multi-instance.
Disadvantage: complex setup, overkill for a single client.

---

## Scripting with Stem as an alternative

When Nyx is not enough, Stem enables programmatic monitoring:

### Bandwidth monitor with file logging

```python
#!/usr/bin/env python3
"""Tor bandwidth monitor with file logging."""

import time
from datetime import datetime
from stem.control import Controller

LOG_FILE = "/var/log/tor-bandwidth.log"

def main():
    with Controller.from_port(port=9051) as ctrl:
        ctrl.authenticate()
        
        print("Monitoring bandwidth... (Ctrl+C to exit)")
        
        while True:
            read = int(ctrl.get_info("traffic/read"))
            written = int(ctrl.get_info("traffic/written"))
            
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            line = f"{timestamp} | Read: {read:>12} bytes | Written: {written:>12} bytes"
            
            print(line)
            with open(LOG_FILE, "a") as f:
                f.write(line + "\n")
            
            time.sleep(5)

if __name__ == "__main__":
    main()
```

### Circuit monitor with alerts

```python
#!/usr/bin/env python3
"""Alert when the guard changes or circuit count is anomalous."""

from stem.control import Controller
from stem import CircStatus
import functools

def circ_event(controller, event):
    if event.status == CircStatus.BUILT:
        path = [entry[1] for entry in event.path]
        guard = path[0] if path else "unknown"
        print(f"[BUILT] Circuit #{event.id}: {' → '.join(path)}")
    elif event.status == CircStatus.FAILED:
        print(f"[FAIL]  Circuit #{event.id}: {event.reason}")

def main():
    with Controller.from_port(port=9051) as ctrl:
        ctrl.authenticate()
        
        listener = functools.partial(circ_event, ctrl)
        ctrl.add_event_listener(listener, "CIRC")
        
        print("Monitoring circuits... (Ctrl+C to exit)")
        try:
            import time
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            pass

if __name__ == "__main__":
    main()
```

---

## Integration with other tools

### Nyx + journalctl (correlated logs)

```bash
# In one terminal: nyx for live monitoring
nyx

# In another terminal: systemd logs for extra details
sudo journalctl -u tor@default.service -f

# The two logs are complementary:
# - Nyx shows ControlPort events (circuits, streams)
# - journalctl shows system logs (crashes, permissions, resources)
```

### Nyx + tcpdump (traffic verification)

```bash
# Terminal 1: nyx to see circuits and connections
nyx

# Terminal 2: tcpdump to verify no leaks
sudo tcpdump -i eth0 -n 'not port 9001 and not port 443 and not port 9050'

# If tcpdump shows non-Tor traffic → there is a leak
```

### Nyx + ss (port verification)

```bash
# Before starting nyx, verify that ports are listening
ss -tlnp | grep tor
# LISTEN  0  4096  127.0.0.1:9050  *  users:(("tor",pid=1234,fd=6))
# LISTEN  0  4096  127.0.0.1:9051  *  users:(("tor",pid=1234,fd=7))
```

---

## In my experience

Nyx is the tool I open most often after starting Tor. I use it daily
on my Kali setup for:

**After NEWNYM**: it is the most immediate way to visually verify that the circuit
has changed. On the Connections screen I see old circuits gradually closing
and new ones being built. I can immediately verify the new exit node and its country.

**Debugging slow connections**: it has happened to me multiple times that browsing via
Tor was unusually slow. Opening Nyx and checking the guard, I discovered
it had very low bandwidth in the consensus (~500 KB/s). A NEWNYM does not help
because the guard is persistent - in that case I had to wait for natural
rotation.

**After configuration changes**: when I modify the torrc (adding bridges, changing
ports, modifying isolation), after the reload I verify in Nyx that everything is connected
correctly. The Configuration screen confirms that directives were picked up, and the
Connections screen shows the new connections.

**Slow bootstrap with bridges**: my ISP (Comeser, Parma) does not block Tor
directly, but with obfs4 bridges the bootstrap is slower. In Nyx the log
shows exactly where it stalls and for how long - typically at 10%
("Finishing handshake with a relay") when the bridge is overloaded.

Installation is trivial (`sudo apt install nyx`) and requires no configuration
if the ControlPort is active with CookieAuthentication and the user is in the
`debian-tor` group. I recommend it as the first tool to install after Tor itself.

---

## See also

- [Circuit Control and NEWNYM](controllo-circuiti-e-newnym.md) - ControlPort and Stem scripting
- [Relay Monitoring and Metrics](../03-nodi-e-rete/relay-monitoring-e-metriche.md) - Relay monitoring with Prometheus
- [Service Management](../02-installazione-e-configurazione/gestione-del-servizio.md) - systemd, logs, debug
- [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) - Viewing guards in Nyx
- [torrc - Complete Guide](../02-installazione-e-configurazione/torrc-guida-completa.md) - ControlPort configuration
