# Incident Response - Compromissione e Recupero

Questo documento analizza come gestire incidenti di sicurezza legati all'uso di Tor:
compromissione del guard, leak dell'IP reale, exit node malevoli, e procedure di
recupero post-incidente.

> **Vedi anche**: [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) per la selezione guard,
> [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md),
> [Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md),
> [Analisi Forense e Artefatti](../05-sicurezza-operativa/analisi-forense-e-artefatti.md).

---

## Indice

- [Tipi di incidenti Tor](#tipi-di-incidenti-tor)
- [Incidente 1: IP leak](#incidente-1-ip-leak)
- [Incidente 2: Guard compromesso](#incidente-2-guard-compromesso)
- [Incidente 3: Exit node malevolo](#incidente-3-exit-node-malevolo)
- [Incidente 4: DNS leak scoperto](#incidente-4-dns-leak-scoperto)
- [Incidente 5: Deanonimizzazione parziale](#incidente-5-deanonimizzazione-parziale)
- [Procedure di recupero generiche](#procedure-di-recupero-generiche)
- [Prevenzione: monitoring continuo](#prevenzione-monitoring-continuo)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Tipi di incidenti Tor

### Classificazione per gravità

| Gravità | Tipo | Esempio | Azione |
|---------|------|---------|--------|
| **Critica** | IP leak durante attività sensibile | WebRTC leak, DNS leak | Stop immediato, valutare danno |
| **Alta** | Guard compromesso/malevolo | Guard logga il tuo IP | Rotazione guard, cambio identità |
| **Alta** | Exit malevolo | SSL stripping, injection | Cambiare circuito, verificare dati |
| **Media** | DNS leak non correlabile | DNS query al ISP senza contesto | Fix configurazione, verificare |
| **Bassa** | Fingerprinting browser | Canvas fingerprint leakato | Rivedere config browser |

---

## Incidente 1: IP leak

### Rilevamento

```bash
# Scopri un leak durante una sessione:
# 1. Tcpdump mostra traffico diretto (non via Tor)
sudo tcpdump -i eth0 -n 'not port 9001 and not port 443 and host not 127.0.0.1'
# Output: pacchetti verso IP esterni → LEAK ATTIVO

# 2. Un sito mostra il tuo IP reale invece dell'exit Tor
proxychains curl https://api.ipify.org
# → mostra il tuo IP REALE → LEAK!

# 3. WebRTC leak rilevato
# Il browser ha esposto l'IP locale via WebRTC
```

### Risposta immediata (primi 60 secondi)

```bash
# 1. STOP: interrompere TUTTA l'attività
# Chiudere il browser immediatamente

# 2. CONTAIN: bloccare il traffico diretto
iptables -A OUTPUT -j DROP  # blocca tutto
iptables -I OUTPUT -m owner --uid-owner $(id -u debian-tor) -j ACCEPT  # solo Tor
iptables -I OUTPUT -d 127.0.0.0/8 -j ACCEPT  # localhost

# 3. VERIFY: confermare che il leak sia fermato
sudo tcpdump -i eth0 -c 10 -n 'not port 9001 and not port 443'
# Deve essere silenzioso ora
```

### Analisi del danno

Domande da rispondere:
1. **Per quanto tempo è durato il leak?** → controllare log, timestamp
2. **Quali dati sono stati esposti?** → URL visitati, DNS queries
3. **Chi poteva osservare?** → ISP, rete locale, server di destinazione
4. **Il leak è correlabile con l'attività Tor?** → timing, destinazione

```bash
# Verificare log DNS dell'ISP (non accessibili, ma stimare dal timing)
# Se hai tcpdump attivo, analizzare la cattura:
tcpdump -r capture.pcap -n 'port 53' | head -20
# Mostra le query DNS leakate

# Verificare la shell history per capire cosa stavi facendo
tail -50 ~/.zsh_history
```

### Recupero

```
Se il leak è stato breve e non critico:
  → Fix la causa (configurazione, disabilitare WebRTC, etc.)
  → NEWNYM per dissociare la sessione
  → Continuare con precauzioni aggiuntive

Se il leak è stato significativo:
  → Cambiare guard (eliminare /var/lib/tor/state)
  → Considerare l'attività anonima come compromessa
  → NON accedere agli stessi servizi dallo stesso setup
  → Valutare se l'identità collegata deve essere abbandonata
```

---

## Incidente 2: Guard compromesso

### Come sapere se il guard è compromesso

Non puoi saperlo con certezza. Segnali indiretti:

| Segnale | Possibile causa | Verifica |
|---------|----------------|----------|
| Guard rimosso dal consenso con flag `BadExit` | Comportamento malevolo rilevato | Controllare Relay Search |
| Guard sparito dal consenso | Offline, rimosso, o compromesso | Controllare metrics.torproject.org |
| Notifica di relay malevolo dalla community | Report pubblico | Controllare tor-relays mailing list |
| Path bias warnings nei log | Circuiti che falliscono troppo spesso | `journalctl -u tor | grep "path bias"` |

### Risposta

```bash
# 1. Verificare quale guard stai usando
cat /var/lib/tor/state | grep "^Guard"
# Guard in EntryGuard MyGuardName AABBCCDD... ...

# 2. Verificare lo stato del guard nel consenso
# Via ControlPort:
echo -e "AUTHENTICATE\r\nGETINFO ns/id/AABBCCDD...\r\nQUIT\r\n" | nc 127.0.0.1 9051
# Se non trovato → il guard è stato rimosso dal consenso

# 3. Forzare rotazione del guard
sudo systemctl stop tor@default.service

# Rimuovere le informazioni sul guard (forza nuova selezione)
sudo rm /var/lib/tor/state

# Riavviare
sudo systemctl start tor@default.service
# Tor selezionerà un nuovo guard

# 4. Verificare il nuovo guard
cat /var/lib/tor/state | grep "^Guard"
```

### Implicazioni

Se il guard era effettivamente malevolo:
- Ha visto il tuo IP reale (sempre, per ogni connessione)
- Ha visto il timing di ogni circuito (ma non la destinazione)
- Potrebbe aver correlato il tuo IP con pattern di traffico
- **Non** ha visto il contenuto dei circuiti (cifrato)
- **Non** ha visto la destinazione (solo il middle la vede cifrata)

---

## Incidente 3: Exit node malevolo

### Rilevamento

```bash
# Segnali di exit malevolo:
# 1. Certificato TLS diverso dall'atteso (SSL stripping)
# 2. Contenuto modificato (injection HTML/JS)
# 3. Redirect non attesi

# Verifica certificato
proxychains curl -sv https://target.com 2>&1 | grep "SSL certificate"
# Confronta con il certificato atteso

# Verifica integrità risposta
proxychains curl -s https://target.com | sha256sum
# Confronta con hash noto
```

### Tipi di attacco dell'exit malevolo

```
1. SSL Stripping:
   Tu → Tor → Exit → HTTPS downgrade a HTTP → target
   Exit vede: tutto il traffico in chiaro
   Rilevamento: browser non mostra lucchetto HTTPS

2. Injection:
   Tu → Tor → Exit → target risponde con HTML
   Exit modifica HTML aggiungendo <script> malevolo
   Rilevamento: hash contenuto diverso, script sconosciuti

3. DNS spoofing:
   Tu → Tor → Exit → risolve target.com → IP falso
   Rilevamento: IP diverso dall'atteso

4. Credential harvesting:
   Exit logga credenziali HTTP non cifrate
   Rilevamento: impossibile da rilevare in tempo reale
```

### Risposta

```bash
# 1. Cambiare circuito immediatamente
echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051

# 2. Identificare l'exit malevolo
# Dalle connessioni in Nyx:
nyx
# Schermata Connections → nota il fingerprint dell'exit prima del NEWNYM

# 3. Segnalare
# Email: bad-relays@lists.torproject.org
# GitLab: https://gitlab.torproject.org/tpo/network-health/team/-/issues

# 4. Cambiare credenziali se esposte
# Se hai inviato password via HTTP (non HTTPS) → cambiarle TUTTE
```

### Prevenzione

- **Usare SEMPRE HTTPS**: Tor protegge il routing, non il contenuto
- **HSTS**: verificare che i siti critici usino HSTS
- **Verificare certificati**: confrontare fingerprint dei certificati
- **Non inserire credenziali via HTTP**: mai, specialmente via Tor

---

## Incidente 4: DNS leak scoperto

### Rilevamento

```bash
# 1. Tcpdump mostra query DNS in uscita
sudo tcpdump -i eth0 -n port 53
# Se vedi pacchetti → DNS LEAK ATTIVO

# 2. Test online
proxychains curl -s https://check.torproject.org/api/ip
# Confrontare con:
curl -s https://api.ipify.org  # IP diretto
# Se diversi ma DNS risolve gli stessi hostname → leak DNS
```

### Risposta

```bash
# 1. Bloccare DNS diretto immediatamente
iptables -I OUTPUT -p udp --dport 53 -j DROP
iptables -I OUTPUT -p tcp --dport 53 -j DROP
# Eccetto verso il DNSPort di Tor:
iptables -I OUTPUT -p udp --dport 53 -d 127.0.0.1 -j ACCEPT

# 2. Identificare la causa
# a. proxychains senza proxy_dns?
grep "proxy_dns" /etc/proxychains4.conf
# Se commentato → CAUSA TROVATA

# b. Firefox senza remote DNS?
# about:config → network.proxy.socks_remote_dns deve essere true

# c. Applicazione che bypassa il proxy?
# Alcune app fanno DNS diretto prima del connect()

# 3. Fixare la causa e verificare
sudo tcpdump -i eth0 -n port 53 -c 10
# Deve essere silenzioso
```

### Impatto

Un DNS leak rivela:
- **Quali siti stai visitando** (hostname nelle query DNS)
- **Timing delle visite** (timestamp delle query)
- **Pattern di navigazione** (sequenza di DNS queries)
- **Correlazione con traffico Tor** (DNS query + connessione Tor = tu)

Il danno dipende da chi osserva:
- ISP: vede tutte le query DNS → sa dove navighi
- Rete locale: se non cifrata, chiunque vede le query
- DNS server: logga le query (Google DNS, Cloudflare, ISP)

---

## Incidente 5: Deanonimizzazione parziale

### Scenari

```
Scenario: un sito ha determinato che sei "la stessa persona" di una visita
precedente (fingerprinting), ma non conosce la tua identità reale.

Gravità: media (non hanno il tuo IP, ma possono correlare attività)

Risposta:
  1. Nuova identità NEWNYM
  2. Modificare il fingerprint del browser:
     - Resize della finestra (window size è un vettore)
     - Cancellare cookie/localStorage
     - Cambiare User-Agent
  3. Per sessioni future: usare Tor Browser (migliore anti-fingerprinting)
```

```
Scenario: correlazione end-to-end (ISP vede connessione Tor + server vede
traffico → timing match).

Gravità: alta (potenzialmente possono identificarti)

Risposta:
  1. Non c'è rimedio retroattivo (il danno è fatto)
  2. Prevenzione futura: bridge obfs4 per nascondere l'uso di Tor all'ISP
  3. Padding: attivare ConnectionPadding 1 nel torrc
  4. Traffico di copertura: usare Tor anche per attività non sensibili
```

---

## Procedure di recupero generiche

### Procedura standard post-incidente

```
FASE 1: CONTENIMENTO (minuti)
  □ Interrompere l'attività in corso
  □ Attivare firewall restrittivo (solo Tor)
  □ Verificare con tcpdump che non ci siano leak attivi

FASE 2: ANALISI (ore)
  □ Determinare tipo e durata dell'incidente
  □ Identificare dati esposti
  □ Valutare chi poteva osservare
  □ Documentare timeline

FASE 3: RECUPERO (ore-giorni)
  □ Fixare la causa tecnica
  □ Cambiare credenziali compromesse
  □ Rotazione guard (se necessario)
  □ NEWNYM per dissociare la sessione
  □ Verificare la fix con testing

FASE 4: PREVENZIONE (continuo)
  □ Implementare monitoring (tcpdump, alerting)
  □ Aggiornare configurazione per prevenire recidiva
  □ Documentare l'incidente e la soluzione
  □ Review della configurazione complessiva
```

### Quando abbandonare un'identità

L'identità (onion address, pseudonimo, account) deve essere abbandonata quando:

- Il tuo IP reale è stato esposto in correlazione con l'identità
- Login a servizi identificabili (email reale, social) dalla stessa sessione
- L'avversario ha motivo e capacità di correlare (stato-nazione, ISP cooperante)
- L'OPSEC è stata violata in modo non recuperabile

---

## Prevenzione: monitoring continuo

### Script di monitoring

```bash
#!/bin/bash
# tor-leak-monitor.sh - Monitora leak in background

LOG="/var/log/tor-leak-monitor.log"

echo "$(date): Monitoring avviato" >> "$LOG"

while true; do
    # Verifica 1: DNS leak
    DNS_LEAK=$(sudo timeout 5 tcpdump -i eth0 -c 1 -n port 53 2>/dev/null)
    if [ -n "$DNS_LEAK" ]; then
        echo "$(date): ALERT - DNS LEAK RILEVATO: $DNS_LEAK" >> "$LOG"
        # Opzionale: notifica desktop
        notify-send "TOR ALERT" "DNS Leak rilevato!" 2>/dev/null
    fi
    
    # Verifica 2: traffico non-Tor
    NON_TOR=$(sudo timeout 5 tcpdump -i eth0 -c 1 -n \
        'not port 9001 and not port 443 and not port 80 and not arp and not port 53' 2>/dev/null)
    if [ -n "$NON_TOR" ]; then
        echo "$(date): ALERT - Traffico non-Tor: $NON_TOR" >> "$LOG"
    fi
    
    # Verifica 3: Tor è attivo
    if ! systemctl is-active --quiet tor@default.service; then
        echo "$(date): ALERT - Tor NON attivo!" >> "$LOG"
        notify-send "TOR ALERT" "Tor service down!" 2>/dev/null
    fi
    
    sleep 30
done
```

### Alerting automatico

```python
#!/usr/bin/env python3
"""Monitor Tor con alerting via ControlPort."""

import functools
from stem.control import Controller

def warn_handler(event):
    """Handler per warning ed errori."""
    if "circuit" in str(event.message).lower() and "failed" in str(event.message).lower():
        print(f"[ALERT] Circuit failure: {event.message}")
    if "path bias" in str(event.message).lower():
        print(f"[ALERT] Path bias: {event.message}")
    if "clock" in str(event.message).lower():
        print(f"[ALERT] Clock issue: {event.message}")

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    ctrl.add_event_listener(warn_handler, "WARN")
    ctrl.add_event_listener(warn_handler, "ERR")
    
    print("Monitoring attivo... (Ctrl+C per uscire)")
    import time
    while True:
        time.sleep(1)
```

---

## Nella mia esperienza

Il mio incidente più significativo è stato un DNS leak: avevo configurato
proxychains per Firefox ma non avevo abilitato `proxy_dns` nel file di
configurazione. Per settimane, ogni hostname che visitavo via "Tor" veniva
prima risolto in chiaro dal mio ISP (Comeser, Parma).

L'ho scoperto per caso, avviando `tcpdump -i eth0 port 53` per un test
diverso. Ho visto decine di query DNS in chiaro per i siti che stavo visitando
via proxychains. Il fix è stato semplice (decommentare `proxy_dns` in
`proxychains4.conf`), ma il danno era fatto: il mio ISP aveva un log completo
di tutti i siti visitati "via Tor" per settimane.

Da quell'esperienza ho imparato:
1. **Verificare SEMPRE con tcpdump** dopo aver configurato qualcosa
2. **Non fidarsi che "funziona"** - verificare che funziona CORRETTAMENTE
3. **Monitorare periodicamente** - i leak possono apparire dopo aggiornamenti
4. **Il DNS è il vettore di leak più comune** e più pericoloso

Ora il mio workflow include sempre una verifica post-configurazione:
```bash
# Dopo ogni modifica alla configurazione Tor:
sudo tcpdump -i eth0 -n port 53 -c 5 &
proxychains curl https://example.com > /dev/null 2>&1
# Se tcpdump mostra pacchetti → leak, fixare prima di usare
```

---

## Vedi anche

- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Prevenire gli incidenti
- [Analisi Forense e Artefatti](../05-sicurezza-operativa/analisi-forense-e-artefatti.md) - Cosa resta dopo un incidente
- [Verifica IP, DNS e Leak](../04-strumenti-operativi/verifica-ip-dns-e-leak.md) - Test completi post-incidente
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - Recovery dei circuiti
- [Attacchi Noti](../07-limitazioni-e-attacchi/attacchi-noti.md) - Scenari di attacco documentati
