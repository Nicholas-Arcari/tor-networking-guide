# DNS Leak - Prevenzione e Hardening

Mitigazioni multilivello per i DNS leak: configurazione Tor, proxychains, applicativa,
sistema operativo, firewall iptables/nftables, systemd-resolved, DoH/DoT, e verifica forense.

> **Estratto da**: [DNS Leak - Come Avvengono e Come Prevenirli](dns-leak.md)
> per gli scenari di leak e la verifica pratica.

---

### Livello 1: Configurazione Tor (torrc)

```ini
# Tor come DNS resolver locale
DNSPort 5353                    # Tor risponde alle query DNS sulla porta 5353/UDP
AutomapHostsOnResolve 1         # Mapping automatico degli hostname a IP fittizi
VirtualAddrNetworkIPv4 10.192.0.0/10  # Range per gli IP fittizi del mapping
```

Come funziona:
```
1. Un'applicazione chiede di risolvere "example.com"
2. La query arriva a 127.0.0.1:5353 (Tor DNSPort)
3. Tor crea un circuito e risolve il DNS sull'exit node
4. Con AutomapHosts: Tor mappa "example.com" → 10.192.x.x
5. L'applicazione si connette a 10.192.x.x
6. Tor intercetta la connessione (TransPort) e la invia all'IP reale
```

### Livello 2: Configurazione ProxyChains

```ini
# /etc/proxychains4.conf
proxy_dns                       # Intercetta le chiamate DNS via LD_PRELOAD
remote_dns_subnet 224           # Subnet per IP fittizi del mapping DNS

# Come funziona proxy_dns:
# 1. proxychains intercetta getaddrinfo() via LD_PRELOAD
# 2. Invece di risolvere, assegna un IP nel range 224.x.x.x
# 3. Quando l'app si connette a 224.x.x.x:
#    proxychains invia l'hostname originale al proxy SOCKS5
# 4. Tor risolve il DNS sull'exit node
```

### Livello 3: Configurazione applicativa

```bash
# curl: SEMPRE --socks5-hostname, MAI --socks5
curl --socks5-hostname 127.0.0.1:9050 https://example.com
# Alternativa:
curl -x socks5h://127.0.0.1:9050 https://example.com

# wget: via proxychains (wget non supporta SOCKS nativamente)
proxychains wget https://example.com

# Firefox: "Proxy DNS when using SOCKS v5" attivo nelle impostazioni proxy
# about:config → network.proxy.socks_remote_dns = true

# git: usare socks5h (h = hostname resolution via proxy)
git config --global http.proxy socks5h://127.0.0.1:9050
git config --global https.proxy socks5h://127.0.0.1:9050

# pip: via proxychains
proxychains pip install package_name

# SSH: configurare in ~/.ssh/config
# Host *.onion
#     ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

### Livello 4: Configurazione di sistema

```bash
# 1. Disabilitare IPv6 (previene leak AAAA)
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
# Rendere persistente:
echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee -a /etc/sysctl.d/99-tor-hardening.conf
echo "net.ipv6.conf.default.disable_ipv6=1" | sudo tee -a /etc/sysctl.d/99-tor-hardening.conf

# 2. Configurare /etc/resolv.conf per usare solo Tor DNS
# ATTENZIONE: se Tor non è attivo, il DNS non funziona!
# Utile solo per setup system-wide
sudo bash -c 'echo "nameserver 127.0.0.1" > /etc/resolv.conf'
# E proteggere il file dalla sovrascrittura:
sudo chattr +i /etc/resolv.conf

# 3. Disabilitare systemd-resolved se non necessario
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

### Livello 5: Firewall (protezione massima)

Per impedire fisicamente che query DNS escano senza passare da Tor:

```bash
# Blocca tutto il DNS in uscita tranne quello di Tor
sudo iptables -A OUTPUT -p udp --dport 53 -m owner --uid-owner debian-tor -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -m owner --uid-owner debian-tor -j ACCEPT
sudo iptables -A OUTPUT -p udp --dport 53 -j DROP
sudo iptables -A OUTPUT -p tcp --dport 53 -j DROP

# Permetti anche DNS verso il DNSPort locale
sudo iptables -A OUTPUT -p udp -d 127.0.0.1 --dport 5353 -j ACCEPT
```

Questo blocca tutte le query DNS (porta 53) che non provengono dal processo Tor
(utente `debian-tor`). Qualsiasi applicazione che tenta di fare DNS diretto viene
bloccata silenziosamente.

---

## Hardening avanzato con iptables/nftables

### Regole iptables complete anti-DNS-leak

```bash
#!/bin/bash
# dns-leak-firewall.sh - Regole anti-DNS-leak complete

# Variabili
TOR_USER="debian-tor"
DNS_PORT=5353
TRANS_PORT=9040

# Flush regole esistenti per la catena DNS
sudo iptables -D OUTPUT -p udp --dport 53 -j DNS_LEAK_PROTECT 2>/dev/null
sudo iptables -F DNS_LEAK_PROTECT 2>/dev/null
sudo iptables -X DNS_LEAK_PROTECT 2>/dev/null

# Crea catena dedicata
sudo iptables -N DNS_LEAK_PROTECT

# Permetti DNS dal processo Tor
sudo iptables -A DNS_LEAK_PROTECT -m owner --uid-owner $TOR_USER -j ACCEPT

# Permetti DNS verso localhost (DNSPort)
sudo iptables -A DNS_LEAK_PROTECT -d 127.0.0.1 -j ACCEPT

# Log e blocca tutto il resto
sudo iptables -A DNS_LEAK_PROTECT -j LOG --log-prefix "DNS_LEAK_BLOCKED: " --log-level warning
sudo iptables -A DNS_LEAK_PROTECT -j DROP

# Applica la catena
sudo iptables -A OUTPUT -p udp --dport 53 -j DNS_LEAK_PROTECT
sudo iptables -A OUTPUT -p tcp --dport 53 -j DNS_LEAK_PROTECT

# Blocca anche DoH (DNS-over-HTTPS) verso resolver noti
# Questo previene che Chrome/app usino DoH per bypassare
for doh_ip in 8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 9.9.9.9; do
    sudo iptables -A OUTPUT -d "$doh_ip" -p tcp --dport 443 \
        -m owner ! --uid-owner $TOR_USER -j DROP
done

echo "Regole anti-DNS-leak attivate"
echo "Verifica con: sudo iptables -L DNS_LEAK_PROTECT -v -n"
```

### Equivalente nftables

```
table inet dns_leak_protect {
    chain output {
        type filter hook output priority 0; policy accept;
        
        # Permetti DNS dal processo Tor
        meta skuid debian-tor udp dport 53 accept
        meta skuid debian-tor tcp dport 53 accept
        
        # Permetti DNS verso localhost
        ip daddr 127.0.0.1 udp dport 5353 accept
        
        # Log e blocca DNS diretto
        udp dport 53 log prefix "DNS_LEAK: " drop
        tcp dport 53 log prefix "DNS_LEAK: " drop
        
        # Blocca DoH verso resolver noti
        ip daddr { 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1 } tcp dport 443 \
            meta skuid != debian-tor drop
    }
}
```

### Verifica delle regole

```bash
# Verifica che le regole siano attive
sudo iptables -L DNS_LEAK_PROTECT -v -n

# Verifica i log dei blocchi
sudo journalctl -k | grep DNS_LEAK_BLOCKED

# Test: prova a fare DNS diretto (dovrebbe essere bloccato)
dig example.com @8.8.8.8
# → timeout (bloccato dal firewall)

# Test: prova via Tor (dovrebbe funzionare)
proxychains curl -s https://check.torproject.org/api/ip
# → {"IsTor":true,...} (DNS risolto via Tor)
```

---

## systemd-resolved e interazione con Tor

### Il problema

`systemd-resolved` è il resolver DNS predefinito su molte distribuzioni Linux.
Crea complicazioni con Tor:

```bash
# systemd-resolved ascolta su 127.0.0.53:53
# /etc/resolv.conf punta a 127.0.0.53
# Le applicazioni risolvono DNS tramite systemd-resolved
# systemd-resolved inoltra le query ai resolver upstream (ISP)

# Anche con proxychains, ci sono casi dove systemd-resolved
# risolve PRIMA che proxychains intercetti:
# - NSS (Name Service Switch) può usare systemd-resolved direttamente
# - Alcune librerie non usano getaddrinfo() standard
```

### Soluzione 1: Disabilitare systemd-resolved

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm /etc/resolv.conf  # Rimuovi il symlink
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
# Ora il DNS usa solo il resolver locale (Tor DNSPort se configurato)
```

### Soluzione 2: Configurare systemd-resolved per usare Tor

```ini
# /etc/systemd/resolved.conf
[Resolve]
DNS=127.0.0.1#5353     # Usa il DNSPort di Tor
FallbackDNS=            # NESSUN fallback (se Tor è giù, DNS non funziona)
DNSOverTLS=no           # Non usare DoT (Tor gestisce la crittografia)
DNSSEC=no               # Tor non supporta DNSSEC end-to-end
Cache=no                # Non cachare (le risposte cambiano con gli exit)
```

```bash
sudo systemctl restart systemd-resolved
# Verifica:
resolvectl status
# Dovrebbe mostrare: DNS Servers: 127.0.0.1#5353
```

### Soluzione 3: Configurazione ibrida (il mio approccio)

```bash
# Su Kali Linux, systemd-resolved non è attivo per default
# Verifico:
systemctl is-active systemd-resolved
# inactive → nessun problema

# Il mio /etc/resolv.conf usa il DNS del router ISP:
cat /etc/resolv.conf
# nameserver 192.168.1.1

# Questo significa:
# - Senza proxychains: DNS risolto dal router ISP (normale)
# - Con proxychains + proxy_dns: DNS risolto via Tor (protetto)
# - Il leak avviene SOLO se dimentico proxychains o uso --socks5 senza -hostname
```

---

## DNS over HTTPS/TLS e implicazioni per Tor

### DoH (DNS-over-HTTPS)

DoH cifra le query DNS dentro HTTPS (porta 443). Sembra buono per la privacy,
ma crea problemi con Tor:

```
Problema 1: DoH bypassa proxychains
  Firefox con DoH attivo → query DNS HTTPS verso Cloudflare (1.1.1.1:443)
  proxychains non intercetta questa connessione HTTPS
  → Le query DNS escono in chiaro (cifrate con TLS, ma non via Tor)
  → Il provider DoH (Cloudflare/Google) vede tutti i tuoi domini

Problema 2: DoH non passa da Tor
  La connessione DoH è una connessione HTTPS separata
  Se non è proxata, esce direttamente
  Anche se è proxata, aggiunge latenza (DoH + Tor = doppio overhead)

Soluzione: disabilitare DoH quando si usa Tor
  Firefox: about:config → network.trr.mode = 5 (disabilitato)
  Chrome: chrome://settings → Sicurezza → "Usa DNS sicuro" → OFF
```

### DoT (DNS-over-TLS)

DoT cifra le query DNS con TLS sulla porta 853. Stesso problema:

```
# Se systemd-resolved usa DoT:
[Resolve]
DNSOverTLS=yes
DNS=1.1.1.1#cloudflare-dns.com

# Le query vanno a Cloudflare via TLS sulla porta 853
# → Non passano da Tor
# → Cloudflare vede tutti i tuoi domini (anche se cifrati in transito)
```

### Raccomandazione

Quando si usa Tor, disabilitare DoH e DoT. Il DNS deve passare
attraverso Tor, che gestisce la propria crittografia. Aggiungere
DoH/DoT a Tor non aggiunge sicurezza e può causare leak.

---

## Rilevamento forense dei DNS leak

### Come un analista forense rileva DNS leak

Un investigatore che ha accesso ai log dell'ISP o a una cattura di rete
può identificare i DNS leak:

```
Evidenza 1: Query DNS in chiaro
  - pcap con query DNS UDP:53 verso il resolver ISP
  - Contengono i domini visitati, con timestamp

Evidenza 2: Correlazione temporale
  - t=0.00: query DNS per "sensitive-site.com" (in chiaro)
  - t=0.05: connessione TLS verso Guard Tor
  - Correlazione: l'utente ha visitato sensitive-site.com via Tor

Evidenza 3: Pattern di leak
  - Le prime query di una sessione sono spesso in chiaro
    (prima che proxychains si inizializzi)
  - Le query per domini interni (.local, .internal) leakano spesso
  - I browser prefetchano DNS prima che l'utente clicchi
```

### Self-audit per DNS leak

```bash
#!/bin/bash
# audit-dns-leak.sh - Verifica se ci sono stati DNS leak
# Analizza un file pcap catturato durante una sessione Tor

PCAP_FILE="${1:-/tmp/session-capture.pcap}"

echo "=== Audit DNS Leak ==="
echo "File: $PCAP_FILE"

# Conta query DNS in uscita (non da Tor)
TOTAL_DNS=$(tcpdump -r "$PCAP_FILE" -n 'udp port 53 and not src host 127.0.0.1' 2>/dev/null | wc -l)
echo "Query DNS in uscita (non-localhost): $TOTAL_DNS"

# Elenca i domini richiesti
echo ""
echo "Domini richiesti in chiaro:"
tcpdump -r "$PCAP_FILE" -n 'udp port 53' 2>/dev/null | \
    grep -oP '(?<=A\? )[^ ]+' | sort -u

# Verifica se ci sono query verso resolver noti (DoH)
echo ""
echo "Connessioni verso resolver DNS noti (possibile DoH):"
for ip in 8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 9.9.9.9; do
    COUNT=$(tcpdump -r "$PCAP_FILE" -n "host $ip" 2>/dev/null | wc -l)
    [ "$COUNT" -gt 0 ] && echo "  $ip: $COUNT pacchetti"
done
```

---

## Nella mia esperienza

La mia configurazione previene i DNS leak a tre livelli:
1. **proxy_dns in proxychains** (intercetta DNS a livello applicativo)
2. **DNSPort 5353 nel torrc** (Tor come resolver DNS locale)
3. **IPv6 disabilitato** (previene leak via AAAA query)

Non ho implementato il firewall iptables perché uso Tor solo per applicazioni
specifiche (non system-wide). Ma per un setup dove voglio la massima protezione,
il firewall sarebbe il passo successivo.

Il test rapido che uso regolarmente:
```bash
# Test DNS leak rapido
sudo tcpdump -i eth0 port 53 -c 5 -n &
proxychains curl -s https://check.torproject.org/api/ip | grep IsTor
# Se tcpdump non cattura nulla e IsTor è true → nessun leak
```

Il leak più insidioso che ho incontrato: **Firefox con DNS prefetch attivo**.
Anche con proxychains, Firefox pre-risolveva i DNS dei link nella pagina.
La soluzione è stata `network.dns.disablePrefetch = true` nel profilo tor-proxy.

---

## Vedi anche

- [Tor e DNS - Risoluzione](../04-strumenti-operativi/tor-e-dns-risoluzione.md) - DNSPort, AutomapHosts, configurazione DNS completa
- [Verifica IP, DNS e Leak](../04-strumenti-operativi/verifica-ip-dns-e-leak.md) - Test IP, DNS leak, IPv6 leak, WebRTC leak
- [Hardening di Sistema](hardening-sistema.md) - sysctl, nftables, regole firewall
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - DNS leak come errore OPSEC
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - TransPort per forzare tutto il traffico via Tor
- [ProxyChains - Guida Completa](../04-strumenti-operativi/proxychains-guida-completa.md) - proxy_dns e configurazione
