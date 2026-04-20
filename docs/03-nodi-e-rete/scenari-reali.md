> **Lingua / Language**: Italiano | [English](../en/03-nodi-e-rete/scenari-reali.md)

# Scenari Reali - Nodi e Rete Tor in Azione

Casi operativi in cui la conoscenza dei nodi Tor (guard, exit, bridge) e
del monitoring ha fatto la differenza in engagement di sicurezza reali.

---

## Indice

- [Scenario 1: Exit malevolo inietta JavaScript durante un assessment](#scenario-1-exit-malevolo-inietta-javascript-durante-un-assessment)
- [Scenario 2: Guard lento compromette una ricognizione time-sensitive](#scenario-2-guard-lento-compromette-una-ricognizione-time-sensitive)
- [Scenario 3: Bridge bloccati durante un audit in paese con censura](#scenario-3-bridge-bloccati-durante-un-audit-in-paese-con-censura)
- [Scenario 4: Identificazione di relay sospetti nella catena con Relay Search](#scenario-4-identificazione-di-relay-sospetti-nella-catena-con-relay-search)

---

## Scenario 1: Exit malevolo inietta JavaScript durante un assessment

### Contesto

Durante un web application assessment, il team usava Tor per testare le
difese del target da prospettive diverse. Analizzando le risposte HTTP,
un operatore ha notato un tag `<script>` non presente nel sorgente originale
del sito - iniettato solo quando il traffico passava da un exit specifico.

### Analisi

```bash
# 1. Identificare l'exit corrente
printf 'AUTHENTICATE "password"\r\nGETINFO circuit-status\r\nQUIT\r\n' \
  | nc 127.0.0.1 9051 | grep BUILT | head -1
# Output: 12 BUILT $AAAA~Guard,$BBBB~Middle,$CCCC~SuspectExit ...

# 2. Confrontare risposte con exit diversi
for i in $(seq 1 5); do
    printf 'AUTHENTICATE "password"\r\nSIGNAL NEWNYM\r\nQUIT\r\n' | nc 127.0.0.1 9051
    sleep 3
    proxychains curl -s http://target.example.com | sha256sum
done

# Le risposte hanno hash diversi quando passano dall'exit $CCCC
# → l'exit sta modificando il contenuto HTTP
```

### Verifica nel consenso

```bash
# Verificare se l'exit ha flag BadExit
proxychains curl -s http://128.31.0.34:9131/tor/status-vote/current/consensus \
  | grep -A1 "SuspectExit"
# Se NON ha BadExit → non ancora segnalato alle DA
```

### Mitigazione

```ini
# torrc - escludere l'exit specifico
ExcludeExitNodes $CCCC
```

Il team ha poi segnalato il relay alle Directory Authorities tramite
il canale bad-relays@lists.torproject.org.

### Lezione appresa

Un exit malevolo può modificare solo traffico **HTTP** non cifrato - il TLS
end-to-end protegge da questo attacco. Vedi [exit-nodes.md](exit-nodes.md)
per la lista dei rischi. La regola per ogni engagement: mai inviare dati
sensibili via HTTP attraverso Tor, anche per "semplici" test.

---

## Scenario 2: Guard lento compromette una ricognizione time-sensitive

### Contesto

Engagement di ricognizione con finestra temporale limitata (4 ore). L'operatore
aveva Tor configurato da settimane con lo stesso guard - che nel frattempo era
diventato sovraccarico (bandwidth scesa da 5 MB/s a 200 KB/s).

### Problema

Ogni richiesta HTTP impiegava 8-15 secondi invece dei soliti 2-3. L'operatore
stava perdendo tempo prezioso durante la finestra di ricognizione.

### Diagnosi

```bash
# Verificare il guard corrente
grep EntryGuard /var/lib/tor/state
# EntryGuard SlowRelay FINGERPRINT_SLOW DirCache

# Verificare la bandwidth del guard su Relay Search
torsocks curl -s "https://onionoo.torproject.org/details?lookup=FINGERPRINT_SLOW" \
  | python3 -c "
import json, sys
r = json.load(sys.stdin)['relays'][0]
print(f'Bandwidth: {r.get(\"observed_bandwidth\",0)//1024} KB/s')
print(f'Flags: {r.get(\"flags\",[])}')
"
# Output: Bandwidth: 180 KB/s  ← molto basso
```

### Soluzione (d'emergenza)

```bash
# Reset del guard (solo per emergenza operativa)
sudo systemctl stop tor@default.service
sudo rm /var/lib/tor/state
sudo systemctl start tor@default.service

# Verificare il nuovo guard
grep EntryGuard /var/lib/tor/state
# EntryGuard FastRelay FINGERPRINT_FAST DirCache

# Test velocità
time proxychains curl -s https://api.ipify.org
# real 0m2.1s  ← molto meglio
```

### Lezione appresa

La persistenza dei guard (vedi [guard-nodes.md](guard-nodes.md)) è una feature
di sicurezza - ma può diventare un problema operativo se il guard si degrada.
In un engagement time-sensitive, il reset del guard è giustificabile. In
condizioni normali, non va mai fatto perché espone alla possibilità di
selezionare un guard malevolo.

---

## Scenario 3: Bridge bloccati durante un audit in paese con censura

### Contesto

Il team operava in un paese che aveva appena implementato un nuovo sistema
DPI. I bridge obfs4 configurati nel torrc smettevano di funzionare ogni 4-6
ore - il DPI li identificava e bloccava gli IP.

### Analisi del pattern

```bash
# Log Tor durante il blocco
sudo journalctl -u tor@default.service -f
# [warn] Problem bootstrapping. Stuck at 5% (conn). Connection timed out to bridge X
# [warn] Problem bootstrapping. Stuck at 5% (conn). Connection timed out to bridge Y
# → Entrambi i bridge bloccati
```

Il DPI non bloccava obfs4 in sé (il protocollo è resistente), ma
identificava e blacklistava gli IP dei bridge dopo un periodo di osservazione.

### Strategia multi-livello

```ini
# Giorno 1-2: obfs4 con iat-mode=2 (massimo offuscamento timing)
Bridge obfs4 IP1:PORT1 FP1 cert=CERT1 iat-mode=2
Bridge obfs4 IP2:PORT2 FP2 cert=CERT2 iat-mode=2

# Quando bloccati: Snowflake (IP cambiano costantemente)
ClientTransportPlugin snowflake exec /usr/bin/snowflake-client
Bridge snowflake 192.0.2.3:80 ...

# Fallback finale: meek-azure (traffico indistinguibile da Azure CDN)
ClientTransportPlugin meek_lite exec /usr/bin/obfs4proxy
Bridge meek_lite 0.0.2.0:2 ... url=https://meek.azureedge.net/
```

Il team manteneva 3 configurazioni torrc pronte e switchava al bisogno:
```bash
sudo cp /etc/tor/torrc.obfs4 /etc/tor/torrc && sudo systemctl restart tor
sudo cp /etc/tor/torrc.snowflake /etc/tor/torrc && sudo systemctl restart tor
sudo cp /etc/tor/torrc.meek /etc/tor/torrc && sudo systemctl restart tor
```

### Lezione appresa

La resistenza alla censura non è binaria - va gestita come difesa in profondità.
Il confronto tra transports (vedi [bridge-configurazione-e-alternative.md](bridge-configurazione-e-alternative.md))
mostra che ogni transport ha vantaggi in scenari diversi. Preparare configurazioni
multiple prima dell'engagement è essenziale.

---

## Scenario 4: Identificazione di relay sospetti nella catena con Relay Search

### Contesto

Threat intelligence engagement: il team monitorava traffico di un threat actor
che utilizzava onion services. Analizzando i circuiti con Nyx, hanno notato che
un middle relay appariva con frequenza anomala nei circuiti - statisticamente
improbabile data la dimensione della rete.

### Analisi con Onionoo API

```bash
# Relay visto in troppi circuiti
SUSPECT_FP="AABBCCDD11223344..."

torsocks curl -s "https://onionoo.torproject.org/details?lookup=$SUSPECT_FP" \
  | python3 -c "
import json, sys
r = json.load(sys.stdin)['relays'][0]
print(f'Nickname: {r[\"nickname\"]}')
print(f'AS: {r.get(\"as\",\"?\")}')
print(f'Contact: {r.get(\"contact\",\"none\")}')
print(f'Bandwidth: {r.get(\"observed_bandwidth\",0)//1024} KB/s')
print(f'First seen: {r.get(\"first_seen\",\"?\")}')
print(f'Family: {r.get(\"effective_family\",[])}')
"
```

### Indicatori di relay sospetto

- **Bandwidth molto alta** senza motivo apparente (gonfiata per attrarre traffico)
- **First seen** recente + bandwidth alta = possibile Sybil attack
- **Nessun contact info** + bandwidth alta = sospetto
- **Stessa /16 subnet** di altri relay dello stesso operatore (MyFamily non dichiarato)
- **Effective family** vuota ma relay sullo stesso AS = non dichiarano MyFamily

### Mitigazione

```ini
# torrc - escludere relay sospetti
ExcludeNodes $AABBCCDD11223344...
```

### Lezione appresa

Il monitoring dei relay (vedi [relay-monitoring-e-metriche.md](relay-monitoring-e-metriche.md)
e [monitoring-avanzato.md](monitoring-avanzato.md)) non è solo per chi opera relay.
Durante threat intelligence, verificare i nodi nella catena è parte dell'OPSEC.
Relay Search e Onionoo API sono strumenti che ogni pentester dovrebbe conoscere.

---

## Riepilogo

| Scenario | Nodo coinvolto | Rischio mitigato |
|----------|---------------|------------------|
| Exit malevolo | Exit Node | Content injection su HTTP |
| Guard lento | Guard Node | Performance degradata in finestra operativa |
| Bridge bloccati | Bridge/PT | Censura DPI progressiva |
| Relay sospetto | Middle Relay | Sybil attack, correlazione |

---

## Vedi anche

- [Exit Nodes](exit-nodes.md) - Ruolo, rischi, exit policy
- [Guard Nodes](guard-nodes.md) - Persistenza, selezione, attacchi
- [Bridges e Pluggable Transports](bridges-e-pluggable-transports.md) - obfs4, resistenza censura
- [Monitoring Avanzato](monitoring-avanzato.md) - Relay Search, OONI, script
- [Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md) - Sybil, exit malevoli, correlazione
