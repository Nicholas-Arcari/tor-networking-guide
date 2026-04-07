# Ricognizione Anonima — OSINT via Tor

Questo documento analizza come utilizzare Tor per attività di ricognizione e
OSINT (Open Source Intelligence) anonima: raccolta di informazioni da fonti
pubbliche senza rivelare la propria identità o interesse.

> **Vedi anche**: [ProxyChains](../04-strumenti-operativi/proxychains-guida-completa.md),
> [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md),
> [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md).

---

## Indice

- [OSINT e anonimato — perché serve](#osint-e-anonimato--perché-serve)
- [Setup per ricognizione anonima](#setup-per-ricognizione-anonima)
- [Strumenti OSINT via Tor](#strumenti-osint-via-tor)
- [Ricognizione web](#ricognizione-web)
- [Ricognizione DNS e domini](#ricognizione-dns-e-domini)
- [Ricognizione social media](#ricognizione-social-media)
- [Raccolta informazioni su target](#raccolta-informazioni-su-target)
- [Anti-detection e rate limiting](#anti-detection-e-rate-limiting)
- [Gestione delle identità](#gestione-delle-identità)
- [OPSEC per OSINT](#opsec-per-osint)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## OSINT e anonimato — perché serve

### Il problema: tipping off

Quando fai ricognizione su un target, le tue query lasciano tracce:

```
Senza Tor:
  Tu (IP: 93.x.x.x, Comeser ISP, Parma) → DNS query "target.com"
  Tu → HTTP request a target.com → il server logga il tuo IP
  Tu → Google search "target.com vulnerabilità" → Google logga la query
  Tu → Shodan query per target IP → Shodan logga il tuo IP

Se il target monitora i propri log:
  "Qualcuno dall'IP 93.x.x.x sta facendo ricognizione su di noi"
  → Possono risalire a te (ISP → log → identità)
```

Con Tor, ogni query arriva da un exit node diverso:
- Il target non vede pattern coerente
- Non può risalire alla tua identità
- Non può determinare che le query provengono dalla stessa persona

### Scenari legittimi

| Scenario | Perché serve anonimato |
|----------|----------------------|
| Pentest (fase ricognizione) | Non alertare il target prima del test |
| Bug bounty | Ricognizione preliminare senza tipping off |
| Threat intelligence | Monitorare threat actors senza essere notati |
| Investigazione aziendale | Verificare fornitori/partner senza rivelare interesse |
| Ricerca accademica | Studiare infrastrutture senza bias |
| Giornalismo investigativo | Proteggere fonti e indagini in corso |

---

## Setup per ricognizione anonima

### Configurazione base

```bash
# 1. Tor attivo con bootstrap completo
sudo systemctl start tor@default.service
sudo journalctl -u tor@default.service | grep "Bootstrapped 100%"

# 2. Verificare connessione
proxychains curl -s https://api.ipify.org
# → IP exit Tor (non il tuo)

# 3. Verificare che l'IP sia riconosciuto come Tor
proxychains curl -s https://check.torproject.org/api/ip | grep IsTor
# → "IsTor":true
```

### Firewall restrittivo (raccomandato per OSINT)

```bash
# Bloccare tutto il traffico diretto — solo Tor può uscire
TOR_UID=$(id -u debian-tor)
iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -j DROP
```

### Stream isolation per OSINT

Per evitare correlazione tra diverse fasi della ricognizione:

```bash
# Query DNS: una sessione
curl --socks5-hostname 127.0.0.1:9050 --proxy-user "dns-recon:1" https://...

# Web scraping: sessione diversa
curl --socks5-hostname 127.0.0.1:9050 --proxy-user "web-recon:2" https://...

# Social media: ancora diversa
curl --socks5-hostname 127.0.0.1:9050 --proxy-user "social-recon:3" https://...
```

---

## Strumenti OSINT via Tor

### Strumenti compatibili con Tor

| Strumento | Via proxychains | Via torsocks | Nativamente | Note |
|-----------|:---:|:---:|:---:|------|
| curl | ✓ | ✓ | ✓ (--socks5-hostname) | Metodo più affidabile |
| wget | ✓ | ✓ | ✗ | Attenzione a DNS leak |
| theHarvester | ✓ | ✓ | ✗ | Lento via Tor |
| Recon-ng | ✓ | ✗ | ✗ | Alcuni moduli non funzionano |
| Maltego | ✗ | ✗ | Limitato | GUI Java, problematico |
| Shodan CLI | ✓ | ✓ | ✗ | API key necessaria |
| Amass | Parziale | Parziale | ✗ | Go binary, DNS diretto |
| whois | ✓ | ✓ | ✗ | TCP porta 43 |
| nmap | ✓ | ✗ | ✓ (--proxy) | Solo -sT (TCP connect) |
| dig | ✗ | ✗ | ✗ | UDP, non funziona |
| nslookup | ✗ | ✗ | ✗ | UDP |

### DNS via Tor

Poiché `dig` e `nslookup` usano UDP (non compatibile con Tor):

```bash
# Alternativa 1: tor-resolve (incluso con Tor)
tor-resolve example.com
# 93.184.216.34

# Alternativa 2: curl con DNS-over-HTTPS
proxychains curl -s "https://dns.google/resolve?name=example.com&type=A" | python3 -m json.tool

# Alternativa 3: Python con socket via torsocks
torsocks python3 -c "import socket; print(socket.getaddrinfo('example.com', 443))"
```

---

## Ricognizione web

### Raccolta informazioni base

```bash
# HTTP headers
proxychains curl -sI https://target.com | head -20

# Certificato TLS
proxychains curl -sv https://target.com 2>&1 | grep -E "subject:|issuer:|expire"

# robots.txt
proxychains curl -s https://target.com/robots.txt

# sitemap.xml
proxychains curl -s https://target.com/sitemap.xml

# Security headers
proxychains curl -sI https://target.com | grep -iE "x-frame|x-content|strict-transport|content-security"
```

### Tecnologie e framework

```bash
# Wappalyzer-style detection via headers
proxychains curl -sI https://target.com | grep -iE "^(server|x-powered-by|x-aspnet|x-generator):"

# Verifica CMS
proxychains curl -s https://target.com/wp-login.php > /dev/null && echo "WordPress"
proxychains curl -s https://target.com/administrator/ > /dev/null && echo "Joomla"
```

### Wayback Machine

```bash
# Pagine archiviate (non serve Tor per Wayback, ma per non rivelare interesse)
proxychains curl -s "https://web.archive.org/web/timemap/json?url=target.com&limit=10" | python3 -m json.tool
```

---

## Ricognizione DNS e domini

### Enumerazione sottodomini

```bash
# Via crt.sh (Certificate Transparency logs)
proxychains curl -s "https://crt.sh/?q=%.target.com&output=json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
domains = set(entry['name_value'] for entry in data)
for d in sorted(domains):
    print(d)
"

# Via API VirusTotal (richiede API key)
proxychains curl -s "https://www.virustotal.com/api/v3/domains/target.com/subdomains" \
  -H "x-apikey: YOUR_KEY"
```

### WHOIS via Tor

```bash
# WHOIS diretto (TCP porta 43, funziona via proxychains)
proxychains whois target.com

# Oppure via web API
proxychains curl -s "https://www.whoisxmlapi.com/whoisserver/WhoisService?domainName=target.com&outputFormat=JSON"
```

### Reverse DNS

```bash
# Reverse lookup via DoH
proxychains curl -s "https://dns.google/resolve?name=34.216.184.93.in-addr.arpa&type=PTR"
```

---

## Ricognizione social media

### OSINT su profili pubblici

```bash
# GitHub
proxychains curl -s "https://api.github.com/users/targetuser" | python3 -m json.tool

# LinkedIn (via ricerca pubblica)
proxychains curl -s "https://www.google.com/search?q=site:linkedin.com+%22targetname%22"

# Twitter/X (via profilo pubblico)
# I social media spesso bloccano Tor → usare API quando possibile
```

### Problemi con social media e Tor

| Piattaforma | Tor bloccato? | Workaround |
|-------------|:---:|------------|
| Google | Captcha frequente | Usare API, DuckDuckGo |
| LinkedIn | Spesso bloccato | API pubblica limitata |
| Twitter/X | Parzialmente | API con token |
| Facebook | Bloccato | .onion: facebookwkhpilnemxj7asaniu7vnjjbiltxjqhye3mhbshg7kx5tfyd.onion |
| GitHub | Funziona | API pubblica |
| Reddit | Funziona | API con rate limiting |
| Instagram | Bloccato | Limitato |

### DuckDuckGo come alternativa a Google

```bash
# DuckDuckGo non blocca Tor e non traccia
proxychains curl -s "https://html.duckduckgo.com/html/?q=target+info" | grep -oP 'href="[^"]*"'

# DuckDuckGo ha anche un onion service
# https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/
```

---

## Raccolta informazioni su target

### Infrastruttura

```bash
# IP e hosting
proxychains curl -s "https://ipinfo.io/$(tor-resolve target.com)" | python3 -m json.tool

# ASN lookup
proxychains curl -s "https://api.bgpview.io/ip/$(tor-resolve target.com)"

# Porte aperte (LENTO via Tor, solo TCP)
proxychains nmap -sT -Pn --top-ports 100 target.com
# ATTENZIONE: nmap via Tor è molto lento e potrebbe timeout
```

### Email e contatti

```bash
# theHarvester via Tor
proxychains theHarvester -d target.com -b google,bing,duckduckgo

# hunter.io (richiede API key)
proxychains curl -s "https://api.hunter.io/v2/domain-search?domain=target.com&api_key=KEY"
```

---

## Anti-detection e rate limiting

### Il problema: Tor exit = IP condiviso

Gli exit node Tor sono usati da migliaia di persone. Molti siti:
- Rate-limitano gli IP Tor
- Mostrano captcha
- Bloccano completamente

### Strategie

```bash
# Rotare IP tra le query (NEWNYM)
for url in "${URLS[@]}"; do
    # Cambia IP
    echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051
    sleep 10  # aspettare il cooldown NEWNYM
    
    # Query con nuovo IP
    proxychains curl -s "$url" >> results.txt
    
    # Delay tra le query (evita rate limiting)
    sleep $((RANDOM % 10 + 5))
done

# Randomizzare User-Agent
UA_LIST=(
    "Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0"
    "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15"
)
UA="${UA_LIST[$RANDOM % ${#UA_LIST[@]}]}"
proxychains curl -s -H "User-Agent: $UA" https://target.com
```

### Timing e pattern

```
SBAGLIATO: query ogni 1 secondo esatto → pattern rilevabile
CORRETTO:  delay random 3-15 secondi → pattern umano
```

---

## Gestione delle identità

### Separazione delle identità

Per OSINT professionale, ogni "identità operativa" dovrebbe avere:

| Aspetto | Identità A (ricerca) | Identità B (social) |
|---------|---------------------|---------------------|
| SocksPort | 9050 | 9060 |
| Browser | Firefox profilo tor-a | Firefox profilo tor-b |
| Exit node | Separato (isolamento) | Separato |
| Account | Nessuno | Account dedicato |
| Email | Nessuna | ProtonMail via Tor |

### Errori fatali di separazione

- Accedere a un account personale dalla stessa istanza Tor usata per OSINT
- Usare lo stesso browser/profilo per identità diverse
- Fare login su servizi identificabili durante la sessione OSINT
- Non cambiare IP (NEWNYM) tra attività di identità diverse

---

## OPSEC per OSINT

### Checklist pre-sessione

- [ ] Firewall restrittivo attivo (solo Tor)
- [ ] Verificato IP Tor (`proxychains curl https://api.ipify.org`)
- [ ] Shell history disabilitata (`unset HISTFILE`)
- [ ] Browser pulito (no cookie, no cache, no login)
- [ ] Stream isolation configurato
- [ ] Nessun account personale aperto nel browser
- [ ] NTP/DNS non leak-ano

### Checklist post-sessione

- [ ] Cancellare cache browser
- [ ] Cancellare download temporanei
- [ ] Verificare che nessun file scaricato contenga metadata con il tuo IP
- [ ] NEWNYM finale per dissociare la sessione
- [ ] Disattivare firewall restrittivo (se temporaneo)

---

## Nella mia esperienza

Uso Tor per ricognizione anonima durante lo studio di infrastrutture e
tecnologie. Il mio workflow tipico:

1. **Preparazione**: attivo Tor, verifico il bootstrap, verifico IP
2. **Ricerca**: uso `proxychains curl` per query HTTP, `tor-resolve` per DNS
3. **Archivio**: salvo i risultati localmente, mai su cloud durante la sessione
4. **Pulizia**: cancello cache, history, file temporanei

I problemi principali che ho incontrato:
- **Google captcha**: quasi inutilizzabile via Tor. Ho switchato a DuckDuckGo
  per le ricerche OSINT, che funziona perfettamente via Tor (e ha un .onion)
- **Rate limiting**: alcuni servizi (crt.sh, Shodan) limitano gli IP Tor.
  La rotazione con NEWNYM aiuta, ma il cooldown di 10 secondi rallenta
- **nmap via Tor**: estremamente lento. Per scan di porte, preferisco farlo da
  una VPS anonima piuttosto che via Tor. Tor è ottimo per web recon, meno per
  network scanning
- **Tool Go (amass, etc.)**: binari statici che bypassano proxychains/torsocks.
  Per questi tool, il transparent proxy (iptables) è l'unica soluzione affidabile

---

## Vedi anche

- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) — Evitare deanonimizzazione durante OSINT
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) — Rischi fingerprint durante ricognizione
- [ProxyChains — Guida Completa](../04-strumenti-operativi/proxychains-guida-completa.md) — Proxare strumenti OSINT
- [Limitazioni nelle Applicazioni](../07-limitazioni-e-attacchi/limitazioni-applicazioni.md) — Compatibilità tool con Tor
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) — Forzare tool Go/statici via Tor
