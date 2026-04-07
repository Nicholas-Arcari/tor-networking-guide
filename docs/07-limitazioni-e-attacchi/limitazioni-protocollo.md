# Limitazioni del Protocollo Tor — Analisi Tecnica Completa

Questo documento analizza in profondità tutte le limitazioni architetturali e
protocollari di Tor: perché supporta solo TCP, cosa succede al traffico UDP,
le conseguenze sulle applicazioni reali, e le soluzioni possibili.

Basato sulla mia esperienza diretta con i limiti di Tor su Kali Linux,
dove ho toccato con mano l'impossibilità di usare certi protocolli e servizi.

---
---

## Indice

- [Limitazione fondamentale: Solo TCP](#limitazione-fondamentale-solo-tcp)
- [Latenza — Il costo dei 3 hop](#latenza-il-costo-dei-3-hop)
- [Bandwidth — Imprevedibile e limitata](#bandwidth-imprevedibile-e-limitata)
- [Limitazioni del protocollo SOCKS5](#limitazioni-del-protocollo-socks5)
- [Circuiti multipli e IP variabili](#circuiti-multipli-e-ip-variabili)
- [Protocolli e applicazioni problematiche — Riepilogo](#protocolli-e-applicazioni-problematiche-riepilogo)
- [Possibili sviluppi futuri](#possibili-sviluppi-futuri)


## Limitazione fondamentale: Solo TCP

### Perché Tor supporta solo TCP

Tor opera a livello di stream TCP. Il protocollo Tor trasporta dati in celle
di 514 byte che viaggiano su connessioni TLS (che a loro volta viaggiano su TCP).
La catena è:

```
Dati applicativi → celle Tor → TLS → TCP → IP → rete fisica
```

TCP garantisce:
- **Ordine dei pacchetti**: fondamentale per la cifratura AES-CTR (il contatore
  deve avanzare in ordine)
- **Consegna affidabile**: se una cella si perde, TCP la ritrasmette
- **Controllo di flusso**: TCP gestisce il rate limiting

UDP non garantisce nessuna di queste proprietà. Implementare un trasporto affidabile
su UDP richiederebbe reimplementare TCP dentro Tor, vanificando il vantaggio di UDP.

### Conseguenze concrete

#### DNS nativo (UDP porta 53) — Bloccato

Il DNS standard usa UDP. Senza configurazione speciale, le query DNS non passano
da Tor:

```
Problema:
[App] → DNS query (UDP:53) → ISP resolver → LEAK!

Soluzione Tor:
[App] → SOCKS5 CONNECT (hostname come stringa) → Tor → Exit (risolve DNS)
oppure:
[App] → DNSPort 5353 (Tor risolve) → Tor → Exit (risolve DNS)
```

Nella mia esperienza, la configurazione `DNSPort 5353` + `proxy_dns` in proxychains
risolve completamente questo problema per le applicazioni che uso.

#### VoIP / RTP (UDP) — Non funzionante

```
Protocollo: RTP over UDP (porte dinamiche)
Stato su Tor: IMPOSSIBILE
Motivo: Tor non trasporta UDP. Anche con encapsulation TCP, la latenza di
  3 hop (200-1000ms) rende le chiamate inutilizzabili.
Impatto: niente chiamate vocali, niente VoIP, niente SIP
```

#### WebRTC (UDP + STUN/TURN) — Disabilitato per sicurezza

```
Protocollo: WebRTC usa UDP per media, STUN/TURN per NAT traversal
Stato su Tor: DISABILITATO in Tor Browser (media.peerconnection.enabled=false)
Motivo duplice:
  1. WebRTC rivela l'IP reale tramite STUN (leak anche con proxy)
  2. Tor non trasporta UDP
Impatto: niente videochiamate nel browser (Google Meet, Zoom web, Discord web)
```

Nella mia configurazione Firefox tor-proxy, ho disabilitato manualmente WebRTC
in about:config per prevenire IP leak.

#### HTTP/3 (QUIC — UDP) — Bloccato

```
Protocollo: QUIC (HTTP/3 over UDP porta 443)
Stato su Tor: BLOCCATO (il browser ritorna a HTTP/2 o HTTP/1.1)
Motivo: QUIC usa UDP
Impatto:
  - Performance peggiori su CDN moderne (Cloudflare, Google)
  - Caricamenti più lenti rispetto a browser normali
  - Nessuna multiplexazione QUIC stream (si usa HTTP/2 multiplexing)
```

In Firefox tor-proxy: `network.http.http3.enabled = false` per evitare
tentativi falliti di QUIC.

#### Gaming online (UDP + bassa latenza) — Impossibile

```
Protocolli: UDP game protocol, anti-cheat, NAT traversal
Stato su Tor: TOTALMENTE IMPOSSIBILE
Motivi:
  1. Niente UDP
  2. Latenza 200-1000ms (i giochi richiedono <50ms)
  3. Bandwidth variabile (i giochi richiedono bandwidth stabile)
  4. Anti-cheat basati su IP (bloccano Tor)
  5. NAT traversal (STUN/TURN) non funziona
```

#### NTP (UDP porta 123) — Bloccato

```
Protocollo: NTP (Network Time Protocol, UDP porta 123)
Stato su Tor: BLOCCATO
Impatto: l'orologio di sistema non si sincronizza automaticamente
Rischio: se l'orologio si desincronizza, Tor può rifiutare il consenso
Soluzione: usare ntpdate occasionalmente senza Tor, o configurare
  chrony con supporto NTS (che usa TCP)
```

#### ICMP (ping, traceroute) — Non supportato

```
Protocollo: ICMP (non è né TCP né UDP)
Stato su Tor: IMPOSSIBILE
Impatto: ping e traceroute non funzionano
Soluzione: nessuna. Per verificare raggiungibilità via Tor, usare:
  proxychains curl -I https://target.com
```

---

## Latenza — Il costo dei 3 hop

### Analisi della latenza

Ogni connessione Tor attraversa 3 hop, ognuno con la propria latenza:

```
Latenza totale ≈ L(client→guard) + L(guard→middle) + L(middle→exit) + L(exit→destinazione)
                + overhead TLS per ogni hop
                + overhead cifratura/decifratura per ogni cella
                + overhead protocollo Tor (handshake, flow control)
```

### Misurazioni dalla mia esperienza

```bash
# Senza Tor:
> time curl -s https://api.ipify.org > /dev/null
real    0m0.245s

# Con Tor (buon circuito):
> time proxychains curl -s https://api.ipify.org > /dev/null 2>&1
real    0m2.342s

# Con Tor (circuito lento):
> time proxychains curl -s https://api.ipify.org > /dev/null 2>&1
real    0m5.891s

# Con Tor + bridge obfs4:
> time proxychains curl -s https://api.ipify.org > /dev/null 2>&1
real    0m4.567s
```

| Configurazione | Latenza tipica | Fattore vs diretto |
|---------------|---------------|-------------------|
| Diretto (no Tor) | 100-300ms | 1x |
| Tor (circuito veloce) | 500-2000ms | 5-10x |
| Tor (circuito medio) | 2000-5000ms | 10-20x |
| Tor (circuito lento) | 5000-15000ms | 20-50x |
| Tor + bridge obfs4 | 1000-8000ms | 10-30x |

### Perché la latenza varia

- I relay sono volontari con bandwidth variabile
- I relay possono essere geograficamente distanti (es. guard in Europa, middle
  in Asia, exit in Americhe)
- Il traffico di altri utenti sugli stessi relay causa congestione
- Il flow control di Tor (SENDME cells) aggiunge pause
- La costruzione iniziale del circuito (handshake ntor × 3) è costosa

---

## Bandwidth — Imprevedibile e limitata

### Perché la bandwidth è bassa

La rete Tor ha ~7000 relay, ma la bandwidth totale è limitata:
- I relay sono gestiti da volontari con connessioni domestiche o VPS economici
- La bandwidth è condivisa tra tutti gli utenti dei circuiti che attraversano il relay
- Il relay più lento nella catena determina la velocità massima del circuito
- Il flow control di Tor limita ulteriormente il throughput

### Throughput tipico

| Tipo di operazione | Throughput via Tor | Throughput diretto |
|-------------------|-------------------|-------------------|
| Navigazione web | 100-500 KB/s | 10+ MB/s |
| Download file | 200-800 KB/s | 10+ MB/s |
| Streaming video | Quasi impossibile | 5+ MB/s |
| apt update | 50-200 KB/s | 5+ MB/s |

### Congestion control (recente)

A partire da Tor 0.4.7, è stato introdotto un nuovo algoritmo di congestion control
che migliora significativamente il throughput. Sostituisce il vecchio meccanismo
basato su finestre fisse con un algoritmo adattivo simile a BBR/CUBIC.

---

## Limitazioni del protocollo SOCKS5

### Cosa SOCKS5 supporta

- `CONNECT`: apre una connessione TCP verso una destinazione → **supportato**
- `BIND`: apre un listener per connessioni in ingresso → **non supportato da Tor**
- `UDP ASSOCIATE`: proxy di pacchetti UDP → **non supportato da Tor**

### Conseguenza di BIND non supportato

FTP in modalità attiva richiede che il server si connetta al client (BIND).
Questo non funziona via Tor. FTP in modalità passiva (il client si connette al server)
funziona ma è instabile perché richiede un secondo stream TCP su una porta dinamica.

### Conseguenza di UDP ASSOCIATE non supportato

Qualsiasi applicazione che tenta `UDP ASSOCIATE` via SOCKS5 riceve un errore.
Questo include client DNS, applicazioni VoIP, e qualsiasi software che tenta di
usare UDP attraverso il proxy.

---

## Circuiti multipli e IP variabili

### Il problema per le applicazioni

Con una VPN, hai un IP fisso. Con Tor:
- Ogni circuito può avere un exit diverso → IP diverso
- Circuiti diversi per stream diversi (stream isolation)
- L'IP cambia ogni ~10 minuti (MaxCircuitDirtiness)
- NEWNYM forza il cambio immediato

### Conseguenze

1. **Sessioni web instabili**: un sito web può invalidare la sessione se l'IP cambia
   (anti-fraud, security tokens legati all'IP)
2. **Rate limiting**: molti siti limitano le richieste per IP. Con Tor, il "tuo" IP
   è condiviso con migliaia di utenti → rate limit raggiunto velocemente
3. **Geolocalizzazione incoerente**: una richiesta esce dall'Olanda, la successiva
   dalla Germania → i siti che verificano la coerenza geografica segnalano anomalie
4. **CAPTCHA infiniti**: i siti vedono traffico da un IP Tor noto → CAPTCHA ripetuti

### Nella mia esperienza

I CAPTCHA sono il problema più frequente. Google in particolare è aggressivo:
a volte è impossibile fare una ricerca via Tor senza superare 3-4 CAPTCHA.
Amazon, PayPal e banche italiane bloccano direttamente il login.

---

## Protocolli e applicazioni problematiche — Riepilogo

| Protocollo/App | Problema | Funziona via Tor? | Alternativa |
|---------------|----------|------------------|-------------|
| DNS (UDP) | Tor non trasporta UDP | Con DNSPort/proxy_dns SI | SOCKS5 hostname |
| HTTP/HTTPS | Nessuno | **SI** | - |
| SSH | Latenza alta, timeout | **Parzialmente** | Aumentare timeout |
| FTP | Canale dati problematico | **Male** | SFTP |
| SMTP | Porta 25 bloccata dalla maggior parte degli exit | **Male** | Webmail |
| IRC | Molti server bloccano Tor | **Parzialmente** | Server che accettano Tor |
| BitTorrent | DHT/PEX leakano IP, exit policy bloccano, Tor sconsiglia | **NO** | - |
| VoIP/SIP | UDP, latenza | **NO** | - |
| Gaming | UDP, latenza, anti-cheat | **NO** | - |
| Streaming video | Bandwidth, latenza | **Quasi NO** | Bassa qualità forse |
| NTP | UDP | **NO** | NTS over TCP |
| ICMP | Non è TCP/UDP | **NO** | curl per test raggiungibilità |
| WebRTC | UDP, IP leak | **Disabilitato** | - |
| QUIC/HTTP3 | UDP | **Fallback a HTTP/2** | - |
| P2P generico | UDP, NAT, IP reveal | **NO** | - |

---

## Possibili sviluppi futuri

### MASQUE (UDP over Tor)

Il Tor Project sta esplorando il protocollo MASQUE (basato su HTTP/3) per
trasportare UDP su Tor. Questo potrebbe un giorno abilitare:
- DNS nativo via Tor
- QUIC/HTTP3 via Tor
- Forse VoIP (ma la latenza resterebbe un problema)

Il lavoro è in fase iniziale e non ancora disponibile nelle versioni stabili.

### Conflux (multi-path circuits)

Conflux permette a un singolo stream di usare più circuiti simultaneamente,
migliorando throughput e affidabilità. Disponibile a partire da Tor 0.4.8.

---

## Vedi anche

- [Architettura di Tor](../01-fondamenti/architettura-tor.md) — Design choices che causano le limitazioni
- [Limitazioni nelle Applicazioni](limitazioni-applicazioni.md) — Impatto pratico delle limitazioni
- [VPN e Tor Ibrido](../06-configurazioni-avanzate/vpn-e-tor-ibrido.md) — VPN per superare alcune limitazioni
- [Attacchi Noti](attacchi-noti.md) — Attacchi che sfruttano le limitazioni
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) — Limiti della protezione dalla correlazione
