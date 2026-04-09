# Lab 02 - Analisi dei Circuiti Tor con Stem e nyx

Esercizio pratico per osservare, analizzare e manipolare i circuiti Tor usando
il ControlPort, la libreria Python Stem, e il monitor nyx.

**Tempo stimato**: 30-40 minuti
**Prerequisiti**: Lab 01 completato, Python 3 con pip
**Difficoltà**: Intermedio

---

## Indice

- [Obiettivi](#obiettivi)
- [Fase 1: Setup Stem](#fase-1-setup-stem)
- [Fase 2: Interrogare i circuiti](#fase-2-interrogare-i-circuiti)
- [Fase 3: NEWNYM e verifica cambio IP](#fase-3-newnym-e-verifica-cambio-ip)
- [Fase 4: Monitorare eventi in tempo reale](#fase-4-monitorare-eventi-in-tempo-reale)
- [Fase 5: nyx - Monitor visuale](#fase-5-nyx--monitor-visuale)
- [Fase 6: Esercizio di analisi](#fase-6-esercizio-di-analisi)
- [Checklist finale](#checklist-finale)

---

## Obiettivi

Al termine di questo lab, saprai:
1. Connetterti al ControlPort con Python Stem
2. Elencare circuiti attivi e relativi relay (Guard, Middle, Exit)
3. Eseguire NEWNYM e verificare il cambio di IP
4. Monitorare eventi Tor in tempo reale
5. Usare nyx per l'analisi visuale dei circuiti

---

## Fase 1: Setup Stem

```bash
# Installare Stem
pip install stem

# Verificare
python3 -c "import stem; print(stem.__version__)"
# Output atteso: 1.8.x o superiore
```

---

## Fase 2: Interrogare i circuiti

Crea il file `circuit-info.py`:

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
# Esegui
python3 circuit-info.py

# Output atteso:
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

**Esercizio**: identifica il tuo Guard persistente. Esegui lo script 3 volte
a distanza di 5 minuti. Il Guard dovrebbe essere lo stesso.

---

## Fase 3: NEWNYM e verifica cambio IP

Crea il file `newnym-verify.py`:

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
pip install PySocks  # se non installato
python3 newnym-verify.py
```

---

## Fase 4: Monitorare eventi in tempo reale

Crea il file `tor-events.py`:

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
# In un terminale: esegui il monitor
python3 tor-events.py

# In un altro terminale: genera traffico
proxychains curl -s https://example.com > /dev/null
proxychains curl -s https://check.torproject.org > /dev/null

# Osserva gli eventi nel primo terminale
```

---

## Fase 5: nyx - Monitor visuale

```bash
# Avviare nyx
nyx

# Schermate (navigare con le frecce):
# 1. Bandwidth graph: grafico in tempo reale
# 2. Connections: connessioni TLS ai relay
# 3. Configuration: configurazione torrc attiva
# 4. Torrc: file torrc con evidenziazione
# 5. Log: log in tempo reale

# Comandi utili in nyx:
# n = NEWNYM (nuova identità)
# r = risolvi hostname
# s = ordina connessioni
# q = esci
```

**Esercizio**: con nyx aperto, genera traffico con `proxychains curl` e osserva
il bandwidth graph e i nuovi circuiti nella schermata Connections.

---

## Fase 6: Esercizio di analisi

1. **Identifica il tuo Guard**: usa `circuit-info.py` e annota il Guard.
   Verifica che sia lo stesso dopo 1 ora.

2. **Conta i circuiti**: quanti circuiti vengono creati in 5 minuti di
   navigazione con `proxychains firefox`?

3. **NEWNYM timing**: quanto tempo passa prima che NEWNYM cambi effettivamente
   l'IP? Testa con `newnym-verify.py`.

4. **Circuiti per destinazione**: visita 3 siti diversi e osserva se Tor
   usa circuiti diversi (con il monitor eventi).

---

## Risoluzione problemi

### Stem non si connette al ControlPort

```bash
# Errore: stem.SocketError: [Errno 111] Connection refused
# → ControlPort non attivo. Verificare:
grep "^ControlPort" /etc/tor/torrc
# Deve mostrare: ControlPort 9051

# Errore: stem.connection.AuthenticationFailure
# → Cookie non leggibile. Verificare:
ls -la /run/tor/control.authcookie
# Il tuo utente deve essere nel gruppo debian-tor
```

### nyx non si avvia o schermo vuoto

```bash
# Errore: "Unable to connect to tor"
# → Stessa causa: ControlPort non attivo o permessi cookie

# Schermo nero/vuoto dopo l'avvio
# → Il terminale è troppo piccolo. nyx richiede almeno 80x24
# → Prova: resize il terminale o usa: stty rows 24 cols 80

# nyx non installato
pip3 install nyx
# oppure
sudo apt install nyx
```

### I circuiti mostrano "Purpose: GENERAL" ma nessun "Purpose: HS_*"

```bash
# Normale se non stai usando onion services in questo momento.
# I circuiti HS_* appaiono solo quando accedi a un indirizzo .onion
# Per provocarli:
curl --socks5-hostname 127.0.0.1:9050 -s http://2gzyxa5ihm7nsber... > /dev/null
# Ora riesegui lo script e vedrai circuiti HS_CLIENT_REND
```

---

## Checklist finale

- [ ] Stem installato e funzionante
- [ ] Script circuit-info.py mostra i circuiti con dettagli relay
- [ ] NEWNYM cambia l'IP di exit
- [ ] Monitor eventi rileva circuiti e stream in tempo reale
- [ ] nyx avviato e navigato tra le 5 schermate
- [ ] Guard persistente identificato e confermato

---

## Vedi anche

- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - Protocollo ControlPort completo
- [Nyx e Monitoraggio](../04-strumenti-operativi/nyx-e-monitoraggio.md) - 5 schermate nyx in dettaglio
- [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) - Perché il Guard è persistente
