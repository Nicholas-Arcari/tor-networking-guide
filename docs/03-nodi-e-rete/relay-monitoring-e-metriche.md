# Relay Monitoring e Metriche

Questo documento analizza come monitorare relay Tor, raccogliere metriche di
performance, e utilizzare gli strumenti di osservabilità della rete Tor. Copre
sia il monitoring di un proprio relay che l'analisi della rete Tor nel suo
complesso.

> **Vedi anche**: [Nyx e Monitoraggio](../04-strumenti-operativi/nyx-e-monitoraggio.md)
> per il monitoring TUI, [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md)
> per ControlPort, [Consenso e Directory Authorities](../01-fondamenti/consenso-e-directory-authorities.md)
> per il processo di voto.

---

## Indice

- [Tor Metrics - l'osservatorio della rete](#tor-metrics--losservatorio-della-rete)
- [Metriche del proprio relay](#metriche-del-proprio-relay)
- [Monitoring con ControlPort e Stem](#monitoring-con-controlport-e-stem)
**Approfondimenti** (file dedicati):
- [Monitoring Avanzato](monitoring-avanzato.md) - Prometheus, OONI, Relay Search, script

---

## Tor Metrics - l'osservatorio della rete

### metrics.torproject.org

Il Tor Project mantiene un portale pubblico di metriche:

| Metrica | URL | Descrizione |
|---------|-----|-------------|
| Utenti | metrics.torproject.org/userstats-relay-country.html | Utenti stimati per paese |
| Relay | metrics.torproject.org/networksize.html | Numero relay attivi |
| Bandwidth | metrics.torproject.org/bandwidth.html | Bandwidth totale della rete |
| Bridge | metrics.torproject.org/userstats-bridge-country.html | Utenti via bridge |
| Latenza | metrics.torproject.org/torperf.html | Performance circuiti |

### Dati disponibili

- **Utenti diretti per paese**: stimati dal numero di richieste al Directory
- **Utenti bridge per paese**: stimati dalle connessioni ai bridge
- **Relay e bridge attivi**: conteggio orario
- **Bandwidth relayed**: totale della rete e per relay
- **Performance (Torperf)**: tempo di download file di test via Tor
- **Server descriptor**: archivio storico di tutti i descriptor pubblicati

### CollecTor

CollecTor è il servizio di raccolta dati:

```
collector.torproject.org
  ├── recent/          → dati delle ultime 72 ore
  │   ├── relay-descriptors/
  │   ├── bridge-descriptors/
  │   ├── exit-lists/
  │   └── torperf/
  └── archive/         → archivio storico completo
      ├── relay-descriptors/  → dal 2007
      └── ...
```

I dati sono pubblici e scaricabili per analisi:

```bash
# Scaricare la lista degli exit node correnti
torsocks curl -s https://check.torproject.org/torbulkexitlist > exit-list.txt
wc -l exit-list.txt
# ~1500 IP di exit node attivi
```

---

## Metriche del proprio relay

### Se operi un relay

Quando operi un relay Tor, puoi monitorare:

#### Via ControlPort

```python
from stem.control import Controller

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    
    # Bandwidth totale
    read = int(ctrl.get_info("traffic/read"))
    written = int(ctrl.get_info("traffic/written"))
    print(f"Read: {read/1024/1024:.1f} MB, Written: {written/1024/1024:.1f} MB")
    
    # Uptime
    uptime = ctrl.get_info("uptime")
    print(f"Uptime: {int(uptime)//3600} ore")
    
    # Accounting
    try:
        accounting = ctrl.get_info("accounting/bytes")
        print(f"Accounting: {accounting}")
    except:
        print("Accounting non configurato")
    
    # Stato nel consenso
    fingerprint = ctrl.get_info("fingerprint")
    print(f"Fingerprint: {fingerprint}")
    
    # Flags
    ns = ctrl.get_network_status(fingerprint)
    print(f"Flags: {', '.join(ns.flags)}")
    print(f"Bandwidth: {ns.bandwidth} KB/s")
```

#### Via log di Tor

```bash
# Heartbeat (ogni 6 ore per default)
sudo journalctl -u tor@default.service | grep "Heartbeat"

# Esempio output:
# Heartbeat: Tor's uptime is 14 days 6:00 hours, with 3 circuits open.
# We've sent 245.12 GB and received 231.45 GB in the last 6 hours.
# Our measured bandwidth is 15000 KB/s.
```

### Descriptor del relay

Ogni relay pubblica un descriptor contenente:

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

## Monitoring con ControlPort e Stem

### Script monitor completo

```python
#!/usr/bin/env python3
"""tor-relay-monitor.py - Monitor relay con output JSON per integrazione."""

import json
import time
from datetime import datetime
from stem.control import Controller

def collect_metrics(ctrl):
    """Raccoglie tutte le metriche disponibili."""
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
    
    # Accounting (se configurato)
    try:
        metrics["accounting"] = {
            "bytes": ctrl.get_info("accounting/bytes"),
            "bytes_left": ctrl.get_info("accounting/bytes-left"),
            "hibernating": ctrl.get_info("accounting/hibernating"),
        }
    except:
        metrics["accounting"] = None
    
    # Network status (se relay)
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
            time.sleep(60)  # ogni minuto

if __name__ == "__main__":
    main()
```

### Event-based monitoring

```python
#!/usr/bin/env python3
"""Monitor eventi Tor in tempo reale."""

import functools
from stem.control import Controller

def handle_event(event_type, event):
    """Handler generico per eventi."""
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
        
        # Registra handler per eventi
        for event_type in ["BW", "CIRC", "STREAM", "WARN", "ERR"]:
            handler = functools.partial(handle_event, event_type)
            ctrl.add_event_listener(handler, event_type)
        
        print("Monitoring eventi... (Ctrl+C per uscire)")
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

> **Continua in**: [Monitoring Avanzato](monitoring-avanzato.md) per Prometheus/Grafana,
> bandwidth accounting, Relay Search, OONI e script di health check.

---

## Vedi anche

- [Monitoring Avanzato](monitoring-avanzato.md) - Prometheus, OONI, Relay Search, script
- [Guard Nodes](guard-nodes.md) - Selezione e monitoraggio dei Guard
- [Exit Nodes](exit-nodes.md) - Exit policy, rischi e metriche
- [Consenso e Directory Authorities](../01-fondamenti/consenso-e-directory-authorities.md) - Votazione, flag, bandwidth authorities
- [Nyx e Monitoraggio](../04-strumenti-operativi/nyx-e-monitoraggio.md) - Monitor TUI per relay locali
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
