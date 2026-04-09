# Segnali, Monitoraggio e Manutenzione di Tor

Segnali Unix del processo Tor, verifiche periodiche della salute del servizio,
procedure di manutenzione (pulizia cache, reset guard), e checklist post-installazione.

Estratto da [Gestione del Servizio](gestione-del-servizio.md).

---

## Indice

- [Segnali del processo Tor](#segnali-del-processo-tor)
- [Monitoraggio della salute di Tor](#monitoraggio-della-salute-di-tor)
- [Procedure di manutenzione](#procedure-di-manutenzione)
- [Verifica completa post-installazione](#verifica-completa-post-installazione)

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

---

## Vedi anche

- [Gestione del Servizio](gestione-del-servizio.md) - systemd, log, debug
- [Troubleshooting e Struttura](troubleshooting-e-struttura.md) - Problemi comuni, struttura file
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - ControlPort e segnali
- [Nyx e Monitoraggio](../04-strumenti-operativi/nyx-e-monitoraggio.md) - Monitor TUI
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
