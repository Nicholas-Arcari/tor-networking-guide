> **Lingua / Language**: Italiano | [English](../en/05-sicurezza-operativa/traffic-analysis-attacchi-e-difese.md)

# Traffic Analysis - Timing, NetFlow e Difese

Timing attack (flow watermarking, clock skew, inter-packet), NetFlow analysis,
attacchi attivi (replay, dropping, tagging), circuit padding framework di Tor,
attacchi pratici documentati e contromisure.

> **Estratto da**: [Traffic Analysis e Attacchi di Correlazione](traffic-analysis.md)
> per correlazione end-to-end e website fingerprinting.

---


### Flow watermarking

Un avversario che controlla un relay intermedio può "marcare" il flusso con pattern
di timing artificiali:

```
Flusso originale:  [pkt][pkt][pkt][pkt][pkt][pkt][pkt][pkt]
                   ||||||||||||||||||||||||||||||||||||||||

Flusso marcato:    [pkt][DELAY 20ms][pkt][pkt][DELAY 20ms][pkt][pkt][DELAY 20ms]
                   |||               ||||||               ||||||
                   Pattern: 1-2-2-2-2-... (watermark binario)

L'avversario:
1. Il relay middle malevolo inserisce ritardi specifici
2. Il pattern di ritardi codifica un "tag" (es. ID del circuito)
3. Un osservatore in un altro punto della rete rileva il pattern
4. Il pattern sopravvive attraverso gli hop Tor
5. → Correlazione: il circuito marcato appartiene all'utente X
```

### Clock skew fingerprinting

Ogni computer ha un orologio leggermente diverso (clock skew). Misurando i
timestamp TCP:

```
Il server invia un pacchetto e riceve la risposta.
Il RTT dovrebbe essere costante, ma il clock skew del client
causa variazioni sistematiche.

Clock skew del client A: +2.3 ppm (parti per milione)
Clock skew del client B: -1.7 ppm

Se l'avversario misura il clock skew del tuo traffico Tor
e lo confronta con traffico non-Tor dello stesso computer:
→ Correlazione tramite clock skew
```

### Inter-packet timing analysis

```
Anche con celle di dimensione fissa (514 byte), il TIMING tra celle rivela:

1. Typing patterns (chat, SSH):
   - Ogni tasto premuto genera un pacchetto
   - Il ritardo tra tasti è unico per ogni persona
   - "the" → 3 pacchetti con timing specifico
   
2. Application behavior:
   - HTTP/1.1: request-response sequenziale → pattern regolare
   - HTTP/2: multiplexed → burst irregolari
   - Streaming video: burst periodici ogni X secondi
   
3. User interaction:
   - Click → pausa → scroll → pausa → click
   - Il pattern di interazione è un fingerprint comportamentale
```

### Difese contro timing attacks

```
1. Celle di dimensione fissa (già implementato in Tor):
   → Nessuna informazione dalla dimensione del pacchetto
   → Ma il timing tra celle resta informativo

2. Connection padding (implementato in Tor):
   → Celle dummy inviate periodicamente sulle connessioni TLS tra relay
   → Nasconde le pause nel traffico
   → Overhead contenuto (~5%)

3. Circuit padding (implementato parzialmente):
   → Celle dummy specifiche per tipo di circuito
   → Attualmente usate per proteggere rendezvous di HS
   → In futuro: estensione a circuiti generali

4. Multiplexing (già implementato):
   → Più circuiti sulla stessa connessione TLS
   → I pattern di un circuito sono mescolati con quelli di altri
   → Ma un avversario sofisticato può demultiplexare
```

---

## NetFlow Analysis

### Come funziona

I router di backbone mantengono record NetFlow che includono:
- IP sorgente e destinazione
- Porte sorgente e destinazione
- Numero di pacchetti e byte
- Timestamp di inizio e fine
- Protocollo

```
Un avversario con accesso ai NetFlow di più ISP/IXP può:

1. Identificare flussi client → Guard Tor (IP del Guard è noto)
2. Identificare flussi Exit Tor → server destinazione
3. Correlare per timing e volume

Esempio:
  NetFlow ISP del client: 151.x.x.x → Guard (185.y.y.y)
    Inizio: 14:30:00, Fine: 14:45:00, Bytes: 2.3 MB
    
  NetFlow ISP del server: Exit (104.z.z.z) → Server (93.w.w.w)
    Inizio: 14:30:05, Fine: 14:44:55, Bytes: 2.1 MB
    
  Correlazione: timing simile, volume simile
  → Probabilità alta che 151.x.x.x stia comunicando con 93.w.w.w
```

### Efficacia

```
Chakravarty et al. (2014): "Traffic Analysis against Low-Latency Anonymity Networks"
  - Usa NetFlow data da un singolo AS
  - ~81% true positive rate per flussi di lunga durata (>5 minuti)
  
Johnson et al. (2013): "Users Get Routed"
  - Modellazione con AS path reali
  - Un singolo AS che osserva molte connessioni Tor
    può deanonimizzare una percentuale significativa di utenti
  - L'AS che ospita il Guard e l'AS della destinazione sono punti critici
```

### Perché è rilevante

```
- I dati NetFlow sono conservati routinariamente dai provider
- Le agenzie di intelligence hanno accesso a NetFlow di backbone
- Il programma NSA "XKeyscore" raccoglieva metadati di rete globali
- I dati NetFlow non richiedono deep packet inspection
- Sono sufficienti i metadati (timing, volume, IP)
```

---

## Attacchi attivi di manipolazione del traffico

### Replay attack

```
Un relay malevolo registra celle e le re-invia successivamente.
Se l'avversario osserva il circuito in un altro punto:
- Vede le celle duplicate
- Può correlare i due punti di osservazione

Contromisura: Tor rileva e scarta celle duplicate tramite
il sequence numbering (RELAY_EARLY counting, digest check)
```

### Dropping attack

```
Un relay malevolo scarta selettivamente celle in determinati circuiti.
Se il client crea un nuovo circuito (perché il primo fallisce):
- Il nuovo circuito potrebbe passare per relay diversi
- L'avversario osserva la sequenza di tentativi
- Pattern di fallimento → fingerprint del circuito

Contromisura: Path Bias (Tor monitora i circuiti che falliscono
troppo spesso e penalizza i relay sospetti)
```

### Tagging attack

```
Un relay malevolo modifica i dati nelle celle (bit flip):
- Il relay A flippa un bit nella cella cifrata
- Il relay B (controllato dallo stesso avversario) controlla il bit
- Se il bit è flippato → il circuito passa da A e B
- → Correlazione: l'avversario sa che questo circuito è di interesse

Contromisura: il digest nelle celle RELAY rileva le modifiche.
Se il digest è sbagliato, il circuito viene chiuso.
```

---

## Circuit padding framework di Tor

### Come funziona

Il Tor Project ha implementato un "circuit padding framework" che permette
di definire macchine a stati per il padding:

```
Una padding machine definisce:
- Stati (es. START, BURST_DETECTED, PADDING, END)
- Transizioni tra stati (basate su eventi di traffico)
- Azioni per ogni stato (invia padding, aspetta, etc.)
- Distribuzioni di timing per il padding

Esempio (semplificato):
  State: IDLE
    On: celle ricevute dall'altra parte → goto PADDING
  
  State: PADDING
    Action: invia 5-15 celle dummy con delay 0-50ms
    On: timeout 100ms → goto IDLE
    On: celle reali ricevute → reset timer

Attualmente implementate:
1. HS rendezvous padding:
   - Protegge i circuiti verso hidden services
   - Aggiunge padding durante la fase di rendezvous
   - Rende più difficile identificare connessioni a .onion

2. Connection padding:
   - Celle padding sulle connessioni TLS tra relay
   - Inviate periodicamente durante le pause
   - Nasconde il pattern di attività/inattività
```

### Efficacia attuale

```
- Riduce accuracy del website fingerprinting del ~10-20%
- Overhead bandwidth: ~5-10% per connection padding
- Protezione significativa per HS rendezvous
- NON sufficiente per sconfiggere completamente il WF
- In sviluppo continuo: nuove padding machines pianificate
```

---

## Attacchi pratici documentati

### Operation Onymous (2014)

Le forze dell'ordine hanno sequestrato decine di hidden services (mercati darknet).
Il metodo esatto non è stato rivelato, ma si sospetta una combinazione di:
- Relay malevoli (relay early tagging)
- Correlazione di traffico
- Errori OPSEC degli operatori
- Possibile exploit dell'applicazione web (non di Tor)

### Carnegie Mellon / FBI (2014)

Ricercatori della Carnegie Mellon University hanno eseguito un attacco Sybil
(~115 relay malevoli) combinato con relay early tagging per
deanonimizzare utenti di hidden services:

```
Tecnica:
1. Inseriti ~115 relay con flag HSDir e Guard
2. I relay usavano RELAY_EARLY tagging per marcare circuiti
3. Quando un client si connetteva a un HS, il relay malevolo
   inseriva un tag nelle celle RELAY_EARLY
4. Un altro relay malevolo riconosceva il tag
5. → Correlazione: questo client visita questo hidden service

Conseguenze per Tor:
- Le celle RELAY_EARLY sono ora limitate e monitorate (max 8 per circuito)
- La selezione dei guard è stata migliorata
- Vanguards sviluppato per hidden services
- Monitoring attivo per inserimenti massicci di relay
```

### RAPTOR (2015)

```
Sun et al. (2015): "RAPTOR: Routing Attacks on Privacy in Tor"
  
Attacco che sfrutta il routing BGP per dirigere traffico Tor
attraverso AS controllati dall'avversario:

1. BGP hijacking: l'avversario annuncia rotte più specifiche
   per gli IP dei Guard Tor
2. Il traffico client→Guard viene rediretto attraverso l'AS dell'avversario
3. L'avversario può ora osservare il traffico in ingresso
4. Combinato con osservazione lato uscita → correlazione end-to-end

Efficacia: >90% dei circuiti Tor vulnerabili a BGP routing attacks
```

---

## Difese e contromisure

### Cosa posso fare per proteggermi

**1. Usare Tor Browser (non Firefox+proxychains)**
Tor Browser ha padding e anti-fingerprinting integrati. Le circuit padding
machines proteggono specifici tipi di circuiti.

**2. Evitare pattern di traffico prevedibili**
Non visitare sempre gli stessi siti alla stessa ora via Tor. La variazione
nei pattern rende la correlazione più difficile.

**3. Usare bridge obfs4**
Nascondono all'ISP che stai usando Tor. L'ISP non sa nemmeno dove iniziare
l'analisi di traffico perché il traffico sembra HTTPS generico.

**4. Non mescolare traffico anonimo e non anonimo**
Non usare Tor e non-Tor sulla stessa rete contemporaneamente se sei
preoccupato per un avversario locale.

**5. Considerare Tails o Whonix**
Per scenari ad alto rischio, sistemi operativi dedicati offrono isolamento
completo del traffico e prevengono leak.

**6. Sessioni brevi**
Sessioni più corte offrono meno dati per la correlazione.
Usare NEWNYM tra attività diverse.

**7. Evitare sessioni interattive prolungate**
Chat e SSH via Tor sono particolarmente vulnerabili a timing analysis
(ogni tasto genera un pacchetto con timing unico).

### Cosa NON può proteggermi

```
Nessuna contromisura può:
- Proteggere da un avversario globale passivo con certezza matematica
- Eliminare completamente il website fingerprinting
- Rendere le sessioni SSH via Tor sicure da timing analysis
- Impedire la correlazione se Guard E Exit sono compromessi
```

---

## Nella mia esperienza

Per il mio caso d'uso (privacy da ISP, test di sicurezza, studio), la traffic
analysis non è una preoccupazione primaria. Il mio avversario principale è l'ISP
e i tracker web, non un'agenzia di intelligence. Ma comprendere questi attacchi
è fondamentale per valutare correttamente il livello di protezione che Tor offre.

I punti chiave che ho interiorizzato:
1. Tor protegge dalla sorveglianza **di massa**, non da quella **mirata**
2. La correlazione end-to-end è il limite fondamentale delle reti a bassa latenza
3. Il website fingerprinting è un rischio reale ma mitigabile (Tor Browser)
4. Bridge obfs4 è la difesa più pratica contro l'ISP locale
5. L'OPSEC umano conta più di qualsiasi difesa tecnica

---

## Vedi anche

- [Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md) - CMU/FBI, Freedom Hosting, Sybil
- [Fingerprinting](fingerprinting.md) - Browser, TLS/JA3, OS fingerprinting
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - Difese comportamentali
- [Limitazioni del Protocollo](../07-limitazioni-e-attacchi/limitazioni-protocollo.md) - Limiti tecnici di Tor
- [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) - Whonix, Tails per scenari ad alto rischio
- [Bridges e Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Bridge obfs4 come difesa da ISP
