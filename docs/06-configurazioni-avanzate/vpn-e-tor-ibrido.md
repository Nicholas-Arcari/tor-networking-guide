# VPN e Tor — Configurazioni Ibride

Questo documento analizza in profondità perché Tor non è una VPN, le configurazioni
ibride VPN+Tor, i compromessi di ciascun approccio, e quale configurazione è
effettivamente utile nel mondo reale.

Basato sulla mia esperienza nel tentare di usare Tor come VPN, nel configurare
bridge per aggirare blocchi, e nel capire perché un approccio ibrido è la soluzione
più pratica.

---

## Perché Tor non è (e non può essere) una VPN

### Differenze architetturali fondamentali

| Caratteristica | VPN | Tor |
|---------------|-----|-----|
| Livello OSI | Layer 3/4 (IP/TCP) | Layer 7 (applicativo, SOCKS5) |
| Interfaccia di rete | Crea `tun0`/`tap0` | Nessuna interfaccia (proxy) |
| Routing | `ip route` gestisce tutto il traffico | Solo traffico applicativo configurato |
| Protocolli supportati | TCP, UDP, ICMP — tutto | Solo TCP |
| IP di uscita | Un IP fisso (server VPN) | IP variabile (exit node diversi) |
| Numero di hop | 1 (client→server VPN) | 3 (guard→middle→exit) |
| Controllo del server | Di un'azienda/privato | Volontari anonimi |
| Latenza | Bassa (1 hop) | Alta (3+ hop) |
| Bandwidth | Alta | Limitata (nodi volontari) |
| Privacy da chi? | ISP, rete locale | ISP, siti web, sorveglianza |

### Cosa significa "non crea interfaccia di rete"

Con una VPN:
```bash
> ip route
default via 10.8.0.1 dev tun0    # TUTTO il traffico va via VPN
```
Il kernel Linux vede `tun0` come interfaccia di rete. Ogni pacchetto IP viene
automaticamente instradato attraverso la VPN.

Con Tor:
```bash
> ip route
default via 192.168.1.1 dev eth0  # Il routing di sistema NON è cambiato
```
Tor non modifica il routing. Solo le applicazioni che si connettono esplicitamente
al SocksPort (9050) passano da Tor. Tutto il resto esce normalmente.

### Nella mia esperienza

Ho provato a rendere Tor "system-wide" con:
- `proxychains` su ogni applicazione → scomodo, non copre i servizi di sistema
- `torsocks` come wrapper globale → non copre processi già in esecuzione
- TransPort + iptables → quasi-VPN ma senza UDP

La conclusione: Tor non può sostituire una VPN. Risolvono problemi diversi.

---

## Configurazioni ibride

### 1. VPN → Tor (Onion over VPN)

```
Tu → [VPN] → [Guard Tor] → [Middle] → [Exit] → Internet
```

Il tuo ISP vede: connessione VPN (non vede Tor).
Il provider VPN vede: connessione al Guard Tor.
L'exit Tor vede: la destinazione (non il tuo IP reale né quello VPN).

**Vantaggi**:
- L'ISP non sa che usi Tor (il traffico sembra VPN normale)
- Se Tor è bloccato nella tua rete, la VPN può aggirare il blocco
- L'exit node non vede il tuo IP reale (vede il guard, che è un relay Tor)

**Svantaggi**:
- Il provider VPN conosce il tuo IP reale E sa che usi Tor
- Aggiunge latenza (VPN + 3 hop Tor)
- Se la VPN logga, la tua connessione a Tor è loggata

**Quando usarla**:
- La rete blocca Tor (alternativa ai bridge)
- Vuoi nascondere l'uso di Tor all'ISP senza bridge obfs4

**Nella mia esperienza**: i bridge obfs4 sono una soluzione migliore per nascondere
Tor all'ISP, perché non richiedono di fidarsi di un provider VPN.

### 2. Tor → VPN (Tor over VPN) — Sconsigliato

```
Tu → [Guard] → [Middle] → [Exit] → [VPN] → Internet
```

**Svantaggi critici**:
- La VPN diventa l'unico punto di uscita → fingerprint altissimo
- La VPN conosce la destinazione E il traffico (anche se non il tuo IP)
- Rompe l'anonimato di Tor (l'exit invia a un singolo IP: la VPN)
- Pochi provider VPN accettano connessioni da Tor

**Non usare questa configurazione.**

### 3. Tor TransPort + iptables (quasi-VPN)

Instrada tutto il traffico TCP del sistema attraverso Tor usando iptables:

```ini
# Nel torrc
TransPort 9040
DNSPort 5353
```

```bash
# iptables per forzare tutto il traffico TCP attraverso Tor
# ATTENZIONE: queste regole bloccano tutto il traffico non-Tor

# Permetti traffico di Tor stesso (utente debian-tor)
sudo iptables -t nat -A OUTPUT -m owner --uid-owner debian-tor -j RETURN
sudo iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
sudo iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports 9040

# Blocca tutto il traffico diretto (non-Tor)
sudo iptables -A OUTPUT -m owner --uid-owner debian-tor -j ACCEPT
sudo iptables -A OUTPUT -p tcp -d 127.0.0.0/8 -j ACCEPT
sudo iptables -A OUTPUT -j DROP
```

**Vantaggi**:
- Effetto quasi-VPN: tutto il traffico TCP passa da Tor
- DNS forzato via Tor (no leak)
- Le applicazioni non devono essere configurate singolarmente

**Svantaggi**:
- **UDP non supportato** → niente NTP, QUIC, VoIP, gaming
- Se Tor si blocca, tutta la rete è bloccata
- Fragile: un errore nelle regole iptables può causare leak
- Performance scarse (tutto il traffico su 3 hop)

### 4. Routing selettivo per applicazione (il mio approccio)

```
Browser → proxychains → Tor → Internet (anonimo)
Terminale → proxychains → Tor → Internet (anonimo)
Aggiornamenti sistema → rete normale / VPN → Internet
Streaming → VPN → Internet
App sensibili → rete normale
```

**Vantaggi**:
- Flessibilità massima
- Non sovraccarica Tor con traffico non necessario
- Ogni applicazione usa il canale migliore per il suo scopo
- Non rompe applicazioni che necessitano UDP

**Svantaggi**:
- Richiede disciplina (ricordarsi di usare proxychains)
- Possibili leak se dimentico di proxare un'applicazione
- Non automatico

**Nella mia esperienza, questa è la configurazione che uso**:
- `proxychains curl` per verifiche
- `proxychains firefox -no-remote -P tor-proxy` per navigazione
- Rete normale per tutto il resto

---

## ExitNodes e geolocalizzazione forzata

### Il problema

Ho provato a forzare l'uscita da un paese specifico:
```ini
ExitNodes {it}
StrictNodes 1
```

Risultati:
- Pochissimi exit italiani disponibili (forse 10-20)
- Circuiti saturi e lenti
- IP che cambiava comunque ad ogni rinnovo del circuito
- Fingerprinting facile ("questo utente esce SEMPRE dall'Italia")

### Perché non funziona

Tor è progettato per la **randomizzazione**. Forzare un paese:
- Riduce il pool di exit (meno privacy, meno bandwidth)
- Rende il traffico più riconoscibile
- Non garantisce lo stesso IP nel tempo (circuiti vengono rinnovati)

Per avere un IP fisso di un paese specifico, una VPN è lo strumento giusto.

---

## Compromessi riassuntivi

| Configurazione | Privacy | Anonimato | Velocità | Affidabilità | Complessità |
|---------------|---------|-----------|----------|-------------|-------------|
| Solo Tor | Alta | Molto alta | Bassa | Media | Bassa |
| Solo VPN | Media | Bassa | Alta | Alta | Bassa |
| VPN → Tor | Alta | Alta | Molto bassa | Media | Media |
| Tor → VPN | Bassa | Bassa | Bassa | Bassa | Alta |
| TransPort+iptables | Alta | Alta | Bassa | Bassa | Alta |
| Routing selettivo | Alta | Alta (per app proxate) | Variabile | Alta | Media |

**La mia scelta**: routing selettivo. È il compromesso migliore tra sicurezza,
usabilità e praticità quotidiana.
