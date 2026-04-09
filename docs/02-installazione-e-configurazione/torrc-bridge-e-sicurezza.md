# Bridge, Pluggable Transports e Direttive di Sicurezza nel torrc

Configurazione dei bridge obfs4, pluggable transports, e direttive di
sicurezza avanzate: selezione nodi, esclusioni, padding e restrizioni di rete.

Estratto da [torrc - Guida Completa](torrc-guida-completa.md).

---

## Indice

- [Bridge e Pluggable Transports](#bridge-e-pluggable-transports)
- [Direttive di sicurezza avanzate](#direttive-di-sicurezza-avanzate)

---

## Bridge e Pluggable Transports

### UseBridges

```ini
UseBridges 1
```

**Cosa fa**: dice a Tor di connettersi alla rete tramite bridge anziché tramite
relay pubblici. Tor non tenterà di connettersi direttamente ai guard nel consenso.

**Quando attivarlo**:
- L'ISP blocca le connessioni ai relay Tor noti
- Si vuole nascondere all'ISP l'uso di Tor
- La rete ha DPI che identifica e blocca il traffico Tor
- Si è in un paese con censura attiva

### ClientTransportPlugin

```ini
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
```

**Cosa fa**: registra `obfs4proxy` come pluggable transport disponibile. Quando Tor
deve connettersi a un bridge obfs4, invoca `/usr/bin/obfs4proxy` come processo
figlio.

**Dettagli interni**:
- Tor comunica con obfs4proxy tramite il protocollo PT (Pluggable Transport)
- obfs4proxy apre una porta locale (scelta dinamicamente)
- Tor si connette a questa porta locale
- obfs4proxy offusca il traffico e lo inoltra al bridge remoto
- Il bridge remoto ha un'istanza di obfs4proxy server-side che deoffusca

### Direttive Bridge

```ini
Bridge obfs4 <IP>:<PORT> <FINGERPRINT> cert=<CERT> iat-mode=<0|1|2>
```

**Componenti**:
- `obfs4` - tipo di pluggable transport
- `<IP>:<PORT>` - indirizzo del bridge (IPv4 o IPv6)
- `<FINGERPRINT>` - fingerprint del relay bridge (20 byte hex)
- `cert=<CERT>` - certificato obfs4 del bridge (base64)
- `iat-mode` - modalità di timing:
  - `0` - nessun padding temporale (più veloce, meno sicuro)
  - `1` - padding temporale moderato (raccomandato)
  - `2` - padding temporale massimo (più lento, massima resistenza a DPI)

**Nella mia esperienza**:
```ini
Bridge obfs4 xxx.xxx.xxx.xxx:4431 F829D395093B... cert=... iat-mode=0
Bridge obfs4 xxx.xxx.xxx.xxx:13630 A3D55AA6178... cert=... iat-mode=2
```

Ho configurato due bridge con iat-mode diversi. Il primo (iat-mode=0) è più veloce
e lo uso come primario. Il secondo (iat-mode=2) è il fallback per situazioni dove
il DPI è aggressivo.

**Come ottenere bridge**:
1. `https://bridges.torproject.org/options` - sito ufficiale (richiede CAPTCHA)
2. Email a `bridges@torproject.org` con corpo `get transport obfs4` (da Gmail o Riseup)
3. Snowflake - bridge tramite browser di volontari (meno stabile)

**Nota dalla mia esperienza**: inizialmente avevo usato un URL errato per i bridge
(`https://bridges.torproject.org/bridges`, suggerito da ChatGPT). L'URL corretto è
`https://bridges.torproject.org/options`. I bridge ricevuti vanno inseriti esattamente
come forniti, incluso il certificato completo.

---

## Direttive di sicurezza avanzate

### ExitNodes, EntryNodes, StrictNodes

```ini
# Forzare exit in un paese specifico
ExitNodes {de},{nl}
StrictNodes 1

# Escludere exit da certi paesi
ExcludeExitNodes {ru},{cn},{ir}

# Forzare entry specifici
EntryNodes {se},{ch}
```

**ATTENZIONE**: usare `ExitNodes` con `StrictNodes 1` è generalmente **sconsigliato**:
- Riduce drasticamente il pool di exit disponibili
- Aumenta la probabilità di saturazione dei pochi exit rimasti
- Rende il traffico più riconoscibile (fingerprinting: "questo utente esce sempre dalla Germania")
- Se i pochi exit disponibili sono offline, Tor non funziona

**Nella mia esperienza**, ho provato `ExitNodes {it}` per uscire con IP italiano.
Il risultato è stato:
- Pochissimi exit italiani disponibili
- Latenza peggiore (paradossalmente, perché i pochi exit erano sovraccarichi)
- Circuiti instabili
- Ho rimosso la direttiva e lasciato che Tor scelga liberamente

### ExcludeNodes

```ini
ExcludeNodes {cn},{ru},{ir},{kp}
```

**Cosa fa**: esclude completamente i relay in questi paesi da qualsiasi posizione
nel circuito (guard, middle, exit). Più ragionevole di `ExitNodes` perché non limita
a pochi relay ma ne esclude alcuni.

### MapAddress

```ini
MapAddress www.example.com www.example.com.torproject.org
MapAddress 10.0.0.0/8 0.0.0.0/8
```

**Cosa fa**: permette di redirezionare hostname o range IP a livello di Tor. Utile
per test o per forzare il routing di certe destinazioni.

### ReachableAddresses

```ini
ReachableAddresses *:80, *:443
ReachableAddresses reject *:*
```

**Cosa fa**: limita le porte verso cui Tor può connettersi per raggiungere i relay.
Utile se sei dietro un firewall che permette solo traffico HTTP/HTTPS.

**Dettaglio**: questo riguarda la connessione Tor→relay, non il traffico applicativo.
Se il tuo firewall permette solo porta 80 e 443, configuri `ReachableAddresses` di
conseguenza e Tor selezionerà solo relay con ORPort su quelle porte.

### ConnectionPadding

```ini
ConnectionPadding 1      # Abilita padding tra relay (default: auto)
ReducedConnectionPadding 0  # Non ridurre il padding (default)
```

**Cosa fa**: Tor invia celle di padding sulle connessioni tra relay per mascherare
i pattern di traffico. `ConnectionPadding 1` forza il padding anche quando non
sarebbe altrimenti attivato.

---

## Vedi anche

- [torrc - Guida Completa](torrc-guida-completa.md) - Struttura, porte, logging
- [Performance, Relay e Configurazione Completa](torrc-performance-e-relay.md) - Tuning, relay, hidden services
- [Bridges e Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Approfondimento su bridge e obfs4
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - Padding e resistenza alla traffic analysis
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
