> **Lingua / Language**: Italiano | [English](../en/05-sicurezza-operativa/fingerprinting-avanzato.md)

# Fingerprinting Avanzato - HTTP/2, OS, Tracking e Difese

Vettori di fingerprinting oltre il browser: HTTP/2 SETTINGS, TCP/IP stack, tracking
senza cookie (HSTS, ETag, favicon), server-side fingerprinting, e configurazioni
per ridurre l'esposizione.

> **Estratto da**: [Fingerprinting - Browser, Rete e Sistema Operativo](fingerprinting.md)
> per browser fingerprinting e TLS/JA3.

---

## HTTP/2 Fingerprinting

### Come funziona

HTTP/2 aggiunge un nuovo livello di fingerprinting tramite i parametri della
connessione:

```
HTTP/2 SETTINGS frame (inviato all'inizio della connessione):
- HEADER_TABLE_SIZE
- ENABLE_PUSH
- MAX_CONCURRENT_STREAMS
- INITIAL_WINDOW_SIZE
- MAX_FRAME_SIZE
- MAX_HEADER_LIST_SIZE

Ogni browser invia valori diversi:

Firefox: HEADER_TABLE_SIZE=65536, INITIAL_WINDOW_SIZE=131072,
         MAX_FRAME_SIZE=16384
Chrome:  HEADER_TABLE_SIZE=65536, INITIAL_WINDOW_SIZE=6291456,
         MAX_FRAME_SIZE=16384
Safari:  HEADER_TABLE_SIZE=4096, INITIAL_WINDOW_SIZE=4194304,
         MAX_FRAME_SIZE=16384

→ I SETTINGS identificano il browser
→ Combinati con JA3 → fingerprint molto preciso
```

### HTTP/2 PRIORITY fingerprinting

```
I browser inviano priorità diverse per le risorse:

Chrome: usa PRIORITY frame con dependency tree complesso
Firefox: usa PRIORITY con weight-based scheme
Safari: usa PRIORITY in modo diverso

Il pattern di priorità è un fingerprint aggiuntivo.
```

---

## OS Fingerprinting

### TCP/IP Stack Fingerprinting

Ogni sistema operativo ha caratteristiche uniche nello stack TCP/IP:

```
Parametri analizzabili (passivamente, dal server):

TTL iniziale:
  Linux: 64
  Windows: 128
  macOS: 64
  FreeBSD: 64

TCP Window Size:
  Linux (kernel 5.x+): 64240
  Windows 10/11: 64240 o 65535
  macOS: 65535

TCP Options (ordine e valori):
  Linux: MSS, SackOK, TS val/ecr, NOP, WScale
  Windows: MSS, NOP, WScale, NOP, NOP, SackOK
  macOS: MSS, NOP, WScale, NOP, NOP, TS val/ecr, SackOK, EOL

DF bit (Don't Fragment):
  Linux: set
  Windows: set
  macOS: set

→ Un server che analizza questi parametri può determinare il tuo OS
  ANCHE se il User-Agent dichiara un OS diverso
```

### Implicazione per Tor

```
Scenario:
  Il mio Tor Browser (o Firefox con resistFingerprinting):
    User-Agent: "Windows NT 10.0"
    TCP/IP stack: TTL=64, Window=64240, Options=Linux-order
    → DISCREPANZA: User-Agent dice Windows, TCP dice Linux

Il server vede:
  "Questo utente dichiara Windows ma ha stack TCP Linux"
  → Probabile: utente Linux che spoofa l'User-Agent
  → Riduce il set di anonimato enormemente

Tor Browser mitiga parzialmente:
  → Normalizza alcuni parametri TCP (WScale, MSS)
  → Ma il TTL e l'ordine delle opzioni TCP sono difficili da spoofar
    senza modifica del kernel
```

### Difesa: network namespace o VM

```
Su Whonix:
  La Workstation è una VM → il suo TCP stack è quello della VM
  Il Gateway trasmette via Tor → il server vede il TCP stack dell'exit
  → Il TCP fingerprint del CLIENT non raggiunge il server
  → Protezione completa

Sul mio setup:
  Il mio TCP stack raggiunge l'exit Tor
  L'exit ricostruisce la connessione TCP verso il server
  → Il server vede il TCP stack dell'EXIT, non del mio PC
  → Parzialmente protetto (ma il guard vede il mio TCP)
```

---

## Tracking avanzato senza cookie

### HSTS Supercookie

```
Un sito può impostare HSTS per sottodomini specifici:
  a.example.com → HSTS = ON  (bit 1)
  b.example.com → HSTS = OFF (bit 0)
  c.example.com → HSTS = ON  (bit 1)
  d.example.com → HSTS = OFF (bit 0)

Il pattern HSTS noti al browser: 1010 = tracking ID univoco

Alla visita successiva:
  Il browser tenta HTTP per ogni sottodominio
  a.example.com → redirect HTTPS (HSTS attivo → bit 1)
  b.example.com → nessun redirect (HSTS non attivo → bit 0)
  → Ricostruisce il pattern → identifica l'utente

Mitigazione: Tor Browser resetta HSTS alla chiusura.
Il mio Firefox: HSTS persiste tra sessioni.
```

### ETag Tracking

```
1. Prima visita: server assegna ETag unico
   Response: ETag: "user-unique-id-abc123"
2. Seconda visita: browser include l'ETag
   Request: If-None-Match: "user-unique-id-abc123"
   → Il server riconosce l'utente tramite l'ETag
   → Funziona come un cookie persistente ma invisibile
```

### Favicon Caching

```
Il browser cachea le favicon. Un sito può usare URL unici:
1. Primo accesso: il sito imposta favicon come /favicon-USER123.ico
2. Il browser cachea questa favicon specifica
3. Accesso successivo: il browser richiede /favicon-USER123.ico
   → Il server vede che USER123 è tornato
   → Tracking senza cookie
```

### TLS Session Resumption

```
Se il browser riutilizza sessioni TLS (session ID o session ticket):
1. Prima connessione: handshake TLS completo
   Server assegna session ticket: "ticket-xyz"
2. Connessione successiva: browser presenta "ticket-xyz"
   → Server riconosce il client → tracking cross-session

Tor Browser: disabilita session resumption
Il mio Firefox: session resumption attiva
```

### DNS Cache Probing

```
Un sito può determinare quali siti hai visitato recentemente:
1. Il sito include risorse da domini specifici:
   <img src="https://visited-site.com/pixel.gif">
2. Se il DNS per visited-site.com è nella cache → risposta rapida
3. Se non è nella cache → risposta lenta (round-trip DNS)
4. La differenza di timing rivela se hai visitato visited-site.com

Mitigazione: DNS via Tor (risolto dall'exit, non localmente)
→ Il mio setup è parzialmente protetto (con proxy_dns)
```

---

## Server-side fingerprinting

### Behavioral fingerprinting

```
Un sito può tracciare il comportamento dell'utente:
- Velocità di digitazione (keystroke dynamics)
- Pattern di movimento del mouse
- Velocità di scroll
- Pattern di click
- Tempo di permanenza sulle pagine

Questi pattern sono UNICI per ogni persona
→ Nessuno strumento tecnico li protegge
→ Solo la consapevolezza e la variazione del comportamento
```

### Timing fingerprinting

```
Il server misura il RTT (round-trip time) delle richieste:
- RTT costante → stessa posizione di rete
- RTT variabile in un pattern → ISP/rete specifica

Via Tor: il RTT è dominato dai 3 hop → varia con i circuiti
→ Meno informativo ma non completamente opaco
```

---

## Fingerprinting attivo vs passivo

### Passivo (server-side)

```
Il server raccoglie informazioni senza eseguire codice nel browser:
- User-Agent header
- Accept-Language header
- TLS ClientHello (JA3/JA4)
- HTTP/2 SETTINGS
- TCP/IP stack parameters
- Timing

Difesa: difficile, molte di queste informazioni sono necessarie
per la comunicazione
```

### Attivo (JavaScript)

```
Il server esegue JavaScript nel browser:
- Canvas fingerprinting
- WebGL rendering
- AudioContext
- Font enumeration
- Screen dimensions
- navigator.* properties
- Battery API
- Gamepad API
- Performance.now() timing

Difesa: Tor Browser neutralizza la maggior parte
        Security Level "Safest" disabilita JavaScript → elimina tutto
```

---

## Il mio livello di protezione reale

| Vettore | Tor Browser | Il mio Firefox+proxychains |
|---------|-------------|---------------------------|
| User-Agent fingerprint | Protetto (uniformato) | **Esposto** (rivela Linux/Kali) |
| Canvas fingerprint | Protetto (randomizzato) | **Esposto** |
| WebGL fingerprint | Protetto (disabilitato) | **Esposto** |
| Font fingerprint | Protetto (font limitati) | **Esposto** |
| TLS/JA3 fingerprint | Specifico ma uniforme tra utenti TB | **Unico** per il mio setup |
| HTTP/2 fingerprint | Uniforme | **Specifico** |
| Screen/Window size | Protetto (letterboxing) | **Esposto** |
| Timezone | UTC | **Esposta** (Europe/Rome) |
| Language | en-US | **Esposta** (it-IT) |
| HSTS tracking | Resettato | **Persistente** |
| Cookie tracking | Isolato per dominio (FPI) | **Non isolato** |
| TCP/IP OS fingerprint | Parziale (exit ricostruisce) | Parziale |
| AudioContext | Neutralizzato | **Esposto** |
| Behavioral | Non protetto | Non protetto |

**Conclusione**: il mio setup protegge l'IP ma non il fingerprint. Un sito
sufficientemente sofisticato può correlare le mie visite anche se cambio IP
con NEWNYM, perché il mio fingerprint è costante e probabilmente unico.

---

## Strumenti di verifica

### Siti per testare il proprio fingerprint

```bash
# AmIUnique - analisi dettagliata del fingerprint
proxychains firefox https://amiunique.org/fingerprint

# Panopticlick (EFF) - test di unicità
proxychains firefox https://coveryourtracks.eff.org/

# BrowserLeaks - test per vettore specifico
proxychains firefox https://browserleaks.com/

# CreepJS - fingerprinting avanzato (canvas, WebGL, etc.)
proxychains firefox https://abrahamjuliot.github.io/creepjs/

# TLS fingerprint (JA3)
proxychains firefox https://ja3.io/
```

### Test da terminale

```bash
# Verifica User-Agent
proxychains curl -s https://httpbin.org/headers | grep User-Agent

# Verifica IP e geolocalizzazione
proxychains curl -s https://ipinfo.io

# Verifica TLS fingerprint
proxychains curl -s https://ja3.io/json | python3 -m json.tool
```

---

## Configurazioni per ridurre il fingerprinting

In `about:config` del profilo `tor-proxy`:

```
# Protezione base (attiva molte mitigazioni)
privacy.resistFingerprinting = true

# Disabilita API pericolose
media.peerconnection.enabled = false          # No WebRTC
webgl.disabled = true                         # No WebGL fingerprint
dom.battery.enabled = false                   # No Battery API
dom.gamepad.enabled = false                   # No Gamepad API
media.navigator.enabled = false               # No media devices
network.http.http3.enabled = false            # No QUIC/UDP

# Disabilita tracking vectors
network.http.http3.enabled = false            # No HTTP/3
browser.send_pings = false                    # No tracking pings
beacon.enabled = false                        # No Beacon API
```

`privacy.resistFingerprinting` attiva molte protezioni:
- Timezone forzata a UTC
- Lingua forzata a en-US
- Screen size spoofata
- Precision ridotta per Performance.now() (anti-timing)
- Canvas readout bloccato (con prompt)
- navigator.hardwareConcurrency forzato a 2
- navigator.platform spoofato

**Non è equivalente a Tor Browser**, ma è meglio di niente. Il JA3 e i font
restano esposti, e l'incoerenza tra User-Agent spoofato e TCP stack reale
può essere più sospetta del non spoofing.

---

## Nella mia esperienza

Il fingerprinting è il tallone d'Achille del mio setup. Lo accetto
consapevolmente perché il mio threat model non richiede anonimato dal
fingerprinting - ho bisogno di privacy dall'ISP (nascondere le destinazioni)
e dai tracker basati su IP.

Per anonimato reale dal fingerprinting: Tor Browser è l'unica soluzione.
Per privacy dall'ISP e test: il mio Firefox+proxychains è sufficiente.

---

## Vedi anche

- [Tor Browser e Applicazioni](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Come Tor Browser mitiga il fingerprinting
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - Fingerprinting come errore OPSEC
- [Traffic Analysis](traffic-analysis.md) - Fingerprinting del traffico di rete
- [DNS Leak](dns-leak.md) - DNS come vettore di fingerprinting
- [Hardening di Sistema](hardening-sistema.md) - Configurazioni Firefox nel profilo tor-proxy
