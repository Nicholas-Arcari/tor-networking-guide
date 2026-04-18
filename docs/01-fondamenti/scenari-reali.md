> **Lingua / Language**: Italiano | [English](../en/01-fondamenti/scenari-reali.md)

# Scenari Reali - Fondamenti della Rete Tor in Azione

Casi operativi in cui la conoscenza dei fondamenti Tor ha fatto la differenza
durante attività di penetration testing, red teaming e audit di sicurezza.

---

## Indice

- [Scenario 1: Analisi dei circuiti durante un pentest esterno](#scenario-1-analisi-dei-circuiti-durante-un-pentest-esterno)
- [Scenario 2: Rilevamento di relay malevoli nella catena](#scenario-2-rilevamento-di-relay-malevoli-nella-catena)
- [Scenario 3: Bypass censura con bridge durante un audit internazionale](#scenario-3-bypass-censura-con-bridge-durante-un-audit-internazionale)
- [Scenario 4: Verifica dell'integrità del consenso dopo compromissione sospetta](#scenario-4-verifica-dellintegrità-del-consenso-dopo-compromissione-sospetta)
- [Scenario 5: Correlazione circuiti e leak di identità in un red team](#scenario-5-correlazione-circuiti-e-leak-di-identità-in-un-red-team)

---

## Scenario 1: Analisi dei circuiti durante un pentest esterno

### Contesto

Engagement di penetration testing esterno su un target con WAF aggressivo che
bloccava IP dopo 3 richieste sospette. Il team doveva ruotare identità
frequentemente senza perdere visibilità sui circuiti attivi.

### Problema

Il WAF correlava le richieste per IP sorgente. Usare `SIGNAL NEWNYM` cambiava
circuito, ma il team non verificava se l'exit node fosse realmente cambiato.
In alcune occasioni lo stesso exit veniva riselezionato (probabilità non
trascurabile con pochi exit disponibili su certe porte).

### Soluzione tecnica

```bash
#!/bin/bash
# Verifica che l'exit cambi effettivamente dopo NEWNYM

OLD_EXIT=$(printf 'AUTHENTICATE "password"\r\nGETINFO circuit-status\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051 | grep "BUILT" | head -1 | grep -oP '\$\w+~\w+' | tail -1)

printf 'AUTHENTICATE "password"\r\nSIGNAL NEWNYM\r\nQUIT\r\n' | nc 127.0.0.1 9051
sleep 2

NEW_EXIT=$(printf 'AUTHENTICATE "password"\r\nGETINFO circuit-status\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051 | grep "BUILT" | head -1 | grep -oP '\$\w+~\w+' | tail -1)

if [ "$OLD_EXIT" = "$NEW_EXIT" ]; then
    echo "[!] Exit invariato: $OLD_EXIT - riprovare NEWNYM"
else
    echo "[+] Exit cambiato: $OLD_EXIT -> $NEW_EXIT"
fi
```

### Lezione appresa

La costruzione dei circuiti (trattata in [costruzione-circuiti.md](costruzione-circuiti.md))
non garantisce un exit diverso ad ogni NEWNYM. Il path selection algorithm bilancia
bandwidth e disponibilità - se pochi exit permettono la porta target, la probabilità
di riselezionare lo stesso è significativa. In quell'engagement, solo 12 exit
permettevano la porta 8443 del target.

---

## Scenario 2: Rilevamento di relay malevoli nella catena

### Contesto

Durante un'attività di threat intelligence, il team monitorava un onion service
sospetto. Le risposte HTTPS contenevano header anomali che non corrispondevano al
server reale - un possibile segno di MITM da parte di un exit malevolo.

### Problema

Un exit node modificava le risposte HTTP non-TLS (il team aveva iniziato con HTTP
per il crawling iniziale, prima di passare a HTTPS). Le risposte contenevano
JavaScript iniettato per il tracking.

### Analisi con i fondamenti

```bash
# Identificare l'exit node corrente
printf 'AUTHENTICATE "password"\r\nGETINFO circuit-status\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051

# Output:
# 42 BUILT $AAAA~GuardOK,$BBBB~MiddleOK,$CCCC~SuspectExit ...

# Verificare i flag dell'exit nel consenso
proxychains curl -s http://128.31.0.34:9131/tor/status-vote/current/consensus \
  | grep -A2 "SuspectExit"

# Cercare il flag BadExit (non presente = non ancora segnalato)
```

L'exit $CCCC non aveva flag `BadExit` perché non era ancora stato segnalato.
Il team ha:
1. Verificato il comportamento con `ExcludeExitNodes $CCCC` in torrc
2. Confermato che l'iniezione spariva con exit diversi
3. Segnalato il relay alle Directory Authorities

### Lezione appresa

Conoscere la struttura del consenso e i flag (vedi [struttura-consenso-e-flag.md](struttura-consenso-e-flag.md))
permette di verificare in tempo reale se un relay è già noto come malevolo. Il
flag `BadExit` è reattivo, non preventivo - le DA lo assegnano solo dopo la
segnalazione. Per attività sensibili, usare sempre HTTPS end-to-end oltre alla
cifratura Tor.

---

## Scenario 3: Bypass censura con bridge durante un audit internazionale

### Contesto

Audit di sicurezza su infrastruttura di un cliente con sedi in un paese che
applica DPI (Deep Packet Inspection) per bloccare Tor. Il team doveva operare
dalla sede locale senza rivelare l'uso di Tor all'ISP nazionale.

### Problema

Le connessioni dirette ai relay Tor venivano resettate dal firewall nazionale
entro 2-3 secondi dall'handshake TLS. Il DPI riconosceva il pattern TLS
specifico di Tor.

### Soluzione

```
# torrc con bridge obfs4
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

Bridge obfs4 [IP:PORTA] [FINGERPRINT] cert=[CERT] iat-mode=1
Bridge obfs4 [IP2:PORTA] [FINGERPRINT2] cert=[CERT2] iat-mode=1
```

Con `iat-mode=1`, obfs4 randomizza i timing inter-arrivo dei pacchetti, rendendo
il traffico indistinguibile da HTTPS generico per il DPI.

### Monitoraggio del bootstrap

```bash
# Osservare il bootstrap via ControlPort
watch -n1 'printf "AUTHENTICATE \"password\"\r\nGETINFO status/bootstrap-phase\r\nQUIT\r\n" \
  | nc 127.0.0.1 9051'

# Output progressivo:
# BOOTSTRAP PROGRESS=10 TAG=conn_done SUMMARY="Connected to a relay"
# BOOTSTRAP PROGRESS=50 TAG=loading_descriptors SUMMARY="Loading relay descriptors"
# BOOTSTRAP PROGRESS=75 TAG=enough_dirinfo SUMMARY="Loaded enough directory info..."
# BOOTSTRAP PROGRESS=100 TAG=done SUMMARY="Done"
```

Il bootstrap con bridge obfs4 richiede 30-60 secondi in più rispetto a una
connessione diretta, perché il client deve prima connettersi al bridge (che non
è nel consenso), e poi scaricare il consenso e i microdescriptor attraverso il bridge.

### Lezione appresa

La comprensione del processo di bootstrap (vedi [architettura-tor.md](architettura-tor.md))
è critica per diagnosticare problemi di connessione in ambienti censurati. Il
bootstrap è la fase più vulnerabile: se fallisce a "loading_descriptors" (75%),
il problema è quasi sempre il bridge (banda insufficiente o bloccato). Se fallisce
a "conn_done" (10%), il DPI sta ancora bloccando la connessione.

---

## Scenario 4: Verifica dell'integrità del consenso dopo compromissione sospetta

### Contesto

Dopo un incident response su un server che operava come relay Tor, il team
sospettava che un avversario avesse manipolato il file `state` e la cache del
consenso in `/var/lib/tor/` per forzare la selezione di guard specifici
controllati dall'attaccante.

### Analisi forense

```bash
# 1. Verificare integrità del file state
cat /var/lib/tor/state | grep EntryGuard
# EntryGuard SuspiciousRelay FINGERPRINT_A DirCache
# EntryGuardAddedBy FINGERPRINT_A 0.4.8.10 2025-11-01 12:00:00

# 2. Confrontare con il consenso corrente
proxychains curl -s http://128.31.0.34:9131/tor/status-vote/current/consensus \
  > /tmp/consensus-fresh.txt
grep "FINGERPRINT_A" /tmp/consensus-fresh.txt
# Verificare che il guard sia nel consenso e abbia flag Guard + Stable

# 3. Controllare la data di aggiunta del guard
# Se il guard è stato aggiunto *dopo* la compromissione, è sospetto

# 4. Verificare i certificati delle DA nella cache
ls -la /var/lib/tor/cached-certs
sha256sum /var/lib/tor/cached-certs
# Confrontare con hash noti dei certificati delle DA
```

### Indicatori di compromissione

- Guard aggiunti dopo la data stimata della compromissione
- Guard che non sono nel consenso corrente (rimossi dalle DA)
- Cache dei certificati con hash non corrispondenti
- Timestamp `EntryGuardAddedBy` incoerente con i log di sistema

### Lezione appresa

La persistenza del file `state` e la cache del consenso (vedi
[descriptor-cache-e-attacchi.md](descriptor-cache-e-attacchi.md)) possono essere
vettori di attacco. Un avversario con accesso root al sistema può modificare il
file `state` per forzare guard malevoli. In caso di compromissione, rigenerare
completamente `/var/lib/tor/` e forzare un nuovo bootstrap è l'unica opzione
sicura - ma va fatto consapevolmente, perché si perde la protezione dei guard
persistenti.

---

## Scenario 5: Correlazione circuiti e leak di identità in un red team

### Contesto

Durante un red team engagement, un operatore ha utilizzato lo stesso circuito
Tor per accedere sia al target (ricognizione anonima) sia a un servizio
personale (email). Questo ha creato un rischio di correlazione: l'exit node
vedeva entrambi gli stream sullo stesso circuito.

### Problema tecnico

Senza stream isolation, Tor multiplexing più stream sullo stesso circuito (vedi
[circuiti-crittografia-e-celle.md](circuiti-crittografia-e-celle.md)). L'exit
node osserva tutti gli stream in chiaro (se non cifrati end-to-end):

```
Circuito 42:
  Stream 1: RELAY_BEGIN → target.example.com:443 (ricognizione)
  Stream 2: RELAY_BEGIN → mail.personal.com:443 (email personale)
```

L'exit node non conosce l'IP del client, ma può correlare le due destinazioni
perché transitano sullo stesso circuito. Se una delle due rivela l'identità
dell'operatore, anche l'altra è compromessa.

### Mitigazione applicata

```
# torrc - isolamento per porta SOCKS
SocksPort 9050 IsolateDestAddr IsolateDestPort  # ricognizione
SocksPort 9052 IsolateClientAddr                 # uso personale

# proxychains per il pentest
# /etc/proxychains4-pentest.conf
socks5 127.0.0.1 9050

# proxychains per uso personale
# /etc/proxychains4-personal.conf
socks5 127.0.0.1 9052
```

Con questa configurazione, connessioni a destinazioni diverse usano
circuiti diversi. Lo stream verso il target e quello verso l'email
non condividono mai lo stesso exit node.

### Lezione appresa

Il modello di minaccia di Tor (vedi [isolamento-e-modello-minaccia.md](isolamento-e-modello-minaccia.md))
protegge dalla correlazione IP ma non dalla correlazione comportamentale.
La stream isolation non è attiva di default per tutte le porte - va configurata
esplicitamente. In un engagement, la regola è: un SocksPort per identità,
`IsolateDestAddr` obbligatorio, mai mischiare traffico operativo e personale.

---

## Riepilogo

| Scenario | Fondamento applicato | Rischio mitigato |
|----------|---------------------|------------------|
| Analisi circuiti | Path selection, ControlPort | Exit non ruotato, WAF bypass fallito |
| Relay malevoli | Flag consenso, BadExit | MITM su traffico HTTP |
| Bypass censura | Bootstrap, bridge, obfs4 | DPI detection, blocco connessione |
| Integrità consenso | Cache state, guard persistenti | Guard forzati post-compromissione |
| Correlazione stream | Stream isolation, multiplexing | Leak identità operatore |

---

## Vedi anche

- [Architettura di Tor](architettura-tor.md) - Componenti e panoramica
- [Costruzione Circuiti](costruzione-circuiti.md) - Path selection, NEWNYM
- [Isolamento e Modello di Minaccia](isolamento-e-modello-minaccia.md) - Stream isolation, threat model
- [Struttura Consenso e Flag](struttura-consenso-e-flag.md) - Flag e bandwidth authorities
- [Descriptor, Cache e Attacchi](descriptor-cache-e-attacchi.md) - Cache, attacchi al consenso
- [OpSec e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Errori operativi da evitare
- [Ricognizione Anonima](../09-scenari-operativi/ricognizione-anonima.md) - Uso operativo per pentest
