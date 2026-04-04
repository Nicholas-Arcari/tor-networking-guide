# OPSEC e Errori Comuni — Cosa Può Deanonimizzarti

Questo documento cataloga gli errori di OPSEC (Operational Security) più comuni
nell'uso di Tor, come evitarli, e casi reali dove utenti sono stati deanonimizzati
nonostante usassero Tor.

---

## Errori di OPSEC che annullano l'anonimato di Tor

### 1. Login con account personali

**L'errore**: navighi via Tor, poi fai login su Gmail, Facebook, o Amazon con
il tuo account personale. Ora il sito sa chi sei, anche se il tuo IP è quello
dell'exit node.

**Perché è grave**: l'anonimato di Tor protegge l'IP. Se dici al sito chi sei
(login), l'IP è irrilevante. Inoltre, il sito può correlare la tua sessione
anonima con sessioni passate/future.

**Regola**: non accedere MAI ad account personali su Tor.

### 2. Usare Tor e non-Tor contemporaneamente

**L'errore**: hai due finestre del browser aperte — una via Tor, una normale.
Visiti lo stesso sito in entrambe. Il sito correla le sessioni tramite cookie,
fingerprint, o timing.

**Regola**: se usi Tor per un'attività, NON fare la stessa attività senza Tor
contemporaneamente.

### 3. Scaricare e aprire file senza precauzioni

**L'errore**: scarichi un PDF via Tor, lo apri con il lettore PDF del sistema.
Il lettore PDF fa richieste HTTP (per font, immagini esterne) che escono
SENZA passare da Tor → rivelano il tuo IP reale.

**Regola**: non aprire file scaricati via Tor in applicazioni che fanno rete.
Oppure aprirli in una VM senza rete.

### 4. Informazioni nell'User-Agent e nei metadata

**L'errore**: il tuo browser rivela OS (Kali Linux), architettura (x86_64),
versione esatta (Firefox 128). Queste informazioni restringono il pool di
utenti possibili.

**Regola**: usare Tor Browser (user-agent uniformato). O almeno attivare
`privacy.resistFingerprinting` in Firefox.

### 5. DNS leak

**L'errore**: le query DNS escono in chiaro verso l'ISP.

**Regola**: `proxy_dns` in proxychains, `--socks5-hostname` con curl,
`DNSPort` nel torrc.

### 6. WebRTC leak

**L'errore**: WebRTC nel browser rivela l'IP locale e pubblico reale.

**Regola**: `media.peerconnection.enabled = false` in about:config.

### 7. Timezone e lingua del browser

**L'errore**: il browser rivela timezone=Europe/Rome e lingua=it-IT.
Questo restringe la geolocalizzazione.

**Regola**: `privacy.resistFingerprinting = true` (forza UTC e en-US).

### 8. Torrenting via Tor

**L'errore**: usi BitTorrent via Tor. Il client BitTorrent rivela il tuo IP
reale nel protocollo DHT/PEX, che non passa dal proxy.

**Regola**: non usare MAI BitTorrent via Tor.

### 9. Eseguire JavaScript non fidato

**L'errore**: JavaScript di un sito malevolo esegue exploit per ottenere
il tuo IP reale (via WebRTC, DNS rebinding, o vulnerabilità del browser).

**Regola**: Tor Browser ha un "Security Level" che limita JavaScript.
Impostarlo su "Safer" o "Safest" per siti non fidati.

### 10. Pattern di comportamento unico

**L'errore**: visiti sempre gli stessi 5 siti, allo stesso orario, con lo
stesso pattern di navigazione. Anche senza fingerprint tecnico, il tuo
*comportamento* è un fingerprint.

**Regola**: variare pattern, non usare Tor per routine prevedibili.

---

## Casi reali di deanonimizzazione

### Ross Ulbricht (Silk Road, 2013)

**Come è stato trovato**: NON tramite vulnerabilità di Tor, ma tramite errori OPSEC:
- Aveva usato il suo vero nome su Stack Overflow per chiedere aiuto con codice
  usato in Silk Road
- Aveva usato un email personale (`rossulbricht@gmail.com`) in post correlati
- Il server era stato trovato tramite un leak nell'interfaccia di login

**Lezione**: Tor era integro. L'errore era umano.

### Hector Monsegur (LulzSec, 2012)

**Come è stato trovato**: si è connesso a un server IRC **una volta senza Tor**
(aveva dimenticato di attivare la VPN). Una singola connessione ha rivelato il
suo IP reale.

**Lezione**: basta una singola connessione senza Tor per essere identificati.

### Freedom Hosting (2013)

**Come è stato trovato**: l'FBI ha sfruttato una vulnerabilità nel browser
(Firefox ESR) per iniettare JavaScript che inviava l'IP reale e il MAC address
a un server FBI.

**Lezione**: il browser è la superficie di attacco. Mantenere Tor Browser
aggiornato è critico.

---

## Checklist OPSEC per l'uso di Tor

### Prima di iniziare

- [ ] Tor è attivo e bootstrap al 100%?
- [ ] ProxyChains è configurato con `proxy_dns`?
- [ ] WebRTC è disabilitato nel browser?
- [ ] IPv6 è disabilitato (`ClientUseIPv6 0`)?
- [ ] Il profilo browser è dedicato a Tor (non condiviso)?

### Durante l'uso

- [ ] NON fare login con account personali
- [ ] NON aprire file scaricati con applicazioni di rete
- [ ] NON usare lo stesso sito via Tor e non-Tor
- [ ] NON rivelare informazioni personali
- [ ] Verificare periodicamente l'IP con `proxychains curl https://api.ipify.org`

### Dopo l'uso

- [ ] Chiudere tutte le applicazioni Tor
- [ ] Pulire la cronologia del browser (o usare navigazione privata)
- [ ] Se necessario, NEWNYM per invalidare i circuiti

---

## Nella mia esperienza

Sono consapevole che il mio setup (Firefox+proxychains su Kali) non è a prova
di fingerprinting. Lo uso per:
- Privacy dall'ISP (nascondere i siti che visito)
- Test di sicurezza (verificare comportamenti da IP diversi)
- Studio della rete Tor

NON lo uso per:
- Attività che richiedano anonimato assoluto
- Login su account personali
- Attività illegali

Per scenari che richiedano anonimato reale, userei Tor Browser su Tails o Whonix.
