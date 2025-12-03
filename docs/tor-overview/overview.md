# Tor Overview

Questo documento fornisce una panoramica approfondita del funzionamento di Tor,
dei suoi componenti principali, dei circuiti, dei nodi e degli obiettivi di anonimato.
Include anche note pratiche legate alla mia esperienza reale nell’uso di Tor tramite
CLI, proxychains, bridge e controllo del circuito tramite ControlPort.

---

## Cos’è Tor?

Tor (The Onion Router) è una rete di instradamento anonimo progettata per:

- proteggere identità e posizione dell’utente,
- impedire la correlazione tra l’origine e la destinazione del traffico,
- resistere alla censura,
- distribuire il trust tra migliaia di nodi volontari.

Funziona costruendo **circuiti multi-hop** e applicando **strati di crittografia a cipolla**.

---

## Architettura di Tor

Tor è composto da diversi tipi di nodi e componenti:

### Onion Proxies (client)
Sono i software installati dall’utente, come:

- `tor` (daemon su Linux)
- Tor Browser
- applicazioni che instradano traffico tramite SOCKS5 verso Tor

Il mio utilizzo è stato principalmente:

- `proxychains`
- `curl` via Tor
- `firefox -P tor-proxy`
- Tor controllato con ControlPort tramite script `newnym`

### Directory Authorities
Server centrali che mantengono:

- stato della rete,
- elenco di relay attivi,
- informazioni di consenso.

Non sono punti di controllo dell’utente: servono solo per verificare lo stato dei nodi.

### Relay (nodi Tor)
Tre tipi principali:

1. **Guard / Entry Node**  
   Primo nodo del circuito.  
   Conosce SOLO che ci siamo noi, non la destinazione.

2. **Middle Relay**  
   Nodo intermedio, non conosce né l’origine né la destinazione.

3. **Exit Node**  
   Ultimo nodo che esce su Internet.  
   Conosce la destinazione ma non l’origine.

Nella mia esperienza:

- l’uscita può essere facilmente verificata con `proxychains curl https://api.ipify.org`
- gli IP cambiano dopo comando `NEWNYM` (se il circuito è aggiornabile)

---

## Come funziona un circuito Tor

Quando un’applicazione invia traffico tramite SOCKS5 verso Tor, il daemon costruisce
un circuito di **3 nodi**:

1. **Entry (Guard)**
2. **Middle**
3. **Exit**

Ogni hop aggiunge o rimuove uno *strato* di crittografia:

🔒 **Strato 1:** Exit → Middle → Entry  
🔒 **Strato 2:** Middle → Entry  
🔒 **Strato 3:** Entry

Solo l’Exit vede il traffico in chiaro (se non è HTTPS).

---

## Obiettivi di anonimato

Tor garantisce:

### Anonimato dell’IP
Il sito che visito vede solo l’IP dell’Exit Node.

### Resistenza alla sorveglianza
Chi osserva il mio ISP vede solo traffico cifrato verso l’Entry Node.

### Sovranità dell’utente
Nessun’entità singola vede origine e destinazione simultaneamente.

### Decentramento
Tor si basa su volontari, non su server centrali proprietari.

---

## Bridge e aggiramento della censura

Nella mia esperienza:

- l’URL ufficiale per richiedere bridge (`https://bridges.torproject.org/bridges`) può essere offuscato o bloccato,
- l’email non sempre è comoda da usare,
- i bridge obfs4 vanno inseriti a mano nel file `torrc`.

Esempio:

```ini
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
Bridge obfs4 <IP>:<PORT> <FINGERPRINT> cert=<CERT> iat-mode=1
