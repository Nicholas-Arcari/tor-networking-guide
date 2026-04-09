# OPSEC - Casi Reali, Stylometry e Difese

Casi reali di deanonimizzazione (Silk Road, AlphaBay, LulzSec, Freedom Hosting),
analisi stylometrica, tracciamento cryptocurrency, checklist operativa completa
e threat model per autovalutazione.

> **Estratto da**: [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) per gli
> errori di OPSEC e la correlazione metadata.

---

### Ross Ulbricht (Silk Road, 2013)

**Chi era**: creatore e operatore di Silk Road, il primo grande mercato
darknet, operativo dal 2011 al 2013.

**Come è stato trovato**: NON tramite vulnerabilità di Tor, ma tramite
una catena di errori OPSEC:

```
Errore 1 (gennaio 2011):
  Ulbricht aveva postato su Shroomery.org (con il suo nome reale)
  chiedendo informazioni su come creare un sito .onion

Errore 2 (marzo 2011):
  Aveva usato il nickname "altoid" sia su Silk Road che su
  Stack Overflow, dove era registrato come "Ross Ulbricht"
  con email rossulbricht@gmail.com

Errore 3 (2012):
  Aveva ordinato documenti falsi (patenti) che sono stati
  intercettati dalla dogana → collegati al suo indirizzo reale

Errore 4 (2013):
  Il server di Silk Road leakava l'IP reale tramite un
  misconfiguration nell'interfaccia di login (CAPTCHA caricato
  da IP diretto, non via .onion)

Errore 5 (arresto):
  È stato arrestato in una biblioteca pubblica mentre era
  loggato come admin di Silk Road sul suo laptop
```

**Lezione**: Tor era integro. Ogni errore era umano. La combinazione
di errori su un arco di 2+ anni ha permesso l'identificazione.

### Alexandre Cazes (AlphaBay, 2017)

**Chi era**: fondatore e admin di AlphaBay, il più grande mercato darknet
successore di Silk Road.

**Come è stato trovato**:

```
Errore 1:
  L'email di recovery del forum di AlphaBay era "pimp_alex_91@hotmail.com"
  → "Alex" + "91" (anno di nascita)
  → Email personale collegata al suo vero nome

Errore 2:
  Il messaggio di benvenuto di AlphaBay conteneva "Welcome to AlphaBay"
  → Lo stesso header era stato usato in un sito web personale di Cazes
  → Stesse configurazioni PHP/MySQL

Errore 3:
  Cazes viveva in Thailandia con uno stile di vita lussuoso
  (Lamborghini, ville) senza un lavoro noto
  → Le autorità hanno correlato il profilo finanziario

Errore 4:
  Il server aveva una configurazione che leakava l'IP in
  caso di errore del web server (pagina di default Apache)
```

**Lezione**: un singolo indirizzo email personale usato per errore ha
iniziato l'intera catena investigativa.

### Hector Monsegur (LulzSec/Anonymous, 2012)

**Come è stato trovato**: si è connesso a un server IRC **una volta senza Tor**
(aveva dimenticato di attivare la VPN). Una singola connessione ha rivelato il
suo IP reale.

**Dettagli**:
```
Monsegur usava Tor per tutte le comunicazioni con LulzSec
Ma una sera, stanco, si è connesso al server IRC senza Tor
Il server ha loggato il suo IP reale: un indirizzo di New York
L'FBI ha correlato l'IP con il suo appartamento
→ Una singola connessione = identificazione completa
```

**Lezione**: basta una singola connessione senza Tor per essere identificati.
L'OPSEC deve essere mantenuta al 100%, non al 99.99%.

### Freedom Hosting (2013)

**Come è stato trovato**: l'FBI ha sfruttato una vulnerabilità nel browser
(Firefox ESR 17) per iniettare JavaScript che inviava l'IP reale e il MAC
address a un server FBI.

**Dettagli tecnici dell'exploit**:
```javascript
// L'exploit era iniettato nelle pagine ospitate su Freedom Hosting
// Sfruttava CVE-2013-1690 (Firefox ESR 17)
// Il payload:
// 1. Bypassava la sandbox del browser
// 2. Eseguiva codice nativo
// 3. Recuperava l'IP reale e il MAC address
// 4. Inviava i dati a un server FBI (fuori da Tor)
// 5. Funzionava solo su Windows (il payload era un PE)
```

**Lezione**: il browser è la superficie di attacco principale. Mantenere
Tor Browser aggiornato è critico. Su Tails/Whonix, anche un exploit del
browser non rivela l'IP (il traffico è forzato via Tor a livello firewall).

### Eldo Kim (minaccia bomba Harvard, 2013)

**Come è stato trovato**:

```
Kim ha usato Tor per inviare email di minaccia bomba a Harvard
per evitare un esame.

Errore: ha usato Tor dalla rete WiFi di Harvard
→ Harvard aveva i log di chi era connesso a Tor in quel momento
→ Solo 1-2 persone sulla rete Harvard usavano Tor alle 08:30
→ Kim era l'unico studente connesso a Tor in quel momento

L'FBI lo ha interrogato e ha confessato immediatamente.
```

**Lezione**: se sei l'unico utente Tor sulla tua rete locale, il semplice
fatto di usare Tor ti rende sospetto. Bridge obfs4 nascondono l'uso di Tor.

### Jeremy Hammond (Anonymous/Stratfor, 2012)

**Come è stato trovato**: tradimento da parte di un informatore (Sabu/Monsegur,
che collaborava con l'FBI) e correlazione dei log di chat.

**Lezione**: la fiducia nelle persone è un vettore di attacco.
Nessuna tecnologia protegge da un infiltrato.

---

## Pattern comportamentali e stylometry

### Cos'è la stylometry

La stylometry analizza lo stile di scrittura per identificare l'autore.
Ogni persona ha un "fingerprint linguistico" unico:

```
Elementi analizzati:
- Lunghezza media delle frasi
- Distribuzione della punteggiatura (uso di - vs - vs ... )
- Parole comuni usate (es. "comunque" vs "tuttavia" vs "però")
- Errori grammaticali ricorrenti
- Struttura dei paragrafi
- Uso di emoticon/emoji
- Vocabolario tecnico specifico
- Formattazione (markdown, HTML, spazi)
```

### Accuratezza della stylometry

```
- Con 5.000 parole di campione: ~80% accuratezza su 50 autori
- Con 10.000 parole: ~90% accuratezza
- Con analisi cross-lingua (stesso autore, lingue diverse): ~60%
- Machine learning (BERT, GPT): >95% su campioni sufficienti
```

### Mitigazione

```
1. Scrivere in modo diverso per ogni identità
   → Difficile da mantenere nel tempo
   
2. Usare un traduttore automatico come "filtro di stile"
   → Scrivi in italiano → traduci in inglese → ri-traduci in italiano
   → Lo stile viene "appiattito"
   
3. Usare un LLM per riscrivere
   → "Riscrivi questo testo in uno stile neutro e generico"
   → Rimuove le caratteristiche stilistiche personali
   
4. Usare solo inglese per attività anonime
   → Pool più grande (lingua più diffusa online)
   → Meno identificabile rispetto all'italiano
```

### Pattern temporali come fingerprint

```
Analisi di post anonimi su un forum:
- L'utente posta tra le 08:00 e le 23:00 CET
- Mai di domenica (probabile lavoratore regolare)
- Picchi di attività alle 13:00 e alle 21:00
- Vacanze a agosto e dicembre (pattern italiano)
→ Timezone: CET
→ Professione: lavoro regolare con pausa pranzo
→ Nazionalità: probabilmente italiano
```

---

## Cryptocurrency e tracciamento finanziario

### Bitcoin non è anonimo

```
Bitcoin è PSEUDONIMO, non anonimo:
- Ogni transazione è pubblica sulla blockchain
- Gli indirizzi sono collegabili tramite analisi dei flussi
- Gli exchange richiedono KYC (Know Your Customer)
- Una singola transazione da un exchange KYC a un indirizzo
  "anonimo" compromette l'intera catena di indirizzi

Strumenti di analisi blockchain:
- Chainalysis (usato da FBI, IRS, Europol)
- Elliptic
- CipherTrace
→ Possono correlare indirizzi, mixer, e movimenti
```

### Errori comuni con crypto

```
Errore 1: comprare BTC su exchange con il proprio nome,
          poi usarli per transazioni anonime
          → Tracciabili al 100%

Errore 2: usare lo stesso wallet per transazioni
          anonime e non anonime
          → Collegamento diretto

Errore 3: non usare Tor per accedere al wallet
          → L'exchange/nodo vede il tuo IP reale

Errore 4: importi specifici (es. 0.12345678 BTC)
          → Tracciabili come importo unico
```

### Mitigazione parziale

```
- Monero (XMR): privacy by default (ring signatures, stealth addresses)
- CoinJoin/Wasabi Wallet: mixing di transazioni Bitcoin
- Mai riutilizzare indirizzi
- Mai collegare wallet anonimi a exchange KYC
- Accedere ai wallet solo via Tor
- Non usare importi specifici riconoscibili
```

---

## Checklist OPSEC completa

### Prima di iniziare una sessione anonima

- [ ] Tor è attivo e bootstrap al 100%?
- [ ] ProxyChains è configurato con `proxy_dns`?
- [ ] WebRTC è disabilitato nel browser (`media.peerconnection.enabled = false`)?
- [ ] IPv6 è disabilitato (`net.ipv6.conf.all.disable_ipv6=1`)?
- [ ] Il profilo browser è dedicato a Tor (non condiviso con navigazione normale)?
- [ ] `privacy.resistFingerprinting = true` nel profilo Tor?
- [ ] DNS prefetch disabilitato (`network.dns.disablePrefetch = true`)?
- [ ] Nessun account personale è loggato nel browser Tor?
- [ ] Nessun altro browser/app usa la stessa rete per attività non anonime?
- [ ] Bridge obfs4 attivo se necessario (nascondere uso di Tor all'ISP)?

### Durante l'uso

- [ ] NON fare login con account personali
- [ ] NON aprire file scaricati con applicazioni di rete
- [ ] NON usare lo stesso sito via Tor e non-Tor contemporaneamente
- [ ] NON rivelare informazioni personali (nome, città, lavoro, etc.)
- [ ] NON usare lo stesso stile di scrittura dell'identità reale
- [ ] NON caricare file con metadata non puliti
- [ ] NON usare Bitcoin da exchange KYC per transazioni anonime
- [ ] NON postare a orari prevedibili che rivelano la timezone
- [ ] Verificare periodicamente l'IP con `proxychains curl https://api.ipify.org`
- [ ] Usare NEWNYM tra attività diverse/non correlate

### Dopo l'uso

- [ ] Chiudere tutte le applicazioni Tor
- [ ] Pulire la cronologia del browser (o usare navigazione privata)
- [ ] NEWNYM per invalidare i circuiti
- [ ] Se alto rischio: spegnere il computer (RAM contiene tracce)
- [ ] Se Tails: riavviare (la RAM viene sovrascritta)

### Errori da non fare MAI

| Errore | Conseguenza | Reversibile? |
|--------|-------------|-------------|
| Login account personale | Identità rivelata al sito | NO - i log esistono |
| Una connessione senza Tor | IP reale loggato | NO |
| File con metadata personali | Nome/posizione esposti | NO - se salvati da altri |
| Stesso wallet crypto anonimo/reale | Collegamento finanziario | NO - blockchain è permanente |
| Post con info personale | Correlazione possibile | PARZIALE - se eliminato velocemente |
| DNS leak | Domini visitati noti all'ISP | NO - ISP logga per legge |

---

## Threat model e autovalutazione

### Definire il tuo avversario

L'OPSEC necessario dipende dal tuo threat model:

| Avversario | Capacità | OPSEC necessario |
|-----------|----------|-----------------|
| Tracker web (Google, Facebook) | Cookie, fingerprint, pixel | Tor Browser, FPI |
| ISP (nel mio caso: Comeser) | Vede destinazioni, timing, volume | Tor + bridge obfs4 |
| Amministratore rete locale | Come ISP + DHCP, ARP | Tor + bridge + MAC spoofing |
| Forze dell'ordine nazionali | Ordini giudiziari a ISP, exchange | Tor + OPSEC rigoroso |
| Intelligence (NSA, GCHQ) | Sorveglianza globale, correlazione | Tails/Whonix + OPSEC perfetto |
| Avversario con accesso fisico | Forensics su disco e RAM | Full disk encryption + Tails |

### Il mio threat model

```
Avversario: ISP + tracker web
Obiettivo: privacy dalla profilazione commerciale, test di sicurezza
Rischio: basso (attività legali, nessun avversario attivo)

OPSEC adeguato:
✓ Tor + proxychains (nasconde destinazioni dall'ISP)
✓ Bridge obfs4 (nasconde uso di Tor dall'ISP)
✓ Profilo Firefox dedicato (separa navigazione Tor da normale)
✓ proxy_dns + DNSPort (previene DNS leak)
✓ WebRTC disabilitato (previene IP leak)

NON necessario per il mio threat model:
✗ Tails/Whonix (il mio avversario non fa forensics)
✗ Compartimentazione estrema (non ho identità anonime da proteggere)
✗ MAC spoofing (non mi connetto a reti sconosciute)
✗ Stylometry defense (non scrivo post anonimi)
```

---

## Nella mia esperienza

Sono consapevole che il mio setup (Firefox+proxychains su Kali) non è a prova
di fingerprinting. Lo uso per:
- Privacy dall'ISP (nascondere i siti che visito)
- Test di sicurezza (verificare comportamenti da IP diversi)
- Studio della rete Tor

NON lo uso per:
- Attività che richiedano anonimato assoluto
- Login su account personali via Tor
- Attività illegali

Per scenari che richiedano anonimato reale, userei Tor Browser su Tails o Whonix.

L'errore OPSEC più comune che ho visto (non che ho commesso, fortunatamente):
dimenticare che `curl` senza `--socks5-hostname` fa leak DNS. È un errore
facile, silenzioso, e devastante. Per questo ho creato alias:

```bash
# Nel mio .zshrc:
alias curltor='curl --socks5-hostname 127.0.0.1:9050'
alias pcurl='proxychains curl'
```

---

## Vedi anche

- [DNS Leak](dns-leak.md) - Prevenzione completa dei DNS leak
- [Fingerprinting](fingerprinting.md) - Vettori di fingerprinting browser, rete, OS
- [Traffic Analysis](traffic-analysis.md) - Correlazione end-to-end, website fingerprinting
- [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) - Whonix, Tails, Qubes
- [Analisi Forense e Artefatti](analisi-forense-e-artefatti.md) - Cosa lasci sul disco e in RAM
- [Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md) - CMU/FBI, Freedom Hosting, exploit
- [Etica e Responsabilità](../08-aspetti-legali-ed-etici/etica-e-responsabilita.md) - Uso responsabile di Tor
