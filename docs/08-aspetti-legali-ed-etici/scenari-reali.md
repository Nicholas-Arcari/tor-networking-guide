> **Lingua / Language**: Italiano | [English](../en/08-aspetti-legali-ed-etici/scenari-reali.md)

# Scenari Reali - Aspetti Legali ed Etici di Tor in Azione

Casi operativi in cui aspetti legali, responsabilità dell'operatore relay,
etica dell'anonimato e confini di legalità hanno avuto impatto concreto
durante penetration test, attività professionali e gestione di incidenti.

---

## Indice

- [Scenario 1: Exit relay operato da consulente riceve abuse complaint durante pentest](#scenario-1-exit-relay-operato-da-consulente-riceve-abuse-complaint-durante-pentest)
- [Scenario 2: Pentest via Tor - scope creep e rischio legale](#scenario-2-pentest-via-tor--scope-creep-e-rischio-legale)
- [Scenario 3: Whistleblower aziendale - OPSEC legale insufficiente](#scenario-3-whistleblower-aziendale--opsec-legale-insufficiente)
- [Scenario 4: Tool dual-use scaricato da .onion - implicazioni per il team](#scenario-4-tool-dual-use-scaricato-da-onion--implicazioni-per-il-team)

---

## Scenario 1: Exit relay operato da consulente riceve abuse complaint durante pentest

### Contesto

Un consulente di sicurezza italiano gestiva un exit relay Tor su una VPS
in Germania come contributo alla rete. Separatamente, un altro team della
sua azienda eseguiva un pentest autorizzato su un cliente. Per coincidenza,
parte del traffico del pentest è transitata dall'exit relay del consulente.

### Problema

Il SOC del cliente ha rilevato attività sospette (scanning) dall'IP
dell'exit relay. Non sapendo che fosse un relay Tor, hanno inviato una
abuse complaint all'hosting provider tedesco:

```
Abuse complaint → hosting provider (Hetzner)
  "Il vostro IP 168.x.x.x ha eseguito port scanning sul nostro server"
  
Hetzner → consulente:
  "Abbiamo ricevuto una segnalazione di abuso per il vostro server.
   Avete 24 ore per rispondere o sospenderemo il servizio."

Timeline:
  1. Il consulente risponde con il template Tor Exit Notice
  2. Hetzner accetta la spiegazione (Hetzner è Tor-friendly)
  3. Ma il cliente del pentest vede "exit Tor" nella risposta
  4. Il cliente chiede: "Perché un exit Tor della vostra azienda
     sta scansionando i nostri server?"
  → Coincidenza, ma la perception è devastante
```

### Come è stato gestito

```
1. Il consulente ha documentato:
   - L'exit relay è un contributo personale, non aziendale
   - Il traffico del pentest è transitato casualmente
   - I log del relay non contengono informazioni utili (by design)

2. L'azienda ha aggiornato la policy interna:
   - Dipendenti che operano relay Tor devono notificarlo
   - Exit relay su IP non riconducibili all'azienda
   - O usare hosting provider diversi per relay e infrastruttura aziendale

3. Comunicazione al cliente:
   - Spiegazione tecnica di come funziona Tor
   - Dimostrazione che il pentest usava IP diversi (log Burp)
   - Aggiornamento del report con nota sulla coincidenza
```

### Lezione appresa

Operare un exit relay è legale e meritorio, ma crea un rischio
reputazionale se l'IP è riconducibile alla propria organizzazione.
Separare l'infrastruttura relay dall'infrastruttura professionale.
Vedi [Aspetti Legali - Relay](aspetti-legali-relay-e-confronto.md)
per i dettagli su responsabilità e safe harbor.

---

## Scenario 2: Pentest via Tor - scope creep e rischio legale

### Contesto

Un pentester usava Tor per la fase di ricognizione esterna su un target
autorizzato. Il contratto specificava come scope "*.target.com". Durante
la ricognizione, ha trovato un sottodominio (dev.target.com) che puntava
a un IP di un provider cloud diverso, gestito da un fornitore terzo.

### Problema

```
Scope contrattuale: *.target.com
dev.target.com → 35.x.x.x (AWS, gestito da fornitore terzo)

Il pentester ha eseguito:
  proxychains nmap -sT -Pn dev.target.com -p 80,443,8080
  proxychains nikto -h https://dev.target.com

Tecnicamente: il dominio è in scope (*.target.com)
Legalmente: l'infrastruttura sottostante è di terzi (il fornitore AWS)
→ Il pentester sta scansionando infrastruttura NON autorizzata

Se il fornitore segnala l'attività:
  - L'IP di uscita è un exit Tor → non risalibile al pentester
  - Ma i log mostrano scanning da Tor su infrastruttura AWS
  - AWS potrebbe segnalare abuse al Tor Project
  - Se viene identificato: potenziale Art. 615-ter c.p. (accesso abusivo)
```

### Fix procedurale

```
1. PRIMA di testare qualsiasi target:
   - Verificare la proprietà dell'infrastruttura (whois, ASN)
   - Se l'infrastruttura è di terzi → chiedere autorizzazione specifica
   - Documentare nel report: "escluso dev.target.com (infra di terzi)"

2. Nel contratto:
   - Clausola che definisce scope per IP, non solo per dominio
   - Clausola che esclude esplicitamente infra di terzi
   - Clausola di manleva per attività in scope

3. Tor non è uno scudo legale:
   - L'anonimato NON cancella il reato
   - "Stavo usando Tor" non è una difesa in tribunale
   - L'autorizzazione scritta è l'UNICA protezione legale
```

### Lezione appresa

Tor nasconde l'IP, non la responsabilità legale. Un pentest senza
autorizzazione esplicita per l'infrastruttura specifica è un reato
(Art. 615-ter c.p.), indipendentemente dal fatto che si usi Tor.
La ricognizione via Tor non rende legale ciò che è illegale.
Vedi [Aspetti Legali](aspetti-legali.md) per il quadro normativo completo.

---

## Scenario 3: Whistleblower aziendale - OPSEC legale insufficiente

### Contesto

Un dipendente di un'azienda italiana ha scoperto irregolarità contabili
gravi. Ha deciso di segnalare all'ANAC (Autorità Nazionale Anticorruzione)
usando Tor per proteggersi da ritorsioni. L'Italia ha una legge sul
whistleblowing (D.Lgs. 24/2023).

### Problema

Il dipendente ha usato Tor correttamente per la segnalazione tecnica,
ma ha commesso errori di OPSEC legale:

```
Cosa ha fatto bene:
  ✓ Tor Browser per la segnalazione ANAC
  ✓ Nessun login con account personali
  ✓ Segnalazione da rete WiFi pubblica (non aziendale)

Cosa ha sbagliato:
  ✗ Ha allegato un documento Word alla segnalazione
    → I metadati del file contenevano: nome utente, nome PC, data creazione
    → Il nome utente corrispondeva al suo account aziendale
    → La data di creazione era durante l'orario di lavoro

  ✗ Ha usato informazioni che solo 3 persone potevano conoscere
    → L'azienda ha identificato il cerchio di sospetti per esclusione
    → Il documento con metadati ha confermato l'identità

  ✗ Non ha consultato un avvocato PRIMA della segnalazione
    → La legge whistleblowing protegge, ma serve documentazione
    → Senza assistenza legale, la protezione è più debole
```

### Come doveva procedere

```
1. Consultare un avvocato specializzato PRIMA di agire
   → L'avvocato guida sulla documentazione necessaria
   → La protezione legale è più forte con assistenza professionale

2. Pulire i metadati dei documenti:
   exiftool -all= documento.docx
   # Oppure copiare il contenuto in un nuovo file di testo

3. Valutare se le informazioni sono identificanti:
   → Se solo 3 persone sanno X, segnalare X identifica il cerchio
   → Includere solo informazioni accessibili a molti dipendenti
   → O accettare il rischio con protezione legale adeguata

4. Usare canali dedicati:
   → SecureDrop del giornale (se disponibile)
   → GlobaLeaks per segnalazioni anonime
   → ANAC ha un canale dedicato per whistleblowing
```

### Lezione appresa

L'anonimato tecnico (Tor) non è sufficiente senza OPSEC sui contenuti.
I metadati dei documenti, il contenuto delle informazioni, e la
tempistica possono deanonimizzare anche con una connessione perfettamente
anonima. Per il whistleblowing, la protezione legale (D.Lgs. 24/2023)
è importante quanto quella tecnica. Vedi [Etica e Responsabilità](etica-e-responsabilita.md)
per i principi etici e [OPSEC](../05-sicurezza-operativa/opsec-e-errori-comuni.md)
per gli errori comuni.

---

## Scenario 4: Tool dual-use scaricato da .onion - implicazioni per il team

### Contesto

Durante un red team engagement, un operatore ha trovato su un forum
.onion un tool di exploitation personalizzato per una vulnerabilità
specifica del target. Il tool non era disponibile su repository pubblici.
L'operatore l'ha scaricato e voleva usarlo nell'engagement.

### Problema

```
Rischi identificati dal team lead:

1. Provenienza sconosciuta:
   - Il tool potrebbe contenere backdoor
   - Il tool potrebbe essere un honeypot delle forze dell'ordine
   - Nessuna possibilità di audit del codice sorgente

2. Implicazioni legali:
   - Il possesso di tool di exploitation non è reato in Italia
     (se per scopi professionali leciti)
   - MA: se il tool contiene funzionalità non dichiarate
     (es. esfiltrazione dati verso terzi), l'operatore potrebbe
     essere corresponsabile

3. Implicazioni contrattuali:
   - Il contratto di pentest specifica gli strumenti approvati
   - Tool da fonti non verificate potrebbero violare il contratto
   - Se il tool causa danni non previsti, la responsabilità è del team

4. Chain of custody:
   - Il report del pentest deve documentare gli strumenti usati
   - "Tool scaricato da un forum .onion" non è presentabile
   - Il cliente potrebbe contestare i risultati
```

### Decisione del team

```
1. NON usare il tool direttamente
   → Rischio backdoor troppo alto per un engagement professionale

2. Analizzare il tool in ambiente isolato:
   - VM senza rete, snapshot pre-analisi
   - Reverse engineering del binario
   - Se contiene funzionalità sospette → discard
   - Se il codice è pulito → valutare

3. Ricreare la funzionalità con tool propri:
   - Studiare la tecnica di exploitation dal tool
   - Reimplementare con strumenti noti e verificati (Metasploit, custom script)
   - Documentabile e auditabile nel report

4. Policy aggiornata:
   - Tool da fonti non verificate: analisi obbligatoria prima dell'uso
   - Documentazione della provenienza nel report interno
   - Approvazione del team lead per qualsiasi tool non standard
```

### Lezione appresa

L'accesso a .onion è legale, ma i contenuti scaricati possono creare
problemi legali, contrattuali e di sicurezza. In un contesto professionale,
la provenienza degli strumenti è importante quanto la loro efficacia.
Mai usare tool non verificati in un engagement - il rischio supera il
beneficio. Vedi [Etica e Responsabilità](etica-e-responsabilita.md)
per il framework etico e [Aspetti Legali](aspetti-legali.md) per la
legalità degli strumenti dual-use.

---

## Riepilogo

| Scenario | Area | Rischio mitigato |
|----------|------|------------------|
| Exit relay e abuse complaint | Responsabilità relay | Conflitto tra contributo personale e ruolo professionale |
| Scope creep nel pentest | Legalità pentest | Accesso abusivo a infra di terzi fuori scope |
| Whistleblower con metadata leak | OPSEC legale | Deanonimizzazione via metadati documento |
| Tool da .onion in engagement | Etica professionale | Backdoor, responsabilità, chain of custody |

---

## Vedi anche

- [Aspetti Legali](aspetti-legali.md) - Legalità in Italia, codice penale, GDPR
- [Aspetti Legali - Relay e Confronto](aspetti-legali-relay-e-confronto.md) - Operare relay, safe harbor
- [Etica e Responsabilità](etica-e-responsabilita.md) - Principi etici, dilemma anonimato
- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Errori e metadata
- [Analisi Forense](../05-sicurezza-operativa/analisi-forense-e-artefatti.md) - Artefatti e tracce
