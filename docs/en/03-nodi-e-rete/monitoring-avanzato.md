> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/monitoring-avanzato.md) | English

# Advanced Monitoring - Prometheus, OONI, and Scripts

Monitoring with Prometheus/Grafana, bandwidth accounting, Relay Search,
OONI for censorship analysis, and custom health check scripts.

Extracted from [Relay Monitoring and Metrics](relay-monitoring-e-metriche.md).

---

## Table of Contents

- [Prometheus and Grafana for relays](#prometheus-and-grafana-for-relays)
- [Bandwidth accounting](#bandwidth-accounting)
- [Relay Search and Atlas](#relay-search-and-atlas)
- [OONI - Open Observatory of Network Interference](#ooni--open-observatory-of-network-interference)
- [Network metrics for censorship analysis](#network-metrics-for-censorship-analysis)
- [Custom monitoring scripts](#custom-monitoring-scripts)

---

## Prometheus and Grafana for relays

### Architecture

```
[Tor daemon] → [ControlPort 9051] → [tor-exporter] → [Prometheus] → [Grafana]
```

### tor-exporter for Prometheus

```python
#!/usr/bin/env python3
"""Prometheus exporter for Tor relay metrics."""

from prometheus_client import start_http_server, Gauge
from stem.control import Controller
import time

# Metric definitions
tor_traffic_read = Gauge('tor_traffic_read_bytes', 'Bytes read by Tor')
tor_traffic_written = Gauge('tor_traffic_written_bytes', 'Bytes written by Tor')
tor_circuits_total = Gauge('tor_circuits_total', 'Total circuits')
tor_circuits_built = Gauge('tor_circuits_built', 'Built circuits')
tor_uptime = Gauge('tor_uptime_seconds', 'Tor daemon uptime')
tor_bandwidth = Gauge('tor_bandwidth_kb', 'Measured bandwidth in KB/s')

def collect():
    with Controller.from_port(port=9051) as ctrl:
        ctrl.authenticate()
        
        tor_traffic_read.set(int(ctrl.get_info("traffic/read")))
        tor_traffic_written.set(int(ctrl.get_info("traffic/written")))
        tor_uptime.set(int(ctrl.get_info("uptime")))
        
        circuits = ctrl.get_circuits()
        tor_circuits_total.set(len(circuits))
        tor_circuits_built.set(len([c for c in circuits if c.status == "BUILT"]))
        
        try:
            fp = ctrl.get_info("fingerprint")
            ns = ctrl.get_network_status(fp)
            tor_bandwidth.set(ns.bandwidth)
        except:
            pass

def main():
    start_http_server(9099)  # Prometheus scrape endpoint
    print("Prometheus exporter on :9099/metrics")
    
    while True:
        try:
            collect()
        except Exception as e:
            print(f"Error: {e}")
        time.sleep(15)

if __name__ == "__main__":
    main()
```

### Grafana Dashboard

Useful Prometheus queries for the dashboard:

```promql
# Bandwidth rate (bytes/sec)
rate(tor_traffic_read_bytes[5m])
rate(tor_traffic_written_bytes[5m])

# Active circuits
tor_circuits_built

# Uptime
tor_uptime_seconds / 3600  # in hours

# Bandwidth in the consensus
tor_bandwidth_kb
```

---

## Bandwidth accounting

### Configuration

If you operate a relay with limited bandwidth:

```ini
# torrc
AccountingMax 500 GBytes
AccountingStart month 1 00:00
# → 500 GB per month, counting from the 1st of the month

# Alternatives:
AccountingStart day 00:00       # daily reset
AccountingStart week 1 00:00    # weekly reset
```

### How it works

```
Day 1: traffic 0/500 GB → relay active
Day 15: traffic 300/500 GB → relay active, 200 GB remaining
Day 25: traffic 500/500 GB → relay HIBERNATES
  → Tor closes circuits
  → Stops accepting new connections
  → Stays connected to receive new descriptors
Day 1 (next month): reset → relay reactivated
```

### Monitoring accounting

```bash
# Via ControlPort
echo -e "AUTHENTICATE\r\nGETINFO accounting/bytes\r\nGETINFO accounting/bytes-left\r\nGETINFO accounting/hibernating\r\nQUIT\r\n" | nc 127.0.0.1 9051

# Output:
# 250-accounting/bytes=322122547200 298877452800
#                      ↑ read          ↑ written
# 250-accounting/bytes-left=178877452800 201122547200
#                           ↑ read left   ↑ written left
# 250-accounting/hibernating=awake
# (or: soft, hard)
```

### Nyx bandwidth accounting

In the Nyx bandwidth screen, if accounting is configured:
```
Accounting: 322.1 GB / 500.0 GB (64.4%)
Remaining: 177.9 GB read, 201.1 GB written
Reset: January 1, 2025 00:00:00
Status: Awake
```

---

## Relay Search and Atlas

### Relay Search

```
metrics.torproject.org/rs.html
```

Allows searching for relays by:
- Nickname
- Fingerprint
- IP address
- Country
- AS number
- Contact info

### Information per relay

For each relay, Relay Search shows:

```
Nickname:    MyTorRelay
Fingerprint: AABBCCDD11223344556677889900AABBCCDD1122
IP:          198.51.100.42
OR Port:     9001
Dir Port:    9030
Platform:    Tor 0.4.8.10 on Linux
Uptime:      45 days
Bandwidth:   15000 KB/s (measured)
Flags:       Fast, Guard, HSDir, Running, Stable, V2Dir, Valid
Exit Policy: reject *:*
Contact:     admin@example.com
Country:     DE (Germany)
AS:          AS24940 (Hetzner Online GmbH)
First Seen:  2024-06-15
```

### Onionoo API

The public API for programmatic queries:

```bash
# Details of a relay by fingerprint
torsocks curl -s "https://onionoo.torproject.org/details?lookup=AABBCCDD1122..." | python3 -m json.tool

# Relays in Italy
torsocks curl -s "https://onionoo.torproject.org/details?country=it&running=true" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'Active relays in Italy: {len(data.get(\"relays\", []))}')
for r in data.get('relays', [])[:5]:
    print(f'  {r[\"nickname\"]:20} {r[\"addresses\"][0]:20} BW:{r.get(\"observed_bandwidth\",0)//1024} KB/s')
"
```

### Bandwidth history

```bash
# Historical bandwidth of a relay (last 3 months)
torsocks curl -s "https://onionoo.torproject.org/bandwidth?lookup=FINGERPRINT" | python3 -m json.tool
```

---

## OONI - Open Observatory of Network Interference

### What is OONI

OONI (ooni.org) is an open source project that measures Internet censorship:
- Which sites are blocked in each country
- How censorship is implemented (DNS, HTTP, TLS)
- Whether Tor and bridges work

### OONI and Tor

OONI specifically measures:
- **Tor reachability**: is the Tor daemon reachable?
- **Tor bridge reachability**: do bridges work?
- **obfs4 reachability**: does obfs4 bypass DPI?
- **Vanilla Tor**: direct connection without bridges

### OONI data for Italy

```
explorer.ooni.org → Country: Italy

Typical results:
  - Tor vanilla: Accessible ✓
  - obfs4 bridges: Accessible ✓
  - Web connectivity: 99.8% accessible
  - Blocked sites: minimal list (gambling, copyright)
```

For my ISP (Comeser, Parma): Tor is directly accessible without bridges.
OONI confirms that in Italy there is no systematic censorship of Tor.

---

## Network metrics for censorship analysis

### Bridge usage by country

```
metrics.torproject.org/userstats-bridge-country.html

Countries with high bridge usage (Tor censorship):
  - Iran: ~80% users via bridge
  - China: ~70% users via bridge
  - Russia: ~40% users via bridge (growing)
  - Turkmenistan: ~90% users via bridge

Countries with minimal bridge usage:
  - Italy: <5% users via bridge
  - Germany: <5%
  - USA: <3%
```

### Interpretation

Bridge usage as a censorship indicator:
- High bridge usage = ISP/government blocks direct connections to Tor
- Low bridge usage = Tor is directly accessible
- Sudden increase = new censorship policy implemented

---

## Custom monitoring scripts

### Complete health check

```bash
#!/bin/bash
# tor-relay-health.sh - Health check for Tor relay

echo "=== Tor Relay Health Check ==="
echo ""

# 1. Service
SERVICE_STATUS=$(systemctl is-active tor@default.service 2>/dev/null)
echo "[Service]  $SERVICE_STATUS"

# 2. Bootstrap
BOOTSTRAP=$(sudo journalctl -u tor@default.service --no-pager 2>/dev/null | grep "Bootstrapped" | tail -1)
echo "[Bootstrap] $BOOTSTRAP"

# 3. Metrics via ControlPort
if ss -tlnp 2>/dev/null | grep -q ":9051 "; then
    METRICS=$(echo -e "AUTHENTICATE\r\nGETINFO traffic/read\r\nGETINFO traffic/written\r\nGETINFO uptime\r\nQUIT\r\n" | nc -w 5 127.0.0.1 9051 2>/dev/null)
    
    READ=$(echo "$METRICS" | grep "traffic/read" | awk -F= '{print $2}')
    WRITTEN=$(echo "$METRICS" | grep "traffic/written" | awk -F= '{print $2}')
    UPTIME=$(echo "$METRICS" | grep "uptime" | awk -F= '{print $2}')
    
    if [ -n "$READ" ]; then
        READ_MB=$((READ / 1024 / 1024))
        WRITTEN_MB=$((WRITTEN / 1024 / 1024))
        UPTIME_H=$((UPTIME / 3600))
        echo "[Traffic]  Read: ${READ_MB} MB, Written: ${WRITTEN_MB} MB"
        echo "[Uptime]   ${UPTIME_H} hours"
    fi
fi

# 4. Connection
TOR_IP=$(curl --socks5-hostname 127.0.0.1:9050 -s --max-time 15 https://api.ipify.org 2>/dev/null)
if [ -n "$TOR_IP" ]; then
    echo "[Conn]     OK (exit: $TOR_IP)"
else
    echo "[Conn]     FAIL"
fi

echo ""
echo "=== Done ==="
```

---

## In my experience

I do not operate a Tor relay (I do not have the bandwidth or infrastructure to do so
reliably), but I constantly use network metrics for my study:

**Relay Search**: when nyx shows me a guard with a nickname or fingerprint, I go to
metrics.torproject.org/rs.html to verify its characteristics - bandwidth, uptime,
flags, country. It was useful when my guard was unusually slow: by checking on
Relay Search I discovered it had only 500 KB/s bandwidth in the consensus, well
below the average.

**Tor Metrics for Italy**: I periodically monitor Italian Tor user statistics.
Italy typically has ~60,000-100,000 direct users per day, with spikes during
news events. Bridge usage is minimal (<5%), confirming that my ISP (Comeser, Parma)
does not block Tor.

**OONI**: I consulted the OONI explorer to verify the censorship status in Italy
before configuring my setup. Result: no Tor blocking, no need for mandatory bridges.
I configured bridges anyway for study purposes and as a backup in case the situation
changes.

---

## See also

- [Relay Monitoring and Metrics](relay-monitoring-e-metriche.md) - Tor Metrics, relay metrics, ControlPort
- [Nyx and Monitoring](../04-strumenti-operativi/nyx-e-monitoraggio.md) - TUI monitor
- [Service Management](../02-installazione-e-configurazione/gestione-del-servizio.md) - systemd, logs
- [Real-World Scenarios](scenari-reali.md) - Practical operational cases from a pentester
