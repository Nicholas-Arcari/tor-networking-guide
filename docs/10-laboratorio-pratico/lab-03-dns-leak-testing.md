> **Lingua / Language**: Italiano | [English](../en/10-laboratorio-pratico/lab-03-dns-leak-testing.md)

# Lab 03 - Rilevamento e Prevenzione DNS Leak

Esercizio pratico per comprendere, rilevare e prevenire i DNS leak quando si usa
Tor. Include cattura con tcpdump, test automatici, e hardening con iptables.

**Tempo stimato**: 25-35 minuti
**Prerequisiti**: Lab 01 completato, accesso root per tcpdump e iptables
**Difficoltà**: Intermedio

---

## Indice

- [Obiettivi](#obiettivi)
- [Fase 1: Capire il DNS leak](#fase-1-capire-il-dns-leak)
- [Fase 2: Provocare un DNS leak](#fase-2-provocare-un-dns-leak)
- [Fase 3: Verificare la protezione](#fase-3-verificare-la-protezione)
- [Fase 4: Hardening con iptables](#fase-4-hardening-con-iptables)
- [Fase 5: Script di test automatico](#fase-5-script-di-test-automatico)
- [Checklist finale](#checklist-finale)

---

## Obiettivi

Al termine di questo lab, saprai:
1. Catturare DNS leak con tcpdump
2. Distinguere tra `--socks5` (leak) e `--socks5-hostname` (sicuro)
3. Verificare che `proxy_dns` in proxychains funzioni
4. Implementare regole iptables anti-DNS-leak
5. Creare uno script di test automatizzato

---

## Fase 1: Capire il DNS leak

```bash
# Primo, vediamo qual è il nostro resolver DNS attuale
cat /etc/resolv.conf
# Output: nameserver 192.168.1.1 (o simile - il tuo router/ISP)

# Questo resolver è quello che riceve le query quando NON usiamo Tor
# Se una query DNS esce senza passare da Tor, va a questo resolver
# → L'ISP vede quale dominio stai cercando di raggiungere
```

---

## Fase 2: Provocare un DNS leak

```bash
# Apri DUE terminali

# TERMINALE 1: cattura DNS
sudo tcpdump -i eth0 port 53 -n -l

# TERMINALE 2: provoca un leak
# Usa --socks5 (SENZA hostname) → risolve DNS localmente → LEAK!
curl --socks5 127.0.0.1:9050 -s --max-time 15 https://example.com > /dev/null

# TERMINALE 1: dovresti vedere qualcosa come:
# 14:23:45.123 IP 192.168.1.100.43521 > 192.168.1.1.53: A? example.com
# → Questa è la query DNS in chiaro che rivela "example.com" al tuo ISP

# Ora prova il metodo CORRETTO:
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 15 https://example.com > /dev/null

# TERMINALE 1: nessuna query DNS visibile → nessun leak!
```

**Esercizio**: annota la differenza tra `--socks5` e `--socks5-hostname`.
Con `--socks5`, quante query DNS vedi? Verso quale IP vanno?

---

## Fase 3: Verificare la protezione

```bash
# Test 1: proxychains con proxy_dns (deve essere attivo)
grep "proxy_dns" /etc/proxychains4.conf
# Deve mostrare: proxy_dns (non commentato)

# TERMINALE 1: tcpdump attivo
sudo tcpdump -i eth0 port 53 -n -l

# TERMINALE 2: test con proxychains
proxychains curl -s --max-time 15 https://check.torproject.org > /dev/null

# TERMINALE 1: nessuna query DNS deve apparire

# Test 2: cosa succede SENZA proxy_dns?
# (NON fare su un sistema in produzione - solo per lab)
# Commenta temporaneamente proxy_dns in /etc/proxychains4.conf
# Ripeti il test → dovresti vedere query DNS in chiaro
# RICORDA di riattivare proxy_dns dopo il test!
```

---

## Fase 4: Hardening con iptables

```bash
# Implementa regole anti-DNS-leak

# 1. Permetti DNS solo dal processo Tor
sudo iptables -A OUTPUT -p udp --dport 53 -m owner --uid-owner debian-tor -j ACCEPT
sudo iptables -A OUTPUT -p tcp --dport 53 -m owner --uid-owner debian-tor -j ACCEPT

# 2. Permetti DNS verso DNSPort locale
sudo iptables -A OUTPUT -p udp -d 127.0.0.1 --dport 5353 -j ACCEPT

# 3. Blocca tutto il resto del DNS
sudo iptables -A OUTPUT -p udp --dport 53 -j LOG --log-prefix "DNS_LEAK: "
sudo iptables -A OUTPUT -p udp --dport 53 -j DROP
sudo iptables -A OUTPUT -p tcp --dport 53 -j DROP

# Verifica le regole
sudo iptables -L OUTPUT -n -v | grep -E "53|DNS"

# Test: prova a fare DNS diretto (deve fallire)
dig example.com @8.8.8.8
# → Timeout (bloccato dalle regole)

# Test: Tor funziona ancora
proxychains curl -s https://api.ipify.org
# → Mostra IP Tor (funziona perché Tor risolve internamente)

# Per rimuovere le regole (fine del lab):
sudo iptables -F OUTPUT
```

---

## Fase 5: Script di test automatico

Crea il file `test-dns-leak.sh`:

```bash
#!/bin/bash
# test-dns-leak.sh - Test automatico DNS leak

IFACE="${1:-eth0}"
PASS=0
FAIL=0

echo "=== DNS Leak Test ==="
echo "Interfaccia: $IFACE"
echo ""

run_test() {
    local desc="$1"
    local cmd="$2"
    local expect_leak="$3"

    echo -n "Test: $desc ... "

    # Cattura DNS in background
    PCAP="/tmp/dns-test-$$.pcap"
    sudo tcpdump -i "$IFACE" port 53 -w "$PCAP" -c 10 &>/dev/null &
    PID=$!
    sleep 1

    # Esegui comando
    eval "$cmd" > /dev/null 2>&1
    sleep 2

    # Ferma cattura
    sudo kill $PID 2>/dev/null; wait $PID 2>/dev/null
    QUERIES=$(sudo tcpdump -r "$PCAP" -n 2>/dev/null | grep -c "A?")
    rm -f "$PCAP"

    if [ "$expect_leak" = "leak" ] && [ "$QUERIES" -gt 0 ]; then
        echo "LEAK rilevato ($QUERIES query) - atteso"
        PASS=$((PASS+1))
    elif [ "$expect_leak" = "noleak" ] && [ "$QUERIES" -eq 0 ]; then
        echo "Nessun leak - OK"
        PASS=$((PASS+1))
    else
        echo "RISULTATO INATTESO ($QUERIES query)"
        FAIL=$((FAIL+1))
    fi
}

run_test "curl --socks5 (atteso: leak)" \
    "curl --socks5 127.0.0.1:9050 -s --max-time 10 https://example.com" "leak"

run_test "curl --socks5-hostname (atteso: no leak)" \
    "curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 https://example.com" "noleak"

run_test "proxychains curl (atteso: no leak)" \
    "proxychains curl -s --max-time 10 https://example.com" "noleak"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
```

```bash
chmod +x test-dns-leak.sh
sudo ./test-dns-leak.sh eth0
```

---

## Risoluzione problemi

### tcpdump non cattura nulla (0 pacchetti)

```bash
# Verificare l'interfaccia corretta
ip route get 8.8.8.8 | grep -oP 'dev \K\S+'
# Se non è "eth0", passare l'interfaccia corretta:
sudo tcpdump -i <interfaccia_corretta> port 53 -n -l

# Su VM/container l'interfaccia potrebbe essere "ens33", "wlan0", etc.
```

### tcpdump mostra query DNS anche con --socks5-hostname

```bash
# Possibili cause:
# 1. systemd-resolved intercetta le query prima di Tor
systemctl status systemd-resolved
# Se attivo, potrebbe risolvere in cache. Per il test:
sudo systemd-resolve --flush-caches

# 2. Il browser (non curl) fa prefetch DNS in background
# → Disabilitare network.dns.disablePrefetch in about:config

# 3. IPv6 DNS leak - il sistema usa DNS IPv6 non coperto dalle regole
# → Aggiungere regole ip6tables o disabilitare IPv6:
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
```

### Le regole iptables bloccano anche il traffico legittimo

```bash
# Se dopo aver applicato le regole anti-DNS-leak perdi la connessione:
# Probabilmente hai bloccato il DNS anche per Tor stesso

# Verifica le regole attuali
sudo iptables -L OUTPUT -n -v --line-numbers

# Rimuovi tutte le regole OUTPUT (ripristino rapido)
sudo iptables -F OUTPUT

# Assicurati che la regola ACCEPT per debian-tor sia PRIMA della regola DROP
# L'ordine delle regole è critico in iptables
```

---

## Checklist finale

- [ ] DNS leak provocato e catturato con tcpdump
- [ ] Differenza --socks5 vs --socks5-hostname compresa
- [ ] proxy_dns verificato in proxychains
- [ ] Regole iptables anti-DNS-leak implementate e testate
- [ ] Script di test automatico funzionante

---

## Vedi anche

- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Analisi completa dei DNS leak
- [Tor e DNS - Risoluzione](../04-strumenti-operativi/tor-e-dns-risoluzione.md) - DNSPort e configurazione
- [Hardening di Sistema](../05-sicurezza-operativa/hardening-sistema.md) - Regole firewall permanenti
