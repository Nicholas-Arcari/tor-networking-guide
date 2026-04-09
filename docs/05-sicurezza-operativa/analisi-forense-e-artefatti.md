# Analisi Forense e Artefatti Tor

Questo documento analizza gli artefatti che Tor lascia su un sistema dal punto
di vista di un analista forense. Comprendere cosa Tor scrive su disco, in memoria,
e nei log è essenziale sia per chi vuole minimizzare le tracce sia per chi deve
investigare l'uso di Tor su un sistema.

> **Vedi anche**: [OPSEC e Errori Comuni](./opsec-e-errori-comuni.md) per errori
> operativi, [Hardening di Sistema](./hardening-sistema.md) per mitigazioni,
> [Isolamento e Compartimentazione](./isolamento-e-compartimentazione.md) per
> ambienti amnestici.

---
 
## Indice

- [Prospettiva dell'analisi forense](#prospettiva-dellanalisi-forense)
- [Artefatti su disco](#artefatti-su-disco)
- [Artefatti nei log di sistema](#artefatti-nei-log-di-sistema)
- [Artefatti in memoria (RAM)](#artefatti-in-memoria-ram)
- [Artefatti di rete](#artefatti-di-rete)
**Approfondimenti** (file dedicati):
- [Analisi Forense - Browser, Mitigazione e Strumenti](forense-browser-e-mitigazione.md) - Browser, timeline, mitigazione, strumenti

---

## Prospettiva dell'analisi forense

Un analista forense che esamina un sistema cerca evidenze che rispondano a:

1. **Tor è installato?** → pacchetti, binari, configurazione
2. **Tor è stato usato?** → log, state file, cache, timestamp
3. **Quando è stato usato?** → log timestamp, file modification times
4. **Come è stato configurato?** → torrc, bridge, exit policy
5. **Cosa è stato fatto via Tor?** → cache browser, history, download

La risposta a queste domande dipende dalla configurazione e dalle misure
di minimizzazione adottate dall'utente.

---

## Artefatti su disco

### Directory Tor

```
/var/lib/tor/                          ← DataDirectory principale
├── cached-certs                       ← Certificati Directory Authorities
├── cached-microdesc-consensus         ← Ultimo consenso scaricato
├── cached-microdescs                  ← Microdescriptor dei relay
├── cached-microdescs.new              ← Buffer per nuovi microdescriptor
├── state                              ← File di stato persistente
├── lock                               ← Lock file (indica Tor in esecuzione)
├── keys/                              ← Chiavi del relay (se configurato)
│   ├── ed25519_master_id_secret_key
│   ├── ed25519_signing_secret_key
│   └── secret_onion_key_ntor
└── hidden_service/                    ← Directory onion service (se configurato)
    ├── hostname                       ← Indirizzo .onion
    ├── hs_ed25519_public_key
    └── hs_ed25519_secret_key
```

### File state - informazioni critiche

Il file `state` contiene informazioni persistenti:

```
# /var/lib/tor/state
TorVersion 0.4.8.10
LastWritten 2024-12-15 09:23:41
TotalBuildTimes ...
CircuitBuildAbandonedCount 3
Guard in EntryGuard MyGuardNode AABBCCDD... DirCache ...
  ↑ Nome e fingerprint del guard scelto
  ↑ Rivela quale guard hai usato (correlabile con timing)

TransportProxy obfs4 exec /usr/bin/obfs4proxy
  ↑ Rivela uso di bridge obfs4
```

**Significato forense**: il file state rivela:
- Versione esatta di Tor usata
- Ultimo utilizzo (LastWritten timestamp)
- Guard node scelto (fingerprint → IP ricavabile dal consenso)
- Se vengono usati bridge e pluggable transport

### Consenso cached

```
/var/lib/tor/cached-microdesc-consensus
```

Contiene l'intero consenso della rete Tor (lista di tutti i relay).
Non è di per sé incriminante, ma conferma che Tor è stato usato
e indica la data dell'ultimo download del consenso.

### Configurazione torrc

```
/etc/tor/torrc
/etc/tor/instances/*/torrc
```

Rivela:
- Porte configurate (SocksPort, ControlPort, DNSPort)
- Bridge utilizzati (indirizzi IP e fingerprint)
- Policy di exit (se relay)
- Hidden service configurati
- Stream isolation settings

**I bridge nel torrc sono particolarmente sensibili**: contengono IP di bridge
che possono essere correlati con l'identità dell'utente (chi ha richiesto
quei bridge specifici?).

### Tor Browser

```
~/tor-browser/
├── Browser/
│   ├── TorBrowser/
│   │   ├── Data/
│   │   │   ├── Browser/profile.default/
│   │   │   │   ├── bookmarks.html          ← segnalibri
│   │   │   │   ├── places.sqlite           ← history + bookmarks DB
│   │   │   │   ├── cookies.sqlite          ← cookie (dovrebbe essere vuoto)
│   │   │   │   ├── formhistory.sqlite      ← form history
│   │   │   │   ├── permissions.sqlite      ← permessi siti
│   │   │   │   ├── webappsstore.sqlite     ← localStorage
│   │   │   │   └── cache2/                 ← cache HTTP
│   │   │   └── Tor/
│   │   │       ├── torrc                   ← config Tor integrato
│   │   │       └── data/                   ← state, consenso, etc.
│   │   └── UpdateInfo/
│   └── start-tor-browser
└── Desktop/
```

Tor Browser è progettato per minimizzare gli artefatti:
- History e cookie vengono cancellati alla chiusura
- Cache in RAM (non su disco per default)
- Ma: il download della directory Tor Browser stessa è evidenza

### Pacchetti installati

```bash
# Evidenza di installazione Tor
dpkg -l | grep -i tor
# ii  tor         0.4.8.10-1  amd64  anonymizing overlay network
# ii  tor-geoipdb  0.4.8.10-1  all    GeoIP database for Tor
# ii  obfs4proxy   0.0.14-1   amd64  pluggable transport proxy
# ii  nyx          2.1.0-2    all    command-line Tor relay monitor
# ii  torsocks     2.4.0-1    amd64  use SOCKS-friendly apps with Tor

# Anche apt history rivela quando Tor è stato installato:
grep -i tor /var/log/apt/history.log
```

---

## Artefatti nei log di sistema

### journalctl / syslog

```bash
# Log del servizio Tor
sudo journalctl -u tor@default.service

# Contiene:
# - Timestamp di ogni avvio/arresto
# - Bootstrap messages (conferma connessione)
# - NEWNYM events
# - Warning ed errori
# - Bridge connection attempts
```

Esempio di log incriminante:

```
Dec 15 09:23:01 kali tor[1234]: Bootstrapped 0% (starting): Starting
Dec 15 09:23:05 kali tor[1234]: Bootstrapped 10% (conn_pt): ...
  ↑ "conn_pt" rivela uso di pluggable transport (bridge)
Dec 15 09:23:41 kali tor[1234]: Bootstrapped 100% (done): Done
  ↑ Timestamp esatto di quando Tor è diventato operativo
Dec 15 14:32:15 kali tor[1234]: Received reload signal (hup). ...
Dec 15 14:32:20 kali tor[1234]: NEWNYM command received.
  ↑ Timestamp di cambio identità → correlabile con attività
```

### auth.log

```bash
# Accessi al gruppo debian-tor
grep debian-tor /var/log/auth.log
# Rivela quali utenti hanno accesso al ControlPort
```

### Log di iptables

```bash
# Se il transparent proxy con logging è attivo
grep "TOR-DROP" /var/log/kern.log
# Rivela tentativi di connessione bloccati
```

---

## Artefatti in memoria (RAM)

### Cosa Tor tiene in RAM

Quando Tor è in esecuzione, la RAM contiene:

- **Chiavi di circuito correnti**: le chiavi AES-128-CTR per ogni hop
- **Tabella dei circuiti**: ID circuito → nodi → stream associati
- **Cache DNS**: hostname → IP risolti via Tor
- **Contenuto dei buffer**: dati in transito nei circuiti
- **Consenso**: lista completa dei relay con flag e bandwidth
- **State in memoria**: guard scelti, circuit build times

### RAM forensics

Un dump della RAM (es. via LiME su Linux) può rivelare:

```
# Stringhe in memoria rilevanti
strings /proc/$(pgrep -f "tor")/mem | grep -i "onion\|circuit\|guard\|relay"

# Nota: richiede root e ptrace non ristretto
```

Dati potenzialmente recuperabili:
- URL .onion visitati (se Tor Browser è aperto)
- Hostname risolti via DNS
- Chiavi di sessione (se catturate prima della deallocazione)
- Contenuto parziale di pagine web in buffer

### Mitigazione RAM

- `kernel.yama.ptrace_scope = 2` → impedisce ptrace (dump memoria)
- Disabilitare crash dump → no core files
- Swap cifrata o disabilitata → no paginazione su disco
- Tails: usa RAM solo, nessuna persistenza

---

## Artefatti di rete

### Traffic capture

Un osservatore di rete (ISP, amministratore LAN) vede:

```
Connessione diretta a Tor (senza bridge):
  IP_locale:porta_random → IP_guard:9001 (TLS)
  ↑ Il certificato TLS del guard contiene la chiave Tor
  ↑ Identificabile come traffico Tor tramite:
    - Porta 9001 (OR port standard)
    - Certificato TLS con formato specifico
    - Pattern di traffico (celle da 514 byte)

Con bridge obfs4:
  IP_locale:porta_random → IP_bridge:porta_random
  ↑ Traffico offuscato, NON identificabile come Tor
  ↑ Ma: l'IP del bridge è noto (se l'ISP conosce i bridge)
```

### Conntrack / netstat history

```bash
# Connessioni correnti (mentre Tor è attivo)
ss -tnp | grep tor
# tcp  ESTAB  127.0.0.1:45678  198.51.100.42:9001  users:(("tor",pid=1234))
# ↑ Rivela l'IP del guard in uso
```

### DNS leak evidence

```bash
# Se c'è stato un DNS leak, il DNS server dell'ISP ha i log:
# ISP log: "2024-12-15 14:32:15 IP_cliente query target-site.com"
# Questo è permanente e al di fuori del controllo dell'utente
```

---

---

> **Continua in**: [Analisi Forense - Browser, Mitigazione e Strumenti](forense-browser-e-mitigazione.md)
> per artefatti browser, proxychains/torsocks, timeline, mitigazione e strumenti forensi.

---

## Vedi anche

- [Analisi Forense - Browser, Mitigazione e Strumenti](forense-browser-e-mitigazione.md) - Browser, timeline, mitigazione, strumenti
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - Errori che lasciano tracce forensi
- [Hardening di Sistema](hardening-sistema.md) - Ridurre la superficie forense con sysctl e AppArmor
- [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) - Tails, Whonix, Qubes per amnesia
- [DNS Leak](dns-leak.md) - Artefatti DNS nei log di sistema
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
