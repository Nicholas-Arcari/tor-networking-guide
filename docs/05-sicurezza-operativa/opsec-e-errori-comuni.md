> **Lingua / Language**: Italiano | [English](../en/05-sicurezza-operativa/opsec-e-errori-comuni.md)

# OPSEC e Errori Comuni - Cosa Può Deanonimizzarti

Questo documento cataloga gli errori di OPSEC (Operational Security) più comuni
nell'uso di Tor, le tecniche di deanonimizzazione basate sul comportamento umano,
casi reali dove utenti sono stati identificati nonostante Tor, e una checklist
operativa completa.

Nella mia esperienza, la maggior parte delle deanonimizzazioni non avviene per
vulnerabilità tecniche di Tor, ma per errori umani. Tor è uno strumento: la sua
efficacia dipende da come lo usi.

---

## Indice

- [Il principio fondamentale dell'OPSEC](#il-principio-fondamentale-dellopsec)
- [Errori di OPSEC che annullano l'anonimato di Tor](#errori-di-opsec-che-annullano-lanonimato-di-tor)
- [Errori avanzati: metadata e correlazione](#errori-avanzati-metadata-e-correlazione)
**Approfondimenti** (file dedicati):
- [OPSEC - Casi Reali, Stylometry e Difese](opsec-casi-reali-e-difese.md) - Casi reali, stylometry, crypto, checklist, threat model

---

## Il principio fondamentale dell'OPSEC

L'OPSEC si basa su un concetto semplice: **un singolo errore può annullare
mesi di comportamento corretto**. L'anonimato non è uno stato binario ma
una catena: basta che un anello si rompa per compromettere tutto.

```
OPSEC = min(sicurezza di ogni singola azione)

100 connessioni anonime + 1 connessione con leak = COMPROMESSO
1 anno di anonimato + 1 login con account reale = COMPROMESSO
Setup perfetto + 1 post con informazione personale = COMPROMESSO
```

L'avversario non deve rompere Tor. Deve solo trovare il tuo errore.

### Le 5 regole d'oro

1. **Mai mescolare identità anonime con identità reali**
2. **Mai fidarsi di una singola protezione** (defense in depth)
3. **Il comportamento è un fingerprint** quanto la tecnologia
4. **Un errore passato può emergere in futuro** (i log esistono)
5. **L'avversario ha più tempo e risorse di te**

---

## Errori di OPSEC che annullano l'anonimato di Tor

### 1. Login con account personali

**L'errore**: navighi via Tor, poi fai login su Gmail, Facebook, o Amazon con
il tuo account personale. Ora il sito sa chi sei, anche se il tuo IP è quello
dell'exit node.

**Perché è grave**: l'anonimato di Tor protegge l'IP. Se dici al sito chi sei
(login), l'IP è irrilevante. Inoltre, il sito può correlare la tua sessione
anonima con sessioni passate/future tramite cookie, fingerprint del browser,
o timing.

**Correlazione cross-session**:
```
Sessione 1 (anonima): visiti forum-x.com, leggi thread specifici
Sessione 2 (stessa ora): login su Gmail dal tuo PC
→ Google sa che usi Tor e conosce il tuo pattern temporale
→ Un avversario con accesso ai log di entrambi può correlare
```

**Regola**: non accedere MAI ad account personali su Tor. Se devi accedere
a un servizio, crea un account dedicato esclusivamente per l'uso via Tor.

### 2. Usare Tor e non-Tor contemporaneamente

**L'errore**: hai due finestre del browser aperte - una via Tor, una normale.
Visiti lo stesso sito in entrambe. Il sito correla le sessioni tramite cookie,
fingerprint, o timing.

**Lo scenario specifico**:
```
Finestra 1 (Tor): visiti forum.example.com da IP exit 185.220.101.x
Finestra 2 (normale): visiti forum.example.com dal tuo IP reale 151.x.x.x
Timing: entrambe le connessioni avvengono alle 14:32
→ Il server vede due sessioni simultanee dallo stesso browser fingerprint
→ Correlazione: l'utente con IP 185.220.101.x è 151.x.x.x
```

**Regola**: se usi Tor per un'attività, NON fare la stessa attività senza Tor
contemporaneamente. Idealmente, usa computer o VM separate.

### 3. Scaricare e aprire file senza precauzioni

**L'errore**: scarichi un PDF via Tor, lo apri con il lettore PDF del sistema.
Il lettore PDF fa richieste HTTP (per font, immagini esterne, tracking pixel)
che escono SENZA passare da Tor → rivelano il tuo IP reale.

**File pericolosi**:
```
PDF:   Può contenere JavaScript, link esterni, tracking pixel
DOCX:  Può caricare template remoti, immagini da URL
XLSX:  Può contenere link a dati esterni
HTML:  Ovviamente può caricare qualsiasi risorsa esterna
SVG:   Può contenere JavaScript e riferimenti esterni
ODT:   Può caricare risorse remote
Torrent: DHT/PEX rivelano l'IP reale (vedi errore #8)
```

**Regola**: non aprire file scaricati via Tor in applicazioni che fanno rete.
Aprirli in una VM disconnessa dalla rete, oppure convertirli in formato
sicuro (es. PDF → immagine) prima di visualizzarli.

### 4. Informazioni nell'User-Agent e nei metadata

**L'errore**: il tuo browser rivela OS (Kali Linux), architettura (x86_64),
versione esatta (Firefox 128). Queste informazioni restringono il pool di
utenti possibili.

**Cosa rivela il mio Firefox**:
```
User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0
→ OS: Linux (minoranza: ~2% degli utenti web)
→ Arch: x86_64
→ Browser: Firefox 128 su Linux
→ Pool stimato: ~0.1% degli utenti web

Tor Browser User-Agent: Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0
→ Pool: tutti gli utenti Tor Browser (milioni)
→ Indistinguibile dagli altri utenti TB
```

**Regola**: usare Tor Browser (user-agent uniformato). O almeno attivare
`privacy.resistFingerprinting` in Firefox per spoofing parziale.

### 5. DNS leak

**L'errore**: le query DNS escono in chiaro verso l'ISP, rivelando quali
siti stai visitando.

**Regola**: `proxy_dns` in proxychains, `--socks5-hostname` con curl,
`DNSPort` nel torrc. Vedi il documento dedicato sui DNS leak.

### 6. WebRTC leak

**L'errore**: WebRTC nel browser rivela l'IP locale e pubblico reale,
anche attraverso un proxy SOCKS5.

**Come funziona il leak**:
```javascript
// JavaScript nel browser:
var pc = new RTCPeerConnection({iceServers: []});
pc.createDataChannel('');
pc.createOffer().then(offer => pc.setLocalDescription(offer));
pc.onicecandidate = event => {
    // event.candidate contiene il tuo IP reale!
    // Es: "candidate:0 1 UDP 2122252543 192.168.1.100 44323 typ host"
    // L'IP 192.168.1.100 è il tuo IP locale
};
```

**Regola**: `media.peerconnection.enabled = false` in about:config.
In Tor Browser è già disabilitato.

### 7. Timezone e lingua del browser

**L'errore**: il browser rivela timezone=Europe/Rome e lingua=it-IT.
Con 33 bit di entropia si identifica una persona. Timezone + lingua
aggiungono ~8 bit, restringendo significativamente il pool.

**Calcolo**:
```
Utenti Tor stimati: ~2 milioni
Timezone Europe/Rome: ~3% → 60.000
Lingua it-IT: ~2% → 1.200
+ Kali Linux: ~0.5% → 6
→ Con solo timezone + lingua + OS, il pool è di ~6 persone
```

**Regola**: `privacy.resistFingerprinting = true` (forza UTC e en-US).

### 8. Torrenting via Tor

**L'errore**: usi BitTorrent via Tor. Il client BitTorrent rivela il tuo IP
reale attraverso DHT (Distributed Hash Table) e PEX (Peer Exchange), che
non passano dal proxy.

**Il problema tecnico**:
```
BitTorrent tracker: comunica via TCP → può passare da Tor
DHT: comunica via UDP → NON può passare da Tor → leak IP reale
PEX: scambia IP con altri peer → contiene il tuo IP reale
uTP: usa UDP → NON può passare da Tor

Anche disabilitando DHT/PEX/uTP, il client potrebbe:
- Inviare il tuo IP reale nel campo "ip" dell'announce al tracker
- Fare richieste DNS per il tracker fuori da Tor
```

**Regola**: non usare MAI BitTorrent via Tor. Oltre al leak, sovraccarica
la rete Tor (che è pensata per traffico a bassa latenza, non file sharing).

### 9. Eseguire JavaScript non fidato

**L'errore**: JavaScript di un sito malevolo può sfruttare vulnerabilità
del browser per ottenere il tuo IP reale.

**Vettori di attacco JavaScript**:
```
WebRTC → rivela IP (se non disabilitato)
DNS rebinding → connessione a localhost
Browser exploit → esecuzione codice arbitrario
Timing side-channel → deanonimizzazione tramite timing
Canvas/WebGL → fingerprinting unico
Audio API → fingerprinting hardware
```

**Regola**: Tor Browser ha un "Security Level" che limita JavaScript:
- **Standard**: JavaScript abilitato (meno sicuro, più usabile)
- **Safer**: JavaScript disabilitato su siti non-HTTPS, no media
- **Safest**: JavaScript disabilitato ovunque, solo contenuto statico

### 10. Pattern di comportamento unico

**L'errore**: visiti sempre gli stessi 5 siti, allo stesso orario, con lo
stesso pattern di navigazione. Anche senza fingerprint tecnico, il tuo
*comportamento* è un fingerprint.

**Esempio**:
```
Pattern osservato su exit Tor (o dal sito):
- Ogni giorno alle 08:30: news-site-a.com
- Ogni giorno alle 09:00: forum-b.com, thread specifici
- Ogni lunedì alle 14:00: service-c.com
- Lingua: italiano, timezone hints in post
→ Anche cambiando IP con NEWNYM, il pattern è identificabile
→ Se lo stesso pattern appare senza Tor → correlazione
```

**Regola**: variare pattern, non usare Tor per routine prevedibili.
Usare NEWNYM tra sessioni diverse. Non rivelare timezone nei post.

---

## Errori avanzati: metadata e correlazione

### Metadata nei documenti

I file che carichi contengono metadata invisibili:

```bash
# Metadata in un documento Word/LibreOffice:
exiftool documento.docx
# Author: Nick Arcari
# Creator: LibreOffice 7.5
# Create Date: 2024-03-15 14:23:42+01:00  ← timezone!
# Producer: Kali Linux

# Metadata in un'immagine:
exiftool foto.jpg
# GPS Latitude: 44.801485    ← posizione esatta!
# GPS Longitude: 10.328946   ← Parma!
# Camera Model: iPhone 15 Pro
# Date/Time: 2024-03-15 09:45:23
```

**Regola**: pulire TUTTI i metadata prima di caricare file:
```bash
# Rimuovi metadata da immagini
exiftool -all= foto.jpg

# Rimuovi metadata da PDF
exiftool -all= documento.pdf

# Per documenti Office: salva come PDF, poi pulisci il PDF
# Oppure usa mat2 (Metadata Anonymization Toolkit 2):
mat2 documento.docx
```

### Correlazione temporale tra sessioni

```
L'avversario osserva:
1. Connessione Tor inizia alle 08:30 (visibile dall'ISP)
2. Post anonimo su forum alle 08:32
3. Connessione Tor termina alle 09:15
4. Questo pattern si ripete ogni giorno

L'avversario conosce:
- L'utente è nel fuso orario CET (+01:00)
- L'utente è attivo 08:30-09:15 ogni giorno
- L'ISP registra che 151.x.x.x inizia Tor alle 08:30 ogni giorno
→ Correlazione: l'utente anonimo è 151.x.x.x
```

### Correlazione tramite dimensione delle risposte

```
Un ISP che osserva il traffico Tor può vedere:
- Volume totale di dati scaricati in una sessione
- Pattern di burst (es. caricamento pagina = burst rapido)

Se l'ISP ha accesso ai log del server di destinazione:
- Il server registra dimensione della risposta per ogni richiesta
- Correlazione: la sessione Tor con volume X corrisponde alla richiesta Y
```

### Errore di compartimentazione

```
Identità A (anonima): usa Tor, scrive su forum X
Identità B (reale): usa email, social media

ERRORE: usa la stessa password per entrambe le identità
ERRORE: usa lo stesso stile di scrittura
ERRORE: menziona le stesse informazioni personali
ERRORE: usa lo stesso provider email (anche con account diverso)
ERRORE: accede a entrambe dalla stessa rete WiFi
```

---

---

> **Continua in**: [OPSEC - Casi Reali, Stylometry e Difese](opsec-casi-reali-e-difese.md)
> per casi di deanonimizzazione (Silk Road, AlphaBay), stylometry, cryptocurrency
> e checklist operativa.

---

## Vedi anche

- [OPSEC - Casi Reali, Stylometry e Difese](opsec-casi-reali-e-difese.md) - Casi reali, stylometry, crypto, checklist
- [DNS Leak](dns-leak.md) - Prevenzione completa dei DNS leak
- [Fingerprinting](fingerprinting.md) - Vettori di fingerprinting browser, rete, OS
- [Traffic Analysis](traffic-analysis.md) - Correlazione end-to-end, website fingerprinting
- [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) - Whonix, Tails, Qubes
- [Analisi Forense e Artefatti](analisi-forense-e-artefatti.md) - Cosa lasci sul disco e in RAM
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
