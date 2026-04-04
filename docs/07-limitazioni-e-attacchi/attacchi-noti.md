# Attacchi Noti alla Rete Tor — Cronologia e Analisi Tecnica

Questo documento cataloga gli attacchi documentati contro la rete Tor: attacchi
di correlazione, Sybil, relay early tagging, HSDir enumeration, website fingerprinting,
e le contromisure adottate dopo ogni incidente.

---

## 1. Sybil Attack

### Come funziona

Un avversario gestisce un gran numero di relay nella rete Tor per aumentare
la probabilità di controllare sia il Guard che l'Exit di un circuito.

```
Scenario:
- La rete Tor ha 7000 relay
- L'avversario ne aggiunge 700 (10% della rete)
- Probabilità di controllare Guard AND Exit: ~1% per circuito
- Con migliaia di circuiti, deanonimizzazione probabile per utenti attivi
```

### Caso reale: CMU/FBI (2014)

Ricercatori della Carnegie Mellon University hanno inserito ~115 relay nella rete
Tor tra gennaio e luglio 2014. Questi relay:
- Avevano flag HSDir (per intercettare descriptor di hidden service)
- Usavano la tecnica "relay early tagging" per marcare i circuiti
- Hanno raccolto informazioni su utenti di hidden services specifici

Le informazioni sono state condivise con l'FBI, che le ha usate per identificare
operatori di mercati darknet.

### Contromisure adottate

- Le Directory Authorities ora monitorano l'aggiunta di relay in massa
- I relay nella stessa /16 subnet non vengono usati nello stesso circuito
- `MyFamily` obbliga i relay co-gestiti a dichiararsi
- Le bandwidth authorities limitano l'influenza di relay nuovi
- Le celle RELAY_EARLY sono ora monitorate e limitate

---

## 2. Relay Early Tagging Attack

### Come funziona

Un relay malevolo (middle) inserisce informazioni in celle `RELAY_EARLY`
che normalmente non dovrebbero contenere dati:

```
1. Client → Guard → Middle malevolo → Exit malevolo
2. Il Middle inserisce tag nelle celle RELAY_EARLY
3. L'Exit riconosce il tag
4. L'Exit può ora correlare: questo circuito viene dal Guard X
5. Se l'Exit conosce anche la destinazione → deanonimizzazione
```

### Caso reale: CMU/FBI (2014)

Questo è lo stesso attacco del caso Sybil sopra. I relay CMU usavano
relay early tagging per "marcare" circuiti verso hidden services specifici,
poi raccoglievano le risposte sugli exit che controllavano.

### Contromisure adottate (Tor 0.2.4.23+)

- I client contano le celle RELAY_EARLY: max 8 per circuito
- I relay che inviano RELAY_EARLY anomali vengono segnalati e rimossi
- Il guard non inoltra celle RELAY_EARLY verso il middle/exit
  (le converte in celle RELAY normali)

---

## 3. Attacco di correlazione end-to-end

### Come funziona

Se l'avversario controlla (o osserva) sia il primo hop (guard o link client→guard)
che l'ultimo hop (exit o link exit→destinazione), può correlare il timing del
traffico per deanonimizzare l'utente.

```
Osservazione lato ingresso:        Osservazione lato uscita:
t=0.00 [burst 5 celle]            t=0.15 [burst 5 celle]
t=0.50 [pausa]                    t=0.65 [pausa]
t=0.55 [burst 3 celle]            t=0.70 [burst 3 celle]

Correlazione statistica → stesso flusso con ~95% di confidenza
```

### Efficacia documentata

La ricerca accademica mostra:
- >90% true positive rate
- <6% false positive rate
- Funziona anche con padding moderato
- Richiede pochi minuti di osservazione per confermare la correlazione

### Limitazione fondamentale

Tor **non è progettato** per resistere a un avversario che controlla entrambi
gli endpoint. Questa è una limitazione dichiarata nel threat model di Tor.

Le contromisure (padding, connection padding) rendono l'attacco più costoso
ma non lo prevengono.

### Chi può fare questo attacco

- Agenzie di intelligence con capacità di sorveglianza globale
- ISP che collaborano (l'ISP del client + l'ISP della destinazione)
- Organizzazioni che controllano relay guard + exit
- CDN che vedono il traffico di uscita (Cloudflare vede ~15% del web)

---

## 4. Website Fingerprinting

### Come funziona

Un avversario locale (es. ISP) osserva solo il traffico client→guard e
determina quale sito sta visitando l'utente analizzando i pattern:

```
Sito A: [300 celle in] [100 celle out] [500 celle in] [50 celle out]
Sito B: [150 celle in] [200 celle out] [100 celle in] [300 celle out]

Pattern osservato: [300 celle in] [100 celle out] [500 celle in] [50 celle out]
Conclusione: l'utente sta visitando il Sito A
```

### Stato dell'arte

Ricerche recenti (2020-2025) usando deep learning:
- >95% accuratezza in condizioni di laboratorio (mondo chiuso)
- 60-80% in condizioni reali (mondo aperto, rumore, multi-tab)
- La difesa più efficace è il padding randomizzato

### Contromisure in sviluppo

Il Tor Project sta sviluppando "circuit padding frameworks" che implementano
macchine a stati per generare padding specifico anti-website-fingerprinting.
Attualmente usate per hidden service rendezvous, in futuro potrebbero essere
estese a circuiti generali.

---

## 5. HSDir Enumeration

### Come funziona

Gli HSDir (Hidden Service Directory) sono relay che memorizzano i descriptor
degli onion service. Un avversario che controlla HSDir può:

1. Vedere quali descriptor vengono richiesti (quale .onion è popolare)
2. Vedere quando vengono aggiornati
3. Correlare richieste con circuiti per restringere la posizione dell'HS

### Contromisure (Onion Service v3)

- I descriptor sono indirizzati con una funzione hash che include il time period
  → gli HSDir cambiano ogni 24 ore
- I descriptor sono cifrati → l'HSDir non può leggerli
- Il client deve conoscere l'indirizzo .onion per calcolare quale HSDir contattare
  → l'HSDir non sa quale .onion sta servendo

---

## 6. Denial of Service (DoS) sulla rete Tor

### Attacchi ai relay

Un avversario può:
- DDoS-are relay specifici per forzare il cambio di guard degli utenti
- Sovraccaricare exit node per ridurre le opzioni di uscita
- Sovraccaricare le Directory Authorities per impedire l'aggiornamento del consenso

### Attacchi agli hidden services

- DDoS degli Introduction Points per rendere l'HS irraggiungibile
- Richieste massive al descriptor per sovraccaricare gli HSDir

### Contromisure

- Proof-of-Work (PoW) per le connessioni agli onion service (Tor 0.4.8+):
  i client devono risolvere un puzzle computazionale per connettersi,
  rendendo il DDoS molto più costoso
- Rate limiting sulle DA
- Diversificazione degli Introduction Points

---

## 7. Attacchi al browser (exploit)

### Freedom Hosting (2013)

L'FBI ha compromesso il server di Freedom Hosting (che ospitava hidden services)
e ha iniettato un exploit JavaScript nel Tor Browser (basato su Firefox ESR 17):

```javascript
// L'exploit sfruttava una vulnerabilità Firefox per:
// 1. Bypassare la sandbox del browser
// 2. Eseguire codice nativo
// 3. Inviare l'IP reale e il MAC address a un server FBI
```

### Contromisure

- Tor Browser è aggiornato frequentemente per patchare vulnerabilità
- Il "Security Level" di Tor Browser limita JavaScript
- Sandboxing del processo browser
- Su Tails/Whonix, anche un exploit del browser non rivela l'IP
  (il traffico è forzato attraverso Tor a livello di firewall)

---

## 8. Attacchi alla supply chain

### Scenario

Un avversario compromette il processo di build di Tor o Tor Browser per inserire
backdoor nel software distribuito.

### Contromisure

- **Reproducible builds**: Tor Browser supporta build riproducibili — chiunque
  può ricompilare il codice sorgente e verificare che il binario distribuito
  corrisponda
- **Firme GPG**: tutti i download sono firmati con le chiavi del Tor Project
- **Codice open source**: il codice è auditabile pubblicamente

---

## Matrice degli attacchi e contromisure

| Attacco | Avversario necessario | Contromisura Tor | Efficacia contromisura |
|---------|----------------------|-----------------|----------------------|
| Sybil | Risorse per ~100+ relay | Monitoring DA, family, /16 rule | Media |
| Relay Early Tagging | Controllo di relay middle+exit | Counting RELAY_EARLY, conversione | Alta |
| Correlazione end-to-end | Osservazione di ingresso+uscita | Padding (limitato) | Bassa |
| Website Fingerprinting | Osservazione locale (ISP) | Circuit padding (in sviluppo) | Media |
| HSDir Enumeration | Controllo di HSDir relay | v3 descriptor cifrati, rotazione | Alta |
| DoS su relay | Bandwidth per DDoS | PoW, rate limiting | Media |
| Browser exploit | 0-day nel browser | Aggiornamenti, Security Level | Media |
| Supply chain | Accesso al build system | Reproducible builds, GPG | Alta |

---

## Conclusione pratica

Nessun sistema è invulnerabile. Tor offre protezione significativa contro la
sorveglianza di massa e gli avversari locali, ma ha limiti documentati contro
avversari con risorse significative (agenzie di intelligence, ISP collaboranti).

Per il mio caso d'uso (privacy dall'ISP, test di sicurezza), le protezioni di
Tor sono più che sufficienti. L'avversario più probabile (ISP, tracker web) non
ha le risorse per gli attacchi descritti sopra.

Per scenari ad alto rischio (giornalismo in regime autoritario, whistleblowing),
le contromisure aggiuntive (Tails, Whonix, OPSEC rigoroso) sono necessarie.
