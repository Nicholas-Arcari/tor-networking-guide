# Middle Relay — Il Nodo Invisibile

Questo documento analizza il ruolo dei Middle Relay nel circuito Tor, l'algoritmo di
selezione, il peso della bandwidth, e perché i middle node sono fondamentali per
l'anonimato nonostante siano il componente meno "visibile" dell'architettura.

---
---

## Indice

- [Ruolo del Middle Relay](#ruolo-del-middle-relay)
- [Algoritmo di selezione dei Middle Relay](#algoritmo-di-selezione-dei-middle-relay)
- [Bandwidth Weights e bilanciamento](#bandwidth-weights-e-bilanciamento)
- [Middle Relay nei circuiti estesi](#middle-relay-nei-circuiti-estesi)
- [Attacchi che coinvolgono i Middle Relay](#attacchi-che-coinvolgono-i-middle-relay)
- [Contribuire come Middle Relay](#contribuire-come-middle-relay)
- [Riepilogo](#riepilogo)


## Ruolo del Middle Relay

Il Middle Relay è il **secondo nodo** del circuito Tor standard a 3 hop:

```
[Tu] ──► [Guard] ──► [Middle] ──► [Exit] ──► [Internet]
```

### Cosa conosce il Middle

| Informazione | Visibile al Middle? |
|-------------|-------------------|
| Il tuo IP reale | **NO** — vede solo l'IP del Guard |
| La destinazione finale | **NO** — vede solo l'IP dell'Exit |
| Il contenuto del traffico | **NO** — vede celle cifrate con 2 strati |
| Il volume di traffico | **SI** — vede il numero di celle che transitano |
| Il timing del traffico | **SI** — vede quando le celle transitano |
| L'identità del Guard | **SI** — è la connessione TLS diretta |
| L'identità dell'Exit | **SI** — è la connessione TLS diretta |

### La funzione di separazione

Il Middle Relay esiste per **separare** il Guard dall'Exit. Senza il middle:

```
Circuito a 2 hop (INSICURO):
[Tu] ──► [Guard+Exit] ──► [Internet]
Il Guard conosce sia te che la destinazione → nessun anonimato
```

Con il middle:
```
Circuito a 3 hop:
[Tu] ──► [Guard] ──► [Middle] ──► [Exit] ──► [Internet]
Guard conosce te ma non la destinazione
Exit conosce la destinazione ma non te
Middle non conosce nessuno dei due
```

Il middle impedisce al Guard di correlare il tuo traffico con la destinazione,
e all'Exit di risalire a te.

---

## Algoritmo di selezione dei Middle Relay

### Selezione pesata per bandwidth

Il middle viene scelto dal consenso con probabilità proporzionale alla **bandwidth
misurata** del relay. Un relay con 10 MB/s di bandwidth ha 10 volte la probabilità
di essere selezionato rispetto a un relay con 1 MB/s.

Formula semplificata:
```
P(relay_i come middle) = BW_i * Wmm / Σ(BW_j * Wmj per tutti i relay j eleggibili)
```

Dove:
- `BW_i` = bandwidth del relay i nel consenso
- `Wmm` = bandwidth weight per middle relay (dal consenso)

### Vincoli di selezione

Tor applica vincoli per evitare che il circuito sia compromesso:

1. **Non nella stessa famiglia**: se il Guard e il candidato middle hanno dichiarato
   `MyFamily` comune, il candidato viene escluso.

2. **Non nella stessa /16 subnet**: se il Guard è in `198.51.100.0/16` e il candidato
   middle è in `198.51.200.0/16`, viene escluso. Questo riduce il rischio che entrambi
   siano nello stesso datacenter/ISP.

3. **Non lo stesso relay**: ovviamente, il middle non può essere lo stesso relay
   del guard o dell'exit.

4. **Nessun flag richiesto**: a differenza di guard ed exit, un middle relay non
   necessita di flag specifici. Qualsiasi relay `Running` e `Valid` può essere middle.

### Perché i middle non hanno flag dedicato

I guard hanno il flag `Guard` (richiede stabilità). Gli exit hanno il flag `Exit`
(richiede exit policy). I middle non hanno requisiti speciali perché:

- La loro funzione è puro transito — non servono proprietà particolari
- Avere un pool ampio di middle migliora l'anonimato (più relay possibili)
- La selezione pesata per bandwidth bilancia automaticamente il carico

---

## Bandwidth Weights e bilanciamento

### Il problema del bilanciamento

La rete Tor ha proporzioni sbilanciate di guard, middle ed exit:
- **Guard**: ~40% dei relay con flag Guard
- **Exit**: ~15-20% dei relay con flag Exit (gli exit sono pochi perché richiedono
  una exit policy permissiva, che espone l'operatore a rischi legali)
- **Middle**: tutti i relay

Se la selezione fosse puramente proporzionale alla bandwidth, gli exit sarebbero
sovraccarichi (pochi relay, molto traffico). I **bandwidth weights** nel consenso
risolvono questo:

```
bandwidth-weights Wbd=0 Wbe=0 Wbg=4203 Wbm=10000 Wdb=10000 Web=10000 
Wed=10000 Weg=10000 Wem=10000 Wgb=10000 Wgd=0 Wgg=5797 Wgm=5797 
Wmb=10000 Wmd=10000 Wme=10000 Wmg=4203 Wmm=10000
```

### Significato dei pesi

- `Wgg=5797` → un relay con flag Guard viene selezionato come guard con peso 5797/10000
- `Wmg=4203` → un relay con flag Guard viene selezionato come middle con peso 4203/10000
- `Wmm=10000` → un relay senza flag Guard/Exit viene selezionato come middle con peso pieno

Questo significa che i relay con flag Guard vengono usati anche come middle (ma con
peso ridotto), per bilanciare il carico. Analogamente, i relay Exit possono essere
usati come middle.

### Implicazione pratica

Il relay che funge da middle nel tuo circuito potrebbe essere:
- Un relay "puro" senza flag particolari
- Un relay con flag Guard (ma selezionato come middle per questa volta)
- Un relay con flag Exit (ma selezionato come middle per questa volta)

---

## Middle Relay nei circuiti estesi

### Circuiti a 3 hop (standard)

Per traffico internet normale, il circuito è sempre a 3 hop: guard → middle → exit.
Un solo middle relay.

### Circuiti per Hidden Services (fino a 6 hop)

Quando un client si connette a un onion service, i circuiti sono più lunghi:

```
Client → Guard → Middle → Rendezvous Point
                                   ↕
Hidden Service → Guard → Middle → Rendezvous Point
```

In questo caso ci sono **due middle relay** (uno per il circuito del client, uno per
quello dell'hidden service), più il rendezvous point (che è anch'esso un relay).

### Circuiti con Vanguards

Con vanguards attivi, i "middle" diventano più strutturati:

```
Client → Guard (L1) → Middle L2 → Middle L3 → Exit/RP
```

I middle L2 e L3 hanno tempi di rotazione diversi, aggiungendo complessità per chi
tenta di correlare il traffico.

---

## Attacchi che coinvolgono i Middle Relay

### 1. Attacco di correlazione tramite middle controllato

Se l'avversario controlla sia il middle che osserva il traffico tra guard e middle
e tra middle ed exit, può correlare i pattern temporali per collegare client e
destinazione.

**Mitigazione**: il volume di traffico multiplexato su ogni connessione TLS rende
la correlazione per-circuito molto difficile (centinaia di circuiti sulla stessa
connessione).

### 2. Middle come sniffing point

Un middle malevolo potrebbe provare a:
- Contare le celle per stimare il volume di traffico
- Misurare la latenza verso guard ed exit
- Raccogliere metadata statistici

Ma **non può** decifrare il contenuto (cifrato con 2 strati di AES-128-CTR che non
possiede).

### 3. Relay early tagging attack

Storicamente (prima di Tor 0.2.4.23), un middle relay poteva inviare celle `RELAY_EARLY`
contraffatte per "taggare" un circuito. L'exit malevolo poteva riconoscere il tag e
confermare che un certo client stava usando quel circuito.

Questo attacco è stato usato nel 2014 per deanonimizzare utenti di hidden services.
Da allora:
- Le celle RELAY_EARLY sono contate e limitate
- I relay che inviano RELAY_EARLY anomali vengono segnalati
- Il client verifica la consistenza delle celle

---

## Contribuire come Middle Relay

Operare un middle relay è il modo più sicuro per contribuire alla rete Tor:

- **Nessun rischio legale**: il traffico che transita è sempre cifrato. Non puoi vedere
  né essere responsabile del contenuto.
- **Requisiti hardware minimi**: anche un VPS economico può essere un middle relay utile.
- **Aiuta la rete**: più middle relay = più diversità = più anonimato per tutti.

### Configurazione minima per un middle relay

```ini
# torrc per middle relay (non exit)
ORPort 9001
Nickname MyMiddleRelay
ContactInfo email@example.com
ExitPolicy reject *:*           # NON essere un exit
RelayBandwidthRate 1 MB
RelayBandwidthBurst 2 MB
```

Non ho attivato un relay nella mia configurazione perché uso Tor come client, ma è
una possibilità interessante per contribuire alla rete.

---

## Riepilogo

| Proprietà | Guard | Middle | Exit |
|-----------|-------|--------|------|
| Conosce il tuo IP | SI | NO | NO |
| Conosce la destinazione | NO | NO | SI |
| Vede il contenuto | NO | NO | Solo se non HTTPS |
| Flag richiesto | Guard | Nessuno | Exit |
| Persistenza | Mesi | Nessuna (cambia ogni circuito) | Nessuna |
| Pool di candidati | ~1500 | ~6000+ | ~1000-1500 |
| Rischio per l'operatore | Basso | Minimo | Alto (possibili abusi) |

---

## Vedi anche

- [Guard Nodes](guard-nodes.md) — Primo hop del circuito
- [Exit Nodes](exit-nodes.md) — Terzo hop del circuito
- [Consenso e Directory Authorities](../01-fondamenti/consenso-e-directory-authorities.md) — Bandwidth weights e selezione
- [Relay Monitoring e Metriche](relay-monitoring-e-metriche.md) — Monitorare il proprio middle relay
- [Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md) — Relay early tagging dal middle
