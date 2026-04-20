> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/relay-monitoring-e-metriche.md) | English

# Relay Monitoring and Metrics

This document analyzes how to monitor Tor relays, collect performance metrics,
and use the Tor network's observability tools. It covers both monitoring your own
relay and analyzing the Tor network as a whole.

> **See also**: [Nyx and Monitoring](../04-strumenti-operativi/nyx-e-monitoraggio.md)
> for TUI monitoring, [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md)
> for ControlPort, [Consensus and Directory Authorities](../01-fondamenti/consenso-e-directory-authorities.md)
> for the voting process.

---

## Table of Contents

- [Tor Metrics - the network observatory](#tor-metrics--the-network-observatory)
- [Your own relay metrics](#your-own-relay-metrics)
- [Monitoring with ControlPort and Stem](#monitoring-with-controlport-and-stem)
**Deep dives** (dedicated files):
- [Advanced Monitoring](monitoring-avanzato.md) - Prometheus, OONI, Relay Search, scripts

---

## Tor Metrics - the network observatory

### metrics.torproject.org

The Tor Project maintains a public metrics portal:

| Metric | URL | Description |
|--------|-----|-------------|
| Users | metrics.torproject.org/userstats-relay-country.html | Estimated users by country |
| Relays | metrics.torproject.org/networksize.html | Number of active relays |
| Bandwidth | metrics.torproject.org/bandwidth.html | Total network bandwidth |
| Bridges | metrics.torproject.org/userstats-bridge-country.html | Users via bridges |
| Latency | metrics.torproject.org/torperf.html | Circuit performance |

### Available data

- **Direct users by country**: estimated from the number of Directory requests
- **Bridge users by country**: estimated from bridge connections
- **Active relays and bridges**: hourly count
- **Bandwidth relayed**: network total and per relay
- **Performance (Torperf)**: download time for test files via Tor
- **Server descriptors**: historical archive of all published descriptors

### CollecTor

CollecTor is the data collection service:

```
collector.torproject.org
  ├── recent/          → data from the last 72 hours
  │   ├── relay-descriptors/
  │   ├── bridge-descriptors/
  │   ├── exit-lists/
  │   └── torperf/
  └── archive/         → complete historical archive
      ├── relay-descriptors/  → since 2007
      └── ...
```

The data is public and downloadable for analysis:

```bash
# Download the list of current exit nodes
torsocks curl -s https://check.torproject.org/torbulkexitlist > exit-list.txt
wc -l exit-list.txt
# ~1500 active exit node IPs
```

---

## Your own relay metrics

### If you operate a relay

When you operate a Tor relay, you can monitor:

#### Via ControlPort

```python
from stem.control import Controller

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    
    # Total bandwidth
    read = int(ctrl.get_info("traffic/read"))
    written = int(ctrl.get_info("traffic/written"))
    print(f"Read: {read/1024/1024:.1f} MB, Written: {written/1024/1024:.1f} MB")
    
    # Uptime
    uptime = ctrl.get_info("uptime")
    print(f"Uptime: {int(uptime)//3600} hours")
    
    # Accounting
    try:
        accounting = ctrl.get_info("accounting/bytes")
        print(f"Accounting: {accounting}")
    except:
        print("Accounting not configured")
    
    # Status in the consensus
    fingerprint = ctrl.get_info("fingerprint")
    print(f"Fingerprint: {fingerprint}")
    
    # Flags
    ns = ctrl.get_network_status(fingerprint)
    print(f"Flags: {', '.join(ns.flags)}")
    print(f"Bandwidth: {ns.bandwidth} KB/s")
```

#### Via Tor logs

```bash
# Heartbeat (every 6 hours by default)
sudo journalctl -u tor@default.service | grep "Heartbeat"

# Example output:
# Heartbeat: Tor's uptime is 14 days 6:00 hours, with 3 circuits open.
# We've sent 245.12 GB and received 231.45 GB in the last 6 hours.
# Our measured bandwidth is 15000 KB/s.
```

### Relay descriptor

Each relay publishes a descriptor containing:

```
@type server-descriptor 1.0
router MyRelay 198.51.100.42 9001 0 0
platform Tor 0.4.8.10 on Linux
bandwidth 20480 40960 15000
  ↑ average  ↑ burst  ↑ observed (KB/s)
published 2024-12-15 09:00:00
uptime 1209600
contact admin@example.com
ntor-onion-key <base64>
signing-key
-----BEGIN RSA PUBLIC KEY-----
...
-----END RSA PUBLIC KEY-----
```

---

## Monitoring with ControlPort and Stem

### Complete monitor script

```python
#!/usr/bin/env python3
"""tor-relay-monitor.py - Relay monitor with JSON output for integration."""

import json
import time
from datetime import datetime
from stem.control import Controller

def collect_metrics(ctrl):
    """Collects all available metrics."""
    metrics = {
        "timestamp": datetime.now().isoformat(),
        "version": str(ctrl.get_version()),
        "uptime_seconds": int(ctrl.get_info("uptime")),
        "traffic": {
            "read_bytes": int(ctrl.get_info("traffic/read")),
            "written_bytes": int(ctrl.get_info("traffic/written")),
        },
        "circuits": {
            "total": len(ctrl.get_circuits()),
            "built": len([c for c in ctrl.get_circuits() if c.status == "BUILT"]),
        },
    }
    
    # Accounting (if configured)
    try:
        metrics["accounting"] = {
            "bytes": ctrl.get_info("accounting/bytes"),
            "bytes_left": ctrl.get_info("accounting/bytes-left"),
            "hibernating": ctrl.get_info("accounting/hibernating"),
        }
    except:
        metrics["accounting"] = None
    
    # Network status (if relay)
    try:
        fp = ctrl.get_info("fingerprint")
        ns = ctrl.get_network_status(fp)
        metrics["relay"] = {
            "fingerprint": fp,
            "nickname": ns.nickname,
            "flags": list(ns.flags),
            "bandwidth_kb": ns.bandwidth,
            "address": ns.address,
        }
    except:
        metrics["relay"] = None
    
    return metrics

def main():
    with Controller.from_port(port=9051) as ctrl:
        ctrl.authenticate()
        
        while True:
            metrics = collect_metrics(ctrl)
            print(json.dumps(metrics))
            time.sleep(60)  # every minute

if __name__ == "__main__":
    main()
```

### Event-based monitoring

```python
#!/usr/bin/env python3
"""Monitor Tor events in real time."""

import functools
from stem.control import Controller

def handle_event(event_type, event):
    """Generic event handler."""
    timestamp = event.arrived_at.strftime("%H:%M:%S") if hasattr(event, 'arrived_at') else "?"
    
    if event_type == "BW":
        print(f"[{timestamp}] BW: read={event.read}B written={event.written}B")
    elif event_type == "CIRC":
        status = event.status if hasattr(event, 'status') else '?'
        print(f"[{timestamp}] CIRC: #{event.id} {status}")
    elif event_type == "WARN":
        print(f"[{timestamp}] WARN: {event.message}")

def main():
    with Controller.from_port(port=9051) as ctrl:
        ctrl.authenticate()
        
        # Register event handlers
        for event_type in ["BW", "CIRC", "STREAM", "WARN", "ERR"]:
            handler = functools.partial(handle_event, event_type)
            ctrl.add_event_listener(handler, event_type)
        
        print("Monitoring events... (Ctrl+C to exit)")
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

> **Continues in**: [Advanced Monitoring](monitoring-avanzato.md) for Prometheus/Grafana,
> bandwidth accounting, Relay Search, OONI, and health check scripts.

---

## See also

- [Advanced Monitoring](monitoring-avanzato.md) - Prometheus, OONI, Relay Search, scripts
- [Guard Nodes](guard-nodes.md) - Guard selection and monitoring
- [Exit Nodes](exit-nodes.md) - Exit policies, risks, and metrics
- [Consensus and Directory Authorities](../01-fondamenti/consenso-e-directory-authorities.md) - Voting, flags, bandwidth authorities
- [Nyx and Monitoring](../04-strumenti-operativi/nyx-e-monitoraggio.md) - TUI monitor for local relays
- [Real-World Scenarios](scenari-reali.md) - Practical operational cases from a pentester
