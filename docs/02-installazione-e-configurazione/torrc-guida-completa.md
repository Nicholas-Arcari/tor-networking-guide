# Configurazione torrc - Guida Completa a Ogni Direttiva

Questo documento analizza in profondità il file di configurazione di Tor (`/etc/tor/torrc`),
spiegando ogni direttiva rilevante con il suo significato a basso livello, le implicazioni
per la sicurezza, e i valori che ho usato nella mia esperienza pratica su Kali Linux.

Non è un elenco di opzioni: è una guida ragionata su cosa ogni direttiva fa internamente
e perché certi valori sono migliori di altri.

---
---

## Indice

- [Il file torrc - Struttura e sintassi](#il-file-torrc-struttura-e-sintassi)
- [Sezione 1: Porte e interfacce di rete](#sezione-1-porte-e-interfacce-di-rete)
- [Sezione 2: Logging](#sezione-2-logging)
**Approfondimenti** (file dedicati):
- [Bridge e Sicurezza nel torrc](torrc-bridge-e-sicurezza.md) - Bridge, pluggable transports, sicurezza avanzata
- [Performance, Relay e Configurazione Completa](torrc-performance-e-relay.md) - Tuning, relay, hidden services, torrc completo


## Il file torrc - Struttura e sintassi

Il file `/etc/tor/torrc` è il file di configurazione principale di Tor. La sintassi è:

```ini
# Commenti iniziano con #
NomeDirettiva valore
NomeDirettiva valore1 valore2   # alcune direttive accettano più valori
```

- Una direttiva per riga
- I valori booleani accettano `0`/`1` oppure `true`/`false`
- I percorsi file accettano path assoluti
- Le porte accettano numeri o `auto`
- Si possono includere file esterni con `%include /path/to/file`

### Verifica della configurazione

Prima di riavviare Tor, **sempre** verificare:
```bash
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config
```

Questo valida la sintassi e i valori senza avviare il daemon. Nella mia esperienza,
mi ha salvato più volte da errori di battitura nei bridge.

---

## Sezione 1: Porte e interfacce di rete

### SocksPort

```ini
SocksPort 9050
```

**Cosa fa**: apre un server SOCKS5 su `127.0.0.1:9050`. Le applicazioni si connettono
qui per instradare traffico attraverso Tor.

**Dettagli interni**:
- Il protocollo SOCKS5 negozia il tipo di connessione (CONNECT, BIND, UDP ASSOCIATE)
- Tor supporta solo `CONNECT` (TCP). `UDP ASSOCIATE` viene rifiutato.
- Il client può specificare la destinazione come hostname (DOMAINNAME) o IP
- Se il client invia un hostname, Tor lo risolve via DNS attraverso la rete Tor
  (il DNS non esce mai dalla macchina locale)

**Configurazioni avanzate**:
```ini
# Porta con binding specifico (non solo localhost)
SocksPort 192.168.1.100:9050

# Porta con flag di isolamento
SocksPort 9050 IsolateDestAddr IsolateDestPort

# Porta con autenticazione SOCKS (per isolamento per-app)
SocksPort 9050 IsolateSOCKSAuth

# Porta senza isolamento (tutti gli stream condividono circuiti)
SocksPort 9053 SessionGroup=1

# Porta con SOCKS5 solo (no SOCKS4)
SocksPort 9050 PreferSOCKSNoAuth

# Porta con timeout personalizzato
SocksPort 9050 KeepAliveIsolateSOCKSAuth
```

**Flag di isolamento disponibili**:

| Flag | Effetto |
|------|---------|
| `IsolateDestAddr` | Stream verso destinazioni diverse → circuiti diversi |
| `IsolateDestPort` | Stream verso porte diverse → circuiti diversi |
| `IsolateSOCKSAuth` | Username/password SOCKS diverse → circuiti diversi |
| `IsolateClientAddr` | Connessioni da IP locali diversi → circuiti diversi |
| `IsolateClientProtocol` | Protocolli diversi (SOCKS4 vs SOCKS5) → circuiti diversi |
| `SessionGroup=N` | Raggruppa stream in sessioni manuali |

**Nella mia esperienza**: uso solo `SocksPort 9050` senza flag extra. Tor applica
isolamento di default ragionevole. Per un setup più avanzato (es. browser separato
da CLI), configurerei porte multiple.

### DNSPort

```ini
DNSPort 5353
```

**Cosa fa**: apre un server DNS su `127.0.0.1:5353`. Le query DNS inviate qui vengono
risolte attraverso la rete Tor, non tramite il DNS del sistema.

**Dettagli interni**:
- Tor intercetta le query DNS e le invia come celle `RELAY_RESOLVE` attraverso il
  circuito. L'Exit Node risolve l'hostname e risponde con `RELAY_RESOLVED`.
- La porta 5353 è usata intenzionalmente perché non è la porta DNS standard (53).
  Questo evita conflitti con resolver locali (systemd-resolved, dnsmasq).
- Per far sì che il sistema usi questo DNS, bisogna configurare il resolver:
  ```bash
  # In /etc/resolv.conf (o equivalente)
  nameserver 127.0.0.1
  ```
  E poi ridirezionare la porta 53 alla 5353, oppure usare `DNSPort 53` (richiede root).

**Perché è importante**: senza DNSPort, le query DNS del sistema escono in chiaro
verso il DNS dell'ISP. Anche se il traffico HTTP va via Tor, il DNS rivela quali
siti stai visitando. Questo è un **DNS leak**.

**Nella mia esperienza**: uso `DNSPort 5353` insieme a `proxy_dns` in proxychains.
Quando uso `proxychains curl`, il DNS viene risolto da Tor (il hostname viene
inviato nel SOCKS5 CONNECT come DOMAINNAME, non come IP). Ma applicazioni che non
passano da proxychains possono ancora fare DNS leak.

### AutomapHostsOnResolve

```ini
AutomapHostsOnResolve 1
```

**Cosa fa**: quando un'applicazione chiede la risoluzione di un hostname `.onion` o
di un hostname qualsiasi tramite il DNSPort, Tor assegna automaticamente un indirizzo
IP fittizio (nella range `VirtualAddrNetworkIPv4`, default `127.192.0.0/10`) e
mantiene un mapping interno hostname → IP fittizio.

**Dettagli interni**:
- L'IP fittizio non viene mai usato in rete. Serve solo come placeholder locale.
- Quando l'applicazione si connette all'IP fittizio via SocksPort, Tor lo rimappa
  all'hostname originale e lo risolve tramite la rete Tor.
- Indispensabile per gli indirizzi `.onion` che non hanno IP reali.

### ControlPort

```ini
ControlPort 9051
CookieAuthentication 1
```

**Cosa fa**: apre un'interfaccia di controllo su `127.0.0.1:9051` che permette di:
- Inviare segnali (NEWNYM, DORMANT, ACTIVE, HEARTBEAT, etc.)
- Interrogare lo stato dei circuiti
- Leggere informazioni sulla configurazione
- Monitorare eventi in tempo reale

**Metodi di autenticazione**:

1. **CookieAuthentication** (raccomandato per uso locale):
   ```ini
   CookieAuthentication 1
   ```
   Tor genera un file cookie di 32 byte in `/run/tor/control.authcookie`. Per
   autenticarsi, il client legge il cookie e lo invia come hex:
   ```
   AUTHENTICATE <32 byte in hex>
   ```

2. **HashedControlPassword** (per accesso remoto o condiviso):
   ```bash
   > tor --hash-password "MyPassword"
   16:872860B76453A77D60CA2BB8C1A7042072093276A3D701AD684053EC4C
   ```
   ```ini
   HashedControlPassword 16:872860B76453A77D60CA2BB8C1A7042072093276A3D701AD684053EC4C
   ```

**Protocollo ControlPort**: il protocollo è testuale, simile a SMTP:
```
AUTHENTICATE <credentials>\r\n
250 OK\r\n
SIGNAL NEWNYM\r\n
250 OK\r\n
GETINFO circuit-status\r\n
250+circuit-status=
1 BUILT $FINGERPRINT1~Nick1,...
.\r\n
250 OK\r\n
QUIT\r\n
250 closing connection\r\n
```

**Nella mia esperienza**, uso CookieAuthentication perché è più sicuro (il cookie
cambia ad ogni riavvio di Tor) e non richiede di memorizzare password. Il mio
script `newnym` legge il cookie così:
```bash
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
```

### ClientUseIPv6

```ini
ClientUseIPv6 0
```

**Cosa fa**: impedisce a Tor di usare connessioni IPv6 verso i relay.

**Perché disabilitarlo**:
- Molte reti non supportano IPv6 correttamente → connessioni fallite
- IPv6 può rivelare il tuo prefisso di rete (/64) che è spesso legato al tuo
  indirizzo fisico
- Se il sistema ha IPv6 attivo ma non configurato correttamente, le connessioni
  IPv6 possono fallire silenziosamente, rallentando il bootstrap

**Dettaglio tecnico**: quando `ClientUseIPv6 0`, Tor filtra i relay con solo
indirizzi IPv6 dalla selezione. Non influenza il traffico applicativo (che è
sempre TCP su IPv4 verso il SocksPort locale).

---

## Sezione 2: Logging

```ini
Log notice file /var/log/tor/notices.log
```

**Livelli di log disponibili**:

| Livello | Verbosità | Uso |
|---------|-----------|-----|
| `err` | Solo errori fatali | Produzione, monitoraggio automatico |
| `warn` | Errori + avvisi | Raccomandato per operazioni normali |
| `notice` | Warn + eventi normali importanti | **Il mio default** |
| `info` | Notice + dettagli operativi | Debug leggero |
| `debug` | Tutto | Solo per sviluppo (ATTENZIONE: può loggare dati sensibili) |

**Destinazioni del log**:
```ini
Log notice file /var/log/tor/notices.log     # su file
Log notice syslog                            # su syslog del sistema
Log notice stderr                            # su standard error
```

**ATTENZIONE ai livelli info e debug**: possono loggare hostname delle richieste,
circuiti con fingerprint dei relay, timing delle connessioni. In un contesto di
sicurezza, non usare mai livelli superiori a `notice` in produzione.

**Nella mia esperienza**, `notice` è il livello giusto. Mi permette di vedere:
- Bootstrap progress
- Connessioni a bridge riuscite/fallite
- Errori di configurazione
- Cambi di guard

Ma non mostra dettagli che potrebbero compromettere l'anonimato se i log venissero
acquisiti.

### Monitorare i log in tempo reale

```bash
sudo journalctl -u tor@default.service -f
# oppure
sudo tail -f /var/log/tor/notices.log
```

---

> **Continua in**: [Bridge e Sicurezza nel torrc](torrc-bridge-e-sicurezza.md) per bridge,
> pluggable transports e direttive di sicurezza, e in [Performance, Relay e Configurazione
> Completa](torrc-performance-e-relay.md) per tuning, configurazione relay e onion services.

---

## Vedi anche

- [Bridge e Sicurezza nel torrc](torrc-bridge-e-sicurezza.md) - Bridge, pluggable transports, sicurezza
- [Performance, Relay e Configurazione Completa](torrc-performance-e-relay.md) - Tuning, relay, hidden services
- [Installazione e Verifica](installazione-e-verifica.md) - Setup iniziale prima del torrc
- [Gestione del Servizio](gestione-del-servizio.md) - Riavviare Tor dopo modifiche al torrc
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester

---

## Cheat Sheet - Direttive torrc essenziali

| Direttiva | Valore | Descrizione |
|-----------|--------|-------------|
| `SocksPort` | `9050` | Porta SOCKS5 per le applicazioni |
| `DNSPort` | `5353` | Porta DNS locale (risolve via Tor) |
| `ControlPort` | `9051` | Porta per controllare Tor (Stem, nyx) |
| `CookieAuthentication` | `1` | Autenticazione cookie per ControlPort |
| `TransPort` | `9040` | Porta per transparent proxy |
| `AutomapHostsOnResolve` | `1` | Mappa hostname a IP fittizi |
| `ClientUseIPv6` | `0` | Disabilita IPv6 per i client |
| `UseBridges` | `1` | Abilita l'uso di bridge |
| `Bridge` | `obfs4 IP:PORT ...` | Configura un bridge obfs4 |
| `MaxCircuitDirtiness` | `600` | Secondi prima del rinnovo circuito |
| `ExitNodes` | `{cc}` | Forza exit da un paese (sconsigliato) |
| `StrictNodes` | `1` | Forza la selezione (sconsigliato) |
| `Log` | `notice file /var/log/tor/tor.log` | File di log |
