> **Lingua / Language**: Italiano | [English](../en/07-limitazioni-e-attacchi/limitazioni-applicazioni-pratica.md)

# Limitazioni Applicazioni - Strumenti, Cloud e Sessioni via Tor

Strumenti di sicurezza (nmap, nikto, sqlmap, Burp, Metasploit), strumenti
di sviluppo (pip, npm, Docker), servizi cloud e API, gestione delle sessioni
con IP variabili, e strategie per i CAPTCHA.

> **Estratto da** [Limitazioni nelle Applicazioni](limitazioni-applicazioni.md) -
> che copre anche perché le app hanno problemi con Tor, siti che bloccano Tor,
> e applicazioni desktop.

---

## Strumenti di sicurezza via Tor

### nmap

```bash
# FUNZIONA: TCP connect scan
proxychains nmap -sT -Pn target.com -p 80,443,8080
# -sT = TCP connect (usa socket normali, compatibile con SOCKS)
# -Pn = no ping (ICMP non supportato)

# NON FUNZIONA: SYN scan (richiede raw socket)
proxychains nmap -sS target.com  # FALLISCE

# NON FUNZIONA: UDP scan
proxychains nmap -sU target.com  # FALLISCE

# NON FUNZIONA: ping scan
proxychains nmap -sn target.com  # FALLISCE (ICMP)

# NON FUNZIONA: OS detection
proxychains nmap -O target.com   # FALLISCE (richiede raw socket)
```

Limitazioni di nmap via Tor:
```
- Solo -sT (TCP connect) funziona
- -Pn è obbligatorio (skip host discovery)
- Molto lento (ogni porta = connessione SOCKS separata)
- Scansioni di porte multiple sono estremamente lente
- Molti exit bloccano le porte non standard → falsi negativi
- -sV (version detection) funziona ma è molto lento
- Script NSE: alcuni funzionano, altri no (dipende se usano raw socket)
```

Performance tipiche:
```
Senza Tor: 1000 porte in ~2 secondi
Con Tor:   1000 porte in ~15-30 minuti
→ Fattore ~500x più lento

Consiglio: scansionare solo porte specifiche note
proxychains nmap -sT -Pn -p 22,80,443,8080,8443 target.com
```

### nikto / dirb / gobuster

```bash
# Enumerazione web via Tor - lenta ma funzionante
proxychains nikto -h https://target.com
proxychains dirb https://target.com /usr/share/dirb/wordlists/common.txt
proxychains gobuster dir -u https://target.com -w /usr/share/wordlists/common.txt

# Performance: ~10-50 richieste/secondo (vs 500+ senza Tor)
# Per wordlist grandi: NEWNYM periodico per non sovraccaricare un singolo exit
```

### sqlmap

```bash
# Funziona via proxychains
proxychains sqlmap -u "https://target.com/page?id=1"

# Oppure usando il proxy interno (più efficiente)
sqlmap -u "https://target.com/page?id=1" --proxy=socks5://127.0.0.1:9050

# Con tor-check integrato:
sqlmap -u "https://target.com/page?id=1" --proxy=socks5://127.0.0.1:9050 \
    --check-tor --tor-type=SOCKS5
```

### Burp Suite

```
Configurazione in Burp:
Settings → Network → Connections → SOCKS proxy
  Host: 127.0.0.1
  Port: 9050
  ☑ Use SOCKS proxy
  ☑ Do DNS lookups over SOCKS proxy

Considerazioni:
  - Tutto il traffico di Burp passa da Tor
  - Intruder/Scanner sono molto lenti via Tor
  - Target potrebbe bloccare l'exit IP durante il test
  - NEWNYM tra fasi diverse del test
```

### Metasploit

```bash
# Metasploit via proxychains
proxychains msfconsole

# Oppure configurare il proxy in Metasploit
msf6> setg Proxies socks5:127.0.0.1:9050
msf6> setg ReverseAllowProxy true

# ATTENZIONE: molti exploit/payload richiedono connessioni dirette
# Reverse shell NON funziona via Tor (richiede connessione in entrata)
# Bind shell: molto lenta e inaffidabile via Tor
# Web exploit (SQLi, etc.): funzionano
```

---

## Strumenti di sviluppo via Tor

### Package manager

```bash
# pip (Python)
proxychains pip install requests
# Funziona bene, lento per pacchetti grandi

# npm (Node.js)
proxychains npm install express
# Funziona, ma npm è già lento → via Tor è molto lento

# gem (Ruby)
proxychains gem install rails
# Funziona

# cargo (Rust) - PROBLEMATICO
proxychains cargo build
# cargo è spesso compilato staticamente → LD_PRELOAD non funziona
# Soluzione: variabili d'ambiente
export HTTPS_PROXY=socks5h://127.0.0.1:9050
cargo build

# apt - NON RACCOMANDATO via proxychains
# Meglio usare Tor APT transport:
# https://onion.debian.org/
```

### Docker via Tor

```bash
# Docker daemon non usa LD_PRELOAD
# Configurare il proxy nel daemon:

# /etc/docker/daemon.json
{
  "proxies": {
    "http-proxy": "socks5://127.0.0.1:9050",
    "https-proxy": "socks5://127.0.0.1:9050"
  }
}

# Riavviare Docker
sudo systemctl restart docker

# Ora docker pull passa da Tor
docker pull debian:bookworm
# LENTO ma funzionante
```

---

## Servizi cloud e API

### API con rate limiting

```
Problema: le API limitano le richieste per IP.
Gli exit Tor sono condivisi tra migliaia di utenti.
→ Il rate limit è già quasi esaurito per il "tuo" exit IP.

Esempio:
  GitHub API: 60 richieste/ora per IP non autenticato
  Ma dall'exit 185.220.101.x, altri utenti hanno già usato 55 richieste
  → Ti restano solo 5 richieste

Soluzione:
  1. NEWNYM frequente (cambia exit = nuovo rate limit)
  2. Autenticazione API (rate limit per account, non per IP)
  3. Usare rete normale per API ad alto volume
```

### Cloud provider (AWS, GCP, Azure)

```
AWS Console: funziona via Tor Browser, possibili CAPTCHA
AWS CLI: proxychains aws ... → funziona ma lento
GCP Console: funziona, possibili verifiche aggiuntive
Azure: funziona, possibili blocchi per nuovi account

ATTENZIONE: non creare account cloud da IP Tor
→ Account spesso bloccati immediatamente per sospetto abuso
→ Creare account da rete normale, poi usare via Tor se necessario
```

---

## Sessioni web e IP variabili

### Il problema

Tor cambia IP periodicamente (ogni ~10 minuti o con NEWNYM). Molti siti web
legano la sessione all'IP:

```
1. Login con IP 185.220.101.143 → sessione creata, cookie set
2. Circuito cambia → nuovo IP 104.244.76.13
3. Sito vede IP diverso → invalida la sessione → logout forzato

Siti più colpiti:
  - Banking: logout immediato al cambio IP
  - Shopping: carrello svuotato, sessione invalidata
  - Email: richiesta re-autenticazione
  - Social media: "suspicious login from new location"
  - SaaS: richiesta MFA ad ogni cambio IP
```

### Mitigazione: MaxCircuitDirtiness

```ini
# Nel torrc: aumentare il tempo prima del rinnovo circuiti
MaxCircuitDirtiness 1800    # 30 minuti invece di 10 (default 600)
```

**Trade-off**: più tempo con lo stesso IP = più tracciabile.
Per navigazione non sensibile: 1800 è accettabile.
Per anonimato massimo: lasciare il default 600.

### Mitigazione: isolamento circuiti

```ini
# SocksPort con isolamento per destinazione
SocksPort 9050 IsolateDestAddr IsolateDestPort

# Questo fa sì che connessioni allo STESSO sito usino lo STESSO circuito
# ma siti DIVERSI usino circuiti diversi
# → La sessione è più stabile per sito singolo
# → Ma siti diversi hanno exit diversi
```

---

## Gestione dei CAPTCHA

### Perché i CAPTCHA appaiono

```
1. IP reputation: gli exit Tor hanno reputazione bassa
   (usati per spam, scraping, attacchi)
2. Traffico anomalo: molte richieste dallo stesso IP
   (condiviso tra migliaia di utenti)
3. Fingerprint mancante: Tor Browser non invia cookie
   di sessione precedenti → "primo visitatore" ogni volta
4. Cloudflare/Akamai: CDN implementano challenge per IP sospetti
```

### Strategie

```
1. NEWNYM: cambia exit, potrebbe ottenere un IP con reputazione migliore
2. Motori di ricerca Tor-friendly:
   - DuckDuckGo (anche via .onion)
   - Startpage (proxy Google)
   - SearXNG (meta-search engine self-hosted)
3. Siti con .onion: bypassano completamente i CAPTCHA
   (Facebook, NYT, BBC, DuckDuckGo)
4. Patience: completare i CAPTCHA (lento ma funziona)
5. Tor Browser: gestisce i challenge JavaScript meglio di Firefox
```

---

## Il compromesso fondamentale

Usare Tor con applicazioni del mondo reale richiede accettare dei compromessi:

```
1. Velocità:      tutto è più lento (5-50x)
2. Compatibilità: molte app non funzionano (UDP, raw socket)
3. Blocchi:        molti siti bloccano o limitano Tor
4. Sessioni:       instabili per cambio IP
5. Funzionalità:   no video call, no voice, no gaming, no streaming
6. CAPTCHA:        frequenti e frustranti
7. Rate limit:     condiviso con altri utenti dello stesso exit
```

Tor è progettato per **anonimato**, non per comodità. Le limitazioni sono
conseguenze dirette delle scelte architetturali che garantiscono l'anonimato
(3 hop, rotazione circuiti, no UDP, exit policy).

Nella mia esperienza, la strategia migliore è:
- **Tor per ciò che richiede anonimato**: navigazione sensibile, ricerca, test
- **Rete normale/VPN per il resto**: banking, shopping, streaming, gaming
- **Mai mescolare** le due cose nella stessa sessione

---

## Nella mia esperienza

Le applicazioni che uso quotidianamente via Tor:
```
curl:    ★★★★★  Perfetto, il mio strumento principale
Firefox: ★★★★☆  Funziona bene con profilo tor-proxy
git:     ★★★★☆  Clone/push funzionano, un po' lento
ssh:     ★★★☆☆  Lento ma funzionante con keep-alive
nmap:    ★★☆☆☆  Solo -sT, estremamente lento
wget:    ★★★★☆  Download funzionano bene
```

Le applicazioni che NON uso mai via Tor:
```
Banking, PayPal, Amazon → blocchi e rischio lock account
Discord, Zoom, Teams → UDP necessario
Spotify, Netflix → troppo lento / bloccato
Steam → UDP necessario
```

---

## Vedi anche

- [Tor Browser e Applicazioni](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Tor Browser internals, matrice compatibilità
- [ProxyChains - Guida Completa](../04-strumenti-operativi/proxychains-guida-completa.md) - LD_PRELOAD, configurazione
- [torsocks](../04-strumenti-operativi/torsocks.md) - Alternativa a proxychains
- [Limitazioni del Protocollo](limitazioni-protocollo.md) - TCP-only, latenza, bandwidth
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - NEWNYM per cambiare exit
- [Ricognizione Anonima](../09-scenari-operativi/ricognizione-anonima.md) - OSINT via Tor
