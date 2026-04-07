# Verifica IP, DNS e Leak — Test Completi per la Sicurezza di Tor

Questo documento copre tutti i metodi per verificare che il traffico stia effettivamente
passando attraverso Tor, che non ci siano DNS leak, e che l'identità reale non sia
esposta. Include test manuali, automatici, e analisi di ogni tipo di leak possibile.

Basato sulla mia esperienza nel verificare l'IP di uscita, nel confrontare l'IP reale
(Parma, Italia) con l'IP Tor, e nel diagnosticare problemi di leak.

---
---

## Indice

- [Verifica dell'IP — Metodi completi](#verifica-dellip-metodi-completi)
- [Test DNS Leak](#test-dns-leak)
- [Verifica delle porte in ascolto](#verifica-delle-porte-in-ascolto)
- [Tipi di leak e come prevenirli](#tipi-di-leak-e-come-prevenirli)
- [Nella mia esperienza](#nella-mia-esperienza)


## Verifica dell'IP — Metodi completi

### 1. IP reale (senza Tor)

```bash
> curl https://api.ipify.org
xxx.xxx.xxx.xxx    # il mio IP reale (censurato — ISP Comeser, Parma)
```

### 2. IP via Tor (curl diretto)

```bash
> curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
185.220.101.143    # IP dell'exit node Tor
```

La flag `--socks5-hostname` è **fondamentale**: invia l'hostname al proxy SOCKS5
(Tor), che lo risolve via la rete Tor. Senza `hostname`:

```bash
# SBAGLIATO — causa DNS leak
> curl --socks5 127.0.0.1:9050 https://api.ipify.org
# curl risolve "api.ipify.org" LOCALMENTE prima di inviare a Tor → DNS leak
```

### 3. IP via Tor (proxychains)

```bash
> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
185.220.101.143
```

Con `proxy_dns` attivo in proxychains.conf, il DNS è risolto via Tor (no leak).

### 4. Informazioni dettagliate sull'IP

```bash
> proxychains curl -s https://ipinfo.io
{
  "ip": "185.220.101.143",
  "hostname": "tor-exit-relay.example.com",
  "city": "Amsterdam",
  "region": "North Holland",
  "country": "NL",
  "loc": "52.3676,4.9041",
  "org": "AS60729 Stichting Tor Exit",
  "timezone": "Europe/Amsterdam"
}
```

Informazioni utili:
- `ip` — IP dell'exit node (non il mio)
- `org` — spesso contiene "Tor Exit" nel nome
- `country` — il paese dell'exit node (cambia ad ogni circuito/NEWNYM)

### 5. Conferma che l'IP è un exit Tor

```bash
> proxychains curl -s https://check.torproject.org/api/ip
{"IsTor":true,"IP":"185.220.101.143"}
```

`IsTor: true` → conferma che il traffico esce da un exit node Tor noto.

---

## Test DNS Leak

### Cos'è un DNS leak

Un DNS leak avviene quando le query DNS escono al di fuori della rete Tor, rivelando
al tuo ISP quali siti stai visitando, anche se il traffico HTTP/HTTPS passa da Tor.

```
Senza DNS leak:
  Tu → Tor → Exit Node (risolve DNS) → Sito

Con DNS leak:
  Tu → ISP DNS (risolve il nome in chiaro!) → [poi] → Tor → Exit Node → Sito
  L'ISP vede che stai cercando "example.com"
```

### Come testare i DNS leak

#### Test 1: dnsleaktest.com

```bash
> proxychains curl -s https://dnsleaktest.com/
# Visualizzare la pagina per verificare quale DNS server viene usato
```

#### Test 2: ipleak.net (API JSON)

```bash
> proxychains curl -s https://ipleak.net/json/
{
  "ip": "185.220.101.143",
  "country_code": "NL",
  ...
}
```

Se l'IP e il country corrispondono a un exit Tor (non al tuo ISP), non c'è leak IP.
Per verificare il DNS specificamente, il sito esegue richieste DNS multiple e mostra
quale resolver le gestisce.

#### Test 3: Test manuale con dig

```bash
# DNS senza Tor (mostra il tuo resolver ISP)
> dig +short whoami.akamai.net @ns1-1.akamaitech.net
xxx.xxx.xxx.xxx    # IP del tuo resolver DNS (il tuo ISP)

# DNS via torsocks (dovrebbe mostrare il resolver dell'exit)
> torsocks dig +short whoami.akamai.net @ns1-1.akamaitech.net
# Nota: dig usa UDP di default, torsocks blocca UDP
# Usare: torsocks dig +tcp whoami.akamai.net @ns1-1.akamaitech.net
```

#### Test 4: Script di verifica

```bash
#!/bin/bash
echo "=== Test DNS Leak ==="

# IP senza Tor
REAL_IP=$(curl -s https://api.ipify.org)
echo "IP reale: $REAL_IP"

# IP con Tor
TOR_IP=$(proxychains curl -s https://api.ipify.org 2>/dev/null)
echo "IP Tor: $TOR_IP"

# Confronto
if [ "$REAL_IP" != "$TOR_IP" ]; then
    echo "✓ IP diversi — Tor funziona"
else
    echo "✗ ATTENZIONE — stesso IP! Tor potrebbe non funzionare"
fi

# Verifica Tor
IS_TOR=$(proxychains curl -s https://check.torproject.org/api/ip 2>/dev/null | grep -o '"IsTor":true')
if [ -n "$IS_TOR" ]; then
    echo "✓ Confermato: traffico esce da exit Tor"
else
    echo "✗ ATTENZIONE — traffico NON esce da Tor"
fi
```

---

## Verifica delle porte in ascolto

Per confermare che il daemon Tor è attivo e le porte sono configurate:

```bash
> sudo ss -tlnp | grep -E "9050|9051"
LISTEN  0  4096  127.0.0.1:9050  0.0.0.0:*  users:(("tor",pid=1234,fd=6))
LISTEN  0  4096  127.0.0.1:9051  0.0.0.0:*  users:(("tor",pid=1234,fd=7))

> sudo ss -ulnp | grep 5353
UNCONN  0  0  127.0.0.1:5353  0.0.0.0:*  users:(("tor",pid=1234,fd=8))
```

Porte attese:
- `9050 TCP` — SocksPort (proxy SOCKS5)
- `9051 TCP` — ControlPort
- `5353 UDP` — DNSPort

Se una porta manca, verificare il torrc e riavviare Tor.

---

## Tipi di leak e come prevenirli

### 1. DNS Leak

**Causa**: l'applicazione risolve gli hostname localmente (via ISP DNS) prima di
inviarli al proxy SOCKS.

**Prevenzione**:
- `proxy_dns` in proxychains.conf
- `--socks5-hostname` con curl (non `--socks5`)
- `DNSPort 5353` nel torrc + `AutomapHostsOnResolve 1`
- torsocks (intercetta DNS automaticamente)

### 2. IPv6 Leak

**Causa**: il sistema ha IPv6 attivo e alcune connessioni escono via IPv6,
bypassando Tor (che opera su IPv4).

**Prevenzione**:
- `ClientUseIPv6 0` nel torrc
- Disabilitare IPv6 a livello di sistema:
  ```bash
  sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
  sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
  ```

### 3. WebRTC Leak

**Causa**: WebRTC nel browser può rivelare l'IP locale e l'IP pubblico reale,
bypassando il proxy.

**Prevenzione**:
- In Firefox: `media.peerconnection.enabled = false` in `about:config`
- Tor Browser lo disabilita di default
- Con il mio profilo Firefox `tor-proxy`: devo disabilitarlo manualmente

### 4. Traffico non-proxy

**Causa**: applicazioni che non rispettano il proxy SOCKS (es. NTP, aggiornamenti
di sistema, servizi di background).

**Prevenzione**:
- Usare proxychains/torsocks per ogni applicazione specifica
- Per protezione system-wide: transparent proxy con iptables (vedi sezione avanzata)
- Usare Whonix o Tails per isolamento totale

### 5. Leak tramite protocolli non-TCP

**Causa**: Tor supporta solo TCP. Traffico UDP (DNS nativo, QUIC, WebRTC, NTP, STUN)
non passa da Tor.

**Prevenzione**:
- torsocks blocca UDP attivamente
- `DNSPort` nel torrc ridireziona DNS
- Disabilitare QUIC nel browser (`network.http.http3.enabled = false` in Firefox)

---

## Nella mia esperienza

### Test quotidiano

Il mio flusso di verifica tipico:

```bash
# 1. Verifico che Tor sia attivo
systemctl is-active tor@default.service

# 2. Verifico l'IP via Tor
proxychains curl -s https://api.ipify.org

# 3. Verifico che sia un exit Tor
proxychains curl -s https://check.torproject.org/api/ip

# 4. Se devo cambiare IP
~/scripts/newnym
proxychains curl -s https://api.ipify.org    # verifico che sia cambiato
```

### Risultati tipici

```
IP reale: xxx.xxx.xxx.xxx (Parma, IT, Comeser S.r.l.)
IP Tor:   185.220.101.143 (Amsterdam, NL, Stichting Tor Exit)
IsTor:    true
```

L'IP via Tor è sempre diverso dal mio IP reale, in un paese diverso, con un
operatore diverso. Questo conferma che il traffico passa correttamente attraverso
la rete Tor.

---

## Vedi anche

- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) — Analisi approfondita dei DNS leak
- [ProxyChains — Guida Completa](proxychains-guida-completa.md) — Configurazione proxy_dns
- [Tor e DNS — Risoluzione](tor-e-dns-risoluzione.md) — DNSPort e risoluzione via Tor
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) — WebRTC leak e fingerprint
- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) — Leak come errore OPSEC

---

## Cheat Sheet — Verifica rapida

| Test | Comando |
|------|---------|
| IP via Tor | `curl --socks5-hostname 127.0.0.1:9050 -s https://api.ipify.org` |
| IsTor check | `curl --socks5-hostname 127.0.0.1:9050 -s https://check.torproject.org/api/ip` |
| DNS leak (tcpdump) | `sudo tcpdump -i eth0 port 53 -n` |
| IP con proxychains | `proxychains curl -s https://api.ipify.org` |
| WebRTC check | Visitare `https://browserleaks.com/webrtc` via Tor |
| IPv6 check | `curl --socks5-hostname 127.0.0.1:9050 -s https://api6.ipify.org` (deve fallire) |
| Bootstrap | `sudo journalctl -u tor@default.service \| grep "Bootstrapped 100%"` |
| Porte Tor | `ss -tlnp \| grep -E '905[01]\|5353'` |
| tor-resolve | `tor-resolve example.com` |
| DNS via Tor | `proxychains dig example.com` |
