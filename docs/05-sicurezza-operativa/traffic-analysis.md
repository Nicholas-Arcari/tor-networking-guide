# Traffic Analysis e Attacchi di Correlazione

Questo documento analizza come un avversario può tentare di deanonimizzare utenti Tor
tramite analisi del traffico, anche senza decifrare il contenuto. Include attacchi di
correlazione end-to-end, website fingerprinting, e le difese implementate da Tor.

---

## Il modello di minaccia di Tor

Tor è progettato per resistere a un avversario che:
- Può osservare **parte** della rete (non tutta)
- Controlla **alcuni** relay (non la maggioranza)
- Può analizzare traffico passivamente

Tor **NON** è progettato per resistere a un avversario che:
- Osserva **tutto** il traffico Internet (avversario globale)
- Controlla sia il Guard che l'Exit del tuo circuito
- Può fare correlazione su larga scala in tempo reale

---

## Attacco di correlazione end-to-end

### Come funziona

Se l'avversario può osservare il traffico **in ingresso** nel Guard e **in uscita**
dall'Exit, può correlare i pattern temporali:

```
Osservazione lato client (Guard):
t=0.00  [100 byte in]
t=0.05  [200 byte in]
t=0.12  [150 byte in]
t=0.50  [pausa]
t=0.55  [500 byte out]

Osservazione lato server (Exit):
t=0.15  [100 byte in]
t=0.20  [200 byte in]
t=0.27  [150 byte in]
t=0.65  [pausa]
t=0.70  [500 byte out]

Correlazione: i pattern sono identici con un ritardo di ~0.15s
→ alta probabilità che siano lo stesso flusso
→ l'utente al Guard sta visitando il sito osservato all'Exit
```

### Perché funziona

Le celle Tor hanno dimensione fissa (514 byte), ma:
- Il **numero** di celle per unità di tempo varia (rivela il volume del traffico)
- La **direzione** delle celle (in vs out) crea un pattern
- Le **pause** tra burst sono correlabili

### Condizioni necessarie

L'avversario deve controllare o osservare:
- Il link tra il client e il Guard (es. l'ISP del client)
- IL link tra l'Exit e la destinazione (es. l'ISP del server)

Oppure:
- Controllare il Guard relay stesso
- Controllare l'Exit relay stesso

### Efficacia

La ricerca accademica mostra che la correlazione end-to-end ha:
- >90% di successo se l'avversario osserva entrambi i punti
- <1% di falsi positivi con algoritmi moderni
- Funziona anche con padding moderato

**Conclusione**: Tor non protegge da un avversario globale. È una limitazione nota
e dichiarata nel design di Tor.

---

## Website Fingerprinting

### Come funziona

Un avversario che può osservare solo il link client→Guard (es. l'ISP) può
determinare quale sito stai visitando basandosi sui **pattern di traffico**:

1. L'avversario visita migliaia di siti web e registra il pattern di traffico
   attraverso Tor (dimensioni pacchetti, timing, direzione)
2. Costruisce un **modello** (machine learning) che associa pattern → sito
3. Quando tu visiti un sito via Tor, l'avversario osserva il tuo traffico
4. Confronta il pattern osservato con i modelli → identifica il sito

### Perché funziona

Ogni sito web ha un "fingerprint di traffico" unico:
- La homepage di Google ha un pattern diverso da quella di Wikipedia
- Il numero di risorse caricate (CSS, JS, immagini) è diverso
- Le dimensioni delle risorse creano un pattern di volume unico
- L'ordine di caricamento è determinato dall'HTML

### Accuratezza (dalla ricerca accademica)

In condizioni di laboratorio:
- >90% di accuratezza su un set chiuso di 100 siti
- ~70-80% su un set più grande con rumore reale
- I difetti peggiorano con: tabbing multiplo, background traffic, padding

In condizioni reali:
- Significativamente peggiore a causa di: variabilità di rete, CDN, A/B testing,
  contenuti dinamici, pubblicità diverse
- Il costo computazionale è alto per monitoraggio su larga scala

### Difese di Tor

**Padding a livello di circuito**: Tor può inserire celle dummy per alterare i pattern.
Le "circuit padding machines" aggiungono padding configurabile per specifici tipi di
circuiti (es. rendezvous per hidden services).

**Limitazione pratica**: un padding sufficiente a sconfiggere il website fingerprinting
richiederebbe un aumento significativo di bandwidth, che i volontari non possono
sostenere.

---

## Timing Attacks

### Flow watermarking

Un avversario che controlla un relay intermedio può "marcare" il flusso con pattern
di timing:

```
Flusso originale: [pkt] [pkt] [pkt] ... [pkt] [pkt]
Flusso marcato:   [pkt] [DELAY] [pkt] [pkt] [DELAY] [pkt] [pkt]
```

I ritardi inseriti creano un "watermark" rilevabile in un altro punto della rete.

### Difese

- Le celle Tor sono di dimensione fissa → nessuna informazione dalla dimensione
- Il multiplexing di circuiti sulla stessa connessione TLS rende difficile
  isolare un singolo flusso
- Il connection padding aggiunge rumore

---

## Attacchi pratici documentati

### Operation Onymous (2014)

Le forze dell'ordine hanno sequestrato decine di hidden services (mercati darknet).
Il metodo esatto non è stato rivelato, ma si sospetta una combinazione di:
- Relay malevoli (relay early tagging)
- Correlazione di traffico
- Errori OPSEC degli operatori

### Carnegie Mellon / FBI (2014)

Ricercatori della Carnegie Mellon University hanno eseguito un attacco Sybil
(centinaia di relay malevoli) combinato con relay early tagging per
deanonimizzare utenti di hidden services. Le informazioni sono state poi
condivise con l'FBI.

Conseguenze per Tor:
- Le celle RELAY_EARLY sono ora limitate e monitorate
- La selezione dei guard è stata migliorata
- Vanguards è stato sviluppato per hidden services

---

## Cosa posso fare per proteggermi

### 1. Usare Tor Browser (non Firefox+proxychains)
Tor Browser ha padding e anti-fingerprinting integrati.

### 2. Evitare pattern di traffico prevedibili
Non visitare sempre gli stessi siti alla stessa ora via Tor.

### 3. Usare bridge obfs4
Nascondono all'ISP che stai usando Tor (l'ISP non sa nemmeno dove
iniziare l'analisi di traffico).

### 4. Non mescolare traffico anonimo e non anonimo
Non usare Tor e non-Tor sulla stessa rete contemporaneamente se sei
preoccupato per un avversario locale.

### 5. Considerare Tails o Whonix
Per scenari ad alto rischio, sistemi operativi dedicati offrono
isolamento completo del traffico.

### Nella mia esperienza

Per il mio caso d'uso (privacy da ISP, test di sicurezza, studio), la traffic
analysis non è una preoccupazione primaria. Il mio avversario principale è l'ISP
e i tracker web, non un'agenzia di intelligence. Ma comprendere questi attacchi
è fondamentale per valutare correttamente il livello di protezione che Tor offre.
