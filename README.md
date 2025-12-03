# Tor Networking Guide 🧅  
Documentazione completa sull’utilizzo di Tor, gestione dei bridge, rotazione dell’IP, controlli del proprio indirizzo pubblico, configurazione di script, gestione delle sessioni e considerazioni sulla privacy e legalità.

Questo progetto nasce per raccogliere in un’unica guida tutto il lavoro tecnico e le configurazioni realizzate durante lo studio della rete Tor e delle sue funzionalità in un ambiente di svilluppo Kali Linux (Debian).

---

## Indice

- [Introduzione](#introduzione)  
- [Obiettivi del progetto](#obiettivi-del-progetto)  
- [Come funziona Tor (breve versione)](#come-funziona-tor-breve-versione)  
- [Bridge e Obfs4](#bridge-e-obfs4)  
- [Controllo del proprio IP pubblico](#controllo-del-proprio-ip-pubblico)  
- [Rotazione IP / SIGNAL NEWNYM](#rotazione-ip--signal-newnym)  
- [Compatibilità delle configurazioni](#compatibilità-delle-configurazioni)  
- [Sicurezza, fingerprinting e tracciamento](#sicurezza-fingerprinting-e-tracciamento)  
- [Legalità](#legalità)  
- [Struttura della repository](#struttura-della-repository)  
- [Licenza](#licenza)

---

## Introduzione

La rete Tor è progettata per offrire anonimato, privacy e resistenza alla censura.  
Questa guida documenta:

- come configurare Tor lato sistema operativo  
- come utilizzare proxy SOCKS5 con applicazioni CLI (curl, proxychains)  
- come cambiare identità tramite il ControlPort  
- come funzionano le autenticazioni dei siti quando si cambia IP  
- come ottenere bridge alternative quando quelli ufficiali non funzionano  
- considerazioni legali e di sicurezza  

---

## Obiettivi del progetto

- creare una documentazione chiara e completa sull’uso avanzato di Tor  
- fornire esempi di configurazione `torrc`  
- includere script per automatizzare alcune operazioni (es. rotazione IP)  
- chiarire limiti, rischi e best practice  

---

## Come funziona Tor (breve versione)

Tor crea un circuito a 3 nodi:

1. **Guard Node** – vede il tuo IP ma non il traffico finale  
2. **Middle Node** – nodo intermedio  
3. **Exit Node** – esce su Internet ma non conosce il tuo IP

Ogni hop è cifrato a strati ("onion routing").

---

## Bridge e Obfs4

I bridge servono per:

- aggirare censura e blocchi
- evitare che l’ISP sappia che usi Tor
- evitare fingerprinting diretto del nodo di ingresso

`obfs4` è il trasporto offuscato più stabile.

---

## Controllo del proprio IP pubblico

Senza Tor:

```bash
curl https://api.ipify.org
