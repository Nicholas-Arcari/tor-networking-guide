> **Lingua / Language**: Italiano | [English](../en/01-fondamenti/architettura-tor.md)

# Architettura di Tor - Analisi a Basso Livello

Questo documento descrive l'architettura interna della rete Tor con un livello di dettaglio
che va oltre la classica spiegazione "3 nodi e crittografia a cipolla". Qui analizziamo come
Tor funziona realmente a livello di protocollo, quali componenti software interagiscono,
come il daemon Tor gestisce connessioni, circuiti e stream, e quali sono le implicazioni
pratiche di ogni scelta architetturale.

Include note dalla mia esperienza diretta nell'uso di Tor su Kali Linux (Debian), con
proxychains, ControlPort, bridge obfs4 e script personalizzati.

---
---

## Indice

- [Visione d'insieme: cosa succede quando lanci Tor](#visione-dinsieme-cosa-succede-quando-lanci-tor)
- [I componenti dell'architettura Tor](#i-componenti-dellarchitettura-tor)

**Approfondimenti** (file dedicati):
- [Costruzione Circuiti](costruzione-circuiti.md) - Path selection, CREATE2/EXTEND2, ntor, celle, TLS
- [Isolamento e Modello di Minaccia](isolamento-e-modello-minaccia.md) - Stream isolation, ciclo vita circuiti, threat model


## Visione d'insieme: cosa succede quando lanci Tor

Quando esegui `sudo systemctl start tor@default.service`, il daemon `tor` compie queste
operazioni in sequenza:

1. **Lettura del torrc** - il file `/etc/tor/torrc` viene parsato. Ogni direttiva viene
   validata. Se c'è un errore sintattico, Tor si rifiuta di partire (verificabile con
   `tor -f /etc/tor/torrc --verify-config`).

2. **Apertura delle porte locali** - Tor apre i socket in ascolto:
   - `SocksPort 9050` - proxy SOCKS5 per applicazioni client
   - `DNSPort 5353` - resolver DNS locale che instrada query via Tor
   - `ControlPort 9051` - interfaccia di controllo per script e tool esterni

3. **Connessione alla rete Tor** - Il daemon contatta le Directory Authorities (o un
   fallback mirror) per scaricare il **consenso** (network consensus), un documento
   firmato che elenca tutti i relay attivi con le loro proprietà.

4. **Bootstrap** - Tor costruisce i primi circuiti. Il processo è visibile nei log:
   ```
   Bootstrapped 5% (conn): Connecting to a relay
   Bootstrapped 10% (conn_done): Connected to a relay
   Bootstrapped 14% (handshake): Handshaking with a relay
   Bootstrapped 15% (handshake_done): Handshake with a relay done
   Bootstrapped 75% (enough_dirinfo): Loaded enough directory info to build circuits
   Bootstrapped 90% (ap_handshake_done): Handshake finished with a relay to build circuits
   Bootstrapped 95% (circuit_create): Establishing a Tor circuit
   Bootstrapped 100% (done): Done
   ```

5. **Pronto per il traffico** - Una volta raggiunto il 100%, il SocksPort accetta
   connessioni. ProxyChains, curl, Firefox possono instradare traffico.

### Nella mia esperienza

Il bootstrap è il momento più critico. Ho visto fallimenti in diverse situazioni:

- **Bridge saturi**: quando i bridge obfs4 configurati nel torrc erano sovraccarichi,
  il bootstrap si bloccava al 10-15% con `Connection timed out`. Soluzione: richiedere
  bridge freschi da `https://bridges.torproject.org/options`.

- **DNS bloccato**: su alcune reti universitarie il DNS era filtrato, impedendo al daemon
  di risolvere i fallback directory. Con i bridge obfs4 il problema si aggirava perché
  la connessione avviene direttamente all'IP del bridge.

- **Orologio di sistema sballato**: Tor verifica i certificati TLS e il consenso ha una
  finestra temporale di validità. Se l'orologio è fuori di più di qualche ora, Tor rifiuta
  il consenso. Mi è capitato su una VM appena installata dove NTP non era configurato.

---

## I componenti dell'architettura Tor

### 1. Onion Proxy (OP) - Il client

L'Onion Proxy è il software che gira sulla macchina dell'utente. Su Linux è il daemon
`tor`. Le sue responsabilità sono:

- **Scaricare e mantenere il consenso aggiornato** - Il consenso viene refreshato ogni ora.
  Contiene la lista di tutti i relay con flag, bandwidth, exit policy, chiavi pubbliche.

- **Costruire circuiti** - L'OP seleziona i nodi (Guard, Middle, Exit) e negozia chiavi
  crittografiche con ciascuno attraverso l'handshake ntor.

- **Multiplexare stream su circuiti** - Un singolo circuito può trasportare più stream
  TCP simultanei. Ogni connessione SOCKS5 al port 9050 genera un nuovo stream, ma
  potrebbe riutilizzare un circuito esistente.

- **Gestire l'isolamento** - Tor decide quando creare nuovi circuiti in base a criteri
  di isolamento (per porta di destinazione, per indirizzo di origine SOCKS, etc.).

- **Esporre interfacce locali** - SocksPort, DNSPort, TransPort, ControlPort.

#### Dettaglio: il flusso di una richiesta SOCKS5

Quando proxychains esegue `curl https://api.ipify.org`:

```
1. curl → proxychains (LD_PRELOAD intercetta connect())
2. proxychains → 127.0.0.1:9050 (SOCKS5 handshake)
3. SOCKS5 CONNECT api.ipify.org:443
4. Tor daemon riceve la richiesta
5. Tor seleziona un circuito (o ne crea uno nuovo)
6. Tor crea uno stream sul circuito → RELAY_BEGIN cell
7. L'Exit Node apre una connessione TCP verso api.ipify.org:443
8. L'Exit Node risponde → RELAY_CONNECTED cell
9. Dati fluiscono bidirezionalmente attraverso celle RELAY_DATA
10. curl riceve la risposta (IP dell'exit node)
```

Nella mia esperienza, verifico questo flusso così:
```bash
> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
185.220.101.143
```

L'IP restituito è quello dell'Exit Node, non il mio (che è un IP italiano di Parma).

### 2. Directory Authorities (DA)

Le Directory Authorities sono 9 server hardcoded nel codice sorgente di Tor (+ 1 bridge
authority). Il loro ruolo è fondamentale:

- **Raccolgono i descriptor dei relay** - Ogni relay pubblica periodicamente un
  server descriptor contenente: chiavi pubbliche, exit policy, bandwidth dichiarata,
  famiglia di relay, contatto dell'operatore.

- **Votano il consenso** - Ogni ora, le DA votano su quali relay includere nel consenso
  e quali flag assegnare a ciascuno. Il risultato è un documento firmato dalla
  maggioranza delle DA.

- **Assegnano i flag** - I flag determinano il comportamento del relay nella rete:

  | Flag | Significato |
  |------|-------------|
  | `Guard` | Può essere usato come entry node |
  | `Exit` | Ha una exit policy che permette traffico in uscita |
  | `Stable` | Uptime lungo e affidabile |
  | `Fast` | Bandwidth sopra la mediana |
  | `HSDir` | Può ospitare descriptor di hidden service |
  | `V2Dir` | Supporta il protocollo directory v2 |
  | `Running` | Il relay è attualmente raggiungibile |
  | `Valid` | Il relay è stato verificato come funzionante |
  | `BadExit` | Exit node noto per comportamento malevolo |

- **Bandwidth Authorities** - Un sottoinsieme delle DA esegue misurazioni di bandwidth
  indipendenti (tramite il software `sbws`). Queste misurazioni sovrascrivono la
  bandwidth autodichiarata dai relay, prevenendo attacchi dove un relay malevolo
  dichiara bandwidth altissima per attrarre più traffico.

#### Implicazione pratica

Le DA sono un punto di centralizzazione. Se un avversario compromettesse 5 delle 9 DA,
potrebbe manipolare il consenso. Tuttavia:
- Le DA sono gestite da organizzazioni indipendenti in giurisdizioni diverse
- Il codice verifica firme multiple
- La community monitora anomalie nel consenso

### 3. Relay (nodi Tor)

I relay sono server volontari che trasportano traffico Tor. Ogni relay ha:

- **Chiave d'identità** (Ed25519) - identifica permanentemente il relay
- **Chiave onion** (Curve25519) - usata per l'handshake ntor (negoziazione chiavi di circuito)
- **Chiave di signing** - firma i descriptor
- **Chiave TLS** - per la connessione TLS tra relay

#### Tipi di relay

**Guard Node (Entry)**
- Primo nodo del circuito
- Conosce l'IP reale del client
- NON conosce la destinazione finale
- Selezionato da un pool ristretto di "entry guards" che il client mantiene per mesi
- Motivazione del guard persistente: se il client scegliesse entry random ogni volta,
  un avversario che controlla alcuni relay finirebbe per essere selezionato come entry
  (vedendo l'IP del client). Con guard persistenti, o sei sfortunato dalla prima
  selezione, o sei protetto per mesi.

**Middle Relay**
- Nodo intermedio
- NON conosce né il client né la destinazione
- Vede solo traffico cifrato dal guard e lo inoltra all'exit
- Selezionato con probabilità proporzionale alla bandwidth

**Exit Node**
- Ultimo nodo, esce su Internet
- Conosce la destinazione (dominio + porta)
- NON conosce l'IP del client
- Il suo IP è quello visibile ai siti web
- Definisce una exit policy che limita quali porte/destinazioni sono permesse

### 4. Bridge Relay

I bridge sono relay non elencati nel consenso pubblico. Esistono per aggirare la censura:

- L'ISP non può bloccarli consultando la lista pubblica dei relay
- Usano pluggable transports (obfs4, meek, Snowflake) per offuscare il traffico
- Sono distribuiti tramite canali limitati (sito web con CAPTCHA, email, Snowflake)

Nella mia esperienza, i bridge obfs4 sono stati essenziali per:
- Aggirare firewall universitari che bloccavano le connessioni dirette ai relay Tor
- Nascondere all'ISP il fatto che stavo usando Tor
- Evitare rallentamenti applicati da alcuni ISP al traffico Tor riconosciuto

---

> **Continua in**: [Costruzione Circuiti](costruzione-circuiti.md) per il protocollo CREATE2/EXTEND2,
> celle, TLS, e in [Isolamento e Modello di Minaccia](isolamento-e-modello-minaccia.md) per
> stream isolation, ciclo di vita dei circuiti e threat model.

---

## Vedi anche

- [Costruzione Circuiti](costruzione-circuiti.md) - Path selection, ntor handshake, celle e TLS
- [Isolamento e Modello di Minaccia](isolamento-e-modello-minaccia.md) - Stream isolation, ciclo vita, threat model
- [Circuiti, Crittografia e Celle](circuiti-crittografia-e-celle.md) - Protocollo a livello di pacchetto
- [Consenso e Directory Authorities](consenso-e-directory-authorities.md) - Votazione, flag, selezione relay
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester

