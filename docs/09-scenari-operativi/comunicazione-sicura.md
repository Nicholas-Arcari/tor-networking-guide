# Comunicazione Sicura via Tor

Questo documento analizza come utilizzare Tor per comunicazioni sicure e anonime:
email anonima, messaggistica, condivisione file, e piattaforme dedicate come
SecureDrop e OnionShare.

> **Vedi anche**: [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md),
> [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md),
> [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md).

---

## Indice

- [Modello di minaccia per la comunicazione](#modello-di-minaccia-per-la-comunicazione)
- [Email anonima via Tor](#email-anonima-via-tor)
- [Messaggistica via Tor](#messaggistica-via-tor)
- [SecureDrop — whistleblowing](#securedrop--whistleblowing)
- [OnionShare — condivisione file](#onionshare--condivisione-file)
- [SSH via Tor](#ssh-via-tor)
- [IRC e chat via Tor](#irc-e-chat-via-tor)
- [OPSEC per comunicazione sicura](#opsec-per-comunicazione-sicura)
- [Nella mia esperienza](#nella-mia-esperienza)

---

## Modello di minaccia per la comunicazione

### Cosa protegge Tor nella comunicazione

| Aspetto | Protetto da Tor? | Note |
|---------|:---:|------|
| Chi comunica con chi | Parziale | Protegge il mittente, non sempre il destinatario |
| Contenuto messaggi | No (solo routing) | Serve crittografia end-to-end (TLS, PGP) |
| IP del mittente | Sì | L'exit/rendezvous nasconde l'IP reale |
| Metadati temporali | No | Timing analysis possibile |
| Esistenza della comunicazione | Parziale | Il traffico Tor è visibile, non il contenuto |

### Livelli di protezione

```
Livello 1: Email via Tor (ProtonMail/Tutanota)
  → Protegge IP del mittente
  → Provider vede contenuto se non E2E
  
Livello 2: Messaggistica E2E via Tor (Signal via Tor, Briar)
  → Protegge IP + contenuto
  → Server vede metadati (chi parla con chi)
  
Livello 3: Comunicazione via onion service (Ricochet, OnionShare)
  → Protegge IP + contenuto + metadati
  → Nessun server centrale
  → P2P via rendezvous
```

---

## Email anonima via Tor

### ProtonMail via Tor

ProtonMail supporta l'accesso via Tor:

```
Onion: https://protonmailrmez3lotccipshtkleegetolb73fuirgj7r4o4vfu7ozyd.onion
Web: https://proton.me (via Tor Browser o proxychains)
```

Setup:
```bash
# Accesso via Tor Browser (raccomandato)
# Navigare all'indirizzo .onion sopra

# Accesso via Firefox tor-proxy
proxychains firefox -no-remote -P tor-proxy &
# Navigare a https://proton.me
```

**Limitazioni**:
- La registrazione richiede verifica (email o telefono)
- ProtonMail vede i metadati (mittente, destinatario, timestamp)
- Il contenuto è cifrato E2E solo verso altri utenti ProtonMail (o con PGP)

### Tutanota via Tor

```
Web: https://app.tuta.com (via Tor)
```

- Registrazione senza telefono (ma con rate limiting)
- E2E cifrato verso altri utenti Tuta
- Per esterni: password condivisa per cifrare il messaggio

### Creazione account email anonimo

Per un account email veramente anonimo:

1. **Usa Tor Browser** (non Firefox tor-proxy → meno fingerprinting)
2. **Non usare informazioni reali** in nessun campo
3. **Non accedere mai senza Tor** (un singolo accesso diretto linka l'IP)
4. **Non collegare all'identità reale** (no forwarding, no contatti noti)
5. **Crea l'account da una sessione Tor dedicata** (nuova identità NEWNYM prima)

### PGP via Tor

Per cifrare email con PGP:

```bash
# Generare chiave PGP (farlo OFFLINE o via Tor)
torsocks gpg --gen-key

# Pubblicare la chiave su keyserver via Tor
torsocks gpg --keyserver hkps://keys.openpgp.org --send-keys KEY_ID

# Cercare chiavi di altri via Tor
torsocks gpg --keyserver hkps://keys.openpgp.org --search-keys target@email.com
```

---

## Messaggistica via Tor

### Signal via Tor (limitato)

Signal non supporta nativamente Tor, ma si può configurare su Android
con Orbot (proxy Tor):

```
Signal → Impostazioni → Avanzate → Proxy → Usa proxy SOCKS5
  Indirizzo: 127.0.0.1
  Porta: 9050
```

**Limitazioni**: Signal richiede numero di telefono → non anonimo.

### Briar

Briar è un messaggero progettato per la censorship resistance:
- Può comunicare via Tor (onion routing)
- Può comunicare via WiFi/Bluetooth (mesh, senza Internet)
- Nessun server centrale
- Messaggi sincronizzati via Tor bridges P2P

```
Architettura Briar:
[User A] ←→ [Tor onion service] ←→ [User B]
  Ogni utente è un onion service
  Comunicazione P2P senza server
```

### Ricochet Refresh

Successore di Ricochet, usa Tor onion services per chat P2P:

```
Architettura Ricochet:
[User A: abcdef.onion] ←→ [rendezvous] ←→ [User B: ghijkl.onion]
  Nessun server centrale
  Nessun account
  Nessun metadato
  Identità = indirizzo .onion
```

### Confronto messaggistica

| Piattaforma | Anonimato | E2E | Metadati | Decentralizzato |
|-------------|:---------:|:---:|:--------:|:---------------:|
| Email (ProtonMail) | IP nascosto | Sì (tra utenti) | Provider li vede | No |
| Signal via Tor | IP nascosto | Sì | Server li vede | No |
| Briar | Forte | Sì | Nessuno | Sì |
| Ricochet Refresh | Forte | Sì | Nessuno | Sì |
| IRC via Tor | IP nascosto | No (senza OTR) | Server li vede | Dipende |
| XMPP via Tor + OMEMO | IP nascosto | Sì | Server li vede | Federato |

---

## SecureDrop — whistleblowing

### Cos'è SecureDrop

SecureDrop è una piattaforma open source per whistleblowing anonimo, usata da
giornali e organizzazioni per ricevere documenti in modo sicuro:

```
Architettura SecureDrop:
[Whistleblower] → [Tor Browser] → [.onion SecureDrop]
  → Upload documento cifrato
  → Giornalista accede da rete air-gapped
  → Comunicazione bidirezionale anonima via codename
```

### Come funziona

1. Il whistleblower accede all'indirizzo `.onion` del giornale via Tor Browser
2. Riceve un **codename** univoco (es. "autumn elephant notebook")
3. Carica documenti e messaggi
4. Il giornalista scarica da un sistema air-gapped (Tails su hardware dedicato)
5. Il whistleblower può tornare con il codename per leggere risposte

### Istanze SecureDrop note

| Organizzazione | Uso |
|---------------|-----|
| The New York Times | Giornalismo investigativo |
| The Washington Post | Whistleblowing |
| The Guardian | Giornalismo investigativo |
| WikiLeaks | Leak documenti |
| ProPublica | Inchieste |

### OPSEC per SecureDrop

- **Usare Tails** (raccomandato ufficialmente), non Kali con Tor
- **Mai accedere da rete aziendale** del whistleblower
- **Non menzionare dettagli identificanti** nei messaggi
- **Memorizzare il codename**, non scriverlo

---

## OnionShare — condivisione file

### Cos'è OnionShare

OnionShare crea un onion service temporaneo per condividere file P2P:

```bash
# Installazione
sudo apt install onionshare-cli

# Condividere un file
onionshare-cli --receive  # ricevi file
onionshare-cli file.zip   # condividi file
```

### Come funziona

```
[Mittente] → OnionShare crea onion service temporaneo
  → Genera URL .onion + password
  → Condivide URL con destinatario (via canale sicuro)

[Destinatario] → Tor Browser → URL .onion
  → Scarica file direttamente dal computer del mittente
  → Nessun server intermedio
  → File mai su cloud o terze parti
```

### Modalità

| Modalità | Comando | Descrizione |
|----------|---------|-------------|
| Share | `onionshare-cli file.zip` | Condividi file (altri scaricano da te) |
| Receive | `onionshare-cli --receive` | Ricevi file (altri caricano a te) |
| Website | `onionshare-cli --website ./site/` | Hosting .onion temporaneo |
| Chat | `onionshare-cli --chat` | Chat room anonima temporanea |

### Vantaggi vs alternative

| Metodo | Server necessario | E2E | Anonimato | Limiti dimensione |
|--------|:-:|:-:|:-:|:-:|
| OnionShare | No (P2P) | Sì (TLS .onion) | Tor nativo | Nessuno |
| Email + PGP | Sì (SMTP) | Sì | Con Tor | ~25 MB |
| Signal | Sì | Sì | Con Tor | 100 MB |
| Cloud (GDrive) | Sì | No | No | Varia |

---

## SSH via Tor

### Connessione SSH anonima

```bash
# Via torsocks (raccomandato per IsolatePID)
torsocks ssh user@server.com

# Via proxychains
proxychains ssh user@server.com

# Via ProxyCommand nativo SSH
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:9050 %h %p" user@server.com

# Persistente in ~/.ssh/config
Host anonymous-server
    HostName server.com
    User user
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

### SSH verso onion service

```bash
# Connessione diretta a .onion (nessun exit node coinvolto)
torsocks ssh user@abcdef...xyz.onion

# In ~/.ssh/config
Host hidden-server
    HostName abcdef...xyz.onion
    User user
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

### Considerazioni di sicurezza SSH via Tor

| Aspetto | Rischio | Mitigazione |
|---------|---------|-------------|
| Host key fingerprint | Exit malevolo potrebbe MITM | Verificare fingerprint fuori-banda |
| Latenza | ~200-500ms per hop → lento per interactive | Usare mosh (non via Tor) |
| Session persistence | Circuito che cambia → disconnessione | ClientKeepAlive, MaxCircuitDirtiness alto |
| Username exposure | L'exit vede username (se non .onion) | Usare key auth, non password |

---

## IRC e chat via Tor

### IRC via Tor

```bash
# Connessione IRC via torsocks
torsocks irssi -c irc.libera.chat -p 6697 --ssl

# Oppure via proxychains
proxychains weechat
# Poi: /server add libera irc.libera.chat/6697 -ssl
```

**Nota**: molti server IRC bloccano connessioni da Tor exit node. Alternative:
- Usare server con onion service (OFTC, Libera Chat hanno .onion)
- Usare SASL auth per essere autorizzati nonostante Tor

### Matrix via Tor

```bash
# Element (client Matrix) via Tor
proxychains element-desktop &

# Homeserver via Tor: l'IP viene nascosto
# Ma: il homeserver vede i messaggi (se non E2E)
# Con E2E attivo: il homeserver vede solo metadati
```

---

## OPSEC per comunicazione sicura

### Regole fondamentali

1. **Mai mixare identità**: una sessione Tor = una identità
2. **NEWNYM tra identità diverse**: cambiare circuito tra attività diverse
3. **Non usare servizi identificanti nella stessa sessione**: se accedi a Gmail,
   non usare lo stesso circuito per comunicazione anonima
4. **Verificare sempre l'IP prima di comunicare**: `proxychains curl https://api.ipify.org`
5. **Cifrare quando possibile**: Tor protegge il routing, non il contenuto

### Pattern di scrittura

Il **stylometry** (analisi dello stile di scrittura) può deanonimizzare:
- Lunghezza media delle frasi
- Punteggiatura caratteristica
- Errori grammaticali ricorrenti
- Vocabolario specifico
- Uso di espressioni dialettali

**Mitigazione**: per comunicazioni critiche, usa un linguaggio neutro e
formale, evita espressioni personali, rivedi il testo prima di inviare.

---

## Nella mia esperienza

Ho testato diverse modalità di comunicazione via Tor:

**ProtonMail via .onion**: funziona bene, l'indirizzo .onion carica più
lentamente ma è il metodo più sicuro. L'ho usato per registrare un account
email dedicato allo studio.

**OnionShare**: l'ho provato per condividere file tra due macchine sulla
stessa rete (una con Tor Browser, l'altra con onionshare-cli). Funziona
perfettamente, anche se il transfer è lento a causa dei 6 hop totali
(3 dal sender al rendezvous + 3 dal receiver al rendezvous).

**SSH via Tor**: uso `torsocks ssh` per connessioni dove non voglio esporre
il mio IP. La latenza è notevole (~300ms per hop), rendendo l'uso interattivo
scomodo. Per sessioni lunghe, il circuito che scade (MaxCircuitDirtiness 600s)
può causare disconnessioni — ho dovuto aumentare `ServerAliveInterval` nella
config SSH.

**IRC via Tor**: ho provato a connettermi a Libera Chat via Tor. La connessione
viene bloccata per default (gli exit node Tor sono bannati). Ho dovuto usare
SASL auth e richiedere un'eccezione. Alternativa: usare il .onion di OFTC.

Il takeaway: Tor è ottimo per proteggere l'IP del mittente, ma non è sufficiente
da solo. Serve crittografia E2E per il contenuto, OPSEC rigorosa per i metadati,
e separazione delle identità per prevenire correlazione.

---

## Vedi anche

- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) — Errori nella comunicazione anonima
- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) — Protocollo rendezvous per servizi nascosti
- [Isolamento e Compartimentazione](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) — Tails per comunicazione ad alto rischio
- [Fingerprinting](../05-sicurezza-operativa/fingerprinting.md) — Rischi di fingerprinting nelle comunicazioni
