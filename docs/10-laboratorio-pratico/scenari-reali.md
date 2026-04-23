> **Lingua / Language**: Italiano | [English](../en/10-laboratorio-pratico/scenari-reali.md)

# Scenari Reali - Laboratorio Pratico in Contesto Operativo

Casi in cui le competenze pratiche dei laboratori (setup, analisi
circuiti, DNS leak testing, onion service, stream isolation) hanno
fatto la differenza durante operazioni reali.

---

## Indice

- [Scenario 1: Bootstrap fallito blocca un engagement - debug con le skill del Lab 01](#scenario-1-bootstrap-fallito-blocca-un-engagement--debug-con-le-skill-del-lab-01)
- [Scenario 2: Analisi circuiti rivela relay sospetto durante operazione](#scenario-2-analisi-circuiti-rivela-relay-sospetto-durante-operazione)
- [Scenario 3: DNS leak test pre-engagement evita compromissione](#scenario-3-dns-leak-test-pre-engagement-evita-compromissione)

---

## Scenario 1: Bootstrap fallito blocca un engagement - debug con le skill del Lab 01

### Contesto

Un operatore doveva avviare Tor su una macchina di test in una rete
aziendale con proxy HTTP obbligatorio. Tor non riusciva a fare bootstrap
e l'engagement era bloccato.

### Problema

```bash
sudo systemctl start tor
journalctl -u tor@default -n 20
# [warn] Proxy Client: unable to connect to 127.0.0.1:9050
# [warn] Problem bootstrapping. Stuck at 5% (conn)
# → La rete aziendale blocca le connessioni dirette alle porte Tor
# → Il proxy HTTP aziendale è obbligatorio per tutto il traffico
```

### Fix (competenze Lab 01)

```bash
# 1. Identificare il proxy aziendale
echo $http_proxy
# http://proxy.azienda.local:8080

# 2. Configurare Tor per usare il proxy aziendale come bridge
# /etc/tor/torrc:
UseBridges 1
Bridge obfs4 [bridge address from bridges.torproject.org]
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

# Se il proxy richiede autenticazione:
HTTPSProxy proxy.azienda.local:8080
HTTPSProxyAuthenticator user:password

# 3. Riavviare e verificare bootstrap
sudo systemctl restart tor
watch -n 1 'cat /var/lib/tor/state | grep Bootstrap'
# Bootstrapped 100% (done)
```

### Lezione appresa

La capacità di diagnosticare bootstrap failure e configurare bridge/proxy
è fondamentale per operare in reti restrittive. Il Lab 01 insegna
esattamente queste skill: verificare lo stato del servizio, leggere i
log, configurare torrc per ambienti diversi.

---

## Scenario 2: Analisi circuiti rivela relay sospetto durante operazione

### Contesto

Durante un'operazione OSINT prolungata (3 settimane), un analista
monitorava i circuiti con Nyx come routine quotidiana (skill Lab 02).
Ha notato un pattern anomalo.

### Problema

```
Osservazione su Nyx:
  - Lo stesso middle relay appariva nel 40% dei circuiti
  - Relay: "SuspiciousRelay1234" (nickname generico)
  - AS: hosting provider economico nell'Est Europa
  - Bandwidth dichiarata: molto alta (attraeva traffico)
  - Uptime: 2 settimane (nuovo nella rete)

Pattern anomalo:
  - Un relay legittimo non dovrebbe apparire così frequentemente
  - Alta bandwidth + recente → possibile Sybil relay
  - Posizione middle: può osservare il Guard scelto
```

### Azione

```bash
# 1. Escludere il relay sospetto
# /etc/tor/torrc:
ExcludeNodes $FINGERPRINT_RELAY_SOSPETTO
# Riavviare Tor

# 2. Segnalare al Tor Project
# Email a bad-relays@lists.torproject.org con:
# - Fingerprint del relay
# - Pattern osservato (frequenza anomala)
# - Periodo di osservazione
# - Screenshot Nyx (opzionale)

# 3. Verificare che i circuiti non lo usino più
nyx  # → lista circuiti, verificare assenza del relay
```

### Lezione appresa

Il monitoraggio attivo dei circuiti con Nyx (Lab 02) non è solo
didattico - è OPSEC operativa. Relay sospetti possono essere
identificati da pattern anomali di selezione. La segnalazione al Tor
Project aiuta a proteggere tutta la rete. Vedi
[Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md) per i
dettagli sugli attacchi Sybil e KAX17.

---

## Scenario 3: DNS leak test pre-engagement evita compromissione

### Contesto

Un team di pentest aveva una checklist pre-engagement che includeva
il DNS leak test (skill Lab 03) prima di qualsiasi attività via Tor.
Prima di un engagement su un target sensibile (settore finanziario),
l'operatore ha eseguito il test di routine.

### Problema

```bash
# Test DNS leak pre-engagement:
sudo tcpdump -i eth0 port 53 -n &
proxychains curl -s https://check.torproject.org/ > /dev/null

# tcpdump output:
# 09:01:15 IP 192.168.1.50.41234 > 192.168.1.1.53: A? check.torproject.org
# → DNS LEAK! Il resolver del sistema sta risolvendo in chiaro

# Causa: un aggiornamento di sistema ha resettato /etc/resolv.conf
# systemd-resolved aveva ripreso il controllo del DNS
# proxychains proxy_dns era configurato ma resolv.conf puntava
# al resolver locale che usciva in chiaro
```

Se l'operatore non avesse eseguito il test, le query DNS per i domini
del target sarebbero uscite in chiaro verso il resolver dell'ISP,
rivelando che qualcuno stava investigando il target.

### Fix

```bash
# 1. Forzare DNS via Tor
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
# Con DNSPort 5353 in torrc + dnsmasq che forwarda a 127.0.0.1:5353

# 2. Bloccare DNS diretto con iptables
sudo iptables -A OUTPUT -p udp --dport 53 -j DROP
sudo iptables -A OUTPUT -p tcp --dport 53 -j DROP
# Eccezione per Tor stesso (uid debian-tor)
sudo iptables -I OUTPUT -m owner --uid-owner debian-tor -j ACCEPT

# 3. Re-test
sudo tcpdump -i eth0 port 53 -n &
proxychains curl -s https://check.torproject.org/ > /dev/null
# tcpdump: nessun output → DNS leak risolto
```

### Lezione appresa

Il DNS leak test (Lab 03) deve essere nella checklist pre-engagement,
non solo un esercizio didattico. Aggiornamenti di sistema, reset di
configurazione, e modifiche a systemd-resolved possono reintrodurre
leak DNS silenziosamente. Vedi [DNS Leak](../05-sicurezza-operativa/dns-leak.md)
per tutti gli scenari di leak.

---

## Riepilogo

| Scenario | Lab correlato | Rischio mitigato |
|----------|---------------|------------------|
| Bootstrap fallito in rete aziendale | Lab 01 - Setup | Engagement bloccato per configurazione |
| Relay sospetto nei circuiti | Lab 02 - Analisi circuiti | Possibile Sybil/sorveglianza relay |
| DNS leak pre-engagement | Lab 03 - DNS Leak Testing | Query DNS in chiaro verso target |

---

## Vedi anche

- [Lab 01 - Setup e Verifica](lab-01-setup-e-verifica.md)
- [Lab 02 - Analisi Circuiti](lab-02-analisi-circuiti.md)
- [Lab 03 - DNS Leak Testing](lab-03-dns-leak-testing.md)
- [Lab 04 - Onion Service](lab-04-onion-service.md)
- [Lab 05 - Stream Isolation](lab-05-stream-isolation.md)
