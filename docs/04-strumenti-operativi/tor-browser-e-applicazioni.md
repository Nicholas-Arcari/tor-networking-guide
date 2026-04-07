# Tor Browser e Routing delle Applicazioni

Questo documento analizza Tor Browser (le sue protezioni interne, il funzionamento
delle patch, il meccanismo di aggiornamento), la differenza con Firefox+proxychains,
come instradare diverse applicazioni attraverso Tor, e le strategie per ogni tipo
di applicazione nel mondo reale.

Basato sulla mia esperienza con Firefox + profilo `tor-proxy` via proxychains,
e la consapevolezza dei limiti di questo approccio rispetto a Tor Browser.

---

## Indice

- [Tor Browser — Architettura interna](#tor-browser--architettura-interna)
- [Protezioni anti-fingerprinting in dettaglio](#protezioni-anti-fingerprinting-in-dettaglio)
- [Protezioni di rete](#protezioni-di-rete)
- [Security Level e NoScript](#security-level-e-noscript)
- [Meccanismo di aggiornamento](#meccanismo-di-aggiornamento)
- [First-Party Isolation in profondità](#first-party-isolation-in-profondità)
- [Firefox + proxychains — Il mio setup e i suoi limiti](#firefox--proxychains--il-mio-setup-e-i-suoi-limiti)
- [Instradare applicazioni attraverso Tor](#instradare-applicazioni-attraverso-tor)
- [Matrice di compatibilità completa](#matrice-di-compatibilità-completa)
- [Applicazioni con SOCKS5 nativo](#applicazioni-con-socks5-nativo)
- [Problemi comuni e soluzioni](#problemi-comuni-e-soluzioni)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Tor Browser — Architettura interna

Tor Browser è un Firefox ESR modificato con patch specifiche. Non è "Firefox con
un proxy SOCKS configurato". Le differenze sono profonde e toccano il codice
sorgente del browser.

### Componenti di Tor Browser

```
Tor Browser Bundle contiene:
├── firefox (Firefox ESR patchato con ~300 modifiche)
├── tor (daemon Tor integrato)
├── torrc-defaults (configurazione Tor minimale)
├── pluggable_transports/
│   ├── obfs4proxy (bridge obfs4)
│   ├── snowflake-client
│   └── meek-client
├── TorButton (estensione integrata)
│   ├── Gestione identità (New Identity)
│   ├── Gestione circuiti (per-tab circuit display)
│   └── Security Level UI
└── NoScript (estensione per bloccare JavaScript)
```

### Come Tor Browser si connette

```
1. L'utente avvia Tor Browser
2. Il daemon Tor integrato si avvia e fa bootstrap
3. Firefox si connette a Tor via SocksPort locale (127.0.0.1:9150)
   NOTA: porta 9150, NON 9050 (per non conflittuare con il Tor di sistema)
4. Ogni tab usa credenziali SOCKS diverse
   → Tab 1: user="tab1-unique-id" pass="random"
   → Tab 2: user="tab2-unique-id" pass="random"
5. Tor crea circuiti diversi per credenziali diverse
   → Ogni dominio ha il proprio circuito
   → Nessuna correlazione cross-tab a livello di rete
```

### Differenza con Tor di sistema

```
Tor Browser (integrato):
  - SocksPort 9150 (non 9050)
  - ControlPort 9151 (non 9051)
  - Tor configurato per il browser, non per uso generale
  - Si chiude con il browser
  - Non condivide circuiti con altre applicazioni

Tor di sistema (il mio setup):
  - SocksPort 9050
  - ControlPort 9051
  - Tor condiviso tra tutte le applicazioni (curl, Firefox, git, etc.)
  - Rimane attivo come servizio systemd
  - I circuiti sono condivisi (a meno di IsolateSOCKSAuth)
```

---

## Protezioni anti-fingerprinting in dettaglio

### Tabella comparativa completa

| Vettore di fingerprinting | Firefox normale | Tor Browser | Come TB lo mitiga |
|--------------------------|----------------|-------------|-------------------|
| User-Agent | Rivela OS, versione, architettura | Uniformato | Sempre "Windows NT 10.0" |
| Dimensioni finestra | Riflette il monitor reale | Arrotondate | Letterboxing (bordi grigi) |
| Canvas | Rivela GPU e driver | Randomizzato | Canvas Blocker integrato |
| WebGL | Rivela modello GPU | Disabilitato/spoofato | `webgl.disabled = true` |
| Font | Rivela font installati (unici per OS) | Solo font standard | Bundled font list |
| Timezone | Rivela la tua timezone | Sempre UTC | `privacy.resistFingerprinting` |
| Lingua | Rivela lingua del sistema | Sempre en-US | Header Accept-Language fisso |
| Screen resolution | Rivela monitor reale | Spoofata | Riportata come multiplo standard |
| AudioContext | Fingerprint audio hardware | Neutralizzato | API modificata |
| Battery API | Rivela stato batteria | Disabilitato | API rimossa |
| Connection API | Rivela tipo connessione | Disabilitato | API rimossa |
| Plugins/Extensions | Lista estensioni installate | Nessuna visibile | `plugins.enumerable_names = ""` |
| navigator.hardwareConcurrency | Rivela numero CPU | Fisso a 2 | Valore hardcoded |
| navigator.deviceMemory | Rivela RAM | Non esposta | API non disponibile |
| Math precision | Differenze tra CPU | Uniformata | Risultati normalizzati |
| Performance.now() | Timer ad alta precisione | Ridotta | Precisione a 100ms |

### Letterboxing in dettaglio

Tor Browser non ridimensiona la pagina web alle dimensioni esatte della finestra.
Aggiunge bordi grigi per arrotondare le dimensioni a multipli di 200x100 pixel:

```
Finestra reale: 1367 x 843 pixel
Dimensione riportata al sito: 1200 x 800 pixel (multiplo di 200x100)
Bordo grigio: 167px orizzontale, 43px verticale

Questo fa sì che tutti gli utenti con finestre tra 1200x800 e 1399x899
abbiano la stessa dimensione riportata → stesso fingerprint per questa metrica.
```

### Canvas fingerprinting — come TB lo blocca

```
Senza protezione:
  1. Il sito disegna testo/forme su un <canvas>
  2. Chiama canvas.toDataURL() per leggere i pixel
  3. I pixel dipendono da GPU, driver, font rendering → fingerprint unico

Con Tor Browser:
  1. Il sito disegna su <canvas> (permesso)
  2. Quando chiama toDataURL():
     - TB mostra un prompt: "Questo sito vuole estrarre dati dal canvas"
     - Se l'utente nega: restituisce dati vuoti
     - Se l'utente permette: restituisce dati leggermente randomizzati
  3. La randomizzazione è diversa per sessione → no tracking persistente
```

---

## Protezioni di rete

### Tabella comparativa rete

| Protezione | Firefox normale | Tor Browser |
|-----------|----------------|-------------|
| WebRTC | Attivo (leak IP reale!) | **Disabilitato** |
| DNS | Usa resolver di sistema | Sempre via Tor (SOCKS5) |
| Prefetch DNS | Attivo (precarica DNS) | **Disabilitato** |
| HTTP/3 (QUIC) | Attivo (usa UDP) | **Disabilitato** |
| Speculative connections | Attive | **Disabilitate** |
| HSTS tracking | Possibile (supercookie) | Reset alla chiusura |
| OCSP requests | In chiaro verso la CA | Disabilitato (CRL stapled) |
| TLS session resumption | Attiva (tracking vector) | **Disabilitata** |
| HTTP referrer | Completo | Troncato al dominio |
| Safe browsing | Connette a Google | **Disabilitato** |
| Telemetry | Attiva | **Completamente rimossa** |
| Crash reporter | Attivo | **Rimosso** |
| Geolocation API | Attiva | **Disabilitata** |
| Search suggestions | Inviate in tempo reale | **Disabilitate** |
| Prefetch pages | Attivo | **Disabilitato** |
| Beacon API | Attiva (tracking) | **Disabilitata** |

### WebRTC — perché è così pericoloso

```javascript
// Senza protezione, qualsiasi sito web può eseguire:
var pc = new RTCPeerConnection({iceServers: [{urls: "stun:stun.l.google.com:19302"}]});
pc.createDataChannel('');
pc.createOffer().then(offer => pc.setLocalDescription(offer));
pc.onicecandidate = function(event) {
    if (event.candidate) {
        var ip = event.candidate.candidate.match(/(\d+\.\d+\.\d+\.\d+)/);
        // ip[1] contiene il tuo IP REALE (locale o pubblico)
        // Questo bypassa completamente il proxy SOCKS5!
    }
};
// Risultato su Firefox senza protezione:
//   "candidate:0 1 UDP 2122252543 192.168.1.100 44323 typ host"
//   → 192.168.1.100 è il tuo IP locale reale
```

Tor Browser: `media.peerconnection.enabled = false` → l'API non esiste.

---

## Security Level e NoScript

### I tre livelli di sicurezza

Tor Browser ha un "Security Level" accessibile dallo scudo nella toolbar:

**Standard (default)**:
```
- JavaScript: abilitato
- Canvas: prompt prima dell'estrazione
- Audio/Video: abilitati
- Font remoti: caricati
- MathML: abilitato
→ Massima usabilità, protezione base
→ Per navigazione generale su siti fidati
```

**Safer**:
```
- JavaScript: disabilitato su siti HTTP (non HTTPS)
- Audio/Video: click-to-play
- Font remoti: bloccati
- MathML: disabilitato
- Alcune feature JS pericolose: disabilitate (JIT, WASM)
→ Buon compromesso sicurezza/usabilità
→ Per navigazione su siti misti
```

**Safest**:
```
- JavaScript: completamente disabilitato OVUNQUE
- Immagini: caricate ma no scripts
- Audio/Video: disabilitati
- Font remoti: bloccati
- CSS: funzionalità ridotte
→ Massima sicurezza, molti siti non funzionano
→ Per siti .onion sensibili o navigazione ad alto rischio
```

### Impatto sulla sicurezza

```
Standard: vulnerabile a exploit JavaScript (es. Freedom Hosting 2013)
Safer: protetto dalla maggior parte degli exploit JS (no JIT = no exploit JIT)
Safest: protetto da quasi tutti gli exploit web (no JS = superficie minima)

Trade-off:
  Standard → 90% dei siti funzionano → rischio medio
  Safer → 70% dei siti funzionano → rischio basso
  Safest → 30% dei siti funzionano → rischio minimo
```

### NoScript in Tor Browser

NoScript è integrato in Tor Browser e controllato dal Security Level:

```
Standard: NoScript è presente ma permette tutto
Safer: NoScript blocca JS su HTTP, permette su HTTPS
Safest: NoScript blocca tutto (JS, font, media, frames)

IMPORTANTE: non modificare manualmente le regole NoScript
→ Regole personalizzate creano un fingerprint unico
→ Tutti gli utenti TB al livello "Standard" hanno le stesse regole
→ Personalizzare = distinguersi dal gruppo
```

---

## Meccanismo di aggiornamento

### Come Tor Browser si aggiorna

```
1. Tor Browser controlla periodicamente
   https://aus1.torproject.org/torbrowser/update_3/
   (tramite Tor, non in chiaro)

2. Se c'è un aggiornamento disponibile:
   - Mostra una notifica nella toolbar
   - Download automatico in background (via Tor)
   - L'utente può applicare con un click

3. Verifica dell'integrità:
   - L'aggiornamento è firmato con le chiavi del Tor Project
   - SHA256 hash verificato
   - Se la verifica fallisce → aggiornamento rifiutato
```

### Perché gli aggiornamenti sono critici

```
Tor Browser è basato su Firefox ESR (Extended Support Release)
Firefox ESR riceve patch di sicurezza ogni ~6 settimane
Tor Browser segue lo stesso ciclo

Se NON aggiorni:
  - Vulnerabilità note (CVE) non patchate
  - Exploit pubblici disponibili
  - Caso Freedom Hosting (2013): exploit su Firefox ESR 17 non aggiornato
  
REGOLA: aggiornare Tor Browser IMMEDIATAMENTE quando disponibile
```

---

## First-Party Isolation in profondità

### Come funziona FPI

Tor Browser implementa **First-Party Isolation (FPI)**, che isola tutto
il browser state per dominio di primo livello:

```
Senza FPI (Firefox normale):
  tracker.com su sito-a.com → cookie tracker.com = "user123"
  tracker.com su sito-b.com → legge cookie tracker.com = "user123"
  → tracker.com sa che hai visitato sia sito-a che sito-b

Con FPI (Tor Browser):
  tracker.com su sito-a.com → cookie {sito-a.com, tracker.com} = "user123"
  tracker.com su sito-b.com → cookie {sito-b.com, tracker.com} = VUOTO
  → tracker.com NON può correlare le visite
```

### Cosa viene isolato per dominio

```
- Cookie: isolati per first-party domain
- Cache HTTP: isolata per first-party domain
- Cache di immagini/font: isolata
- Connessioni TLS: sessioni separate per dominio
- HSTS state: isolato per dominio
- OCSP responses: isolate
- SharedWorkers: isolati
- Service Workers: disabilitati
- Favicon cache: isolata
- Alt-Svc: isolato (no cross-site HTTP/2 push)
- Circuito Tor: diverso per ogni dominio (via SOCKS auth)
```

### Circuiti per dominio

```
Tab 1: visita sito-a.com
  → SOCKS auth: user="sito-a.com" pass="random1"
  → Tor usa circuito A (Guard X → Middle Y → Exit Z)

Tab 2: visita sito-b.com
  → SOCKS auth: user="sito-b.com" pass="random2"
  → Tor usa circuito B (Guard X → Middle W → Exit V)

Tab 3: visita sito-a.com/altra-pagina
  → SOCKS auth: user="sito-a.com" pass="random1" (stesso dominio)
  → Riutilizza circuito A
  
→ Exit diversi per domini diversi
→ Il server di destinazione non può correlare le visite a siti diversi
→ Nemmeno l'exit node può correlare
```

---

## Firefox + proxychains — Il mio setup e i suoi limiti

### Come ho configurato il mio setup

```bash
# 1. Creare un profilo dedicato (una tantum)
firefox -no-remote -CreateProfile tor-proxy

# 2. Avviare Firefox con il profilo, via proxychains
proxychains firefox -no-remote -P tor-proxy & disown
```

Il flag `-no-remote` impedisce a Firefox di connettersi a un'istanza esistente
(che potrebbe non passare da Tor).

### Configurazioni manuali necessarie nel profilo

In `about:config` del profilo `tor-proxy`:

```
# Protezione rete
media.peerconnection.enabled = false        # Disabilita WebRTC (previene IP leak)
network.http.http3.enabled = false           # Disabilita QUIC/HTTP3 (usa UDP)
network.dns.disablePrefetch = true           # No DNS prefetch
network.prefetch-next = false                # No prefetch pagine
network.predictor.enabled = false            # No connessioni speculative
browser.send_pings = false                   # No tracking pings
geo.enabled = false                          # No geolocalizzazione

# Anti-fingerprinting
privacy.resistFingerprinting = true          # Protezione base (timezone, locale, etc.)
webgl.disabled = true                        # No WebGL fingerprint
dom.battery.enabled = false                  # No Battery API
dom.gamepad.enabled = false                  # No Gamepad API
media.navigator.enabled = false              # No media devices enumeration

# Privacy
privacy.trackingprotection.enabled = true    # Tracking protection
network.cookie.cookieBehavior = 1            # Solo first-party cookie
browser.safebrowsing.enabled = false         # No connessioni a Google
browser.safebrowsing.malware.enabled = false # No connessioni a Google
toolkit.telemetry.enabled = false            # No telemetria

# DNS
network.proxy.socks_remote_dns = true        # DNS via SOCKS5
network.trr.mode = 5                         # Disabilita DoH completamente
```

### Cosa questo setup NON protegge

Anche con queste configurazioni, Firefox normale:

| Protezione | Tor Browser | Il mio Firefox |
|-----------|-------------|----------------|
| User-Agent uniformato | SI (tutti gli utenti TB identici) | NO (rivela Linux/Kali) |
| Letterboxing | SI | NO (dimensioni reali) |
| Cookie isolation per dominio | SI (FPI) | NO (cookie condivisi cross-site) |
| Timezone spoofing | SI (UTC) | PARZIALE (con resistFingerprinting) |
| Font unificate | SI (solo font bundled) | NO (font di sistema visibili) |
| Canvas protection | SI (prompt + randomizzazione) | PARZIALE (con resistFingerprinting) |
| Circuiti per dominio | SI (SOCKS auth diversa per dominio) | NO (stesso circuito per tutti i siti) |
| New Identity | SI (un click resetta tutto) | NO (devo chiudere e riaprire) |
| Estensioni nascoste | SI | NO (estensioni rilevabili) |

**Conclusione**: uso questo setup per comodità e test, non per anonimato massimo.
Per anonimato reale, bisogna usare Tor Browser.

---

## Instradare applicazioni attraverso Tor

### Metodo 1: proxychains (LD_PRELOAD)

```bash
# proxychains intercetta le chiamate di rete via LD_PRELOAD
# Funziona con la maggior parte delle applicazioni dinamicamente linkate

proxychains curl https://example.com
proxychains firefox -no-remote -P tor-proxy
proxychains git clone https://github.com/user/repo
proxychains ssh user@host
proxychains nmap -sT -Pn target.com
```

**Quando funziona**: applicazioni che usano glibc e fanno chiamate di rete standard
(connect, getaddrinfo, etc.).

**Quando NON funziona**:
- Applicazioni staticamente linkate (Go binaries, Rust binaries)
- Applicazioni che usano raw socket (nmap -sS, ping)
- Applicazioni che gestiscono i socket direttamente (bypass di glibc)
- Applicazioni Electron (hanno il proprio stack di rete)

### Metodo 2: torsocks (LD_PRELOAD specializzato)

```bash
# torsocks è specifico per Tor, più sicuro di proxychains
# Blocca attivamente connessioni non-TCP (UDP) invece di ignorarle

torsocks curl https://example.com
torsocks ssh user@host
torsocks wget https://example.com/file

# Vantaggio: se un'app tenta UDP, torsocks la BLOCCA
# proxychains: ignorerebbe silenziosamente il tentativo UDP
```

### Metodo 3: configurazione SOCKS5 nativa dell'app

```bash
# Alcune applicazioni supportano proxy SOCKS5 nella configurazione
# Questo è più affidabile di LD_PRELOAD

# curl nativo:
curl --socks5-hostname 127.0.0.1:9050 https://example.com
# oppure
curl -x socks5h://127.0.0.1:9050 https://example.com

# git nativo:
git config --global http.proxy socks5h://127.0.0.1:9050
git config --global https.proxy socks5h://127.0.0.1:9050
# IMPORTANTE: "socks5h" (con h) → risolvi hostname via proxy

# SSH via ProxyCommand:
# In ~/.ssh/config:
Host *.onion
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

### Metodo 4: TransPort (transparent proxy)

```bash
# Per uso system-wide, iptables redirige tutto il traffico TCP a Tor
# Vedi docs/06-configurazioni-avanzate/transparent-proxy.md

# Vantaggi: TUTTE le applicazioni passano da Tor, senza configurazione
# Svantaggi: UDP bloccato, performance degradate, fragile
```

---

## Matrice di compatibilità completa

### Applicazioni CLI

| Applicazione | Metodo | Funziona? | DNS sicuro? | Note |
|-------------|--------|-----------|-------------|------|
| curl | `--socks5-hostname` | SI | SI | Perfetto, il mio strumento principale |
| curl | `--socks5` (senza h) | SI ma LEAK DNS | **NO** | Mai usare senza -hostname |
| wget | proxychains | SI | SI (con proxy_dns) | Download funzionano bene |
| git (HTTPS) | proxychains o config | SI | SI | Clone, pull, push |
| git (SSH) | proxychains | Parziale | SI | Lento, timeout possibili |
| ssh | proxychains o ProxyCommand | SI | SI | Lento ma funzionante |
| pip | proxychains | SI | SI | Installa pacchetti Python via Tor |
| npm | proxychains | SI | SI | Installa pacchetti Node.js via Tor |
| gem | proxychains | SI | SI | Installa gem Ruby via Tor |
| cargo | proxychains | Parziale | SI | Rust: link statico può causare problemi |
| rsync | proxychains | SI | SI | Sincronizzazione file |
| scp | proxychains | SI | SI | Copia file via SSH |

### Strumenti di sicurezza

| Applicazione | Metodo | Funziona? | Note |
|-------------|--------|-----------|------|
| nmap -sT | proxychains | SI | Solo TCP connect scan, -Pn obbligatorio |
| nmap -sS | proxychains | **NO** | SYN scan richiede raw socket |
| nmap -sU | proxychains | **NO** | UDP non supportato da Tor |
| nmap -sn | proxychains | **NO** | Ping usa ICMP |
| nikto | proxychains | SI | Lento ma funzionante |
| dirb/gobuster | proxychains | SI | Enumerazione directory via Tor |
| sqlmap | proxychains o --proxy | SI | Supporta SOCKS5 nativamente |
| Burp Suite | config proxy interna | SI | SOCKS proxy nelle impostazioni |
| wfuzz | proxychains | SI | Fuzzing web via Tor |
| hydra | proxychains | Parziale | Solo protocolli TCP, molto lento |
| ping | Non supportato | **NO** | ICMP non supportato |
| traceroute | Non supportato | **NO** | ICMP/UDP |

### Applicazioni Desktop

| Applicazione | Metodo | Funziona? | Note |
|-------------|--------|-----------|------|
| Firefox | proxychains + profilo | SI | Senza protezioni anti-fingerprint complete |
| Tor Browser | Integrato | SI | Setup completo, raccomandato |
| Chromium | proxychains | Parziale | DoH può bypassare, fingerprint alto |
| Thunderbird | proxy SOCKS5 config | SI | Email via Tor possibile |
| Discord | proxychains | **NO** | Usa WebSocket + UDP per voce |
| Telegram Desktop | config proxy interna | SI | Configurare SOCKS5 nelle impostazioni |
| Signal Desktop | proxychains | Parziale | Funziona per messaggi, non per chiamate |
| Steam | proxychains | **NO** | Usa UDP per gaming |
| Spotify | proxychains | **NO** | Protocollo proprietario, streaming |
| VLC (streaming) | proxychains | **NO** | Usa UDP per streaming |
| Electron apps | proxychains | Parziale | Spesso ignorano LD_PRELOAD |
| VS Code | proxychains | Parziale | Electron, estensioni possono bypassare |
| Client email (SMTP) | proxychains | Parziale | Porta 25 bloccata dalla maggior parte degli exit |

### Servizi specifici

| Servizio | Via Tor Browser | Via proxychains | Note |
|---------|----------------|-----------------|------|
| Google Search | SI (con CAPTCHA) | SI (con CAPTCHA) | Usare DuckDuckGo/Startpage |
| Gmail | SI (difficile) | SI (difficile) | Richiede verifica telefono |
| GitHub | SI | SI | Funziona generalmente bene |
| Stack Overflow | SI | SI | Lettura perfetta, posting con verifica |
| Wikipedia | SI (lettura) | SI (lettura) | Editing bloccato da IP Tor |
| Reddit | SI | SI | Login richiesto più spesso |
| Amazon | SI (navigazione) | SI (navigazione) | Acquisti spesso bloccati |
| Banking | **NO** | **NO** | Bloccato, possibile lock account |
| PayPal | **NO** | **NO** | Bloccato, possibile sospensione |
| Netflix | Parziale | **NO** | Blocca molti exit IP |

---

## Applicazioni con SOCKS5 nativo

### Firefox (nel profilo `tor-proxy`)

```
Settings → Network Settings → Manual proxy configuration
  SOCKS Host: 127.0.0.1
  SOCKS Port: 9050
  SOCKS v5
  ☑ Proxy DNS when using SOCKS v5

Oppure in about:config:
  network.proxy.type = 1
  network.proxy.socks = "127.0.0.1"
  network.proxy.socks_port = 9050
  network.proxy.socks_version = 5
  network.proxy.socks_remote_dns = true
```

### git

```bash
# Configurazione globale
git config --global http.proxy socks5h://127.0.0.1:9050
git config --global https.proxy socks5h://127.0.0.1:9050

# Solo per un repository specifico
cd /path/to/repo
git config http.proxy socks5h://127.0.0.1:9050

# Rimuovere il proxy
git config --global --unset http.proxy
git config --global --unset https.proxy

# IMPORTANTE: "socks5h" con la 'h' = hostname risolto dal proxy
# "socks5" senza 'h' = hostname risolto localmente (DNS leak!)
```

### SSH

```
# ~/.ssh/config
Host *.onion
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p

# Per qualsiasi host via Tor:
Host tor-*
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p

# Uso:
ssh tor-myserver.com    # Passa da Tor
ssh myserver.com        # Connessione diretta
```

### Telegram Desktop

```
Settings → Advanced → Connection type → Use custom proxy
  Type: SOCKS5
  Hostname: 127.0.0.1
  Port: 9050
  Username: (vuoto)
  Password: (vuoto)
```

### Burp Suite

```
Settings → Network → Connections → SOCKS proxy
  Host: 127.0.0.1
  Port: 9050
  ☑ Use SOCKS proxy
  ☑ Do DNS lookups over SOCKS proxy
```

### sqlmap

```bash
# Via opzione --proxy
sqlmap -u "https://target.com/page?id=1" --proxy=socks5://127.0.0.1:9050

# Oppure via proxychains
proxychains sqlmap -u "https://target.com/page?id=1"
```

---

## Problemi comuni e soluzioni

### Problema: applicazione ignora proxychains

```bash
# Sintomo: l'applicazione si connette direttamente (IP reale esposto)
# Causa: applicazione staticamente linkata o usa raw socket

# Verifica se l'applicazione è dinamicamente linkata:
ldd /usr/bin/app_name
# Se mostra "not a dynamic executable" → proxychains non funzionerà

# Soluzione 1: usare torsocks (può funzionare dove proxychains fallisce)
torsocks app_name

# Soluzione 2: configurare il proxy nell'applicazione
# Soluzione 3: usare TransPort/transparent proxy (iptables)
# Soluzione 4: usare network namespace
```

### Problema: timeout frequenti

```bash
# Sintomo: "Connection timed out" dopo pochi secondi
# Causa: l'applicazione ha timeout troppo brevi per Tor

# Per curl: aumentare il timeout
curl --socks5-hostname 127.0.0.1:9050 --max-time 60 https://example.com

# Per git: aumentare i timeout
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 60

# Per SSH: keep-alive
# ~/.ssh/config
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ConnectTimeout 60
```

### Problema: DNS leak nonostante proxychains

```bash
# Sintomo: tcpdump mostra query DNS in uscita
# Causa: proxy_dns non attivo, o app bypassa LD_PRELOAD

# Verifica 1: proxy_dns nel config
grep proxy_dns /etc/proxychains4.conf
# Deve mostrare: proxy_dns (non commentato)

# Verifica 2: test con tcpdump
sudo tcpdump -i eth0 port 53 -n &
proxychains curl -s https://example.com > /dev/null
# Se tcpdump mostra query → leak

# Soluzione: aggiungere regole iptables anti-leak
sudo iptables -A OUTPUT -p udp --dport 53 -m owner ! --uid-owner debian-tor -j DROP
```

### Problema: CAPTCHA infiniti

```
Sintomo: Google/Cloudflare mostra CAPTCHA ad ogni pagina
Causa: l'IP dell'exit Tor è in una blocklist

Soluzioni:
1. Cambiare exit: NEWNYM (via ControlPort o nyx)
2. Usare motori di ricerca Tor-friendly (DuckDuckGo, Startpage)
3. Per Cloudflare: non c'è soluzione universale, dipende dal sito
4. Forzare un exit di un paese specifico (NON raccomandato per privacy):
   ExitNodes {de},{nl}  # Exit da Germania/Olanda (meno bloccati)
```

---

## Nella mia esperienza

### Il mio workflow quotidiano

```bash
# Navigazione web anonima:
proxychains firefox -no-remote -P tor-proxy & disown

# Ricerche rapide:
proxychains curl -s https://api.ipify.org  # Verifica IP

# Test di sicurezza:
proxychains nmap -sT -Pn -p 80,443,8080 target.com

# Git via Tor:
proxychains git clone https://github.com/user/repo

# Tutto il resto: rete normale
firefox  # Profilo default, senza proxy
```

### Tor Browser vs il mio setup — Riepilogo finale

| Aspetto | Tor Browser | Il mio setup (Firefox+proxychains) |
|---------|-------------|----------------------------------|
| Anonimato IP | Eccellente | Eccellente |
| Anti-fingerprinting | Eccellente | Scarso |
| DNS leak prevention | Automatico | Richiede config (proxy_dns) |
| WebRTC protection | Automatico | Manuale (about:config) |
| Cross-site tracking | FPI (automatico) | Nessuna protezione nativa |
| Circuiti per dominio | Automatico | No (stesso circuito per tutti) |
| Facilità d'uso | Scarica e avvia | Configurazione manuale |
| Flessibilità | Limitata (è un browser) | Alta (qualsiasi app) |
| Per anonimato massimo | **SI** | NO |
| Per test e sviluppo | Poco pratico | **SI** |

Il mio setup è un compromesso consapevole: sacrifico l'anti-fingerprinting per
avere la flessibilità di usare Tor con qualsiasi strumento CLI e con Firefox
in un ambiente di sviluppo.

---

## Vedi anche

- [ProxyChains — Guida Completa](proxychains-guida-completa.md) — LD_PRELOAD, chain modes, proxy_dns
- [torsocks](torsocks.md) — Confronto con proxychains, blocco UDP, edge cases
- [Verifica IP, DNS e Leak](verifica-ip-dns-e-leak.md) — Test completi per verificare la protezione
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) — Tutti i vettori di fingerprinting
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) — Prevenzione completa DNS leak
- [Controllo Circuiti e NEWNYM](controllo-circuiti-e-newnym.md) — Gestione circuiti e cambio IP
