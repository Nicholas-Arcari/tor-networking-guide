> **Lingua / Language**: Italiano | [English](../en/06-configurazioni-avanzate/vpn-tor-routing-e-dns.md)

# VPN e Tor - Routing Selettivo, DNS e Kill Switch

Routing selettivo per applicazione, gestione DNS nelle configurazioni ibride,
kill switch VPN e Tor, confronto WireGuard vs OpenVPN, ExitNodes e
geolocalizzazione forzata, tabella comparativa.

> **Estratto da**: [VPN e Tor - Configurazioni Ibride](vpn-e-tor-ibrido.md)
> per le differenze architetturali e le configurazioni VPN→Tor e Tor→VPN.

---

## Routing selettivo per applicazione

### Il mio approccio

```
Browser (navigazione anonima) → proxychains → Tor → Internet
Terminale (test, curl)        → proxychains → Tor → Internet
Aggiornamenti sistema         → rete normale            → Internet
Streaming/video               → VPN (opzionale)         → Internet
App sensibili                 → rete normale             → Internet
Banking                       → rete normale (MAI Tor)   → Internet
Gaming                        → rete normale             → Internet
```

### Implementazione pratica

```bash
# ~/.zshrc o ~/.bashrc

# Alias per Tor
alias curltor='curl --socks5-hostname 127.0.0.1:9050'
alias pcurl='proxychains curl -s'
alias pfirefox='proxychains firefox -no-remote -P tor-proxy &>/dev/null & disown'

# Funzione per verificare lo stato
torcheck() {
    echo -n "IP Tor: "
    curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 https://api.ipify.org
    echo ""
    echo -n "IsTor: "
    curl --socks5-hostname 127.0.0.1:9050 -s --max-time 10 \
        https://check.torproject.org/api/ip | grep -o '"IsTor":[a-z]*'
}

# Git via Tor (solo per repository specifici)
alias gittor='git -c http.proxy=socks5h://127.0.0.1:9050 -c https.proxy=socks5h://127.0.0.1:9050'
```

### Vantaggi

- Flessibilità massima: ogni app usa il canale migliore
- Non sovraccarica Tor con traffico non necessario
- Non rompe applicazioni che necessitano UDP
- Performance ottimali per ogni tipo di traffico
- Controllo granulare su cosa è anonimo e cosa no

### Svantaggi

- Richiede disciplina (ricordarsi di usare proxychains)
- Possibili leak se dimentico di proxare un'applicazione
- Non automatico: errore umano è il rischio principale
- Non adatto a scenari ad alto rischio (meglio Whonix/Tails)

---

## Gestione DNS nelle configurazioni ibride

### DNS in VPN → Tor

```
Problema:
  La VPN configura i propri DNS (es. via DHCP push)
  Tor usa il suo DNSPort per risolvere
  Chi risolve prima?

Flusso corretto:
  App → proxychains → SOCKS5 hostname → Tor → Exit (risolve DNS)
  La VPN e i suoi DNS non sono coinvolti per il traffico Tor

Flusso problematico:
  App → DNS della VPN → risposta in chiaro alla VPN
  → poi → connessione via Tor
  La VPN ha visto il dominio! Privacy parzialmente compromessa

Soluzione:
  1. Usare sempre --socks5-hostname (non --socks5)
  2. Attivare proxy_dns in proxychains
  3. In Firefox: network.proxy.socks_remote_dns = true
  4. Non usare i DNS push della VPN per il traffico Tor
```

### DNS in TransPort

```
Flusso:
  App → query DNS locale → iptables REDIRECT → DNSPort Tor
  → Tor risolve via circuito → risposta all'app
  → App si connette → iptables REDIRECT → TransPort Tor
  → Connessione via Tor

Tutto il DNS è forzato via Tor. Nessun leak possibile
(a meno di bug nelle regole iptables).
```

### DNS in routing selettivo

```
Il mio setup:
  Con proxychains: DNS risolto via Tor (proxy_dns)
  Senza proxychains: DNS risolto dal router ISP (192.168.1.1)

Rischio: se dimentico proxychains, il DNS esce in chiaro
Mitigazione: iptables che blocca DNS diretto (porta 53) per il mio utente
```

---

## Kill switch e protezione dai leak

### Kill switch per VPN → Tor

Se la VPN si disconnette, Tor si connetterebbe direttamente → l'ISP vede Tor.

```bash
#!/bin/bash
# vpn-killswitch.sh - Blocca traffico se la VPN cade

VPN_IFACE="wg0"  # o tun0 per OpenVPN
VPN_SERVER="85.x.x.x"  # IP del server VPN

# Permetti solo traffico verso il server VPN (per mantenere la connessione)
sudo iptables -A OUTPUT -d $VPN_SERVER -j ACCEPT

# Permetti traffico sulla VPN
sudo iptables -A OUTPUT -o $VPN_IFACE -j ACCEPT

# Permetti localhost
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Permetti traffico locale
sudo iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# Blocca TUTTO il resto (kill switch)
sudo iptables -A OUTPUT -j DROP

# Se la VPN cade → tun0/wg0 scompare → traffico droppato → nessun leak
```

### Kill switch per Tor da solo

```bash
#!/bin/bash
# tor-killswitch.sh - Blocca traffico non-Tor

TOR_USER="debian-tor"

# Permetti traffico dal processo Tor
sudo iptables -A OUTPUT -m owner --uid-owner $TOR_USER -j ACCEPT

# Permetti localhost
sudo iptables -A OUTPUT -o lo -j ACCEPT

# Permetti LAN
sudo iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# Blocca tutto il resto
sudo iptables -A OUTPUT -j REJECT --reject-with icmp-port-unreachable

# Se Tor si blocca → applicazioni non possono uscire → nessun leak
# Ma anche: niente aggiornamenti, NTP, etc.
```

---

## WireGuard vs OpenVPN con Tor

### WireGuard

```
Vantaggi con Tor:
  + Connessione veloce (handshake in 1 RTT)
  + Overhead basso (meno latenza aggiunta a Tor)
  + Configurazione semplice
  + Rimane connesso anche dopo sleep/resume

Svantaggi:
  - UDP-only (può essere bloccato da firewall)
  - Assegna IP fisso al peer (fingerprint se il provider logga)
  - Meno offuscamento (WireGuard è facilmente identificabile da DPI)
```

### OpenVPN

```
Vantaggi con Tor:
  + TCP mode disponibile (bypassa firewall che bloccano UDP)
  + Supporta offuscamento (obfsproxy, stunnel)
  + Più flessibile nella configurazione

Svantaggi:
  - Handshake più lento (multi-RTT)
  - Overhead maggiore
  - Riconnessione più lenta dopo disconnessione
```

### Raccomandazione

```
Per uso generale (VPN → Tor): WireGuard (più veloce, meno overhead)
Per reti restrittive: OpenVPN TCP (bypassa firewall)
Per massimo offuscamento: OpenVPN + obfsproxy (sembra HTTPS)
```

---

## ExitNodes e geolocalizzazione forzata

### Il problema

Ho provato a forzare l'uscita da un paese specifico:
```ini
ExitNodes {it}
StrictNodes 1
```

Risultati:
- Pochissimi exit italiani disponibili (~10-20 su ~2000 totali)
- Circuiti saturi e lenti (tutti gli utenti con {it} condividono pochi exit)
- IP che cambiava comunque ad ogni rinnovo del circuito
- Fingerprinting facile ("questo utente esce SEMPRE dall'Italia")

### Perché non funziona

Tor è progettato per la **randomizzazione**. Forzare un paese:
- Riduce il pool di exit (meno privacy, meno bandwidth)
- Rende il traffico più riconoscibile
- Non garantisce lo stesso IP nel tempo (circuiti vengono rinnovati)
- Crea un set di anonimato ridotto (solo utenti con ExitNodes {it})

### Alternative

```
Per geolocalizzazione:
  → VPN con server nel paese desiderato (IP fisso, veloce)

Per anonimato + paese specifico (raro):
  → Tor → VPN nel paese desiderato (ma vedi problemi sopra)

Per test da paesi specifici:
  → ExitNodes {cc} temporaneamente, poi rimuovere
  → Non usare per navigazione quotidiana
```

---

## Tabella comparativa

| Configurazione | Privacy | Anonimato | Velocità | Affidabilità | Complessità | DNS sicuro |
|---------------|---------|-----------|----------|-------------|-------------|-----------|
| Solo Tor | Alta | Molto alta | Bassa | Media | Bassa | Con config |
| Solo VPN | Media | Bassa | Alta | Alta | Bassa | Dipende |
| VPN → Tor | Alta | Alta | Molto bassa | Media | Media | Con config |
| Tor → VPN | Bassa | Bassa | Bassa | Bassa | Alta | Problematico |
| TransPort+iptables | Alta | Alta | Bassa | Bassa | Alta | Forzato |
| Routing selettivo | Alta | Alta (per app proxate) | Variabile | Alta | Media | Con config |

---

## Nella mia esperienza

**La mia scelta**: routing selettivo. È il compromesso migliore tra sicurezza,
usabilità e praticità quotidiana.

```
Il mio workflow:
1. Tor daemon sempre attivo (systemd)
2. Bridge obfs4 configurato (nasconde Tor all'ISP Comeser)
3. proxychains per navigazione e test
4. Rete normale per tutto il resto
5. Nessuna VPN (non ne ho bisogno per il mio threat model)
```

Se dovessi aggiungere una VPN, la userei per:
- Streaming geolocalizzato (Netflix, etc.)
- WiFi pubblici (protezione generica, non anonimato)
- Fallback se Tor è troppo lento per un'operazione specifica

NON la userei per:
- Aggiungere "sicurezza" a Tor (non aggiunge nulla di significativo)
- Sostituire bridge obfs4 (i bridge sono migliori per nascondere Tor)

---

## Vedi anche

- [Transparent Proxy](transparent-proxy.md) - Setup completo iptables/nftables TransPort
- [Multi-Istanza e Stream Isolation](multi-istanza-e-stream-isolation.md) - Isolamento circuiti per app
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Prevenzione DNS leak in ogni configurazione
- [Bridges e Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Alternativa a VPN per nascondere Tor
- [Isolamento e Compartimentazione](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) - Whonix, Tails, Qubes
- [Limitazioni del Protocollo](../07-limitazioni-e-attacchi/limitazioni-protocollo.md) - Perché Tor non supporta UDP
