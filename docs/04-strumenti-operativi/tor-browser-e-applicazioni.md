# Tor Browser e Routing delle Applicazioni

Questo documento analizza Tor Browser (le sue protezioni interne), la differenza
con Firefox+proxychains, e come instradare diverse applicazioni attraverso Tor
nel mondo reale.

Basato sulla mia esperienza con Firefox + profilo `tor-proxy` via proxychains,
e la consapevolezza dei limiti di questo approccio rispetto a Tor Browser.

---

## Tor Browser — Cosa fa che Firefox non fa

Tor Browser è un Firefox ESR modificato con patch specifiche. Non è "Firefox con
un proxy SOCKS configurato". Le differenze sono profonde:

### Protezioni anti-fingerprinting

| Vettore di fingerprinting | Firefox normale | Tor Browser |
|--------------------------|----------------|-------------|
| User-Agent | Rivela OS, versione, architettura | Uniformato a un valore standard |
| Dimensioni finestra | Riflette il monitor reale | Arrotondate a multipli (letterboxing) |
| Canvas | Rivela GPU e driver | Randomizzato o bloccato |
| WebGL | Rivela modello GPU | Disabilitato o spoofato |
| Font | Rivela font installati (unici per OS) | Solo font di sistema standard |
| Timezone | Rivela la tua timezone | Sempre UTC |
| Lingua | Rivela lingua del sistema | Sempre en-US |
| Screen resolution | Rivela monitor reale | Spoofata |
| AudioContext | Fingerprint audio hardware | Neutralizzato |
| Battery API | Rivela stato batteria | Disabilitato |
| Connection API | Rivela tipo connessione | Disabilitato |
| Plugins/Extensions | Lista estensioni installate | Nessuna estensione visibile |

### Protezioni di rete

| Protezione | Firefox normale | Tor Browser |
|-----------|----------------|-------------|
| WebRTC | Attivo (leak IP reale!) | **Disabilitato** |
| DNS | Usa resolver di sistema | Sempre via Tor |
| Prefetch DNS | Attivo (precarica DNS) | **Disabilitato** |
| HTTP/3 (QUIC) | Attivo (usa UDP) | **Disabilitato** |
| Speculative connections | Attive | **Disabilitate** |
| HSTS tracking | Possibile | Mitigato |
| OCSP requests | In chiaro | Disabilitato |

### Isolamento per dominio

Tor Browser implementa **First-Party Isolation (FPI)**:
- I cookie sono isolati per dominio di primo livello
- Le cache sono isolate per dominio
- Le connessioni TLS sono isolate per dominio
- Ogni dominio usa un circuito diverso (tramite SOCKS auth diverso)

Questo impedisce il tracking cross-site: un tracker su `sito-a.com` non può
correlare con lo stesso tracker su `sito-b.com`.

---

## Firefox + proxychains — Il mio setup e i suoi limiti

### Come ho configurato il mio setup

```bash
# 1. Creare un profilo dedicato (una tantum)
firefox -no-remote -CreateProfile tor-proxy

# 2. Avviare Firefox con il profilo, via proxychains
proxychains firefox -no-remote -P tor-proxy & disown
```

Il flag `-no-remote` impedisce a Firefox di connettersi a un'istanza esistente
(che potrebbe non passare da Tor).

### Configurazioni manuali necessarie nel profilo

In `about:config` del profilo `tor-proxy`:

```
media.peerconnection.enabled = false        # Disabilita WebRTC (previene IP leak)
network.http.http3.enabled = false           # Disabilita QUIC/HTTP3 (usa UDP)
network.dns.disablePrefetch = true           # No DNS prefetch
network.prefetch-next = false                # No prefetch pagine
network.predictor.enabled = false            # No connessioni speculative
browser.send_pings = false                   # No tracking pings
geo.enabled = false                          # No geolocalizzazione
privacy.resistFingerprinting = true          # Attiva resistenza fingerprinting base
```

### Cosa questo setup NON protegge

Anche con queste configurazioni, Firefox normale:
- Ha un user-agent diverso da Tor Browser (identificabile)
- Non ha letterboxing (le dimensioni finestra rivelano il monitor)
- Non isola i cookie per dominio come Tor Browser
- Non spoofa timezone, lingua, font
- Ha un canvas fingerprint unico
- Le estensioni installate sono rilevabili

**Conclusione**: uso questo setup per comodità e test, non per anonimato massimo.
Per anonimato reale, bisogna usare Tor Browser.

---

## Instradare diverse applicazioni attraverso Tor

### Matrice di compatibilità

| Applicazione | Metodo | Funziona? | Note |
|-------------|--------|-----------|------|
| curl | `--socks5-hostname` o proxychains | Si | Perfetto |
| wget | proxychains | Si | Funziona bene |
| Firefox | proxychains + profilo dedicato | Si | Senza protezioni anti-fingerprint |
| git (HTTPS) | proxychains | Si | Clone, pull, push |
| git (SSH) | proxychains | Parziale | Lento, timeout possibili |
| ssh | proxychains o torsocks | Si | Lento ma funzionante |
| nmap TCP | proxychains (-sT) | Si | Solo TCP connect scan |
| nmap SYN | Non supportato | No | SYN scan richiede raw socket |
| ping | Non supportato | No | ICMP non supportato da Tor |
| traceroute | Non supportato | No | ICMP/UDP |
| pip/npm | proxychains | Si | Installa pacchetti via Tor |
| apt | Non consigliato | Parziale | Meglio usare Tor APT transport |
| Discord | proxychains | No | Usa UDP/WebSocket non standard |
| Telegram Desktop | proxychains | Parziale | Solo con proxy SOCKS5 nelle impostazioni |
| Spotify | proxychains | No | Usa protocollo proprietario |
| Steam | proxychains | No | Usa UDP per gaming |

### Applicazioni che supportano SOCKS5 nativamente

Alcune applicazioni hanno configurazione proxy integrata:

**Firefox** (nel profilo `tor-proxy`):
```
Settings → Network Settings → Manual proxy configuration
  SOCKS Host: 127.0.0.1
  SOCKS Port: 9050
  SOCKS v5
  ☑ Proxy DNS when using SOCKS v5
```

**git**:
```bash
git config --global http.proxy socks5h://127.0.0.1:9050
git config --global https.proxy socks5h://127.0.0.1:9050
```
(`socks5h` = risolvi hostname via proxy, come `--socks5-hostname`)

**SSH** (via `~/.ssh/config`):
```
Host *.onion
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

---

## Tor Browser vs il mio setup — Riepilogo

| Aspetto | Tor Browser | Il mio setup (Firefox+proxychains) |
|---------|-------------|----------------------------------|
| Anonimato IP | Eccellente | Eccellente |
| Anti-fingerprinting | Eccellente | Scarso |
| DNS leak prevention | Automatico | Richiede config (proxy_dns) |
| WebRTC protection | Automatico | Manuale (about:config) |
| Cross-site tracking | FPI (automatico) | Nessuna protezione |
| Facilità d'uso | Scarica e avvia | Configurazione manuale |
| Flessibilità | Limitata (è un browser) | Alta (qualsiasi app) |
| Per anonimato massimo | **SI** | NO |
| Per test e sviluppo | Poco pratico | **SI** |

Il mio setup è un compromesso consapevole: sacrifico l'anti-fingerprinting per
avere la flessibilità di usare Tor con qualsiasi strumento CLI e con Firefox
in un ambiente di sviluppo.
