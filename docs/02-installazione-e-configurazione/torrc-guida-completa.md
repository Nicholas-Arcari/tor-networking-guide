# Configurazione torrc — Guida Completa a Ogni Direttiva

Questo documento analizza in profondità il file di configurazione di Tor (`/etc/tor/torrc`),
spiegando ogni direttiva rilevante con il suo significato a basso livello, le implicazioni
per la sicurezza, e i valori che ho usato nella mia esperienza pratica su Kali Linux.

Non è un elenco di opzioni: è una guida ragionata su cosa ogni direttiva fa internamente
e perché certi valori sono migliori di altri.

---

## Il file torrc — Struttura e sintassi

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

## Sezione 3: Bridge e Pluggable Transports

### UseBridges

```ini
UseBridges 1
```

**Cosa fa**: dice a Tor di connettersi alla rete tramite bridge anziché tramite
relay pubblici. Tor non tenterà di connettersi direttamente ai guard nel consenso.

**Quando attivarlo**:
- L'ISP blocca le connessioni ai relay Tor noti
- Si vuole nascondere all'ISP l'uso di Tor
- La rete ha DPI che identifica e blocca il traffico Tor
- Si è in un paese con censura attiva

### ClientTransportPlugin

```ini
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
```

**Cosa fa**: registra `obfs4proxy` come pluggable transport disponibile. Quando Tor
deve connettersi a un bridge obfs4, invoca `/usr/bin/obfs4proxy` come processo
figlio.

**Dettagli interni**:
- Tor comunica con obfs4proxy tramite il protocollo PT (Pluggable Transport)
- obfs4proxy apre una porta locale (scelta dinamicamente)
- Tor si connette a questa porta locale
- obfs4proxy offusca il traffico e lo inoltra al bridge remoto
- Il bridge remoto ha un'istanza di obfs4proxy server-side che deoffusca

### Direttive Bridge

```ini
Bridge obfs4 <IP>:<PORT> <FINGERPRINT> cert=<CERT> iat-mode=<0|1|2>
```

**Componenti**:
- `obfs4` — tipo di pluggable transport
- `<IP>:<PORT>` — indirizzo del bridge (IPv4 o IPv6)
- `<FINGERPRINT>` — fingerprint del relay bridge (20 byte hex)
- `cert=<CERT>` — certificato obfs4 del bridge (base64)
- `iat-mode` — modalità di timing:
  - `0` — nessun padding temporale (più veloce, meno sicuro)
  - `1` — padding temporale moderato (raccomandato)
  - `2` — padding temporale massimo (più lento, massima resistenza a DPI)

**Nella mia esperienza**:
```ini
Bridge obfs4 xxx.xxx.xxx.xxx:4431 F829D395093B... cert=... iat-mode=0
Bridge obfs4 xxx.xxx.xxx.xxx:13630 A3D55AA6178... cert=... iat-mode=2
```

Ho configurato due bridge con iat-mode diversi. Il primo (iat-mode=0) è più veloce
e lo uso come primario. Il secondo (iat-mode=2) è il fallback per situazioni dove
il DPI è aggressivo.

**Come ottenere bridge**:
1. `https://bridges.torproject.org/options` — sito ufficiale (richiede CAPTCHA)
2. Email a `bridges@torproject.org` con corpo `get transport obfs4` (da Gmail o Riseup)
3. Snowflake — bridge tramite browser di volontari (meno stabile)

**Nota dalla mia esperienza**: inizialmente avevo usato un URL errato per i bridge
(`https://bridges.torproject.org/bridges`, suggerito da ChatGPT). L'URL corretto è
`https://bridges.torproject.org/options`. I bridge ricevuti vanno inseriti esattamente
come forniti, incluso il certificato completo.

---

## Sezione 4: Direttive di sicurezza avanzate

### ExitNodes, EntryNodes, StrictNodes

```ini
# Forzare exit in un paese specifico
ExitNodes {de},{nl}
StrictNodes 1

# Escludere exit da certi paesi
ExcludeExitNodes {ru},{cn},{ir}

# Forzare entry specifici
EntryNodes {se},{ch}
```

**ATTENZIONE**: usare `ExitNodes` con `StrictNodes 1` è generalmente **sconsigliato**:
- Riduce drasticamente il pool di exit disponibili
- Aumenta la probabilità di saturazione dei pochi exit rimasti
- Rende il traffico più riconoscibile (fingerprinting: "questo utente esce sempre dalla Germania")
- Se i pochi exit disponibili sono offline, Tor non funziona

**Nella mia esperienza**, ho provato `ExitNodes {it}` per uscire con IP italiano.
Il risultato è stato:
- Pochissimi exit italiani disponibili
- Latenza peggiore (paradossalmente, perché i pochi exit erano sovraccarichi)
- Circuiti instabili
- Ho rimosso la direttiva e lasciato che Tor scelga liberamente

### ExcludeNodes

```ini
ExcludeNodes {cn},{ru},{ir},{kp}
```

**Cosa fa**: esclude completamente i relay in questi paesi da qualsiasi posizione
nel circuito (guard, middle, exit). Più ragionevole di `ExitNodes` perché non limita
a pochi relay ma ne esclude alcuni.

### MapAddress

```ini
MapAddress www.example.com www.example.com.torproject.org
MapAddress 10.0.0.0/8 0.0.0.0/8
```

**Cosa fa**: permette di redirezionare hostname o range IP a livello di Tor. Utile
per test o per forzare il routing di certe destinazioni.

### ReachableAddresses

```ini
ReachableAddresses *:80, *:443
ReachableAddresses reject *:*
```

**Cosa fa**: limita le porte verso cui Tor può connettersi per raggiungere i relay.
Utile se sei dietro un firewall che permette solo traffico HTTP/HTTPS.

**Dettaglio**: questo riguarda la connessione Tor→relay, non il traffico applicativo.
Se il tuo firewall permette solo porta 80 e 443, configuri `ReachableAddresses` di
conseguenza e Tor selezionerà solo relay con ORPort su quelle porte.

### ConnectionPadding

```ini
ConnectionPadding 1      # Abilita padding tra relay (default: auto)
ReducedConnectionPadding 0  # Non ridurre il padding (default)
```

**Cosa fa**: Tor invia celle di padding sulle connessioni tra relay per mascherare
i pattern di traffico. `ConnectionPadding 1` forza il padding anche quando non
sarebbe altrimenti attivato.

---

## Sezione 5: Performance e tuning

### CircuitBuildTimeout

```ini
CircuitBuildTimeout 60
```

**Cosa fa**: timeout in secondi per la costruzione di un circuito. Se un circuito non
viene costruito entro questo tempo, viene abbandonato e Tor ne prova un altro.

**Default**: Tor calcola dinamicamente questo valore basandosi sulle esperienze
passate. Impostarlo manualmente sovrascrive il calcolo adattivo.

### LearnCircuitBuildTimeout

```ini
LearnCircuitBuildTimeout 1
```

**Cosa fa**: permette a Tor di adattare il timeout basandosi sulle esperienze reali.
Se la rete è lenta (es. via bridge obfs4), Tor aumenta il timeout. Se è veloce, lo
riduce.

### NumEntryGuards

```ini
NumEntryGuards 1
```

**Cosa fa**: numero di guard persistenti da mantenere. Il default è 1 (prima era 3).

**Perché 1 è meglio di 3**: con un solo guard, c'è 1 possibilità su ~1000 che il
guard sia malevolo. Con 3 guard, ci sono 3 possibilità su ~1000. Meno guard = meno
rischio di avere un guard malevolo nel tempo.

### MaxCircuitDirtiness

```ini
MaxCircuitDirtiness 600
```

**Cosa fa**: tempo in secondi dopo il quale un circuito "dirty" (che ha trasportato
almeno uno stream) non viene riutilizzato per nuovi stream. Default: 600 (10 minuti).

**Implicazione**: dopo 10 minuti, le nuove connessioni useranno un nuovo circuito
(con potenzialmente un nuovo exit e un nuovo IP). Questo è il motivo per cui il tuo
IP visibile cambia periodicamente anche senza NEWNYM.

---

## Sezione 6: Configurazione come relay (opzionale)

Queste direttive sono per chi vuole contribuire alla rete Tor operando un relay.
Non le ho attivate nella mia configurazione, ma le documento per completezza.

### ORPort

```ini
ORPort 9001
# oppure con binding specifico
ORPort 443 NoListen
ORPort 127.0.0.1:9001 NoAdvertise
```

**Cosa fa**: apre la porta Onion Router, che accetta connessioni da altri relay Tor.
Attivare ORPort trasforma il tuo sistema in un relay Tor.

### Relay Bandwidth

```ini
RelayBandwidthRate 1 MB    # Throttle a 1 MB/s
RelayBandwidthBurst 2 MB   # Burst fino a 2 MB/s
AccountingMax 500 GB       # Massimo 500 GB per periodo
AccountingStart month 1 00:00  # Periodo mensile
```

### Relay come bridge

```ini
BridgeRelay 1
PublishServerDescriptor 0   # Non pubblicare nel consenso (bridge privato)
ServerTransportPlugin obfs4 exec /usr/bin/obfs4proxy
ServerTransportListenAddr obfs4 0.0.0.0:8443
ExtORPort auto
```

### Exit Policy (se il relay è un exit)

```ini
# Permetti solo web
ExitPolicy accept *:80
ExitPolicy accept *:443
ExitPolicy reject *:*

# Oppure: restrittiva ma permetti servizi comuni
ExitPolicy accept *:20-23     # FTP, SSH, Telnet
ExitPolicy accept *:53        # DNS
ExitPolicy accept *:80        # HTTP
ExitPolicy accept *:443       # HTTPS
ExitPolicy accept *:993       # IMAPS
ExitPolicy accept *:995       # POP3S
ExitPolicy reject *:*
```

---

## Sezione 7: Hidden Services (Onion Services v3)

```ini
HiddenServiceDir /var/lib/tor/hidden_service/
HiddenServicePort 80 127.0.0.1:8080
```

**Cosa fa**: configura un onion service che rende raggiungibile un servizio locale
(porta 8080) tramite un indirizzo `.onion` sulla porta 80.

**Dettagli interni**:
- Tor genera una coppia di chiavi Ed25519 in `HiddenServiceDir`
- L'indirizzo `.onion` è derivato dalla chiave pubblica (56 caratteri per v3)
- Tor pubblica dei descriptor cifrati sugli HSDir nella rete Tor
- I client che conoscono l'indirizzo `.onion` usano il descriptor per stabilire
  un circuito rendezvous

Questo viene approfondito nel documento dedicato agli onion services.

---

## La mia configurazione completa

Ecco il mio torrc completo, con commenti che spiegano ogni scelta:

```ini
# === Porte client ===
SocksPort 9050                    # Proxy SOCKS5 principale
DNSPort 5353                      # DNS via Tor
AutomapHostsOnResolve 1           # Mapping automatico .onion e hostname

# === Controllo ===
ControlPort 9051                  # Per NEWNYM e monitoring
CookieAuthentication 1            # Auth via cookie file

# === Sicurezza ===
ClientUseIPv6 0                   # No IPv6 (previene leak)

# === Dati ===
DataDirectory /var/lib/tor

# === Logging ===
Log notice file /var/log/tor/notices.log

# === Bridge obfs4 ===
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
Bridge obfs4 xxx.xxx.xxx.xxx:4431 F829D395093B... cert=... iat-mode=0
Bridge obfs4 xxx.xxx.xxx.xxx:13630 A3D55AA6178... cert=... iat-mode=2
```

Questa configurazione:
- Instrada il traffico attraverso bridge obfs4 (nasconde l'uso di Tor all'ISP)
- Previene DNS leak (DNSPort + AutomapHostsOnResolve)
- Previene IPv6 leak (ClientUseIPv6 0)
- Permette rotazione IP via ControlPort (NEWNYM)
- Logga a livello notice per troubleshooting senza compromettere privacy
