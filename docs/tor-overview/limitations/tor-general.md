# Limitazioni di Tor  

---

## 1. Limitazioni dell'architettura

### 1.1 Tor supporta solo TCP
Tor non trasporta pacchetti UDP. Questo rompe o degrada:

- DNS (che usa UDP nativamente)
- VoIP / RTP
- WebRTC
- Videogiochi online
- Protocolli QUIC (HTTP/3)
- Streaming in tempo reale (P2P)

---

### 1.2 Latenza molto elevata
Ogni circuito Tor utilizza 3 nodi spesso lontani tra loro.

Conseguenze:

- lentezza nelle sessioni SSH  
- strumenti real-time quasi inutilizzabili  
- connessioni instabili sotto carico  
- ritardo evidente nelle app interattive  

---

### 1.3 Larghezza di banda instabile
I nodi Tor sono volontari → banda limitata e imprevedibile.

Tor non può garantire:

- velocità di download costanti  
- latenza stabile  
- throughput elevato  

---

## 2. Limitazioni nelle applicazioni web

### 2.1 Tor Browser != Firefox con proxy SOCKS
Tor Browser contiene patch e funzioni che Firefox normale non ha, come:

- riduzione fingerprint  
- isolamento delle richieste  
- disattivazione WebRTC  
- spoofing canvas/font  
- modifiche ai TLS fingerprints  

Usare Firefox con `SOCKS5 127.0.0.1:9050` non offre la stessa privacy

---

### 2.2 Siti che bloccano Tor
Molti servizi bloccano o limitano gli exit node:

- Google (captcha infiniti)  
- Amazon  
- PayPal  
- Instagram / Meta  
- Reddit  
- Banche  
- Provider email  
- Portali con login sensibili  

Risultati:

- loop di captcha  
- errori di sicurezza  
- logout improvvisi  
- impossibilità di accedere  

---

### 2.3 Sessioni instabili
Tor causa:

- IP condivisi da migliaia di utenti  
- cambi di posizione geografica continui  
- meccanismi anti-abuso più severi  
- invalidazione dei token di sessione  

---

### 2.4 WebRTC disattivato → niente videochiamate
A causa del rischio di IP leak, WebRTC è disattivato.

Implicazioni:

- niente Google Meet  
- niente Discord video  
- niente WebTorrent P2P  
- niente strumenti che usano STUN/TURN  

---

### 2.5 HTTP/3 (QUIC) disabilitato
QUIC è basato su UDP → Tor lo blocca

Il browser torna a:
- HTTP/2  
- HTTP/1.1  

Risultato:
- performance peggiori su CDN moderne  
- caricamenti più lenti  

---

## 3. Limitazioni nelle applicazioni non web

### 3.1 Niente multicast o broadcast
Tor non supporta traffico broadcast/multicast

Quindi non funzionano:
- mDNS (es. rilevamento stampanti)
- UPnP
- SSDP
- discovery di dispositivi in LAN
- alcune scansioni nmap

---

### 3.2 SSH funziona, ma male
Problemi comuni:

- latenza altissima  
- timeouts  
- key exchange lento  
- provider cloud che bloccano Tor  

---

### 3.3 FTP poco affidabile
FTP usa:
- canale di controllo  
- canale dati  
- porte dinamiche

Tor spesso rompe il protocollo.  
Alternative consigliate:

- SFTP
- FTPS

---

### 3.4 Gaming impossibile
I videogiochi online richiedono:

- UDP  
- NAT traversal  
- latenza bassissima  
- anti-cheat basati su IP  

Tor li rende ingiocabili.

---

### 3.5 P2P / Torrent bloccati
Tor **sconsiglia e limita**:

- BitTorrent  
- magnet link  
- DHT  
- peer exchange  

Motivi:
- rischio legale  
- abuso di banda  
- incompatibilità del protocollo  

---

### 3.6 Applicazioni desktop non compatibili
Molte app ignorano le impostazioni proxy:

Non funzionano su Tor:
- Discord  
- Telegram Desktop  
- Steam  
- Spotify  
- App Electron varie  
- Molti client email  

Funziona solo ciò che supporta SOCKS5 manualmente

---

## 4. Limitazioni di privacy e sicurezza

### 4.1 Rischi dell'exit node
I nodi di uscita possono:

- leggere traffico HTTP  
- intercettare dati non cifrati  
- iniettare malware  
- manipolare file scaricati  

HTTPS riduce il rischio, ma non elimina tutto

---

### 4.2 Fingerprinting del browser
Browser non-Tor sono riconoscibili tramite:

- WebGL  
- timestamp  
- fonts  
- canvas  
- GPU  
- estensioni  
- dimensioni finestra  

Solo Tor Browser mitiga questi vettori

---

### 4.3 Censura e rilevabilità
Molti Paesi rilevano e bloccano Tor:

- Cina  
- Russia  
- Iran  
- Turkmenistan  

Blocchi applicati:

- directory authorities  
- fingerprint TLS standard  
- exit node noti  

Soluzioni:
- obfs4
- meek
- snowflake

---

### 4.4 Tor non protegge da compromissioni locali
Tor NON difende da:

- keylogger  
- malware  
- spyware  
- compromissione dell'OS  
- estensioni pericolose del browser  

---

## 5. Limiti Tor vs VPN

Tor:

- non è system-wide  
- non supporta UDP  
- non offre IP stabile  
- non supporta alta banda  
- non permette split tunneling  
- non è progettato per streaming o lavoro remoto serio  

VPN e Tor risolvono problemi diversi

---

## 6. Tabella riassuntiva

| Categoria | Limitazione |
|----------|-------------|
| Web | Login instabili, WebRTC disattivato, blocchi anti-bot |
| Networking | No UDP, no multicast, alta latenza |
| Applicazioni | Solo app proxy-aware funzionano |
| Sicurezza | Exit node possono leggere HTTP |
| Censura | Tor rilevabile senza obfs4 |
| Performance | Banda lenta e variabile |

---

## 7. Limitazioni specifiche su localhost

Tor Browser NON può accedere a:

- `http://localhost:*`
- `127.0.0.1:*`
- `0.0.0.0:*`

Perché?

1. Le richieste escono dal circuito su un exit node remoto  
2. L'exit node non può raggiungere la tua macchina locale. 
3. Tor Browser blocca volontariamente l'accesso a risorse locali per privacy/sicurezza

Per accedere a servizi locali (come Docker su `5173`):

- usare Firefox normale (non Tor Browser)  
- oppure usare `torsocks` da CLI  
- oppure esporre temporaneamente il servizio verso l'esterno (non consigliato)  
- oppure usare un reverse proxy che esponga una porta pubblica  

---

## Fine documento
