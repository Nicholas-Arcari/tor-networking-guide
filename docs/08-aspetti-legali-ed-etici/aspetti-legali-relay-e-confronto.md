# Aspetti Legali - Relay, Data Retention e Confronto Internazionale

Operare un relay Tor in Italia, obblighi degli ISP e data retention,
quadro europeo (GDPR, NIS2, DSA), precedenti giuridici, confronto
internazionale, Tor nel contesto aziendale.

> **Estratto da** [Aspetti Legali dell'Uso di Tor](aspetti-legali.md) -
> che copre anche legalità in Italia, base giuridica, reati, e sfumature
> legali specifiche.

---

## Operare un relay Tor in Italia

### Tipi di relay e rischio legale

| Tipo di relay | Rischio legale in Italia | Note |
|--------------|------------------------|------|
| Bridge (non pubblico) | Minimo | Traffico offuscato, non sei nell'elenco pubblico |
| Guard/Middle relay | Basso | Traffico cifrato in transito, non sei l'origine |
| Exit node | Medio-alto | Il traffico esce dal tuo IP |
| Directory Authority | N/A | Solo 9 nel mondo, gestiti dal Tor Project |

### Considerazioni per relay middle/guard

```
Rischio legale: basso
  - Il traffico che transita è cifrato
  - Non puoi vedere il contenuto
  - Non sei né l'origine né la destinazione
  - Sei equivalente a un ISP che trasporta traffico

Rischio pratico:
  - Consume bandwidth (verifica il tuo contratto ISP)
  - Potrebbe violare i ToS del tuo ISP (verifica)
  - L'IP potrebbe finire in alcune blocklist (raro per non-exit)

Raccomandazione:
  - Verifica i ToS del tuo ISP
  - Usa un'istanza dedicata (non il tuo PC principale)
  - Configura AccountingMax per limitare il traffico
```

### Responsabilità del carrier (safe harbor)

In Italia e nell'UE, il principio del "mere conduit" (semplice trasporto) della
Direttiva 2000/31/CE (Direttiva e-Commerce) offre protezione a chi fornisce
servizi di trasporto di dati:

**Art. 12 (mere conduit)**:
> Il prestatore di servizi non è responsabile delle informazioni trasmesse
> a condizione che non dia origine alla trasmissione, non selezioni il
> destinatario, e non selezioni né modifichi le informazioni trasmesse.

Un relay Tor soddisfa tutte e tre le condizioni:
1. Non origina il traffico (lo riceve e lo inoltra)
2. Non seleziona il destinatario (il circuito è scelto dal client)
3. Non modifica le informazioni (le inoltra cifrate)

Tuttavia, questa protezione non è stata testata specificamente per i relay Tor
nei tribunali italiani.

---

## Obblighi degli ISP e data retention

### Cosa logga il mio ISP (Comeser)

Secondo la normativa italiana sulla data retention (D.Lgs. 109/2008, come
modificato dal D.Lgs. 132/2021), gli ISP sono obbligati a conservare:

```
Dati conservati (per 6 anni per traffico telefonico, 1 anno per telematico):
- Data e ora della connessione
- Durata della connessione
- IP assegnato
- Tipo di connessione (ADSL, fibra, mobile)

Dati NON conservati (per navigazione web):
- URL visitati (il contenuto della navigazione non è loggato)
- Query DNS individuali (non obbligatoriamente)
- Contenuto delle comunicazioni

Eccezione: con ordine dell'autorità giudiziaria, l'ISP può essere
obbligato a monitorare il traffico di un utente specifico
(intercettazione telematica, Art. 266-bis c.p.p.)
```

### Cosa vede l'ISP quando uso Tor

```
Senza bridge:
- L'ISP vede: connessione TCP verso IP di un Guard Tor noto
- L'ISP sa: "questo utente sta usando Tor"
- L'ISP NON sa: cosa sta facendo su Tor

Con bridge obfs4:
- L'ISP vede: connessione verso un IP non noto come relay Tor
- L'ISP vede: traffico che sembra HTTPS normale (offuscato)
- L'ISP NON sa: che stai usando Tor
- L'ISP NON sa: cosa stai facendo
```

### Data retention e Tor

La data retention italiana conserva metadati di connessione, non contenuti.
L'ISP logga che alle 14:30 il mio IP (151.x.x.x) si è connesso a un IP
(il Guard). Non logga cosa ho fatto su Tor.

Se l'ISP identifica la connessione come Tor (senza bridge), logga solo:
"connessione a IP di relay Tor". Non può loggare la destinazione finale.

---

## Quadro europeo

### GDPR e privacy

Il GDPR riconosce la privacy come diritto fondamentale. L'uso di strumenti
come Tor è coerente con il diritto alla protezione dei dati personali
(Art. 5, 25, 32 GDPR).

La Corte di Giustizia dell'UE ha più volte ribadito che la protezione dei dati
personali è un diritto fondamentale (Art. 8 Carta dei diritti fondamentali UE).

### Direttiva NIS2 (2022/2555)

La Direttiva NIS2 sulla sicurezza delle reti e dei sistemi informativi
non vieta Tor. Anzi, la crittografia e l'anonimizzazione sono raccomandate
come misure di sicurezza per le organizzazioni critiche.

### Digital Services Act (DSA) - Regolamento 2022/2065

Il DSA regola le piattaforme online ma non vieta l'uso di strumenti di
anonimizzazione. Impone obblighi di moderazione ai gestori di piattaforme,
non agli utenti. Non menziona Tor.

### ePrivacy Directive (2002/58/CE)

Protegge la riservatezza delle comunicazioni elettroniche. L'uso di Tor è
coerente con questa direttiva: l'utente protegge la riservatezza delle
proprie comunicazioni.

### Proposta ePrivacy Regulation (in discussione)

La proposta di regolamento ePrivacy, in discussione dal 2017, potrebbe
rafforzare le protezioni della privacy online. Non contiene disposizioni
che vietino strumenti di anonimizzazione.

---

## Precedenti giuridici rilevanti

### Italia

**Non esistono sentenze italiane note che condannino l'uso di Tor in sé.**

Ci sono sentenze dove Tor è menzionato come strumento usato durante un reato
(es. accesso abusivo), ma in nessun caso l'uso di Tor è stato considerato
reato autonomo o aggravante.

Casi dove Tor è menzionato nei procedimenti italiani:
- Indagini su mercati darknet con utenti italiani
- Casi di pedopornografia dove Tor è stato usato per l'accesso
- Casi di hacking dove Tor è stato usato per anonimizzare

In tutti questi casi, il reato contestato è l'attività svolta (spaccio,
possesso di materiale CSAM, accesso abusivo), non l'uso di Tor.

### Europa

**Daniel Moritz Haikal (Germania, 2016)**:
Un operatore di exit node tedesco è stato assolto dall'accusa di favoreggiamento
per il traffico transitato dal suo relay. Il tribunale ha stabilito che
l'operatore di un relay non è responsabile per il contenuto del traffico.

**Zwiebelfreunde e.V. (Germania, 2018)**:
La polizia tedesca ha sequestrato i server di un'associazione che gestiva
relay Tor. Il sequestro è stato successivamente dichiarato illegittimo.

### USA

**Vari casi di operatori exit node**:
Negli USA, diversi operatori di exit node hanno ricevuto mandati di perquisizione
o sequestri. In nessun caso noto sono stati condannati per il traffico di terzi.
L'EFF (Electronic Frontier Foundation) ha fornito assistenza legale in molti casi.

---

## Confronto internazionale

### Paesi dove Tor è legale e non bloccato

| Paese | Status | Note |
|-------|--------|------|
| Italia | Legale, non bloccato | Nessuna restrizione |
| Germania | Legale, non bloccato | Forte tradizione di privacy |
| Francia | Legale, non bloccato | |
| Spagna | Legale, non bloccato | |
| Olanda | Legale, non bloccato | Molti relay ospitati |
| Svizzera | Legale, non bloccato | Sede di ProtonMail |
| USA | Legale, non bloccato | Tor è nato dal progetto della US Navy |
| UK | Legale, non bloccato | Ma sorveglianza estesa (GCHQ) |
| Giappone | Legale, non bloccato | |
| Brasile | Legale, non bloccato | |

### Paesi dove Tor è bloccato o limitato

| Paese | Status | Dettagli |
|-------|--------|----------|
| Cina | Bloccato (DPI) | Bridge parzialmente funzionanti, meek utile |
| Russia | Bloccato dal 2021 | obfs4 bridge funzionano, Snowflake funziona |
| Iran | Bloccato | Bridge necessari, obfs4 funziona |
| Turkmenistan | Internet pesantemente filtrato | Tor molto difficile da usare |
| Bielorussia | Bloccato dal 2022 | Bridge necessari |
| Egitto | Parzialmente bloccato | Bridge funzionano |
| Kazakistan | Parzialmente bloccato | DPI intermittente |
| Venezuela | Parzialmente bloccato | Periodi di blocco intermittente |

### Paesi dove l'uso di Tor può essere rischioso

| Paese | Rischio | Note |
|-------|---------|------|
| Cina | Alto | Possibili conseguenze legali per aggiramento censura |
| Arabia Saudita | Alto | Criminalizzazione di VPN/Tor possibile |
| Emirati Arabi | Alto | Uso di VPN/Tor può essere multato |
| Corea del Nord | Estremo | Internet non accessibile per la popolazione |

**In Italia e nell'UE**: Tor non è bloccato né limitato. L'uso è un diritto
implicito nella legislazione sulla privacy.

---

## Tor nel contesto aziendale

### Uso di Tor nelle aziende

L'uso di Tor in contesto aziendale è legale ma può essere limitato dalle
policy aziendali:

```
Usi legittimi in azienda:
- Threat intelligence (monitorare darknet per leak di dati aziendali)
- OSINT (ricognizione anonima su competitor o threat actors)
- Test di sicurezza (verificare come appaiono i servizi da IP anonimi)
- Protezione di ricerche sensibili (R&D, M&A)
- Comunicazione con fonti riservate (giornalismo investigativo)

Usi problematici:
- Bypassare il firewall aziendale (possibile violazione policy)
- Attività non autorizzate durante l'orario di lavoro
- Esfiltrazione di dati aziendali
```

### Policy aziendale raccomandata

```
Una policy aziendale su Tor dovrebbe:
1. Non vietare Tor genericamente (è uno strumento legittimo)
2. Autorizzare l'uso per scopi specifici (CTI, OSINT, test)
3. Richiedere autorizzazione per l'installazione
4. Loggare l'uso (senza loggare il contenuto)
5. Definire responsabilità in caso di incidenti
```

---

## Chi usa Tor legittimamente

Tor è usato quotidianamente da milioni di persone per scopi legittimi:

- **Giornalisti**: proteggere fonti e comunicazioni (SecureDrop usa Tor)
- **Attivisti per i diritti umani**: in paesi con sorveglianza di massa
- **Ricercatori di sicurezza**: test anonimi, analisi di minacce, OSINT
- **Cittadini comuni**: privacy dall'ISP e dai tracker
- **Aziende**: competitive intelligence senza rivelare l'IP
- **Forze dell'ordine**: indagini sotto copertura (sì, le forze dell'ordine usano Tor)
- **Militari e diplomatici**: comunicazioni sicure (Tor è nato dal progetto della US Navy)
- **Whistleblower**: segnalazioni anonime (SecureDrop, GlobaLeaks)
- **Vittime di violenza domestica**: comunicazione sicura con centri antiviolenza
- **Persone LGBT+ in paesi ostili**: protezione dalla persecuzione
- **Utenti in paesi con censura**: accesso a informazione libera

### Statistiche sulla rete Tor (2024-2025)

```
Utenti giornalieri stimati: ~2-4 milioni
Relay attivi: ~7.000-8.000
Bridge attivi: ~2.000-3.000
Bandwidth totale: ~400-600 Gbit/s
Paesi con più utenti: USA, Russia, Germania, Francia, UK
```

---

## Nella mia esperienza

Prima di iniziare a usare Tor, mi sono informato sulla legalità in Italia.
Le mie conclusioni:

1. **Usare Tor è legale**: nessuna legge italiana lo vieta
2. **Bridge e NEWNYM sono legali**: sono funzionalità tecniche, non attività illecite
3. **Accedere a siti esteri è legale**: lo fanno milioni di persone quotidianamente
4. **L'importante è cosa fai**: Tor è uno strumento, la legalità dipende dall'uso
5. **L'ISP non può impedirti di usare Tor**: non viola nessun contratto standard

Le configurazioni documentate in questa guida sono per studio, sicurezza e
privacy legittima. Non incoraggiano e non facilitano attività illegali.

Il mio caso d'uso rientra pienamente nel diritto alla privacy:
- Studio del protocollo e della rete
- Test di sicurezza autorizzati
- Privacy dalla profilazione dell'ISP
- Comprensione delle tecniche di anonimato

---

## Vedi anche

- [Etica e Responsabilità](etica-e-responsabilita.md) - Dilemma etico, casi studio, uso responsabile
- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Conseguenze legali degli errori
- [Exit Nodes](../03-nodi-e-rete/exit-nodes.md) - Rischi pratici dell'operare un exit
- [Bridges e Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Uso legale in paesi con censura
- [Ricognizione Anonima](../09-scenari-operativi/ricognizione-anonima.md) - OSINT legale via Tor
