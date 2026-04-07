# Lab 04 — Creare e Testare un Onion Service v3

Esercizio pratico per configurare un Onion Service v3, verificarne il
funzionamento, implementare autenticazione client, e comprendere la struttura
delle chiavi crittografiche.

**Tempo stimato**: 35-45 minuti
**Prerequisiti**: Lab 01 completato, accesso root, web server (nginx o python3)
**Difficoltà**: Intermedio-Avanzato

---

## Indice

- [Obiettivi](#obiettivi)
- [Fase 1: Web server locale](#fase-1-web-server-locale)
- [Fase 2: Configurazione Onion Service](#fase-2-configurazione-onion-service)
- [Fase 3: Verifica e connessione](#fase-3-verifica-e-connessione)
- [Fase 4: Struttura delle chiavi](#fase-4-struttura-delle-chiavi)
- [Fase 5: Autenticazione client](#fase-5-autenticazione-client)
- [Fase 6: Vanity address (opzionale)](#fase-6-vanity-address-opzionale)
- [Fase 7: Hardening del servizio](#fase-7-hardening-del-servizio)
- [Checklist finale](#checklist-finale)

---

## Obiettivi

Al termine di questo lab, avrai:
1. Un Onion Service v3 funzionante con indirizzo `.onion`
2. Compreso la struttura delle chiavi ed25519 generate da Tor
3. Configurato l'autenticazione client (x25519)
4. Applicato hardening di base al servizio nascosto
5. Testato la connettività end-to-end via Tor Browser e curl

---

## Fase 1: Web server locale

```bash
# Opzione A: Python (più semplice per il lab)
mkdir -p /var/www/onion-lab
echo "<h1>Onion Service Lab</h1><p>Funziona! Sei connesso via Tor.</p>" \
    > /var/www/onion-lab/index.html

# Avvia il server sulla porta 8080 (solo localhost)
cd /var/www/onion-lab
python3 -m http.server 8080 --bind 127.0.0.1 &
HTTP_PID=$!

# Verifica che il server risponda
curl -s http://127.0.0.1:8080/
# Output atteso: <h1>Onion Service Lab</h1>...
```

```bash
# Opzione B: nginx (più realistico)
sudo apt install -y nginx
sudo tee /etc/nginx/sites-available/onion-lab << 'EOF'
server {
    listen 127.0.0.1:8080;
    server_name localhost;
    root /var/www/onion-lab;
    index index.html;

    # Header di sicurezza
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy no-referrer;

    # Disabilitare il logging per il servizio nascosto
    access_log off;
    error_log /dev/null;
}
EOF

sudo ln -sf /etc/nginx/sites-available/onion-lab /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

curl -s http://127.0.0.1:8080/
```

**Verifica**: `curl http://127.0.0.1:8080/` restituisce la pagina HTML.

> **Nota di sicurezza**: il server ascolta solo su `127.0.0.1` — non è
> raggiungibile dall'esterno. Solo Tor può raggiungerlo via Onion Service.

---

## Fase 2: Configurazione Onion Service

```bash
# Aggiungere la configurazione al torrc
sudo tee -a /etc/tor/torrc << 'EOF'

# === Lab 04 — Onion Service ===
HiddenServiceDir /var/lib/tor/onion-lab/
HiddenServicePort 80 127.0.0.1:8080
HiddenServiceVersion 3
EOF

# Riavviare Tor
sudo systemctl restart tor@default.service

# Attendere che Tor generi le chiavi e pubblichi il descriptor
sleep 5

# Leggere l'indirizzo .onion generato
sudo cat /var/lib/tor/onion-lab/hostname
# Output: un indirizzo di 56 caratteri + .onion
# Esempio: dz4k6x2xbv5aomht...d.onion
```

```bash
# Salvare l'indirizzo in una variabile per i test successivi
ONION_ADDR=$(sudo cat /var/lib/tor/onion-lab/hostname)
echo "Il tuo Onion Service: $ONION_ADDR"

# Verificare che Tor sia attivo con il servizio
sudo journalctl -u tor@default.service --no-pager | tail -5
# Dovresti vedere: "Registered new hidden service"
```

**Verifica**: un file `hostname` esiste in `/var/lib/tor/onion-lab/` con un
indirizzo `.onion` v3 di 56 caratteri.

---

## Fase 3: Verifica e connessione

```bash
# Test 1: connessione via curl e SOCKS5
ONION_ADDR=$(sudo cat /var/lib/tor/onion-lab/hostname)
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 60 "http://$ONION_ADDR"
# Output atteso: <h1>Onion Service Lab</h1>...
# NOTA: la prima connessione può richiedere 15-30 secondi

# Test 2: connessione via torsocks
torsocks curl -s --max-time 60 "http://$ONION_ADDR"
# Stesso output atteso

# Test 3: verifica con proxychains
proxychains curl -s --max-time 60 "http://$ONION_ADDR"
```

```bash
# Test 4: verifica in Tor Browser
# Apri Tor Browser e visita l'indirizzo .onion
echo "Apri Tor Browser e visita: http://$ONION_ADDR"

# Test 5: temporizzazione — misura la latenza
time curl --socks5-hostname 127.0.0.1:9050 -s --max-time 60 \
    -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" "http://$ONION_ADDR"
# Output tipico: HTTP 200 in 2.5-5.0s (6 hop: 3 client + 3 servizio)
```

**Verifica**: la pagina è raggiungibile da tutti e tre i metodi. La latenza
è più alta del normale (6 hop vs 3).

---

## Fase 4: Struttura delle chiavi

```bash
# Esaminare i file generati da Tor
sudo ls -la /var/lib/tor/onion-lab/
# Output:
# hostname                — indirizzo .onion pubblico
# hs_ed25519_public_key   — chiave pubblica ed25519 (32 byte)
# hs_ed25519_secret_key   — chiave privata ed25519 (64 byte)

# Analizzare le chiavi
sudo xxd /var/lib/tor/onion-lab/hs_ed25519_public_key | head -5
# I primi 32 byte dopo l'header "== ed25519v1-public: type0 ==\x00\x00\x00"
# sono la chiave pubblica effettiva

sudo xxd /var/lib/tor/onion-lab/hs_ed25519_secret_key | head -5
# Header: "== ed25519v1-secret: type0 ==\x00\x00\x00"
# Seguono 64 byte della chiave privata

# Decodificare l'indirizzo .onion
ONION_ADDR=$(sudo cat /var/lib/tor/onion-lab/hostname)
echo "Indirizzo: $ONION_ADDR"
echo "Lunghezza (senza .onion): ${#ONION_ADDR%%.*}"
# 56 caratteri = base32 di (32 byte pubkey + 2 byte checksum + 1 byte versione)
```

```bash
# Verificare la relazione tra chiave pubblica e indirizzo
# L'indirizzo .onion v3 è: base32(pubkey || checksum || version)
python3 << 'PYEOF'
import base64, hashlib

# Leggi la chiave pubblica (salta header di 32 byte)
with open("/var/lib/tor/onion-lab/hs_ed25519_public_key", "rb") as f:
    data = f.read()
    pubkey = data[32:]  # 32 byte dopo l'header

# Calcola indirizzo v3
version = bytes([3])
checksum = hashlib.sha3_256(
    b".onion checksum" + pubkey + version
).digest()[:2]

onion_bytes = pubkey + checksum + version
address = base64.b32encode(onion_bytes).decode().lower() + ".onion"
print(f"Calcolato:  {address}")

# Confronta con quello generato da Tor
with open("/var/lib/tor/onion-lab/hostname") as f:
    hostname = f.read().strip()
print(f"Da Tor:     {hostname}")
print(f"Match: {address == hostname}")
PYEOF
```

**Esercizio**: perché la chiave privata è il segreto più critico? Cosa
succede se qualcuno la ottiene?

---

## Fase 5: Autenticazione client

```bash
# Generare una coppia di chiavi x25519 per l'autenticazione client
# Richiede openssl ≥ 1.1 o il tool tor
# Metodo con Python (funziona ovunque):

python3 << 'PYEOF'
import os, base64

# Genera chiave privata x25519 (32 byte random, clamped)
privkey = bytearray(os.urandom(32))
privkey[0]  &= 248
privkey[31] &= 127
privkey[31] |= 64

# Per la chiave pubblica, serve la curva x25519
# Usiamo la libreria cryptography se disponibile
try:
    from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
    from cryptography.hazmat.primitives import serialization

    key = X25519PrivateKey.from_private_bytes(bytes(privkey))
    pubkey = key.public_key().public_bytes(
        serialization.Encoding.Raw,
        serialization.PublicFormat.Raw
    )
except ImportError:
    print("ERRORE: installa python3-cryptography")
    print("  sudo apt install python3-cryptography")
    exit(1)

priv_b32 = base64.b32encode(privkey).decode().rstrip("=")
pub_b32 = base64.b32encode(pubkey).decode().rstrip("=")

print(f"# Chiave PRIVATA (per il client) — file: client.auth_private")
print(f"# <onion-addr-no-.onion>:descriptor:x25519:<base32-privkey>")
print(f"PRIVKEY: {priv_b32}")
print()
print(f"# Chiave PUBBLICA (per il server) — file: <nome>.auth")
print(f"# descriptor:x25519:<base32-pubkey>")
print(f"PUBKEY: {pub_b32}")

# Salva i file
with open("/tmp/lab04-privkey.txt", "w") as f:
    f.write(priv_b32)
with open("/tmp/lab04-pubkey.txt", "w") as f:
    f.write(pub_b32)
PYEOF
```

```bash
# Configurare il LATO SERVER (autorizzazione client)
PUBKEY=$(cat /tmp/lab04-pubkey.txt)
sudo mkdir -p /var/lib/tor/onion-lab/authorized_clients
echo "descriptor:x25519:$PUBKEY" | \
    sudo tee /var/lib/tor/onion-lab/authorized_clients/lab-client.auth

# Riavviare Tor per attivare l'autenticazione
sudo systemctl restart tor@default.service
sleep 5

# Ora SENZA autenticazione, il servizio NON è raggiungibile
ONION_ADDR=$(sudo cat /var/lib/tor/onion-lab/hostname)
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 30 "http://$ONION_ADDR"
# Output atteso: errore o pagina vuota (descriptor non decifrabile)
```

```bash
# Configurare il LATO CLIENT
ONION_ADDR=$(sudo cat /var/lib/tor/onion-lab/hostname)
ONION_NAME="${ONION_ADDR%.onion}"
PRIVKEY=$(cat /tmp/lab04-privkey.txt)

# Creare il file di autenticazione client
sudo mkdir -p /var/lib/tor/onion_auth
echo "${ONION_NAME}:descriptor:x25519:${PRIVKEY}" | \
    sudo tee /var/lib/tor/onion_auth/lab-service.auth_private

# Aggiungere la direttiva al torrc (se non presente)
grep -q "ClientOnionAuthDir" /etc/tor/torrc || \
    echo "ClientOnionAuthDir /var/lib/tor/onion_auth" | \
    sudo tee -a /etc/tor/torrc

# Riavviare Tor
sudo systemctl restart tor@default.service
sleep 5

# Ora CON autenticazione, il servizio è raggiungibile
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 60 "http://$ONION_ADDR"
# Output atteso: <h1>Onion Service Lab</h1>...
```

**Esercizio**: cosa succede se rimuovi il file `.auth` dal server ma
il client ha ancora il file `.auth_private`? E viceversa?

---

## Fase 6: Vanity address (opzionale)

```bash
# mkp224o genera indirizzi .onion con un prefisso scelto
# ATTENZIONE: più lungo il prefisso, più tempo ci vuole

sudo apt install -y gcc libsodium-dev make autoconf git
git clone https://github.com/cathugger/mkp224o.git /tmp/mkp224o
cd /tmp/mkp224o
./autogen.sh && ./configure && make

# Genera un indirizzo che inizia con "test"
# (4 caratteri = pochi secondi, 6+ = ore/giorni)
./mkp224o -d /tmp/vanity-keys test -n 1 -S 10
ls /tmp/vanity-keys/

# Dentro la cartella trovi: hostname, hs_ed25519_public_key, hs_ed25519_secret_key
# Puoi copiarli al posto di quelli generati da Tor (fai backup prima!)
```

**Nota**: i vanity address sono cosmetici. Non aggiungono sicurezza
e il tempo di generazione cresce esponenzialmente con la lunghezza del prefisso.

---

## Fase 7: Hardening del servizio

```bash
# 1. Verificare i permessi delle chiavi
sudo ls -la /var/lib/tor/onion-lab/
# hs_ed25519_secret_key deve essere: -rw------- (600) owner: debian-tor
sudo stat -c "%a %U:%G" /var/lib/tor/onion-lab/hs_ed25519_secret_key
# Output atteso: 600 debian-tor:debian-tor

# 2. Limitare il web server a solo localhost
ss -tlnp | grep 8080
# Output: deve mostrare 127.0.0.1:8080 (non 0.0.0.0:8080)

# 3. Aggiungere header di sicurezza (se usi nginx)
# → Già configurati nella Fase 1 (Opzione B)

# 4. Limitare le connessioni con HiddenServiceMaxStreams
# Aggiungere al torrc nella sezione dell'onion service:
#   HiddenServiceMaxStreams 20
#   HiddenServiceMaxStreamsCloseCircuit 1

# 5. Isolare il servizio con systemd sandboxing
sudo systemctl edit tor@default.service << 'EOF'
[Service]
NoNewPrivileges=yes
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=/var/lib/tor /var/log/tor
EOF
sudo systemctl daemon-reload && sudo systemctl restart tor@default.service
```

```bash
# 6. Verificare che il servizio non esponga informazioni
curl --socks5-hostname 127.0.0.1:9050 -s -I "http://$ONION_ADDR" | head -10
# Controlla che NON ci sia:
# - Server: nginx/x.x.x  (usa "server_tokens off;" in nginx)
# - X-Powered-By: ...
# - Informazioni sulla versione del software
```

---

## Risoluzione problemi

### L'indirizzo .onion non viene generato

```bash
# Verificare i log di Tor
sudo journalctl -u tor@default.service --no-pager | grep -i "hidden\|error"

# Causa comune: permessi errati sulla directory
sudo ls -la /var/lib/tor/onion-lab/
# La directory deve essere: owner debian-tor, permessi 700
sudo chown -R debian-tor:debian-tor /var/lib/tor/onion-lab/
sudo chmod 700 /var/lib/tor/onion-lab/

# Causa comune: errore di sintassi nel torrc
sudo tor --verify-config
# Se mostra errori, correggi il torrc e riavvia
```

### curl verso .onion va in timeout

```bash
# La prima connessione può richiedere 30-60 secondi (6 hop da costruire)
# Aumenta il timeout:
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 120 "http://$ONION_ADDR"

# Se persiste, verificare che il web server locale sia attivo:
curl -s http://127.0.0.1:8080/
# Se questo fallisce → il server non è in esecuzione, non è un problema Tor

# Verificare che Tor abbia pubblicato il descriptor:
sudo journalctl -u tor@default.service | grep "Registered new hidden service"
# Se non appare → il torrc non è stato ricaricato
sudo systemctl restart tor@default.service
```

### Autenticazione client non funziona

```bash
# Errore: il servizio diventa irraggiungibile dopo aver aggiunto l'auth

# 1. Verificare formato file .auth (lato server)
sudo cat /var/lib/tor/onion-lab/authorized_clients/lab-client.auth
# Formato corretto: descriptor:x25519:<base32_pubkey>
# Errore comune: spazi o newline extra nel file

# 2. Verificare formato file .auth_private (lato client)
sudo cat /var/lib/tor/onion_auth/lab-service.auth_private
# Formato corretto: <onion_senza_.onion>:descriptor:x25519:<base32_privkey>

# 3. Riavviare Tor dopo ogni modifica ai file di auth
sudo systemctl restart tor@default.service
sleep 10  # attendere la ripubblicazione del descriptor
```

---

## Cleanup

```bash
# Rimuovere la configurazione del lab dal torrc
sudo sed -i '/# === Lab 04/,/^$/d' /etc/tor/torrc

# Rimuovere i file dell'onion service
sudo rm -rf /var/lib/tor/onion-lab/
sudo rm -rf /var/lib/tor/onion_auth/

# Rimuovere la direttiva ClientOnionAuthDir
sudo sed -i '/ClientOnionAuthDir/d' /etc/tor/torrc

# Riavviare Tor
sudo systemctl restart tor@default.service

# Fermare il web server Python (se usato)
kill $HTTP_PID 2>/dev/null

# Rimuovere i file temporanei
rm -f /tmp/lab04-privkey.txt /tmp/lab04-pubkey.txt
```

---

## Checklist finale

- [ ] Web server locale attivo solo su 127.0.0.1:8080
- [ ] Onion Service v3 configurato e indirizzo .onion generato
- [ ] Connessione verificata via curl, torsocks e Tor Browser
- [ ] Struttura chiavi ed25519 analizzata e compresa
- [ ] Relazione chiave pubblica ↔ indirizzo .onion verificata con Python
- [ ] Autenticazione client x25519 configurata e testata
- [ ] Servizio non raggiungibile senza autenticazione
- [ ] Servizio raggiungibile con autenticazione corretta
- [ ] Hardening applicato (permessi, header, binding)

---

## Vedi anche

- [Onion Services v3](../03-nodi-e-rete/onion-services-v3.md) — Architettura e protocollo completo
- [Tor e Localhost](../06-configurazioni-avanzate/tor-e-localhost.md) — Binding e port forwarding
- [Hardening di Sistema](../05-sicurezza-operativa/hardening-sistema.md) — Sandboxing e permessi
- [Comunicazione Sicura](../09-scenari-operativi/comunicazione-sicura.md) — Scenari d'uso reali
