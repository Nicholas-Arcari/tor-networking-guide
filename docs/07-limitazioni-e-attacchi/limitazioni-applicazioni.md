# Limitazioni nelle Applicazioni — Cosa Funziona e Cosa No con Tor

Questo documento cataloga il comportamento di applicazioni specifiche quando usate
attraverso Tor: web app, applicazioni desktop, servizi cloud, strumenti di sviluppo,
e strumenti di sicurezza. Per ogni categoria analizza perché funzionano o non funzionano,
i workaround disponibili, la gestione delle sessioni con IP variabili, e le strategie
per i CAPTCHA.

Basato sulla mia esperienza diretta nel testare diverse applicazioni via
proxychains e Tor su Kali Linux.

---

## Indice

- [Perché le applicazioni hanno problemi con Tor](#perché-le-applicazioni-hanno-problemi-con-tor)
- [Applicazioni Web](#applicazioni-web)
- [Siti che bloccano Tor — Strategie](#siti-che-bloccano-tor--strategie)
- [Applicazioni Desktop](#applicazioni-desktop)
- [Strumenti di sicurezza via Tor](#strumenti-di-sicurezza-via-tor)
- [Strumenti di sviluppo via Tor](#strumenti-di-sviluppo-via-tor)
- [Servizi cloud e API](#servizi-cloud-e-api)
- [Sessioni web e IP variabili](#sessioni-web-e-ip-variabili)
- [Gestione dei CAPTCHA](#gestione-dei-captcha)
- [Il compromesso fondamentale](#il-compromesso-fondamentale)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Perché le applicazioni hanno problemi con Tor

Le applicazioni non funzionano con Tor per cinque ragioni fondamentali:

```
1. Protocollo: usano UDP, ICMP, o raw socket
   → Tor supporta SOLO TCP
   → UDP: VoIP, gaming, DNS diretto, QUIC, NTP
   → ICMP: ping, traceroute
   → Raw socket: nmap -sS, ping

2. Architettura proxy: non rispettano SOCKS5
   → App staticamente linkate: ignorano LD_PRELOAD
   → App Electron: stack di rete proprio (Node.js)
   → App con DNS hardcoded: bypassano proxy_dns
   → App con raw socket: non possono essere proxate

3. Sicurezza anti-abuso: bloccano IP di exit Tor
   → La lista degli exit è pubblica (check.torproject.org/torbulkexitlist)
   → Exit IP hanno bassa reputazione (usati per spam, attacchi)
   → CAPTCHA, blocchi, sospensione account

4. Sessioni legate all'IP: invalidate dal cambio IP
   → Tor cambia exit ogni ~10 min (MaxCircuitDirtiness)
   → Il sito vede un IP diverso → sessione invalidata
   → Logout forzato, carrello svuotato, etc.

5. Performance: latenza e bandwidth insufficienti
   → 3 hop = 200-500ms RTT
   → Bandwidth limitata (tipicamente 1-10 Mbps via Tor)
   → Timeout per applicazioni con timer aggressivi
```

---

## Applicazioni Web

### Siti che bloccano o limitano Tor

#### Google (Search, Maps, Gmail)

**Comportamento**: CAPTCHA aggressivi e ripetuti. A volte blocco totale con
messaggio "unusual traffic from your computer network".

**Motivo**: Google riceve enormi quantità di traffico automatizzato (bot, scraping)
dagli exit Tor. Per proteggersi, richiede verifiche umane.

**Nella mia esperienza**: le ricerche Google via Tor sono spesso frustranti.
Ogni 2-3 ricerche appare un CAPTCHA. A volte il CAPTCHA è infinito.

**Workaround**:
```
1. Usare DuckDuckGo (https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion)
2. Usare Startpage (proxy anonimo di Google)
3. NEWNYM per cambiare exit e riprovare
4. Google ha un .onion sperimentale: non sempre disponibile
```

#### Amazon

**Comportamento**: navigazione funziona. Login può fallire con
"suspicious activity". Acquisti spesso bloccati.

**Motivo**: Amazon blocca login da IP con reputazione bassa.

**Workaround**: non usare Tor per acquisti. Usare rete normale.

#### PayPal

**Comportamento**: login bloccato immediatamente. Account può essere
temporaneamente sospeso.

**Motivo**: PayPal ha policy anti-frode aggressive. Exit Tor = alto rischio.

**Workaround**: nessuno. Non usare PayPal via Tor.

#### Instagram / Meta

**Comportamento**: login molto difficile. Richiesta verifica identità, SMS, selfie.
Spesso blocco completo dell'account.

**Workaround**: non usare Meta via Tor per account personali.
Facebook ha un .onion ufficiale per navigazione anonima.

#### Reddit

**Comportamento**: funziona per la lettura. Login richiesto più frequentemente.
Alcuni subreddit bloccano post/commenti da Tor.

**Workaround**: usare old.reddit.com (meno JavaScript, funziona meglio).

#### Wikipedia

**Comportamento**: lettura perfetta. **Editing bloccato** per tutti gli IP degli
exit Tor (policy anti-vandalismo).

**Workaround**: richiedere l'esenzione IP block (IP block exemption) per
account fidati. Processo lungo ma possibile.

#### GitHub

**Comportamento**: funziona generalmente bene. Occasionalmente richiede
autenticazione aggiuntiva. Push/pull via HTTPS funzionano con proxychains.

```bash
# Clone via Tor:
proxychains git clone https://github.com/user/repo

# Push via Tor:
proxychains git push origin main

# Oppure configurazione permanente:
git config --global http.proxy socks5h://127.0.0.1:9050
```

#### Stack Overflow

**Comportamento**: funziona bene per lettura e ricerca. Login e posting possono
richiedere verifiche extra.

#### Banche italiane (home banking)

**Comportamento**: **blocco totale** nella mia esperienza. I sistemi anti-frode
bancari bloccano immediatamente connessioni da IP Tor/datacenter. Spesso
l'account viene temporaneamente bloccato, richiedendo chiamata al supporto.

**Regola**: non usare MAI Tor per accedere a servizi bancari.

#### Cloudflare-protected sites

**Comportamento**: molti siti usano Cloudflare come CDN/WAF. Cloudflare
implementa verifiche aggiuntive per IP Tor:
```
- "Checking your browser..." page (JavaScript challenge)
- CAPTCHA hCaptcha o Turnstile
- Blocco completo per alcuni siti
- Il comportamento dipende dalla configurazione del sito
```

**Workaround**:
```
1. NEWNYM e riprovare (exit diverso = reputazione diversa)
2. Attendere che il JavaScript challenge completi (5-10 secondi)
3. Usare Tor Browser (gestisce i challenge meglio di Firefox+proxychains)
4. Non c'è soluzione universale: dipende dal sito
```

---

## Siti che bloccano Tor — Strategie

### Strategia 1: cambio exit

```bash
# Cambiare exit node via ControlPort
echo -e "AUTHENTICATE \"password\"\r\nSIGNAL NEWNYM\r\nQUIT" | nc 127.0.0.1 9051

# Attendere ~5 secondi per il nuovo circuito
sleep 5

# Riprovare
proxychains curl -s https://sito-problematico.com
```

### Strategia 2: forzare exit di paesi specifici (temporaneo)

```ini
# Nel torrc (temporaneamente):
ExitNodes {de},{nl},{ch}    # Exit da paesi con alta reputazione
StrictNodes 1

# ATTENZIONE: riduce l'anonimato! Usare solo per test temporanei.
# Rimuovere dopo l'uso.
```

### Strategia 3: exit node personale

```
Se gestisci un exit node, il suo IP ha reputazione migliore
(meno abusato di exit condivisi). Ma:
- Costo e complessità di gestione
- Il tuo exit è collegabile a te
- Non raccomandato per anonimato personale
```

### Strategia 4: accettare il compromesso

Alcuni siti non funzioneranno mai bene via Tor. Accettare che Tor non è
adatto per tutto e usare la rete normale per quei siti.

---

## Applicazioni Desktop

### Tor Browser vs Firefox con proxy SOCKS

| Aspetto | Tor Browser | Firefox + proxychains |
|---------|-------------|----------------------|
| IP anonimo | SI | SI |
| DNS via Tor | Automatico | Richiede proxy_dns |
| Anti-fingerprinting | Completo (300+ patch) | Minimo (resistFingerprinting) |
| WebRTC protezione | Automatica | Manuale (about:config) |
| Circuiti per dominio | Automatico (FPI) | No |
| Facilità | Alta | Media |
| Flessibilità | Bassa | Alta |

### Applicazioni che NON funzionano con proxychains

| Applicazione | Motivo | Alternativa |
|-------------|--------|-------------|
| Discord | Usa WebSocket + UDP per voce | Nessuna alternativa via Tor |
| Telegram Desktop | Stack di rete proprietario | Proxy SOCKS5 nelle impostazioni |
| Steam | Usa UDP per gaming, TCP per store | Lo store funziona male via browser |
| Spotify | Protocollo proprietario streaming | Non praticabile via Tor |
| Electron apps (VS Code, Slack) | Spesso ignorano LD_PRELOAD | Dipende dall'app |
| Client email desktop (Thunderbird) | SMTP porta 25 bloccata da exit | Config SOCKS5 interna + SMTP su 587 |
| Zoom/Teams | UDP per video/voce | Non praticabile via Tor |
| VLC streaming | UDP/RTP | Non praticabile |
| Dropbox client | Protocollo proprietario | Web interface via Tor Browser |
| OneDrive/Google Drive sync | Servizi di sistema in background | Web interface via Tor Browser |

### Applicazioni che funzionano con proxychains

| Applicazione | Qualità | Note |
|-------------|---------|------|
| curl | Eccellente | Il mio strumento principale (`--socks5-hostname`) |
| wget | Buona | Download funzionano, attenzione ai redirect |
| git (HTTPS) | Buona | Clone, pull, push (`socks5h://`) |
| ssh | Accettabile | Lento ma funzionante, keep-alive consigliato |
| pip | Buona | Installa pacchetti Python via Tor |
| npm | Buona | Installa pacchetti Node.js via Tor |
| gem | Buona | Installa gem Ruby via Tor |
| rsync (via SSH) | Accettabile | Lento per file grandi |
| lynx/w3m | Buona | Browser testuali, nessun JavaScript |
| aria2c | Buona | Download con resume via proxy |

### Applicazioni Go staticamente linkate

```
Problema: molte applicazioni Go sono compilate staticamente.
LD_PRELOAD (usato da proxychains) non funziona con binari statici.

Esempi: hugo, terraform, kubectl, docker (CLI), gh (GitHub CLI)

Soluzioni:
1. Usare torsocks (può funzionare dove proxychains fallisce)
2. Configurare variabili d'ambiente:
   export HTTP_PROXY=socks5://127.0.0.1:9050
   export HTTPS_PROXY=socks5://127.0.0.1:9050
   export ALL_PROXY=socks5://127.0.0.1:9050
3. Usare TransPort (transparent proxy a livello iptables)
4. Usare network namespace
```

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
# Enumerazione web via Tor — lenta ma funzionante
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

# cargo (Rust) — PROBLEMATICO
proxychains cargo build
# cargo è spesso compilato staticamente → LD_PRELOAD non funziona
# Soluzione: variabili d'ambiente
export HTTPS_PROXY=socks5h://127.0.0.1:9050
cargo build

# apt — NON RACCOMANDATO via proxychains
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

- [Tor Browser e Applicazioni](../04-strumenti-operativi/tor-browser-e-applicazioni.md) — Tor Browser internals, matrice compatibilità
- [ProxyChains — Guida Completa](../04-strumenti-operativi/proxychains-guida-completa.md) — LD_PRELOAD, configurazione
- [torsocks](../04-strumenti-operativi/torsocks.md) — Alternativa a proxychains
- [Limitazioni del Protocollo](limitazioni-protocollo.md) — TCP-only, latenza, bandwidth
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) — NEWNYM per cambiare exit
- [Ricognizione Anonima](../09-scenari-operativi/ricognizione-anonima.md) — OSINT via Tor
