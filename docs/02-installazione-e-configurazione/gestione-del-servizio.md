# Gestione del Servizio Tor — systemd, Debug e Operazioni

Questo documento copre la gestione operativa del daemon Tor su sistemi Debian/Kali:
i comandi systemd, la lettura dei log, il debug dei problemi, le operazioni di
manutenzione, e le procedure per gestire situazioni anomale.

Include troubleshooting basato sulla mia esperienza reale con problemi di bootstrap,
bridge, permessi e configurazione.

---

## systemd e Tor — Come funziona

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
- `User=debian-tor` — il daemon gira come utente non privilegiato
- `Type=notify` — systemd usa `sd_notify` per sapere quando Tor è pronto
- `ExecStart=/usr/bin/tor ...` — il comando di avvio con i parametri
- `ExecReload=/bin/kill -HUP $MAINPID` — reload invia SIGHUP

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

### Problema 3: "Clock skew" — Orologio fuori sincro

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

## Segnali del processo Tor

Oltre ai comandi systemd, Tor risponde a segnali Unix:

| Segnale | Effetto | Equivalente systemd |
|---------|---------|-------------------|
| SIGHUP | Ricarica torrc, mantiene circuiti | `systemctl reload` |
| SIGINT | Shutdown pulito (attende circuiti) | `systemctl stop` |
| SIGTERM | Shutdown pulito | `systemctl stop` |
| SIGUSR1 | Log statistiche correnti | (nessuno) |
| SIGUSR2 | Passa a log level debug | (nessuno) |

### SIGHUP vs restart

`SIGHUP` (reload) è preferibile quando:
- Cambi parametri minori (logging, timeout)
- Aggiorni bridge
- Modifichi exit/entry nodes

`restart` è necessario quando:
- Cambi ControlPort o SocksPort
- Cambi DataDirectory
- Aggiungi/rimuovi funzionalità (relay, hidden service)

### Nella mia esperienza

Uso `reload` quando cambio bridge:
```bash
# 1. Modifico il torrc con i nuovi bridge
sudo nano /etc/tor/torrc

# 2. Verifico la configurazione
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config

# 3. Reload (mantiene i circuiti esistenti)
sudo systemctl reload tor@default.service

# 4. Verifico nei log che i nuovi bridge funzionino
sudo journalctl -u tor@default.service -f
```

---

## Monitoraggio della salute di Tor

### Verifiche periodiche

```bash
# 1. Tor è attivo?
systemctl is-active tor@default.service

# 2. Le porte sono in ascolto?
sudo ss -tlnp | grep -E "9050|9051"
sudo ss -ulnp | grep 5353

# 3. Il bootstrap è al 100%?
sudo journalctl -u tor@default.service | grep "Bootstrapped 100%"

# 4. Ci sono errori recenti?
sudo journalctl -u tor@default.service -p err --since "1 hour ago"

# 5. Funziona il routing via Tor?
curl --socks5-hostname 127.0.0.1:9050 -s https://check.torproject.org/api/ip
# Risposta attesa: {"IsTor":true,"IP":"..."}

# 6. NEWNYM funziona?
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
# Risposta attesa: 250 OK
```

### Monitorare le risorse

```bash
# CPU e memoria del processo Tor
ps aux | grep /usr/bin/tor

# Connessioni di rete attive
sudo ss -tnp | grep tor | wc -l

# Spazio disco usato dalla cache
du -sh /var/lib/tor/
```

---

## Procedure di manutenzione

### Pulizia della cache e reset

Se Tor si comporta in modo anomalo (circuiti sempre lenti, bootstrap fallisce
ripetutamente), una pulizia della cache può aiutare:

```bash
# 1. Fermare Tor
sudo systemctl stop tor@default.service

# 2. Pulire la cache (mantiene le chiavi e lo state)
sudo rm -f /var/lib/tor/cached-*

# 3. Riavviare
sudo systemctl start tor@default.service
# Il prossimo bootstrap sarà più lento perché scaricherà tutto da zero
```

### Reset completo (inclusi guard)

**ATTENZIONE**: questo resetta la selezione dei guard. Da fare solo se sospetti che
il guard sia compromesso.

```bash
sudo systemctl stop tor@default.service
sudo rm -f /var/lib/tor/cached-* /var/lib/tor/state
sudo systemctl start tor@default.service
```

### Backup della configurazione

```bash
# Backup del torrc e dei bridge
sudo cp /etc/tor/torrc /etc/tor/torrc.backup.$(date +%Y%m%d)

# Backup dello state (guard selection)
sudo cp /var/lib/tor/state /var/lib/tor/state.backup.$(date +%Y%m%d)
```

---

## Verifica completa post-installazione

Checklist da eseguire dopo ogni installazione o modifica importante:

```bash
# 1. Configurazione valida
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
echo "Config: OK"

# 2. Servizio attivo
sudo systemctl restart tor@default.service
sleep 5
systemctl is-active tor@default.service
echo "Service: OK"

# 3. Porte in ascolto
sudo ss -tlnp | grep 9050 && echo "SocksPort: OK"
sudo ss -tlnp | grep 9051 && echo "ControlPort: OK"
sudo ss -ulnp | grep 5353 && echo "DNSPort: OK"

# 4. Bootstrap completato (attendi fino a 2 minuti)
timeout 120 bash -c 'while ! sudo journalctl -u tor@default.service | grep -q "Bootstrapped 100%"; do sleep 2; done'
echo "Bootstrap: OK"

# 5. Connessione Tor funzionante
IP=$(curl --socks5-hostname 127.0.0.1:9050 -s https://api.ipify.org)
echo "Tor exit IP: $IP"

# 6. ControlPort funzionante
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
RESULT=$(printf "AUTHENTICATE %s\r\nGETINFO version\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051 | head -3)
echo "ControlPort: $RESULT"
```
