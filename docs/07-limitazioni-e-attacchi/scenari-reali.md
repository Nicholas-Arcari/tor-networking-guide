# Scenari Reali - Limitazioni e Attacchi Tor in Azione

Casi operativi in cui le limitazioni del protocollo Tor, l'incompatibilità
delle applicazioni, e gli attacchi noti hanno avuto impatto concreto durante
penetration test, red team engagement e attività di ricognizione.

---

## Indice

- [Scenario 1: nmap SYN scan leak IP reale durante pentest](#scenario-1-nmap-syn-scan-leak-ip-reale-durante-pentest)
- [Scenario 2: Exit Tor bloccati dal WAF durante web app assessment](#scenario-2-exit-tor-bloccati-dal-waf-durante-web-app-assessment)
- [Scenario 3: Correlazione temporale deanonimizza operatore OSINT](#scenario-3-correlazione-temporale-deanonimizza-operatore-osint)
- [Scenario 4: Sessione web invalidata durante exploitation via Tor](#scenario-4-sessione-web-invalidata-durante-exploitation-via-tor)

---

## Scenario 1: nmap SYN scan leak IP reale durante pentest

### Contesto

Un junior pentester doveva eseguire port scanning anonimo su un target
esterno. Aveva configurato proxychains con Tor e lanciato nmap con i flag
che usava abitualmente.

### Problema

```bash
# Il pentester ha lanciato:
proxychains nmap -sS -Pn target.com -p 1-1000
# tcpdump sull'interfaccia mostra:
# SYN packets diretti verso target.com dalla eth0 → IP REALE!
```

nmap con `-sS` (SYN scan) usa **raw socket** a livello kernel, bypassando
completamente lo stack TCP userspace. `proxychains` opera tramite
`LD_PRELOAD` intercettando solo le chiamate socket() standard - le raw
socket non vengono intercettate.

```
Flusso con -sS:
  nmap → raw socket (kernel) → IP stack → target
  proxychains NON intercetta → traffico diretto con IP reale

Flusso con -sT:
  nmap → connect() → proxychains intercetta → SOCKS5 → Tor → target
```

### Fix

```bash
# CORRETTO: TCP connect scan (unico compatibile con SOCKS)
proxychains nmap -sT -Pn target.com -p 80,443,8080,8443

# Per evitare errori futuri: alias nel .zshrc
alias nmap-tor='proxychains nmap -sT -Pn'

# Verificare che nessun traffico esca diretto:
sudo iptables -A OUTPUT -d target.com -j LOG --log-prefix "DIRECT: "
```

### Lezione appresa

Con Tor, nmap funziona **solo** con `-sT` (TCP connect). I flag `-sS`,
`-sU`, `-sn`, `-O` richiedono raw socket o ICMP e bypassano qualsiasi
proxy SOCKS. In alternativa, usare transparent proxy iptables per catturare
anche il traffico raw socket. Vedi [Limitazioni nelle Applicazioni](limitazioni-applicazioni.md)
per la matrice completa nmap+Tor.

---

## Scenario 2: Exit Tor bloccati dal WAF durante web app assessment

### Contesto

Un team di pentest aveva ricevuto autorizzazione per un web application
assessment su un portale aziendale protetto da Cloudflare WAF. L'assessment
doveva essere anonimo (il cliente voleva testare anche la capacità di
detection del SOC). Il team usava Burp Suite configurato con SOCKS5 su Tor.

### Problema

Dopo le prime 20 richieste, il WAF ha bloccato l'IP dell'exit Tor:

```
1. Burp Intruder: prime 20 richieste → risposte 200 OK
2. Richiesta 21 → 403 Forbidden "Access denied | Cloudflare"
3. NEWNYM → nuovo exit IP → altre 15 richieste → 403
4. NEWNYM → altro exit → 10 richieste → 403
→ Cloudflare bloccava tutti gli IP dalla lista pubblica exit Tor
```

La lista degli exit Tor è **pubblica** (`check.torproject.org/torbulkexitlist`).
Cloudflare la importa automaticamente e applica challenge o blocchi.

### Soluzione operativa

```bash
# 1. Cambiare approccio: ExitNodes da paesi con reputazione migliore
# torrc (temporaneo, riduce anonimato):
ExitNodes {ch},{is},{no}
StrictNodes 1

# 2. Alternativa: usare un proxy chain Tor → VPS → target
# La VPS ha un IP "pulito" non nella lista exit Tor
ssh -D 1080 user@vps-clean-ip
# Configurare Burp su localhost:1080

# 3. Per Intruder: rate limiting manuale
# Burp → Settings → Network → Connections → Throttle: 1 req/sec
# + NEWNYM ogni 50 richieste
```

### Lezione appresa

Per web app assessment su target con WAF avanzato, Tor da solo non basta.
Gli IP degli exit sono pubblici e bloccati preventivamente. La soluzione
è una catena Tor→VPS con IP dedicato, oppure negoziare con il cliente
il whitelisting dell'IP di test. Vedi [Siti che bloccano Tor](limitazioni-applicazioni.md#siti-che-bloccano-tor--strategie)
per le strategie di bypass.

---

## Scenario 3: Correlazione temporale deanonimizza operatore OSINT

### Contesto

Un analista OSINT usava Tor per monitorare un forum underground dove il
threat actor target era attivo. L'analista visitava il forum ogni giorno
durante l'orario di lavoro, usando NEWNYM prima di ogni sessione.

### Problema

Il threat actor gestiva il forum e aveva accesso ai log del web server.
Ha notato un pattern:

```
Log del web server (lato threat actor):
  Visitatore Tor, stesso browser fingerprint:
  - Lun-Ven, 09:30-10:00 e 14:00-14:30 (CET)
  - Mai weekend, mai festivi italiani
  - Sempre da exit europei
  - Navigazione: sempre sezioni "marketplace" e "leaks"
  - Timing: iniziato 3 giorni dopo il data breach dell'azienda X

Deduzione del threat actor:
  → Qualcuno sta investigando il breach dell'azienda X
  → Orari di lavoro italiani → probabilmente analista italiano
  → Ha iniziato dopo il breach → collegato all'incident response
  → Il threat actor ha modificato il suo comportamento
```

L'analista era deanonimizzato non tecnicamente (Tor funzionava) ma
**comportamentalmente**: i pattern temporali e la correlazione con
eventi noti hanno rivelato il suo ruolo.

### Fix procedurale

```
1. Variare orari di accesso: includere sessioni serali/weekend
2. Randomizzare l'inizio: non iniziare il giorno dopo l'evento
3. Creare rumore: visitare sezioni irrilevanti, altri forum simili
4. Variare il fingerprint: alternare Tor Browser e curl
5. Usare dead drop: scaricare snapshot del forum e analizzare offline
   → Riduce le visite dirette al minimo
```

### Lezione appresa

Tor protegge l'IP ma non il comportamento. L'avversario con accesso ai
log del server può correlare pattern temporali, di navigazione e di
fingerprint per identificare investigatori. La correlazione end-to-end
non richiede sempre un avversario globale - basta il controllo di un
endpoint. Vedi [Attacchi di correlazione](attacchi-noti.md#3-attacco-di-correlazione-end-to-end)
e [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md).

---

## Scenario 4: Sessione web invalidata durante exploitation via Tor

### Contesto

Durante un authorized pentest, un operatore aveva trovato una SQL injection
su un portale target. L'exploitation richiedeva più passaggi sequenziali:
login → navigazione a pagina vulnerabile → injection → estrazione dati.
L'operatore usava sqlmap via Tor con proxy SOCKS5.

### Problema

```bash
# Primo tentativo:
sqlmap -u "https://target.com/app?id=1" --proxy=socks5://127.0.0.1:9050 \
    --cookie="JSESSIONID=abc123" --dump

# Output sqlmap:
# [WARNING] target URL appears to be non-injectable
# HTTP error 302 (redirect to login page)
```

Il circuito Tor è cambiato durante l'exploitation (MaxCircuitDirtiness
default: 10 minuti). Il nuovo exit ha un IP diverso → il server ha
invalidato la sessione (JSESSIONID legato all'IP) → redirect al login
→ sqlmap non trova più la vulnerabilità.

```
Timeline:
  t=0:00  Login con exit 185.220.101.x → JSESSIONID creato per quell'IP
  t=8:00  sqlmap trova SQLi, inizia estrazione
  t=10:02 Circuito cambia → nuovo exit 104.244.76.x
  t=10:03 Server: IP diverso per JSESSIONID → sessione invalidata → 302
  t=10:04 sqlmap: "non-injectable" (perché ora vede la pagina di login)
```

### Fix

```ini
# torrc: aumentare MaxCircuitDirtiness per l'exploitation
MaxCircuitDirtiness 3600    # 1 ora (sufficiente per completare l'exploit)

# Oppure: usare IsolateDestAddr per stabilizzare il circuito per-target
SocksPort 9050 IsolateDestAddr
```

```bash
# Rilanciare sqlmap con circuito stabile:
sqlmap -u "https://target.com/app?id=1" --proxy=socks5://127.0.0.1:9050 \
    --cookie="JSESSIONID=abc123" --dump --threads=1
# → Con MaxCircuitDirtiness 3600, il circuito resta stabile per 1 ora
```

### Lezione appresa

Le sessioni web legate all'IP sono incompatibili con la rotazione dei
circuiti Tor. Per exploitation multi-step, aumentare `MaxCircuitDirtiness`
o usare `IsolateDestAddr` per mantenere lo stesso exit per lo stesso
target. Ricordare di ripristinare il valore default dopo l'operazione.
Vedi [Limitazioni del Protocollo](limitazioni-protocollo.md#circuiti-multipli-e-ip-variabili)
per il dettaglio tecnico.

---

## Riepilogo

| Scenario | Limitazione | Rischio mitigato |
|----------|-------------|------------------|
| nmap -sS via proxychains | Raw socket bypassa SOCKS | Leak IP reale durante scan |
| WAF blocca exit Tor | Lista exit pubblica | Assessment bloccato dopo poche richieste |
| Pattern temporali OSINT | Correlazione comportamentale | Deanonimizzazione per pattern di accesso |
| Sessione invalidata durante exploit | IP variabili / MaxCircuitDirtiness | Exploitation fallita per cambio circuito |

---

## Vedi anche

- [Limitazioni del Protocollo](limitazioni-protocollo.md) - TCP-only, latenza, bandwidth
- [Limitazioni nelle Applicazioni](limitazioni-applicazioni.md) - Cosa funziona e cosa no via Tor
- [Attacchi Noti](attacchi-noti.md) - Sybil, correlazione, website fingerprinting
- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Errori comportamentali
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - MaxCircuitDirtiness, NEWNYM
