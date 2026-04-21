> **Lingua / Language**: Italiano | [English](../en/06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md)

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

- [Perché multiple istanze - modello di minaccia](#perché-multiple-istanze--modello-di-minaccia)
- [Configurazione con systemd templates](#configurazione-con-systemd-templates)
- [Architetture multi-istanza per scenari reali](#architetture-multi-istanza-per-scenari-reali)
- [Stream isolation su singola istanza](#stream-isolation-su-singola-istanza)
- [Flag di isolamento - approfondimento](#flag-di-isolamento--approfondimento)
**Approfondimenti** (file dedicati):
- [Stream Isolation Avanzato](stream-isolation-avanzato.md) - Tor Browser, SessionGroup, curl/Python, gestione operativa

---

## Perché multiple istanze - modello di minaccia

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
# torrc - singola istanza, isolamento per porta
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

## Flag di isolamento - approfondimento

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


---

> **Continua in**: [Stream Isolation Avanzato](stream-isolation-avanzato.md) per
> come Tor Browser implementa l'isolamento, SessionGroup, isolamento via applicazione
> e gestione operativa.

---

## Vedi anche

- [Stream Isolation Avanzato](stream-isolation-avanzato.md) - Tor Browser, SessionGroup, curl/Python, gestione operativa
- [torrc - Guida Completa](../02-installazione-e-configurazione/torrc-guida-completa.md) - Direttive SocksPort e isolamento
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - NEWNYM per istanza
- [VPN e Tor Ibrido](vpn-e-tor-ibrido.md) - Routing selettivo per applicazione
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
