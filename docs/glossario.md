> **Lingua / Language**: Italiano | [English](en/glossario.md)

# Glossario

Terminologia tecnica usata in questa guida, con definizioni specifiche al
contesto Tor e anonimato di rete.

---

| Termine | Definizione |
|---------|-------------|
| **AES-128-CTR** | Cifrario simmetrico usato da Tor per cifrare le celle nei circuiti. Counter mode, chiave 128 bit. |
| **AppArmor** | Framework di sicurezza Linux che confina i processi (incluso Tor) limitando l'accesso a file e risorse. |
| **AutomapHostsOnResolve** | Direttiva torrc che mappa hostname a IP fittizi per il transparent proxy. |
| **Bandwidth Authority** | Server che misura la bandwidth reale dei relay per il consenso (sbws). |
| **Bridge** | Relay Tor non elencato pubblicamente, usato per aggirare la censura. |
| **Cell (Cella)** | Unità di dati di Tor: 514 byte fissi (4B CircID + 1B Command + 509B Payload). |
| **CircID** | Identificatore di circuito (4 byte), diverso per ogni hop del circuito. |
| **Circuito** | Percorso di 3 relay (Guard → Middle → Exit) attraverso la rete Tor. |
| **Consenso** | Documento firmato dalle Directory Authorities con la lista di tutti i relay e le loro proprietà. |
| **ControlPort** | Porta TCP (default 9051) per controllare Tor programmaticamente. |
| **CookieAuthentication** | Metodo di autenticazione al ControlPort tramite file cookie. |
| **CREATE2/CREATED2** | Celle per la creazione di circuiti (handshake ntor). |
| **Curve25519** | Curva ellittica usata per il key exchange nel handshake ntor di Tor. |
| **Deanonimizzazione** | Processo di identificazione di un utente Tor, vanificando l'anonimato. |
| **Directory Authority (DA)** | Uno dei 9 server fidati che votano per creare il consenso della rete. |
| **DNSPort** | Porta UDP su cui Tor accetta query DNS e le risolve via circuito. |
| **DPI (Deep Packet Inspection)** | Tecnica di analisi del traffico che esamina il contenuto dei pacchetti. |
| **Ed25519** | Algoritmo di firma digitale usato da Tor per identity key e onion services v3. |
| **Exit Node** | L'ultimo relay del circuito, che si connette alla destinazione finale. |
| **Exit Policy** | Regole che definiscono quali destinazioni un exit node accetta. |
| **Fingerprint** | Hash SHA-1 della chiave pubblica di un relay (40 caratteri hex). |
| **First-Party Isolation (FPI)** | Isolamento per dominio di primo livello in Tor Browser (cookie, cache, etc.). |
| **Flag** | Proprietà assegnata a un relay nel consenso (Guard, Exit, Fast, Stable, HSDir, etc.). |
| **Guard Node** | Primo relay del circuito, scelto con persistenza (~2-3 mesi). Vede il tuo IP reale. |
| **HKDF** | Hash-based Key Derivation Function, usato per derivare le chiavi di sessione. |
| **HMAC-SHA256** | Message Authentication Code usato per verificare l'integrità delle celle. |
| **HSDir** | Relay responsabile di conservare i descriptor degli onion services. |
| **iat-mode** | Modalità di obfs4 per la resistenza all'analisi del timing inter-packet. |
| **Introduction Point** | Relay dove un onion service aspetta connessioni dai client. |
| **IsolateSOCKSAuth** | Flag SocksPort che isola circuiti in base alle credenziali SOCKS5. |
| **LD_PRELOAD** | Meccanismo Linux per caricare librerie prima di libc, usato da proxychains e torsocks. |
| **MaxCircuitDirtiness** | Tempo massimo (secondi) prima che un circuito venga chiuso e ricreato (default 600). |
| **meek** | Pluggable transport che usa domain fronting (CDN) per nascondere il traffico Tor. |
| **Middle Relay** | Secondo relay del circuito. Non vede né l'IP del client né la destinazione. |
| **NEWNYM** | Segnale ControlPort per cambiare identità (nuovi circuiti, nuovi exit IP). |
| **nftables** | Framework firewall moderno di Linux, successore di iptables. |
| **ntor** | Handshake crittografico di Tor basato su Curve25519 per creare circuiti. |
| **Nyx** | Monitor TUI per Tor (successore di `arm`). Visualizza circuiti, bandwidth, log. |
| **obfs4** | Pluggable transport che offusca il traffico Tor per resistere al DPI. |
| **Onion Service** | Servizio accessibile solo via Tor (indirizzo .onion), senza exit node. |
| **OONI** | Open Observatory of Network Interference - misura la censura Internet globale. |
| **OR Port** | Porta usata dai relay per comunicare tra loro (default 9001). |
| **Path Bias** | Meccanismo di Tor che rileva circuiti che falliscono troppo spesso (possibile attacco). |
| **Pluggable Transport (PT)** | Protocollo che trasforma il traffico Tor per evitare il rilevamento. |
| **proxychains** | Wrapper LD_PRELOAD che forza le applicazioni a usare un proxy SOCKS/HTTP. |
| **RELAY_BEGIN** | Cella relay che apre uno stream verso una destinazione. |
| **RELAY_DATA** | Cella relay che trasporta dati applicativi. |
| **RELAY_RESOLVE** | Cella relay per risolvere DNS via circuito Tor. |
| **Rendezvous Point** | Relay dove client e onion service si incontrano per comunicare. |
| **SENDME** | Cella per il flow control di Tor (conferma ricezione, previene congestione). |
| **SessionGroup** | Meccanismo per raggruppare stream in gruppi di isolamento su SocksPort. |
| **Snowflake** | Pluggable transport basato su WebRTC, usa browser di volontari come proxy. |
| **SO_ORIGINAL_DST** | Socket option Linux per recuperare la destinazione originale dopo REDIRECT iptables. |
| **SocksPort** | Porta su cui Tor accetta connessioni SOCKS5 dalle applicazioni (default 9050). |
| **Stem** | Libreria Python per controllare Tor via ControlPort. |
| **Stream** | Connessione TCP individuale all'interno di un circuito Tor. |
| **Stream Isolation** | Separazione degli stream in circuiti diversi per prevenire correlazione. |
| **Stylometry** | Analisi dello stile di scrittura per deanonimizzare l'autore di un testo. |
| **Sybil Attack** | Attacco dove un avversario controlla molti relay per dominare la rete. |
| **torsocks** | Wrapper LD_PRELOAD specifico per Tor, blocca attivamente UDP. |
| **TransPort** | Porta di Tor per il transparent proxy (accetta TCP nativo, non SOCKS). |
| **Vanguards** | Sistema di relay persistenti multi-livello per proteggere gli onion services. |
| **VirtualAddrNetwork** | Range IP fittizio usato da AutomapHosts per mappare hostname (default 10.192.0.0/10). |
| **Website Fingerprinting** | Attacco che identifica quali siti un utente Tor sta visitando analizzando i pattern di traffico. |
