# Fingerprinting — Browser, Rete e Sistema Operativo

Questo documento analizza tutti i vettori di fingerprinting che possono compromettere
l'anonimato di un utente Tor: dal browser fingerprinting al TLS fingerprinting,
passando per OS fingerprinting e tecniche di tracking avanzate.

Basato sulla mia consapevolezza che il mio setup (Firefox+proxychains) NON protegge
dal fingerprinting, a differenza di Tor Browser.

---

## Browser Fingerprinting

### Cos'è

Il browser fingerprinting è una tecnica che identifica univocamente un browser
basandosi sulle sue caratteristiche tecniche, senza usare cookie o storage.

### Vettori principali

**1. User-Agent**
```
Firefox normale:  Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
Tor Browser:      Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0
```
Tor Browser si maschera come Windows anche su Linux, per essere indistinguibile
dagli altri utenti Tor Browser su Windows.

Il mio Firefox su Kali rivela: Linux, x86_64, versione specifica → identificabile.

**2. Canvas Fingerprinting**
Un sito può chiedere al browser di renderizzare un'immagine su un elemento `<canvas>`.
Il risultato dipende da: GPU, driver, OS, font rendering engine. Due computer
producono canvas diversi → fingerprint unico.

```javascript
// Il sito esegue:
var canvas = document.createElement('canvas');
var ctx = canvas.getContext('2d');
ctx.fillText('Hello World', 0, 0);
var hash = canvas.toDataURL().hashCode();
// hash è unico per combinazione GPU+driver+OS
```

Tor Browser: randomizza il canvas o chiede conferma.
Il mio Firefox: non protegge.

**3. WebGL Fingerprinting**
Simile al canvas ma usa il rendering 3D. Rivela:
- Modello GPU
- Versione driver
- Estensioni WebGL supportate
- Performance characteristics

**4. Font Fingerprinting**
Il sito misura la dimensione di rendering di testo in font specifici. I font
installati variano per OS e per utente → fingerprint unico.

**5. Audio Fingerprinting (AudioContext)**
Il sito genera un segnale audio e lo elabora con AudioContext. Il risultato
dipende dall'hardware audio → fingerprint.

**6. Dimensioni della finestra**
La dimensione della finestra del browser (inclusa la differenza tra inner e outer)
rivela: risoluzione dello schermo, barre degli strumenti, DPI scaling.

Tor Browser: usa "letterboxing" (aggiunge bordi grigi) per arrotondare le
dimensioni a multipli standard.

### Entropia del fingerprint

Ogni vettore contribuisce bit di entropia al fingerprint totale:

| Vettore | Bit di entropia (circa) |
|---------|------------------------|
| User-Agent | 10-12 bit |
| Canvas | 8-10 bit |
| WebGL | 6-8 bit |
| Font | 8-12 bit |
| Screen resolution | 4-6 bit |
| Timezone | 3-5 bit |
| Language | 3-4 bit |
| Installed plugins | 4-8 bit |
| **Totale** | **~50-70 bit** |

Con 33 bit di entropia si può identificare univocamente ogni persona sulla Terra.
50-70 bit sono più che sufficienti per un fingerprint unico.

---

## TLS Fingerprinting (JA3/JA4)

### Come funziona

Quando un browser apre una connessione HTTPS, invia un TLS ClientHello. Questo
pacchetto contiene:
- Versione TLS supportata
- Cipher suite (lista di algoritmi crittografici)
- Estensioni TLS
- Gruppi di curva ellittica
- Signature algorithms

Ogni browser ha un ClientHello **unico**:

```
Firefox 128 (Linux): TLS 1.3, cipher_suites=[0x1301,0x1302,0x1303,...], extensions=[...]
Chrome 120 (Windows): TLS 1.3, cipher_suites=[0x1301,0x1303,...], extensions=[...]
Tor Browser: TLS 1.3, cipher_suites=[identico a Firefox ESR su Windows]
```

### JA3 Hash

JA3 è un metodo per calcolare un hash del TLS ClientHello:

```
JA3 = MD5(TLSVersion + Ciphers + Extensions + EllipticCurves + EllipticCurveFormats)
```

Questo hash identifica il client. Il JA3 di Tor Browser è noto e diverso da
quello di Firefox normale → un server o un CDN può identificare utenti Tor Browser.

### JA4 (successore di JA3)

JA4 include più informazioni e usa SHA256. È più preciso ma il principio è lo stesso.

### Implicazioni per il mio setup

Il mio Firefox su Kali ha un JA3 diverso da Tor Browser:
- JA3 specifico per Firefox su Linux
- Diverso dalla popolazione di Tor Browser (che usa Firefox ESR su Windows)
- Un server può distinguermi dagli utenti Tor Browser

Non c'è mitigazione semplice per questo: la fingerprint TLS è determinata dal
browser e dalla piattaforma.

---

## OS Fingerprinting

### TCP/IP Stack Fingerprinting

Ogni sistema operativo ha caratteristiche uniche nello stack TCP/IP:
- **TTL iniziale**: Linux=64, Windows=128, macOS=64
- **Window Size**: diverso per OS
- **TCP options**: ordine e valori diversi

Un server che analizza i pacchetti TCP può determinare il tuo OS.

### Implicazione per Tor

L'exit node vede i pacchetti TCP originali (ricostruiti). Se il tuo client Tor
è su Linux e Tor Browser dichiara di essere Windows (user-agent), c'è una
discrepanza: il TCP/IP stack dice Linux, il user-agent dice Windows.

Tor Browser mitiga questo parzialmente, ma la mitigazione non è completa.

---

## Tracking avanzato senza cookie

### HSTS Supercookie

Un sito può impostare HSTS (HTTP Strict Transport Security) per sottodomini
specifici. Il pattern di sottodomini HSTS noti al browser diventa un tracking ID.

**Mitigazione**: Tor Browser resetta HSTS alla chiusura. In Firefox normale,
HSTS persiste.

### ETag Tracking

Il server assegna un ETag unico a ogni utente. Il browser lo include nelle
richieste successive (`If-None-Match`). Funziona come un cookie persistente.

### Favicon Caching

Il browser cache le favicon. Un sito può usare URL di favicon unici per ogni
utente come tracking mechanism.

### TLS Session Resumption

Se il browser riutilizza sessioni TLS (session ID o session ticket), il server
può correlare visite successive.

**Mitigazione**: Tor Browser disabilita la session resumption. Firefox normale
la mantiene.

---

## Il mio livello di protezione reale

| Vettore | Tor Browser | Il mio Firefox+proxychains |
|---------|-------------|---------------------------|
| User-Agent fingerprint | Protetto (uniformato) | **Esposto** (rivela Linux/Kali) |
| Canvas fingerprint | Protetto (randomizzato) | **Esposto** |
| WebGL fingerprint | Protetto (disabilitato) | **Esposto** |
| Font fingerprint | Protetto (font limitati) | **Esposto** |
| TLS/JA3 fingerprint | Specifico ma uniforme tra utenti TB | **Unico** per il mio setup |
| Screen/Window size | Protetto (letterboxing) | **Esposto** |
| Timezone | UTC | **Esposta** (Europe/Rome) |
| Language | en-US | **Esposta** (it-IT o configurazione locale) |
| HSTS tracking | Resettato | **Persistente** |
| Cookie tracking | Isolato per dominio (FPI) | **Non isolato** |

**Conclusione**: il mio setup protegge l'IP ma non il fingerprint. Un sito
sufficientemente sofisticato può correlare le mie visite anche se cambio IP
con NEWNYM.

Per anonimato reale: usare Tor Browser. Per privacy dall'ISP e test: il mio
setup è sufficiente.

---

## Configurazioni minime per ridurre il fingerprinting in Firefox

In `about:config` del profilo `tor-proxy`:

```
privacy.resistFingerprinting = true          # Protezione base (timezone, locale, etc.)
media.peerconnection.enabled = false          # No WebRTC
webgl.disabled = true                         # No WebGL fingerprint
network.http.http3.enabled = false            # No QUIC/UDP
dom.battery.enabled = false                   # No Battery API
dom.gamepad.enabled = false                   # No Gamepad API
media.navigator.enabled = false               # No media devices enumeration
```

`privacy.resistFingerprinting` attiva molte protezioni:
- Timezone forzata a UTC
- Lingua forzata a en-US
- Screen size spoofata
- Precision ridotta per timer (anti-timing attack)
- Canvas readout bloccato (con prompt)

Non è equivalente a Tor Browser, ma è meglio di niente.
