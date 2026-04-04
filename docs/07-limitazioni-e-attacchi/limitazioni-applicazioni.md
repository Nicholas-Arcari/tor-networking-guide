# Limitazioni nelle Applicazioni — Cosa Funziona e Cosa No con Tor

Questo documento cataloga il comportamento di applicazioni specifiche quando usate
attraverso Tor: web app, applicazioni desktop, servizi cloud, e strumenti di
sviluppo. Per ogni categoria, analizza perché funzionano o non funzionano e
quali workaround esistono.

Basato sulla mia esperienza diretta nel testare diverse applicazioni via
proxychains e Tor su Kali Linux.

---

## Applicazioni Web

### Siti che bloccano o limitano Tor

Molti siti web mantengono liste di IP degli exit node Tor (scaricabili da
`https://check.torproject.org/torbulkexitlist`) e applicano restrizioni.

#### Google (Search, Maps, Gmail)

**Comportamento**: CAPTCHA aggressivi e ripetuti. A volte blocco totale con
messaggio "unusual traffic from your computer network".

**Motivo**: Google riceve enormi quantità di traffico automatizzato (bot, scraping)
dagli exit Tor. Per proteggersi, richiede verifiche umane (CAPTCHA reCAPTCHA).

**Nella mia esperienza**: le ricerche Google via Tor sono spesso frustranti.
Ogni 2-3 ricerche appare un CAPTCHA. A volte il CAPTCHA è infinito
(ne completi uno, ne appare un altro). Soluzione: usare DuckDuckGo o Startpage
come motore di ricerca via Tor.

#### Amazon

**Comportamento**: il sito funziona per la navigazione. Il login può fallire
con "suspicious activity detected". Gli acquisti sono spesso bloccati.

**Motivo**: Amazon blocca login da IP con reputazione bassa (Tor, VPN, datacenter).

#### PayPal

**Comportamento**: login bloccato immediatamente. Account può essere temporaneamente
sospeso se si tenta il login da Tor.

**Motivo**: PayPal ha policy anti-frode molto aggressive. Connessione da exit
Tor = alto rischio frode.

#### Instagram / Meta

**Comportamento**: login molto difficile. Richiesta verifica identità, SMS, selfie.
Spesso blocco completo dell'account.

#### Reddit

**Comportamento**: funziona per la lettura. Login richiesto più frequentemente.
Alcuni subreddit bloccano post/commenti da Tor.

#### Wikipedia

**Comportamento**: lettura perfetta. **Editing bloccato** per tutti gli IP degli
exit Tor (policy anti-vandalismo).

#### GitHub

**Comportamento**: funziona generalmente bene. Occasionalmente richiede
autenticazione aggiuntiva. Push/pull via HTTPS funzionano con proxychains.

#### Stack Overflow

**Comportamento**: funziona bene per lettura e ricerca. Login e posting possono
richiedere verifiche extra.

#### Banche italiane (home banking)

**Comportamento**: **blocco totale** nella mia esperienza. I sistemi anti-frode
bancari bloccano immediatamente connessioni da IP Tor/datacenter. Spesso
l'account viene temporaneamente bloccato, richiedendo chiamata al supporto.

**Regola**: non usare MAI Tor per accedere a servizi bancari.

---

## Applicazioni Desktop

### Tor Browser vs Firefox con proxy SOCKS

| Aspetto | Tor Browser | Firefox + proxychains |
|---------|-------------|----------------------|
| IP anonimo | SI | SI |
| DNS via Tor | Automatico | Richiede proxy_dns |
| Anti-fingerprinting | Completo | Minimo |
| WebRTC protezione | Automatica | Manuale |
| Facilità | Alta | Media |
| Flessibilità | Bassa | Alta |

### Applicazioni che NON funzionano con proxychains

| Applicazione | Motivo | Alternativa |
|-------------|--------|-------------|
| Discord | Usa WebSocket + UDP per voce | Nessuna via Tor |
| Telegram Desktop | Ha proxy SOCKS5 integrato ma richiede config | Configurare proxy nelle impostazioni |
| Steam | Usa UDP per gaming, TCP per store | Lo store funziona male via browser |
| Spotify | Protocollo proprietario, streaming | Non praticabile via Tor |
| Electron apps varie | Spesso ignorano LD_PRELOAD | Dipende dall'app |
| Client email desktop | Molti usano SMTP porta 25 (bloccata dagli exit) | Webmail via Tor Browser |

### Applicazioni che funzionano con proxychains

| Applicazione | Qualità | Note |
|-------------|---------|------|
| curl | Eccellente | Il mio strumento principale |
| wget | Buona | Download funzionano |
| git (HTTPS) | Buona | Clone, pull, push |
| ssh | Accettabile | Lento ma funzionante |
| pip | Buona | Installa pacchetti Python via Tor |
| npm | Buona | Installa pacchetti Node.js via Tor |
| nmap -sT | Accettabile | Solo TCP connect scan, lento |

---

## Strumenti di sicurezza via Tor

### nmap

```bash
# FUNZIONA: TCP connect scan
proxychains nmap -sT -Pn target.com

# NON FUNZIONA: SYN scan (richiede raw socket)
proxychains nmap -sS target.com  # FALLISCE

# NON FUNZIONA: UDP scan
proxychains nmap -sU target.com  # FALLISCE

# NON FUNZIONA: ping scan
proxychains nmap -sn target.com  # FALLISCE (ICMP)
```

Limitazioni di nmap via Tor:
- Solo `-sT` (TCP connect) funziona
- `-Pn` è obbligatorio (skip host discovery, che usa ICMP)
- Molto lento (ogni porta è una connessione SOCKS separata)
- Scansioni di porte multiple sono estremamente lente
- Molti exit bloccano le porte non standard → falsi negativi

### nikto / dirb / gobuster

```bash
# Funzionano via proxychains per enumerazione web
proxychains nikto -h https://target.com
proxychains dirb https://target.com /usr/share/dirb/wordlists/common.txt
proxychains gobuster dir -u https://target.com -w /usr/share/wordlists/common.txt
```

Molto lenti via Tor ma funzionanti per test mirati.

### sqlmap

```bash
# Funziona via proxychains
proxychains sqlmap -u "https://target.com/page?id=1"

# Oppure usando il proxy interno
sqlmap -u "https://target.com/page?id=1" --proxy=socks5://127.0.0.1:9050
```

### Burp Suite

Burp Suite può essere configurato per usare Tor come upstream proxy:
```
Settings → Network → Connections → SOCKS proxy
  Host: 127.0.0.1
  Port: 9050
  ☑ Use SOCKS proxy
  ☑ Do DNS lookups over SOCKS proxy
```

---

## Sessioni web e IP variabili

### Il problema

Tor cambia IP periodicamente (ogni ~10 minuti o con NEWNYM). Molti siti web
legano la sessione all'IP:

```
1. Login con IP 185.220.101.143 → sessione creata
2. Circuito cambia → nuovo IP 104.244.76.13
3. Sito vede IP diverso → invalida la sessione → logout forzato
```

### Siti più colpiti

- **Banking**: logout immediato al cambio IP
- **Shopping**: carrello svuotato, sessione invalidata
- **Email**: richiesta re-autenticazione
- **Social media**: "suspicious login from new location"

### Mitigazione parziale

```ini
# Nel torrc: aumentare il tempo prima del rinnovo circuiti
MaxCircuitDirtiness 1800    # 30 minuti invece di 10
```

Ma questo riduce l'anonimato (più tempo con lo stesso IP = più tracciabile).

---

## Il compromesso fondamentale

Usare Tor con applicazioni del mondo reale richiede accettare dei compromessi:

1. **Velocità**: tutto è più lento (5-50x)
2. **Compatibilità**: molte app non funzionano
3. **Blocchi**: molti siti bloccano o limitano Tor
4. **Sessioni**: instabili per cambio IP
5. **Funzionalità**: no video, no voice, no gaming

Tor è progettato per **anonimato**, non per comodità. Le limitazioni sono
conseguenze dirette delle scelte architetturali che garantiscono l'anonimato
(3 hop, rotazione circuiti, no UDP, exit policy).

Nella mia esperienza, la strategia migliore è:
- **Tor per ciò che richiede anonimato**: navigazione sensibile, ricerca, test
- **Rete normale/VPN per il resto**: banking, shopping, streaming, gaming
- **Mai mescolare** le due cose nella stessa sessione
