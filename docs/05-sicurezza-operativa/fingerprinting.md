# Fingerprinting - Browser, Rete e Sistema Operativo

Questo documento analizza tutti i vettori di fingerprinting che possono compromettere
l'anonimato di un utente Tor: dal browser fingerprinting al TLS fingerprinting,
passando per OS fingerprinting, HTTP/2 fingerprinting, e tecniche di tracking avanzate
senza cookie. Per ogni vettore, analizzo come funziona, quanta entropia contribuisce,
e come Tor Browser lo mitiga rispetto al mio setup Firefox+proxychains.

Basato sulla mia consapevolezza che il mio setup (Firefox+proxychains) NON protegge
dal fingerprinting, a differenza di Tor Browser.

---

## Indice

- [Cos'è il fingerprinting](#cosè-il-fingerprinting)
- [Browser Fingerprinting](#browser-fingerprinting)
- [TLS Fingerprinting (JA3/JA4)](#tls-fingerprinting-ja3ja4)
**Approfondimenti** (file dedicati):
- [Fingerprinting Avanzato](fingerprinting-avanzato.md) - HTTP/2, OS, tracking senza cookie, strumenti, configurazioni

---

## Cos'è il fingerprinting

Il fingerprinting è una tecnica che identifica univocamente un browser (e quindi
un utente) basandosi sulle sue caratteristiche tecniche, **senza usare cookie,
localStorage o alcun meccanismo di storage esplicito**.

### Perché è efficace

```
Entropia necessaria per identificare una persona:
  - Popolazione mondiale: 8 miliardi → 33 bit di entropia
  - Utenti internet: 5 miliardi → 32.2 bit
  - Utenti Tor: ~2-4 milioni → 21-22 bit

Un browser fingerprint tipico: 50-70 bit di entropia
→ Più che sufficienti per identificare UNIVOCAMENTE
  qualsiasi persona sulla Terra

Il problema: ogni "scelta" del browser aggiunge entropia
  - OS: Linux → ~2% degli utenti web → 5.6 bit
  - Lingua: it-IT → ~2% → 5.6 bit
  - Timezone: CET → ~3% → 5 bit
  - Font installati: combinazione unica → 8-12 bit
  - Canvas: rendering unico → 8-10 bit
  Totale parziale: già ~30 bit con 5 caratteristiche
```

### Due approcci al fingerprinting

```
1. Rendere il fingerprint UNICO (il problema):
   Ogni browser ha caratteristiche diverse
   → Identificazione univoca possibile
   → Tracking persistente senza cookie

2. Rendere il fingerprint UNIFORME (la soluzione Tor Browser):
   Tutti gli utenti Tor Browser hanno lo STESSO fingerprint
   → L'utente si "nasconde nella folla"
   → Il fingerprint identifica "utente Tor Browser" ma non QUALE utente
```

---

## Browser Fingerprinting

### Vettori principali

**1. User-Agent**

```
Firefox normale (il mio):
  Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
  → Rivela: Linux, x86_64, Firefox 128
  → Pool: ~0.1% degli utenti web

Tor Browser:
  Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0
  → Si maschera come Windows anche su Linux
  → Pool: tutti gli utenti Tor Browser (milioni)
  → Indistinguibile dagli altri utenti TB

Entropia: 10-12 bit
```

**2. Canvas Fingerprinting**

Un sito può chiedere al browser di renderizzare un'immagine su un elemento `<canvas>`.
Il risultato dipende da: GPU, driver, OS, font rendering engine, antialiasing.

```javascript
// Il sito esegue:
var canvas = document.createElement('canvas');
var ctx = canvas.getContext('2d');
ctx.textBaseline = "top";
ctx.font = "14px 'Arial'";
ctx.fillStyle = "#f60";
ctx.fillRect(125, 1, 62, 20);
ctx.fillStyle = "#069";
ctx.fillText("Cwm fjordbank", 2, 15);
var hash = canvas.toDataURL().hashCode();
// hash è UNICO per combinazione GPU+driver+OS+rendering

// Due computer con la stessa GPU ma driver diversi
// producono canvas DIVERSI → fingerprint unico
```

```
Tor Browser: randomizza il canvas output o chiede conferma
  → Ogni sessione produce un hash diverso → no tracking
  → Prompt: "Questo sito vuole estrarre dati dal canvas. Permettere?"

Il mio Firefox: nessuna protezione
  → Il canvas hash è costante → tracking persistente

Entropia: 8-10 bit
```

**3. WebGL Fingerprinting**

Simile al canvas ma usa il rendering 3D:

```javascript
var gl = canvas.getContext('webgl');
var debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
var vendor = gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL);
var renderer = gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
// vendor: "Intel Inc."
// renderer: "Intel(R) UHD Graphics 630"
// → Identifica esattamente la GPU
```

Informazioni rivelate:
- Modello GPU esatto
- Versione driver
- Estensioni WebGL supportate (lista unica per GPU)
- Performance characteristics (timing del rendering)
- Shader precision format

```
Tor Browser: WebGL disabilitato o spoofato
Il mio Firefox: completamente esposto

Entropia: 6-8 bit
```

**4. Font Fingerprinting**

Il sito misura la dimensione di rendering di testo in centinaia di font:

```javascript
// Il sito crea un elemento <span> con testo di riferimento
// Lo rende in un font di fallback (es. monospace)
// Poi cambia il font a uno specifico (es. "Courier New")
// Se le dimensioni cambiano → il font è installato
// La LISTA dei font installati è un fingerprint

// Font comuni su Linux (il mio caso):
// DejaVu Sans, Liberation Mono, Cantarell, etc.
// Font comuni su Windows:
// Arial, Calibri, Cambria, Comic Sans, etc.
// → La lista è diversa per OS → fingerprint unico
```

```
Tor Browser: carica solo un set limitato di font bundled
  → Tutti gli utenti TB hanno gli stessi font → no fingerprint
Il mio Firefox: tutti i font di sistema sono visibili

Entropia: 8-12 bit
```

**5. Audio Fingerprinting (AudioContext)**

```javascript
var audioCtx = new (window.AudioContext || window.webkitAudioContext)();
var oscillator = audioCtx.createOscillator();
var analyser = audioCtx.createAnalyser();
var gain = audioCtx.createGain();

oscillator.connect(analyser);
analyser.connect(gain);
gain.connect(audioCtx.destination);

// L'output audio dipende dall'hardware audio
// Il fingerprint è un hash dell'output elaborato
// Diverso per ogni combinazione hardware/driver
```

```
Tor Browser: AudioContext API neutralizzata
Il mio Firefox: completamente esposto

Entropia: 4-6 bit
```

**6. Dimensioni della finestra**

```
La dimensione della finestra del browser rivela:
- Risoluzione dello schermo
- Barre degli strumenti attive
- DPI scaling
- Numero di monitor (con window.screen)
- Posizione della finestra

Tor Browser: "letterboxing" - aggiunge bordi grigi per arrotondare
  Finestra reale: 1367 × 843
  Riportata al sito: 1200 × 800 (multiplo di 200 × 100)
  → Tutti gli utenti con finestre simili hanno lo stesso valore

Il mio Firefox: dimensioni reali esposte

Entropia: 4-6 bit
```

**7. Navigator properties**

```javascript
navigator.hardwareConcurrency  // Numero di CPU logiche
// Il mio: 8 → rivela classe di CPU
// Tor Browser: sempre 2

navigator.deviceMemory         // RAM in GB (approssimata)
// Il mio: 16 → rivela classe di computer
// Tor Browser: non esposta

navigator.maxTouchPoints       // Touchscreen
// Desktop: 0, Tablet: 5-10
// Tor Browser: sempre 0

navigator.languages            // Lingue preferite
// Il mio: ["it-IT", "it", "en-US", "en"]
// Tor Browser: ["en-US", "en"]

navigator.platform             // Piattaforma
// Il mio: "Linux x86_64"
// Tor Browser: "Win32" (anche su Linux!)
```

### Entropia totale del fingerprint

| Vettore | Bit di entropia (circa) | Tor Browser | Il mio Firefox |
|---------|------------------------|-------------|----------------|
| User-Agent | 10-12 bit | Uniforme | **Esposto** |
| Canvas | 8-10 bit | Randomizzato | **Esposto** |
| WebGL | 6-8 bit | Disabilitato | **Esposto** |
| Font | 8-12 bit | Limitati | **Esposto** |
| Screen/Window | 4-6 bit | Letterboxing | **Esposto** |
| Timezone | 3-5 bit | UTC | **Esposto** (CET) |
| Language | 3-4 bit | en-US | **Esposto** (it-IT) |
| AudioContext | 4-6 bit | Neutralizzato | **Esposto** |
| Plugins | 4-8 bit | Nessuno visibile | **Esposto** |
| navigator.* | 4-6 bit | Valori fissi | **Esposto** |
| **Totale** | **~55-80 bit** | **~5-8 bit** (uniforme) | **~55-80 bit** (unico) |

Con Tor Browser: ~5-8 bit → "sei un utente Tor Browser" (milioni di persone).
Con il mio Firefox: ~55-80 bit → "sei TU" (probabilmente unico al mondo).

---

## TLS Fingerprinting (JA3/JA4)

### Come funziona

Quando un browser apre una connessione HTTPS, invia un TLS ClientHello.
Questo pacchetto contiene parametri unici per ogni browser:

```
TLS ClientHello contiene:
- TLS version supportata
- Cipher suites (lista ordinata di algoritmi crittografici)
- Extensions TLS (lista ordinata)
- Supported groups (curve ellittiche)
- Signature algorithms
- ALPN (protocolli applicativi: h2, http/1.1)
- Key share groups

Ogni browser ha un ClientHello UNICO:

Firefox 128 (Linux):
  TLS 1.3, cipher_suites=[0x1301,0x1302,0x1303,0xc02b,0xc02f,...],
  extensions=[0x0000,0x0017,0x002b,...], groups=[x25519,secp256r1,...]

Chrome 120 (Windows):
  TLS 1.3, cipher_suites=[0x1301,0x1303,0xc02b,...],
  extensions=[0x0000,0x0017,...], groups=[x25519,secp256r1,secp384r1,...]

Tor Browser:
  TLS 1.3, cipher_suites=[identico a Firefox ESR su Windows]
  → Coerente con il user-agent dichiarato
```

### JA3 Hash

```
JA3 = MD5(
    TLSVersion,
    Ciphers (lista ordinata),
    Extensions (lista ordinata),
    EllipticCurves,
    EllipticCurveFormats
)

Esempio:
  JA3 del mio Firefox su Kali: e7d705a3286e19ea42f587b344ee6865
  JA3 di Tor Browser: 839bbe3ed07fed922ded5aaf714d6842
  JA3 di Chrome su Windows: b32309a26951912be7dba376398abc3b

→ Un server che calcola il JA3 può:
  1. Identificare il tipo di browser
  2. Verificare coerenza con il User-Agent dichiarato
  3. Bloccare specifici browser/client
```

### JA4 (successore di JA3)

```
JA4 è più granulare:
- Usa SHA256 (non MD5)
- Include ALPN, signature algorithms
- Formato leggibile: "t13d1517h2_8daaf6152771_b0da82dd1658"
  t = TLS, 13 = versione, d = protocollo, 15 = cipher count,
  17 = extension count, h2 = ALPN
- Più preciso per fingerprinting
```

### Implicazioni per il mio setup

```
Il mio Firefox su Kali:
  JA3: specifico per Firefox su Linux
  → Diverso dalla popolazione Tor Browser (Firefox ESR su Windows)
  → Un server/CDN può distinguermi dagli utenti Tor Browser

Il problema della coerenza:
  User-Agent: "Linux x86_64" (se non spoofato)
  JA3: Firefox su Linux
  → Coerente, ma identifica come "Firefox Linux" non "Tor Browser"

Con resistFingerprinting:
  User-Agent: spoofato a "Windows NT 10.0" (parziale)
  JA3: resta Firefox Linux (non spoofabile a livello browser)
  → INCOERENZA: User-Agent dice Windows, JA3 dice Linux
  → Più sospetto che senza spoofing!
```

Non c'è mitigazione semplice per il JA3: il fingerprint TLS è determinato dal
browser e dalla piattaforma a livello di codice compilato.

---

> **Continua in**: [Fingerprinting Avanzato](fingerprinting-avanzato.md) per HTTP/2,
> OS fingerprinting, tracking senza cookie, strumenti di verifica e configurazioni difensive.

---

## Vedi anche

- [Fingerprinting Avanzato](fingerprinting-avanzato.md) - HTTP/2, OS, tracking, strumenti, configurazioni
- [Tor Browser e Applicazioni](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Come Tor Browser mitiga il fingerprinting
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - Fingerprinting come errore OPSEC
- [Traffic Analysis](traffic-analysis.md) - Fingerprinting del traffico di rete
- [Hardening di Sistema](hardening-sistema.md) - Configurazioni Firefox nel profilo tor-proxy
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
