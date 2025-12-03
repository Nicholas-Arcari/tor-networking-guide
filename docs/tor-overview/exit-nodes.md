# Exit Nodes

Questo documento descrive cosa sono i **nodi di uscita Tor**, perché sono
fondamentali, quali rischi comportano, quali policy seguono e soprattutto come
verificare l’indirizzo IP con cui esci realmente su Internet quando usi Tor
(diretto o tramite proxychains).  
Include anche note pratiche basate sulla mia esperienza d’uso reale.

---

## Cosa sono gli Exit Nodes?

Un **Exit Node** è l’ultimo nodo del circuito Tor:  
il server dal quale il traffico esce verso Internet “normale”.

Il circuito Tor tipicamente è: [Client] → [Guard Node] → [Middle Node] → [Exit Node] → Internet


Quindi l’Exit Node è il punto in cui:

- il traffico esce dal circuito Tor,
- viene instradato verso la destinazione finale,
- **l’IP pubblico visibile dal sito è quello dell’Exit Node**, non il tuo.

---

## Perché esistono?

Ogni nodo Tor svolge un ruolo specifico:

| Tipo di nodo | Ruolo |
|--------------|-------|
| Guard/Entry  | Ingresso al circuito, conosce solo te ma non la destinazione |
| Middle       | Rimbalzo intermedio, non conosce né te né la destinazione |
| Exit Node    | Esce su Internet, conosce la destinazione ma non chi sei |

Gli Exit Node permettono la separazione tra:

- **identità (tu)** → conosciuta solo dall’entry  
- **destinazione (sito finale)** → conosciuta solo dall’exit  

Questa separazione è la base dell’anonimato.

---

## Rischi degli Exit Nodes

Poiché l’Exit Node “esce su Internet”, **il traffico NON è cifrato dopo
l’uscita**, a meno che:

- il sito usi HTTPS
- si usi un protocollo cifrato (SSH, TLS, ecc.)

### Possibili rischi:

#### **1. Sniffing del traffico non cifrato**
Un exit malevolo può:

- leggere password HTTP,
- vedere richieste in chiaro,
- identificare query non cifrate,
- intercettare protocolli vulnerabili.

> Questo non tocca il tuo IP, ma la tua privacy sui contenuti.

#### **2. Manipolazione del traffico non cifrato**
Un exit può:

- modificare pagine HTTP,
- inserire payload,
- fare MITM se non controlli certificati TLS.

#### **3. Blocking / captchas**
Gli exit sono spesso abusati → molti siti:

- li bloccano,
- richiedono CAPTCHA,
- limitano funzionalità.

#### **4. Illegale?**
No: **usare exit nodes non è illegale**, ma…

- ciò che fai *tramite* gli exit node può esserlo,
- l'exit node stesso può essere monitorato,
- siti possono loggare le richieste provenienti da Tor.

---

## Exit Policy

Ogni Exit Node definisce una **Exit Policy**, cioè quali porte possono essere
usate per uscire.

Esempi:

- alcuni permettono solo `:80` e `:443`
- altri bloccano SMTP (`:25`)
- alcuni sono "reject *:*" → non sono exit veri, ma relay

La policy si trova nel consenso Tor e decide:

- quali protocolli puoi usare,
- la probabilità di errori tipo "Connection refused".

---

## Perché i siti vedono un IP diverso dal tuo?

Perché l’IP visibile è quello dell’**Exit Node**.

Esempio:
```bash
>curl https://api.ipify.org
81.30.xx.xx (tuo IP reale)

> proxychains curl https://api.ipify.org
45.84.xx.xx (Exit Node Tor)
```

Nella mia esperienza:

- ogni circuito Tor ha un exit diverso,
- usando `NEWNYM` puoi forzare il cambio di exit,
- non tutti gli exit cambiano immediatamente (dipende da Tor).

---

## Come verificare l’IP dell’Exit Node

### **1. Metodo semplice**

```bash
proxychains curl https://api.ipify.org
```
oppure
```bash
proxychains curl https://check.torproject.org/api/ip
```

### **2. Controllo Dettagliato**
```bash
proxychains curl https://ipinfo.io
```
otterrai:
```bash
{
  "ip": "45.84.xx.xx",
  "city": "Amsterdam",
  "country": "NL",
  "org": "ASxxxx Tor Exit Router"
}
```