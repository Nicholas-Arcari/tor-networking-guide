# Troubleshooting, Struttura dei File e Aggiornamento di Tor

Risoluzione dei problemi comuni di installazione, mappa completa dei file
installati con i relativi permessi, e procedure di aggiornamento sicuro.

Estratto da [Installazione e Verifica](installazione-e-verifica.md).

---

## Indice

- [Troubleshooting dell'installazione](#troubleshooting-dellinstallazione)
- [Struttura dei file di Tor dopo l'installazione](#struttura-dei-file-di-tor-dopo-linstallazione)
- [Aggiornamento di Tor](#aggiornamento-di-tor)

---

## Troubleshooting dell'installazione

### Problema: Tor non parte

```bash
> sudo systemctl status tor@default.service
● tor@default.service - Anonymizing overlay network for TCP
   Active: failed
```

**Cause comuni e soluzioni**:

1. **Permessi errati su DataDirectory**:
   ```bash
   sudo chown -R debian-tor:debian-tor /var/lib/tor
   sudo chmod 700 /var/lib/tor
   ```

2. **Un'altra istanza di Tor è già in esecuzione**:
   ```bash
   # Verificare se c'è un lock file
   ls -la /var/lib/tor/lock
   # Se il processo non esiste più, rimuovere il lock
   sudo rm /var/lib/tor/lock
   ```

3. **Torrc con errori**:
   ```bash
   sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
   ```

4. **Port conflict**:
   ```bash
   # Verificare se la porta 9050 è già in uso
   sudo ss -tlnp | grep 9050
   ```

### Problema: Bootstrap bloccato

```bash
> sudo journalctl -u tor@default.service -f
Bootstrapped 10% (conn): Connecting to a relay
... (rimane qui)
```

**Cause comuni**:

1. **Firewall che blocca le connessioni Tor**:
   - Se sei su una rete restrittiva, devi usare bridge obfs4
   - Verificare: `curl -s https://check.torproject.org` (senza Tor) → se il sito
     è raggiungibile, la rete non blocca Tor completamente

2. **DNS non funzionante**:
   ```bash
   # Verificare che il DNS di sistema funzioni
   nslookup torproject.org
   ```

3. **Bridge non funzionanti**:
   ```bash
   # Nei log vedrai:
   Connection timed out to bridge xxx.xxx.xxx.xxx:port
   ```
   Soluzione: richiedere bridge freschi da `https://bridges.torproject.org/options`

4. **Orologio di sistema errato**:
   ```bash
   # Verificare
   timedatectl
   # Se l'orologio è sbagliato
   sudo timedatectl set-ntp true
   ```

### Problema: proxychains dà "need more proxies"

```
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  timeout
!!! need more proxies !!!
```

Significa che Tor non è in esecuzione o non ha completato il bootstrap:
```bash
sudo systemctl status tor@default.service
sudo systemctl start tor@default.service
```

Nella mia esperienza, questo errore appare quando dimentico di avviare Tor dopo
un riavvio del sistema (se non ho abilitato `systemctl enable`).

---

## Struttura dei file di Tor dopo l'installazione

```
/etc/tor/
├── torrc                        # Configurazione principale (da modificare)
├── torrc.d/                     # Directory per configurazioni modulari
└── torsocks.conf                # Configurazione di torsocks

/usr/bin/
├── tor                          # Daemon Tor
├── obfs4proxy                   # Pluggable transport obfs4
├── proxychains4                 # Wrapper proxy
├── torsocks                     # Wrapper SOCKS (alternativa a proxychains)
└── nyx                          # Monitor TUI

/var/lib/tor/                    # Dati persistenti (cache, chiavi, state)
├── cached-certs
├── cached-microdesc
├── cached-microdesc.new
├── cached-consensus
├── state                        # Guard selection e stato persistente
└── lock                         # Lock file (un processo alla volta)

/var/log/tor/
└── notices.log                  # Log (se configurato nel torrc)

/run/tor/
├── control.authcookie           # Cookie per ControlPort (32 byte)
├── tor.pid                      # PID del processo
└── socks                        # Unix domain socket (se configurato)

/usr/share/tor/
├── geoip                        # Database GeoIP IPv4
└── geoip6                       # Database GeoIP IPv6
```

### Permessi critici

| File/Directory | Owner | Permessi | Note |
|---------------|-------|----------|------|
| `/var/lib/tor/` | debian-tor:debian-tor | 700 | Solo Tor può leggere/scrivere |
| `/run/tor/control.authcookie` | debian-tor:debian-tor | 640 | Leggibile dal gruppo debian-tor |
| `/etc/tor/torrc` | root:root | 644 | Leggibile da tutti, scrivibile da root |
| `/var/log/tor/` | debian-tor:adm | 2750 | setgid per group adm |

---

## Aggiornamento di Tor

### Aggiornamento dai repository

```bash
sudo apt update
sudo apt upgrade tor
```

Dopo l'aggiornamento, Tor viene riavviato automaticamente da systemd (se il servizio
era attivo).

### Verificare dopo l'aggiornamento

```bash
tor --version
sudo systemctl status tor@default.service
sudo journalctl -u tor@default.service -n 10
```

### Considerazioni sulla sicurezza degli aggiornamenti

Aggiornare Tor tempestivamente è importante perché le vulnerabilità vengono scoperte
e patchate regolarmente. Le versioni obsolete possono avere:
- Bug nel protocollo di handshake
- Vulnerabilità nella selezione dei guard
- Problemi di memory safety
- Bypass di isolamento

La politica di sicurezza di Tor: le versioni in "end of life" non ricevono patch.
Verificare sempre la [pagina delle release](https://www.torproject.org/download/tor/) 
per assicurarsi di essere su una versione supportata.

---

## Vedi anche

- [Installazione e Verifica](installazione-e-verifica.md) - Prerequisiti, installazione, verifica
- [Configurazione Iniziale](configurazione-iniziale.md) - Torrc minimo, debian-tor, Firefox
- [Gestione del Servizio](gestione-del-servizio.md) - systemd, log, debug approfondito
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
