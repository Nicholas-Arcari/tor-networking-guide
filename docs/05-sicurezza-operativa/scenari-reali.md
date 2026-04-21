> **Lingua / Language**: Italiano | [English](../en/05-sicurezza-operativa/scenari-reali.md)

# Scenari Reali - Sicurezza Operativa Tor in Azione

Casi operativi in cui DNS leak, fingerprinting, OPSEC, isolamento e hardening
hanno fatto la differenza durante penetration test, red team engagement e
attività OSINT.

---

## Indice

- [Scenario 1: DNS leak non rilevato durante OSINT su target sensibile](#scenario-1-dns-leak-non-rilevato-durante-osint-su-target-sensibile)
- [Scenario 2: JA3 fingerprint tradisce l'operatore durante red team](#scenario-2-ja3-fingerprint-tradisce-loperatore-durante-red-team)
- [Scenario 3: Artefatti forensi su workstation post-engagement](#scenario-3-artefatti-forensi-su-workstation-post-engagement)
- [Scenario 4: OPSEC failure - correlazione temporale tra sessioni](#scenario-4-opsec-failure--correlazione-temporale-tra-sessioni)
- [Scenario 5: Isolamento con network namespace salva un engagement](#scenario-5-isolamento-con-network-namespace-salva-un-engagement)

---

## Scenario 1: DNS leak non rilevato durante OSINT su target sensibile

### Contesto

Un team OSINT raccoglieva informazioni su un'organizzazione target. L'operatore
usava `proxychains firefox` con il profilo tor-proxy per navigare su siti collegati
al target. Dopo due giorni, il cliente ha ricevuto alert dal proprio SOC che
indicavano query DNS sospette per i propri domini da un IP italiano.

### Problema

Firefox con proxychains risolveva correttamente via Tor per i siti visitati
direttamente, ma il DNS prefetch pre-risolveva i domini dei link nelle pagine.

```bash
# tcpdump mostra le query prefetch che escono in chiaro
sudo tcpdump -i eth0 port 53 -n
# 14:23:01 IP 151.x.x.x.48320 > 192.168.1.1.53: A? subdomain.target.com
# 14:23:01 IP 151.x.x.x.48321 > 192.168.1.1.53: A? mail.target.com
# → Firefox pre-risolveva i link nella pagina PRIMA del click
```

Il profilo tor-proxy aveva `network.proxy.socks_remote_dns = true`, ma
`network.dns.disablePrefetch` era rimasto a `false` (default).

### Fix

```
# about:config - aggiungere al profilo tor-proxy:
network.dns.disablePrefetch = true
network.prefetch-next = false
network.predictor.enabled = false
network.http.speculative-parallel-limit = 0
```

### Lezione appresa

`socks_remote_dns` protegge solo le richieste DNS esplicite. Il prefetch DNS
di Firefox è un meccanismo separato che bypassa completamente il proxy. Vedi
[DNS Leak](dns-leak.md) per tutti gli scenari e [Hardening Avanzato](hardening-avanzato.md)
per la configurazione Firefox completa.

---

## Scenario 2: JA3 fingerprint tradisce l'operatore durante red team

### Contesto

Durante un red team, l'operatore usava Firefox+proxychains su Kali per
ricognizione web sul target. Il target aveva un WAF (Web Application Firewall)
con fingerprinting JA3 attivo. Dopo poche richieste, l'IP dell'exit Tor è
stato bloccato.

### Analisi

Il WAF del target confrontava il JA3 hash con il User-Agent dichiarato:

```
User-Agent: Mozilla/5.0 (Windows NT 10.0; rv:128.0) [privacy.resistFingerprinting]
JA3 hash: e7d705a3286e19ea42f587b344ee6865 [Firefox su Linux]

→ INCOERENZA: User-Agent dice Windows, JA3 dice Linux
→ WAF flag: "spoofed User-Agent" → blocco automatico
```

Con `privacy.resistFingerprinting` attivo, Firefox dichiarava Windows nel
User-Agent, ma il TLS ClientHello conteneva parametri specifici di Firefox
su Linux - una discrepanza impossibile per un utente reale Windows.

### Soluzione

```bash
# Opzione 1: NON usare resistFingerprinting (coerenza JA3/UA)
# Il JA3 corrisponde a Firefox su Linux, e il UA dice Linux
# Meno sospetto per WAF con JA3 matching

# Opzione 2: Tor Browser (JA3 e UA coerenti, pool largo)
# Tor Browser ha JA3 specifico e UA corrispondente
# Il WAF vede "utente Tor Browser" - pool di milioni

# Opzione 3: curl con --socks5-hostname (JA3 diverso)
proxychains curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
  https://target.com/
# curl ha un JA3 diverso da Firefox - meno associato a Linux
```

### Lezione appresa

`privacy.resistFingerprinting` crea incoerenza tra User-Agent e JA3, che è
più sospetto del non-spoofing. Per ricognizione web su target con WAF avanzato,
usare Tor Browser (JA3/UA coerenti) o strumenti con JA3 non-browser.
Vedi [Fingerprinting](fingerprinting.md) per JA3/JA4 e la tabella di protezione.

---

## Scenario 3: Artefatti forensi su workstation post-engagement

### Contesto

Dopo un red team engagement di 3 mesi, il team doveva restituire le workstation
aziendali. Un membro del team aveva usato Tor su quella macchina per la
ricognizione. La policy aziendale prevedeva audit forense pre-restituzione.

### Problema

L'audit ha trovato tracce estensive dell'uso di Tor:

```bash
# L'auditor ha eseguito:
dpkg -l | grep -iE "tor |torsocks|obfs4|nyx|proxychains"
# → 5 pacchetti Tor-related installati

journalctl -u tor@default --since "3 months ago" | head -50
# → Centinaia di entry con timestamp di avvio/NEWNYM/shutdown

cat /var/lib/tor/state
# → Guard fingerprint, ultimo uso, bridge obfs4 configurati

grep -r "proxychains\|torsocks\|nyx" ~/.zsh_history
# → 200+ comandi con target specifici del cliente

cat ~/.mozilla/firefox/*.tor-proxy/prefs.js | grep socks
# → Configurazione SOCKS5 127.0.0.1:9050
```

### Mitigazione applicata (post-incidente)

```bash
# 1. Pulizia Tor
sudo systemctl stop tor@default.service
sudo apt purge tor tor-geoipdb obfs4proxy nyx torsocks
sudo rm -rf /var/lib/tor/ /var/log/tor/ /etc/tor/

# 2. Pulizia browser
rm -rf ~/.mozilla/firefox/*.tor-proxy/

# 3. Pulizia history
rm -f ~/.zsh_history ~/.bash_history

# 4. Pulizia log
sudo journalctl --vacuum-time=1d

# 5. Pulizia apt history
sudo rm /var/log/apt/history.log*
```

### Lezione appresa

Per engagement dove l'uso di Tor non deve lasciare tracce sulla macchina:
- Usare una VM dedicata (eliminabile a fine engagement)
- Oppure Tails da USB (zero artefatti su disco)
- Oppure Docker con volume tmpfs (contenitore usa-e-getta)

La pulizia post-hoc è sempre incompleta: journald può avere entry in
segmenti ruotati, il filesystem può avere dati recuperabili. Vedi
[Analisi Forense e Artefatti](analisi-forense-e-artefatti.md) per la lista
completa degli artefatti.

---

## Scenario 4: OPSEC failure - correlazione temporale tra sessioni

### Contesto

Un operatore conduceva ricognizione anonima su un forum del target. Usava
Tor correttamente, NEWNYM tra sessioni, nessun login. Ma il SOC del target
ha correlato le sessioni anonime con l'engagement.

### Come è stato scoperto

```
Pattern osservato dal SOC del target:
- Visite anonime al forum: ogni giorno 09:00-09:30 e 14:00-14:30
- Sempre da exit Tor europei
- Pattern di navigazione: sempre stesse sezioni del forum
- Le visite sono iniziate esattamente il giorno di inizio engagement

Correlazione del SOC:
- L'engagement è stato comunicato internamente il 1° marzo
- Le visite anonime al forum sono iniziate il 2 marzo
- Le visite seguono orari di lavoro italiani (09-18 CET)
- L'operatore è l'unico visitor Tor ricorrente al forum
→ Conclusione: le visite anonime provengono dal team di pentest
```

### Fix procedurale

```
1. NON iniziare la ricognizione il giorno dopo il kick-off
   → Iniziare almeno 1-2 settimane prima (se il contratto lo permette)
   → Oppure randomizzare l'inizio

2. NON usare orari prevedibili
   → Variare gli orari di accesso (non sempre 09:00 e 14:00)
   → Includere accessi fuori orario lavorativo

3. Usare NEWNYM tra sezioni diverse del forum
   → Non navigare più sezioni con lo stesso exit IP

4. Mixare con traffico non-target
   → Visitare anche altri forum simili per creare rumore
```

### Lezione appresa

L'OPSEC comportamentale è importante quanto quella tecnica. Pattern temporali
regolari e correlazione con eventi noti (inizio engagement) sono vettori di
deanonimizzazione che Tor non può prevenire. Vedi
[OPSEC e Errori Comuni](opsec-e-errori-comuni.md) per i pattern comportamentali
e [OPSEC - Casi Reali](opsec-casi-reali-e-difese.md) per casi storici.

---

## Scenario 5: Isolamento con network namespace salva un engagement

### Contesto

Durante un engagement, un operatore doveva eseguire uno script Python
personalizzato via Tor per enumerare endpoint API del target. Lo script usava
`requests` con proxy SOCKS5, ma faceva anche chiamate a servizi interni
(logging, database locale) che non dovevano passare da Tor.

### Problema

Lo script aveva un bug: una dipendenza faceva richieste HTTP a un servizio
di telemetria esterno senza rispettare il proxy SOCKS5 configurato. Le
richieste uscivano con l'IP reale dell'operatore.

```python
# Il codice dell'operatore (corretto):
import requests
session = requests.Session()
session.proxies = {"https": "socks5h://127.0.0.1:9050"}
resp = session.get("https://api.target.com/v1/users")

# La dipendenza importata (bug):
import analytics  # libreria di logging interna
analytics.track("scan_started")  # → HTTP POST a analytics.example.com
# → Esce con IP reale! La libreria non usa il proxy della session
```

### Soluzione: network namespace

```bash
# Creare namespace isolato
sudo ip netns add pentest_ns
sudo ip link add veth-host type veth peer name veth-ns
sudo ip link set veth-ns netns pentest_ns
sudo ip addr add 10.200.1.1/24 dev veth-host
sudo ip link set veth-host up
sudo ip netns exec pentest_ns ip addr add 10.200.1.2/24 dev veth-ns
sudo ip netns exec pentest_ns ip link set veth-ns up
sudo ip netns exec pentest_ns ip link set lo up
sudo ip netns exec pentest_ns ip route add default via 10.200.1.1

# Forzare tutto il traffico del namespace via Tor TransPort
sudo iptables -t nat -A PREROUTING -s 10.200.1.0/24 -p tcp \
    -j REDIRECT --to-ports 9040
sudo iptables -t nat -A PREROUTING -s 10.200.1.0/24 -p udp --dport 53 \
    -j REDIRECT --to-ports 5353
sudo iptables -A FORWARD -s 10.200.1.0/24 -j DROP

# Eseguire lo script nel namespace
sudo ip netns exec pentest_ns sudo -u $USER python3 scan_api.py
# → TUTTO il traffico TCP passa da Tor, inclusa la telemetria
# → La richiesta analytics.track() passa da Tor automaticamente
# → UDP bloccato (nessun DNS leak possibile)
```

### Lezione appresa

Il network namespace forza **tutto** il traffico di un processo e delle sue
dipendenze attraverso Tor, indipendentemente da come il codice gestisce le
connessioni. È la soluzione ideale per script con dipendenze non controllate.
Vedi [Isolamento Avanzato](isolamento-avanzato.md) per il setup completo e
[Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) per
iptables/nftables.

---

## Riepilogo

| Scenario | Area | Rischio mitigato |
|----------|------|------------------|
| DNS prefetch in OSINT | DNS Leak | Query DNS in chiaro per domini target |
| JA3 mismatch con WAF | Fingerprinting | Blocco IP per incoerenza UA/JA3 |
| Artefatti post-engagement | Forense | Tracce Tor su workstation aziendale |
| Correlazione temporale | OPSEC | Pattern di accesso predicibili |
| Namespace per script Python | Isolamento | Leak IP da dipendenze non controllate |

---

## Vedi anche

- [DNS Leak](dns-leak.md) - Scenari di leak e verifica
- [Fingerprinting](fingerprinting.md) - JA3, browser, OS fingerprinting
- [Analisi Forense e Artefatti](analisi-forense-e-artefatti.md) - Artefatti su disco e RAM
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - Errori e correlazione
- [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) - Namespaces, Whonix, Tails
- [Hardening di Sistema](hardening-sistema.md) - Configurazione Firefox e sistema
