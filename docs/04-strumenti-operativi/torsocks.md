# torsocks - Wrapper LD_PRELOAD Dedicato per Tor

torsocks è un wrapper LD_PRELOAD progettato **specificamente per Tor**. A differenza
di proxychains (che supporta chain di proxy generici), torsocks è ottimizzato per
un singolo scenario: instradare traffico TCP attraverso il daemon Tor locale,
bloccando attivamente tutto il traffico che potrebbe causare leak.

> **Vedi anche**: [ProxyChains - Guida Completa](./proxychains-guida-completa.md)
> per il confronto, [DNS Leak](../05-sicurezza-operativa/dns-leak.md) per la
> prevenzione dei leak, [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md)
> per IsolatePID.

---

## Indice

- [Come funziona internamente](#come-funziona-internamente)
- [Syscall intercettate](#syscall-intercettate)
- [Gestione DNS in torsocks](#gestione-dns-in-torsocks)
- [Blocco UDP - analisi dettagliata](#blocco-udp--analisi-dettagliata)
- [Configurazione](#configurazione)
- [IsolatePID - stream isolation automatico](#isolatepid--stream-isolation-automatico)
- [Uso pratico](#uso-pratico)
- [Shell interattiva torsocksificata](#shell-interattiva-torsocksificata)
- [torsocks on - attivazione permanente](#torsocks-on--attivazione-permanente)
**Approfondimenti** (file dedicati):
- [torsocks Avanzato](torsocks-avanzato.md) - Variabili, edge cases, debugging, sicurezza, confronto

---

## Come funziona internamente

### Meccanismo LD_PRELOAD

Quando esegui `torsocks curl example.com`, il sistema operativo:

```
1. Shell legge il comando "torsocks curl example.com"
2. torsocks è un wrapper script che esegue:
   LD_PRELOAD=/usr/lib/x86_64-linux-gnu/torsocks/libtorsocks.so curl example.com
3. Il dynamic linker (ld-linux.so) carica libtorsocks.so PRIMA di libc.so
4. Le funzioni in libtorsocks.so "shadowano" le funzioni omonime in libc.so
5. Quando curl chiama connect() → viene eseguita la versione di torsocks
6. torsocks redirige la connessione a 127.0.0.1:9050 via SOCKS5
```

### Il flow completo di una connessione

```
curl example.com
  │
  ├─ getaddrinfo("example.com")
  │   → libtorsocks intercetta
  │   → NON risolve localmente
  │   → restituisce un placeholder (o usa SOCKS5 hostname diretto)
  │
  ├─ connect(socket_fd, sockaddr{IP, port})
  │   → libtorsocks intercetta
  │   → invece di connect() diretto, esegue:
  │     1. connect(127.0.0.1:9050)         [connessione a Tor]
  │     2. SOCKS5 handshake (version, auth)
  │     3. SOCKS5 CONNECT "example.com:443" [ATYP=0x03, hostname]
  │     4. Tor riceve l'hostname, costruisce circuito
  │     5. Exit node risolve DNS e si connette
  │
  ├─ send()/recv() → passano normali attraverso il socket SOCKS5
  │
  └─ close() → chiude il socket, torsocks fa cleanup
```

---

## Syscall intercettate

torsocks intercetta queste chiamate di libreria (non syscall dirette):

| Funzione libc | Azione torsocks |
|---------------|-----------------|
| `connect()` | Ridirige TCP a SOCKS5, blocca UDP |
| `getaddrinfo()` | Intercetta, risolve via SOCKS5 |
| `gethostbyname()` | Intercetta, risolve via SOCKS5 |
| `gethostbyname_r()` | Thread-safe variant, intercettata |
| `getaddrinfo()` | Intercetta con hint per IPv4/IPv6 |
| `sendto()` | Blocca se UDP (es. DNS diretto) |
| `sendmsg()` | Blocca se UDP |
| `socket()` | Monitora creazione socket (per tracking) |
| `close()` | Cleanup delle connessioni tracked |
| `getpeername()` | Restituisce indirizzo reale, non SOCKS5 |

### Cosa NON viene intercettato

```
- Syscall dirette (syscall(__NR_connect, ...))
  → Bypassano libtorsocks completamente
  
- Funzioni di I/O raw (read/write su socket già connesso)
  → Passano dirette (il socket è già connesso via SOCKS5)
  
- Funzioni non-libc (implementazioni custom di DNS, etc.)
  → Se l'app implementa il proprio resolver, torsocks non lo vede
```

Questa è la limitazione fondamentale dell'approccio LD_PRELOAD: funziona solo
per applicazioni che usano le funzioni standard della libc.

---

## Gestione DNS in torsocks

### Meccanismo di risoluzione

A differenza di proxychains (che usa IP fittizi dal range `remote_dns_subnet`),
torsocks gestisce il DNS in modo più pulito:

```
Proxychains:
  getaddrinfo("example.com") → mapping fittizio 224.0.0.1
  connect(224.0.0.1) → riconosce fittizio → SOCKS5 CONNECT "example.com"

torsocks:
  getaddrinfo("example.com") → intercettata direttamente
  → genera SOCKS5 CONNECT con hostname
  → nessun IP fittizio necessario
```

### OnionAddrRange

Per gli indirizzi `.onion`, torsocks usa un range IP fittizio:

```ini
# torsocks.conf
OnionAddrRange 127.42.42.0/24
```

Quando un'applicazione risolve un indirizzo `.onion`:
1. torsocks assegna un IP dal range `127.42.42.0/24`
2. L'app riceve questo IP e chiama `connect()`
3. torsocks riconosce il range → invia via SOCKS5 con l'hostname .onion
4. Tor gestisce la connessione al servizio hidden

### Blocco DNS UDP diretto

Se un'applicazione tenta di inviare una query DNS via UDP diretto:

```
App → sendto(8.8.8.8:53, DNS_query)
  → torsocks intercetta sendto()
  → rileva: destinazione porta 53, protocollo UDP
  → BLOCCA e logga:
    [warn] torsocks[12345]: UDP connection is not supported.
    Dropping connection to 8.8.8.8:53 on port 53
```

---

## Blocco UDP - analisi dettagliata

### Perché Tor non supporta UDP

Tor è basato su circuiti TCP. Il protocollo delle celle (514 byte, trasporto su
TLS/TCP) non ha meccanismo per incapsulare datagrammi UDP. Questo significa:

| Protocollo | Tor | Conseguenza |
|-----------|-----|-------------|
| TCP | Supportato | HTTP, HTTPS, SSH, etc. funzionano |
| UDP | **Non supportato** | DNS, NTP, QUIC, WebRTC, VoIP bloccati |
| ICMP | **Non supportato** | ping, traceroute non funzionano |

### Applicazioni affette dal blocco UDP

| Applicazione/Protocollo | Usa UDP per | Effetto con torsocks |
|------------------------|-------------|---------------------|
| DNS diretto (dig, nslookup) | Query DNS porta 53 | Bloccato, warning |
| NTP (ntpdate, timedatectl) | Sincronizzazione orologio | Bloccato |
| QUIC / HTTP/3 | Trasporto web moderno | Bloccato, fallback a TCP |
| WebRTC | Audio/video P2P | Bloccato completamente |
| VoIP (SIP) | Segnalazione e media | Bloccato |
| Gaming online | Game state updates | Bloccato |
| mDNS | Discovery servizi LAN | Bloccato |
| DHCP | Configurazione rete | Non affetto (livello L2) |

### Vantaggio di sicurezza rispetto a proxychains

```
Con proxychains:
  App → sendto(8.8.8.8:53) → proxychains NON intercetta UDP
  → Il pacchetto UDP esce in chiaro → DNS LEAK!

Con torsocks:
  App → sendto(8.8.8.8:53) → torsocks INTERCETTA e BLOCCA
  → Nessun pacchetto esce → Nessun leak
  → Warning nel log: UDP not supported
```

Questo è il singolo vantaggio più importante di torsocks su proxychains dal
punto di vista della sicurezza.

---

## Configurazione

### File di configurazione

```bash
# Percorso default
/etc/tor/torsocks.conf

# Override per utente
~/.torsocks.conf
```

### Direttive complete

```ini
# /etc/tor/torsocks.conf

# Indirizzo e porta del daemon Tor
TorAddress 127.0.0.1
TorPort 9050

# Range IP per mapping indirizzi .onion
OnionAddrRange 127.42.42.0/24

# Permettere connessioni in ingresso (per server locali)
AllowInbound 1

# Permettere connessioni a localhost (127.0.0.0/8)
AllowOutboundLocalhost 1

# Stream isolation per PID
IsolatePID 1
```

| Direttiva | Default | Descrizione |
|-----------|---------|-------------|
| `TorAddress` | 127.0.0.1 | IP del daemon Tor |
| `TorPort` | 9050 | Porta SOCKS di Tor |
| `OnionAddrRange` | 127.42.42.0/24 | Range IP fittizio per .onion |
| `AllowInbound` | 0 | Permetti connessioni in ingresso |
| `AllowOutboundLocalhost` | 0 | Permetti connessioni a localhost |
| `IsolatePID` | 0 | Isola circuiti per PID |

---

## IsolatePID - stream isolation automatico

### Come funziona

Quando `IsolatePID 1`, torsocks usa il PID del processo come credenziale
di autenticazione SOCKS5:

```
Processo curl (PID 12345):
  torsocks → SOCKS5 AUTH: username="12345" password=""
  Tor (con IsolateSOCKSAuth) → circuito dedicato per PID 12345

Processo wget (PID 12346):
  torsocks → SOCKS5 AUTH: username="12346" password=""
  Tor → circuito DIVERSO per PID 12346
```

### Requisito torrc

Per funzionare, `SocksPort` deve avere `IsolateSOCKSAuth`:

```ini
# torrc
SocksPort 9050 IsolateSOCKSAuth
```

### Implicazioni

- Due esecuzioni di `torsocks curl` usano circuiti diversi (PID diversi)
- Un browser e un terminale usano circuiti diversi
- Fork dello stesso processo: il figlio eredita il PID (e il circuito) del padre - attenzione con applicazioni multi-processo

---

## Uso pratico

### Comandi comuni

```bash
# Verifica IP via Tor
torsocks curl https://api.ipify.org

# Download via Tor
torsocks wget https://example.com/file.zip

# SSH via Tor
torsocks ssh user@server.com

# git via Tor
torsocks git clone https://github.com/user/repo.git

# pip via Tor
torsocks pip3 install package_name

# Python script via Tor
torsocks python3 myscript.py

# Accesso a servizi .onion
torsocks curl http://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/
```

### Comandi che NON funzionano

```bash
# ping → ICMP, non TCP
torsocks ping example.com
# Errore: ICMP non supportato

# traceroute → ICMP/UDP
torsocks traceroute example.com
# Errore

# dig → UDP porta 53
torsocks dig example.com
# [warn] UDP not supported, dropping connection

# nmap → vari protocolli
torsocks nmap -sV example.com
# Funziona SOLO con -sT (TCP connect scan), non con SYN scan
```

---

## Shell interattiva torsocksificata

```bash
# Apri una shell dove TUTTO passa da Tor
torsocks bash

# Ora ogni comando in questa shell usa Tor
$ curl https://api.ipify.org     # → IP exit Tor
$ wget https://example.com       # → via Tor
$ ssh user@server.com            # → via Tor
$ python3 -c "import urllib.request; print(urllib.request.urlopen('https://api.ipify.org').read())"
                                  # → via Tor

$ exit  # torna alla shell normale
```

**Attenzione**: nella shell torsocksificata, *tutti* i comandi passano da Tor,
inclusi quelli che non dovrebbero (es. `apt update` sarà lentissimo).

---

## torsocks on - attivazione permanente

### Come funziona

```bash
# Attivare torsocks per la sessione corrente
source torsocks on
# oppure
. torsocks on

# Ora TUTTI i comandi passano da Tor automaticamente
curl https://api.ipify.org     # → IP Tor, senza prefix "torsocks"
wget https://example.com       # → via Tor

# Verificare stato
torsocks show
# Tor mode activated. Every command will be torified for this shell.

# Disattivare
source torsocks off
# oppure
. torsocks off
```

### Internamente

`torsocks on` esporta la variabile `LD_PRELOAD`:

```bash
# Dopo "source torsocks on":
echo $LD_PRELOAD
# /usr/lib/x86_64-linux-gnu/torsocks/libtorsocks.so

# Dopo "source torsocks off":
echo $LD_PRELOAD
# (vuoto)
```

### Differenza con `torsocks bash`

| Metodo | Scope | Annidamento |
|--------|-------|-------------|
| `torsocks bash` | Nuova shell figlia | Non affetta la shell padre |
| `source torsocks on` | Shell corrente | Modifica la sessione in corso |
| `torsocks comando` | Singolo comando | Nessun effetto persistente |

---

---

> **Continua in**: [torsocks Avanzato](torsocks-avanzato.md) per variabili
> d'ambiente, edge cases, debugging avanzato, analisi di sicurezza e confronto con proxychains.

---

## Vedi anche

- [torsocks Avanzato](torsocks-avanzato.md) - Variabili, edge cases, debugging, confronto
- [ProxyChains - Guida Completa](proxychains-guida-completa.md) - Alternativa a torsocks
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - torsocks e prevenzione DNS leak
- [Controllo Circuiti e NEWNYM](controllo-circuiti-e-newnym.md) - IsolatePID e circuiti
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
