# Applicazioni via Tor - Instradamento, Compatibilità e Problemi

Metodi per instradare applicazioni attraverso Tor (proxychains, torsocks,
SOCKS5 nativo, env vars), matrice di compatibilità e problemi comuni.

Estratto da [Tor Browser e Applicazioni](tor-browser-e-applicazioni.md).

---

## Indice

- [Instradare applicazioni attraverso Tor](#instradare-applicazioni-attraverso-tor)
- [Matrice di compatibilità completa](#matrice-di-compatibilità-completa)
- [Applicazioni con SOCKS5 nativo](#applicazioni-con-socks5-nativo)
- [Problemi comuni e soluzioni](#problemi-comuni-e-soluzioni)

---

## Instradare applicazioni attraverso Tor

### Metodo 1: proxychains (LD_PRELOAD)

```bash
# proxychains intercetta le chiamate di rete via LD_PRELOAD
# Funziona con la maggior parte delle applicazioni dinamicamente linkate

proxychains curl https://example.com
proxychains firefox -no-remote -P tor-proxy
proxychains git clone https://github.com/user/repo
proxychains ssh user@host
proxychains nmap -sT -Pn target.com
```

**Quando funziona**: applicazioni che usano glibc e fanno chiamate di rete standard
(connect, getaddrinfo, etc.).

**Quando NON funziona**:
- Applicazioni staticamente linkate (Go binaries, Rust binaries)
- Applicazioni che usano raw socket (nmap -sS, ping)
- Applicazioni che gestiscono i socket direttamente (bypass di glibc)
- Applicazioni Electron (hanno il proprio stack di rete)

### Metodo 2: torsocks (LD_PRELOAD specializzato)

```bash
# torsocks è specifico per Tor, più sicuro di proxychains
# Blocca attivamente connessioni non-TCP (UDP) invece di ignorarle

torsocks curl https://example.com
torsocks ssh user@host
torsocks wget https://example.com/file

# Vantaggio: se un'app tenta UDP, torsocks la BLOCCA
# proxychains: ignorerebbe silenziosamente il tentativo UDP
```

### Metodo 3: configurazione SOCKS5 nativa dell'app

```bash
# Alcune applicazioni supportano proxy SOCKS5 nella configurazione
# Questo è più affidabile di LD_PRELOAD

# curl nativo:
curl --socks5-hostname 127.0.0.1:9050 https://example.com
# oppure
curl -x socks5h://127.0.0.1:9050 https://example.com

# git nativo:
git config --global http.proxy socks5h://127.0.0.1:9050
git config --global https.proxy socks5h://127.0.0.1:9050
# IMPORTANTE: "socks5h" (con h) → risolvi hostname via proxy

# SSH via ProxyCommand:
# In ~/.ssh/config:
Host *.onion
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

### Metodo 4: TransPort (transparent proxy)

```bash
# Per uso system-wide, iptables redirige tutto il traffico TCP a Tor
# Vedi docs/06-configurazioni-avanzate/transparent-proxy.md

# Vantaggi: TUTTE le applicazioni passano da Tor, senza configurazione
# Svantaggi: UDP bloccato, performance degradate, fragile
```

---

## Matrice di compatibilità completa

### Applicazioni CLI

| Applicazione | Metodo | Funziona? | DNS sicuro? | Note |
|-------------|--------|-----------|-------------|------|
| curl | `--socks5-hostname` | SI | SI | Perfetto, il mio strumento principale |
| curl | `--socks5` (senza h) | SI ma LEAK DNS | **NO** | Mai usare senza -hostname |
| wget | proxychains | SI | SI (con proxy_dns) | Download funzionano bene |
| git (HTTPS) | proxychains o config | SI | SI | Clone, pull, push |
| git (SSH) | proxychains | Parziale | SI | Lento, timeout possibili |
| ssh | proxychains o ProxyCommand | SI | SI | Lento ma funzionante |
| pip | proxychains | SI | SI | Installa pacchetti Python via Tor |
| npm | proxychains | SI | SI | Installa pacchetti Node.js via Tor |
| gem | proxychains | SI | SI | Installa gem Ruby via Tor |
| cargo | proxychains | Parziale | SI | Rust: link statico può causare problemi |
| rsync | proxychains | SI | SI | Sincronizzazione file |
| scp | proxychains | SI | SI | Copia file via SSH |

### Strumenti di sicurezza

| Applicazione | Metodo | Funziona? | Note |
|-------------|--------|-----------|------|
| nmap -sT | proxychains | SI | Solo TCP connect scan, -Pn obbligatorio |
| nmap -sS | proxychains | **NO** | SYN scan richiede raw socket |
| nmap -sU | proxychains | **NO** | UDP non supportato da Tor |
| nmap -sn | proxychains | **NO** | Ping usa ICMP |
| nikto | proxychains | SI | Lento ma funzionante |
| dirb/gobuster | proxychains | SI | Enumerazione directory via Tor |
| sqlmap | proxychains o --proxy | SI | Supporta SOCKS5 nativamente |
| Burp Suite | config proxy interna | SI | SOCKS proxy nelle impostazioni |
| wfuzz | proxychains | SI | Fuzzing web via Tor |
| hydra | proxychains | Parziale | Solo protocolli TCP, molto lento |
| ping | Non supportato | **NO** | ICMP non supportato |
| traceroute | Non supportato | **NO** | ICMP/UDP |

### Applicazioni Desktop

| Applicazione | Metodo | Funziona? | Note |
|-------------|--------|-----------|------|
| Firefox | proxychains + profilo | SI | Senza protezioni anti-fingerprint complete |
| Tor Browser | Integrato | SI | Setup completo, raccomandato |
| Chromium | proxychains | Parziale | DoH può bypassare, fingerprint alto |
| Thunderbird | proxy SOCKS5 config | SI | Email via Tor possibile |
| Discord | proxychains | **NO** | Usa WebSocket + UDP per voce |
| Telegram Desktop | config proxy interna | SI | Configurare SOCKS5 nelle impostazioni |
| Signal Desktop | proxychains | Parziale | Funziona per messaggi, non per chiamate |
| Steam | proxychains | **NO** | Usa UDP per gaming |
| Spotify | proxychains | **NO** | Protocollo proprietario, streaming |
| VLC (streaming) | proxychains | **NO** | Usa UDP per streaming |
| Electron apps | proxychains | Parziale | Spesso ignorano LD_PRELOAD |
| VS Code | proxychains | Parziale | Electron, estensioni possono bypassare |
| Client email (SMTP) | proxychains | Parziale | Porta 25 bloccata dalla maggior parte degli exit |

### Servizi specifici

| Servizio | Via Tor Browser | Via proxychains | Note |
|---------|----------------|-----------------|------|
| Google Search | SI (con CAPTCHA) | SI (con CAPTCHA) | Usare DuckDuckGo/Startpage |
| Gmail | SI (difficile) | SI (difficile) | Richiede verifica telefono |
| GitHub | SI | SI | Funziona generalmente bene |
| Stack Overflow | SI | SI | Lettura perfetta, posting con verifica |
| Wikipedia | SI (lettura) | SI (lettura) | Editing bloccato da IP Tor |
| Reddit | SI | SI | Login richiesto più spesso |
| Amazon | SI (navigazione) | SI (navigazione) | Acquisti spesso bloccati |
| Banking | **NO** | **NO** | Bloccato, possibile lock account |
| PayPal | **NO** | **NO** | Bloccato, possibile sospensione |
| Netflix | Parziale | **NO** | Blocca molti exit IP |

---

## Applicazioni con SOCKS5 nativo

### Firefox (nel profilo `tor-proxy`)

```
Settings → Network Settings → Manual proxy configuration
  SOCKS Host: 127.0.0.1
  SOCKS Port: 9050
  SOCKS v5
  ☑ Proxy DNS when using SOCKS v5

Oppure in about:config:
  network.proxy.type = 1
  network.proxy.socks = "127.0.0.1"
  network.proxy.socks_port = 9050
  network.proxy.socks_version = 5
  network.proxy.socks_remote_dns = true
```

### git

```bash
# Configurazione globale
git config --global http.proxy socks5h://127.0.0.1:9050
git config --global https.proxy socks5h://127.0.0.1:9050

# Solo per un repository specifico
cd /path/to/repo
git config http.proxy socks5h://127.0.0.1:9050

# Rimuovere il proxy
git config --global --unset http.proxy
git config --global --unset https.proxy

# IMPORTANTE: "socks5h" con la 'h' = hostname risolto dal proxy
# "socks5" senza 'h' = hostname risolto localmente (DNS leak!)
```

### SSH

```
# ~/.ssh/config
Host *.onion
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p

# Per qualsiasi host via Tor:
Host tor-*
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p

# Uso:
ssh tor-myserver.com    # Passa da Tor
ssh myserver.com        # Connessione diretta
```

### Telegram Desktop

```
Settings → Advanced → Connection type → Use custom proxy
  Type: SOCKS5
  Hostname: 127.0.0.1
  Port: 9050
  Username: (vuoto)
  Password: (vuoto)
```

### Burp Suite

```
Settings → Network → Connections → SOCKS proxy
  Host: 127.0.0.1
  Port: 9050
  ☑ Use SOCKS proxy
  ☑ Do DNS lookups over SOCKS proxy
```

### sqlmap

```bash
# Via opzione --proxy
sqlmap -u "https://target.com/page?id=1" --proxy=socks5://127.0.0.1:9050

# Oppure via proxychains
proxychains sqlmap -u "https://target.com/page?id=1"
```

---

## Problemi comuni e soluzioni

### Problema: applicazione ignora proxychains

```bash
# Sintomo: l'applicazione si connette direttamente (IP reale esposto)
# Causa: applicazione staticamente linkata o usa raw socket

# Verifica se l'applicazione è dinamicamente linkata:
ldd /usr/bin/app_name
# Se mostra "not a dynamic executable" → proxychains non funzionerà

# Soluzione 1: usare torsocks (può funzionare dove proxychains fallisce)
torsocks app_name

# Soluzione 2: configurare il proxy nell'applicazione
# Soluzione 3: usare TransPort/transparent proxy (iptables)
# Soluzione 4: usare network namespace
```

### Problema: timeout frequenti

```bash
# Sintomo: "Connection timed out" dopo pochi secondi
# Causa: l'applicazione ha timeout troppo brevi per Tor

# Per curl: aumentare il timeout
curl --socks5-hostname 127.0.0.1:9050 --max-time 60 https://example.com

# Per git: aumentare i timeout
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 60

# Per SSH: keep-alive
# ~/.ssh/config
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ConnectTimeout 60
```

### Problema: DNS leak nonostante proxychains

```bash
# Sintomo: tcpdump mostra query DNS in uscita
# Causa: proxy_dns non attivo, o app bypassa LD_PRELOAD

# Verifica 1: proxy_dns nel config
grep proxy_dns /etc/proxychains4.conf
# Deve mostrare: proxy_dns (non commentato)

# Verifica 2: test con tcpdump
sudo tcpdump -i eth0 port 53 -n &
proxychains curl -s https://example.com > /dev/null
# Se tcpdump mostra query → leak

# Soluzione: aggiungere regole iptables anti-leak
sudo iptables -A OUTPUT -p udp --dport 53 -m owner ! --uid-owner debian-tor -j DROP
```

### Problema: CAPTCHA infiniti

```
Sintomo: Google/Cloudflare mostra CAPTCHA ad ogni pagina
Causa: l'IP dell'exit Tor è in una blocklist

Soluzioni:
1. Cambiare exit: NEWNYM (via ControlPort o nyx)
2. Usare motori di ricerca Tor-friendly (DuckDuckGo, Startpage)
3. Per Cloudflare: non c'è soluzione universale, dipende dal sito
4. Forzare un exit di un paese specifico (NON raccomandato per privacy):
   ExitNodes {de},{nl}  # Exit da Germania/Olanda (meno bloccati)
```

---

## Nella mia esperienza

### Il mio workflow quotidiano

```bash
# Navigazione web anonima:
proxychains firefox -no-remote -P tor-proxy & disown

# Ricerche rapide:
proxychains curl -s https://api.ipify.org  # Verifica IP

# Test di sicurezza:
proxychains nmap -sT -Pn -p 80,443,8080 target.com

# Git via Tor:
proxychains git clone https://github.com/user/repo

# Tutto il resto: rete normale
firefox  # Profilo default, senza proxy
```

### Tor Browser vs il mio setup - Riepilogo finale

| Aspetto | Tor Browser | Il mio setup (Firefox+proxychains) |
|---------|-------------|----------------------------------|
| Anonimato IP | Eccellente | Eccellente |
| Anti-fingerprinting | Eccellente | Scarso |
| DNS leak prevention | Automatico | Richiede config (proxy_dns) |
| WebRTC protection | Automatico | Manuale (about:config) |
| Cross-site tracking | FPI (automatico) | Nessuna protezione nativa |
| Circuiti per dominio | Automatico | No (stesso circuito per tutti) |
| Facilità d'uso | Scarica e avvia | Configurazione manuale |
| Flessibilità | Limitata (è un browser) | Alta (qualsiasi app) |
| Per anonimato massimo | **SI** | NO |
| Per test e sviluppo | Poco pratico | **SI** |

Il mio setup è un compromesso consapevole: sacrifico l'anti-fingerprinting per
avere la flessibilità di usare Tor con qualsiasi strumento CLI e con Firefox
in un ambiente di sviluppo.

---

## Vedi anche

- [ProxyChains - Guida Completa](proxychains-guida-completa.md) - LD_PRELOAD, chain modes, proxy_dns
- [torsocks](torsocks.md) - Confronto con proxychains, blocco UDP, edge cases
- [Verifica IP, DNS e Leak](verifica-ip-dns-e-leak.md) - Test completi per verificare la protezione
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) - Tutti i vettori di fingerprinting
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Prevenzione completa DNS leak
- [Controllo Circuiti e NEWNYM](controllo-circuiti-e-newnym.md) - Gestione circuiti e cambio IP
