# Tor e DNS — Risoluzione, Leak e Automapping

La risoluzione DNS è uno dei vettori di deanonimizzazione più sottovalutati nell'uso
di Tor. Questo documento analizza l'intera catena di risoluzione DNS quando si usa
Tor: dal momento in cui un'applicazione richiede un hostname fino alla risposta che
arriva dall'exit node.

> **Vedi anche**: [DNS Leak](../05-sicurezza-operativa/dns-leak.md) per la prevenzione
> dei leak, [ProxyChains](./proxychains-guida-completa.md) per `proxy_dns`,
> [torrc Guida Completa](../02-installazione-e-configurazione/torrc-guida-completa.md)
> per la configurazione DNSPort.

---

## Indice

- [Come funziona la risoluzione DNS normale](#come-funziona-la-risoluzione-dns-normale)
- [Il problema: DNS e anonimato](#il-problema-dns-e-anonimato)
- [Come Tor risolve il DNS](#come-tor-risolve-il-dns)
- [DNSPort — il resolver locale di Tor](#dnsport--il-resolver-locale-di-tor)
- [AutomapHostsOnResolve — il meccanismo di mapping](#automaphostsonresolve--il-meccanismo-di-mapping)
- [SOCKS5 remote DNS resolution](#socks5-remote-dns-resolution)
- [Interazione con systemd-resolved](#interazione-con-systemd-resolved)
- [Interazione con /etc/resolv.conf](#interazione-con-etcresolvconf)
- [DNS e proxychains — proxy_dns internals](#dns-e-proxychains--proxy_dns-internals)
- [DNS e torsocks](#dns-e-torsocks)
- [DNS via ControlPort — risoluzione manuale](#dns-via-controlport--risoluzione-manuale)
- [Risoluzione .onion](#risoluzione-onion)
- [DNS leak — scenari dettagliati](#dns-leak--scenari-dettagliati)
- [Hardening DNS completo](#hardening-dns-completo)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Come funziona la risoluzione DNS normale

Prima di capire come Tor gestisce il DNS, è essenziale capire il flow normale:

```
Applicazione chiama getaddrinfo("example.com")
  → glibc legge /etc/nsswitch.conf
  → nsswitch: "hosts: files dns" → prima /etc/hosts, poi DNS
  → glibc legge /etc/resolv.conf → trova "nameserver 192.168.1.1"
  → UDP pacchetto DNS query (porta 53) → router locale
  → router forwarda a DNS ISP (es. Comeser: 62.94.0.1)
  → risposta DNS → IP 93.184.216.34
  → applicazione fa connect(93.184.216.34)
```

Ogni passaggio è un potenziale leak:

| Punto | Chi vede | Cosa vede |
|-------|----------|-----------|
| `/etc/resolv.conf` | Sistema locale | Quale DNS server è configurato |
| UDP porta 53 → router | Router/ISP | Quale dominio stai risolvendo |
| DNS ISP | ISP (Comeser nel mio caso) | Tutti i domini che visiti |
| Risposta DNS | Chiunque intercetti | Associazione hostname→IP |

Il DNS è **in chiaro** (UDP porta 53) e **non autenticato**. Qualsiasi
osservatore tra te e il DNS server vede esattamente dove stai navigando.

---

## Il problema: DNS e anonimato

Quando usi Tor senza precauzioni DNS:

```
SCENARIO PERICOLOSO:
[App] → getaddrinfo("target.com") → DNS in chiaro al tuo ISP ← LEAK!
[App] → connect(IP) → via SOCKS5 → Tor → exit → target.com

L'ISP vede: "L'utente ha risolto target.com alle 14:32"
Tor protegge: la connessione TCP all'IP
Risultato: l'ISP sa esattamente cosa stai visitando
```

Anche se il traffico TCP è anonimo via Tor, la query DNS rivela la destinazione.
Questo è il **DNS leak** nella sua forma più basilare: la risoluzione del nome
avviene fuori dal tunnel Tor.

### Correlazione DNS + timing

Un avversario che osserva sia il DNS che il traffico Tor può:

1. Vedere query DNS per `target.com` dal tuo IP reale
2. Vedere connessione Tor dallo stesso IP 500ms dopo
3. Correlare con certezza: sei tu che stai visitando `target.com` via Tor

La finestra di correlazione è molto stretta (millisecondi), rendendo l'attacco
quasi deterministico.

---

## Come Tor risolve il DNS

Tor offre tre meccanismi per risolvere DNS in modo sicuro:

### 1. SOCKS5 con hostname (remote resolution)

Il metodo preferito. L'applicazione invia l'hostname (non l'IP) al proxy SOCKS5:

```
SOCKS5 flow con hostname:
  Client → SOCKS5 proxy (Tor): CONNECT "example.com:443"
  Tor riceve l'hostname come stringa
  Tor lo inoltra nel circuito come RELAY_BEGIN
  L'exit node risolve il DNS localmente
  L'exit node si connette all'IP risultante
  → Nessuna risoluzione DNS locale
```

A livello di protocollo SOCKS5:

```
Client → Tor:
  VER: 0x05
  CMD: 0x01 (CONNECT)
  ATYP: 0x03 (DOMAINNAME)  ← chiave: hostname, non IP
  DST.ADDR: length + "example.com"
  DST.PORT: 0x01BB (443)

Tor → Circuito:
  RELAY_BEGIN cell:
    Payload: "example.com:443\0"
    → L'exit node riceve l'hostname e fa DNS resolve
```

### 2. DNSPort — resolver locale dedicato

Tor espone una porta UDP che accetta query DNS standard e le risolve via circuito:

```
[App] → query DNS UDP → 127.0.0.1:5353 (DNSPort Tor)
  → Tor incapsula in RELAY_RESOLVE cell
  → Circuito Tor → exit node
  → Exit node fa DNS query
  → Risposta DNS torna nel circuito
  → Tor risponde alla query UDP locale
```

### 3. TransPort con AutomapHosts

Per il transparent proxy, Tor mappa automaticamente hostname a IP fittizi:

```
[App] → DNS query "example.com" → DNSPort
  → Tor assegna 10.192.0.42 come IP fittizio
  → Risponde all'app: "example.com = 10.192.0.42"
[App] → connect(10.192.0.42) → iptables REDIRECT → TransPort 9040
  → Tor vede 10.192.0.42 → sa che è "example.com"
  → RELAY_BEGIN "example.com:443"
```

---

## DNSPort — il resolver locale di Tor

### Configurazione

```ini
# torrc
DNSPort 5353
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
```

### Come funziona internamente

DNSPort apre un socket UDP su `127.0.0.1:5353`. Quando riceve una query DNS:

1. **Parsing della query**: Tor decodifica il pacchetto DNS (formato RFC 1035)
2. **Creazione RELAY_RESOLVE**: genera una cella `RELAY_RESOLVE` con l'hostname
3. **Invio nel circuito**: la cella viaggia attraverso Guard → Middle → Exit
4. **Risoluzione remota**: l'exit node esegue la query DNS con il suo resolver
5. **Risposta RELAY_RESOLVED**: l'exit invia la risposta nel circuito
6. **Composizione risposta DNS**: Tor costruisce un pacchetto DNS di risposta
7. **Invio all'applicazione**: risposta UDP verso l'applicazione richiedente

### Tipi di query supportati

| Tipo | Supporto | Note |
|------|----------|------|
| A (IPv4) | Completo | Risoluzione standard |
| AAAA (IPv6) | Parziale | Dipende da `ClientUseIPv6` |
| PTR (reverse) | Completo | Per `.onion` e IP normali |
| CNAME | Completo | Segue la catena |
| MX, TXT, SRV | **No** | Non supportati dal protocollo RELAY_RESOLVE |
| DNSSEC | **No** | L'exit risolve, non valida |

### Limitazione critica: no DNSSEC

Tor non supporta DNSSEC end-to-end. Questo significa che:
- L'exit node potrebbe manipolare le risposte DNS (DNS spoofing)
- Non c'è modo di verificare l'autenticità della risposta
- HTTPS (certificati TLS) è l'unica protezione contro exit malevoli

### Performance

Le query DNS via Tor hanno latenza significativamente più alta:

```
DNS diretto (ISP Comeser, Parma):     ~15ms
DNS via Tor (DNSPort):                 ~200-800ms
DNS via SOCKS5 remote:                 ~150-600ms
```

La differenza è dovuta ai 3 hop del circuito + il tempo di risoluzione dell'exit.

---

## AutomapHostsOnResolve — il meccanismo di mapping

### Funzionamento

Quando `AutomapHostsOnResolve 1`, Tor mantiene una tabella interna che mappa
hostname a IP fittizi dal range `VirtualAddrNetworkIPv4`:

```
Tabella AutomapHosts (in memoria):
  example.com      → 10.192.0.1
  github.com       → 10.192.0.2
  api.ipify.org    → 10.192.0.3
  duckduckgo.com   → 10.192.0.4
  abcxyz.onion     → 10.192.0.5
```

Questa tabella esiste solo in memoria e viene svuotata al restart di Tor.

### Il range VirtualAddrNetwork

```ini
VirtualAddrNetworkIPv4 10.192.0.0/10
```

Questo definisce 4.194.304 indirizzi IP fittizi (da 10.192.0.0 a 10.255.255.255).
Ogni hostname risolvibile ottiene un IP da questo range.

**Attenzione**: il range non deve sovrapporsi a reti reali nella tua LAN. Il default
`10.192.0.0/10` è sicuro per la maggior parte delle configurazioni, ma se la tua
rete usa `10.0.0.0/8` potresti avere conflitti.

### Suffissi mappati

```ini
AutomapHostsSuffixes .onion,.exit
```

Di default mappa `.onion` e `.exit`. Con `AutomapHostsOnResolve 1` mappa tutti
gli hostname, necessario per il transparent proxy.

### Ciclo di vita di un mapping

```
1. App: getaddrinfo("example.com") → query a DNSPort
2. Tor: hostname non in cache → assegna 10.192.0.42
3. Tor: risponde DNS A record: 10.192.0.42
4. App: connect(10.192.0.42:443)
5. Tor (TransPort): intercetta, cerca 10.192.0.42 nella tabella
6. Tor: trova "example.com", crea RELAY_BEGIN "example.com:443"
7. Circuito: exit risolve example.com realmente e si connette

Se l'app rifà la query:
8. App: getaddrinfo("example.com") → query a DNSPort
9. Tor: hostname in cache → restituisce 10.192.0.42 (stesso IP)
```

### TTL e cache

Tor gestisce il TTL delle risposte DNS cached:
- **Minimum TTL**: 60 secondi (hard-coded)
- **Maximum TTL**: 30 minuti per la cache interna
- **NEWNYM**: svuota la cache DNS (importante per cambio identità)

---

## SOCKS5 remote DNS resolution

### Il metodo più sicuro

Quando un'applicazione usa correttamente SOCKS5 con hostname:

```
curl --socks5-hostname 127.0.0.1:9050 https://example.com
                ↑
                "--socks5-hostname" è la chiave:
                invia l'hostname al proxy, NON lo risolve localmente
```

Confronto:
```bash
# SICURO: hostname inviato a Tor, DNS remoto
curl --socks5-hostname 127.0.0.1:9050 https://example.com

# INSICURO: DNS locale, poi IP inviato a Tor
curl --socks5 127.0.0.1:9050 https://example.com
#     ↑ senza "-hostname" → risolve localmente prima!
```

La differenza è una singola flag, ma la conseguenza sulla privacy è totale.

### Come le applicazioni inviano hostname via SOCKS5

Non tutte le applicazioni supportano SOCKS5 con hostname. Il comportamento dipende
da come l'applicazione gestisce il proxy:

| Applicazione | Metodo | DNS remoto? |
|-------------|--------|-------------|
| curl (`--socks5-hostname`) | ATYP=0x03 | Sì |
| curl (`--socks5`) | Risolve, ATYP=0x01 | **No** |
| Firefox (proxy SOCKS5 + remote DNS) | ATYP=0x03 | Sì |
| proxychains (`proxy_dns`) | Thread DNS → SOCKS5 | Sì (con hack) |
| torsocks | Intercetta getaddrinfo | Sì |
| Python requests + PySocks | Dipende da config | Dipende |
| git (`socks5h://`) | ATYP=0x03 | Sì |
| ssh (`ProxyCommand nc -X 5`) | ATYP=0x03 | Sì |

---

## Interazione con systemd-resolved

Kali Linux (e molte distribuzioni Debian-based recenti) usano `systemd-resolved`
come DNS resolver di sistema.

### Il problema

```
systemd-resolved ascolta su 127.0.0.53:53
/etc/resolv.conf → "nameserver 127.0.0.53"

Quando un'app fa DNS senza passare da Tor:
  App → getaddrinfo() → glibc → 127.0.0.53 → systemd-resolved
  systemd-resolved → DNS upstream (ISP) → LEAK!
```

### Verifica dello stato

```bash
# Controllare se systemd-resolved è attivo
systemctl status systemd-resolved

# Vedere la configurazione DNS corrente
resolvectl status

# Output tipico su Kali:
# Link 2 (eth0):
#   Current Scopes: DNS
#   DefaultRoute setting: yes
#   LLMNR setting: yes        ← potenziale leak!
#   MulticastDNS setting: no
#   DNSOverTLS setting: no
#   DNSSEC setting: no
#   Current DNS Server: 192.168.1.1
```

### Mitigazione

Per impedire leak DNS via systemd-resolved quando usi Tor:

```bash
# Opzione 1: Disabilitare systemd-resolved (drastico)
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
# Creare /etc/resolv.conf manuale:
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

# Opzione 2: Configurare resolved per usare DNSPort di Tor
sudo mkdir -p /etc/systemd/resolved.conf.d/
cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/tor.conf
[Resolve]
DNS=127.0.0.1#5353
LLMNR=no
MulticastDNS=no
EOF
sudo systemctl restart systemd-resolved
```

### LLMNR e mDNS — leak silenziosi

`systemd-resolved` abilita per default:
- **LLMNR** (Link-Local Multicast Name Resolution): risolve nomi sulla LAN via multicast
- **mDNS** (Multicast DNS): scoperta servizi sulla rete locale

Entrambi inviano pacchetti multicast sulla rete locale, rivelando quali hostname
stai cercando di risolvere. Anche con Tor attivo, una query LLMNR per un hostname
che non è nel DNS può leak sulla LAN.

---

## Interazione con /etc/resolv.conf

### Anatomia del file

```bash
cat /etc/resolv.conf
# Sul mio Kali (Parma, Comeser ISP):
# nameserver 192.168.1.1     ← router locale
# nameserver 127.0.0.53      ← systemd-resolved (se attivo)
```

### Il problema con NetworkManager

NetworkManager riscrive `/etc/resolv.conf` ad ogni connessione di rete:

```
Connessione WiFi → DHCP → ottieni DNS ISP → NetworkManager aggiorna resolv.conf
```

Qualsiasi configurazione manuale (es. puntare a 127.0.0.1 per Tor) viene
sovrascritta. Soluzioni:

```bash
# Opzione 1: Rendere resolv.conf immutabile
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
sudo chattr +i /etc/resolv.conf

# Opzione 2: Configurare NetworkManager per non toccare DNS
# /etc/NetworkManager/conf.d/dns.conf
[main]
dns=none

# Opzione 3: Usare /etc/NetworkManager/dispatcher.d/ per override post-connessione
```

---

## DNS e proxychains — proxy_dns internals

### Come proxy_dns funziona

Quando `proxy_dns` è abilitato in `/etc/proxychains4.conf`:

```
proxychains curl https://example.com

1. curl chiama getaddrinfo("example.com")
2. proxychains intercetta getaddrinfo() via LD_PRELOAD
3. Invece di risolvere localmente, proxychains:
   a. Genera un IP fittizio dal range remote_dns_subnet (224.x.x.x)
   b. Memorizza: 224.0.0.1 → "example.com"
   c. Restituisce 224.0.0.1 a curl
4. curl chiama connect(224.0.0.1:443)
5. proxychains intercetta connect()
6. Riconosce 224.0.0.1 → cerca nella tabella → trova "example.com"
7. Invia a Tor via SOCKS5: CONNECT "example.com:443" (ATYP=0x03)
8. Tor risolve "example.com" via exit node
```

### Il range remote_dns_subnet

```ini
# /etc/proxychains4.conf
remote_dns_subnet 224
```

Il valore `224` significa che gli IP fittizi sono nel range `224.0.0.0/8`
(che normalmente è multicast, quindi non conflitto con IP reali).

### Limitazione: race condition DNS

Se un'applicazione fa DNS in un thread separato prima del connect(), proxychains
potrebbe non intercettare la query. Questo è un edge case raro ma possibile
con applicazioni multi-threaded complesse.

---

## DNS e torsocks

### Meccanismo

torsocks intercetta le chiamate DNS a un livello più basso di proxychains:

```
torsocks curl https://example.com

1. curl chiama getaddrinfo("example.com")
2. libtorsocks.so intercetta getaddrinfo()
3. torsocks NON risolve localmente
4. torsocks invia direttamente a Tor via SOCKS5 con hostname
5. Non serve mapping fittizio: l'hostname va diretto nel circuito
```

Differenza chiave: torsocks non usa IP fittizi. Invia l'hostname direttamente
al proxy SOCKS5, che è il metodo più pulito e sicuro.

### Blocco DNS UDP

torsocks blocca attivamente le query DNS UDP dirette:

```
[warn] torsocks[12345]: sendto: Connection to a DNS server (8.8.8.8:53)
  is not allowed. UDP is not supported by Tor, dropping connection
```

---

## DNS via ControlPort — risoluzione manuale

### RESOLVE command

Il ControlPort supporta la risoluzione DNS manuale:

```
$ echo -e "AUTHENTICATE\r\nRESOLVE example.com\r\nQUIT\r\n" | nc 127.0.0.1 9051
250 OK
250 CNAME=example.com
250-address=93.184.216.34
250 OK
```

### Python con Stem

```python
from stem.control import Controller

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    
    # Risoluzione DNS via Tor
    result = ctrl.resolve("example.com")
    print(f"example.com → {result}")
    
    # Risoluzione inversa
    result = ctrl.resolve("93.184.216.34", reverse=True)
    print(f"93.184.216.34 → {result}")
```

Utile per script che necessitano di risolvere hostname via Tor senza usare
proxychains o torsocks.

---

## Risoluzione .onion

Gli indirizzi `.onion` non esistono nel DNS pubblico. La risoluzione funziona
diversamente:

```
1. App richiede: "abcdef...xyz.onion"
2. Tor riconosce il suffisso .onion
3. NON fa query DNS
4. Estrae la chiave pubblica dall'indirizzo (Ed25519 per v3)
5. Calcola l'hash per trovare gli HSDir (responsible HSDirs)
6. Scarica il descriptor del servizio dagli HSDir
7. Decifra il descriptor con la chiave pubblica
8. Ottiene gli introduction points
9. Costruisce circuito di rendezvous
```

### Risoluzione .onion con AutomapHosts

Quando `AutomapHostsOnResolve 1`:

```
getaddrinfo("abcdef...xyz.onion")
  → Tor risponde: 10.192.0.42 (IP fittizio)
  → App si connette a 10.192.0.42
  → Tor riconosce il mapping → avvia protocollo rendezvous
```

Questo permette ad applicazioni che non supportano nativamente `.onion` di
accedere ai servizi hidden tramite il transparent proxy o DNSPort.

---

## DNS leak — scenari dettagliati

### Scenario 1: Applicazione che ignora il proxy

```
Firefox con proxy SOCKS5 configurato MA "DNS over SOCKS" disabilitato:
  Firefox → getaddrinfo("target.com") → DNS ISP (LEAK!)
  Firefox → connect(IP) → SOCKS5 → Tor → exit → target
  
  Fix: network.proxy.socks_remote_dns = true in about:config
```

### Scenario 2: Dual-stack IPv6

```
Sistema con IPv6 attivo:
  App → query DNS AAAA "target.com" → DNS IPv6 (non intercettato da Tor!)
  
  Fix: disabilitare IPv6 o filtrare con ip6tables
```

### Scenario 3: DNS prefetch del browser

```
Browser con prefetch attivo:
  Pagina contiene link a "other-site.com"
  Browser fa DNS prefetch → query DNS diretta (LEAK!)
  
  Fix: network.dns.disablePrefetch = true
```

### Scenario 4: WebRTC

```
Browser con WebRTC:
  STUN request → rivela IP locale e pubblico → LEAK
  
  Fix: media.peerconnection.enabled = false
```

### Scenario 5: Captive portal detection

```
NetworkManager/systemd-networkd:
  Controlla connectivity → DNS + HTTP in chiaro → LEAK
  
  Fix: disabilitare connectivity check
```

---

## Hardening DNS completo

### Livello 1: torrc

```ini
DNSPort 5353
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
ClientUseIPv6 0
```

### Livello 2: Sistema

```bash
# Bloccare DNS diretto con iptables
# Permettere solo DNS a 127.0.0.1:5353 (DNSPort Tor)
iptables -A OUTPUT -p udp --dport 53 -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j DROP
iptables -A OUTPUT -p tcp --dport 53 -j DROP
```

### Livello 3: Applicazione

```
Firefox about:config:
  network.proxy.socks_remote_dns = true
  network.dns.disablePrefetch = true
  network.dns.disableIPv6 = true
  
proxychains4.conf:
  proxy_dns
  remote_dns_subnet 224
```

### Livello 4: Monitoraggio

```bash
# Monitorare query DNS in uscita (dovrebbero essere zero se tutto è configurato)
sudo tcpdump -i eth0 port 53 -n

# Se vedi pacchetti → c'è un leak da investigare
```

---

## Nella mia esperienza

La configurazione DNS è stata la parte più insidiosa del mio setup Tor su Kali.
I problemi che ho incontrato:

1. **systemd-resolved che sovrascriveva tutto**: dopo ogni riconnessione WiFi,
   `/etc/resolv.conf` tornava al DNS del router. Ho risolto con `chattr +i`
   dopo aver configurato manualmente il file.

2. **Firefox con DNS leak nonostante proxy SOCKS5**: avevo configurato il proxy
   manualmente in Firefox ma non avevo abilitato `network.proxy.socks_remote_dns`.
   Risultato: il traffico HTTP passava da Tor, ma il DNS andava diretto al mio ISP
   (Comeser, Parma). L'ho scoperto con `tcpdump -i eth0 port 53` — vedevo query DNS
   in chiaro per ogni sito che visitavo.

3. **proxychains e proxy_dns**: nella configurazione iniziale avevo commentato
   `proxy_dns` in `proxychains4.conf`. Tutto funzionava apparentemente, ma ogni
   hostname veniva risolto localmente prima di passare a Tor. Ho verificato con
   `PROXYCHAINS_DEBUG=1 proxychains curl https://check.torproject.org` — il debug
   output mostrava la risoluzione locale.

4. **DNSPort 5353 vs 53**: ho scelto 5353 per non dover eseguire Tor come root
   (le porte sotto 1024 richiedono privilegi). Funziona perfettamente con la
   regola iptables di redirect, ma le applicazioni che hardcodano DNS su porta 53
   devono essere intercettate con iptables REDIRECT.

La regola d'oro: **mai fidarsi che il DNS passi da Tor — verificare sempre con
tcpdump**. Un singolo leak DNS annulla tutta la protezione del circuito Tor.

---

## Vedi anche

- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) — Scenari di leak e prevenzione multilivello
- [ProxyChains — Guida Completa](proxychains-guida-completa.md) — proxy_dns e intercettazione DNS
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) — DNSPort con TransPort
- [Verifica IP, DNS e Leak](verifica-ip-dns-e-leak.md) — Test DNS leak con tcpdump
- [Hardening di Sistema](../05-sicurezza-operativa/hardening-sistema.md) — systemd-resolved e iptables DNS
