> **Lingua / Language**: Italiano | [English](../en/09-scenari-operativi/sviluppo-e-test.md)

# Sviluppo e Test via Tor

Questo documento analizza come usare Tor nel contesto dello sviluppo software
e del testing: testare applicazioni web da IP diversi, testing di geolocalizzazione,
CI/CD anonimo, e debug di servizi via Tor.

> **Vedi anche**: [Tor e Localhost](../06-configurazioni-avanzate/tor-e-localhost.md),
> [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md),
> [ProxyChains](../04-strumenti-operativi/proxychains-guida-completa.md).

---

## Indice

- [Perché usare Tor nello sviluppo](#perché-usare-tor-nello-sviluppo)
- [Testing da IP multipli](#testing-da-ip-multipli)
- [Testing di geolocalizzazione](#testing-di-geolocalizzazione)
- [Testing di rate limiting e WAF](#testing-di-rate-limiting-e-waf)
- [CI/CD anonimo](#cicd-anonimo)
- [Debug API via Tor](#debug-api-via-tor)
- [Scraping etico e testing](#scraping-etico-e-testing)
- [Testing onion services](#testing-onion-services)
- [Limiti di Tor per testing](#limiti-di-tor-per-testing)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Perché usare Tor nello sviluppo

### Scenari dove Tor è utile per sviluppatori

| Scenario | Perché Tor |
|----------|-----------|
| Testare da IP diversi | Ogni NEWNYM = IP diverso |
| Verificare geoblocking | Exit node in paesi diversi |
| Testare rate limiting | Simulare utenti diversi |
| Testare WAF/CDN | Verificare comportamento con IP Tor |
| Testing anonimo | Non rivelare chi sta testando |
| Bug bounty | Ricognizione anonima |
| Verificare censura | Testare accessibilità da reti diverse |

---

## Testing da IP multipli

### Script per test con IP rotation

```bash
#!/bin/bash
# test-multi-ip.sh - Testa un endpoint da IP diversi

TARGET_URL="https://api.example.com/endpoint"
NUM_TESTS=10

echo "Testing $TARGET_URL da $NUM_TESTS IP diversi"
echo "================================================="

for i in $(seq 1 $NUM_TESTS); do
    # Cambia IP
    echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc -w 3 127.0.0.1 9051 > /dev/null 2>&1
    sleep 10  # Cooldown NEWNYM
    
    # Ottieni nuovo IP
    IP=$(proxychains curl -s --max-time 15 https://api.ipify.org 2>/dev/null)
    
    # Test endpoint
    HTTP_CODE=$(proxychains curl -s -o /dev/null -w "%{http_code}" --max-time 30 "$TARGET_URL" 2>/dev/null)
    RESPONSE_TIME=$(proxychains curl -s -o /dev/null -w "%{time_total}" --max-time 30 "$TARGET_URL" 2>/dev/null)
    
    echo "Test $i: IP=$IP HTTP=$HTTP_CODE Time=${RESPONSE_TIME}s"
done

echo "================================================="
echo "Testing completato."
```

### Python per test con IP rotation

```python
#!/usr/bin/env python3
"""Test endpoint da IP multipli via Tor con rotation."""

import requests
import time
from stem.control import Controller
from stem import Signal

SOCKS_PROXY = "socks5h://127.0.0.1:9050"
TARGET = "https://api.example.com/endpoint"

def new_identity():
    """Richiedi nuovo circuito Tor."""
    with Controller.from_port(port=9051) as ctrl:
        ctrl.authenticate()
        ctrl.signal(Signal.NEWNYM)
    time.sleep(10)  # cooldown

def get_tor_ip():
    """Ottieni IP exit corrente."""
    session = requests.Session()
    session.proxies = {"https": SOCKS_PROXY, "http": SOCKS_PROXY}
    return session.get("https://api.ipify.org", timeout=15).text

def test_endpoint(url):
    """Testa l'endpoint e restituisci risultati."""
    session = requests.Session()
    session.proxies = {"https": SOCKS_PROXY, "http": SOCKS_PROXY}
    
    start = time.time()
    response = session.get(url, timeout=30)
    elapsed = time.time() - start
    
    return {
        "status_code": response.status_code,
        "response_time": round(elapsed, 2),
        "content_length": len(response.content),
    }

def main():
    results = []
    
    for i in range(10):
        new_identity()
        ip = get_tor_ip()
        result = test_endpoint(TARGET)
        result["ip"] = ip
        result["test_num"] = i + 1
        results.append(result)
        
        print(f"Test {i+1}: IP={ip} HTTP={result['status_code']} "
              f"Time={result['response_time']}s")
    
    # Riepilogo
    codes = [r["status_code"] for r in results]
    times = [r["response_time"] for r in results]
    print(f"\nRiepilogo: {len(set(codes))} codici diversi, "
          f"tempo medio: {sum(times)/len(times):.2f}s")

if __name__ == "__main__":
    main()
```

---

## Testing di geolocalizzazione

### Forzare exit in paesi specifici

```ini
# torrc - exit in Germania
ExitNodes {de}
StrictNodes 1
```

```bash
# Oppure via ControlPort
echo -e "AUTHENTICATE\r\nSETCONF ExitNodes={de}\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051

# Verificare
proxychains curl -s https://ipinfo.io | grep country
# "country": "DE"

# Testare la tua app
proxychains curl -s https://myapp.com/api/geo
# Dovrebbe restituire contenuto per utenti tedeschi
```

### Script per test multi-paese

```bash
#!/bin/bash
# test-geo.sh - Testa la geolocalizzazione della tua app da paesi diversi

TARGET="https://myapp.com/api/content"
COUNTRIES=("us" "de" "fr" "jp" "br" "au")

for country in "${COUNTRIES[@]}"; do
    echo "--- Testing da $country ---"
    
    # Configura exit in quel paese
    echo -e "AUTHENTICATE\r\nSETCONF ExitNodes={$country}\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc -w 3 127.0.0.1 9051
    sleep 12
    
    # Verifica paese
    GEO=$(proxychains curl -s --max-time 20 https://ipinfo.io/country 2>/dev/null)
    echo "  Exit country: $GEO"
    
    # Testa endpoint
    RESULT=$(proxychains curl -s --max-time 20 "$TARGET" 2>/dev/null | head -c 200)
    echo "  Response: $RESULT"
    echo ""
done

# Ripristina configurazione
echo -e "AUTHENTICATE\r\nSETCONF ExitNodes=\r\nQUIT\r\n" | nc -w 3 127.0.0.1 9051
echo "ExitNodes ripristinato a default."
```

### Limitazioni della geolocalizzazione via Tor

- Non tutti i paesi hanno exit node attivi
- `StrictNodes 1` può ridurre la bandwidth disponibile
- Alcuni servizi (Netflix, etc.) bloccano tutti gli IP Tor indipendentemente dal paese
- La geolocalizzazione dell'exit potrebbe non corrispondere all'IP (GeoIP non è perfetto)

---

## Testing di rate limiting e WAF

### Testare il rate limiter della tua app

```python
#!/usr/bin/env python3
"""Testa il rate limiting con IP rotation via Tor."""

import requests
import time
from stem.control import Controller
from stem import Signal

PROXY = "socks5h://127.0.0.1:9050"
TARGET = "https://myapp.com/api/login"

def new_ip():
    with Controller.from_port(port=9051) as ctrl:
        ctrl.authenticate()
        ctrl.signal(Signal.NEWNYM)
    time.sleep(10)

def test_rate_limit(requests_per_ip=20):
    """Invia N richieste dallo stesso IP, poi cambia."""
    session = requests.Session()
    session.proxies = {"https": PROXY, "http": PROXY}
    
    ip = session.get("https://api.ipify.org", timeout=10).text
    print(f"\nTesting da IP: {ip}")
    
    for i in range(requests_per_ip):
        try:
            r = session.post(TARGET, json={"user": "test", "pass": "test"}, timeout=15)
            status = r.status_code
            
            if status == 429:
                print(f"  Request {i+1}: RATE LIMITED (429) ← rate limiter funziona")
                return i + 1  # richieste prima del limit
            elif status == 403:
                print(f"  Request {i+1}: BLOCKED (403) ← WAF ha bloccato")
                return i + 1
            else:
                print(f"  Request {i+1}: {status}")
        except Exception as e:
            print(f"  Request {i+1}: ERROR ({e})")
        
        time.sleep(0.5)
    
    print(f"  Nessun rate limiting dopo {requests_per_ip} richieste!")
    return requests_per_ip

# Test da 3 IP diversi
for test_num in range(3):
    new_ip()
    limit = test_rate_limit(20)
    print(f"Rate limit hit dopo {limit} richieste")
```

### Testare il comportamento WAF con IP Tor

Molti WAF (Cloudflare, AWS WAF) trattano gli IP Tor diversamente:

```bash
# Test: la tua app blocca gli IP Tor?
proxychains curl -s -o /dev/null -w "%{http_code}" https://myapp.com
# 200 → non blocca Tor
# 403 → blocca Tor
# 503 → challenge/captcha (Cloudflare)

# Test con header check
proxychains curl -sI https://myapp.com | grep -iE "cf-|server:|x-"
```

---

## CI/CD anonimo

### GitHub Actions via Tor (per pull da repo privati)

```yaml
# .github/workflows/anonymous-test.yml
name: Anonymous Test
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Setup Tor
        run: |
          sudo apt-get update && sudo apt-get install -y tor
          sudo systemctl start tor
          sleep 10
      
      - name: Verify Tor
        run: |
          torsocks curl -s https://check.torproject.org/api/ip
      
      - name: Run tests via Tor
        run: |
          torsocks npm test
```

### git via Tor

```bash
# Clone via Tor
torsocks git clone https://github.com/user/repo.git

# Push via Tor
torsocks git push origin main

# Configurazione permanente per un repo
git config http.proxy socks5h://127.0.0.1:9050
```

---

## Debug API via Tor

### Testare API da prospettiva esterna

```bash
# Verificare che l'API sia raggiungibile da Tor
proxychains curl -sv https://api.myapp.com/v1/health 2>&1

# Testare CORS da IP Tor
proxychains curl -s -H "Origin: https://malicious-site.com" \
  -H "Access-Control-Request-Method: GET" \
  -X OPTIONS https://api.myapp.com/v1/data

# Testare autenticazione da IP sconosciuto
proxychains curl -s -H "Authorization: Bearer TOKEN" \
  https://api.myapp.com/v1/protected
```

### Confronto risposte locale vs Tor

```bash
# Risposta diretta (locale)
curl -s https://api.myapp.com/v1/endpoint | python3 -m json.tool > response_direct.json

# Risposta via Tor
proxychains curl -s https://api.myapp.com/v1/endpoint 2>/dev/null | python3 -m json.tool > response_tor.json

# Confronta
diff response_direct.json response_tor.json
# Differenze possono indicare: geo-filtering, IP-based content, WAF intervention
```

---

## Scraping etico e testing

### Rate-limited scraping via Tor

```python
#!/usr/bin/env python3
"""Scraping etico con rate limiting e IP rotation."""

import requests
import time
import random
from stem.control import Controller
from stem import Signal

PROXY = "socks5h://127.0.0.1:9050"

def polite_scrape(urls, delay_range=(5, 15), rotate_every=10):
    """Scraping con delay random e rotazione IP."""
    session = requests.Session()
    session.proxies = {"https": PROXY, "http": PROXY}
    session.headers["User-Agent"] = "ResearchBot/1.0 (Academic research)"
    
    results = []
    
    for i, url in enumerate(urls):
        # Rotazione IP ogni N richieste
        if i > 0 and i % rotate_every == 0:
            with Controller.from_port(port=9051) as ctrl:
                ctrl.authenticate()
                ctrl.signal(Signal.NEWNYM)
            time.sleep(10)
            print(f"[IP rotated at request {i}]")
        
        try:
            r = session.get(url, timeout=30)
            results.append({"url": url, "status": r.status_code, "size": len(r.content)})
            print(f"[{i+1}/{len(urls)}] {r.status_code} {url[:60]}")
        except Exception as e:
            results.append({"url": url, "status": "error", "error": str(e)})
            print(f"[{i+1}/{len(urls)}] ERROR {url[:60]}: {e}")
        
        # Delay random (comportamento umano)
        delay = random.uniform(*delay_range)
        time.sleep(delay)
    
    return results
```

### Rispettare robots.txt

```python
import urllib.robotparser

def check_robots(base_url, target_path):
    """Verifica robots.txt prima di scrapare."""
    rp = urllib.robotparser.RobotFileParser()
    rp.set_url(f"{base_url}/robots.txt")
    rp.read()
    
    if not rp.can_fetch("*", f"{base_url}{target_path}"):
        print(f"BLOCCATO da robots.txt: {target_path}")
        return False
    return True
```

---

## Testing onion services

### Testare il proprio onion service

```bash
# Verificare che il servizio .onion sia raggiungibile
proxychains curl -s http://$(sudo cat /var/lib/tor/myservice/hostname)/

# Testare latenza
for i in $(seq 1 5); do
    TIME=$(proxychains curl -s -o /dev/null -w "%{time_total}" \
      http://$(sudo cat /var/lib/tor/myservice/hostname)/ 2>/dev/null)
    echo "Test $i: ${TIME}s"
done

# Testare da un altro circuito (NEWNYM prima)
echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051
sleep 10
proxychains curl -s http://YOUR_ONION_ADDRESS.onion/
```

---

## Limiti di Tor per testing

| Limite | Impatto sul testing | Workaround |
|--------|-------------------|------------|
| Latenza 200-800ms | Test lenti | Batch requests, parallelize |
| NEWNYM cooldown 10s | Rotazione IP lenta | Pianificare i test |
| Exit IP condivisi | Rate limiting | Delay tra richieste |
| No UDP | Test DNS/QUIC impossibili | Test solo TCP |
| Bandwidth variabile | Test performance inaffidabili | Media su più test |
| Exit bloccati | Alcuni siti inaccessibili | Verificare prima |

---

## Nella mia esperienza

Uso Tor regolarmente nel mio workflow di sviluppo e testing:

**Test geolocalizzazione**: ho usato lo script multi-paese per verificare
che un'applicazione web rispondesse correttamente con contenuti localizzati
per diversi paesi. Funziona bene con `ExitNodes {country}`, ma non tutti i
paesi hanno exit node affidabili - per paesi rari (Asia, Africa) i circuiti
erano spesso lenti o fallivano.

**Debug API dockerizzata**: come documentato nella sezione su Tor e localhost,
ho testato la mia REST API dockerizzata sia in locale che via Tor per verificare
il comportamento con IP esterni. Utile per testare CORS e rate limiting.

**git via Tor**: uso `torsocks git clone` quando clono repository da fonti
che non voglio collegare al mio IP personale. Il clone è più lento ma funziona
perfettamente.

**Rate limiting**: ho usato lo script di test per verificare il rate limiter
di un progetto. Risultato: il rate limiter basato su IP funzionava, ma era
facilmente aggirabile con la rotazione IP di Tor. Questo mi ha portato a
implementare anche rate limiting basato su token/sessione.

---

## Vedi anche

- [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Circuiti separati per test paralleli
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - Rotazione IP per test
- [ProxyChains - Guida Completa](../04-strumenti-operativi/proxychains-guida-completa.md) - Proxare strumenti di sviluppo
- [Limitazioni nelle Applicazioni](../07-limitazioni-e-attacchi/limitazioni-applicazioni.md) - Cosa funziona e cosa no via Tor
