# Configurazione Ibrida Tor

Questo documento discute i **limiti dell’uso di Tor come VPN**, perché Tor non
è progettato per funzionare come un servizio VPN tradizionale, quali potrebbero
essere delle configurazioni “ibride”, e quali compromessi comportano.  
Include considerazioni basate sulla mia esperienza pratica (richiesta bridge,
configurazioni SOCKS, test tramite proxychains, problemi con exit node, e
tentativi di usare Tor come se fosse un “tunnel VPN globale”).

---

## Perché Tor **non** è una VPN

### Obiettivo di Tor:

- **Anonimato**
- **Separazione tra identità e destinazione**
- **Distribuzione su tre nodi per minimizzare correlazioni**
- **Resistenza alla censura (bridge, obfs4)**

### Obiettivo di una VPN:

- **Spostare il tuo traffico su un singolo server fidato**
- **Cambiare l'IP pubblico con quello del server VPN**
- **Cifrare tutto il traffico fin dal kernel (L3/L4)**
- **Comportarsi come una interfaccia di rete (TUN/TAP)**

Tor invece:

- Non crea un’interfaccia di rete
- Non opera come tunnel L3/L4 ma come proxy SOCKS5
- Non supporta UDP (eccetto DNS tramite Tor DNSPort)
- Bilancia il traffico su circuiti differenti → impossibile avere “un solo IP”
- Non è pensato per traffico persistente o real-time

- **Tor != VPN**  
E non può diventarlo senza violare i suoi principi di design.

---

## Problemi del "Tor come VPN"

### 1. **Assenza di un tunnel di livello IP**

Con una VPN puoi fare:

- `tun0`
- routing tramite `ip route`
- firewall per tun interface
- DNS forzato

Con Tor:

- Hai un proxy SOCKS su `127.0.0.1:9050`
- Non puoi fare `route add default dev tor`
- Il kernel non “vede” il traffico Tor

### 2. **Il traffico non passa tutto automaticamente**

Senza proxy (es. browser non configurati, ping, NTP, aggiornamenti di sistema)
→ **escono con il tuo IP reale**.

Esporre servizi di sistema fuori dal tunnel è il principale motivo del design:
Tor è pensato per traffico applicativo, **non di sistema**.

### 3. **Circuiti multipli con IP diversi**

Con una VPN, il tuo IP è sempre uno.  
Con Tor:

- ogni flusso può usare un circuito diverso
- ogni circuito ha un exit diverso
- NEWNYM rigenera tutto ogni ~10 minuti

### 4. **UDP non supportato**

Quindi:

- videogiochi online → impossibile
- call VoIP → pessime o non funzionanti
- DNS UDP → bloccato (usa DNSPort 5353 ma non è universale)

---

## La mia esperienza: perché un sistema ibrido sembra utile

Durante la configurazione reale:

- ho installato Tor su Kali
- ho abilitato bridge + obfs4 per aggirare blocchi geografici  
  (richiesti tramite **bridges.torproject.org**)
- ho verificato l’IP con `proxychains curl`
- ho tentato configurazioni globali stile VPN, tipo:
  - instradare tutto via proxychains
  - usare `torsocks` come wrapper globale
  - provare a creare routing via `TransPort` + iptables

Era evidente che **un comportamento da VPN non si ottiene mai al 100%**.

Da qui nasce l’idea di una **configurazione ibrida**.

---

## Cos’è una configurazione ibrida Tor?

Una “configurazione ibrida” è una combinazione di:

- Tor (per anonimato e resistenza alla censura)
- strumenti di sistema (proxy, iptables, DNS isolato)
- eventuale VPN (prima o dopo Tor)

Esempi comuni:

### **1. VPN → Tor (Onion over VPN)**

Tu → VPN → Tor → Internet

**Pro**

- ISP vede solo VPN
- Puoi accedere alla rete Tor anche se bloccata
- Exit Node non vede la tua home IP

**Contro**

- VPN vede il tuo IP reale
- più lento
- non aumenta anonimato, solo aggira censura

### **2. Tor → VPN (Tor over VPN)**

Tu → Tor → VPN → Internet  
(Molto raro, quasi sempre sconsigliato)

**Pro**

- puoi uscire con IP della VPN

**Contro**

- **rompe completamente l’anonimato Tor**
- la VPN diventa l'unico exit → fingerprint altissimo
- alcuni protocolli non funzionano

### **3. Tor + Transparent Proxy (iptables + TransPort)**

Instradi tutto il traffico TCP dentro Tor: iptables → TransPort → Tor → Internet

**Pro**

- effetto quasi-VPN
- il traffico non passa più accidentalmente fuori

**Contro**

- UDP non supportato
- se Tor crolla → freeze della rete
- molto fragile

### **4. Applicazioni mirate (soluzione “ibrida minima”)**

- browser → Tor
- terminale → proxychains
- aggiornamenti → VPN
- app sensibili → rete normale

Questa soluzione è quella più bilanciata nella pratica.

---

## Perché “ibrido + migrazione IP da altri paesi” è problematico

Quando hai provato a “migrare” l’origine del traffico usando:

- ExitNodes {paese}
- StrictNodes 1

…il problema era:

### **1. Riduci enormemente il set di exit disponibili**

Tor funziona sulla randomizzazione → se la togli:

- rischi circuiti saturi
- latenza enorme
- fingerprinting

### **2. Non puoi mantenere _lo stesso_ exit nel tempo**

Tor ricrea circuiti ciclicamente → l’IP cambia comunque.

### **3. Gli exit dei paesi piccoli sono pochissimi**

Se scegli paesi non comuni →  
non c’è abbastanza banda disponibile.

---

## Compromessi di ciascun approccio

| Configurazione           | Sicurezza  | Anonimato  | Velocità | Affidabilità |
| ------------------------ | ---------- | ---------- | -------- | ------------ |
| Tor standard             | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐       | ⭐⭐⭐       |
| VPN                      | ⭐⭐⭐     | ⭐         | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐   |
| VPN → Tor                | ⭐⭐⭐⭐   | ⭐⭐       | ⭐⭐     | ⭐⭐⭐       |
| Tor → VPN                | ⭐         | ⭐         | ⭐⭐     | ⭐           |
| Tor TransPort + iptables | ⭐⭐⭐     | ⭐⭐⭐     | ⭐       | ⭐           |
| Uso mirato app-by-app    | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐   | ⭐⭐⭐   | ⭐⭐⭐⭐     |

---

## Quindi qual è la soluzione ibrida “migliore”?

### **La soluzione più stabile e sicura è questa:**

1. **Tor configurato bene**

   - SOCKSPort 9050
   - ControlPort 9051
   - obfs4 se serve censura
   - bridge richiesti dal sito ufficiale

2. **VPN per traffico non anonimo**

   - update
   - download pesanti
   - streaming

3. **Routing selettivo**
   - Tor per browser anonimi
   - proxychains per CLI sensibili
   - rete normale per servizi di sistema
   - VPN per operazioni ad alta banda

### È la configurazione ibrida naturale ed efficiente:

- non rompe Tor
- non sovraccarica proxychains
- mantiene un buon equilibrio
- evita leak
- è praticabile ogni giorno

---

## Conclusione

Tor non può funzionare come una VPN, ma può essere integrato in una **strategia
ibrida** che massimizza privacy e sicurezza senza sacrificare usabilità.

Le soluzioni ibride devono essere pensate con attenzione perché:

- Tor non supporta UDP
- Tor non è progettato per routing globale
- l’anonimato si riduce se si forza la geolocalizzazione
- più livelli non significano sempre più sicurezza

La configurazione ibrida ideale resta:

**Tor per anonimato**  
**VPN per traffico normale**  
**Proxy, browser e firewall configurati su misura**

Un sistema equilibrato, flessibile e molto più robusto nella realtà di tutti i
giorni.
