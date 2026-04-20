> **Lingua / Language**: Italiano | [English](../en/04-strumenti-operativi/nyx-avanzato.md)

# Nyx Avanzato - Navigazione, Configurazione e Scripting

Shortcut di navigazione, configurazione avanzata di Nyx (.nyx/config),
scenari di debugging, confronto con alternative, e scripting con Stem.

Estratto da [Nyx e Monitoraggio](nyx-e-monitoraggio.md).

---

## Indice

- [Navigazione e shortcut](#navigazione-e-shortcut)
- [Configurazione avanzata di Nyx](#configurazione-avanzata-di-nyx)
- [Scenari di debugging con Nyx](#scenari-di-debugging-con-nyx)
- [Nyx vs alternative](#nyx-vs-alternative)
- [Scripting con Stem come alternativa](#scripting-con-stem-come-alternativa)
- [Integrazione con altri strumenti](#integrazione-con-altri-strumenti)

---

## Navigazione e shortcut

### Shortcut globali

| Tasto | Azione |
|-------|--------|
| ← → | Cambia schermata (1-5) |
| ↑ ↓ | Scorrere nella lista corrente |
| Page Up/Down | Scorrimento rapido |
| Home/End | Inizio/fine lista |
| Enter | Dettagli dell'elemento selezionato |
| p | Pausa/riprendi aggiornamento |
| h | Mostra help |
| q | Esci da Nyx |

### Shortcut per schermata

| Schermata | Tasto | Azione |
|-----------|-------|--------|
| Bandwidth | s | Cambia periodo di aggregazione |
| Bandwidth | b | Toggle download/upload/both |
| Connections | s | Ordina per colonna |
| Connections | u | Filtra per tipo connessione |
| Connections | d | Toggle resolver DNS |
| Configuration | / | Cerca direttiva |
| Configuration | Enter | Modifica valore |
| Log | s | Seleziona livello minimo |
| Log | / | Cerca nei log |
| Log | c | Pulisci log visualizzati |
| Interpretor | Tab | Autocompletamento |
| Interpretor | ↑ | Comando precedente (history) |

---

## Configurazione avanzata di Nyx

### File di configurazione

```bash
# Percorso config
~/.nyx/config
# oppure
~/.nyx/nyxrc
```

### Opzioni configurabili

```ini
# ~/.nyx/config

# Refresh rate (secondi)
redraw_rate 1

# Colore interfaccia
color_override false

# Larghezza massima (0 = auto)
max_line_wrap 0

# Log: livello minimo iniziale
log_filter NOTICE

# Connections: resolver DNS abilitato
resolve_dns true

# Connections: mostra GeoIP
show_locale true

# Bandwidth: periodo iniziale
bandwidth_rate 1

# Interpretor: history file
config_log ~/.nyx/log
```

### Startup flags

```bash
# Modalità blind (no colori, per redirect output)
nyx --blind

# Logging verboso di nyx stesso
nyx --log ~/.nyx/debug.log

# Specificare config custom
nyx --config /path/to/custom/nyxrc
```

---

## Scenari di debugging con Nyx

### Scenario 1: Circuito lento

**Sintomo**: navigazione via Tor molto lenta, timeout frequenti.

```
1. Apri Nyx → Schermata Connections
2. Identifica il Guard → premi Enter per i dettagli
3. Controlla:
   - Bandwidth del guard: se < 1000 KB/s → guard lento
   - Flags: deve avere Fast, Stable, Guard
   - Uptime: guard instabile se uptime basso
4. Schermata Bandwidth: verifica il throughput effettivo
   - Se il grafico mostra < 50 KB/s costante → collo di bottiglia
5. Soluzione: SIGNAL NEWNYM nell'Interpretor per nuovi circuiti
   - Se il problema persiste → il guard è il bottleneck
   - Ultima risorsa: eliminare /var/lib/tor/state per forzare nuovo guard
```

### Scenario 2: Guard che cambia inaspettatamente

**Sintomo**: nella schermata Connections, il Guard IP è diverso dal solito.

```
1. Connections → verifica il nuovo Guard (fingerprint, nickname)
2. Interpretor: GETINFO entry-guards
   - Mostra tutti i guard nella lista con stato
3. Possibili cause:
   - Guard precedente offline (verifica su metrics.torproject.org)
   - Rotazione naturale (~2-3 mesi)
   - Path bias detection ha scartato il guard
4. Verifica /var/lib/tor/state:
   Guard in EntryGuard {nickname} {fingerprint} ... 
```

### Scenario 3: Bridge che non si connette

**Sintomo**: bootstrap bloccato al 10-15%.

```
1. Schermata Log → filtra per WARN:
   - "Could not connect to bridge" → bridge offline o bloccato
   - "Connection refused" → porta bloccata dal firewall/ISP
   - "TLS handshake failed" → DPI sta interferendo
2. Connections → nessuna connessione OR attiva
3. Interpretor: GETINFO status/bootstrap-phase
   - Mostra esattamente dove è bloccato
4. Soluzioni:
   - Provare un bridge diverso
   - Cambiare pluggable transport (obfs4 → meek → Snowflake)
   - Verificare che obfs4proxy sia installato
```

### Scenario 4: Bandwidth anomala dopo NEWNYM

**Sintomo**: dopo NEWNYM, la bandwidth crolla e non si riprende.

```
1. Bandwidth → confronta prima/dopo NEWNYM
2. Connections → verifica i nuovi relay nel circuito
3. Se un relay ha bandwidth molto bassa nel consenso:
   - Il circuito è stato costruito con un relay lento
   - NEWNYM di nuovo per tentare circuito migliore
4. Se la bandwidth resta bassa dopo multipli NEWNYM:
   - Verificare il guard (potrebbe essere il bottleneck fisso)
   - Controllare la rete locale (speed test senza Tor)
```

### Scenario 5: Connessione persa dopo resume da suspend

**Sintomo**: dopo aver risvegliato il laptop, Tor non si riconnette.

```
1. Log → cercare "connection refused" o "timeout"
2. Bootstrap → potrebbe essere tornato a 0%
3. Soluzione rapida nell'Interpretor:
   SIGNAL RELOAD    → ricarica config e riconnetti
4. Se non funziona:
   - Verificare rete (ping router)
   - sudo systemctl restart tor@default.service
5. Nyx si riconnette automaticamente al ControlPort dopo restart
```

---

## Nyx vs alternative

### arm (predecessore)

Nyx è la riscrittura moderna di `arm` (anonymizing relay monitor):

| Caratteristica | arm | Nyx |
|---------------|-----|-----|
| Python | 2.x | 3.x |
| Stem version | 1.x | 1.8+ |
| Manutenzione | Abbandonato | Attivo |
| UI | Basic curses | Curses migliorato |
| Interpretor | No | Sì |
| Performance | Lento su tanti relay | Ottimizzato |

### Stem CLI scripts

Per monitoring programmatico, Stem offre più flessibilità:

| Scenario | Nyx | Stem script |
|----------|-----|-------------|
| Monitoring interattivo | Ottimo | Non adatto |
| Logging automatico | Limitato | Ottimo |
| Alert/notifiche | No | Sì (con codice) |
| Grafici storici | Solo sessione | Salva su file/DB |
| Integrazione CI/CD | No | Sì |

### Grafana + Prometheus

Per relay operator che necessitano monitoring 24/7:

```
Tor daemon → ControlPort → exporter Prometheus → Grafana dashboard
```

Vantaggi: storico illimitato, alert, dashboard grafiche, multi-istanza.
Svantaggio: setup complesso, overkill per un singolo client.

---

## Scripting con Stem come alternativa

Quando Nyx non basta, Stem permette monitoring programmatico:

### Monitor bandwidth con logging su file

```python
#!/usr/bin/env python3
"""Monitor bandwidth Tor con logging su file."""

import time
from datetime import datetime
from stem.control import Controller

LOG_FILE = "/var/log/tor-bandwidth.log"

def main():
    with Controller.from_port(port=9051) as ctrl:
        ctrl.authenticate()
        
        print("Monitoring bandwidth... (Ctrl+C per uscire)")
        
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

### Monitor circuiti con alert

```python
#!/usr/bin/env python3
"""Alert quando il guard cambia o il circuito count è anomalo."""

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
        
        print("Monitoring circuiti... (Ctrl+C per uscire)")
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

## Integrazione con altri strumenti

### Nyx + journalctl (log correlati)

```bash
# In un terminale: nyx per monitoring live
nyx

# In un altro terminale: log systemd per dettagli extra
sudo journalctl -u tor@default.service -f

# I due log sono complementari:
# - Nyx mostra eventi ControlPort (circuiti, stream)
# - journalctl mostra log di sistema (crash, permessi, risorse)
```

### Nyx + tcpdump (verifica traffico)

```bash
# Terminale 1: nyx per vedere circuiti e connessioni
nyx

# Terminale 2: tcpdump per verificare che non ci siano leak
sudo tcpdump -i eth0 -n 'not port 9001 and not port 443 and not port 9050'

# Se tcpdump mostra traffico non-Tor → c'è un leak
```

### Nyx + ss (verifica porte)

```bash
# Prima di avviare nyx, verificare che le porte siano in ascolto
ss -tlnp | grep tor
# LISTEN  0  4096  127.0.0.1:9050  *  users:(("tor",pid=1234,fd=6))
# LISTEN  0  4096  127.0.0.1:9051  *  users:(("tor",pid=1234,fd=7))
```

---

## Nella mia esperienza

Nyx è lo strumento che apro più spesso dopo aver avviato Tor. Lo uso quotidianamente
sul mio setup Kali per:

**Dopo NEWNYM**: è il modo più immediato per verificare visivamente che il circuito
sia cambiato. Nella schermata Connections vedo i vecchi circuiti che si chiudono
gradualmente e i nuovi che vengono costruiti. Posso verificare immediatamente il
nuovo exit node e il suo paese.

**Debugging di connessioni lente**: mi è capitato più volte che la navigazione via
Tor fosse insolitamente lenta. Aprendo Nyx e controllando il guard ho scoperto
che aveva bandwidth molto bassa nel consenso (~500 KB/s). Un NEWNYM non risolve
perché il guard è persistente - in quel caso ho dovuto aspettare la rotazione
naturale.

**Dopo cambio configurazione**: quando modifico il torrc (aggiunta bridge, cambio
porte, modifica isolamento), dopo il reload verifico in Nyx che tutto sia connesso
correttamente. La schermata Configuration conferma che le direttive sono state
recepite, e la schermata Connections mostra le nuove connessioni.

**Bootstrap lento con bridge**: il mio ISP (Comeser, Parma) non blocca Tor
direttamente, ma con i bridge obfs4 il bootstrap è più lento. In Nyx il log
mostra esattamente dove si blocca e per quanto tempo - tipicamente al 10%
("Finishing handshake with a relay") quando il bridge è sovraccarico.

L'installazione è banale (`sudo apt install nyx`) e non richiede configurazione
se il ControlPort è attivo con CookieAuthentication e l'utente è nel gruppo
`debian-tor`. Lo consiglio come primo strumento da installare dopo Tor stesso.

---

## Vedi anche

- [Controllo Circuiti e NEWNYM](controllo-circuiti-e-newnym.md) - ControlPort e Stem scripting
- [Relay Monitoring e Metriche](../03-nodi-e-rete/relay-monitoring-e-metriche.md) - Monitoraggio relay con Prometheus
- [Gestione del Servizio](../02-installazione-e-configurazione/gestione-del-servizio.md) - systemd, log, debug
- [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) - Visualizzare guard in nyx
- [torrc - Guida Completa](../02-installazione-e-configurazione/torrc-guida-completa.md) - Configurazione ControlPort
