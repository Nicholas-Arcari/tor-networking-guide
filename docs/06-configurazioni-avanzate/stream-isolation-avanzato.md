# Stream Isolation Avanzato - Tor Browser, SessionGroup e Gestione Operativa

Come Tor Browser implementa l'isolamento SOCKS5 per dominio, SessionGroup per
raggruppamento manuale, isolamento via curl/Python/Firefox Container Tabs,
gestione operativa multi-istanza e trade-off.

> **Estratto da**: [Multi-Istanza Tor e Stream Isolation](multi-istanza-e-stream-isolation.md)
> per il modello di minaccia, systemd templates e i flag di isolamento.

---

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

## SessionGroup - approfondimento

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

- [torrc - Guida Completa](../02-installazione-e-configurazione/torrc-guida-completa.md) - Direttive SocksPort e isolamento
- [ProxyChains - Guida Completa](../04-strumenti-operativi/proxychains-guida-completa.md) - Proxare app su istanze diverse
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - NEWNYM per istanza
- [VPN e Tor Ibrido](vpn-e-tor-ibrido.md) - Routing selettivo per applicazione
- [Gestione del Servizio](../02-installazione-e-configurazione/gestione-del-servizio.md) - systemd templates
