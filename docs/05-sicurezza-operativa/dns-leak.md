# DNS Leak — Come Avvengono e Come Prevenirli

Questo documento analizza i DNS leak in contesto Tor: come avvengono a livello tecnico,
tutti gli scenari che li causano, come testarli, e le mitigazioni complete.

I DNS leak sono probabilmente la vulnerabilità più comune nell'uso di Tor da CLI,
perché molte applicazioni risolvono i DNS localmente prima di passare il traffico
al proxy. Nella mia esperienza, la configurazione corretta di `proxy_dns` in
proxychains e `DNSPort` nel torrc è stata fondamentale.

---

## Cos'è un DNS leak

Un DNS leak avviene quando una query DNS esce dal tuo sistema **senza passare
attraverso Tor**, rivelando al tuo ISP (o al resolver DNS) quale sito stai per
visitare.

```
SCENARIO CORRETTO (no leak):
Browser → "example.com" → ProxyChains → SOCKS5 (hostname) → Tor → Exit (risolve DNS)
  L'ISP vede: traffico cifrato verso Guard/Bridge
  L'ISP NON vede: "example.com"

SCENARIO CON LEAK:
Browser → DNS query "example.com" → ISP DNS resolver → risposta IP
       → poi → ProxyChains → SOCKS5 (IP) → Tor → Exit → Server
  L'ISP vede: query DNS per "example.com" IN CHIARO
  Il traffico HTTPS è protetto, ma l'ISP sa che visiti example.com
```

### Perché è grave

Anche se il contenuto della connessione è cifrato (HTTPS via Tor), il DNS leak rivela:
- **Quali siti visiti** (il dominio è in chiaro nella query DNS)
- **Quando li visiti** (timestamp della query)
- **Quanto spesso** (frequenza delle query)
- Questi metadata sono sufficienti per profilare il tuo comportamento

---

## Scenari che causano DNS leak

### 1. curl con --socks5 (senza hostname)

```bash
# LEAK! curl risolve localmente prima di inviare al proxy
curl --socks5 127.0.0.1:9050 https://example.com

# CORRETTO: hostname inviato al proxy, risolto da Tor
curl --socks5-hostname 127.0.0.1:9050 https://example.com
```

### 2. ProxyChains senza proxy_dns

Se `proxy_dns` non è attivo nel proxychains.conf, le chiamate `getaddrinfo()`
non vengono intercettate e il DNS esce in chiaro.

### 3. Applicazioni che bypassano il proxy

Applicazioni che non rispettano le impostazioni proxy del sistema o che usano
resolver DNS propri (es. Chrome con DoH verso Google).

### 4. systemd-resolved che risponde prima del proxy

Su molti sistemi Linux, `systemd-resolved` gestisce il DNS. Se è configurato con
un upstream esterno, le query possono essere risolte prima che l'applicazione
passi dal proxy.

### 5. IPv6 DNS query

Se IPv6 è attivo, il sistema potrebbe inviare query DNS AAAA via IPv6,
bypassando la configurazione proxy IPv4.

### 6. Applicazioni con DNS hardcoded

Alcune applicazioni hanno resolver DNS hardcoded (es. `8.8.8.8` di Google)
che bypassano `/etc/resolv.conf` e qualsiasi proxy DNS.

---

## Prevenzione completa dei DNS leak

### Livello 1: Configurazione Tor (torrc)

```ini
DNSPort 5353                    # Tor risponde alle query DNS sulla porta 5353
AutomapHostsOnResolve 1         # Mapping automatico degli hostname
```

### Livello 2: Configurazione ProxyChains

```ini
proxy_dns                       # Intercetta le chiamate DNS
remote_dns_subnet 224           # Subnet per IP fittizi del mapping DNS
```

### Livello 3: Configurazione applicativa

```bash
# curl: SEMPRE --socks5-hostname, MAI --socks5
curl --socks5-hostname 127.0.0.1:9050 https://example.com

# Firefox: "Proxy DNS when using SOCKS v5" attivo nelle impostazioni proxy

# git: usare socks5h (h = hostname resolution via proxy)
git config --global http.proxy socks5h://127.0.0.1:9050
```

### Livello 4: Configurazione di sistema

```bash
# Disabilitare IPv6
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1

# Configurare /etc/resolv.conf per usare il DNS di Tor
# (opzionale e rischioso — se Tor non è attivo, il DNS non funziona)
# nameserver 127.0.0.1
```

### Livello 5: Firewall (protezione massima)

Per impedire fisicamente che query DNS escano senza passare da Tor:

```bash
# Blocca tutto il DNS in uscita tranne quello di Tor
sudo iptables -A OUTPUT -p udp --dport 53 -m owner ! --uid-owner debian-tor -j DROP
sudo iptables -A OUTPUT -p tcp --dport 53 -m owner ! --uid-owner debian-tor -j DROP
```

Questo blocca tutte le query DNS (porta 53) che non provengono dal processo Tor
(utente `debian-tor`). Qualsiasi applicazione che tenta di fare DNS diretto viene
bloccata.

---

## Nella mia esperienza

La mia configurazione previene i DNS leak a due livelli:
1. `proxy_dns` in proxychains (intercetta DNS a livello applicativo)
2. `DNSPort 5353` nel torrc (Tor come resolver DNS locale)

Non ho implementato il firewall iptables perché uso Tor solo per applicazioni
specifiche (non system-wide). Ma per un setup dove voglio la massima protezione,
il firewall sarebbe il passo successivo.

Il test rapido che uso:
```bash
proxychains curl -s https://check.torproject.org/api/ip | grep IsTor
# {"IsTor":true,...} → OK, nessun leak evidente
```
