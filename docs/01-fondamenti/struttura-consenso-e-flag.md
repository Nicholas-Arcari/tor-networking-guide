> **Lingua / Language**: Italiano | [English](../en/01-fondamenti/struttura-consenso-e-flag.md)

# Struttura del Consenso, Flag e Bandwidth Authorities

Il documento di consenso, i flag assegnati ai relay, e il sistema
di misurazione della banda che previene attacchi di amplificazione.

Estratto da [Consenso e Directory Authorities](consenso-e-directory-authorities.md).

---

## Indice

- [Struttura del documento di consenso](#struttura-del-documento-di-consenso)
- [Flag del consenso - Analisi approfondita](#flag-del-consenso--analisi-approfondita)
- [Bandwidth Authorities e misurazione della banda](#bandwidth-authorities-e-misurazione-della-banda)

---

## Struttura del documento di consenso

Il consenso è un documento di testo di circa 2-3 MB. Ecco la sua struttura semplificata:

### Header

```
network-status-version 3
vote-status consensus
consensus-method 32
valid-after 2025-01-15 12:00:00
fresh-until 2025-01-15 13:00:00
valid-until 2025-01-15 15:00:00
voting-delay 300 300
...
```

- `valid-after`: quando il consenso diventa valido
- `fresh-until`: entro quando il client dovrebbe cercare un consenso più recente
- `valid-until`: dopo questa data il consenso è considerato scaduto
- `voting-delay`: tempo per upload dei voti e per il calcolo

### Sezione delle DA

```
dir-source moria1 ...
contact Roger Dingledine
vote-digest ABCDEF1234...
...
```

### Sezione dei relay (il cuore del consenso)

Per ogni relay:

```
r ExitRelay1 ABCDef123 2025-01-15 11:45:33 198.51.100.42 9001 0
s Exit Fast Guard HSDir Running Stable V2Dir Valid
w Bandwidth=15000
p accept 20-23,43,53,79-81,88,110,143,194,220,389,443,464-465,531,543-544,554,563,587,636,706,749,853,873,902-904,981,989-995,1194,1220,1293,1500,1533,1677,1723,1755,1863,2082-2083,2086-2087,2095-2096,2102-2104,3128,3389,3690,4321,4443,5050,5190,5222-5223,5228,5900,6660-6669,6679,6697,8000-8003,8080,8332-8333,8443,8888,9418,11371,19294,19638
```

Spiegazione riga per riga:

- **r** (router): nickname, fingerprint (base64), data pubblicazione, IP, ORPort, DirPort
- **s** (status flags): i flag assegnati dal consenso
- **w** (weight): bandwidth in KB/s (pesata e misurata)
- **p** (exit policy summary): versione compressa dell'exit policy

### Sezione delle firme

```
directory-signature sha256 FINGERPRINT_DA
-----BEGIN SIGNATURE-----
...
-----END SIGNATURE-----
```

---

## Flag del consenso - Analisi approfondita

I flag determinano come il client usa ogni relay. La loro assegnazione è critica per
la sicurezza della rete.

### Flag `Guard`

**Requisiti**: il relay deve essere:
- `Stable` (uptime sopra la mediana dei relay Stable-eligible)
- `Fast` (bandwidth sopra la mediana)
- In funzione da almeno 8 giorni
- Con bandwidth sufficiente (almeno la mediana o almeno 2 MB/s)

**Implicazione**: solo i relay con flag Guard possono essere scelti come entry node
dal client. Questo limita il pool di entry a relay affidabili e ad alta bandwidth,
riducendo il rischio che un relay malevolo venga scelto come guard.

### Flag `Exit`

**Requisiti**: la exit policy del relay permette connessioni verso almeno porta 80 e 443
di almeno 2 indirizzi /8.

**Implicazione**: solo i relay con flag Exit vengono considerati per l'ultimo hop.
Un relay senza flag Exit ma con una exit policy parziale non viene selezionato come
exit dal client (ma potrebbe comunque funzionare se forzato).

### Flag `Stable`

**Requisiti**: MTBF (Mean Time Between Failures) sopra la mediana dei relay con uptime > 1 giorno, OPPURE sopra 7 giorni.

**Implicazione**: usato per circuiti che richiedono connessioni lunghe (SSH, IRC, etc.).
Tor seleziona relay Stable per stream su porte note per connessioni persistenti.

### Flag `Fast`

**Requisiti**: bandwidth misurata sopra la mediana dei relay attivi, O almeno 100 KB/s.

**Implicazione**: aumenta la probabilità di selezione per quel relay (più banda → più
traffico instradato).

### Flag `HSDir`

**Requisiti**: il relay supporta il protocollo directory per hidden services.

**Implicazione**: può memorizzare e servire descriptor di hidden services (.onion).
Importante per la raggiungibilità degli onion services.

### Flag `BadExit`

**Requisiti**: assegnato manualmente dalle DA quando un exit node è stato identificato
come malevolo (sniffing, injection, MITM).

**Implicazione**: il client **non seleziona** mai un relay con flag BadExit come exit
node. Può ancora essere usato come middle.

### Nella mia esperienza

Non ho mai dovuto interagire direttamente con i flag, ma li vedo quando uso Nyx o
quando ispeziono i circuiti via ControlPort. Sapere che il mio guard ha il flag `Guard`
e `Stable` mi dà più fiducia nella stabilità dei circuiti.

---

## Bandwidth Authorities e misurazione della banda

### Il problema della bandwidth autodichiarata

Ogni relay può dichiarare qualsiasi valore di bandwidth nel proprio descriptor. Un
relay malevolo potrebbe dichiarare 100 MB/s quando ne ha 1 MB/s, per attrarre più
traffico e aumentare le probabilità di essere selezionato.

### La soluzione: bandwidth authorities

Un sottoinsieme delle DA esegue misurazioni di bandwidth indipendenti usando il
software **sbws** (Simple Bandwidth Scanner):

1. **sbws** si connette a ogni relay e misura la banda reale
2. Genera un file di voto con le bandwidth misurate
3. Durante la votazione, le bandwidth misurate sovrascrivono quelle autodichiarate
4. Il consenso contiene la bandwidth misurata, non quella dichiarata

### Bandwidth weights nel consenso

Il consenso include anche i **bandwidth weights** - coefficienti globali che determinano
come distribuire il traffico tra guard, middle, exit:

```
bandwidth-weights Wbd=0 Wbe=0 Wbg=4203 Wbm=10000 Wdb=10000 Web=10000 Wed=10000
Weg=10000 Wem=10000 Wgb=10000 Wgd=0 Wgg=5797 Wgm=5797 Wmb=10000 Wmd=10000
Wme=10000 Wmg=4203 Wmm=10000
```

Questi pesi servono per bilanciare il traffico: se ci sono pochi exit rispetto ai
guard, i pesi vengono aggiustati per mandare più traffico attraverso gli exit
disponibili.

---


---

## Vedi anche

- [Consenso e Directory Authorities](consenso-e-directory-authorities.md) - Perché il consenso, DAs, votazione
- [Descriptor, Cache e Attacchi](descriptor-cache-e-attacchi.md) - Server descriptor, cache, attacchi al consenso
- [Architettura di Tor](architettura-tor.md) - Componenti e panoramica
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
