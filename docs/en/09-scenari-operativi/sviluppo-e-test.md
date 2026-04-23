> **Lingua / Language**: [Italiano](../../09-scenari-operativi/sviluppo-e-test.md) | English

# Development and Testing via Tor

This document analyzes how to use Tor in the context of software development
and testing: testing web applications from different IPs, geolocation testing,
anonymous CI/CD, and debugging services via Tor.

> **See also**: [Tor and Localhost](../06-configurazioni-avanzate/tor-e-localhost.md),
> [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md),
> [ProxyChains](../04-strumenti-operativi/proxychains-guida-completa.md).

---

## Table of Contents

- [Why use Tor in development](#why-use-tor-in-development)
- [Testing from multiple IPs](#testing-from-multiple-ips)
- [Geolocation testing](#geolocation-testing)
- [Rate limiting and WAF testing](#rate-limiting-and-waf-testing)
- [Anonymous CI/CD](#anonymous-cicd)
- [API debugging via Tor](#api-debugging-via-tor)
- [Ethical scraping and testing](#ethical-scraping-and-testing)
- [Testing onion services](#testing-onion-services)
- [Tor limitations for testing](#tor-limitations-for-testing)
- [In my experience](#in-my-experience)

---

## Why use Tor in development

### Scenarios where Tor is useful for developers

| Scenario | Why Tor |
|----------|---------|
| Testing from different IPs | Each NEWNYM = different IP |
| Verifying geoblocking | Exit nodes in different countries |
| Testing rate limiting | Simulate different users |
| Testing WAF/CDN | Verify behavior with Tor IPs |
| Anonymous testing | Do not reveal who is testing |
| Bug bounty | Anonymous reconnaissance |
| Verifying censorship | Test accessibility from different networks |

---

## Testing from multiple IPs

### Script for testing with IP rotation

```bash
#!/bin/bash
# test-multi-ip.sh - Test an endpoint from different IPs

TARGET_URL="https://api.example.com/endpoint"
NUM_TESTS=10

echo "Testing $TARGET_URL from $NUM_TESTS different IPs"
echo "================================================="

for i in $(seq 1 $NUM_TESTS); do
    # Change IP
    echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc -w 3 127.0.0.1 9051 > /dev/null 2>&1
    sleep 10  # NEWNYM cooldown
    
    # Get new IP
    IP=$(proxychains curl -s --max-time 15 https://api.ipify.org 2>/dev/null)
    
    # Test endpoint
    HTTP_CODE=$(proxychains curl -s -o /dev/null -w "%{http_code}" --max-time 30 "$TARGET_URL" 2>/dev/null)
    RESPONSE_TIME=$(proxychains curl -s -o /dev/null -w "%{time_total}" --max-time 30 "$TARGET_URL" 2>/dev/null)
    
    echo "Test $i: IP=$IP HTTP=$HTTP_CODE Time=${RESPONSE_TIME}s"
done

echo "================================================="
echo "Testing completed."
```

### Python for testing with IP rotation

```python
#!/usr/bin/env python3
"""Test endpoint from multiple IPs via Tor with rotation."""

import requests
import time
from stem.control import Controller
from stem import Signal

SOCKS_PROXY = "socks5h://127.0.0.1:9050"
TARGET = "https://api.example.com/endpoint"

def new_identity():
    """Request a new Tor circuit."""
    with Controller.from_port(port=9051) as ctrl:
        ctrl.authenticate()
        ctrl.signal(Signal.NEWNYM)
    time.sleep(10)  # cooldown

def get_tor_ip():
    """Get current exit IP."""
    session = requests.Session()
    session.proxies = {"https": SOCKS_PROXY, "http": SOCKS_PROXY}
    return session.get("https://api.ipify.org", timeout=15).text

def test_endpoint(url):
    """Test the endpoint and return results."""
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
    
    # Summary
    codes = [r["status_code"] for r in results]
    times = [r["response_time"] for r in results]
    print(f"\nSummary: {len(set(codes))} different codes, "
          f"average time: {sum(times)/len(times):.2f}s")

if __name__ == "__main__":
    main()
```

---

## Geolocation testing

### Force exit in specific countries

```ini
# torrc - exit in Germany
ExitNodes {de}
StrictNodes 1
```

```bash
# Or via ControlPort
echo -e "AUTHENTICATE\r\nSETCONF ExitNodes={de}\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051

# Verify
proxychains curl -s https://ipinfo.io | grep country
# "country": "DE"

# Test your app
proxychains curl -s https://myapp.com/api/geo
# Should return content for German users
```

### Script for multi-country testing

```bash
#!/bin/bash
# test-geo.sh - Test your app's geolocation from different countries

TARGET="https://myapp.com/api/content"
COUNTRIES=("us" "de" "fr" "jp" "br" "au")

for country in "${COUNTRIES[@]}"; do
    echo "--- Testing from $country ---"
    
    # Configure exit in that country
    echo -e "AUTHENTICATE\r\nSETCONF ExitNodes={$country}\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc -w 3 127.0.0.1 9051
    sleep 12
    
    # Verify country
    GEO=$(proxychains curl -s --max-time 20 https://ipinfo.io/country 2>/dev/null)
    echo "  Exit country: $GEO"
    
    # Test endpoint
    RESULT=$(proxychains curl -s --max-time 20 "$TARGET" 2>/dev/null | head -c 200)
    echo "  Response: $RESULT"
    echo ""
done

# Restore configuration
echo -e "AUTHENTICATE\r\nSETCONF ExitNodes=\r\nQUIT\r\n" | nc -w 3 127.0.0.1 9051
echo "ExitNodes restored to default."
```

### Geolocation via Tor limitations

- Not all countries have active exit nodes
- `StrictNodes 1` can reduce available bandwidth
- Some services (Netflix, etc.) block all Tor IPs regardless of country
- The exit's geolocation may not match the IP (GeoIP is not perfect)

---

## Rate limiting and WAF testing

### Testing your app's rate limiter

```python
#!/usr/bin/env python3
"""Test rate limiting with IP rotation via Tor."""

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
    """Send N requests from the same IP, then rotate."""
    session = requests.Session()
    session.proxies = {"https": PROXY, "http": PROXY}
    
    ip = session.get("https://api.ipify.org", timeout=10).text
    print(f"\nTesting from IP: {ip}")
    
    for i in range(requests_per_ip):
        try:
            r = session.post(TARGET, json={"user": "test", "pass": "test"}, timeout=15)
            status = r.status_code
            
            if status == 429:
                print(f"  Request {i+1}: RATE LIMITED (429) ← rate limiter works")
                return i + 1  # requests before the limit
            elif status == 403:
                print(f"  Request {i+1}: BLOCKED (403) ← WAF blocked")
                return i + 1
            else:
                print(f"  Request {i+1}: {status}")
        except Exception as e:
            print(f"  Request {i+1}: ERROR ({e})")
        
        time.sleep(0.5)
    
    print(f"  No rate limiting after {requests_per_ip} requests!")
    return requests_per_ip

# Test from 3 different IPs
for test_num in range(3):
    new_ip()
    limit = test_rate_limit(20)
    print(f"Rate limit hit after {limit} requests")
```

### Testing WAF behavior with Tor IPs

Many WAFs (Cloudflare, AWS WAF) treat Tor IPs differently:

```bash
# Test: does your app block Tor IPs?
proxychains curl -s -o /dev/null -w "%{http_code}" https://myapp.com
# 200 → does not block Tor
# 403 → blocks Tor
# 503 → challenge/captcha (Cloudflare)

# Test with header check
proxychains curl -sI https://myapp.com | grep -iE "cf-|server:|x-"
```

---

## Anonymous CI/CD

### GitHub Actions via Tor (for pulling from private repos)

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

# Permanent configuration for a repo
git config http.proxy socks5h://127.0.0.1:9050
```

---

## API debugging via Tor

### Testing APIs from an external perspective

```bash
# Verify that the API is reachable from Tor
proxychains curl -sv https://api.myapp.com/v1/health 2>&1

# Test CORS from a Tor IP
proxychains curl -s -H "Origin: https://malicious-site.com" \
  -H "Access-Control-Request-Method: GET" \
  -X OPTIONS https://api.myapp.com/v1/data

# Test authentication from an unknown IP
proxychains curl -s -H "Authorization: Bearer TOKEN" \
  https://api.myapp.com/v1/protected
```

### Comparing local vs Tor responses

```bash
# Direct response (local)
curl -s https://api.myapp.com/v1/endpoint | python3 -m json.tool > response_direct.json

# Response via Tor
proxychains curl -s https://api.myapp.com/v1/endpoint 2>/dev/null | python3 -m json.tool > response_tor.json

# Compare
diff response_direct.json response_tor.json
# Differences may indicate: geo-filtering, IP-based content, WAF intervention
```

---

## Ethical scraping and testing

### Rate-limited scraping via Tor

```python
#!/usr/bin/env python3
"""Ethical scraping with rate limiting and IP rotation."""

import requests
import time
import random
from stem.control import Controller
from stem import Signal

PROXY = "socks5h://127.0.0.1:9050"

def polite_scrape(urls, delay_range=(5, 15), rotate_every=10):
    """Scraping with random delay and IP rotation."""
    session = requests.Session()
    session.proxies = {"https": PROXY, "http": PROXY}
    session.headers["User-Agent"] = "ResearchBot/1.0 (Academic research)"
    
    results = []
    
    for i, url in enumerate(urls):
        # IP rotation every N requests
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
        
        # Random delay (human-like behavior)
        delay = random.uniform(*delay_range)
        time.sleep(delay)
    
    return results
```

### Respecting robots.txt

```python
import urllib.robotparser

def check_robots(base_url, target_path):
    """Check robots.txt before scraping."""
    rp = urllib.robotparser.RobotFileParser()
    rp.set_url(f"{base_url}/robots.txt")
    rp.read()
    
    if not rp.can_fetch("*", f"{base_url}{target_path}"):
        print(f"BLOCKED by robots.txt: {target_path}")
        return False
    return True
```

---

## Testing onion services

### Testing your own onion service

```bash
# Verify that the .onion service is reachable
proxychains curl -s http://$(sudo cat /var/lib/tor/myservice/hostname)/

# Test latency
for i in $(seq 1 5); do
    TIME=$(proxychains curl -s -o /dev/null -w "%{time_total}" \
      http://$(sudo cat /var/lib/tor/myservice/hostname)/ 2>/dev/null)
    echo "Test $i: ${TIME}s"
done

# Test from a different circuit (NEWNYM first)
echo -e "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051
sleep 10
proxychains curl -s http://YOUR_ONION_ADDRESS.onion/
```

---

## Tor limitations for testing

| Limitation | Impact on testing | Workaround |
|------------|------------------|------------|
| Latency 200-800ms | Slow tests | Batch requests, parallelize |
| NEWNYM cooldown 10s | Slow IP rotation | Plan tests accordingly |
| Shared exit IPs | Rate limiting | Delay between requests |
| No UDP | DNS/QUIC testing impossible | TCP-only tests |
| Variable bandwidth | Unreliable performance tests | Average over multiple tests |
| Blocked exits | Some sites inaccessible | Verify beforehand |

---

## In my experience

I regularly use Tor in my development and testing workflow:

**Geolocation testing**: I used the multi-country script to verify
that a web application responded correctly with localized content
for different countries. It works well with `ExitNodes {country}`, but not all
countries have reliable exit nodes - for less common countries (Asia, Africa) the circuits
were often slow or failed.

**Dockerized API debugging**: as documented in the Tor and localhost section,
I tested my dockerized REST API both locally and via Tor to verify
behavior with external IPs. Useful for testing CORS and rate limiting.

**git via Tor**: I use `torsocks git clone` when cloning repositories from sources
that I do not want to link to my personal IP. The clone is slower but works
perfectly.

**Rate limiting**: I used the test script to verify the rate limiter
of a project. Result: the IP-based rate limiter worked, but was
easily bypassed with Tor's IP rotation. This led me to
also implement token/session-based rate limiting.

---

## See also

- [Multi-Instance and Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) - Separate circuits for parallel testing
- [Circuit Control and NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) - IP rotation for testing
- [ProxyChains - Complete Guide](../04-strumenti-operativi/proxychains-guida-completa.md) - Proxying development tools
- [Application Limitations](../07-limitazioni-e-attacchi/limitazioni-applicazioni.md) - What works and what does not via Tor
