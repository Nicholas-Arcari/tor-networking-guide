# Guard Nodes - Il Primo Anello della Catena

Questo documento analizza in profondità il ruolo, la selezione, la persistenza e i
rischi dei Guard Node (Entry Node) nella rete Tor. I guard sono il componente più
critico del circuito dal punto di vista della sicurezza dell'utente, perché sono
l'unico nodo che conosce il nostro IP reale.

Include osservazioni dalla mia esperienza con guard selection, cambio di guard dopo
reset, e impatto sulle prestazioni.

---
---

## Indice

- [Ruolo del Guard Node](#ruolo-del-guard-node)
- [Entry Guard: il meccanismo di persistenza](#entry-guard-il-meccanismo-di-persistenza)
- [Il file state e la persistenza dei Guard](#il-file-state-e-la-persistenza-dei-guard)
- [Requisiti per essere un Guard Node](#requisiti-per-essere-un-guard-node)
- [Path Bias Detection](#path-bias-detection)
- [Vanguards - Protezione avanzata per Hidden Services](#vanguards-protezione-avanzata-per-hidden-services)
- [Attacchi specifici ai Guard Nodes](#attacchi-specifici-ai-guard-nodes)
- [Impatto dei Guard sulla performance](#impatto-dei-guard-sulla-performance)


## Ruolo del Guard Node

Il Guard Node è il **primo nodo** del circuito Tor:

```
[Tu: IP reale] ──TLS──► [Guard Node] ──TLS──► [Middle] ──TLS──► [Exit] ──► Internet
```

### Cosa conosce il Guard

| Informazione | Visibile al Guard? |
|-------------|-------------------|
| Il tuo IP reale | **SI** - è la connessione TCP diretta |
| La tua posizione geografica | **SI** - derivabile dall'IP |
| Il tuo ISP | **SI** - derivabile dall'IP |
| Quando ti connetti | **SI** - vede il timing della connessione |
| Quanti dati invii | **SI** - vede il volume di traffico |
| La destinazione finale | **NO** - vede solo l'IP del Middle |
| Il contenuto del traffico | **NO** - vede solo celle cifrate |

### Perché il Guard è critico

Se un avversario controlla il Guard Node che stai usando, conosce:
- Chi sei (il tuo IP)
- Quando usi Tor
- Il volume di traffico

Se lo stesso avversario controlla **anche** l'Exit Node del tuo circuito, può
correlare il timing del traffico in ingresso e in uscita per deanonimizzarti
(**attacco di correlazione end-to-end**). Per questo la selezione dei guard è
progettata per minimizzare questo rischio.

---

## Entry Guard: il meccanismo di persistenza

### Il problema della selezione casuale

Nelle prime versioni di Tor, il primo nodo veniva scelto casualmente per ogni
circuito. Questo aveva un problema fatale:

- Supponiamo che un avversario controlli il 5% dei relay
- Ogni nuovo circuito ha il 5% di probabilità di usare un relay malevolo come entry
- In 14 circuiti, la probabilità di almeno uno con entry malevolo è ~50%
- In un giorno, un utente attivo costruisce centinaia di circuiti
- **Prima o poi**, l'avversario diventa il tuo entry node

### La soluzione: Entry Guard persistenti

A partire da Tor 0.2.4, il client seleziona un piccolo numero di guard e li
riutilizza per un periodo esteso (mesi):

- Se il guard è "buono" (non controllato dall'avversario), sei protetto per mesi
- Se il guard è "malevolo", sei esposto - ma il rischio è una tantum, non
  cumulativo nel tempo
- Con 1 guard, hai ~probabilità_avversario di esposizione, non 1-(1-p)^n

**Il principio**: è meglio avere un piccolo rischio costante che un rischio
cumulativo crescente.

### Parametri attuali (Tor 0.4.x)

| Parametro | Valore | Significato |
|-----------|--------|-------------|
| `NumEntryGuards` | 1 | Un solo guard primario |
| Guard rotation period | ~2-3 mesi | Dopo questo periodo, un nuovo guard viene scelto |
| Sampling period | 27 giorni | Periodo per campionare guard candidati |
| Numero di guard nel "sample" | ~20 | Pool di guard candidati |

### Come funziona la selezione

1. **Campionamento**: Tor crea un "sampled set" di ~20 guard dal consenso. Questi
   sono relay con flag `Guard` + `Stable` + `Fast`.

2. **Selezione primaria**: dal sampled set, 1 guard viene selezionato come primario.
   La selezione è pesata per bandwidth.

3. **Utilizzo**: tutti i circuiti usano questo guard. Se il guard diventa
   irraggiungibile, Tor prova i guard "di riserva" nel sampled set.

4. **Rotazione**: dopo il periodo di rotazione (~2-3 mesi), il guard primario viene
   sostituito. Il nuovo guard viene scelto dal sampled set (che viene anch'esso
   aggiornato periodicamente).

---

## Il file state e la persistenza dei Guard

I guard selezionati sono salvati nel file `/var/lib/tor/state`:

```
Guard in 2025-01-15 12:00:00 name=MyGuard id=FINGERPRINT
GuardReachable=1
GuardConfirmedIdx=0
GuardLastSampled 2025-01-01 00:00:00
GuardAddedBy 0.4.8.10 2025-01-01 00:00:00
GuardPathBias 500 0 0 0 500 0
```

### Campi importanti

- **GuardReachable**: 1 se il guard è attualmente raggiungibile
- **GuardConfirmedIdx**: posizione nell'ordine di preferenza
- **GuardLastSampled**: quando il guard è stato aggiunto al campione
- **GuardPathBias**: contatori per path bias detection

### Conseguenze pratiche

- **Reinstallazione di Tor**: se cancelli `/var/lib/tor/state`, Tor seleziona nuovi
  guard. Questo **riduce temporaneamente la sicurezza** perché perdi guard che hanno
  dimostrato di essere affidabili.

- **Migrazione di sistema**: se sposti la configurazione Tor su un altro sistema,
  copia anche `/var/lib/tor/state` per mantenere i guard.

- **Sospetto di guard compromesso**: se hai motivo di credere che il tuo guard sia
  controllato da un avversario, cancellare `state` è giustificato.

### Nella mia esperienza

Dopo aver configurato Tor per la prima volta, ho resettato `/var/lib/tor/state`
diverse volte durante le fasi di testing e configurazione. In produzione, non
tocco mai il file state. Ho osservato che il mio guard cambia approssimativamente
ogni 2-3 mesi guardando i log:

```bash
sudo journalctl -u tor@default.service | grep "guard"
```

---

## Requisiti per essere un Guard Node

Non tutti i relay possono diventare guard. Le Directory Authorities assegnano il
flag `Guard` solo a relay che soddisfano:

1. **Flag `Stable`**: MTBF (Mean Time Between Failures) superiore alla mediana
   della rete, o almeno 7 giorni

2. **Flag `Fast`**: bandwidth superiore alla mediana o almeno 100 KB/s

3. **Uptime minimo**: almeno 8 giorni di funzionamento continuo

4. **Bandwidth minima**: almeno la mediana della rete o almeno 2 MB/s

5. **Raggiungibilità**: verificata dalle DA con probe periodici

### Perché questi requisiti?

- **Stabilità**: un guard che va offline frequentemente forza il client a usare
  guard di riserva, aumentando l'esposizione
- **Bandwidth**: un guard lento diventa un collo di bottiglia per tutto il traffico
  dell'utente
- **Uptime**: un relay appena apparso non ha abbastanza storia per essere fidato

### Implicazione per la sicurezza

I requisiti stringenti significano che:
- È costoso per un avversario mantenere guard malevoli (servono server stabili, veloci,
  con uptime alto)
- Il pool di guard è relativamente piccolo (~1000-2000 relay su ~7000 totali)
- Questo rende la selezione casuale pesata per bandwidth ragionevolmente sicura

---

## Path Bias Detection

Tor monitora il successo dei circuiti per ogni guard per rilevare guard malevoli:

### Come funziona

Per ogni guard, Tor tiene traccia di:
- Quanti circuiti sono stati tentati
- Quanti sono stati costruiti con successo
- Quanti sono stati usati con successo
- Quanti hanno fallito in modo sospetto

Se il tasso di fallimento è anomalo, Tor sospetta che il guard stia interferendo:

```
[warn] Your guard FINGERPRINT is failing an extremely high fraction of circuits.
If this persists, Tor will stop using it.
```

### Soglie

| Metrica | Soglia warn | Soglia extreme |
|---------|------------|---------------|
| Circuiti falliti | > 30% | > 70% |
| Circuiti col collapse | > 30% | > 70% |

Se la soglia "extreme" viene superata, Tor marca il guard come inutilizzabile e
ne seleziona un altro.

### Cosa può indicare

- **Guard malevolo**: interferisce selettivamente con i circuiti
- **Guard sovraccarico**: non riesce a gestire il traffico
- **Problema di rete**: la connessione al guard è instabile

---

## Vanguards - Protezione avanzata per Hidden Services

Per gli onion services (hidden services), i guard sono ancora più critici perché un
avversario potrebbe provare a enumerare i guard per deanonimizzare il server.

### Il problema

Un avversario che controlla alcuni relay nella rete Tor potrebbe:
1. Connettersi ripetutamente all'onion service
2. Osservare quale guard viene usato dall'onion service
3. Con abbastanza osservazioni, restringere il candidato a pochi guard
4. Correlare il guard con un IP

### La soluzione: Vanguards

Vanguards aggiunge strati di protezione:

- **Layer 1 guards** (guard veri): ruotano lentamente (mesi)
- **Layer 2 guards** (middle persistenti): ruotano moderatamente (giorni)
- **Layer 3 guards** (middle variabili): ruotano spesso (ore)

Il circuito di un onion service con vanguards è:
```
HS → Layer1 Guard → Layer2 Middle → Layer3 Middle → ... → Client
```

Questo impedisce all'avversario di avvicinarsi al guard reale dell'onion service
osservando solo i relay nel circuito.

### Attivazione

Dalla versione 0.4.7+, vanguards è integrato in Tor:
```ini
# Nel torrc (per onion services)
VanguardsEnabled 1
```

---

## Attacchi specifici ai Guard Nodes

### 1. Guard Discovery Attack

**Scenario**: l'avversario vuole scoprire quale guard usa un utente specifico.

**Metodo**: se l'avversario controlla un Exit Node e può forzare l'utente a
riconnettersi (es. causando errori), osserva il primo hop del circuito.
Ripetendo molte volte, conferma che l'utente usa sempre lo stesso guard.

**Mitigazione**: l'utente usa 1 solo guard per mesi. L'avversario scopre il guard,
ma questo non rivela direttamente l'IP dell'utente (a meno che non controlli
anche il guard stesso).

### 2. Guard Enumeration (per Hidden Services)

**Scenario**: l'avversario vuole scoprire tutti i guard di un onion service.

**Metodo**: l'avversario gestisce relay middle/exit e monitora le connessioni
verso l'onion service per settimane/mesi, registrando il first hop.

**Mitigazione**: Vanguards (vedi sopra).

### 3. Denial of Service per forzare cambio guard

**Scenario**: l'avversario DDoS-a il guard dell'utente per forzarlo a selezionarne
uno nuovo (potenzialmente controllato dall'avversario).

**Metodo**: flood di traffico verso il guard → il guard diventa irraggiungibile →
l'utente passa a un guard di riserva.

**Mitigazione**: Tor non abbandona un guard immediatamente. Ci sono retry e timeout
progressivi. Inoltre, il nuovo guard viene scelto dal sampled set esistente, che è
stato selezionato in un momento precedente (non al momento dell'attacco).

---

## Impatto dei Guard sulla performance

Il guard è il collo di bottiglia del circuito. La sua bandwidth e latenza influenzano
direttamente le prestazioni di tutte le connessioni Tor.

### Nella mia esperienza

Ho notato che dopo certi rinnovi del guard, le prestazioni cambiano significativamente:

```bash
# Test velocità con guard vecchio
> time proxychains curl -s https://api.ipify.org
185.220.101.143
real    0m2.342s

# Dopo rotazione guard (più lento)
> time proxychains curl -s https://api.ipify.org  
104.244.76.13
real    0m5.891s
```

La differenza è dovuta alla bandwidth e latenza del nuovo guard. Non c'è molto da
fare: aspettare la prossima rotazione o resettare lo state (sconsigliato per ragioni
di sicurezza).

### Guard e bridge

Quando uso bridge obfs4, il bridge funge da guard. Questo significa che:
- La bandwidth del bridge diventa il collo di bottiglia
- La latenza aggiuntiva di obfs4 si aggiunge a quella del circuito
- I bridge sono spesso meno performanti dei guard normali (meno bandwidth, più carico)

Nei miei test:
- Guard diretto: ~2-4 secondi per una richiesta HTTPS
- Bridge obfs4: ~4-8 secondi per la stessa richiesta

Il trade-off è chiaro: maggiore privacy (nascondere l'uso di Tor all'ISP) vs.
prestazioni peggiori.

---

## Vedi anche

- [Middle Relay](middle-relay.md) - Secondo hop del circuito
- [Exit Nodes](exit-nodes.md) - Terzo hop e uscita dalla rete
- [Architettura di Tor](../01-fondamenti/architettura-tor.md) - Ruolo del Guard nell'architettura
- [Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md) - Attacchi ai Guard (Sybil, correlazione)
- [Onion Services v3](onion-services-v3.md) - Vanguards come Guard persistenti per HS
