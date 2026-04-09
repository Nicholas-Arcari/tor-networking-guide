# Analisi Forense - Browser, Mitigazione e Strumenti

Artefatti del browser (Firefox, Tor Browser), tracce di proxychains e torsocks,
timeline forense di una sessione Tor, mitigazione a 4 livelli (configurazione,
pulizia, tmpfs, sistema amnestico) e strumenti di analisi.

> **Estratto da**: [Analisi Forense e Artefatti Tor](analisi-forense-e-artefatti.md)
> per artefatti su disco, log, RAM e rete.

---


### Firefox profilo tor-proxy

```
~/.mozilla/firefox/xxxxxxxx.tor-proxy/
├── places.sqlite          ← History e bookmark (se non cancellati)
├── cookies.sqlite         ← Cookie
├── formhistory.sqlite     ← Dati form compilati
├── webappsstore.sqlite    ← localStorage
├── cache2/               ← Cache HTTP
├── sessionstore.jsonlz4   ← Tab aperti (session restore)
├── prefs.js              ← Impostazioni (rivela proxy config)
├── cert9.db              ← Certificati salvati
└── logins.json           ← Password salvate (se non vuoto)
```

**prefs.js** è particolarmente informativo:

```javascript
// rivela la configurazione proxy:
user_pref("network.proxy.socks", "127.0.0.1");
user_pref("network.proxy.socks_port", 9050);
user_pref("network.proxy.socks_remote_dns", true);
// ↑ Conferma uso di Tor come proxy SOCKS5
```

### Download directory

```bash
# File scaricati via Tor Browser o Firefox tor-proxy
ls -la ~/Downloads/
# I metadati dei file (creation time, source URL) possono essere preservati
```

### Tor Browser download evidence

```bash
# La directory di Tor Browser stessa
ls ~/tor-browser/
# La sua sola esistenza è evidenza
# La data di creazione indica quando è stato installato
stat ~/tor-browser/start-tor-browser
```

---

## Artefatti di proxychains e torsocks

### proxychains

```
/etc/proxychains4.conf
  ↑ Configurazione con proxy Tor (socks5 127.0.0.1 9050)
  ↑ Rivela uso di proxychains per torificare applicazioni

~/.proxychains/proxychains.conf
  ↑ Config utente (se presente)
```

L'output di proxychains (se non soppresso) viene scritto su stderr:
```
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
```

Se catturato in un file di log → evidenza di uso.

### torsocks

```
/etc/tor/torsocks.conf
  ↑ Configurazione torsocks

# Log torsocks (se loggato su file)
/var/log/torsocks.log  ← se TORSOCKS_LOG_FILE_PATH è configurato
```

### Shell history

```bash
# ~/.bash_history o ~/.zsh_history
proxychains curl https://target-site.com
torsocks ssh user@hidden-server.com
nyx
~/scripts/newnym
# ↑ Ogni comando con proxychains/torsocks/nyx nella history
```

**Mitigazione**: `HISTFILE=/dev/null` o `unset HISTFILE` prima della sessione.

---

## Timeline forense di una sessione Tor

Un analista ricostruisce la timeline da più fonti:

```
09:20:00  apt history: "apt install tor obfs4proxy nyx"
          ↑ Installazione pacchetti Tor

09:22:00  /etc/tor/torrc: mtime = 09:22:00
          ↑ Configurazione torrc modificata

09:23:01  journalctl: "Starting Tor..."
09:23:41  journalctl: "Bootstrapped 100% (done)"
          ↑ Tor avviato e connesso

09:23:45  /var/lib/tor/state: "LastWritten 09:23:45"
          ↑ File state aggiornato

09:25:00  ss -tnp: connessione a 198.51.100.42:9001
          ↑ Connessione al guard node

09:30:00  .bash_history: "proxychains curl https://target.com"
          ↑ Comando eseguito via Tor

14:32:15  journalctl: "NEWNYM command received"
          ↑ Cambio identità

14:32:20  /var/lib/tor/state: Guard changed
          ↑ Nuovo circuito costruito

18:00:00  journalctl: "Tor daemon shutting down"
          ↑ Chiusura Tor
```

---

## Mitigazione degli artefatti

### Livello 1: Configurazione base

```ini
# torrc - minimizzare logging
Log notice file /var/log/tor/notices.log
# NON usare debug o info

# Oppure: log solo su stdout (non su file)
Log notice stdout
```

```bash
# Disabilitare shell history per la sessione
unset HISTFILE
# oppure
export HISTFILE=/dev/null
```

### Livello 2: Pulizia post-sessione

```bash
# Cancellare artefatti Tor
sudo systemctl stop tor@default.service
sudo rm -rf /var/lib/tor/cached-*
sudo rm -f /var/log/tor/*
# NON cancellare /var/lib/tor/state se vuoi mantenere il guard

# Cancellare artefatti browser
rm -rf ~/.mozilla/firefox/*.tor-proxy/cache2/
rm -f ~/.mozilla/firefox/*.tor-proxy/places.sqlite
rm -f ~/.mozilla/firefox/*.tor-proxy/cookies.sqlite

# Cancellare history
rm -f ~/.bash_history ~/.zsh_history
```

### Livello 3: tmpfs e RAM-only

```bash
# Montare DataDirectory di Tor in tmpfs
# /etc/fstab:
tmpfs /var/lib/tor tmpfs defaults,noatime,size=256M 0 0

# Effetto: tutto il state di Tor è in RAM
# Al reboot: tutto cancellato automaticamente
# Svantaggio: guard cambia ad ogni reboot (bad for security)
```

### Livello 4: Sistema amnestico

**Tails**: l'intero sistema operativo gira in RAM. Al shutdown, zero artefatti
su disco. È la soluzione definitiva per zero-evidence.

**Whonix**: non amnestico per default, ma la Workstation può usare tmpfs
per le directory sensibili.

---

## Strumenti di analisi forense

### Per un analista che cerca artefatti Tor

| Strumento | Uso |
|-----------|-----|
| `strings` | Cercare stringhe Tor in file/RAM dump |
| `find / -name "*tor*"` | Cercare file correlati a Tor |
| `grep -r "9050\|9051\|SocksPort" /etc/` | Cercare configurazioni proxy |
| `journalctl -u tor*` | Log del servizio Tor |
| `sqlite3 places.sqlite` | Analizzare history Firefox |
| `volatility` | Analisi dump RAM |
| `autopsy/sleuthkit` | Analisi disco |
| `log2timeline` | Ricostruzione timeline |

### Query forensi specifiche

```bash
# Cercare evidenza di Tor su disco
find / -name "torrc" -o -name "torsocks.conf" -o -name "proxychains*.conf" 2>/dev/null

# Cercare nella history dei comandi
grep -r "proxychains\|torsocks\|tor-browser\|newnym\|nyx" /home/*/.*history 2>/dev/null

# Cercare processi Tor in esecuzione
ps aux | grep -i tor

# Cercare connessioni a porte Tor
ss -tnp | grep -E ":(9050|9051|9001|9040) "

# Cercare pacchetti Tor installati
dpkg -l | grep -iE "^ii.*(tor |torsocks|obfs4|nyx|proxychains)"
```

---

## Nella mia esperienza

Studiare gli artefatti forensi di Tor è stato fondamentale per capire il mio
livello di esposizione. Ho fatto un esercizio pratico: dopo una sessione Tor
sul mio Kali, ho cercato sistematicamente tutti gli artefatti che un analista
avrebbe trovato.

**Quello che ho trovato**:
- `/var/lib/tor/state` con il fingerprint del mio guard e timestamp dell'ultimo uso
- `journalctl` con timestamp precisi di ogni avvio, NEWNYM, e shutdown di Tor
- `.zsh_history` piena di comandi `proxychains curl ...` e `nyx`
- `prefs.js` del profilo tor-proxy con la configurazione SOCKS5
- `torrc` con i bridge obfs4 configurati
- Output di `dpkg -l` che mostra chiaramente tor, obfs4proxy, nyx, torsocks, proxychains

**Quello che ho mitigato**:
- Shell history: ora uso `HISTFILE=/dev/null` durante sessioni sensibili
- Log retention: ridotto a 1 settimana in journald.conf
- Browser: cancello la cache del profilo tor-proxy periodicamente

**Quello che non ho mitigato** (accettato come rischio):
- I pacchetti installati sono visibili (non mi preoccupa, uso Tor legalmente)
- Il torrc con i bridge è su disco (potrei cifrare la partizione)
- Il file state di Tor esiste (necessario per mantenere il guard)

Per uno scenario dove l'evidenza di uso di Tor è un problema (giornalisti in
paesi ostili, attivisti), la risposta è Tails: nessun artefatto su disco, tutto
in RAM, shutdown = cancellazione totale.

---

## Vedi anche

- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - Errori che lasciano tracce forensi
- [Hardening di Sistema](hardening-sistema.md) - Ridurre la superficie forense con sysctl e AppArmor
- [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) - Tails, Whonix, Qubes per amnesia
- [DNS Leak](dns-leak.md) - Artefatti DNS nei log di sistema
- [Tor Browser e Applicazioni](../04-strumenti-operativi/tor-browser-e-applicazioni.md) - Artefatti browser
