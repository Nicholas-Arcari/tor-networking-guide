# Tor e Localhost - Docker, Sviluppo Web e Onion Services

Docker e Tor (container via Tor, servizi .onion, debug API), sviluppo web locale
con Tor attivo, onion services per servizi locali, interazione con servizi di
sistema e matrice di compatibilità browser/localhost.

> **Estratto da**: [Tor e Localhost](tor-e-localhost.md) per il problema,
> l'attacco Local Service Discovery e le soluzioni base.

---

## Docker e Tor - scenari avanzati

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
come `.onion`, e funziona perfettamente - ma aggiunge ~300ms di latenza che
rende il hot reload di Vite frustrante. Per lo sviluppo, la separazione dei
profili è la soluzione migliore.

La lezione imparata: **non è necessario accedere ai servizi locali via Tor
Browser**. Sono due casi d'uso diversi che richiedono strumenti diversi. Tentare
di forzare Tor Browser ad accedere a localhost è sia un rischio di sicurezza
che un workaround inutile.

---

## Vedi anche

- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) - Alternativa sicura per esporre servizi locali
- [Multi-Istanza e Stream Isolation](multi-istanza-e-stream-isolation.md) - Istanze Tor per servizi diversi
- [Hardening di Sistema](../05-sicurezza-operativa/hardening-sistema.md) - Proteggere servizi locali
- [Transparent Proxy](transparent-proxy.md) - TransPort e interazione con localhost
