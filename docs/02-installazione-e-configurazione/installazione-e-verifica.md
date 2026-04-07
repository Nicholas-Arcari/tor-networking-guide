# Installazione e Verifica di Tor — Guida Completa per Debian/Kali

Questo documento copre l'installazione di Tor e dei componenti associati (obfs4proxy,
proxychains, torsocks, nyx) su sistemi Debian-based come Kali Linux. Include la
verifica dell'installazione, il troubleshooting dei problemi più comuni, e la
configurazione iniziale minima per avere un sistema funzionante.

Basato sulla mia esperienza diretta su Kali Linux (Debian-based), dove ho configurato
Tor per uso con proxychains, bridge obfs4 e ControlPort.

---
---

## Indice

- [Prerequisiti di sistema](#prerequisiti-di-sistema)
- [Installazione dei pacchetti](#installazione-dei-pacchetti)
- [Verifica dell'installazione](#verifica-dellinstallazione)
- [Gestione del servizio systemd](#gestione-del-servizio-systemd)
- [Configurazione iniziale minima](#configurazione-iniziale-minima)
- [Configurazione del gruppo debian-tor](#configurazione-del-gruppo-debian-tor)
- [Configurazione del profilo Firefox per Tor](#configurazione-del-profilo-firefox-per-tor)
- [Troubleshooting dell'installazione](#troubleshooting-dellinstallazione)
- [Struttura dei file di Tor dopo l'installazione](#struttura-dei-file-di-tor-dopo-linstallazione)
- [Aggiornamento di Tor](#aggiornamento-di-tor)


## Prerequisiti di sistema

### Sistema operativo

Tor supporta nativamente:
- Debian, Ubuntu, Kali Linux (pacchetti `.deb`)
- Fedora, CentOS, RHEL (pacchetti `.rpm`)
- Arch Linux (pacchetti `pacman`)
- macOS (tramite Homebrew)
- Windows (solo Tor Browser o Expert Bundle)

Questa guida si concentra su **Debian/Kali** perché è il sistema che uso.

### Requisiti hardware minimi

| Risorsa | Minimo | Raccomandato |
|---------|--------|-------------|
| RAM | 256 MB | 512 MB+ |
| Disco | 50 MB per Tor + ~200 MB per descriptor cache | 500 MB+ |
| CPU | Qualsiasi x86_64 o ARM | Multi-core per relay |
| Rete | Qualsiasi connessione TCP | Banda stabile per relay |

Per un **client** (il nostro caso), i requisiti sono minimi. Per un **relay**, servono
più risorse e soprattutto banda stabile.

---

## Installazione dei pacchetti

### Metodo 1: Repository di sistema (più semplice)

```bash
sudo apt update
sudo apt install tor obfs4proxy proxychains4 torsocks nyx
```

Questo installa:
- `tor` — il daemon Tor
- `obfs4proxy` — pluggable transport per offuscamento traffico
- `proxychains4` — wrapper per forzare applicazioni attraverso proxy
- `torsocks` — alternativa a proxychains basata su LD_PRELOAD
- `nyx` — monitor TUI per Tor (ex `arm`)

### Nella mia esperienza

Su Kali Linux, tutti questi pacchetti sono nei repository standard:
```bash
> sudo apt install tor obfs4proxy
Reading package lists... Done
Building dependency tree... Done
The following NEW packages will be installed:
  obfs4proxy tor tor-geoipdb
...
```

Il pacchetto `tor-geoipdb` viene installato come dipendenza e contiene il database
GeoIP per la localizzazione dei relay.

### Metodo 2: Repository ufficiale Tor Project (più aggiornato)

I repository Debian possono avere versioni leggermente datate di Tor. Per la versione
più recente, usare il repository ufficiale:

```bash
# Installare le dipendenze per il repository
sudo apt install apt-transport-https gpg

# Aggiungere la chiave GPG del Tor Project
wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | sudo tee /usr/share/keyrings/tor-archive-keyring.gpg > /dev/null

# Aggiungere il repository (sostituire "bookworm" con la propria release)
echo "deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org bookworm main" | sudo tee /etc/apt/sources.list.d/tor.list

# Per Kali (che è basata su Debian testing/sid):
echo "deb [signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org sid main" | sudo tee /etc/apt/sources.list.d/tor.list

# Aggiornare e installare
sudo apt update
sudo apt install tor deb.torproject.org-keyring
```

### Verifica della versione installata

```bash
> tor --version
Tor version 0.4.8.10.
```

La versione è importante perché determina:
- Quali protocolli sono supportati (ntor, hs-v3, congestion control, etc.)
- Quali vulnerabilità note sono state patchate
- Quale formato di consenso è supportato

---

## Verifica dell'installazione

### 1. Verificare che il binario tor sia installato correttamente

```bash
> which tor
/usr/bin/tor

> which obfs4proxy
/usr/bin/obfs4proxy

> which proxychains4
/usr/bin/proxychains4

> which torsocks
/usr/bin/torsocks
```

### 2. Verificare i permessi

Tor gira come utente `debian-tor` su sistemi Debian. Le directory devono avere i
permessi corretti:

```bash
> ls -la /var/lib/tor/
total 24
drwx--S--- 3 debian-tor debian-tor 4096 ... .
...

> ls -la /var/log/tor/
total 8
drwxr-s--- 2 debian-tor adm 4096 ... .
...

> ls -la /run/tor/
total 4
drwxr-sr-x 2 debian-tor debian-tor 100 ... .
-rw------- 1 debian-tor debian-tor  32 ... control.authcookie
```

### 3. Verificare obfs4proxy

```bash
> obfs4proxy --version
obfs4proxy-0.0.14

> ls -la /usr/bin/obfs4proxy
-rwxr-xr-x 1 root root 7061504 ... /usr/bin/obfs4proxy
```

obfs4proxy deve essere eseguibile. Se non lo è:
```bash
sudo chmod +x /usr/bin/obfs4proxy
```

### 4. Verificare la configurazione (senza avviare Tor)

```bash
> sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
...
Configuration was valid
```

Se ci sono errori:
```bash
> sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
[warn] Unrecognized option 'InvalidOption'
...
```

Nella mia esperienza, gli errori più comuni in questa fase sono:
- Bridge malformati (mancanza di `cert=` o fingerprint errato)
- Path errato per `obfs4proxy`
- Permessi errati su `/var/lib/tor/`

---

## Gestione del servizio systemd

### Unità systemd di Tor

Tor su Debian usa un'unità systemd template: `tor@default.service`. Questo permette
di eseguire multiple istanze di Tor con configurazioni diverse.

```bash
# Avviare Tor
sudo systemctl start tor@default.service

# Fermare Tor
sudo systemctl stop tor@default.service

# Riavviare Tor (chiude e riapre il daemon)
sudo systemctl restart tor@default.service

# Ricaricare la configurazione (SIGHUP — non chiude il daemon)
sudo systemctl reload tor@default.service

# Abilitare Tor all'avvio del sistema
sudo systemctl enable tor@default.service

# Disabilitare l'avvio automatico
sudo systemctl disable tor@default.service

# Stato corrente
sudo systemctl status tor@default.service
```

### Differenza tra restart e reload

| Operazione | Cosa fa | Circuiti | Connessioni |
|-----------|---------|----------|-------------|
| `restart` | Ferma e riavvia il daemon | Tutti distrutti | Interrotte |
| `reload` | Invia SIGHUP, rilegge torrc | Mantenuti (se possibile) | Mantenute |
| `NEWNYM` | Segnale via ControlPort | Marcati come dirty | Mantenute |

Nella mia esperienza, uso:
- `restart` quando cambio configurazione dei bridge o abilito/disabilito funzionalità
- `reload` quando modifico parametri minori
- `NEWNYM` per cambiare IP senza interrompere nulla

---

## Configurazione iniziale minima

### Il file `/etc/tor/torrc`

Dopo l'installazione, il torrc contiene solo commenti. La configurazione minima
per il mio setup è:

```ini
# === Porte di ascolto ===
SocksPort 9050                  # Proxy SOCKS5 per applicazioni
DNSPort 5353                    # DNS via Tor (previene leak DNS)
AutomapHostsOnResolve 1         # Risolve automaticamente .onion e hostname via Tor
ControlPort 9051                # Porta di controllo per NEWNYM e monitoring
CookieAuthentication 1          # Autenticazione al ControlPort via cookie file

# === Sicurezza ===
ClientUseIPv6 0                 # Disabilita IPv6 (previene leak)

# === Logging ===
Log notice file /var/log/tor/notices.log

# === Directory dati ===
DataDirectory /var/lib/tor
```

Dopo aver salvato:
```bash
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
sudo systemctl restart tor@default.service
```

### Verifica che tutto funzioni

```bash
# Verificare che le porte siano in ascolto
> sudo netstat -tlnp | grep tor
tcp   0  0  127.0.0.1:9050   0.0.0.0:*  LISTEN  1234/tor
tcp   0  0  127.0.0.1:9051   0.0.0.0:*  LISTEN  1234/tor

> sudo netstat -ulnp | grep tor
udp   0  0  127.0.0.1:5353   0.0.0.0:*         1234/tor

# Verificare il bootstrap
> sudo journalctl -u tor@default.service -n 20
...
Bootstrapped 100% (done): Done

# Verificare che Tor funzioni
> curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
185.220.101.143

> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
185.220.101.143
```

Se l'IP restituito è diverso dal tuo IP reale, Tor funziona.

---

## Configurazione del gruppo debian-tor

Per usare il ControlPort senza sudo, l'utente deve essere nel gruppo `debian-tor`.
Questo gruppo ha accesso al file cookie di autenticazione.

```bash
# Aggiungere l'utente corrente al gruppo
sudo usermod -aG debian-tor $USER

# IMPORTANTE: il cambio di gruppo richiede un nuovo login
# Opzione 1: riavviare la sessione
# Opzione 2: forzare il logout
pkill -KILL -u $USER

# Dopo il login, verificare
> groups
... debian-tor ...

# Verificare l'accesso al cookie
> ls -la /run/tor/control.authcookie
-rw-r----- 1 debian-tor debian-tor 32 ... /run/tor/control.authcookie

> xxd -p /run/tor/control.authcookie | tr -d '\n'
a1b2c3d4e5f6...  (32 byte in hex)
```

### Nella mia esperienza

Questo passaggio mi ha bloccato inizialmente. Quando eseguivo il mio script `newnym`:
```bash
> ~/scripts/newnym
514 Authentication required
```

L'errore 514 significava che il cookie non era leggibile perché il mio utente non era
nel gruppo `debian-tor`. Dopo `sudo usermod -aG debian-tor $USER` e un riavvio della
sessione (`pkill -KILL -u $USER`), il problema si è risolto:
```bash
> ~/scripts/newnym
250 OK
250 closing connection
```

---

## Configurazione del profilo Firefox per Tor

Per navigare via Tor senza Tor Browser, ho creato un profilo Firefox dedicato:

```bash
# Creare il profilo
firefox -no-remote -CreateProfile tor-proxy

# Avviare Firefox con il profilo Tor via proxychains
proxychains firefox -no-remote -P tor-proxy & disown
```

Il flag `-no-remote` è fondamentale: impedisce a Firefox di connettersi a un'istanza
già in esecuzione (che potrebbe non passare da Tor).

Alternativa per processi che devono sopravvivere al logout:
```bash
nohup proxychains firefox -no-remote -P tor-proxy >/dev/null 2>&1 &
```

### Attenzione

Usare Firefox con profilo dedicato via proxychains **NON** equivale a Tor Browser.
Firefox normale ha:
- User-Agent diverso
- Nessuna protezione anti-fingerprinting
- WebRTC potenzialmente attivo (leak IP)
- Canvas, WebGL, font non spoofati

Lo uso per comodità e test, non per anonimato massimo.

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

- [torrc — Guida Completa](torrc-guida-completa.md) — Configurazione completa dopo l'installazione
- [Gestione del Servizio](gestione-del-servizio.md) — systemd, log, troubleshooting
- [Verifica IP, DNS e Leak](../04-strumenti-operativi/verifica-ip-dns-e-leak.md) — Test post-installazione
- [ProxyChains — Guida Completa](../04-strumenti-operativi/proxychains-guida-completa.md) — Configurare proxychains dopo Tor
- [Tor Browser e Applicazioni](../04-strumenti-operativi/tor-browser-e-applicazioni.md) — Profilo Firefox per Tor
