# Bridges e obfs4

Questo documento spiega cosa sono i **Bridge Tor**, come funzionano i
trasporti pluggable (in particolare **obfs4**), come configurarli e contiene
anche note basate sulla mia esperienza reale nel richiedere bridge,
configurarli e usarli in situazioni con potenziale censura o blocchi ISP.

---

## Perché esistono i Bridge?

I Bridge sono nodi Tor *non pubblicamente elencati* nel consenso.
Questo significa che:

- non compaiono nella lista pubblica dei relay Tor,
- un ISP o un governo non può bloccarli facilmente,
- sono utili quando Tor normale è bloccato, filtrato o rallentato,
- sono spesso necessari in paesi ad alta censura o con DPI aggressivo.

In varie occasioni i bridge sono utili anche in contesti non censurati, ad esempio quando:

- l’ISP interferisce con Tor,
- si vuole nascondere il fatto stesso di usare Tor,
- alcuni relay entry pubblici risultano inaffidabili.

---

## Come ottenere i Bridge (dalla mia esperienza)

Ci sono tre metodi principali:

### **1. Dal sito ufficiale**
Il sito è: `https://bridges.torproject.org/options`

Nella mia esperienza:

- il sito è a volte lento a rispondere,
- alcune richieste restituiscono bridge già molto utilizzati,
- in contesti con filtraggio DNS il dominio può essere bloccato.

### **2. Via email**
Inviando un'email (da Gmail o Riseup): `tor@torproject.org`
contenente: get transport obfs4


✦ È un metodo affidabile ma non immediato.  
✦ Alcuni provider filtrano gli allegati contenenti stringhe sospette.

### **3. Snowflake**
Non è un bridge obfs4 normale: usa volontari browser-side.  
Nella mia esperienza non è sempre stabile e può oscillare molto in banda.

---

## Cosa sono i Pluggable Transports?

Sono metodi per rendere il traffico Tor **difficile da identificare**.

Gli ISP possono riconoscere Tor tramite:

- fingerprint TLS dei relay,
- pattern di pacchetti,
- analisi statistica.

I Pluggable Transports “offuscano” il traffico Tor in qualcosa che sembra:

- traffico casuale,
- traffico innocuo,
- o completamente indistinguibile da rumore.

---

## obfs4: il trasporto migliore (e perché lo uso)

**obfs4** è il trasporto più utilizzato e raccomandato oggi.

### Caratteristiche principali

- Resiste al **DPI** (Deep Packet Inspection)
- Genera traffico **completamente indistinguibile dal rumore**
- È resistente alla censura attiva:  
  un censore non può “provare” a connettersi al bridge e verificare che sia Tor
- Supporta l’opzione **iat-mode**, utile per rendere più casuale il timing

### Vantaggi basati sulla mia esperienza:

- sempre funzionato anche in reti universitarie con firewall pesante,
- non rilevato da hotspot pubblici che bloccavano Tor diretto,
- molto stabile e veloce se il bridge è recente e non sovraccarico.

### Svantaggi:

- richiede configurazione extra nel `torrc`,
- i bridge possono diventare saturi nel tempo,
- richiede l’eseguibile `obfs4proxy`.

---

## Configurazione dei Bridge obfs4

### Prerequisito: installare il trasporto

Su Debian/Ubuntu:

```bash
sudo apt install obfs4proxy
```

# verifica funzionamento bridge
```bash
> sudo journalctl -u tor -f
Bootstrapped 10% (conn): Connecting to a relay
...
Bootstrapped 75% (enough_dirinfo): Loaded enough directory info to build circuits
...
Bootstrapped 100% (done): Done

# se tor non riesce a collegarsi restituisce:
# Connection timed out to bridge


```