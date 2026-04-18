> **Lingua / Language**: Italiano | [English](../en/02-installazione-e-configurazione/torrc-performance-e-relay.md)

# Performance, Relay e Configurazione Completa del torrc

Direttive di performance e tuning, configurazione come relay (middle, bridge, exit),
onion services, e configurazione torrc completa commentata.

Estratto da [torrc - Guida Completa](torrc-guida-completa.md).

---

## Indice

- [Performance e tuning](#performance-e-tuning)
- [Configurazione come relay](#configurazione-come-relay)
- [Hidden Services (Onion Services v3)](#hidden-services-onion-services-v3)
- [La mia configurazione completa](#la-mia-configurazione-completa)

---

## Performance e tuning

### CircuitBuildTimeout

```ini
CircuitBuildTimeout 60
```

**Cosa fa**: timeout in secondi per la costruzione di un circuito. Se un circuito non
viene costruito entro questo tempo, viene abbandonato e Tor ne prova un altro.

**Default**: Tor calcola dinamicamente questo valore basandosi sulle esperienze
passate. Impostarlo manualmente sovrascrive il calcolo adattivo.

### LearnCircuitBuildTimeout

```ini
LearnCircuitBuildTimeout 1
```

**Cosa fa**: permette a Tor di adattare il timeout basandosi sulle esperienze reali.
Se la rete è lenta (es. via bridge obfs4), Tor aumenta il timeout. Se è veloce, lo
riduce.

### NumEntryGuards

```ini
NumEntryGuards 1
```

**Cosa fa**: numero di guard persistenti da mantenere. Il default è 1 (prima era 3).

**Perché 1 è meglio di 3**: con un solo guard, c'è 1 possibilità su ~1000 che il
guard sia malevolo. Con 3 guard, ci sono 3 possibilità su ~1000. Meno guard = meno
rischio di avere un guard malevolo nel tempo.

### MaxCircuitDirtiness

```ini
MaxCircuitDirtiness 600
```

**Cosa fa**: tempo in secondi dopo il quale un circuito "dirty" (che ha trasportato
almeno uno stream) non viene riutilizzato per nuovi stream. Default: 600 (10 minuti).

**Implicazione**: dopo 10 minuti, le nuove connessioni useranno un nuovo circuito
(con potenzialmente un nuovo exit e un nuovo IP). Questo è il motivo per cui il tuo
IP visibile cambia periodicamente anche senza NEWNYM.

---

## Configurazione come relay

Queste direttive sono per chi vuole contribuire alla rete Tor operando un relay.
Non le ho attivate nella mia configurazione, ma le documento per completezza.

### ORPort

```ini
ORPort 9001
# oppure con binding specifico
ORPort 443 NoListen
ORPort 127.0.0.1:9001 NoAdvertise
```

**Cosa fa**: apre la porta Onion Router, che accetta connessioni da altri relay Tor.
Attivare ORPort trasforma il tuo sistema in un relay Tor.

### Relay Bandwidth

```ini
RelayBandwidthRate 1 MB    # Throttle a 1 MB/s
RelayBandwidthBurst 2 MB   # Burst fino a 2 MB/s
AccountingMax 500 GB       # Massimo 500 GB per periodo
AccountingStart month 1 00:00  # Periodo mensile
```

### Relay come bridge

```ini
BridgeRelay 1
PublishServerDescriptor 0   # Non pubblicare nel consenso (bridge privato)
ServerTransportPlugin obfs4 exec /usr/bin/obfs4proxy
ServerTransportListenAddr obfs4 0.0.0.0:8443
ExtORPort auto
```

### Exit Policy (se il relay è un exit)

```ini
# Permetti solo web
ExitPolicy accept *:80
ExitPolicy accept *:443
ExitPolicy reject *:*

# Oppure: restrittiva ma permetti servizi comuni
ExitPolicy accept *:20-23     # FTP, SSH, Telnet
ExitPolicy accept *:53        # DNS
ExitPolicy accept *:80        # HTTP
ExitPolicy accept *:443       # HTTPS
ExitPolicy accept *:993       # IMAPS
ExitPolicy accept *:995       # POP3S
ExitPolicy reject *:*
```

---

## Hidden Services (Onion Services v3)

```ini
HiddenServiceDir /var/lib/tor/hidden_service/
HiddenServicePort 80 127.0.0.1:8080
```

**Cosa fa**: configura un onion service che rende raggiungibile un servizio locale
(porta 8080) tramite un indirizzo `.onion` sulla porta 80.

**Dettagli interni**:
- Tor genera una coppia di chiavi Ed25519 in `HiddenServiceDir`
- L'indirizzo `.onion` è derivato dalla chiave pubblica (56 caratteri per v3)
- Tor pubblica dei descriptor cifrati sugli HSDir nella rete Tor
- I client che conoscono l'indirizzo `.onion` usano il descriptor per stabilire
  un circuito rendezvous

Questo viene approfondito nel documento dedicato agli onion services.

---

## La mia configurazione completa

Ecco il mio torrc completo, con commenti che spiegano ogni scelta:

```ini
# === Porte client ===
SocksPort 9050                    # Proxy SOCKS5 principale
DNSPort 5353                      # DNS via Tor
AutomapHostsOnResolve 1           # Mapping automatico .onion e hostname

# === Controllo ===
ControlPort 9051                  # Per NEWNYM e monitoring
CookieAuthentication 1            # Auth via cookie file

# === Sicurezza ===
ClientUseIPv6 0                   # No IPv6 (previene leak)

# === Dati ===
DataDirectory /var/lib/tor

# === Logging ===
Log notice file /var/log/tor/notices.log

# === Bridge obfs4 ===
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
Bridge obfs4 xxx.xxx.xxx.xxx:4431 F829D395093B... cert=... iat-mode=0
Bridge obfs4 xxx.xxx.xxx.xxx:13630 A3D55AA6178... cert=... iat-mode=2
```

Questa configurazione:
- Instrada il traffico attraverso bridge obfs4 (nasconde l'uso di Tor all'ISP)
- Previene DNS leak (DNSPort + AutomapHostsOnResolve)
- Previene IPv6 leak (ClientUseIPv6 0)
- Permette rotazione IP via ControlPort (NEWNYM)
- Logga a livello notice per troubleshooting senza compromettere privacy

---

## Vedi anche

- [torrc - Guida Completa](torrc-guida-completa.md) - Struttura, porte, logging
- [Bridge e Sicurezza nel torrc](torrc-bridge-e-sicurezza.md) - Bridge, pluggable transports, sicurezza
- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) - Approfondimento onion services
- [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - SocksPort multipli
- [Relay Monitoring e Metriche](../03-nodi-e-rete/relay-monitoring-e-metriche.md) - Monitoraggio relay
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
