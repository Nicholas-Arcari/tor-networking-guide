> **Lingua / Language**: Italiano | [English](../en/08-aspetti-legali-ed-etici/aspetti-legali.md)

# Aspetti Legali dell'Uso di Tor - Italia e UE

Questo documento analizza il quadro legale dell'uso di Tor in Italia e nell'Unione
Europea: cosa è legale, cosa non lo è, precedenti giuridici rilevanti, obblighi
degli ISP, responsabilità degli operatori relay, e le sfumature legali di bridge,
NEWNYM, accesso a siti esteri e data retention.

Basato sulla mia esperienza personale: mi sono informato sulla legalità prima di
iniziare a usare Tor, e ho confermato che in Italia l'uso di Tor è pienamente legale.

---

## Indice

- [In Italia: usare Tor è legale](#in-italia-usare-tor-è-legale)
- [Base giuridica dettagliata](#base-giuridica-dettagliata)
- [Cosa resta illegale (con o senza Tor)](#cosa-resta-illegale-con-o-senza-tor)
- [Sfumature legali specifiche](#sfumature-legali-specifiche)
- **Approfondimenti** (file dedicati)
  - [Relay, Data Retention e Confronto Internazionale](aspetti-legali-relay-e-confronto.md)

---

## In Italia: usare Tor è legale

### La posizione chiara

**L'uso di Tor è legale in Italia.** Non esiste nessuna legge che vieti:
- L'installazione e l'esecuzione del software Tor
- L'uso di bridge obfs4 per offuscare il traffico
- La rotazione dell'IP tramite NEWNYM
- L'uso di ProxyChains o torsocks
- La navigazione web tramite la rete Tor
- L'accesso a siti web di altri paesi tramite exit node esteri
- L'accesso a onion services (.onion)

### Cosa è legale fare con Tor - Tabella completa

| Attività | Legale? | Note |
|----------|---------|------|
| Installare Tor su qualsiasi sistema | SI | Software open source, licenza BSD |
| Navigare il web via Tor | SI | Diritto alla privacy |
| Usare bridge obfs4/meek/Snowflake | SI | Strumenti anti-censura |
| Cambiare IP con NEWNYM | SI | Equivalente a riconnessione ISP |
| Accedere a siti web di altri paesi | SI | Routing Internet normale |
| Usare ProxyChains / torsocks | SI | Strumenti di rete standard |
| Operare un relay Tor (middle/guard) | SI | Contribuzione a infrastruttura |
| Operare un exit node Tor | SI | Ma con rischi pratici significativi |
| Accedere a onion services (.onion) | SI | Non sono illegali per natura |
| Usare Tor per ricerca di sicurezza | SI | Pratica professionale riconosciuta |
| Usare Tor per OSINT | SI | Comune in cybersecurity |
| Gestire un bridge Tor | SI | Contribuzione anti-censura |
| Usare Tor in combinazione con VPN | SI | Configurazione di rete legittima |
| Fare test di penetrazione via Tor | SI | Con autorizzazione del target |

---

## Base giuridica dettagliata

### Costituzione Italiana

**Art. 15 - Segretezza della corrispondenza**:
> La libertà e la segretezza della corrispondenza e di ogni altra forma di
> comunicazione sono inviolabili. La loro limitazione può avvenire soltanto
> per atto motivato dell'autorità giudiziaria con le garanzie stabilite dalla legge.

Questo articolo protegge il diritto alla privacy delle comunicazioni.
L'uso di strumenti di anonimizzazione come Tor è coerente con questo diritto.

**Art. 21 - Libertà di espressione**:
> Tutti hanno diritto di manifestare liberamente il proprio pensiero con la parola,
> lo scritto e ogni altro mezzo di diffusione.

La libertà di espressione include il diritto di esprimersi in modo anonimo,
purché non si commettano reati.

### Codice Penale - Articoli rilevanti

**Art. 615-ter - Accesso abusivo a un sistema informatico**:
Punisce chi si introduce abusivamente in un sistema informatico protetto da
misure di sicurezza. L'uso di Tor non costituisce accesso abusivo: Tor è uno
strumento di trasporto, non di intrusione.

**Art. 617-quater - Intercettazione di comunicazioni informatiche**:
Punisce chi intercetta comunicazioni. L'uso di Tor per proteggere le proprie
comunicazioni è l'opposto: è una difesa contro l'intercettazione.

**Art. 640-ter - Frode informatica**:
Punisce chi altera il funzionamento di un sistema per procurarsi un vantaggio.
L'uso di Tor per navigare anonimamente non altera nessun sistema.

### Codice delle Comunicazioni Elettroniche (D.Lgs. 259/2003)

Non contiene alcuna disposizione che vieti l'uso di strumenti di anonimizzazione.
Regola le telecomunicazioni ma non impone obblighi di identificazione agli utenti
finali per la navigazione web.

### GDPR (Regolamento UE 2016/679)

Il GDPR riconosce esplicitamente:

**Art. 5 - Principio di minimizzazione dei dati**:
I dati personali devono essere "adeguati, pertinenti e limitati a quanto necessario".
L'uso di Tor è coerente con la minimizzazione: riduce i dati personali esposti.

**Art. 25 - Privacy by design e by default**:
Il GDPR incoraggia la protezione della privacy fin dalla progettazione.
Tor implementa privacy by design.

**Art. 32 - Sicurezza del trattamento**:
Richiede misure tecniche adeguate per proteggere i dati. La crittografia e
l'anonimizzazione sono espressamente menzionate come misure adeguate.

**Considerando 26**:
I dati anonimizzati non sono dati personali. Tor anonimizza il traffico di rete.

---

## Cosa resta illegale (con o senza Tor)

Tor non cambia la legge. Le attività illegali restano illegali indipendentemente
dal mezzo tecnico usato.

| Attività | Articolo c.p. | Legale senza Tor? | Legale con Tor? |
|----------|--------------|------------------|-----------------|
| Accesso non autorizzato a sistemi | Art. 615-ter | NO | NO |
| Distribuzione di malware | Art. 615-quinquies | NO | NO |
| Frode informatica | Art. 640-ter | NO | NO |
| Traffico di sostanze illegali | D.P.R. 309/1990 | NO | NO |
| Distribuzione di materiale CSAM | Art. 600-ter, 600-quater | NO | NO |
| Phishing | Art. 640 + 615-ter | NO | NO |
| Estorsione | Art. 629 | NO | NO |
| Diffamazione | Art. 595 | NO | NO |
| Violazione del copyright (su larga scala) | L. 633/1941 | NO | NO |
| Riciclaggio di denaro | Art. 648-bis | NO | NO |
| Terrorismo e apologia | Art. 270-bis e ss. | NO | NO |
| Minacce | Art. 612 | NO | NO |

**Il principio è semplice**: se un'attività è illegale senza Tor, resta illegale
con Tor. Tor è uno strumento neutro, come un telefono, un'automobile, o un
coltello da cucina. La legalità dipende dall'uso, non dallo strumento.

### La questione dell'anonimato come aggravante

In Italia, l'uso di strumenti di anonimizzazione durante un reato informatico
**non è un'aggravante specifica** prevista dal codice penale. Tuttavia, un
giudice potrebbe considerare la premeditazione (uso deliberato di Tor per
nascondere le tracce) come elemento del dolo.

Allo stesso modo, l'anonimato non è una scusante: un reato commesso via Tor
è perseguibile esattamente come uno commesso senza Tor.

---

## Sfumature legali specifiche

### Operare un exit node in Italia

Operare un exit node è legale, ma comporta rischi pratici significativi:

**Il problema**:
```
Il traffico di utenti sconosciuti esce dal tuo IP pubblico.
Se un utente commette un reato via Tor:
  1. Le indagini partono dall'IP dell'exit node (il TUO IP)
  2. Le autorità possono sequestrare cautelativamente il tuo server
  3. Devi dimostrare che sei un relay, non l'autore del traffico
  4. Il processo è lungo, costoso e stressante
```

**Mitigazioni legali**:
1. **Tor Exit Notice**: il Tor Project fornisce un template HTML da mostrare
   sulla porta 80 del tuo exit, che spiega che è un relay Tor
2. **Registrazione come relay**: documenta pubblicamente che gestisci un relay
3. **Consulenza legale**: consulta un avvocato PRIMA di operare un exit in Italia
4. **Comunicazione preventiva**: alcuni operatori informano la Polizia Postale
   che gestiscono un relay Tor

**Nella pratica italiana**: non ci sono precedenti giuridici noti di operatori
di exit node Tor condannati in Italia per il traffico transitato. Ma il rischio
di sequestro cautelare e delle spese legali esiste.

### Accedere a siti di altri paesi

Accedere a siti web stranieri (uscendo con un exit in USA, UK, Giappone, etc.)
è perfettamente legale. Milioni di persone lo fanno quotidianamente tramite VPN,
CDN, e routing Internet normale.

L'unica eccezione sarebbe se un sito è specificamente oggetto di un ordine
giudiziario italiano:
- Siti di gambling non autorizzati bloccati da ADM (ex AAMS)
- Siti con contenuti pedopornografici nella lista CNCPO
- Siti soggetti a ordine di oscuramento del GIP

**Nota**: il blocco ADM è implementato a livello DNS dall'ISP. Non è un divieto
penale per l'utente. Bypassare il blocco DNS non è reato per l'utente
(è un obbligo dell'ISP di implementarlo, non dell'utente di rispettarlo).

### Bridge e offuscamento

Usare bridge e pluggable transports (obfs4, meek, Snowflake) è legale in Italia.
Sono strumenti anti-censura sviluppati per proteggere utenti in paesi dove Tor è
bloccato. In Italia non c'è censura di Tor, ma usare bridge per privacy è un
diritto.

L'offuscamento del traffico non è reato. È equivalente all'uso di crittografia,
che è legale e protetto dal GDPR.

### NEWNYM e rotazione IP

Cambiare il proprio IP di uscita non è illegale. È equivalente a:
- Riconnettersi a Internet (il modem assegna un nuovo IP)
- Cambiare server VPN
- Spostarsi da una cella 4G a un'altra
- Usare un WiFi diverso

Non esiste legge che imponga di mantenere lo stesso IP.

### Uso di .onion

Accedere a siti .onion non è illegale. Gli onion services sono una tecnologia,
non un tipo di contenuto. Esistono .onion perfettamente legali:

```
Servizi .onion legali e noti:
- Facebook: facebookwkhpilnemxj7asaniu7vnjjbiltxjqhye3mhbshg7kx5tfyd.onion
- New York Times: nytimesn7cgmftshazwhfgzm37qxb44r64ytbb2dj3x62d2lnez7pnzl.onion
- BBC: bbcnewsd73hkzno2ini43t4gblxvycyac5aw4gnv7t2rccijh7745uqd.onion
- ProtonMail: protonmailrmez3lotccipshtkleegetolb73fuirgj7r4o4vfu7ozyd.onion
- DuckDuckGo: duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion
- SecureDrop (vari media): onion services per whistleblowing
- Debian packages: 2s4yqjx5ul6okpp3f2gaunr2syex5jgbfpfvhxxbbjdbez5dp4rbd2ad.onion
```

---

> **Continua in** [Aspetti Legali - Relay, Data Retention e Confronto Internazionale](aspetti-legali-relay-e-confronto.md)
> - operare relay in Italia, obblighi ISP, data retention, quadro europeo,
> precedenti giuridici, confronto internazionale, Tor in azienda.

---

## Vedi anche

- [Etica e Responsabilità](etica-e-responsabilita.md) - Dilemma etico, casi studio, uso responsabile
- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Conseguenze legali degli errori
- [Exit Nodes](../03-nodi-e-rete/exit-nodes.md) - Rischi pratici dell'operare un exit
- [Bridges e Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Uso legale in paesi con censura
