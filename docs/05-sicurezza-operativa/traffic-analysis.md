# Traffic Analysis e Attacchi di Correlazione

Questo documento analizza come un avversario può tentare di deanonimizzare utenti Tor
tramite analisi del traffico, anche senza decifrare il contenuto. Include attacchi di
correlazione end-to-end, website fingerprinting, timing attacks, e le difese implementate
da Tor. Per ogni attacco, analizzo la tecnica, l'efficacia documentata dalla ricerca
accademica, e le contromisure disponibili.

---

## Indice

- [Il modello di minaccia di Tor](#il-modello-di-minaccia-di-tor)
- [Attacco di correlazione end-to-end](#attacco-di-correlazione-end-to-end)
- [Website Fingerprinting](#website-fingerprinting)
**Approfondimenti** (file dedicati):
- [Traffic Analysis - Timing, NetFlow e Difese](traffic-analysis-attacchi-e-difese.md) - Timing, NetFlow, attacchi attivi, circuit padding, difese

---

## Il modello di minaccia di Tor

Tor è progettato per resistere a un avversario che:
- Può osservare **parte** della rete (non tutta)
- Controlla **alcuni** relay (non la maggioranza)
- Può analizzare traffico passivamente

Tor **NON** è progettato per resistere a un avversario che:
- Osserva **tutto** il traffico Internet (avversario globale passivo - GPA)
- Controlla sia il Guard che l'Exit del tuo circuito
- Può fare correlazione su larga scala in tempo reale
- Ha capacità di manipolazione attiva del traffico

### Il threat model formale

```
Tor fornisce:
✓ Anonimato del mittente (il server non sa chi sei)
✓ Anonimato del destinatario (onion services)
✓ Resistenza alla sorveglianza di massa (troppo costoso correlare tutti)
✓ Unlinkability (sessioni diverse non sono correlabili)

Tor NON fornisce:
✗ Resistenza all'avversario globale (chi vede tutto)
✗ Resistenza alla correlazione end-to-end (chi vede ingresso e uscita)
✗ Resistenza al website fingerprinting perfetto (attacco locale)
✗ Resistenza agli attacchi attivi (manipolazione del traffico)
```

---

## Attacco di correlazione end-to-end

### Come funziona

Se l'avversario può osservare il traffico **in ingresso** nel Guard e **in uscita**
dall'Exit, può correlare i pattern temporali:

```
Osservazione lato client (Guard):
t=0.000  [burst: 5 celle in, 0 out]
t=0.050  [burst: 3 celle in, 2 out]
t=0.120  [burst: 8 celle in, 0 out]
t=0.500  [pausa: 380ms senza traffico]
t=0.550  [burst: 2 celle in, 5 out]

Osservazione lato server (Exit):
t=0.150  [burst: 5 celle in, 0 out]    ← +150ms
t=0.200  [burst: 3 celle in, 2 out]    ← +150ms
t=0.270  [burst: 8 celle in, 0 out]    ← +150ms
t=0.650  [pausa: 380ms senza traffico] ← stessa durata!
t=0.700  [burst: 2 celle in, 5 out]    ← +150ms

Correlazione statistica:
  - I pattern sono identici con un ritardo di ~150ms
  - La distribuzione delle pause è identica
  - La direzione dei burst è identica
  → Probabilità >95% che siano lo stesso flusso
  → L'utente al Guard sta comunicando con il server osservato all'Exit
```

### Perché funziona

Le celle Tor hanno dimensione fissa (514 byte), ma questo non basta a prevenire
la correlazione. Le informazioni che leakano:

```
1. Volume: il NUMERO di celle per unità di tempo varia
   → Una pagina web con 50 immagini genera più celle di una con 2
   → Il volume rivela il "peso" della comunicazione

2. Direzione: la DIREZIONE delle celle (in vs out) crea un pattern
   → Download: molte celle in, poche out
   → Upload: molte celle out, poche in
   → Chat: distribuzione bilanciata

3. Timing: le PAUSE tra burst sono correlabili
   → L'utente clicca un link → pausa → burst di dati
   → Il pattern di interazione umana è unico
   → Anche jitter di rete non nasconde le macro-pause

4. Burst structure: la STRUTTURA dei burst
   → HTTP/1.1: richiesta → risposta → richiesta → risposta
   → HTTP/2: richieste multiplexate → burst complesso
   → Il protocollo applicativo crea pattern specifici
```

### Condizioni necessarie

L'avversario deve controllare o osservare:

```
Scenario 1 (osservazione passiva):
  - Il link tra il client e il Guard (es. l'ISP del client)
  - Il link tra l'Exit e la destinazione (es. l'ISP del server)
  → Possibile per ISP che collaborano

Scenario 2 (relay malevoli):
  - Controllare il Guard relay stesso
  - Controllare l'Exit relay stesso
  → Possibile con attacco Sybil (vedi attacchi-noti.md)

Scenario 3 (CDN):
  - Cloudflare vede ~15-20% del traffico web
  - Se il tuo ISP collabora E il sito usa Cloudflare → correlazione
  → Possibile per un avversario con accesso a CDN + ISP

Scenario 4 (IXP):
  - Un Internet Exchange Point vede traffico di molti ISP
  - Un IXP grande può osservare sia il lato Guard che il lato Exit
  → Possibile per avversari con accesso agli IXP
```

### Efficacia documentata

La ricerca accademica mostra:

```
Murdoch & Danezis (2005): primi attacchi di correlazione
  - ~50% true positive con pochi minuti di osservazione
  
Levine et al. (2004): "Timing Attacks in Low-Latency Mix Systems"
  - >80% true positive rate
  - Padding a livello di celle non è sufficiente

Johnson et al. (2013): "Users Get Routed"
  - Simulazione su rete Tor reale
  - >80% degli utenti deanonimizzati in 6 mesi
  - Il Guard persistente aiuta ma non elimina il rischio

Nasr et al. (2018): "DeepCorr"
  - Deep learning per correlazione
  - >96% true positive con <0.1% false positive
  - Funziona anche con Tor circuit padding
  - Richiede solo 25 secondi di osservazione
```

### Limitazione fondamentale

**Tor non è progettato per resistere alla correlazione end-to-end.**
Questa è una limitazione dichiarata, nota, e probabilmente irrisolvibile
per una rete a bassa latenza. Le contromisure (padding, batching) rendono
l'attacco più costoso ma non lo prevengono.

---

## Website Fingerprinting

### Come funziona

Un avversario che può osservare solo il link client→Guard (es. l'ISP) può
determinare quale sito stai visitando basandosi sui **pattern di traffico**:

```
Fase di training:
1. L'avversario visita migliaia di siti web via Tor
2. Per ogni sito, registra il "fingerprint" di traffico:
   - Sequenza di dimensioni dei pacchetti
   - Sequenza di direzioni (in/out)
   - Timing tra pacchetti
   - Numero totale di pacchetti
   - Burst patterns
3. Allena un classificatore (machine learning) su questi fingerprint

Fase di attacco:
1. L'avversario osserva il tuo traffico client→Guard
2. Estrae le stesse feature
3. Il classificatore confronta con i fingerprint noti
4. Restituisce: "L'utente sta visitando il Sito X con probabilità 93%"
```

### Perché funziona

Ogni sito web ha un "fingerprint di traffico" unico:

```
Google.com:
  [in: 5 celle] [out: 2] [in: 15] [out: 3] [in: 50] [out: 5]
  Totale: ~80 celle, ratio in/out: 7:1

Wikipedia.org (articolo lungo):
  [in: 5 celle] [out: 2] [in: 200] [out: 8] [in: 30] [out: 2]
  Totale: ~247 celle, ratio in/out: 23:1

GitHub.com (repository):
  [in: 5 celle] [out: 3] [in: 40] [out: 10] [in: 60] [out: 15]
  Totale: ~133 celle, ratio in/out: 3.5:1

I fingerprint differiscono per:
- Numero di risorse caricate (CSS, JS, immagini)
- Dimensioni delle risorse
- Ordine di caricamento (determinato dall'HTML)
- Protocollo HTTP/1.1 vs HTTP/2 (multiplexing diverso)
```

### Accuratezza (dalla ricerca accademica)

**Mondo chiuso** (l'avversario conosce tutti i siti possibili):

```
Panchenko et al. (2016): "Website Fingerprinting at Internet Scale"
  - SVM classifier
  - >90% accuracy su 100 siti monitorati

Sirinam et al. (2018): "Deep Fingerprinting"
  - CNN (deep learning)
  - >98% accuracy su 95 siti (mondo chiuso)
  - ~95% con tabbing multiplo

Rahman et al. (2020): "Tik-Tok"
  - Usa timing features
  - >96% accuracy
```

**Mondo aperto** (l'utente può visitare qualsiasi sito):

```
In condizioni reali:
  - 60-80% true positive rate (identifica il sito corretto)
  - 5-15% false positive rate
  - Degrada significativamente con:
    → Multi-tab browsing (rumore da traffico contemporaneo)
    → Background traffic (download, aggiornamenti)
    → CDN e A/B testing (pagine servite diversamente)
    → Contenuti dinamici e personalizzati
    → Pubblicità diverse per sessione
  - Il costo computazionale è alto per monitoraggio su larga scala
```

### Difese contro il website fingerprinting

**Padding a livello di circuito**: Tor può inserire celle dummy per alterare i pattern.
Le "circuit padding machines" aggiungono padding configurabile per specifici tipi di
circuiti (es. rendezvous per hidden services).

**WTF-PAD** (Wang & Goldberg, 2017):
```
- Aggiunge padding adattivo basato su una macchina a stati
- Osserva i gap tra pacchetti e inserisce padding nei gap
- Riduce l'accuracy del WF del ~20-30%
- Overhead bandwidth: ~60%
```

**FRONT** (Gong & Wang, 2020):
```
- Aggiunge padding solo alla "front" della traccia (primi pacchetti)
- I classificatori dipendono molto dai primi pacchetti
- Riduce accuracy del ~40% con solo ~30% overhead
```

**Limitazione pratica**: un padding sufficiente a sconfiggere il website fingerprinting
richiederebbe un aumento significativo di bandwidth (~50-100%), che i volontari non
possono sostenere. Il Tor Project bilancia sicurezza e costo.


---

> **Continua in**: [Traffic Analysis - Timing, NetFlow e Difese](traffic-analysis-attacchi-e-difese.md)
> per timing attack, NetFlow, attacchi attivi, circuit padding e contromisure.

---

## Vedi anche

- [Traffic Analysis - Timing, NetFlow e Difese](traffic-analysis-attacchi-e-difese.md) - Timing, NetFlow, attacchi, padding, difese
- [Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md) - CMU/FBI, Freedom Hosting, Sybil
- [Fingerprinting](fingerprinting.md) - Browser, TLS/JA3, OS fingerprinting
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - Difese comportamentali
- [Limitazioni del Protocollo](../07-limitazioni-e-attacchi/limitazioni-protocollo.md) - Limiti tecnici di Tor
- [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) - Whonix, Tails per scenari ad alto rischio
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
