> **Lingua / Language**: Italiano | [English](../en/04-strumenti-operativi/nyx-e-monitoraggio.md)

# Nyx - Monitoraggio in Tempo Reale di Tor

Nyx (precedentemente chiamato `arm`) è un monitor TUI (Text User Interface) per il
daemon Tor. Permette di visualizzare in tempo reale circuiti, bandwidth, connessioni,
log e configurazione. È lo strumento essenziale per capire cosa sta facendo Tor
in un dato momento.

> **Vedi anche**: [Controllo Circuiti e NEWNYM](./controllo-circuiti-e-newnym.md) per
> il protocollo ControlPort, [Gestione del Servizio](../02-installazione-e-configurazione/gestione-del-servizio.md)
> per bootstrap e log, [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) per la selezione guard.

---

## Indice

- [Installazione e dipendenze](#installazione-e-dipendenze)
- [Architettura interna di Nyx](#architettura-interna-di-nyx)
- [Schermata 1: Bandwidth Graph](#schermata-1-bandwidth-graph)
- [Schermata 2: Connections](#schermata-2-connections)
- [Schermata 3: Configuration](#schermata-3-configuration)
- [Schermata 4: Log](#schermata-4-log)
- [Schermata 5: Interpretor](#schermata-5-interpretor)
**Approfondimenti** (file dedicati):
- [Nyx Avanzato](nyx-avanzato.md) - Navigazione, configurazione, debugging, Stem, integrazione

---

## Installazione e dipendenze

### Installazione su Kali/Debian

```bash
# Metodo 1: apt (raccomandato su Kali)
sudo apt install nyx

# Metodo 2: pip (versione più recente)
pip3 install nyx

# Verifica versione
nyx --version
# nyx version 2.1.0 (stem 1.8.1)
```

### Dipendenze

Nyx dipende da:
- **Stem** (libreria Python per il ControlPort Tor) - installato automaticamente
- **Python 3.5+** - presente di default su Kali
- **curses** - libreria TUI, parte della standard library Python

### Requisiti Tor

Nyx richiede accesso al ControlPort:

```ini
# torrc - necessario per nyx
ControlPort 9051
CookieAuthentication 1
```

L'utente deve essere nel gruppo `debian-tor` per leggere il cookie:

```bash
# Verificare appartenenza al gruppo
groups | grep debian-tor

# Se non presente:
sudo usermod -aG debian-tor $USER
# → logout e login necessari
```

### Avvio

```bash
# Connessione default (127.0.0.1:9051)
nyx

# Specificare porta
nyx -i 127.0.0.1:9051

# Specificare socket file
nyx -s /run/tor/control

# Con password (se non usi CookieAuthentication)
nyx -i 127.0.0.1:9051 -p "la_tua_password"
```

---

## Architettura interna di Nyx

### Come Nyx comunica con Tor

Nyx usa la libreria Stem per connettersi al ControlPort di Tor. Il flusso:

```
[Nyx TUI] → [Stem library] → [ControlPort TCP 9051] → [Tor daemon]
                                    ↓
                         Protocollo testuale:
                         AUTHENTICATE <cookie>
                         SETEVENTS BW CIRC STREAM ORCONN
                         GETINFO circuit-status
                         GETCONF SocksPort
```

### Eventi sottoscritti

All'avvio, Nyx si registra per ricevere eventi in tempo reale:

| Evento | Descrizione | Uso in Nyx |
|--------|-------------|------------|
| `BW` | Bandwidth read/written (ogni secondo) | Grafico bandwidth |
| `CIRC` | Cambiamenti stato circuiti | Lista circuiti |
| `STREAM` | Cambiamenti stato stream | Connessioni attive |
| `ORCONN` | Connessioni OR (relay-to-relay) | Lista connessioni |
| `NEWDESC` | Nuovi descriptor disponibili | Aggiornamento info relay |
| `NOTICE` / `WARN` / `ERR` | Log events | Schermata log |

### Comandi GETINFO usati

```
GETINFO version                    → Versione Tor
GETINFO circuit-status             → Tutti i circuiti
GETINFO stream-status              → Tutti gli stream
GETINFO orconn-status              → Connessioni OR
GETINFO ns/all                     → Network status (consenso)
GETINFO traffic/read               → Byte letti totali
GETINFO traffic/written            → Byte scritti totali
GETINFO process/pid                → PID del daemon Tor
GETINFO process/descriptor-limit   → Limite file descriptor
```

### Refresh rate

Nyx aggiorna l'interfaccia:
- **Bandwidth**: ogni 1 secondo (basato su evento `BW`)
- **Connessioni**: ogni 5 secondi (polling `GETINFO orconn-status`)
- **Circuiti**: event-driven (aggiornato ad ogni evento `CIRC`)
- **Log**: event-driven (aggiornato ad ogni evento di log)

---

## Schermata 1: Bandwidth Graph

La prima schermata mostra un grafico ASCII della bandwidth in tempo reale:

```
┌──────────────────────────────────────────────────────────────┐
│ Tor Bandwidth (since 2024-12-15 09:23:41):                   │
│                                                              │
│ 250 KB/s ┤                                                   │
│ 200 KB/s ┤        ▄▆                                         │
│ 150 KB/s ┤   ▂▄▆▇██▇▅                                       │
│ 100 KB/s ┤ ▄████████████▇▅▃                                  │
│  50 KB/s ┤████████████████████▇▅▃▂▁     ▂▃▅                  │
│   0 KB/s ┤██████████████████████████▇▅▃▂█████▇▅▃▂▁           │
│          └──────────────────────────────────────────          │
│                                                              │
│ Download: 127 KB/s   Upload: 43 KB/s                         │
│ Total: 1.2 GB down, 456 MB up (this session)                 │
│ Avg: 89 KB/s down, 31 KB/s up                                │
└──────────────────────────────────────────────────────────────┘
```

### Statistiche visualizzate

| Statistica | Descrizione |
|------------|-------------|
| Current | Bandwidth istantanea (ultimo secondo) |
| Average | Media dall'avvio della sessione |
| Total | Byte totali trasferiti |
| Min/Max | Picchi minimi e massimi |

### Periodi di aggregazione

Premendo `s` nella schermata bandwidth:

| Periodo | Granularità | Utilizzo |
|---------|-------------|----------|
| 1 secondo | Real-time | Monitoring live |
| 5 secondi | Media mobile | Pattern di traffico |
| 30 secondi | Trend breve | Stabilità connessione |
| 10 minuti | Trend medio | Performance circuito |
| 1 ora | Trend lungo | Sessione completa |
| 1 giorno | Overview | Relay operators |

### Accounting (per relay operator)

Se operi un relay con bandwidth accounting:

```ini
# torrc relay
AccountingMax 50 GBytes
AccountingStart month 1 00:00
```

Nyx mostra nella bandwidth screen:
- Quota usata / quota totale
- Tempo rimanente nel periodo
- Stato hibernate (se raggiunta la quota)

---

## Schermata 2: Connections

Mostra tutte le connessioni TCP attive del daemon Tor:

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Connections (ctrl+l: resolve, s: sort, enter: details)                   │
│                                                                          │
│ Type    Address               Fingerprint     Nickname      Time  Circ   │
│ ──────────────────────────────────────────────────────────────────────    │
│ Guard   198.51.100.42:9001    AABB...CC01     MyGuardNode   3h   5,7,12 │
│ Middle  203.0.113.88:443      EEFF...GG02     FastMiddle    45m  5      │
│ Middle  192.0.2.77:9001       1122...3344     TorRelay99    12m  7      │
│ Exit    45.33.32.156:443      5566...7788     ExitDE        45m  5      │
│ Exit    104.244.76.13:443     99AA...BB01     ExitFR        12m  7      │
│ Dir     128.31.0.34:9131      CC00...DD02     moria1        2h   -      │
│ Control 127.0.0.1:9051        -               -             3h   -      │
│ Socks   127.0.0.1:45678       -               -             2m   5      │
│                                                                          │
│ 8 connections (3 relays, 2 exits, 1 directory, 1 control, 1 client)      │
└──────────────────────────────────────────────────────────────────────────┘
```

### Colonne disponibili

| Colonna | Descrizione |
|---------|-------------|
| Type | Guard, Middle, Exit, Directory, Control, Socks, Bridge |
| Address | IP:porta del relay remoto |
| Fingerprint | Hash SHA-1 della chiave identity (troncato) |
| Nickname | Nome scelto dall'operatore del relay |
| Time | Durata della connessione |
| Circuit | ID dei circuiti che usano questa connessione |

### Dettagli per connessione (Enter)

Premendo Enter su una connessione:

```
Connection Details:
  Address:     198.51.100.42:9001
  Fingerprint: AABBCCDD11223344556677889900AABBCCDD1122
  Nickname:    MyGuardNode
  Type:        Guard
  
  Country:     Germany (DE)
  AS:          AS24940 (Hetzner Online GmbH)
  Platform:    Tor 0.4.8.10 on Linux
  
  Flags:       Fast, Guard, HSDir, Running, Stable, V2Dir, Valid
  Bandwidth:   45000 KB/s (advertised), 38000 KB/s (measured)
  Uptime:      45 days, 12 hours
  
  Circuits using this connection: 5, 7, 12
```

### GeoIP e risoluzione

Nyx usa il database GeoIP di Tor per mostrare:
- Paese del relay (codice ISO)
- ASN (Autonomous System Number)
- Organizzazione (ISP/hosting provider)

```bash
# Il database GeoIP di Tor:
/usr/share/tor/geoip
/usr/share/tor/geoip6
```

### Filtri e ordinamento

| Shortcut | Azione |
|----------|--------|
| `s` | Ordina per colonna (type, address, fingerprint, bandwidth, country) |
| `u` | Filtra per tipo (relay, exit, directory, control) |
| `/` | Cerca per nickname o fingerprint |

---

## Schermata 3: Configuration

Mostra tutte le direttive del torrc con i valori correnti:

```
┌──────────────────────────────────────────────────────────────┐
│ Configuration (enter: edit, s: sort, /: search)               │
│                                                               │
│ Directive              Value              Type     Is Set     │
│ ──────────────────────────────────────────────────────────    │
│ SocksPort              9050               Port     Yes        │
│ DNSPort                5353               Port     Yes        │
│ ControlPort            9051               Port     Yes        │
│ CookieAuthentication   1                  Boolean  Yes        │
│ ClientUseIPv6          0                  Boolean  Yes        │
│ UseBridges             1                  Boolean  Yes        │
│ ConnectionPadding      1                  Boolean  Default    │
│ CircuitBuildTimeout    60                 Interval Default    │
│ MaxCircuitDirtiness    600                Interval Default    │
│ NumEntryGuards         1                  Integer  Default    │
│ ...                                                           │
└──────────────────────────────────────────────────────────────┘
```

### Informazioni per ogni direttiva

- **Directive**: nome della direttiva torrc
- **Value**: valore corrente (runtime)
- **Type**: tipo di dato (Port, Boolean, Interval, String, etc.)
- **Is Set**: se è esplicitamente nel torrc o usa il default

### Modifica runtime

Nyx permette di modificare alcune direttive senza restart via `SETCONF`:

```
# Esempio: cambiare MaxCircuitDirtiness a runtime
SETCONF MaxCircuitDirtiness=300
```

**Attenzione**: non tutte le direttive sono modificabili a runtime. Quelle che
richiedono restart (come `SocksPort`, `ControlPort`) non possono essere cambiate.

---

## Schermata 4: Log

Mostra i log di Tor in tempo reale con filtri:

```
┌──────────────────────────────────────────────────────────────────┐
│ Log (filter: NOTICE+, s: select level, /: search, c: clear)      │
│                                                                   │
│ 09:23:41 [NOTICE] Bootstrapped 100% (done): Done                 │
│ 09:24:02 [NOTICE] New control connection opened from 127.0.0.1   │
│ 09:25:15 [NOTICE] Tried for 120 seconds to get a connection to   │
│          [scrubbed]:443. Giving up. (waiting for circuit)         │
│ 09:26:01 [WARN] Problem bootstrapping. Stuck at 10% (Handshaking │
│          with a]relay): TIMEOUT. (1 attempts so far.)             │
│ 09:26:45 [NOTICE] NEWNYM command received. Closing circuits.      │
│ 09:26:46 [NOTICE] New circuit built successfully.                 │
│ 09:27:12 [NOTICE] Heartbeat: Tor's uptime is 3:45 hours.         │
│          Tor has successfully opened 1 circuit. In the last hour  │
│          we relayed 0 cells and 0 connections.                    │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Livelli di log

| Livello | Colore in Nyx | Contenuto tipico |
|---------|---------------|------------------|
| `ERR` | Rosso | Errori critici, impossibile operare |
| `WARN` | Giallo | Bootstrap fallito, timeout, problemi rete |
| `NOTICE` | Bianco | Bootstrap, NEWNYM, heartbeat, nuovi circuiti |
| `INFO` | Ciano | Dettagli operativi, selezione relay, circuit build |
| `DEBUG` | Grigio | Ogni singola operazione (molto verboso) |

### Filtri log

```
Shortcut 's' → seleziona livello minimo:
  ERR      → solo errori critici
  WARN     → warning + errori
  NOTICE   → notice + warning + errori (default)
  INFO     → molto dettagliato
  DEBUG    → estremamente verboso
```

### Ricerca nei log

`/` per cercare con regex nei log. Utile per:
- Cercare errori di bootstrap: `/bootstrap`
- Trovare problemi di circuito: `/circuit.*failed`
- Verificare NEWNYM: `/NEWNYM`

### Log durante bootstrap

Il log è fondamentale per diagnosticare problemi di avvio:

```
[NOTICE] Bootstrapped 0% (starting): Starting
[NOTICE] Bootstrapped 5% (conn_dir): Connecting to a directory server
[NOTICE] Bootstrapped 10% (handshake_dir): Finishing handshake with directory server
[NOTICE] Bootstrapped 15% (onehop_create): Establishing an encrypted directory connection
[NOTICE] Bootstrapped 20% (requesting_status): Asking for networkstatus consensus
[NOTICE] Bootstrapped 25% (loading_status): Loading networkstatus consensus
[NOTICE] Bootstrapped 40% (loading_keys): Loading authority key certs
[NOTICE] Bootstrapped 45% (requesting_descriptors): Asking for relay descriptors
[NOTICE] Bootstrapped 50% (loading_descriptors): Loading relay descriptors
[NOTICE] Bootstrapped 80% (conn_or): Connecting to the Tor network
[NOTICE] Bootstrapped 85% (handshake_or): Finishing handshake with first hop
[NOTICE] Bootstrapped 90% (circuit_create): Establishing a Tor circuit
[NOTICE] Bootstrapped 100% (done): Done
```

Se il bootstrap si blocca a un punto specifico, il log in Nyx mostra esattamente dove.

---

## Schermata 5: Interpretor

La REPL integrata per comandi ControlPort diretti. Accessibile premendo `→` fino
alla quinta schermata:

```
┌──────────────────────────────────────────────────────────────┐
│ Interpretor (enter command, tab: autocomplete)                │
│                                                               │
│ >>> GETINFO version                                           │
│ 250-version=0.4.8.10                                          │
│ 250 OK                                                        │
│                                                               │
│ >>> GETINFO circuit-status                                    │
│ 250+circuit-status=                                           │
│ 5 BUILT $AABB...01~Guard,$EEFF...02~Middle,$5566...03~Exit   │
│    PURPOSE=GENERAL TIME_CREATED=2024-12-15T09:25:01           │
│ 7 BUILT $AABB...01~Guard,$1122...04~Middle,$99AA...05~Exit   │
│    PURPOSE=GENERAL TIME_CREATED=2024-12-15T09:26:45           │
│ 250 OK                                                        │
│                                                               │
│ >>> SIGNAL NEWNYM                                             │
│ 250 OK                                                        │
│                                                               │
│ >>> _                                                          │
└──────────────────────────────────────────────────────────────┘
```

### Comandi utili nell'interpretor

```
# Informazioni sistema
GETINFO version
GETINFO process/pid
GETINFO traffic/read
GETINFO traffic/written

# Circuiti e stream
GETINFO circuit-status
GETINFO stream-status
GETINFO orconn-status

# Network status
GETINFO ns/all                    # tutti i relay nel consenso
GETINFO ns/name/MyRelay           # info su un relay specifico
GETINFO ns/id/AABBCCDD...         # info per fingerprint

# Segnali
SIGNAL NEWNYM                     # nuova identità
SIGNAL RELOAD                     # ricarica torrc
SIGNAL SHUTDOWN                   # shutdown pulito

# Configurazione
GETCONF SocksPort
GETCONF ExitNodes
SETCONF MaxCircuitDirtiness=300

# Risoluzione DNS
RESOLVE example.com
```

L'interpretor ha autocompletamento con Tab, che elenca tutti i comandi e le
opzioni disponibili.

---

---

> **Continua in**: [Nyx Avanzato](nyx-avanzato.md) per navigazione, shortcut,
> configurazione avanzata, scenari di debugging e scripting con Stem.

---

## Vedi anche

- [Nyx Avanzato](nyx-avanzato.md) - Navigazione, configurazione, debugging, Stem
- [Controllo Circuiti e NEWNYM](controllo-circuiti-e-newnym.md) - ControlPort e Stem scripting
- [Relay Monitoring e Metriche](../03-nodi-e-rete/relay-monitoring-e-metriche.md) - Monitoraggio relay
- [Gestione del Servizio](../02-installazione-e-configurazione/gestione-del-servizio.md) - systemd, log, debug
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
