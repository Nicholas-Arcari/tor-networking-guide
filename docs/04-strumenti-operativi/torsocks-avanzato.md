# torsocks Avanzato - Variabili, Edge Cases, Debugging e Confronto

Variabili d'ambiente, edge cases e problemi noti, debugging avanzato,
analisi critica della sicurezza, e confronto dettagliato con proxychains.

Estratto da [torsocks](torsocks.md).

---

## Indice

- [Variabili d'ambiente](#variabili-dambiente)
- [Edge cases e problemi noti](#edge-cases-e-problemi-noti)
- [Debugging avanzato](#debugging-avanzato)
- [Sicurezza di torsocks - analisi critica](#sicurezza-di-torsocks--analisi-critica)
- [torsocks vs proxychains - confronto dettagliato](#torsocks-vs-proxychains--confronto-dettagliato)

---

## Variabili d'ambiente

```bash
# File di configurazione custom
TORSOCKS_CONF_FILE=/path/to/custom.conf torsocks curl example.com

# Livello di log (1=error, 2=warn, 3=notice, 4=info, 5=debug)
TORSOCKS_LOG_LEVEL=5 torsocks curl example.com

# File di log (invece di stderr)
TORSOCKS_LOG_FILE_PATH=/tmp/torsocks.log torsocks curl example.com

# Permettere connessioni in ingresso
TORSOCKS_ALLOW_INBOUND=1 torsocks ./myserver

# Override indirizzo Tor
TORSOCKS_TOR_ADDRESS=127.0.0.1 torsocks curl example.com

# Override porta Tor
TORSOCKS_TOR_PORT=9060 torsocks curl example.com

# Isolamento PID
TORSOCKS_ISOLATE_PID=1 torsocks curl example.com

# Username SOCKS5 per isolamento manuale
TORSOCKS_USERNAME="mia-sessione-1" torsocks curl example.com
TORSOCKS_PASSWORD="random123" torsocks curl example.com
```

---

## Edge cases e problemi noti

### Binari Go staticamente linkati

Go compila binari statici per default. Non usano la libc dinamica → LD_PRELOAD
non funziona:

```bash
torsocks ./mio-programma-go
# Il programma si connette DIRETTAMENTE, bypassando torsocks!
# NESSUN warning viene mostrato - silenziosamente insicuro

# Verifica se un binario è statico:
file ./mio-programma-go
# mio-programma-go: ELF 64-bit, statically linked
# ↑ "statically linked" = torsocks NON funziona

ldd ./mio-programma-go
# not a dynamic executable
# ↑ Conferma: nessuna libreria dinamica, torsocks inutile
```

**Workaround**: usare transparent proxy (iptables) o configurare il programma
Go per usare SOCKS5 nativamente (la maggior parte dei client HTTP Go supporta proxy).

### Java con JNI

Alcune applicazioni Java usano JNI per networking nativo. In questi casi,
le chiamate possono bypassare la libc:

```bash
torsocks java -jar myapp.jar
# Potrebbe funzionare per HTTP standard (via java.net)
# Ma JNI networking custom bypassa torsocks
```

### Node.js

Node.js usa libuv per I/O, che generalmente usa le syscall libc. Funziona
nella maggior parte dei casi:

```bash
torsocks node myapp.js
# Generalmente funziona per HTTP/HTTPS
# MA: DNS resolution in Node.js può usare c-ares (non libc)
#     c-ares potrebbe non essere intercettato
```

### Applicazioni multi-processo (fork)

Quando un processo fa `fork()`:
- Il figlio eredita `LD_PRELOAD` → torsocks funziona
- MA: se il figlio fa `exec()` con un binario setuid → LD_PRELOAD viene ignorato per sicurezza

```bash
# Esempio: sudo dentro torsocks
torsocks bash
$ sudo apt update    # sudo è setuid → LD_PRELOAD ignorato → LEAK!
```

---

## Debugging avanzato

### Log verbose

```bash
# Livello 5 (debug): mostra ogni syscall intercettata
TORSOCKS_LOG_LEVEL=5 torsocks curl https://api.ipify.org

# Output esempio:
# [debug] torsocks[23456]: connect: Connection to 127.0.0.1:9050
# [debug] torsocks[23456]: SOCKS5 sending method for auth
# [debug] torsocks[23456]: SOCKS5 received method for auth: 00
# [debug] torsocks[23456]: SOCKS5 sending connect request to: api.ipify.org:443
# [debug] torsocks[23456]: SOCKS5 received connect reply success
# [debug] torsocks[23456]: connect: Connection to api.ipify.org:443 was successful
```

### Verificare che libtorsocks sia caricato

```bash
# Metodo 1: controllare /proc/PID/maps
torsocks bash -c 'cat /proc/self/maps | grep torsocks'
# 7f8a1234000-7f8a1238000 r-xp ... /usr/lib/.../libtorsocks.so

# Metodo 2: ldd (per binari dinamici)
ldd $(which curl) | grep torsocks
# Non mostrerà torsocks (LD_PRELOAD non è in ldd)
# Ma conferma che curl è dinamico (può essere hooked)

# Metodo 3: strace per vedere l'hooking
strace -e trace=connect torsocks curl https://api.ipify.org 2>&1 | head -20
# connect(3, {sa_family=AF_INET, sin_port=htons(9050), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
# ↑ La connessione va a 127.0.0.1:9050 (Tor), non all'IP di destinazione
```

### Verificare che non ci siano leak

```bash
# In un terminale: tcpdump per catturare traffico non-Tor
sudo tcpdump -i eth0 -n 'not port 9050 and not port 9001 and not port 443' &

# In un altro terminale: usa torsocks
torsocks curl https://api.ipify.org

# Se tcpdump mostra pacchetti → c'è un leak
# Se tcpdump è silenzioso → torsocks funziona correttamente
```

---

## Sicurezza di torsocks - analisi critica

### Cosa protegge

| Vettore | Protetto? | Come |
|---------|-----------|------|
| Connessioni TCP | Sì | Redirect via SOCKS5 |
| DNS via getaddrinfo | Sì | Intercetta e risolve via Tor |
| UDP | Sì (blocca) | Intercetta sendto/sendmsg, DROP |
| DNS UDP diretto | Sì (blocca) | Bloccato con warning |

### Cosa NON protegge

| Vettore | Protetto? | Perché |
|---------|-----------|-------|
| Syscall dirette | **No** | LD_PRELOAD opera a livello libc, non kernel |
| Binari statici | **No** | Non usano libc dinamica |
| Binari setuid | **No** | LD_PRELOAD ignorato per sicurezza |
| io_uring | **No** | I/O asincrono kernel-level, bypassa libc |
| Raw socket | **No** | Richiede root, non passa per connect() |
| ICMP | **No** | Non usa connect(), usa raw socket |
| Fork + exec setuid | **No** | Figlio perde LD_PRELOAD |

### Scenari di leak possibili

1. **DNS prima dell'hook**: se un'applicazione risolve DNS prima che torsocks
   possa intercettare (es. libreria DNS custom caricata prima di libtorsocks)

2. **Subprocess senza LD_PRELOAD**: se un processo spawna un child che resetta
   l'ambiente (raro, ma possibile con `env -i`)

3. **IPv6 non bloccato**: torsocks blocca UDP IPv4 ma potrebbe non intercettare
   tutte le varianti IPv6 in alcune versioni

### Mitigazione: combinare con iptables

Per sicurezza massima, torsocks dovrebbe essere combinato con regole iptables
che bloccano tutto il traffico non-Tor:

```bash
# Bloccare traffico diretto (backup per se torsocks fallisce)
iptables -A OUTPUT -m owner --uid-owner $(id -u) -p tcp --dport 9050 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner $(id -u) -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner $(id -u) -j DROP
```

---

## torsocks vs proxychains - confronto dettagliato

| Criterio | torsocks | proxychains |
|----------|----------|-------------|
| **Blocco UDP** | Sì (attivo) | No (ignora) |
| **DNS handling** | Intercetta getaddrinfo | IP fittizio + mapping |
| **Chain proxy** | No (solo Tor) | Sì (multipli proxy) |
| **Output verbosità** | Minimo (solo warning) | Molto verboso |
| **Stream isolation** | IsolatePID automatico | Manuale (SOCKS auth) |
| **Compatibilità app** | Uguale (entrambi LD_PRELOAD) | Uguale |
| **Binari statici** | Non funziona | Non funziona |
| **Configurazione** | Semplice (solo Tor) | Più flessibile |
| **Proxy SOCKS4** | No | Sì |
| **Proxy HTTP** | No | Sì |
| **Manutenzione** | Attiva (Tor Project) | Attiva (community) |
| **Installazione** | apt install torsocks | apt install proxychains4 |
| **Shell mode** | `source torsocks on` | No equivalente |
| **Sicurezza DNS** | Superiore | Buona con proxy_dns |
| **Debug** | TORSOCKS_LOG_LEVEL | PROXYCHAINS_DEBUG |

### Quando usare quale

| Scenario | Scelta | Motivazione |
|----------|--------|-------------|
| Navigazione Firefox | proxychains | Più testato, output utile |
| Script automatizzati | torsocks | Meno rumore, blocco UDP |
| SSH via Tor | torsocks | IsolatePID, meno overhead |
| Chain di proxy (Tor → VPN → proxy) | proxychains | Supporta chain |
| Sicurezza massima | torsocks + iptables | Blocco UDP + fallback |
| Debug connessioni | proxychains | Output molto dettagliato |
| Shell completa via Tor | torsocks | `source torsocks on` |
| Accesso .onion | torsocks | OnionAddrRange nativo |

---

## Automazione con torsocks

### Script wrapper per verifica IP periodica

```bash
#!/bin/bash
# check-tor-ip.sh - Verifica periodica IP via torsocks

while true; do
    IP=$(torsocks curl -s --max-time 15 https://api.ipify.org 2>/dev/null)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ -n "$IP" ]; then
        echo "$TIMESTAMP | Tor IP: $IP"
    else
        echo "$TIMESTAMP | ERRORE: impossibile ottenere IP via Tor"
    fi
    
    sleep 300  # ogni 5 minuti
done
```

### Cron job anonimizzato

```bash
# crontab -e
# Scarica report ogni giorno alle 03:00 via Tor
0 3 * * * /usr/bin/torsocks /usr/bin/wget -q -O /tmp/report.html https://example.com/report 2>/dev/null
```

### systemd service con torsocks

```ini
# /etc/systemd/system/my-tor-service.service
[Unit]
Description=Servizio via Tor
After=tor@default.service
Requires=tor@default.service

[Service]
Type=simple
Environment=LD_PRELOAD=/usr/lib/x86_64-linux-gnu/torsocks/libtorsocks.so
ExecStart=/usr/bin/my-service
User=myuser
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

---

## Limiti fondamentali

| Limite | Descrizione | Workaround |
|--------|-------------|------------|
| LD_PRELOAD | Non funziona con binari statici o setuid | Transparent proxy (iptables) |
| No syscall dirette | Programmi che bypassano libc non sono coperti | Network namespace |
| No UDP | UDP è bloccato, non proxato | Nessuno (Tor non supporta UDP) |
| No ICMP | ping e traceroute impossibili | Nessuno |
| Multi-thread | Possibili race condition rare | IsolatePID mitiga |
| Setuid drop | sudo/su resetta LD_PRELOAD | Usare torsocks dentro sudo |
| Performance | Overhead LD_PRELOAD trascurabile, latenza Tor significativa | Nessuno |

---

## Nella mia esperienza

Uso principalmente proxychains per il mio workflow quotidiano su Kali perché:
- L'ho configurato per primo e ci sono abituato
- L'output verboso mi aiuta nel debugging durante lo studio
- Lo uso con Firefox tramite il profilo `tor-proxy`

Tuttavia, riconosco che torsocks è la scelta migliore dal punto di vista della
sicurezza per un motivo fondamentale: **blocca UDP attivamente**. Con proxychains,
un DNS leak via UDP passerebbe inosservato. Con torsocks, viene intercettato e
bloccato con un warning esplicito nel log.

Per script automatizzati e SSH, torsocks è superiore:
- `torsocks ssh user@server.com` è più pulito di `proxychains ssh user@server.com`
  (meno output di noise, IsolatePID automatico)
- Per cron job e automazione, il logging minimo di torsocks è preferibile

Ho testato entrambi con applicazioni Go statiche e nessuno dei due funziona -
il binario si connette direttamente bypassando il wrapper. Per quei casi, l'unica
soluzione è il transparent proxy con iptables o un network namespace dedicato.

Il consiglio: usare proxychains per il lavoro interattivo quotidiano (browser,
curl manuale, debug), e torsocks per automazione e script dove la sicurezza
UDP è prioritaria.

---

## Vedi anche

- [ProxyChains - Guida Completa](proxychains-guida-completa.md) - Confronto dettagliato con torsocks
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - torsocks e prevenzione DNS leak
- [Verifica IP, DNS e Leak](verifica-ip-dns-e-leak.md) - Test con torsocks
- [Controllo Circuiti e NEWNYM](controllo-circuiti-e-newnym.md) - IsolatePID e circuiti
- [Limitazioni nelle Applicazioni](../07-limitazioni-e-attacchi/limitazioni-applicazioni.md) - Quali app funzionano con torsocks
