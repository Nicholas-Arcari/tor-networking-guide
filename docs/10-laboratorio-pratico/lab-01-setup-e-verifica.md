> **Lingua / Language**: Italiano | [English](../en/10-laboratorio-pratico/lab-01-setup-e-verifica.md)

# Lab 01 - Setup Completo e Verifica di Tor

Esercizio pratico per installare, configurare e verificare un setup Tor completo
su Kali Linux (Debian-based). Ogni passo include il comando, l'output atteso,
e cosa verificare.

**Tempo stimato**: 30-45 minuti
**Prerequisiti**: Kali Linux, accesso root, connessione Internet
**Difficoltà**: Base

---

## Indice

- [Obiettivi](#obiettivi)
- [Fase 1: Installazione pacchetti](#fase-1-installazione-pacchetti)
- [Fase 2: Configurazione torrc](#fase-2-configurazione-torrc)
- [Fase 3: Avvio e bootstrap](#fase-3-avvio-e-bootstrap)
- [Fase 4: Verifica connessione](#fase-4-verifica-connessione)
- [Fase 5: Test ControlPort](#fase-5-test-controlport)
- [Fase 6: Verifica DNS](#fase-6-verifica-dns)
- [Fase 7: Profilo Firefox](#fase-7-profilo-firefox)
- [Checklist finale](#checklist-finale)

---

## Obiettivi

Al termine di questo lab, avrai:
1. Tor installato e funzionante come servizio systemd
2. SocksPort, ControlPort e DNSPort configurati
3. proxychains4 configurato con proxy_dns
4. Un profilo Firefox dedicato per la navigazione via Tor
5. Tutti i test di verifica superati

---

## Fase 1: Installazione pacchetti

```bash
# Installare Tor e gli strumenti necessari
sudo apt update
sudo apt install -y tor proxychains4 torsocks nyx curl netcat-openbsd xxd

# Verificare l'installazione
tor --version
# Output atteso: Tor version 0.4.x.x
proxychains4 -h 2>&1 | head -1
# Output atteso: ProxyChains-4.x
```

**Verifica**: tutti i pacchetti installati senza errori.

---

## Fase 2: Configurazione torrc

```bash
# Backup del torrc originale
sudo cp /etc/tor/torrc /etc/tor/torrc.backup

# Aggiungere le configurazioni necessarie
sudo tee -a /etc/tor/torrc << 'EOF'

# === Lab 01 Config ===
SocksPort 9050
DNSPort 5353
ControlPort 9051
CookieAuthentication 1
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
ClientUseIPv6 0
Log notice file /var/log/tor/tor.log
EOF

# Aggiungere l'utente al gruppo debian-tor
sudo usermod -aG debian-tor $USER
# NOTA: il gruppo diventa attivo al prossimo login o con: newgrp debian-tor
```

**Verifica**: `grep -c "^[^#]" /etc/tor/torrc` deve mostrare le direttive attive.

---

## Fase 3: Avvio e bootstrap

```bash
# Riavviare Tor con la nuova configurazione
sudo systemctl restart tor@default.service

# Verificare lo stato
sudo systemctl status tor@default.service
# Output atteso: active (running)

# Verificare il bootstrap
sudo journalctl -u tor@default.service --no-pager | grep "Bootstrapped"
# Output atteso: Bootstrapped 100% (done): Done
```

**Verifica**: il bootstrap raggiunge il 100%. Se si blocca, controllare:
- Connessione Internet attiva
- Nessun firewall che blocca le connessioni in uscita
- Log: `sudo tail -20 /var/log/tor/tor.log`

---

## Fase 4: Verifica connessione

```bash
# Test 1: IP via Tor (SOCKS5 diretto)
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://api.ipify.org
# Output atteso: un IP diverso dal tuo IP reale

# Test 2: Verifica IsTor
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://check.torproject.org/api/ip
# Output atteso: {"IsTor":true,"IP":"xxx.xxx.xxx.xxx"}

# Test 3: proxychains
proxychains curl -s --max-time 20 https://api.ipify.org
# Output atteso: un IP di exit Tor (può essere diverso dal test 1)

# Test 4: Confronto IP
echo "IP reale: $(curl -s https://api.ipify.org)"
echo "IP Tor:   $(curl --socks5-hostname 127.0.0.1:9050 -s https://api.ipify.org)"
# I due IP DEVONO essere diversi
```

**Verifica**: tutti e 4 i test mostrano IP Tor diversi dal tuo IP reale.

---

## Fase 5: Test ControlPort

```bash
# Verificare che il cookie sia leggibile
ls -la /run/tor/control.authcookie
# Output: il file deve esistere e il tuo utente deve poterlo leggere

# Autenticazione e query
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
printf "AUTHENTICATE %s\r\nGETINFO version\r\nQUIT\r\n" "$COOKIE" | \
    nc -w 5 127.0.0.1 9051
# Output atteso:
# 250 OK
# 250-version=0.4.x.x
# 250 OK
# 250 closing connection

# Test NEWNYM
printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | \
    nc -w 5 127.0.0.1 9051
# Output atteso: due righe "250 OK"
```

**Verifica**: autenticazione e NEWNYM funzionano.

---

## Fase 6: Verifica DNS

```bash
# Test tor-resolve
tor-resolve example.com
# Output atteso: un IP (es. 93.184.216.34)

# Test DNS leak: cattura DNS mentre usi Tor
sudo tcpdump -i eth0 port 53 -c 5 -n &
TCPDUMP_PID=$!
sleep 1
curl --socks5-hostname 127.0.0.1:9050 -s https://example.com > /dev/null
sleep 3
sudo kill $TCPDUMP_PID 2>/dev/null
# Output atteso: NESSUNA query DNS catturata (0 pacchetti)
# Se appaiono query → c'è un DNS leak → rivedere la configurazione
```

**Verifica**: nessuna query DNS catturata da tcpdump durante la connessione via Tor.

---

## Fase 7: Profilo Firefox

```bash
# Creare un profilo dedicato
firefox -no-remote -CreateProfile tor-proxy

# Avviare Firefox con il profilo via proxychains
proxychains firefox -no-remote -P tor-proxy &

# In Firefox, configurare about:config:
# media.peerconnection.enabled = false
# network.dns.disablePrefetch = true
# network.prefetch-next = false
# privacy.resistFingerprinting = true
# webgl.disabled = true
# network.http.http3.enabled = false
# network.proxy.socks_remote_dns = true
```

**Verifica**: visitare https://check.torproject.org - deve mostrare "Congratulations. This browser is configured to use Tor."

---

## Risoluzione problemi

### Bootstrap bloccato (non raggiunge il 100%)

```bash
# Controllare i log per capire dove si blocca
sudo journalctl -u tor@default.service --no-pager | tail -30

# Cause comuni:
# "Problem bootstrapping. Stuck at X%: Connecting to a relay"
# → Firewall o ISP che blocca le connessioni Tor (porta 443/9001)
# → Soluzione: usare un bridge obfs4

# "Clock skew detected"
# → L'orologio di sistema è sballato (Tor richiede ±30 minuti)
# → Soluzione:
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# "Could not bind to 127.0.0.1:9050: Address already in use"
# → Un'altra istanza Tor è già in esecuzione
# → Soluzione:
sudo systemctl stop tor@default.service
sudo killall tor 2>/dev/null
sudo systemctl start tor@default.service
```

### ControlPort non risponde

```bash
# Verificare che la porta sia in ascolto
ss -tlnp | grep 9051
# Se vuoto → ControlPort non configurato nel torrc

# Verificare permessi cookie
ls -la /run/tor/control.authcookie
# Se "Permission denied" → l'utente non è nel gruppo debian-tor
groups $USER | grep debian-tor || echo "MANCA: esegui sudo usermod -aG debian-tor $USER e ri-logga"
```

### proxychains mostra "connection refused"

```bash
# Verificare che Tor sia attivo e la porta SOCKS sia aperta
ss -tlnp | grep 9050
# Se vuoto → Tor non è in esecuzione o SocksPort non configurato

# Verificare la configurazione proxychains
grep -v "^#" /etc/proxychains4.conf | grep socks
# Deve mostrare: socks5 127.0.0.1 9050
```

---

## Checklist finale

- [ ] Tor installato e servizio attivo
- [ ] Bootstrap al 100%
- [ ] SocksPort 9050 funzionante
- [ ] ControlPort 9051 funzionante con cookie auth
- [ ] DNSPort 5353 configurato
- [ ] NEWNYM accettato
- [ ] proxychains funzionante con proxy_dns
- [ ] Nessun DNS leak rilevato con tcpdump
- [ ] Profilo Firefox tor-proxy creato e configurato
- [ ] check.torproject.org conferma navigazione via Tor

---

## Vedi anche

- [Installazione e Verifica](../02-installazione-e-configurazione/installazione-e-verifica.md) - Guida completa installazione
- [torrc - Guida Completa](../02-installazione-e-configurazione/torrc-guida-completa.md) - Tutte le direttive
- [Verifica IP, DNS e Leak](../04-strumenti-operativi/verifica-ip-dns-e-leak.md) - Test approfonditi
