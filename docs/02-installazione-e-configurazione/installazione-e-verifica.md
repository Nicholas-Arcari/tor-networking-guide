> **Lingua / Language**: Italiano | [English](../en/02-installazione-e-configurazione/installazione-e-verifica.md)

# Installazione e Verifica di Tor - Guida Completa per Debian/Kali

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
**Approfondimenti** (file dedicati):
- [Configurazione Iniziale](configurazione-iniziale.md) - Torrc minimo, debian-tor, profilo Firefox
- [Troubleshooting e Struttura](troubleshooting-e-struttura.md) - Problemi comuni, struttura file, aggiornamento


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
- `tor` - il daemon Tor
- `obfs4proxy` - pluggable transport per offuscamento traffico
- `proxychains4` - wrapper per forzare applicazioni attraverso proxy
- `torsocks` - alternativa a proxychains basata su LD_PRELOAD
- `nyx` - monitor TUI per Tor (ex `arm`)

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

> **Continua in**: [Configurazione Iniziale](configurazione-iniziale.md) per la configurazione
> minima del torrc, il gruppo debian-tor e il profilo Firefox, e in
> [Troubleshooting e Struttura](troubleshooting-e-struttura.md) per i problemi comuni,
> la struttura dei file e l'aggiornamento.

---

## Vedi anche

- [Configurazione Iniziale](configurazione-iniziale.md) - Torrc minimo, debian-tor, profilo Firefox
- [Troubleshooting e Struttura](troubleshooting-e-struttura.md) - Problemi comuni, struttura file, aggiornamento
- [torrc - Guida Completa](torrc-guida-completa.md) - Configurazione completa dopo l'installazione
- [Gestione del Servizio](gestione-del-servizio.md) - systemd, log, troubleshooting
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
