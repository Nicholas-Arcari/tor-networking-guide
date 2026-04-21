> **Lingua / Language**: [Italiano](../../06-configurazioni-avanzate/localhost-docker-e-sviluppo.md) | English

# Tor and Localhost - Docker, Web Development and Onion Services

Docker and Tor (containers via Tor, .onion services, API debugging), local web
development with Tor active, onion services for local services, interaction with
system services, and browser/localhost compatibility matrix.

> **Extracted from**: [Tor and Localhost](tor-e-localhost.md) for the problem,
> the Local Service Discovery attack, and the basic solutions.

---

## Docker and Tor - advanced scenarios

### Scenario 1: Container that exits via Tor

The Docker container must use Tor for external connections:

```yaml
# docker-compose.yml
services:
  app:
    build: .
    network_mode: "host"  # shares the network with the host
    # Now the container sees 127.0.0.1:9050 (host's Tor SocksPort)
    environment:
      - HTTP_PROXY=socks5h://127.0.0.1:9050
      - HTTPS_PROXY=socks5h://127.0.0.1:9050
```

Alternative with bridge network:

```yaml
services:
  app:
    build: .
    environment:
      - HTTP_PROXY=socks5h://host.docker.internal:9050
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

### Scenario 2: Container that exposes a .onion service

```yaml
services:
  tor:
    image: osminogin/tor-simple
    volumes:
      - ./torrc:/etc/tor/torrc
      - tor-data:/var/lib/tor
    ports:
      - "9050:9050"
  
  webapp:
    build: .
    expose:
      - "5173"

volumes:
  tor-data:
```

```ini
# torrc for the Tor container
HiddenServiceDir /var/lib/tor/webapp/
HiddenServicePort 80 webapp:5173
```

### Scenario 3: Debugging a containerized API

My specific case: RESTful API on port 5173 in Docker.

```bash
# From host, without Tor (works):
curl http://localhost:5173/api/status

# From host, via Tor for testing (works):
torsocks curl http://localhost:5173/api/status
# (with AllowOutboundLocalhost 1 in torsocks.conf)

# From Tor Browser (DOES NOT work):
# -> Blocked by network.proxy.allow_hijacking_localhost

# Solution: do not use Tor Browser for local debugging
```

### Scenario 4: Docker network mode and implications

```
network_mode: "bridge" (default):
  Container has its own network interface (172.17.0.x)
  Cannot see host services on 127.0.0.1
  Must use host.docker.internal to reach the host

network_mode: "host":
  Container shares the host's network stack
  Sees 127.0.0.1:9050 (Tor SocksPort)
  But also exposes its own ports on host's localhost

network_mode: "none":
  No network -> maximum isolation
  Useful for containers that only process local data
```

### Scenario 5: Container with integrated torsocks

```dockerfile
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y torsocks curl
COPY torsocks.conf /etc/tor/torsocks.conf
# In torsocks.conf: TorAddress host.docker.internal, TorPort 9050
ENTRYPOINT ["torsocks"]
CMD ["curl", "https://api.ipify.org"]
```

---

## Local web development with Tor active

### The split routing problem

When you develop a web application and also use Tor:

```
Simultaneous needs:
  1. Access localhost:5173 (Vite/React/Django dev server)
  2. Browse anonymously via Tor
  3. Download dependencies (npm, pip) -> fast, Tor not needed
  4. Access external APIs during development -> depends
```

### Solution: separate browser profiles

```bash
# Profile 1: Development (no proxy, localhost access)
firefox -no-remote -P development &

# Profile 2: Anonymous browsing (proxychains + Tor)
proxychains firefox -no-remote -P tor-proxy &

# The two profiles are completely isolated:
# - Separate cookies
# - Separate cache
# - Separate proxy settings
```

### Proxy bypass configuration for localhost

In Firefox (development profile), if you need the proxy for some sites
but not for localhost:

```
Preferences -> Network Settings -> Manual proxy configuration:
  SOCKS Host: 127.0.0.1    Port: 9050
  No proxy for: localhost, 127.0.0.1, ::1, 192.168.0.0/16
```

### Framework specifics

| Framework | Dev server | Default port | Notes with Tor |
|-----------|-----------|--------------|----------------|
| Vite | `npm run dev` | 5173 | localhost works without Tor |
| React (CRA) | `npm start` | 3000 | Hot reload on localhost |
| Next.js | `npm run dev` | 3000 | API routes on localhost |
| Django | `manage.py runserver` | 8000 | Admin on localhost |
| Flask | `flask run` | 5000 | Debug mode on localhost |
| Express | `node server.js` | 3000 | API on localhost |

---

## Onion services for local services

### The secure alternative to localhost bypass

Instead of disabling Tor Browser's protection, you can expose your
local service as `.onion`:

```ini
# Add to torrc
HiddenServiceDir /var/lib/tor/local-dev/
HiddenServicePort 80 127.0.0.1:5173
```

```bash
# Restart Tor
sudo systemctl restart tor@default.service

# Read the generated .onion address
sudo cat /var/lib/tor/local-dev/hostname
# abcdef...xyz.onion

# Now accessible from Tor Browser:
# http://abcdef...xyz.onion -> your localhost:5173
```

### Advantages

- **No security bypass**: Tor Browser works normally
- **Accessible from other devices via Tor**: you can test from a phone
- **End-to-end encrypted**: traffic is protected all the way to your service
- **No exit node involved**: direct connection via rendezvous

### Limitations

- **Latency**: the .onion connection has ~200-500ms of additional latency
- **Slow hot reload**: frontend frameworks with hot module reload will be slow
- **Overhead**: for simple development, it is excessive
- **Persistence**: the .onion address changes if you remove `HiddenServiceDir`

---

## Interaction with system services

### Services on localhost and Tor

| Service | Port | Risk if exposed via Tor |
|---------|------|------------------------|
| PostgreSQL | 5432 | DB access -> data breach |
| MySQL | 3306 | DB access -> data breach |
| Redis | 6379 | Often no auth -> RCE possible |
| Elasticsearch | 9200 | API without auth -> data leak |
| MongoDB | 27017 | Often no auth -> data leak |
| Tor ControlPort | 9051 | Circuit manipulation, NEWNYM |
| Docker API | 2375 | Full container control -> RCE |

### The ControlPort special case

The ControlPort (9051) is particularly sensitive:

```
If a malicious site could connect to 127.0.0.1:9051:
  -> AUTHENTICATE (if no auth or weak password)
  -> GETINFO address -> your real IP!
  -> SIGNAL NEWNYM -> force circuit change
  -> SETCONF -> modify Tor configuration
  -> Complete deanonymization
```

This is why `CookieAuthentication 1` in the torrc is essential, and Tor
Browser's localhost block is a second line of defense.

---

## Browser/localhost compatibility matrix

| Browser / Configuration | localhost HTTP | localhost HTTPS | .onion | Notes |
|-------------------------|---------------|-----------------|--------|-------|
| **Tor Browser** (default) | Blocked | Blocked | Yes | Active protection |
| **Tor Browser** (allow_hijacking=true) | Works* | Works* | Yes | Insecure |
| **Firefox + proxychains** | Works | Works | Yes** | localnet in config |
| **Firefox tor-proxy profile** | Works | Works | Yes** | No proxy for localhost |
| **Firefox manual SOCKS5** | Depends*** | Depends*** | Yes** | Depends on config |
| **Chrome + proxy** | Works | Works | No | Chrome does not natively support .onion |
| **curl --socks5-hostname** | Blocked**** | Blocked**** | Yes | Exit sees its own localhost |
| **torsocks curl** | Works | Works | Yes | AllowOutboundLocalhost=1 |

```
*    Works but the request goes to the exit node (which sees its own localhost)
**   Requires AutomapHostsOnResolve or proxy_dns
***  Depends on "no proxy for" setting
**** localhost is sent to the exit node, which connects to its own 127.0.0.1
```

---

## In my experience

I encountered this problem directly while debugging a dockerized RESTful API
web application on Kali. The API was running in a Docker container on port 5173,
and I was using Tor Browser for other purposes at the same time.

When I tried to open `localhost:5173` in Tor Browser to test the API,
I received "Unable to connect". My first reaction was to think Docker
had a networking problem, but verifying with `curl http://localhost:5173`
everything was working perfectly.

The solution I use daily is simple:

```bash
# Local development -> normal Firefox
firefox -P development http://localhost:5173

# Anonymous browsing -> Firefox tor-proxy via proxychains
proxychains firefox -no-remote -P tor-proxy & disown
```

Two browsers, two profiles, two different purposes. The `development` profile has
no proxy configured and accesses localhost directly. The `tor-proxy` profile
uses proxychains and browses anonymously.

I also tested the onion service solution to expose the local service
as `.onion`, and it works perfectly - but it adds ~300ms of latency that
makes Vite's hot reload frustrating. For development, profile separation
is the best solution.

Lesson learned: **it is not necessary to access local services via Tor
Browser**. They are two different use cases that require different tools. Trying
to force Tor Browser to access localhost is both a security risk
and an unnecessary workaround.

---

## See also

- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) - Secure alternative for exposing local services
- [Multi-Instance and Stream Isolation](multi-istanza-e-stream-isolation.md) - Tor instances for different services
- [System Hardening](../05-sicurezza-operativa/hardening-sistema.md) - Protecting local services
- [Transparent Proxy](transparent-proxy.md) - TransPort and interaction with localhost
