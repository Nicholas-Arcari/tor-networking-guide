# Configurazione Iniziale - Torrc Minimo, Gruppo debian-tor e Firefox

Configurazione iniziale minima del torrc, gestione del gruppo debian-tor
per l'accesso al ControlPort, e profilo Firefox dedicato per Tor.

Estratto da [Installazione e Verifica](installazione-e-verifica.md).

---

## Indice

- [Gestione del servizio systemd](#gestione-del-servizio-systemd)
- [Configurazione iniziale minima](#configurazione-iniziale-minima)
- [Configurazione del gruppo debian-tor](#configurazione-del-gruppo-debian-tor)
- [Configurazione del profilo Firefox per Tor](#configurazione-del-profilo-firefox-per-tor)

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

# Ricaricare la configurazione (SIGHUP - non chiude il daemon)
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

## Vedi anche

- [Installazione e Verifica](installazione-e-verifica.md) - Prerequisiti, installazione, verifica
- [Troubleshooting e Struttura](troubleshooting-e-struttura.md) - Problemi comuni, struttura file
- [torrc - Guida Completa](torrc-guida-completa.md) - Tutte le direttive del torrc
- [Gestione del Servizio](gestione-del-servizio.md) - systemd avanzato, log, debug
- [Tor Browser e Applicazioni](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Firefox vs Tor Browser
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
