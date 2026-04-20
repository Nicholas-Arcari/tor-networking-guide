> **Lingua / Language**: Italiano | [English](../en/03-nodi-e-rete/exit-nodes-pratica.md)

# Exit Nodes nella Pratica - Blocchi, DNS e Identificazione

Blocchi e CAPTCHA dai siti web, risoluzione DNS dall'exit node,
principio di selettività nelle exit policy, e identificazione degli exit nel consenso.

Estratto da [Exit Nodes](exit-nodes.md).

---

## Indice

- [Blocchi e CAPTCHA - Come i siti reagiscono agli Exit Node](#blocchi-e-captcha--come-i-siti-reagiscono-agli-exit-node)
- [Exit Node e DNS - Chi risolve cosa](#exit-node-e-dns--chi-risolve-cosa)
- [Exit Policy e il principio di selettività](#exit-policy-e-il-principio-di-selettività)
- [Identificare gli Exit Node nel consenso](#identificare-gli-exit-node-nel-consenso)
- [Riepilogo dei rischi e mitigazioni](#riepilogo-dei-rischi-e-mitigazioni)

---

## Blocchi e CAPTCHA - Come i siti reagiscono agli Exit Node

### Perché i siti bloccano Tor

Gli IP degli exit node Tor sono **pubblicamente noti** (sono nel consenso). I siti
possono:

1. **Scaricare la lista degli exit** da `https://check.torproject.org/torbulkexitlist`
2. **Bloccare o limitare** le connessioni provenienti da questi IP
3. **Richiedere CAPTCHA** aggiuntivi
4. **Ridurre le funzionalità** (no login, no acquisti, no API)

### Siti che ho testato personalmente

| Sito | Comportamento via Tor |
|------|----------------------|
| Google Search | CAPTCHA frequenti, a volte blocco totale |
| Google Maps | Funziona con CAPTCHA occasionali |
| Amazon | Blocco login, richiesta verifica aggiuntiva |
| Reddit | Funziona ma richiede login frequente |
| GitHub | Funziona generalmente bene |
| Wikipedia | Lettura OK, editing bloccato |
| PayPal | Login bloccato, "suspicious activity" |
| Instagram/Meta | Login molto difficile, blocchi frequenti |
| Stack Overflow | Funziona bene |
| Banche italiane | Blocco totale o 2FA forzato |

### Strategie per gestire i blocchi

1. **NEWNYM e riprova**: a volte il blocco è sull'exit specifico. Cambiando exit
   (NEWNYM) potresti ottenere un exit non bloccato.

2. **Non loggarsi**: usare Tor per navigazione anonima, non per account personali.
   Loggarsi con account personali su Tor è un errore OPSEC (vedi sezione sicurezza).

3. **Accettare i limiti**: certi servizi non funzioneranno mai bene via Tor. È
   un compromesso dell'anonimato.

---

## Exit Node e DNS - Chi risolve cosa

### Il flusso DNS in un circuito Tor

```
1. L'utente chiede di connettersi a "example.com"
2. L'hostname viene inviato al SocksPort come DOMAINNAME (non risolto localmente)
3. Tor crea una cella RELAY_BEGIN con "example.com:443"
4. L'Exit Node riceve "example.com:443"
5. L'Exit Node usa il SUO resolver DNS per risolvere "example.com"
6. L'Exit Node si connette all'IP risultante
```

### Implicazioni

- **Il DNS non esce MAI dal tuo computer** (se usi proxychains/torsocks correttamente)
- **L'Exit Node fa la risoluzione DNS** → usa il DNS del datacenter dove si trova
- **Exit diversi possono risolvere hostname diversamente** (CDN, load balancing, geo-DNS)

### DNS leak

Se un'applicazione risolve l'hostname PRIMA di inviarlo al SocksPort, il DNS
esce in chiaro verso il tuo ISP. Questo è un **DNS leak**:

```
CORRETTO (no leak):
curl --socks5-hostname 127.0.0.1:9050 https://example.com
  → "example.com" inviato come stringa a Tor → Exit risolve

SBAGLIATO (leak):
curl --socks5 127.0.0.1:9050 https://example.com
  → curl risolve "example.com" localmente → DNS leak!
  → poi invia l'IP a Tor

La differenza è --socks5-hostname (risolve via proxy) vs --socks5 (risolve localmente)
```

Proxychains con `proxy_dns` attivo gestisce questo automaticamente, intercettando
le chiamate DNS e inviandole al proxy.

---

## Exit Policy e il principio di selettività

### Exit policy ridotta (Reduced Exit Policy)

Molti operatori di exit usano una policy ridotta che permette solo le porte più
comuni e sicure:

```
accept *:20-23     # FTP, SSH, Telnet
accept *:43        # WHOIS
accept *:53        # DNS
accept *:80        # HTTP
accept *:443       # HTTPS
accept *:993       # IMAPS
accept *:995       # POP3S
reject *:*         # Blocca tutto il resto
```

### Perché le exit policy sono restrittive

- **Ridurre abuse complaints**: porte come 25 (SMTP) generano spam. Porte come
  6667 (IRC) generano flood. Bloccandole, l'operatore riceve meno segnalazioni.
- **Ridurre il rischio legale**: meno porte aperte = meno possibilità di essere
  associato a traffico illegale.
- **Concentrare la bandwidth**: la bandwidth dell'exit è limitata. Servire solo
  porte web (80/443) massimizza l'utilità per la maggior parte degli utenti.

### Impatto sulla selezione dei circuiti

Tor seleziona l'exit PRIMA della porta richiesta dallo stream. Se lo stream
richiede porta 22 (SSH), Tor cerca un exit che permetta porta 22. Se pochi
exit la permettono, il pool è ristretto e la latenza potenzialmente peggiore.

---

## Identificare gli Exit Node nel consenso

### Lista degli exit attivi

```bash
# Scaricare il consenso e filtrare gli exit
proxychains curl -s http://128.31.0.34:9131/tor/status-vote/current/consensus > /tmp/consensus.txt

# Contare i relay con flag Exit
grep -c "^s.*Exit" /tmp/consensus.txt

# Estrarre IP degli exit
grep -B1 "^s.*Exit" /tmp/consensus.txt | grep "^r " | awk '{print $7}'
```

### Numeri tipici

- ~7000 relay totali
- ~1000-1500 relay con flag Exit
- ~800-1000 exit che accettano la porta 443
- ~400-600 exit che accettano anche la porta 22

Il numero relativamente basso di exit rispetto ai relay totali è il motivo per cui:
- Gli exit sono il collo di bottiglia della rete
- I bandwidth weights nel consenso favoriscono gli exit
- I siti possono facilmente elencare e bloccare tutti gli exit

---

## Riepilogo dei rischi e mitigazioni

| Rischio | Condizione | Mitigazione |
|---------|-----------|-------------|
| Sniffing contenuto | Solo se HTTP (non HTTPS) | Usare SEMPRE HTTPS |
| DNS spoofing | Exit malevolo | Verificare certificati TLS |
| SSL stripping | Sito raggiunto via HTTP iniziale | HSTS, Tor Browser |
| Download injection | File scaricato via HTTP | Verificare hash/firma |
| Logging metadata | Sempre possibile | Tor Browser riduce metadata |
| MITM su TLS | Exit genera cert falso | Non ignorare errori certificato |
| Blocchi/CAPTCHA | IP exit è pubblico | NEWNYM, accettare il compromesso |
| Exit policy restrittiva | Porte non standard | Riprova con NEWNYM |

---

## Vedi anche

- [Exit Nodes](exit-nodes.md) - Ruolo, exit policy, rischi
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - Approfondimento DNS leak
- [Verifica IP, DNS e Leak](../04-strumenti-operativi/verifica-ip-dns-e-leak.md) - Test pratici
- [OpSec e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Login via Tor
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
