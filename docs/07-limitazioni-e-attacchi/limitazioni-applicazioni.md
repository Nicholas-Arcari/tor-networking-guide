> **Lingua / Language**: Italiano | [English](../en/07-limitazioni-e-attacchi/limitazioni-applicazioni.md)

# Limitazioni nelle Applicazioni - Cosa Funziona e Cosa No con Tor

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
- [Siti che bloccano Tor - Strategie](#siti-che-bloccano-tor--strategie)
- [Applicazioni Desktop](#applicazioni-desktop)
- **Approfondimenti** (file dedicati)
  - [Strumenti, Cloud e Sessioni via Tor](limitazioni-applicazioni-pratica.md)

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

## Siti che bloccano Tor - Strategie

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

> **Continua in** [Limitazioni Applicazioni - Strumenti, Cloud e Sessioni](limitazioni-applicazioni-pratica.md)
> - nmap, nikto, sqlmap, Burp Suite, Metasploit, package manager, Docker via Tor,
> servizi cloud e API, sessioni web con IP variabili, gestione CAPTCHA.

---

## Vedi anche

- [Tor Browser e Applicazioni](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Tor Browser internals
- [ProxyChains - Guida Completa](../04-strumenti-operativi/proxychains-guida-completa.md) - LD_PRELOAD, configurazione
- [torsocks](../04-strumenti-operativi/torsocks.md) - Alternativa a proxychains
- [Limitazioni del Protocollo](limitazioni-protocollo.md) - TCP-only, latenza, bandwidth
