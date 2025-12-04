# Tor & Localhost - Perché Tor Browser non può accedere a localhost

Questo documento spiega in modo chiaro perché Tor Browser non può accedere a servizi locali (come applicazioni Docker su localhost:5173), quali rischi vengono evitati, e quali sono le soluzioni possibili.

È basato sull’esperienza reale incontrata durante il debug di un'applicazione web dockerizzata restful api in esecuzione su Kali Linux.

---

## Problema Riscontrato

Tentando di aprire una webapp Docker (porta 5173) tramite Tor Browser, il browser mostra:

```bash
Unable to connect

Firefox can’t establish a connection to the server at localhost:5173.
```

Questo accade anche se Docker funziona perfettamente e la porta è esposta correttamente:

```bash
ports:
  - 5173:5173
```

Da un browser normale, l’applicazione funziona:
```bash
http://localhost:5173
```

Ma Tor Browser rifiuta ogni connessione verso localhost

---

## Perché Tor Browser blocca le connessioni a localhost?

Il motivo è una misura di sicurezza obbligatoria, progettata dal Tor Project per prevenire attacchi molto pericolosi:

### Un sito web potrebbe interrogare i tuoi servizi locali

Se Tor permettesse l’accesso a 127.0.0.1, un sito potrebbe inserire:
```bash
<img src="http://127.0.0.1:5173/admin">
```
per verificare:

- se hai Docker
- quali servizi locali hai attivi
- se usi specifici framework (Laravel, Vite, phpMyAdmin, ecc.)
- vulnerabilità locali

Questo tipo di attacco è chiamato Local Service Discovery Attack

### Potrebbe rivelare la tua identità

Interagire con servizi locali bypassa completamente la rete Tor e potrebbe:

- esporre il tuo vero IP
- esporre dati a livello locale
- rivelare informazioni sull’hardware → fingerprinting

### Protezione contro attacchi di deanonymization

Molti attacchi (XS-Leaks, timing leaks) funzionano proprio analizzando la risposta dei servizi locali

---

## Impostazione di sicurezza specifica

Tor Browser, rispetto a Firefox normale, impone:
```bash
network.proxy.allow_hijacking_localhost = false
```

Questo impedisce dirottamenti per evitare che un sito web possa aprire connessioni nella tua rete locale

---

## Se si volesse davvero accedere a localhost da Tor Browser

È possibile, ma fortemente sconsigliato dal Tor Project.

Apri su Firefox:
```bash
about:config
```

Cerca:
```bash
network.proxy.allow_hijacking_localhost
```

Impostalo a "true", attenzione perchè verrà persa una parte di anonimato
