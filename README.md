# Tor Networking Guide 🧅

Documentazione completa sull’utilizzo di Tor, gestione dei bridge, rotazione dell’IP, controlli del proprio indirizzo pubblico, configurazione di script, gestione delle sessioni e considerazioni sulla privacy e legalità.

Questo progetto raccoglie in un’unica guida tutto il lavoro tecnico e le configurazioni realizzate durante lo studio della rete Tor e delle sue funzionalità in un ambiente di sviluppo Kali Linux (Debian).

---

## Indice

- [Introduzione](#introduzione)
- [Obiettivi del progetto](#obiettivi-del-progetto)
- [Come funziona Tor](#come-funziona-tor)
- [Bridge e Obfs4](#bridge-e-obfs4)
- [Controllo del proprio IP pubblico](#controllo-del-proprio-ip-pubblico)
- [Rotazione IP / SIGNAL NEWNYM](#rotazione-ip--signal-newnym)
- [Compatibilità delle configurazioni](#compatibilità-delle-configurazioni)
- [Sicurezza, fingerprinting e tracciamento](#sicurezza-fingerprinting-e-tracciamento)
- [Legalità](#legalità)
- [Script utili](#script-utili)

---

## Introduzione

La rete Tor (The Onion Router) permette di ottenere anonimato e privacy grazie a un’architettura distribuita e basata sul concetto di onion routing.  
Questa guida è pensata per:

- utenti che vogliono capire come funziona Tor  
- sviluppatori che desiderano utilizzare Tor da CLI  
- chi vuole evitare censura e blocchi tramite bridge  
- chi vuole gestire rotazioni IP o circuiti multipli  
- chi vuole ridurre fingerprinting e leak  

---

## Obiettivi del progetto

- fornire una documentazione chiara e completa sull’uso avanzato di Tor  
- spiegare configurazioni del file `torrc`  
- mostrare come verificare l’IP pubblico tramite Tor  
- automatizzare la rotazione IP tramite il ControlPort  
- chiarire limiti, rischi e considerazioni legali  

---

## Come funziona Tor

Tor costruisce un circuito a 3 nodi:

1. **Guard Node**  
   - vede il tuo IP  
   - non vede la destinazione  

2. **Middle Node**  
   - nodo di transito  
   - non vede né origine né destinazione  

3. **Exit Node**  
   - vede la destinazione  
   - non conosce l’IP reale del client  

Ogni hop è cifrato a strati (onion routing), quindi ogni nodo conosce solo quello immediatamente precedente e successivo.

---

## Bridge e Obfs4

I bridge sono nodi Tor non pubblici, utili per:

- aggirare censura e DPI  
- evitare che l’ISP sappia che stai usando Tor  
- ridurre fingerprinting sul nodo di ingresso  

Il trasporto **obfs4** (Obfuscation v4) offusca completamente il traffico Tor rendendolo indistinguibile dal rumore.

### Vantaggi di obfs4:

- resistente a DPI avanzata  
- non permette fingerprinting per riconoscere Tor  
- non rivela il nodo di ingresso pubblico  
- funziona anche su reti restrittive  

---

## Controllo del proprio IP pubblico

### Senza Tor:
```bash
curl https://api.ipify.org
```

### Con Tor:
```bash
curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
```

### Con proxychains:
```bash
proxychains curl https://api.ipify.org
```

---

## Rotazione IP / SIGNAL NEWNYM

Puoi cambiare IP di uscita chiedendo a Tor un nuovo circuito:
```bash
echo -e 'AUTHENTICATE ""\nSIGNAL NEWNYM\nQUIT' | nc 127.0.0.1 9051
```
Richiede:

- ControlPort 9051 attivo
- CookieAuthentication 1 nel torrc

Il cambio non è immediato: Tor impone un tempo minimo tra due richieste NEWNYM.

---

## Compatibilità delle configurazioni

Tor non è una VPN.
Funziona solo su connessioni TCP, non UDP.

Problemi comuni:

- alcune app ignorano il proxy SOCKS
- DNS leak se non configurato `DNSPort`
- IPv6 leak se non disabilitato
- traffico locale che bypassa il circuito

Tor Browser minimizza fingerprinting, CLI no.

---

## Sicurezza, fingerprinting e tracciamento

- l’ISP non vede i siti visitati
- i siti vedono solo l’exit node
- fingerprinting HTTP rimane possibile
- JavaScript, WebGL, canvas e font possono rivelare identità
- le richieste Tor CLI hanno fingerprint diverso da Tor Browser

Per massima privacy: usare sempre Tor Browser.

---

## Legalità

In Italia, usare Tor è legale

Non è legale:
- violare sistemi
- aggirare login non autorizzati
- compiere azioni criminali tramite Tor

Le configurazioni tecniche descritte servono per studio, sicurezza e anonimato legittimo.

---

## Script utili

### Controllo IP via Tor:
```bash
#!/bin/bash
curl --socks5-hostname 127.0.0.1:9050 https://api.ipify.org
```

### Rotazione IP (NEWNYM):
```bash
#!/bin/bash
echo -e 'AUTHENTICATE ""\nSIGNAL NEWNYM\nQUIT' | nc 127.0.0.1 9051
```

Rendi eseguibile:
```bash
chmod +x newnym.sh
```

### comando per avviare Tor:
```bash
firefox -no-remote -CreateProfile tor-proxy             # questo crea un profilo Firefox dedicato a Tor ed evita crash e conflitti con il profilo normale
proxychains firefox -no-remote -P tor-proxy & disown    # questo forza Firefox a usare Tor, DNS attraverso Tor, e niente conflitti con sessioni esistenti
```
si potrebbe anche usare:
```bash
nohup proxychains firefox -no-remote -P tor-proxy >/dev/null 2>&1 &     # usato per processi permanenti, se vuoi che continui anche dopo logout
```

