# Bridges e Pluggable Transports — Aggirare Censura e DPI

Questo documento analizza in profondità i Bridge Tor, i Pluggable Transports (PT),
e in particolare obfs4: come funzionano a livello protocollare, come resistono alla
Deep Packet Inspection, come configurarli, e i limiti reali nell'uso quotidiano.

Include la mia esperienza diretta nel richiedere bridge, configurarli nel torrc,
debuggare connessioni fallite, e usarli su reti restrittive (universitarie,
hotspot pubblici).

---

## Perché esistono i Bridge

I relay Tor normali sono elencati nel **consenso pubblico**. Chiunque può scaricare
la lista di tutti i ~7000 relay con i loro IP. Questo significa che:

1. **Un ISP può bloccare tutti i relay Tor**: scarica il consenso, estrae gli IP,
   li aggiunge a una blacklist nel firewall.

2. **Un governo con DPI può identificare il traffico Tor**: anche senza bloccare gli
   IP, l'analisi dei pacchetti può rilevare pattern tipici del protocollo Tor
   (TLS handshake specifico, formato delle celle, timing).

3. **Un osservatore passivo sa che usi Tor**: il tuo ISP vede una connessione verso
   un IP noto come relay Tor.

I Bridge risolvono questi problemi perché:
- **Non sono nel consenso pubblico** → non possono essere bloccati per lista
- **Usano Pluggable Transports** → il traffico non sembra Tor
- **Sono distribuiti in modo limitato** → più difficili da scoprire per un censore

---

## Come funzionano i Bridge a livello di protocollo

### Architettura di un bridge

Un bridge è un relay Tor con due differenze:
1. Non pubblica il suo descriptor nel consenso pubblico
2. Pubblica il descriptor solo alla **Bridge Authority**
3. Supporta Pluggable Transports per offuscare il traffico

```
Connessione tramite relay normale:
[Client Tor] ──TLS──► [Guard pubblico] ──TLS──► [Middle] ──► [Exit]
  L'ISP vede: connessione TLS verso IP noto come Tor relay

Connessione tramite bridge obfs4:
[Client Tor] ──PT──► [obfs4proxy client] ──obfs4──► [Bridge] ──► [Middle] ──► [Exit]
  L'ISP vede: traffico che sembra rumore casuale verso IP sconosciuto
```

### Il flusso con obfs4

1. Il client Tor legge la riga `Bridge obfs4 IP:PORT FINGERPRINT cert=... iat-mode=N`
2. Avvia `obfs4proxy` come processo figlio usando il protocollo PT (Pluggable Transport)
3. obfs4proxy apre una porta locale (es. 127.0.0.1:47832)
4. Tor si connette a questa porta locale come se fosse un relay
5. obfs4proxy riceve i dati, li offusca, e li invia al bridge remoto
6. Il bridge remoto ha obfs4proxy server-side che deoffusca i dati
7. Il bridge processa il traffico Tor normalmente
8. Il circuito continua: bridge → middle → exit → internet

---

## Pluggable Transports — I protocolli di offuscamento

### Cos'è un Pluggable Transport

Un PT è un programma che **trasforma il traffico Tor** in qualcosa che non sembra
Tor. Si posiziona tra il client e il bridge:

```
[Tor daemon] ←SOCKS→ [PT client-side] ←offuscato→ [PT server-side] ←→ [Bridge Tor]
```

I PT comunicano con Tor tramite il **protocollo PT** (specificato in `pt-spec.txt`):
- Tor imposta variabili d'ambiente (`TOR_PT_MANAGED_TRANSPORT_VER`, `TOR_PT_CLIENT_TRANSPORTS`, etc.)
- Il PT stampa su stdout le porte che ha aperto (es. `CMETHOD obfs4 socks5 127.0.0.1:47832`)
- Tor si connette a queste porte

### Tipi di Pluggable Transport

| Transport | Tecnica | Resistenza a DPI | Velocità | Stato |
|-----------|---------|-----------------|----------|-------|
| **obfs4** | Offuscamento crittografico, sembra rumore | Alta | Buona | **Raccomandato** |
| **meek** | Incapsula in HTTPS verso CDN (Amazon, Azure) | Molto alta | Lenta | Attivo |
| **Snowflake** | Usa WebRTC tramite browser volontari | Alta | Variabile | Attivo |
| **webtunnel** | Sembra traffico HTTPS normale | Alta | Buona | Nuovo |
| obfs3 | Offuscamento semplice | Bassa | Buona | Deprecato |
| ScrambleSuit | Offuscamento con shared secret | Media | Buona | Deprecato |
| FTE | Format-Transforming Encryption | Media | Media | Deprecato |

---

## obfs4 — Analisi tecnica approfondita

### Come funziona l'offuscamento

obfs4 (Obfuscation version 4) trasforma il traffico Tor in dati che:
- **Non hanno pattern riconoscibili** — nessun header, magic byte, o struttura
- **Sembrano rumore casuale** — distribuzione uniforme dei byte
- **Non hanno dimensioni di pacchetto prevedibili** — padding variabile
- **Non hanno timing prevedibile** — con iat-mode, il timing viene randomizzato

### Il protocollo obfs4 step-by-step

**Fase 1: Handshake**

```
Client                                    Server (Bridge)
  |                                          |
  | Il client conosce:                       |
  | - node-id (fingerprint del bridge)       |
  | - public-key (chiave Curve25519 server)  |
  | (entrambi dal campo cert= del bridge)    |
  |                                          |
  | 1. Genera keypair ephemeral Curve25519   |
  | 2. Calcola mark = HMAC(keypair, node-id) |
  | 3. Invia: X (pubkey) + padding + mark    |
  |─────────────────────────────────────────►|
  |                                          | 4. Riceve, trova mark nel flusso
  |                                          | 5. Verifica che X sia valido
  |                                          | 6. Genera keypair ephemeral
  |                                          | 7. Calcola shared secret (ECDH)
  |                                          | 8. Invia: Y (pubkey) + auth + padding
  |◄─────────────────────────────────────────|
  | 9. Calcola shared secret (ECDH)          |
  | 10. Verifica auth                        |
  | 11. Deriva chiavi simmetriche            |
  |                                          |
  | Ora entrambi hanno chiavi per            |
  | NaCl secretbox (XSalsa20+Poly1305)       |
```

**Fase 2: Trasferimento dati offuscati**

Dopo l'handshake, ogni pacchetto è:
```
[length (2 byte, cifrati)] [payload (cifrato con NaCl secretbox)] [padding]
```

- La lunghezza è cifrata → un osservatore non sa quanto è grande il payload
- Il payload è cifrato e autenticato (Poly1305)
- Il padding è variabile → le dimensioni dei pacchetti sono imprevedibili

### iat-mode — Inter-Arrival Time obfuscation

Il parametro `iat-mode` nel bridge controlla l'offuscamento temporale:

**iat-mode=0**: nessun padding temporale. I pacchetti vengono inviati quando i dati
sono pronti. Un osservatore può analizzare il timing dei pacchetti per correlare
con pattern noti.

**iat-mode=1**: padding temporale moderato. obfs4 aggiunge un ritardo casuale tra
i pacchetti per spezzare pattern temporali evidenti.

**iat-mode=2**: padding temporale massimo. obfs4 aggiunge ritardi e pacchetti
dummy per rendere il timing completamente casuale. Aumenta la latenza ma migliora
la resistenza a traffic analysis avanzata.

### Nella mia esperienza

Ho usato bridge con diversi iat-mode:

```ini
Bridge obfs4 xxx.xxx.xxx.xxx:4431 F829D395093B... cert=... iat-mode=0
Bridge obfs4 xxx.xxx.xxx.xxx:13630 A3D55AA6178... cert=... iat-mode=2
```

- `iat-mode=0`: più veloce, sufficiente per nascondere il traffico Tor all'ISP
- `iat-mode=2`: più lento ma necessario su reti con DPI aggressivo

Su reti universitarie con firewall pesante, `iat-mode=0` è stato sufficiente.
Il firewall non analizzava il timing, solo il tipo di protocollo.

---

## Resistenza alla censura — Come obfs4 sopravvive ai censori

### Livello 1: Blocco per IP

**Attacco**: il censore blocca gli IP dei relay Tor noti.

**Difesa di obfs4**: i bridge non sono nel consenso pubblico. Gli IP dei bridge
sono distribuiti tramite canali limitati. Il censore non ha una lista completa.

**Limite**: se il censore ottiene un bridge (richiedendolo dal sito o via email),
può bloccarne l'IP. Per questo i bridge vengono distribuiti in modo limitato
(CAPTCHA, rate limiting, etc.).

### Livello 2: Deep Packet Inspection (DPI)

**Attacco**: il censore analizza il contenuto dei pacchetti per riconoscere il
protocollo Tor (magic bytes, handshake patterns, distribuzione dei byte).

**Difesa di obfs4**:
- Nessun magic byte o header riconoscibile
- L'handshake sembra rumore casuale (distribuzione uniforme)
- I dati cifrati sono indistinguibili dal rumore
- Le dimensioni dei pacchetti sono variabili e non seguono pattern

### Livello 3: Active Probing

**Attacco**: il censore sospetta che un IP sia un bridge. Apre una connessione e
prova a fare l'handshake Tor. Se il server risponde come un relay Tor, lo blocca.

**Difesa di obfs4**:
- Il server obfs4 non risponde a connessioni che non presentano il corretto `mark`
  nell'handshake
- Il `mark` è derivato dalla chiave pubblica del server, che solo i client legittimi
  conoscono (dal campo `cert=`)
- Un censore che non conosce `cert` non può completare l'handshake
- Il server semplicemente non risponde o chiude la connessione

### Livello 4: Statistical Analysis

**Attacco**: il censore analizza le proprietà statistiche del traffico (distribuzione
delle dimensioni dei pacchetti, entropia, timing) per distinguere obfs4 da traffico
legittimo.

**Difesa di obfs4**:
- Alta entropia (sembra rumore casuale — ma anche il rumore ha entropia alta)
- iat-mode per randomizzare timing
- Padding per variare dimensioni

**Limite**: un censore sofisticato potrebbe notare che il traffico ha entropia
insolitamente alta (il traffico web normale ha pattern strutturati, non rumore puro).
Questo è un'area di ricerca attiva.

---

## Come ottenere bridge — Esperienza pratica

### Metodo 1: Sito ufficiale

URL: `https://bridges.torproject.org/options`

1. Vai al sito
2. Seleziona il tipo di transport (obfs4)
3. Risolvi il CAPTCHA
4. Ricevi 2-3 righe di bridge

Nella mia esperienza:
- Il sito funziona ma è a volte lento
- I bridge forniti possono essere già saturi (molti utenti li richiedono)
- In contesti con filtraggio DNS, il dominio `bridges.torproject.org` può essere
  bloccato → usare un DNS alternativo o Tor stesso per accedere al sito

**Nota**: inizialmente avevo usato l'URL `https://bridges.torproject.org/bridges`
(suggerito da ChatGPT), che non funzionava. L'URL corretto è `.../options`.

### Metodo 2: Email

Invia un'email a `bridges@torproject.org` da un indirizzo Gmail o Riseup.

Corpo dell'email:
```
get transport obfs4
```

Risposta (entro poche ore):
```
Bridge obfs4 IP1:PORT1 FINGERPRINT1 cert=CERT1 iat-mode=0
Bridge obfs4 IP2:PORT2 FINGERPRINT2 cert=CERT2 iat-mode=0
Bridge obfs4 IP3:PORT3 FINGERPRINT3 cert=CERT3 iat-mode=0
```

Vantaggi: funziona anche se il sito è bloccato.
Svantaggi: non è immediato, richiede un account email specifico.

### Metodo 3: Snowflake (alternativa, non obfs4)

Snowflake usa browser di volontari come bridge temporanei tramite WebRTC:

```ini
UseBridges 1
ClientTransportPlugin snowflake exec /usr/bin/snowflake-client
Bridge snowflake 192.0.2.3:80 ... fingerprint ... url=...
```

Nella mia esperienza, Snowflake è:
- Meno stabile (dipende dai volontari online)
- Più lento (la banda dipende dalla connessione del volontario)
- Utile come fallback quando i bridge obfs4 non funzionano

---

## Configurazione dei bridge nel torrc

### Configurazione completa

```ini
# Abilitare bridge
UseBridges 1

# Registrare il pluggable transport
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

# Bridge (sostituire con valori reali)
Bridge obfs4 198.51.100.42:4431 AABBCCDD... cert=BASE64CERT... iat-mode=0
Bridge obfs4 203.0.113.88:13630 EEFFGGHH... cert=BASE64CERT... iat-mode=2
```

### Regole per le righe Bridge

- Il formato è rigido: `Bridge <transport> <IP>:<PORT> <FINGERPRINT> <parametri>`
- **Nessuno spazio** all'inizio della riga
- Il fingerprint è esadecimale, senza separatori (40 hex char per SHA-1)
- `cert=` è base64 senza spazi
- `iat-mode=` accetta 0, 1, o 2
- Si possono specificare più bridge: Tor li prova in ordine e usa il primo che risponde

### Verifica e debug

```bash
# Verificare la configurazione
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config

# Riavviare e monitorare
sudo systemctl restart tor@default.service
sudo journalctl -u tor@default.service -f
```

**Output di successo**:
```
Bootstrapped 5% (conn): Connecting to a relay
Bootstrapped 10% (conn_done): Connected to a relay
... (progressione fino a 100%)
Bootstrapped 100% (done): Done
```

**Output di fallimento**:
```
Bootstrapped 5% (conn): Connecting to a relay
[warn] Problem bootstrapping. Stuck at 5% (conn). (Connection timed out;
  NOROUTE; count 1; recommendation warn; host AABBCCDD at 198.51.100.42:4431)
```

Se vedo `Connection timed out` per tutti i bridge:
1. Verifico che `obfs4proxy` sia installato e eseguibile
2. Verifico che il formato dei bridge sia corretto
3. Testo la raggiungibilità dell'IP: `nc -zv 198.51.100.42 4431 -w 5`
4. Se tutto OK, i bridge sono probabilmente saturi → richiederne di nuovi

---

## meek — Incapsulamento in CDN

### Come funziona

meek nasconde il traffico Tor all'interno di connessioni HTTPS normali verso CDN
come Amazon CloudFront o Microsoft Azure:

```
[Client] ──HTTPS──► [Amazon CloudFront] ──► [meek bridge] ──► [Tor Network]
```

Il censore vede solo una connessione HTTPS verso `d2cly7j4zqgua7.cloudfront.net`
(Amazon). Bloccare questo significherebbe bloccare tutto Amazon CloudFront,
causando danni collaterali enormi. Questo è il principio del **domain fronting**.

### Limiti di meek

- **Lento**: il traffico passa attraverso una CDN → latenza aggiuntiva
- **Costoso**: il Tor Project paga per l'hosting sulle CDN
- **Domain fronting in declino**: alcuni provider (Google, Amazon) hanno limitato
  il domain fronting

### Configurazione

```ini
UseBridges 1
ClientTransportPlugin meek_lite exec /usr/bin/obfs4proxy
Bridge meek_lite 192.0.2.18:80 ... url=https://meek.azureedge.net/ front=ajax.aspnetcdn.com
```

---

## Snowflake — Bridge peer-to-peer

### Come funziona

Snowflake usa volontari che eseguono un'estensione del browser come "proxy":

```
[Client] ──WebRTC──► [Volontario browser] ──► [Snowflake bridge] ──► [Tor Network]
```

1. Il client contatta un broker (tramite domain fronting) per trovare un volontario
2. Stabilisce una connessione WebRTC con il volontario
3. Il traffico Tor viene incapsulato nel canale WebRTC
4. Il volontario lo inoltra al bridge Snowflake
5. Il bridge lo immette nella rete Tor

### Vantaggi

- I "bridge" sono milioni di browser di volontari → impossibile bloccarli tutti
- Nessuna configurazione manuale dei bridge necessaria
- Funziona anche in paesi con censura estrema

### Svantaggi

- Dipende dalla disponibilità dei volontari
- Banda limitata dalla connessione del volontario
- WebRTC può avere problemi di NAT traversal
- Latenza variabile

---

## Confronto tra i Pluggable Transport

| Caratteristica | obfs4 | meek | Snowflake |
|---------------|-------|------|-----------|
| Resistenza DPI | Alta | Molto alta | Alta |
| Active probing resistance | Alta | Molto alta | Alta |
| Velocità | Buona | Scarsa | Variabile |
| Stabilità | Buona | Buona | Media |
| Facilità config | Media | Media | Facile |
| Necessita bridge manuali | Si | No | No |
| Collateral damage per censore | Basso | Alto (bloccare CDN) | Alto (bloccare WebRTC) |
| Disponibilità | Dipende dai bridge | Limitato da costi | Dipende dai volontari |

### La mia scelta

Uso obfs4 perché:
- Offre il miglior compromesso tra velocità e sicurezza
- Ho bridge configurati e funzionanti
- Su reti universitarie dove l'ho testato, è stato sufficiente
- Non ho bisogno del livello di anti-censura di meek/Snowflake (non sono in Cina/Iran)

Per scenari di censura estrema, meek o Snowflake sarebbero la scelta migliore perché
non richiedono bridge specifici che possono essere scoperti e bloccati.
