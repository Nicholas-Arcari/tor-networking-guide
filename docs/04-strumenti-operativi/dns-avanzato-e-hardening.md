# DNS Avanzato - resolv.conf, Leak Dettagliati e Hardening

Interazione con /etc/resolv.conf, internals DNS di proxychains e torsocks,
risoluzione via ControlPort, .onion, scenari di DNS leak e hardening completo.

Estratto da [Tor e DNS - Risoluzione](tor-e-dns-risoluzione.md).

---

## Indice

- [Interazione con /etc/resolv.conf](#interazione-con-etcresolvconf)
- [DNS e proxychains - proxy_dns internals](#dns-e-proxychains--proxy_dns-internals)
- [DNS e torsocks](#dns-e-torsocks)
- [DNS via ControlPort - risoluzione manuale](#dns-via-controlport--risoluzione-manuale)
- [Risoluzione .onion](#risoluzione-onion)
- [DNS leak - scenari dettagliati](#dns-leak--scenari-dettagliati)
- [Hardening DNS completo](#hardening-dns-completo)

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

## DNS e proxychains - proxy_dns internals

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

## DNS via ControlPort - risoluzione manuale

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

## DNS leak - scenari dettagliati

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
   (Comeser, Parma). L'ho scoperto con `tcpdump -i eth0 port 53` - vedevo query DNS
   in chiaro per ogni sito che visitavo.

3. **proxychains e proxy_dns**: nella configurazione iniziale avevo commentato
   `proxy_dns` in `proxychains4.conf`. Tutto funzionava apparentemente, ma ogni
   hostname veniva risolto localmente prima di passare a Tor. Ho verificato con
   `PROXYCHAINS_DEBUG=1 proxychains curl https://check.torproject.org` - il debug
   output mostrava la risoluzione locale.

4. **DNSPort 5353 vs 53**: ho scelto 5353 per non dover eseguire Tor come root
   (le porte sotto 1024 richiedono privilegi). Funziona perfettamente con la
   regola iptables di redirect, ma le applicazioni che hardcodano DNS su porta 53
   devono essere intercettate con iptables REDIRECT.

La regola d'oro: **mai fidarsi che il DNS passi da Tor - verificare sempre con
tcpdump**. Un singolo leak DNS annulla tutta la protezione del circuito Tor.

---

## Vedi anche

- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Scenari di leak e prevenzione multilivello
- [ProxyChains - Guida Completa](proxychains-guida-completa.md) - proxy_dns e intercettazione DNS
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - DNSPort con TransPort
- [Verifica IP, DNS e Leak](verifica-ip-dns-e-leak.md) - Test DNS leak con tcpdump
- [Hardening di Sistema](../05-sicurezza-operativa/hardening-sistema.md) - systemd-resolved e iptables DNS
