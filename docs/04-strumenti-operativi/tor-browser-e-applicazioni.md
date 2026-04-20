> **Lingua / Language**: Italiano | [English](../en/04-strumenti-operativi/tor-browser-e-applicazioni.md)

# Tor Browser e Routing delle Applicazioni

Questo documento analizza Tor Browser (le sue protezioni interne, il funzionamento
delle patch, il meccanismo di aggiornamento), la differenza con Firefox+proxychains,
come instradare diverse applicazioni attraverso Tor, e le strategie per ogni tipo
di applicazione nel mondo reale.

Basato sulla mia esperienza con Firefox + profilo `tor-proxy` via proxychains,
e la consapevolezza dei limiti di questo approccio rispetto a Tor Browser.

---

## Indice

- [Tor Browser - Architettura interna](#tor-browser--architettura-interna)
- [Protezioni anti-fingerprinting in dettaglio](#protezioni-anti-fingerprinting-in-dettaglio)
- [Protezioni di rete](#protezioni-di-rete)
- [Security Level e NoScript](#security-level-e-noscript)
- [Meccanismo di aggiornamento](#meccanismo-di-aggiornamento)
- [First-Party Isolation in profondità](#first-party-isolation-in-profondità)
- [Firefox + proxychains - Il mio setup e i suoi limiti](#firefox--proxychains--il-mio-setup-e-i-suoi-limiti)
**Approfondimenti** (file dedicati):
- [Applicazioni via Tor](applicazioni-via-tor.md) - Instradamento, compatibilità, SOCKS5 nativo, problemi

---

## Tor Browser - Architettura interna

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

### Canvas fingerprinting - come TB lo blocca

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

### WebRTC - perché è così pericoloso

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

## Firefox + proxychains - Il mio setup e i suoi limiti

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

---

> **Continua in**: [Applicazioni via Tor](applicazioni-via-tor.md) per metodi di
> instradamento, matrice di compatibilità, SOCKS5 nativo e problemi comuni.

---

## Vedi anche

- [Applicazioni via Tor](applicazioni-via-tor.md) - Instradamento, compatibilità, problemi
- [ProxyChains - Guida Completa](proxychains-guida-completa.md) - LD_PRELOAD, chain modes
- [torsocks](torsocks.md) - Confronto con proxychains, blocco UDP
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) - Vettori di fingerprinting
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
