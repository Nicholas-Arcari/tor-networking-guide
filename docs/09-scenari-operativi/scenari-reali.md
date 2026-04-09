# Scenari Reali - Operazioni Tor in Contesto Professionale

Casi operativi in cui ricognizione anonima, comunicazione sicura,
sviluppo via Tor e incident response hanno avuto impatto concreto
durante engagement professionali.

---

## Indice

- [Scenario 1: OSINT cross-target - correlazione da exit condiviso](#scenario-1-osint-cross-target--correlazione-da-exit-condiviso)
- [Scenario 2: SecureDrop usato per ricevere IOC durante incident response](#scenario-2-securedrop-usato-per-ricevere-ioc-durante-incident-response)
- [Scenario 3: Pipeline CI/CD via Tor rallenta il rilascio critico](#scenario-3-pipeline-cicd-via-tor-rallenta-il-rilascio-critico)
- [Scenario 4: Monitoraggio darknet rivela data breach prima del cliente](#scenario-4-monitoraggio-darknet-rivela-data-breach-prima-del-cliente)

---

## Scenario 1: OSINT cross-target - correlazione da exit condiviso

### Contesto

Un team CTI (Cyber Threat Intelligence) monitorava due threat actor
distinti per due clienti diversi. Lo stesso analista conduceva la
ricognizione OSINT su entrambi i target usando la stessa istanza Tor
con SocksPort 9050 senza flag di isolamento.

### Problema

Entrambe le attività di ricognizione condividevano gli stessi circuiti
Tor. In un caso, uno dei threat actor gestiva anche un servizio web che
loggava gli IP dei visitatori:

```
Log del threat actor (forum che gestiva):
  Exit 185.220.101.x → visita profilo "actor_A" alle 10:15
  Exit 185.220.101.x → visita profilo "actor_B" alle 10:18
  (stesso exit, stesso minuto)

Deduzione:
  → Qualcuno sta investigando sia actor_A che actor_B
  → Probabilmente un analista CTI che lavora su entrambi i casi
  → Se actor_A e actor_B comunicano: "qualcuno ci sta osservando"
```

La mancanza di stream isolation ha correlato due indagini che dovevano
restare completamente separate.

### Fix

```ini
# torrc: stream isolation per ogni attività
SocksPort 9050 IsolateSOCKSAuth

# Oppure: istanze Tor separate
SocksPort 9050   # Client A
SocksPort 9052   # Client B
```

```bash
# Ricerca su target A → circuito A
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "clientA:osint" https://forum-actor-a.com/

# Ricerca su target B → circuito B (exit diverso)
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "clientB:osint" https://forum-actor-b.com/
```

### Lezione appresa

Ogni engagement/cliente deve avere circuiti Tor separati. Senza
`IsolateSOCKSAuth` o istanze dedicate, un exit node (o il threat actor
che controlla un endpoint) può correlare attività che dovrebbero essere
indipendenti. Vedi [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md).

---

## Scenario 2: SecureDrop usato per ricevere IOC durante incident response

### Contesto

Durante un incident response per un'azienda italiana che aveva subito
un data breach, il team IR aveva bisogno di ricevere informazioni da
una fonte interna che temeva ritorsioni. La fonte aveva identificato
l'entry point dell'attaccante ma non voleva essere associata alla
segnalazione per paura di essere considerata complice.

### Problema

```
Canali valutati:
  Email aziendale    → Loggata dal mail server compromesso
  Telefono aziendale → Call log accessibili al management
  Email personale    → Potenzialmente monitorata dall'attaccante
  Incontro fisico    → La fonte temeva di essere vista

Soluzione: la fonte ha usato Tor Browser per contattare il team IR
attraverso un'istanza GlobaLeaks temporanea.
```

Il team IR ha deployato un'istanza GlobaLeaks su un server esterno,
accessibile solo via .onion:

```bash
# Setup rapido GlobaLeaks (sul server del team IR)
# → Genera un indirizzo .onion
# → La fonte accede via Tor Browser
# → Carica documenti con evidenze (screenshot, log)
# → Comunicazione bidirezionale anonima

# La fonte ha fornito:
# - Screenshot del server compromesso con backdoor path
# - Log che mostravano l'entry point (VPN credential stuffing)
# - Timeline interna dell'attacco
```

### Risultato

La fonte ha condiviso IOC critici che hanno accelerato il contenimento
di 48 ore. L'identità della fonte non è mai stata rivelata al management
del cliente. Dopo l'incident response, l'istanza GlobaLeaks è stata
distrutta.

### Lezione appresa

Per incident response dove le fonti interne temono ritorsioni, un canale
anonimo via .onion è essenziale. GlobaLeaks e SecureDrop permettono
comunicazione bidirezionale anonima. Il team IR deve avere la capacità
di deployare rapidamente un servizio .onion temporaneo. Vedi
[Comunicazione Sicura](comunicazione-sicura.md) e
[Onion Services v3](../03-nodi-e-rete/onion-services-v3.md).

---

## Scenario 3: Pipeline CI/CD via Tor rallenta il rilascio critico

### Contesto

Un team di sviluppo aveva configurato la pipeline CI per scaricare
dipendenze via Tor (proxychains + npm/pip), per evitare che il server
CI rivelasse l'IP aziendale ai registry pubblici. Funzionava per build
normali (5-10 dipendenze, piccole).

### Problema

Un rilascio critico richiedeva l'aggiornamento di 47 dipendenze npm
(incluso un framework UI da 80 MB). La pipeline via Tor ha impiegato
42 minuti invece dei soliti 3:

```
Build senza Tor:  npm install → 2 min 15 sec
Build con Tor:    proxychains npm install → 42 min 08 sec
  - Ogni pacchetto: download SOCKS5 → lento
  - Pacchetti grandi: timeout, retry, timeout, retry
  - npm audit: timeout (API rate-limited per exit Tor)
  - Il rilascio critico è stato ritardato di quasi 1 ora

Il CTO: "Perché il build ci mette 40 minuti?"
```

### Fix

```bash
# Approccio ibrido: cache locale + Tor solo per build sensibili

# 1. Mirror npm locale (Verdaccio)
docker run -d --name verdaccio -p 4873:4873 verdaccio/verdaccio
npm set registry http://localhost:4873

# 2. Verdaccio upstream via Tor (solo per aggiornare la cache)
# verdaccio config: proxy upstream via SOCKS5

# 3. Pipeline CI: usa il mirror locale (veloce)
# Il mirror si aggiorna in background via Tor (lento ma non bloccante)

# Risultato:
# Build da mirror locale: 2 min 30 sec (quasi come senza Tor)
# Aggiornamento mirror via Tor: in background, non bloccante
```

### Lezione appresa

Tor non è adatto per pipeline CI con molte dipendenze in download
diretto. La soluzione è un mirror/cache locale che si aggiorna via Tor
in background. Il download diretto via Tor è accettabile solo per
poche dipendenze piccole. Vedi [Sviluppo e Test](sviluppo-e-test.md)
per le configurazioni CI/CD.

---

## Scenario 4: Monitoraggio darknet rivela data breach prima del cliente

### Contesto

Un team CTI monitorava forum e marketplace .onion per conto di diversi
clienti. Il monitoraggio usava script Python automatizzati che accedevano
a .onion noti via Tor, scaricavano listing e li analizzavano per keyword
dei clienti.

### Scoperta

```python
# Lo script ha trovato un listing su un marketplace:
# "DB dump - azienda_italiana_spa - 2.3M records"
# - Email, password hash (bcrypt), nomi, indirizzi
# - Prezzo: $500
# - Pubblicato: 3 ore fa
# - Vendor con rating 4.8/5 (vendor affidabile)

# Verifica: il sample nel listing conteneva
# record con dominio @azienda_italiana_spa.it
# → Breach confermato
```

Il team CTI ha notificato il cliente prima che il breach diventasse
pubblico. Il cliente non sapeva di essere stato compromesso.

### Gestione

```
Timeline:
  t=0h:    Script trova il listing
  t=0.5h:  Analista verifica il sample (dati reali, breach confermato)
  t=1h:    Notifica al CISO del cliente via canale sicuro
  t=2h:    Il cliente avvia incident response
  t=4h:    Contenimento (credential reset, log analysis)
  t=24h:   Il listing viene rimosso dal marketplace (vendor lo ritira)
  t=48h:   Notifica al Garante Privacy (obbligo GDPR, 72 ore)

Senza monitoraggio darknet:
  → Il breach sarebbe stato scoperto settimane dopo
  → Forse solo quando i dati erano già stati rivenduti
  → Il Garante avrebbe ricevuto la notifica fuori termine
```

### Lezione appresa

Il monitoraggio proattivo dei marketplace .onion è CTI operativa
essenziale. L'accesso via Tor è l'unico modo per raggiungere questi
servizi. L'automazione (script + Tor) permette monitoraggio continuo
di centinaia di fonti. La tempestività della notifica ha permesso al
cliente di rispettare i termini GDPR (72 ore). Vedi
[Incident Response](incident-response.md) per il workflow completo.

---

## Riepilogo

| Scenario | Area | Rischio mitigato |
|----------|------|------------------|
| OSINT cross-target senza isolamento | Ricognizione | Correlazione tra indagini separate |
| SecureDrop per IR con fonte interna | Comunicazione | Protezione identità fonte durante breach |
| CI/CD via Tor troppo lento | Sviluppo | Ritardo rilascio per download via Tor |
| Darknet monitoring pre-breach | Incident Response | Scoperta breach prima della divulgazione pubblica |

---

## Vedi anche

- [Ricognizione Anonima](ricognizione-anonima.md) - OSINT via Tor
- [Comunicazione Sicura](comunicazione-sicura.md) - SecureDrop, GlobaLeaks, messaging
- [Sviluppo e Test](sviluppo-e-test.md) - CI/CD, Docker, dependency management
- [Incident Response](incident-response.md) - Threat intelligence, darknet monitoring
- [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Isolamento circuiti
