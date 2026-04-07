# Multi-Istanza Tor e Stream Isolation

Questo documento analizza come eseguire multiple istanze di Tor per separare
il traffico di applicazioni diverse, e come configurare l'isolamento degli
stream per massimizzare la privacy. Copre sia la separazione completa (istanze
multiple) che l'isolamento logico su singola istanza (stream isolation flags).

> **Vedi anche**: [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md)
> per ControlPort, [Guard Nodes](../03-nodi-e-rete/guard-nodes.md) per le implicazioni
> della selezione guard, [Isolamento e Compartimentazione](../05-sicurezza-operativa/isolamento-e-compartimentazione.md)
> per isolamento a livello sistema, [torrc Guida Completa](../02-installazione-e-configurazione/torrc-guida-completa.md)
> per SocksPort flags.

---

## Indice

- [Perché multiple istanze — modello di minaccia](#perché-multiple-istanze--modello-di-minaccia)
- [Configurazione con systemd templates](#configurazione-con-systemd-templates)
- [Architetture multi-istanza per scenari reali](#architetture-multi-istanza-per-scenari-reali)
- [Stream isolation su singola istanza](#stream-isolation-su-singola-istanza)
- [Flag di isolamento — approfondimento](#flag-di-isolamento--approfondimento)
- [Come Tor Browser implementa l'isolamento](#come-tor-browser-implementa-lisolamento)
- [SessionGroup — approfondimento](#sessiongroup--approfondimento)
- [Stream isolation via applicazione](#stream-isolation-via-applicazione)
- [Gestione operativa multi-istanza](#gestione-operativa-multi-istanza)
- [Limiti e trade-off](#limiti-e-trade-off)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Perché multiple istanze — modello di minaccia

### Il problema: correlazione tra stream

Un singolo processo Tor condivide i circuiti tra tutte le applicazioni connesse.
Questo crea un rischio di correlazione:

```
Scenario con singola istanza:
[Firefox] ──→ SocksPort 9050 ──→ Circuito A ──→ Exit Node X
[curl]    ──→ SocksPort 9050 ──→ Circuito A ──→ Exit Node X
[script]  ──→ SocksPort 9050 ──→ Circuito A ──→ Exit Node X

Exit Node X vede:
  - Traffico HTTP browser (Facebook, Gmail)
  - Query curl a api.ipify.org
  - Traffico script automatizzato
  → Può correlare TUTTO allo stesso utente
```

### Esempio concreto di deanonimizzazione

1. Navighi su un forum anonimo via Tor Browser
2. Contemporaneamente, uno script curl controlla la tua email via Tor
3. Entrambi usano lo stesso exit node (stesso circuito Tor)
4. L'exit node (se malevolo) vede:
   - `POST forum-anonimo.onion/reply` (tuo post anonimo)
   - `GET mail.provider.com/inbox?user=tuonome@email.com` (tua identità reale)
5. **Correlazione**: il tuo post anonimo è ora collegato alla tua email

### Con istanze separate

```
[Firefox]  ──→ Istanza 1 (SocksPort 9050) ──→ Circuito A ──→ Exit X
[curl]     ──→ Istanza 2 (SocksPort 9060) ──→ Circuito B ──→ Exit Y
[script]   ──→ Istanza 3 (SocksPort 9070) ──→ Circuito C ──→ Exit Z

Exit X vede solo il traffico browser
Exit Y vede solo le query curl
Exit Z vede solo il traffico script
→ Nessuna correlazione possibile tra le attività
```

---

## Configurazione con systemd templates

### Il modo corretto su Debian/Kali

Debian (e Kali) supporta nativamente istanze multiple di Tor tramite il
sistema di template systemd `tor@.service`:

```bash
# Creare una nuova istanza
sudo tor-instance-create cli

# Struttura creata automaticamente:
/etc/tor/instances/cli/torrc       ← configurazione
/var/lib/tor-instances/cli/        ← data directory
# Utente: _tor-cli (creato automaticamente)
# Gruppo: _tor-cli
```

### Configurazione istanze

#### Istanza 1: Navigazione browser

```ini
# /etc/tor/instances/browser/torrc
SocksPort 9050 IsolateDestAddr IsolateDestPort
DNSPort 5353
ControlPort 9051
CookieAuthentication 1
DataDirectory /var/lib/tor-instances/browser
ClientUseIPv6 0
```

#### Istanza 2: CLI e script

```ini
# /etc/tor/instances/cli/torrc
SocksPort 9060 IsolateSOCKSAuth
DNSPort 5363
ControlPort 9061
CookieAuthentication 1
DataDirectory /var/lib/tor-instances/cli
ClientUseIPv6 0
```

#### Istanza 3: Comunicazione sicura

```ini
# /etc/tor/instances/secure/torrc
SocksPort 9070 IsolateDestAddr IsolateDestPort IsolateSOCKSAuth
DNSPort 5373
ControlPort 9071
CookieAuthentication 1
DataDirectory /var/lib/tor-instances/secure
ClientUseIPv6 0
```

### Gestione con systemctl

```bash
# Avviare/fermare istanze
sudo systemctl start tor@browser.service
sudo systemctl start tor@cli.service
sudo systemctl start tor@secure.service

# Stato
sudo systemctl status tor@browser.service

# Abilitare avvio automatico
sudo systemctl enable tor@browser.service

# Restart singola istanza (senza toccare le altre)
sudo systemctl restart tor@cli.service

# Log di un'istanza specifica
sudo journalctl -u tor@cli.service -f
```

### Verifica porte

```bash
# Verificare che tutte le istanze siano in ascolto
ss -tlnp | grep tor
# LISTEN 127.0.0.1:9050  ... tor (browser)
# LISTEN 127.0.0.1:9060  ... tor (cli)
# LISTEN 127.0.0.1:9070  ... tor (secure)
```

### Uso

```bash
# Browser usa istanza 1
proxychains firefox -no-remote -P tor-proxy & disown
# (proxychains4.conf punta a 9050)

# CLI usa istanza 2
curl --socks5-hostname 127.0.0.1:9060 https://api.ipify.org

# Comunicazione sicura usa istanza 3
torsocks -P 9070 thunderbird &
```

---

## Architetture multi-istanza per scenari reali

### Scenario: OSINT + Navigazione + Comunicazione + Sviluppo

```
┌─────────────────────────────────────────────────────┐
│                  Kali Linux Host                     │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────┐ │
│  │ Firefox  │  │ curl/    │  │ Thunder- │  │ Dev │ │
│  │ tor-proxy│  │ scripts  │  │ bird     │  │ test│ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──┬──┘ │
│       │              │              │            │    │
│  SocksPort      SocksPort      SocksPort    SocksPort│
│    9050           9060           9070         9080   │
│       │              │              │            │    │
│  ┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐  ┌──┴──┐ │
│  │ Tor #1   │  │ Tor #2   │  │ Tor #3   │  │Tor#4│ │
│  │ browser  │  │ cli      │  │ secure   │  │ dev │ │
│  │ Guard A  │  │ Guard B  │  │ Guard C  │  │Grd D│ │
│  └──────────┘  └──────────┘  └──────────┘  └─────┘ │
│                                                      │
│  Ogni istanza: guard diverso, circuiti indipendenti  │
│  Nessuna correlazione possibile tra istanze           │
└─────────────────────────────────────────────────────┘
```

### Tabella porte

| Istanza | SocksPort | DNSPort | ControlPort | Uso |
|---------|-----------|---------|-------------|-----|
| browser | 9050 | 5353 | 9051 | Firefox, navigazione web |
| cli | 9060 | 5363 | 9061 | curl, wget, script |
| secure | 9070 | 5373 | 9071 | Email, chat, comunicazione |
| dev | 9080 | 5383 | 9081 | Testing, sviluppo |

---

## Stream isolation su singola istanza

Se non vuoi gestire istanze multiple, puoi ottenere isolamento parziale
con porte SOCKS diverse sulla stessa istanza:

```ini
# torrc — singola istanza, isolamento per porta
SocksPort 9050 IsolateDestAddr IsolateDestPort           # browser
SocksPort 9052 IsolateSOCKSAuth                           # CLI con auth
SocksPort 9053 SessionGroup=1                             # script gruppo 1
SocksPort 9054 SessionGroup=2                             # script gruppo 2
```

### Come funziona internamente

Tor associa ogni stream a un circuito basandosi su una **chiave di isolamento**.
La chiave è costruita da:

```
isolation_key = (
    SocksPort,
    SessionGroup,
    IsolateDestAddr ? dest_ip : *,
    IsolateDestPort ? dest_port : *,
    IsolateSOCKSAuth ? socks_username : *,
    IsolateClientAddr ? client_ip : *,
    IsolateClientProtocol ? protocol : *
)

Stream con la stessa isolation_key → stesso circuito
Stream con chiave diversa → circuito diverso
```

---

## Flag di isolamento — approfondimento

### Tabella completa

| Flag | Parametro chiave | Effetto |
|------|-----------------|--------|
| `IsolateDestAddr` | IP destinazione | google.com e github.com → circuiti diversi |
| `IsolateDestPort` | Porta destinazione | :443 e :80 → circuiti diversi |
| `IsolateSOCKSAuth` | Credenziali SOCKS5 | User diversi → circuiti diversi |
| `IsolateClientAddr` | IP sorgente | Client da IP diversi → circuiti diversi |
| `IsolateClientProtocol` | SOCKS4/5/HTTP | Protocolli diversi → circuiti diversi |
| `SessionGroup=N` | Gruppo manuale | Solo stream nello stesso gruppo condividono |

### Matrice di isolamento

Combinazioni comuni e il loro effetto:

| Configurazione | google.com:443 + google.com:80 | google.com:443 + github.com:443 |
|---------------|-------------------------------|-------------------------------|
| Nessun flag | Stesso circuito | Stesso circuito |
| `IsolateDestAddr` | Stesso circuito | **Diverso** |
| `IsolateDestPort` | **Diverso** | Stesso circuito |
| `IsolateDestAddr IsolateDestPort` | **Diverso** | **Diverso** |
| `IsolateSOCKSAuth` | Dipende da auth | Dipende da auth |

### Osservare l'isolamento via ControlPort

```python
from stem.control import Controller

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()
    
    # Mostra tutti gli stream con i circuiti associati
    for stream in ctrl.get_info("stream-status").split("\n"):
        if stream.strip():
            # Format: StreamID Status CircuitID Target
            parts = stream.split()
            print(f"Stream {parts[0]}: circuit={parts[2]} target={parts[3]}")
```

Output esempio con `IsolateDestAddr`:
```
Stream 1: circuit=5  target=google.com:443
Stream 2: circuit=5  target=google.com:80     ← stesso circuito (stesso IP dest)
Stream 3: circuit=7  target=github.com:443    ← circuito diverso (IP diverso)
```

---

## Come Tor Browser implementa l'isolamento

### SOCKS5 auth per dominio

Tor Browser è il gold standard per l'isolamento. Usa `IsolateSOCKSAuth` con
credenziali SOCKS5 generate per-dominio:

```
Tab 1 (google.com):
  SOCKS5 CONNECT google.com:443
  Auth: username="google.com" password="<random_nonce_1>"
  → Circuito A

Tab 2 (github.com):
  SOCKS5 CONNECT github.com:443
  Auth: username="github.com" password="<random_nonce_2>"
  → Circuito B (diverso da A, perché auth diversa)

Tab 3 (google.com di nuovo):
  SOCKS5 CONNECT google.com:443
  Auth: username="google.com" password="<random_nonce_1>"  ← stessa!
  → Circuito A (stesso, perché auth uguale)
```

### First-Party Isolation (FPI)

Tor Browser implementa anche FPI a livello Firefox:
- Cookie: isolati per dominio di primo livello
- Cache: isolata per dominio
- SessionStorage: isolata per dominio
- HSTS: isolato per dominio

### Il codice Torbutton

Il componente Torbutton di Tor Browser genera le credenziali:

```javascript
// Logica semplificata
function getProxyCredentials(url) {
    let domain = extractFirstPartyDomain(url);
    let nonce = getOrCreateNonce(domain);
    return { username: domain, password: nonce };
}
```

---

## SessionGroup — approfondimento

### Come funziona

`SessionGroup` è un meccanismo di raggruppamento manuale degli stream:

```ini
SocksPort 9050 SessionGroup=0    # Gruppo 0: browser
SocksPort 9052 SessionGroup=1    # Gruppo 1: script OSINT
SocksPort 9053 SessionGroup=1    # Gruppo 1: stesso gruppo → condividono circuiti
SocksPort 9054 SessionGroup=2    # Gruppo 2: comunicazione
```

### Regole

- Stream nello **stesso SessionGroup** e **stessa porta** possono condividere circuiti
- Stream in **SessionGroup diversi** NON condividono mai
- `SessionGroup` si combina con gli altri flag di isolamento
- Ogni porta senza `SessionGroup` esplicito ha un group implicito unico

### Quando usarlo

- **Raggruppare attività correlate**: se due script devono apparire come lo stesso
  "utente" (stesso IP exit), metterli nello stesso SessionGroup
- **Separare attività diverse**: attività che non devono essere correlate vanno
  in SessionGroup diversi

---

## Stream isolation via applicazione

### curl con SOCKS5 auth

```bash
# Ogni dominio con credenziali diverse → circuiti diversi
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "google.com:session1" \
     https://www.google.com

curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "github.com:session2" \
     https://github.com

# Verifica: IP diversi
curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "check1:test" \
     https://api.ipify.org
# → 185.220.100.240

curl --socks5-hostname 127.0.0.1:9050 \
     --proxy-user "check2:test" \
     https://api.ipify.org
# → 109.70.100.13 (diverso!)
```

### Python requests con isolamento

```python
import requests

def tor_session(username="default", password="default"):
    """Crea sessione Tor con isolamento SOCKS auth."""
    session = requests.Session()
    session.proxies = {
        'http': f'socks5h://{username}:{password}@127.0.0.1:9050',
        'https': f'socks5h://{username}:{password}@127.0.0.1:9050',
    }
    return session

# Sessione 1: ricerca
s1 = tor_session("research", "task1")
ip1 = s1.get("https://api.ipify.org").text

# Sessione 2: comunicazione
s2 = tor_session("comm", "task2")
ip2 = s2.get("https://api.ipify.org").text

print(f"Research IP: {ip1}")    # → IP exit A
print(f"Communication IP: {ip2}")  # → IP exit B (diverso)
```

### Firefox Container Tabs

Con il profilo tor-proxy e l'estensione Multi-Account Containers:
- Ogni container può avere credenziali proxy diverse
- Risultato: isolamento per container senza istanze multiple

---

## Gestione operativa multi-istanza

### Monitoraggio

```bash
# Stato di tutte le istanze
for inst in browser cli secure; do
    STATUS=$(systemctl is-active tor@${inst}.service 2>/dev/null)
    echo "tor@${inst}: $STATUS"
done

# Nyx per istanza specifica
nyx -i 127.0.0.1:9051    # browser
nyx -i 127.0.0.1:9061    # cli
nyx -i 127.0.0.1:9071    # secure
```

### NEWNYM per istanza specifica

```bash
# Cambiare identità solo sull'istanza CLI
echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9061

# Script per NEWNYM su tutte le istanze
for port in 9051 9061 9071; do
    echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 $port
    echo "NEWNYM inviato a porta $port"
done
```

### Risorse di sistema

Ogni istanza Tor consuma risorse aggiuntive:

| Risorsa | Per istanza | 4 istanze |
|---------|-------------|-----------|
| RAM | ~30-60 MB | ~120-240 MB |
| CPU | Minima (idle) | Minima |
| File descriptors | ~200 | ~800 |
| Connessioni TCP | 3-5 (guard+directory) | 12-20 |
| Disk (state/cache) | ~50-100 MB | ~200-400 MB |

---

## Limiti e trade-off

### Più guard = più superficie di attacco

Ogni istanza Tor seleziona il proprio guard. Con 4 istanze hai 4 guard diversi:

```
Singola istanza: 1 guard → 1 punto di osservazione per l'avversario
4 istanze: 4 guard → 4 punti di osservazione

Un avversario che controlla anche solo 1 dei 4 guard
vede 25% del tuo traffico totale
```

Questo è un trade-off reale: più isolamento tra le attività, ma più guard
coinvolti nella tua attività complessiva.

### Quando l'isolamento NON serve

- **Single-purpose machine**: se usi Tor solo per un'attività (es. solo browsing),
  una singola istanza è sufficiente
- **Whonix/Tails**: già forniscono isolamento a livello VM/OS
- **Uso occasionale**: se usi Tor raramente, la complessità non è giustificata

### Complessità di gestione

- Più istanze = più torrc da mantenere
- Aggiornamenti Tor: tutte le istanze devono essere riavviate
- Monitoring: serve monitorare ogni istanza separatamente
- Bridge: ogni istanza potrebbe aver bisogno dei propri bridge

---

## Nella mia esperienza

Uso una singola istanza Tor con la porta 9050 di default. Il mio uso è
relativamente semplice:
- Firefox con profilo `tor-proxy` via proxychains per navigazione
- curl via proxychains o torsocks per test e verifica
- Script Python per automazione

Non ho configurato stream isolation avanzato né istanze multiple perché il mio
modello di minaccia non lo richiede: non combino attività identificabili con
attività anonime sullo stesso sistema. Quando faccio ricerca via Tor, è l'unica
attività attiva.

Per un setup più serio (es. giornalista con fonti da proteggere, o OSINT
professionale), configurerei almeno due istanze:
1. **Navigazione**: con `IsolateDestAddr` per isolare ogni sito
2. **Comunicazione**: istanza separata con guard diverso

Il sistema di template systemd (`tor@istanza.service`) rende la gestione molto
più semplice rispetto a lanciare processi Tor manualmente. Lo consiglio per chi
ha bisogno di più di una singola istanza.

---

## Vedi anche

- [torrc — Guida Completa](../02-installazione-e-configurazione/torrc-guida-completa.md) — Direttive SocksPort e isolamento
- [ProxyChains — Guida Completa](../04-strumenti-operativi/proxychains-guida-completa.md) — Proxare app su istanze diverse
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) — NEWNYM per istanza
- [VPN e Tor Ibrido](vpn-e-tor-ibrido.md) — Routing selettivo per applicazione
- [Gestione del Servizio](../02-installazione-e-configurazione/gestione-del-servizio.md) — systemd templates
