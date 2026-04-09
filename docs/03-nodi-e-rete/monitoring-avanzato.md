# Monitoring Avanzato - Prometheus, OONI e Script

Monitoring con Prometheus/Grafana, bandwidth accounting, Relay Search,
OONI per analisi della censura, e script di health check personalizzati.

Estratto da [Relay Monitoring e Metriche](relay-monitoring-e-metriche.md).

---

## Indice

- [Prometheus e Grafana per relay](#prometheus-e-grafana-per-relay)
- [Bandwidth accounting](#bandwidth-accounting)
- [Relay search e Atlas](#relay-search-e-atlas)
- [OONI - Open Observatory of Network Interference](#ooni--open-observatory-of-network-interference)
- [Metriche di rete per analisi della censura](#metriche-di-rete-per-analisi-della-censura)
- [Script di monitoring personalizzati](#script-di-monitoring-personalizzati)

---

## Prometheus e Grafana per relay

### Architettura

```
[Tor daemon] → [ControlPort 9051] → [tor-exporter] → [Prometheus] → [Grafana]
```

### tor-exporter per Prometheus

```python
#!/usr/bin/env python3
"""Esportatore Prometheus per metriche Tor relay."""

from prometheus_client import start_http_server, Gauge
from stem.control import Controller
import time

# Definizione metriche
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
    print("Exporter Prometheus su :9099/metrics")
    
    while True:
        try:
            collect()
        except Exception as e:
            print(f"Errore: {e}")
        time.sleep(15)

if __name__ == "__main__":
    main()
```

### Dashboard Grafana

Query Prometheus utili per la dashboard:

```promql
# Bandwidth rate (bytes/sec)
rate(tor_traffic_read_bytes[5m])
rate(tor_traffic_written_bytes[5m])

# Circuiti attivi
tor_circuits_built

# Uptime
tor_uptime_seconds / 3600  # in ore

# Bandwidth nel consenso
tor_bandwidth_kb
```

---

## Bandwidth accounting

### Configurazione

Se operi un relay con bandwidth limitata:

```ini
# torrc
AccountingMax 500 GBytes
AccountingStart month 1 00:00
# → 500 GB al mese, conteggio dal 1° del mese

# Alternative:
AccountingStart day 00:00       # reset giornaliero
AccountingStart week 1 00:00    # reset settimanale
```

### Come funziona

```
Giorno 1: traffico 0/500 GB → relay attivo
Giorno 15: traffico 300/500 GB → relay attivo, 200 GB rimanenti
Giorno 25: traffico 500/500 GB → relay HIBERNATE
  → Tor chiude i circuiti
  → Smette di accettare nuove connessioni
  → Resta connesso per ricevere nuovi descriptor
Giorno 1 (mese successivo): reset → relay riattivo
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
# (oppure: soft, hard)
```

### Nyx bandwidth accounting

Nella schermata bandwidth di Nyx, se accounting è configurato:
```
Accounting: 322.1 GB / 500.0 GB (64.4%)
Remaining: 177.9 GB read, 201.1 GB written
Reset: January 1, 2025 00:00:00
Status: Awake
```

---

## Relay search e Atlas

### Relay Search

```
metrics.torproject.org/rs.html
```

Permette di cercare relay per:
- Nickname
- Fingerprint
- IP address
- Country
- AS number
- Contact info

### Informazioni per relay

Per ogni relay, Relay Search mostra:

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

L'API pubblica per query programmatiche:

```bash
# Dettagli di un relay per fingerprint
torsocks curl -s "https://onionoo.torproject.org/details?lookup=AABBCCDD1122..." | python3 -m json.tool

# Relay in Italia
torsocks curl -s "https://onionoo.torproject.org/details?country=it&running=true" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'Relay attivi in Italia: {len(data.get(\"relays\", []))}')
for r in data.get('relays', [])[:5]:
    print(f'  {r[\"nickname\"]:20} {r[\"addresses\"][0]:20} BW:{r.get(\"observed_bandwidth\",0)//1024} KB/s')
"
```

### Bandwidth history

```bash
# Bandwidth storica di un relay (ultimi 3 mesi)
torsocks curl -s "https://onionoo.torproject.org/bandwidth?lookup=FINGERPRINT" | python3 -m json.tool
```

---

## OONI - Open Observatory of Network Interference

### Cos'è OONI

OONI (ooni.org) è un progetto open source che misura la censura Internet:
- Quali siti sono bloccati in ogni paese
- Come viene implementata la censura (DNS, HTTP, TLS)
- Se Tor e i bridge funzionano

### OONI e Tor

OONI misura specificamente:
- **Tor reachability**: il daemon Tor è raggiungibile?
- **Tor bridge reachability**: i bridge funzionano?
- **obfs4 reachability**: obfs4 bypassa il DPI?
- **Vanilla Tor**: connessione diretta senza bridge

### Dati OONI per l'Italia

```
explorer.ooni.org → Country: Italy

Risultati tipici:
  - Tor vanilla: Accessible ✓
  - obfs4 bridges: Accessible ✓
  - Web connectivity: 99.8% accessible
  - Blocked sites: lista minima (gambling, copyright)
```

Per il mio ISP (Comeser, Parma): Tor è accessibile direttamente senza bridge.
OONI conferma che in Italia non c'è censura sistematica di Tor.

---

## Metriche di rete per analisi della censura

### Bridge usage per paese

```
metrics.torproject.org/userstats-bridge-country.html

Paesi con alto uso di bridge (censura Tor):
  - Iran: ~80% utenti via bridge
  - China: ~70% utenti via bridge
  - Russia: ~40% utenti via bridge (in crescita)
  - Turkmenistan: ~90% utenti via bridge

Paesi con uso minimo di bridge:
  - Italia: <5% utenti via bridge
  - Germania: <5%
  - USA: <3%
```

### Interpretazione

L'uso di bridge come indicatore di censura:
- Alto uso bridge = ISP/governo bloccano connessioni dirette a Tor
- Basso uso bridge = Tor accessibile direttamente
- Aumento improvviso = nuova policy di censura implementata

---

## Script di monitoring personalizzati

### Health check completo

```bash
#!/bin/bash
# tor-relay-health.sh - Health check per relay Tor

echo "=== Tor Relay Health Check ==="
echo ""

# 1. Servizio
SERVICE_STATUS=$(systemctl is-active tor@default.service 2>/dev/null)
echo "[Service]  $SERVICE_STATUS"

# 2. Bootstrap
BOOTSTRAP=$(sudo journalctl -u tor@default.service --no-pager 2>/dev/null | grep "Bootstrapped" | tail -1)
echo "[Bootstrap] $BOOTSTRAP"

# 3. Metriche via ControlPort
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

# 4. Connessione
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

## Nella mia esperienza

Non opero un relay Tor (non ho la bandwidth o l'infrastruttura per farlo in modo
affidabile), ma utilizzo costantemente le metriche della rete per il mio studio:

**Relay Search**: quando nyx mi mostra un guard con nickname o fingerprint, vado
su metrics.torproject.org/rs.html per verificare le sue caratteristiche - bandwidth,
uptime, flags, paese. Mi è stato utile quando il mio guard era insolitamente lento:
verificando su Relay Search ho scoperto che aveva bandwidth di soli 500 KB/s nel
consenso, molto sotto la media.

**Tor Metrics per l'Italia**: monitoro periodicamente le statistiche degli utenti
Tor italiani. L'Italia ha tipicamente ~60.000-100.000 utenti diretti al giorno,
con picchi durante eventi di cronaca. L'uso di bridge è minimo (<5%), confermando
che il mio ISP (Comeser, Parma) non blocca Tor.

**OONI**: ho consultato OONI explorer per verificare lo stato della censura in
Italia prima di configurare il mio setup. Risultato: nessun blocco di Tor, nessun
bisogno di bridge obbligatori. I bridge li ho configurati comunque per studio e
come backup nel caso la situazione cambi.

---

## Vedi anche

- [Relay Monitoring e Metriche](relay-monitoring-e-metriche.md) - Tor Metrics, metriche relay, ControlPort
- [Nyx e Monitoraggio](../04-strumenti-operativi/nyx-e-monitoraggio.md) - Monitor TUI
- [Gestione del Servizio](../02-installazione-e-configurazione/gestione-del-servizio.md) - systemd, log
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
