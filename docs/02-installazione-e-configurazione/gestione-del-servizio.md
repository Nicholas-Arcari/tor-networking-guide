# Gestione del Servizio Tor - systemd, Debug e Operazioni

Questo documento copre la gestione operativa del daemon Tor su sistemi Debian/Kali:
i comandi systemd, la lettura dei log, il debug dei problemi, le operazioni di
manutenzione, e le procedure per gestire situazioni anomale.

Include troubleshooting basato sulla mia esperienza reale con problemi di bootstrap,
bridge, permessi e configurazione.

---
---

## Indice

- [systemd e Tor - Come funziona](#systemd-e-tor-come-funziona)
- [Log e monitoraggio](#log-e-monitoraggio)
- [Debug dei problemi comuni](#debug-dei-problemi-comuni)
**Approfondimenti** (file dedicati):
- [Manutenzione e Monitoraggio](manutenzione-e-monitoraggio.md) - Segnali, health check, procedure, verifica post-installazione


## systemd e Tor - Come funziona

### L'unità template

Tor su Debian usa un'unità **template** systemd: `tor@.service`. Questo permette
istanze multiple con nomi diversi:

```bash
# Istanza default (quella che usiamo normalmente)
tor@default.service

# Istanze custom (se servissero più processi Tor)
tor@secondary.service
```

L'istanza `default` usa il torrc standard `/etc/tor/torrc`. Le istanze custom
cercherebbero `/etc/tor/instances/<nome>/torrc`.

### File dell'unità systemd

```bash
> systemctl cat tor@default.service
```

L'unità specifica:
- `User=debian-tor` - il daemon gira come utente non privilegiato
- `Type=notify` - systemd usa `sd_notify` per sapere quando Tor è pronto
- `ExecStart=/usr/bin/tor ...` - il comando di avvio con i parametri
- `ExecReload=/bin/kill -HUP $MAINPID` - reload invia SIGHUP

### Comandi operativi quotidiani

```bash
# === Stato ===
sudo systemctl status tor@default.service
# Mostra: active/inactive, PID, ultimi log, uptime

# === Avvio/Stop/Restart ===
sudo systemctl start tor@default.service
sudo systemctl stop tor@default.service
sudo systemctl restart tor@default.service

# === Reload (ricarica torrc senza riavviare) ===
sudo systemctl reload tor@default.service
# Equivale a: kill -HUP $(pidof tor)
# Tor rilegge il torrc, ma mantiene i circuiti esistenti

# === Abilitare/Disabilitare all'avvio ===
sudo systemctl enable tor@default.service    # si avvia al boot
sudo systemctl disable tor@default.service   # non si avvia al boot

# === Verificare se è abilitato ===
sudo systemctl is-enabled tor@default.service
```

### Nella mia esperienza

Non ho abilitato Tor all'avvio (`enable`) perché non sempre voglio che Tor sia
attivo. Preferisco avviarlo manualmente quando ne ho bisogno:

```bash
sudo systemctl start tor@default.service
# ... lavoro con Tor ...
sudo systemctl stop tor@default.service
```

Questo riduce la superficie di attacco quando non uso Tor e evita traffico inutile.

---

## Log e monitoraggio

### Visualizzare i log in tempo reale

```bash
# Via journalctl (raccomandato)
sudo journalctl -u tor@default.service -f

# Via file di log (se configurato nel torrc)
sudo tail -f /var/log/tor/notices.log
```

### Visualizzare gli ultimi N messaggi

```bash
sudo journalctl -u tor@default.service -n 50
```

### Filtrare i log per livello

```bash
# Solo errori
sudo journalctl -u tor@default.service -p err

# Errori e warning
sudo journalctl -u tor@default.service -p warning

# Da una data specifica
sudo journalctl -u tor@default.service --since "2025-01-15 10:00:00"
```

### Log del bootstrap

Il bootstrap è la fase più importante da monitorare. Ecco i messaggi e il loro significato:

```
Bootstrapped   0% (starting): Starting
Bootstrapped   5% (conn): Connecting to a relay
   → Tor sta tentando una connessione TCP al guard/bridge
Bootstrapped  10% (conn_done): Connected to a relay
   → Connessione TCP stabilita
Bootstrapped  14% (handshake): Handshaking with a relay
   → TLS handshake in corso
Bootstrapped  15% (handshake_done): Handshake with a relay done
   → TLS handshake completato con successo
Bootstrapped  20% (onehop_create): Establishing a one-hop circuit
   → Sta creando un circuito a 1 hop per scaricare il consenso
Bootstrapped  25% (requesting_status): Asking for networkstatus consensus
   → Richiedendo il documento di consenso
Bootstrapped  40% (loading_status): Loading networkstatus consensus
   → Scaricando il consenso
Bootstrapped  45% (loading_keys): Loading authority key certs
   → Scaricando i certificati delle Directory Authorities
Bootstrapped  50% (loading_descriptors): Loading relay descriptors
   → Scaricando i microdescriptor dei relay
Bootstrapped  75% (enough_dirinfo): Loaded enough directory info to build circuits
   → Abbastanza descriptor per costruire circuiti (non tutti, ma sufficienti)
Bootstrapped  80% (ap_conn): Connecting to a relay to build circuits
   → Costruendo il primo circuito completo
Bootstrapped  85% (ap_conn_done): Connected to a relay to build circuits
   → Connessione al guard del primo circuito stabilita
Bootstrapped  89% (ap_handshake): Finishing handshake with a relay to build circuits
   → Handshake ntor in corso per il primo circuito
Bootstrapped  90% (ap_handshake_done): Handshake finished with a relay to build circuits
   → Handshake completato
Bootstrapped  95% (circuit_create): Establishing a Tor circuit
   → Estendendo il circuito (guard → middle → exit)
Bootstrapped 100% (done): Done
   → Tor è pronto. SocksPort accetta connessioni.
```

### Nella mia esperienza

Il bootstrap con bridge obfs4 è notevolmente più lento del bootstrap diretto.
Tempi tipici che ho osservato:

| Configurazione | Tempo bootstrap |
|---------------|----------------|
| Connessione diretta (no bridge) | 5-15 secondi |
| Bridge obfs4 (bridge vicino) | 15-30 secondi |
| Bridge obfs4 (bridge lontano/lento) | 30-120 secondi |
| Bridge obfs4 su rete restrittiva | Fino a 3 minuti |

Se il bootstrap si blocca per più di 2-3 minuti, probabilmente il bridge è saturo o
irraggiungibile. Verifico con:
```bash
sudo journalctl -u tor@default.service -f
# Se vedo ripetutamente:
# "Connection timed out to bridge xxx.xxx.xxx.xxx:port"
# → Il bridge non funziona, devo sostituirlo
```

---

## Debug dei problemi comuni

### Problema 1: "Torrc error" al restart

```
[warn] Failed to parse/validate config: ...
```

**Diagnosi**:
```bash
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
```

**Cause comuni**:
- Bridge con formato errato (mancano spazi, cert= troncato)
- Direttiva scritta male (case-sensitive)
- Path inesistente per DataDirectory o Log
- Porta già in uso

### Problema 2: "Permission denied" su DataDirectory

```
[warn] Directory /var/lib/tor cannot be read: Permission denied
```

**Soluzione**:
```bash
sudo chown -R debian-tor:debian-tor /var/lib/tor
sudo chmod 700 /var/lib/tor
```

### Problema 3: "Clock skew" - Orologio fuori sincro

```
[warn] Received a consensus that is X hours in the future
```

**Soluzione**:
```bash
timedatectl                          # Verificare
sudo timedatectl set-ntp true        # Abilitare NTP
sudo systemctl restart systemd-timesyncd
date                                 # Verificare che sia corretto
```

### Problema 4: Bootstrap bloccato con bridge

```
Bootstrapped 10% (conn): Connecting to a relay
... (nessun progresso per 2+ minuti)
```

**Diagnosi step-by-step**:

1. **Verificare che obfs4proxy esista e sia eseguibile**:
   ```bash
   ls -la /usr/bin/obfs4proxy
   # Se manca: sudo apt install obfs4proxy
   ```

2. **Verificare il formato dei bridge nel torrc**:
   ```bash
   grep "^Bridge" /etc/tor/torrc
   # Deve essere esattamente:
   # Bridge obfs4 IP:PORT FINGERPRINT cert=CERT iat-mode=N
   ```

3. **Testare la raggiungibilità del bridge**:
   ```bash
   # Il bridge deve essere raggiungibile sulla porta specificata
   nc -zv <IP_BRIDGE> <PORTA> -w 5
   # Se timeout → il bridge è irraggiungibile dalla tua rete
   ```

4. **Provare bridge diversi**:
   Richiedere nuovi bridge da `https://bridges.torproject.org/options`

5. **Provare senza bridge** (temporaneamente):
   ```bash
   # Commentare le righe bridge nel torrc
   # UseBridges 1 → #UseBridges 1
   sudo systemctl restart tor@default.service
   ```
   Se funziona senza bridge, il problema è nei bridge configurati.

### Problema 5: Tor parte ma proxychains non funziona

```
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  timeout
```

**Diagnosi**:

1. **Verificare che la porta 9050 sia in ascolto**:
   ```bash
   sudo ss -tlnp | grep 9050
   # Deve mostrare: LISTEN ... 127.0.0.1:9050 ... tor
   ```

2. **Verificare il bootstrap**:
   ```bash
   sudo journalctl -u tor@default.service | grep Bootstrapped
   # Deve mostrare "Bootstrapped 100%"
   ```

3. **Testare senza proxychains**:
   ```bash
   curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
   ```

4. **Verificare il proxychains.conf**:
   ```bash
   grep -v "^#" /etc/proxychains4.conf | grep -v "^$"
   # Deve contenere:
   # dynamic_chain
   # proxy_dns
   # socks5 127.0.0.1 9050
   ```

---

> **Continua in**: [Manutenzione e Monitoraggio](manutenzione-e-monitoraggio.md) per i segnali
> Unix, il monitoraggio della salute, le procedure di manutenzione e la verifica post-installazione.

---

## Vedi anche

- [Manutenzione e Monitoraggio](manutenzione-e-monitoraggio.md) - Segnali, health check, manutenzione
- [Installazione e Verifica](installazione-e-verifica.md) - Setup iniziale
- [torrc - Guida Completa](torrc-guida-completa.md) - Configurazione da ricaricare
- [Nyx e Monitoraggio](../04-strumenti-operativi/nyx-e-monitoraggio.md) - Monitor TUI per il servizio
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester

---

## Cheat Sheet - Comandi systemd per Tor

| Comando | Descrizione |
|---------|-------------|
| `sudo systemctl start tor@default.service` | Avvia Tor |
| `sudo systemctl stop tor@default.service` | Ferma Tor |
| `sudo systemctl restart tor@default.service` | Riavvia Tor |
| `sudo systemctl reload tor@default.service` | Ricarica torrc (SIGHUP) |
| `sudo systemctl status tor@default.service` | Stato del servizio |
| `sudo systemctl enable tor@default.service` | Avvio automatico al boot |
| `sudo journalctl -u tor@default.service -f` | Log in tempo reale |
| `sudo journalctl -u tor@default.service \| grep Bootstrap` | Stato bootstrap |
| `sudo kill -HUP $(pidof tor)` | Ricarica torrc (alternativa) |
| `sudo kill -USR1 $(pidof tor)` | Log delle statistiche |
| `nyx` | Monitor TUI (richiede ControlPort) |
