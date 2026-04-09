# Attacchi Noti - HSDir, DoS, Browser Exploit e Contromisure

HSDir enumeration, Denial of Service, exploit del browser (Freedom Hosting,
Playpen), supply chain, BGP/RAPTOR, Sniper Attack, attacchi agli Onion Services,
matrice completa degli attacchi e cronologia delle contromisure adottate da Tor.

> **Estratto da** [Attacchi Noti alla Rete Tor](attacchi-noti.md) - che copre
> anche Sybil attack, relay early tagging, correlazione end-to-end e website
> fingerprinting.

---

## 5. HSDir Enumeration

### Come funziona

Gli HSDir (Hidden Service Directory) sono relay che memorizzano i descriptor
degli onion service. Un avversario che controlla HSDir può:

```
Onion Services v2 (deprecato):
  1. L'HSDir è determinato dalla combinazione di:
     indirizzo .onion + data corrente + posizione nel DHT
  2. Un avversario può calcolare QUALI HSDir conterranno
     il descriptor di un dato .onion
  3. Posizionando relay in quelle posizioni:
     → Vede le richieste per quel descriptor
     → Sa quando il descriptor viene aggiornato
     → Può correlare richieste con circuiti

2016 - Ricercatori hanno enumerato ~110.000 onion services v2
  analizzando le richieste agli HSDir
```

### Contromisure (Onion Service v3)

```
v3 ha risolto molte vulnerabilità di v2:

1. Descriptor cifrati:
   - Il descriptor è cifrato con la chiave pubblica dell'HS
   - L'HSDir NON può leggere il contenuto del descriptor
   - Non sa quale .onion sta servendo

2. Rotazione degli HSDir:
   - Gli HSDir cambiano ogni 24 ore (time period based)
   - L'avversario deve riposizionare i relay continuamente

3. Blinding della chiave:
   - La chiave usata per il DHT è derivata (blinded)
   - Non è possibile risalire all'indirizzo .onion dal DHT

4. Richiesta autenticata:
   - Il client deve conoscere l'indirizzo .onion per calcolare
     quale HSDir contattare
   - Un HSDir casuale non può scoprire nuovi .onion

5. Client authorization:
   - L'HS può richiedere autenticazione del client
   - Solo client autorizzati possono scaricare il descriptor
```

---

## 6. Denial of Service (DoS) sulla rete Tor

### Attacchi ai relay

```
Un avversario può:
1. DDoS-are relay specifici per forzare il cambio di guard
   - L'utente deve scegliere un nuovo guard
   - Se il nuovo guard è malevolo → compromissione
   - "Guard rotation attack"

2. Sovraccaricare exit node
   - Riduce le opzioni di uscita → meno anonimato
   - Forza il traffico su exit ancora disponibili → congestione

3. Sovraccaricare le Directory Authorities
   - Impedisce l'aggiornamento del consenso
   - I client non possono ottenere informazioni sulla rete
```

### Attacchi agli hidden services (2021-2023)

```
Dal 2021, la rete Tor ha subito attacchi DoS significativi
mirati agli onion services:

Tecnica:
  - Flood di richieste verso gli Introduction Points
  - L'HS deve processare ogni richiesta (costoso)
  - L'attaccante non deve pagare alcun costo
  → Asimmetria: poco costo per l'attaccante, alto per l'HS

Impatto:
  - Molti .onion irraggiungibili per ore/giorni
  - Degradazione performance della rete intera
  - Impatto su servizi legittimi (.onion di giornali, SecureDrop)
```

### Contromisure

```
1. Proof-of-Work (PoW) per onion services (Tor 0.4.8+):
   - I client devono risolvere un puzzle computazionale
   - Il puzzle scala con il carico dell'HS
   - Sotto carico: il puzzle diventa più difficile
   - L'attaccante deve spendere CPU per ogni richiesta
   - Implementazione: EquiX (Equihash-based)

2. Rate limiting sulle Directory Authorities:
   - Limita le richieste per IP
   - Previene flooding del consenso

3. Diversificazione degli Introduction Points:
   - L'HS può avere più Introduction Points
   - Se uno è sotto attacco, gli altri funzionano

4. Vanguards:
   - Relay persistenti multi-livello per proteggere il percorso
     verso gli Introduction Points
   - Previene che l'avversario scopra l'IP dell'HS tramite DoS
     selettivo degli Introduction Points
```

---

## 7. Attacchi al browser (exploit)

### Freedom Hosting (2013)

L'FBI ha compromesso il server di Freedom Hosting (che ospitava hidden services)
e ha iniettato un exploit JavaScript nel Tor Browser (basato su Firefox ESR 17):

```
Tecnica:
  1. L'FBI ha ottenuto il controllo del server Freedom Hosting
  2. Ha iniettato codice JavaScript malevolo nelle pagine servite
  3. L'exploit sfruttava CVE-2013-1690 (Firefox ESR 17)
  4. Il payload:
     a. Bypassava la sandbox del browser
     b. Eseguiva codice nativo (shellcode)
     c. Recuperava l'IP reale della vittima
     d. Recuperava il MAC address
     e. Recuperava l'hostname del computer
     f. Inviava i dati a un server FBI (IP: 65.222.202.54)
  5. Funzionava solo su Windows (il payload era un PE)
  6. Su Linux/macOS: l'exploit non aveva effetto

Risultato:
  - Centinaia di utenti di Freedom Hosting identificati
  - Arresti multipli per possesso di materiale CSAM
  - Eric Eoin Marques (operatore Freedom Hosting) arrestato
```

### Playpen (2015)

```
L'FBI ha usato una tecnica simile per identificare utenti di Playpen:
  1. Ha preso il controllo del server Playpen (hidden service CSAM)
  2. Ha operato il sito per 13 giorni
  3. Ha distribuito un NIT (Network Investigative Technique)
     tramite exploit del browser
  4. Il NIT recuperava IP reale, MAC, hostname
  5. ~8.700 IP raccolti, 137 incriminati

Controversia legale:
  - L'FBI ha operato un sito CSAM per 13 giorni
  - Dibattito sulla legalità dell'operazione
  - I NIT sono stati contestati in tribunale
  - Alcuni casi archiviati per violazione del quarto emendamento
```

### Contromisure

```
1. Aggiornamenti frequenti:
   - Tor Browser segue il ciclo di Firefox ESR (~6 settimane)
   - Patch di sicurezza applicate immediatamente
   - REGOLA: aggiornare SEMPRE appena disponibile

2. Security Level:
   - "Safest" disabilita JavaScript → elimina la superficie di attacco
   - "Safer" disabilita JIT → elimina exploit JIT-based

3. Sandboxing:
   - Tor Browser usa il sandboxing di Firefox (seccomp-bpf su Linux)
   - Limita le syscall disponibili all'exploit
   - Non è impenetrabile ma alza la barra

4. Isolamento del sistema:
   - Su Tails/Whonix: anche un exploit del browser non rivela l'IP
   - Il firewall del sistema forza tutto il traffico via Tor
   - L'exploit non può bypassare il firewall del Gateway

5. NoScript:
   - Blocca JavaScript per default ai livelli Safer/Safest
   - Riduce drasticamente la superficie di attacco
```

---

## 8. Attacchi alla supply chain

### Scenario

Un avversario compromette il processo di build di Tor o Tor Browser per inserire
backdoor nel software distribuito.

```
Vettori possibili:
  1. Compromissione del repository Git
  2. Compromissione del build server
  3. Compromissione dei maintainer (social engineering, coercizione)
  4. Compromissione del canale di distribuzione (mirror, CDN)
  5. Inserimento di dipendenze malevole (dependency confusion)
```

### Contromisure

```
1. Reproducible builds:
   - Tor Browser supporta build riproducibili
   - Chiunque può ricompilare il codice sorgente
   - Il binario risultante deve essere identico bit-per-bit
   - Se non corrisponde → il build è stato compromesso

2. Firme GPG:
   - Tutti i download sono firmati con le chiavi del Tor Project
   - Le chiavi sono pubblicate e verificabili
   - Il download manager di Tor Browser verifica la firma

3. Codice open source:
   - Il codice è pubblico e auditabile
   - Community di sviluppatori che revisiona i cambiamenti
   - Bug bounty program

4. Build process documentato:
   - Il processo di build è documentato pubblicamente
   - Usa container Docker per isolamento
   - Log di build verificabili
```

---

## 9. Attacchi al routing BGP (RAPTOR)

### Come funziona

```
Sun et al. (2015): "RAPTOR: Routing Attacks on Privacy in Tor"

L'avversario sfrutta il protocollo BGP per osservare traffico Tor:

Attacco 1 - BGP Hijacking:
  1. L'avversario annuncia rotte BGP più specifiche
     per il range IP di un Guard Tor
  2. Il traffico client→Guard viene rediretto attraverso
     l'AS dell'avversario (man-in-the-middle a livello di routing)
  3. L'avversario osserva il traffico in ingresso
  4. Combinato con osservazione lato uscita → correlazione

Attacco 2 - Asymmetric routing:
  1. I percorsi BGP sono spesso asimmetrici
     (A→B passa per AS diversi da B→A)
  2. L'avversario può osservare solo una direzione
  3. Ma anche una direzione è sufficiente per correlazione

Attacco 3 - BGP interception:
  1. L'avversario ridirige il traffico, lo osserva, e lo rilascia
  2. Il client non nota nulla (latenza leggermente aumentata)
  3. Attacco completamente passivo dalla prospettiva della vittima
```

### Efficacia

```
- >90% dei circuiti Tor vulnerabili a routing attacks
- Un singolo AS in posizione strategica può osservare
  una percentuale significativa del traffico Tor
- Non richiede il controllo di relay Tor
- Difficile da rilevare dal client
```

### Contromisure

```
- Guard persistente: riduce la finestra di vulnerabilità
  (l'avversario deve mantenere il BGP hijack per settimane)
- RPKI (Resource Public Key Infrastructure):
  - Firma crittografica delle rotte BGP
  - Previene BGP hijacking non autorizzato
  - Adozione in crescita ma non universale
- Monitoring BGP:
  - RIPE RIS, RouteViews monitorano le rotte BGP
  - Anomalie di routing possono essere rilevate
- Selezione relay basata su diversità AS:
  - Tor seleziona relay in AS diversi
  - Riduce la probabilità che un singolo AS osservi tutto il circuito
```

---

## 10. Sniper Attack

### Come funziona

```
Jansen et al. (2014): "The Sniper Attack"

L'avversario forza un relay Tor a esaurire la memoria (OOM kill):

1. L'avversario crea un circuito attraverso il relay vittima
2. Invia dati al relay ma NON legge la risposta
3. I dati si accumulano nei buffer del relay
4. Il relay esaurisce la memoria → crash o OOM kill
5. Se il relay è il Guard della vittima:
   → La vittima deve scegliere un nuovo Guard
   → Se il nuovo Guard è malevolo → compromissione

Costo per l'avversario: minimo (invia dati, non legge)
Costo per la vittima: crash del relay, perdita di circuiti
```

### Contromisure

```
- Flow control migliorato (SENDME cells):
  - I relay non inviano più dati di quanti il ricevente confermi
  - Previene l'accumulo infinito di dati nei buffer
  
- OOM handler:
  - Tor rileva l'esaurimento della memoria
  - Chiude i circuiti più problematici invece di crashare
  
- Circuit-level flow control (Prop #324):
  - Congestion control a livello di circuito
  - Previene che un singolo circuito monopolizzi le risorse
```

---

## 11. Attacchi agli Onion Services

### Vanguards

```
Problema:
  Un avversario che controlla l'HS Directory può osservare
  le richieste e correlare con i circuiti.
  DoS selettivo degli Introduction Points può rivelare
  la posizione dell'HS.

Soluzione - Vanguards (Tor 0.4.1+):
  L'HS usa relay "vanguard" persistenti per i circuiti
  verso gli Introduction Points:

  HS → [Layer 1 Vanguard] → [Layer 2 Vanguard] → [Introduction Point]
  
  - Layer 1: persiste per mesi (come un Guard)
  - Layer 2: persiste per giorni
  - L'avversario deve compromettere entrambi i livelli
  - Molto più difficile che compromettere un singolo relay

Vanguards-lite (Tor 0.4.7+):
  - Versione semplificata attivata di default
  - Protegge tutti gli onion services
  - Un solo livello di vanguard
```

### Onion Service Directory (HSDirs) Attack

```
L'avversario posiziona relay come HSDir per un dato .onion:

v2 (vulnerabile):
  - L'avversario calcola quali relay saranno HSDir per un .onion
  - Posiziona relay in quelle posizioni
  - Vede ogni richiesta per quel .onion
  → Enumerazione e surveillance possibili

v3 (mitigato):
  - Descriptor cifrati (HSDir non può leggere)
  - Blinded keys (HSDir non sa quale .onion)
  - Rotazione basata su time period
  → L'attacco è molto più difficile/costoso
```

---

## Matrice degli attacchi e contromisure

| Attacco | Avversario necessario | Contromisura Tor | Efficacia contromisura | Anno scoperta |
|---------|----------------------|-----------------|----------------------|--------------|
| Sybil | Risorse per ~100+ relay | Monitoring DA, family, /16 rule | Media | 2014 |
| Relay Early Tagging | Controllo di relay middle+exit | Counting RELAY_EARLY, conversione | Alta | 2014 |
| Correlazione end-to-end | Osservazione di ingresso+uscita | Padding (limitato) | Bassa | 2004 |
| Website Fingerprinting | Osservazione locale (ISP) | Circuit padding (in sviluppo) | Media | 2011 |
| HSDir Enumeration | Controllo di HSDir relay | v3 descriptor cifrati, rotazione | Alta | 2016 |
| DoS su relay | Bandwidth per DDoS | PoW, rate limiting | Media | 2021 |
| Browser exploit | 0-day nel browser | Aggiornamenti, Security Level | Media | 2013 |
| Supply chain | Accesso al build system | Reproducible builds, GPG | Alta | - |
| BGP routing | Controllo di AS/IXP | Guard persistente, diversità AS | Bassa | 2015 |
| Sniper attack | Circuito malevolo | Flow control, OOM handler | Alta | 2014 |
| HS enumeration | Relay HSDir | Onion Services v3 | Alta | 2016 |

---

## Cronologia delle contromisure Tor

```
2012  Guard persistente (riduce esposizione a relay malevoli)
2014  Counting RELAY_EARLY (anti-tagging)
2014  Rimozione relay CMU/FBI
2015  Miglioramento selezione Guard (path bias tracking)
2017  Onion Services v3 (descriptor cifrati, blinded keys)
2018  Connection padding (celle dummy tra relay)
2019  Vanguards per onion services
2020  Circuit padding framework
2021  Rimozione relay KAX17
2021  Vanguards-lite (default per tutti gli HS)
2022  Congestion control (Prop #324)
2023  Proof-of-Work per onion services (anti-DoS)
2024  Continuazione rimozione relay malevoli
```

---

## Conclusione pratica

Nessun sistema è invulnerabile. Tor offre protezione significativa contro la
sorveglianza di massa e gli avversari locali, ma ha limiti documentati contro
avversari con risorse significative.

### Per il mio caso d'uso

Per privacy dall'ISP e test di sicurezza, le protezioni di Tor sono più che
sufficienti. L'avversario più probabile (ISP, tracker web) non ha le risorse
per gli attacchi descritti sopra.

### Per scenari ad alto rischio

Per giornalismo in regimi autoritari, whistleblowing, o attivismo, le
contromisure aggiuntive sono necessarie:
- Tails o Whonix (protezione da exploit del browser)
- OPSEC rigoroso (la tecnologia non compensa errori umani)
- Tor Browser a livello Safest (no JavaScript)
- Bridge obfs4 o Snowflake (nascondere uso di Tor)
- Aggiornamenti immediati (patch di sicurezza)

La lezione più importante dalla storia degli attacchi: **nella maggioranza dei
casi, la deanonimizzazione avviene per errori OPSEC, non per vulnerabilità
tecniche di Tor**.

---

## Vedi anche

- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - Correlazione end-to-end, website fingerprinting
- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Errori umani che causano deanonimizzazione
- [Limitazioni del Protocollo](limitazioni-protocollo.md) - Limiti architetturali di Tor
- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) - Protezioni v3 contro HSDir attacks
- [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) - Selezione persistente come difesa
- [Bridges e Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Difesa da censura e DPI
- [Isolamento e Compartimentazione](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Whonix/Tails come difesa da exploit
