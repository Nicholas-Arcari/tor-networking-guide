# Lab 05 — Stream Isolation e Multi-Istanza Tor

Esercizio pratico per configurare stream isolation con SocksPort multipli,
istanze Tor separate, e verificare che il traffico di applicazioni diverse
viaggi su circuiti indipendenti.

**Tempo stimato**: 40-50 minuti
**Prerequisiti**: Lab 01 completato, accesso root, Python 3
**Difficoltà**: Avanzato

---

## Indice

- [Obiettivi](#obiettivi)
- [Fase 1: Comprendere la stream isolation](#fase-1-comprendere-la-stream-isolation)
- [Fase 2: SocksPort multipli con IsolateDestAddr](#fase-2-socksport-multipli-con-isolatedestaddr)
- [Fase 3: Verificare l'isolamento](#fase-3-verificare-lisolamento)
- [Fase 4: Multi-istanza Tor](#fase-4-multi-istanza-tor)
- [Fase 5: Routing applicazioni su istanze diverse](#fase-5-routing-applicazioni-su-istanze-diverse)
- [Fase 6: Script di verifica automatica](#fase-6-script-di-verifica-automatica)
- [Fase 7: Scenario operativo — identità separate](#fase-7-scenario-operativo--identità-separate)
- [Checklist finale](#checklist-finale)

---

## Obiettivi

Al termine di questo lab, saprai:
1. Configurare SocksPort multipli con flag di isolamento diversi
2. Verificare che circuiti diversi siano effettivamente usati
3. Configurare e gestire istanze Tor indipendenti con systemd
4. Assegnare applicazioni a istanze/porte specifiche
5. Implementare separazione di identità a livello di rete

---

## Fase 1: Comprendere la stream isolation

```
Senza isolation:
  Browser ──┐
  curl    ──┼── SocksPort 9050 ──→ Circuito A ──→ Exit X
  wget    ──┘

Con isolation (IsolateDestAddr):
  Browser → example.com ──→ SocksPort 9050 ──→ Circuito A ──→ Exit X
  Browser → torproject.org ──→ SocksPort 9050 ──→ Circuito B ──→ Exit Y
  (stesso SocksPort, circuiti diversi per destinazione diversa)

Con SocksPort multipli:
  Browser ──→ SocksPort 9050 ──→ Circuito A ──→ Exit X
  curl    ──→ SocksPort 9052 ──→ Circuito B ──→ Exit Y
  wget    ──→ SocksPort 9054 ──→ Circuito C ──→ Exit Z
  (porte diverse = circuiti indipendenti garantiti)
```

```bash
# Verificare la configurazione attuale
grep "SocksPort" /etc/tor/torrc
# Output probabile: SocksPort 9050

# Controllare i flag di isolamento di default
# Tor applica automaticamente: IsolateClientAddr IsolateSOCKSAuth IsolateClientProtocol IsolateDestPort
# Questo significa che connessioni dalla stessa app alla stessa porta
# di destinazione usano lo stesso circuito
```

---

## Fase 2: SocksPort multipli con IsolateDestAddr

```bash
# Configurare SocksPort dedicati per scopi diversi
sudo tee -a /etc/tor/torrc << 'EOF'

# === Lab 05 — Stream Isolation ===
# Porta generica (isolamento standard)
# SocksPort 9050 già configurato

# Porta per browser (isola per indirizzo di destinazione)
SocksPort 9052 IsolateDestAddr IsolateDestPort

# Porta per comunicazioni (isola per autenticazione SOCKS)
SocksPort 9054 IsolateSOCKSAuth

# Porta per download (nessun isolamento — massimo riuso circuiti)
SocksPort 9056 NoIsolateClientAddr NoIsolateSOCKSAuth NoIsolateClientProtocol NoIsolateDestPort NoIsolateDestAddr

# Porta per operazioni sensibili (isolamento massimo)
SocksPort 9058 IsolateClientAddr IsolateSOCKSAuth IsolateClientProtocol IsolateDestPort IsolateDestAddr
EOF

# Riavviare Tor
sudo systemctl restart tor@default.service
sleep 3

# Verificare che tutte le porte siano attive
for port in 9050 9052 9054 9056 9058; do
    if ss -tlnp | grep -q ":$port "; then
        echo "SocksPort $port: ATTIVO"
    else
        echo "SocksPort $port: NON ATTIVO — controllare i log"
    fi
done
```

**Verifica**: tutte e 5 le porte rispondono.

---

## Fase 3: Verificare l'isolamento

```bash
# Test 1: SocksPort standard (9050) — stesso circuito per stessa destinazione
echo "=== SocksPort 9050 (default) ==="
IP1=$(curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://api.ipify.org)
IP2=$(curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://api.ipify.org)
echo "Richiesta 1: $IP1"
echo "Richiesta 2: $IP2"
echo "Stesso IP (stesso circuito riusato): $([ "$IP1" = "$IP2" ] && echo SÌ || echo NO)"

# Test 2: SocksPort 9052 (IsolateDestAddr) — circuiti diversi per host diversi
echo ""
echo "=== SocksPort 9052 (IsolateDestAddr) ==="
IP_A=$(curl --socks5-hostname 127.0.0.1:9052 -s --max-time 20 https://api.ipify.org)
IP_B=$(curl --socks5-hostname 127.0.0.1:9052 -s --max-time 20 https://httpbin.org/ip | grep -oP '"origin":\s*"\K[^"]+')
echo "api.ipify.org vede: $IP_A"
echo "httpbin.org vede:   $IP_B"
echo "IP diversi (isolamento OK): $([ "$IP_A" != "$IP_B" ] && echo SÌ || echo NO)"

# Test 3: SocksPort 9058 (isolamento massimo) — sempre circuiti diversi
echo ""
echo "=== SocksPort 9058 (max isolation) ==="
for i in 1 2 3; do
    IP=$(curl --socks5-hostname 127.0.0.1:9058 -s --max-time 20 https://api.ipify.org)
    echo "Richiesta $i: $IP"
done
echo "(Potrebbero essere diversi ad ogni richiesta)"
```

```bash
# Test 4: Osservare i circuiti con Stem
python3 << 'PYEOF'
import stem
from stem.control import Controller
import time

with Controller.from_port(port=9051) as ctrl:
    ctrl.authenticate()

    print("Circuiti attivi:")
    print("-" * 60)
    for circ in ctrl.get_circuits():
        if circ.status == "BUILT":
            path = " → ".join([
                f"{nick}({fp[:8]})"
                for fp, nick in circ.path
            ])
            print(f"  Circuito {circ.id}: {path}")
            if circ.purpose:
                print(f"    Purpose: {circ.purpose}")
    print(f"\nTotale circuiti built: {sum(1 for c in ctrl.get_circuits() if c.status == 'BUILT')}")
PYEOF
```

**Esercizio**: quanti circuiti vedi dopo aver eseguito i 4 test?
Riesci a correlare ogni circuito con i test effettuati?

---

## Fase 4: Multi-istanza Tor

```bash
# Creare una seconda istanza Tor completamente indipendente
# Ogni istanza ha: torrc, DataDirectory, SocksPort, ControlPort separati

# 1. Creare la directory dati
sudo mkdir -p /var/lib/tor-instances/lab05
sudo chown debian-tor:debian-tor /var/lib/tor-instances/lab05
sudo chmod 700 /var/lib/tor-instances/lab05

# 2. Creare il torrc dedicato
sudo tee /etc/tor/instances/lab05/torrc << 'EOF'
# Seconda istanza Tor — indipendente dalla principale
SocksPort 9060
ControlPort 9061
CookieAuthentication 1

# DataDirectory gestito automaticamente da tor@lab05
# /var/lib/tor-instances/lab05/

Log notice file /var/log/tor/tor-lab05.log
EOF

# 3. Creare la directory di configurazione (Debian/Kali)
sudo mkdir -p /etc/tor/instances/lab05

# 4. Avviare la seconda istanza
sudo systemctl start tor@lab05.service
sudo systemctl status tor@lab05.service
# Output atteso: active (running)

# 5. Verificare il bootstrap
sleep 10
sudo journalctl -u tor@lab05.service --no-pager | grep "Bootstrapped 100%"
```

```bash
# Verificare che le due istanze siano indipendenti
echo "=== Istanza principale (9050) ==="
curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://api.ipify.org

echo "=== Istanza lab05 (9060) ==="
curl --socks5-hostname 127.0.0.1:9060 -s --max-time 20 https://api.ipify.org

# Le due istanze hanno circuiti completamente indipendenti
# Non condividono guard node, circuiti, o stato
```

```bash
# Confrontare i guard node delle due istanze
python3 << 'PYEOF'
from stem.control import Controller

for name, port in [("Principale", 9051), ("Lab05", 9061)]:
    try:
        with Controller.from_port(port=port) as ctrl:
            ctrl.authenticate()
            guards = set()
            for circ in ctrl.get_circuits():
                if circ.status == "BUILT" and circ.path:
                    guards.add(circ.path[0][1])  # nickname del guard
            print(f"Istanza {name} (:{port}) — Guard nodes: {guards or 'nessuno ancora'}")
    except Exception as e:
        print(f"Istanza {name} (:{port}) — Errore: {e}")
PYEOF
# I guard node DEVONO essere diversi (istanze indipendenti)
```

---

## Fase 5: Routing applicazioni su istanze diverse

```bash
# Scenario: separare il traffico browser dal traffico CLI

# Configurare proxychains per ciascuna istanza
# Profilo 1: istanza principale (browser)
sudo tee /etc/proxychains-browser.conf << 'EOF'
strict_chain
proxy_dns
[ProxyList]
socks5 127.0.0.1 9050
EOF

# Profilo 2: istanza lab05 (CLI e download)
sudo tee /etc/proxychains-cli.conf << 'EOF'
strict_chain
proxy_dns
[ProxyList]
socks5 127.0.0.1 9060
EOF

# Usare profili specifici
echo "Browser (istanza 1):"
proxychains -f /etc/proxychains-browser.conf curl -s --max-time 20 https://api.ipify.org

echo "CLI (istanza 2):"
proxychains -f /etc/proxychains-cli.conf curl -s --max-time 20 https://api.ipify.org
# IP diversi = istanze indipendenti confermate
```

```bash
# Esempio pratico: browser e terminale su identità separate
# Terminale 1 — Firefox su istanza principale
proxychains -f /etc/proxychains-browser.conf firefox -no-remote -P tor-proxy &

# Terminale 2 — operazioni CLI su istanza separata
PROXYCHAINS_CONF_FILE=/etc/proxychains-cli.conf proxychains wget -q \
    -O /dev/null https://check.torproject.org

# Il browser e il terminale usano exit node diversi
# → non possono essere correlati da un osservatore
```

---

## Fase 6: Script di verifica automatica

Crea il file `test-stream-isolation.sh`:

```bash
#!/bin/bash
# test-stream-isolation.sh — Verifica stream isolation e multi-istanza
set -euo pipefail

PASS=0
FAIL=0
TIMEOUT=25

green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }

check() {
    local desc="$1" result="$2"
    if [ "$result" = "OK" ]; then
        green "  ✓ $desc"
        PASS=$((PASS+1))
    else
        red "  ✗ $desc — $result"
        FAIL=$((FAIL+1))
    fi
}

echo "=== Test Stream Isolation ==="
echo ""

# Test 1: tutte le porte attive
echo "--- Porte SocksPort ---"
for port in 9050 9052 9054 9056 9058 9060; do
    if ss -tlnp | grep -q ":$port "; then
        check "SocksPort $port attivo" "OK"
    else
        check "SocksPort $port attivo" "FAIL: porta non in ascolto"
    fi
done

echo ""
echo "--- Isolamento per destinazione (SocksPort 9052) ---"
IP_A=$(curl --socks5-hostname 127.0.0.1:9052 -s --max-time $TIMEOUT https://api.ipify.org 2>/dev/null || echo "ERRORE")
IP_B=$(curl --socks5-hostname 127.0.0.1:9052 -s --max-time $TIMEOUT https://httpbin.org/ip 2>/dev/null | grep -oP '"origin":\s*"\K[^"]+' || echo "ERRORE")
if [ "$IP_A" != "$IP_B" ] && [ "$IP_A" != "ERRORE" ] && [ "$IP_B" != "ERRORE" ]; then
    check "IsolateDestAddr: IP diversi per host diversi ($IP_A ≠ $IP_B)" "OK"
else
    check "IsolateDestAddr: IP diversi per host diversi" "FAIL: $IP_A vs $IP_B"
fi

echo ""
echo "--- Isolamento tra istanze ---"
IP_MAIN=$(curl --socks5-hostname 127.0.0.1:9050 -s --max-time $TIMEOUT https://api.ipify.org 2>/dev/null || echo "ERRORE")
IP_LAB=$(curl --socks5-hostname 127.0.0.1:9060 -s --max-time $TIMEOUT https://api.ipify.org 2>/dev/null || echo "ERRORE")
if [ "$IP_MAIN" != "$IP_LAB" ] && [ "$IP_MAIN" != "ERRORE" ] && [ "$IP_LAB" != "ERRORE" ]; then
    check "Istanze indipendenti: IP diversi ($IP_MAIN ≠ $IP_LAB)" "OK"
elif [ "$IP_MAIN" = "ERRORE" ] || [ "$IP_LAB" = "ERRORE" ]; then
    check "Istanze indipendenti" "FAIL: connessione non riuscita"
else
    check "Istanze indipendenti" "WARN: stesso IP (può capitare, ripetere il test)"
fi

echo ""
echo "--- Risultati ---"
echo "PASS: $PASS  FAIL: $FAIL"
[ $FAIL -eq 0 ] && green "Tutti i test superati!" || red "Alcuni test falliti."
```

```bash
chmod +x test-stream-isolation.sh
./test-stream-isolation.sh
```

---

## Fase 7: Scenario operativo — identità separate

Scenario: un ricercatore deve mantenere due identità online completamente
separate — una per raccogliere informazioni pubbliche, l'altra per comunicare
con le fonti.

```bash
# Architettura:
#
# Identità A (OSINT)          Identità B (Comunicazione)
#   Firefox profilo osint        Firefox profilo comms
#        ↓                            ↓
#   proxychains 9050             proxychains 9060
#        ↓                            ↓
#   tor@default                  tor@lab05
#   Guard: G1                    Guard: G2
#   Exit: diversi                Exit: diversi
#
# Le due identità NON condividono:
# - Guard node
# - Circuiti
# - Cookie di sessione (profili Firefox separati)
# - Tempo di utilizzo (usarli in momenti diversi riduce la correlazione)

# Preparazione identità A
firefox -no-remote -CreateProfile osint 2>/dev/null
proxychains -f /etc/proxychains-browser.conf firefox -no-remote -P osint &

# Preparazione identità B (in un altro terminale)
firefox -no-remote -CreateProfile comms 2>/dev/null
proxychains -f /etc/proxychains-cli.conf firefox -no-remote -P comms &
```

**Regole operative**:
1. **Mai** usare le due identità contemporaneamente sulla stessa rete
2. **Mai** accedere agli stessi account da entrambe le identità
3. Cambiare circuito (NEWNYM) prima di passare da un'identità all'altra
4. Mantenere stili di scrittura e comportamento diversi
5. Usare orari di connessione diversi quando possibile

---

## Risoluzione problemi

### Le porte extra non si attivano

```bash
# Verificare errori nella configurazione
sudo tor --verify-config 2>&1 | grep -i error

# Causa comune: conflitto di porte con altri servizi
for port in 9052 9054 9056 9058; do
    if ss -tlnp | grep -q ":$port "; then
        echo "Porta $port: OK"
    else
        echo "Porta $port: CONFLITTO — qualcosa la occupa già?"
        ss -tlnp | grep ":$port " || echo "  (porta libera ma Tor non la usa — controllare torrc)"
    fi
done

# Se Tor non si avvia affatto dopo le modifiche al torrc:
sudo journalctl -u tor@default.service --no-pager | tail -20
# Cercare: "Failed to parse" o "Could not bind"
```

### L'isolamento non funziona (stesso IP su porte diverse)

```bash
# IsolateDestAddr isola per DESTINAZIONE, non per richiesta.
# Se chiedi lo stesso URL su porte diverse con IsolateDestAddr,
# Tor può riutilizzare lo stesso circuito (stessa destinazione!)

# Per test affidabili, usa destinazioni DIVERSE:
curl --socks5-hostname 127.0.0.1:9052 -s https://api.ipify.org      # sito A
curl --socks5-hostname 127.0.0.1:9052 -s https://httpbin.org/ip      # sito B
# Questi DEVONO dare IP diversi con IsolateDestAddr

# Per forzare circuiti diversi anche verso lo stesso sito,
# usa la porta con isolamento massimo (9058)
```

### La seconda istanza Tor non fa bootstrap

```bash
# Verificare che la directory di configurazione esista
ls -la /etc/tor/instances/lab05/torrc

# Verificare che la DataDirectory abbia permessi corretti
sudo ls -la /var/lib/tor-instances/lab05/
# Deve essere: owner debian-tor, permessi 700

# Verificare i log specifici dell'istanza
sudo journalctl -u tor@lab05.service --no-pager | tail -20

# Se l'errore è "No such file": Debian/Kali usa il pattern tor@<nome>
# La configurazione deve essere in /etc/tor/instances/<nome>/torrc
```

---

## Cleanup

```bash
# Fermare l'istanza lab05
sudo systemctl stop tor@lab05.service
sudo systemctl disable tor@lab05.service 2>/dev/null

# Rimuovere la configurazione multi-istanza
sudo rm -rf /etc/tor/instances/lab05/
sudo rm -rf /var/lib/tor-instances/lab05/
sudo rm -f /var/log/tor/tor-lab05.log

# Rimuovere le porte extra dal torrc principale
sudo sed -i '/# === Lab 05/,/^$/d' /etc/tor/torrc
sudo sed -i '/SocksPort 905[2468]/d' /etc/tor/torrc

# Rimuovere i file proxychains extra
sudo rm -f /etc/proxychains-browser.conf /etc/proxychains-cli.conf

# Riavviare Tor con la configurazione pulita
sudo systemctl restart tor@default.service

# Rimuovere i profili Firefox del lab
rm -rf ~/.mozilla/firefox/*osint* ~/.mozilla/firefox/*comms*
```

---

## Checklist finale

- [ ] SocksPort multipli (9050, 9052, 9054, 9056, 9058) configurati e attivi
- [ ] IsolateDestAddr verificato: host diversi → exit node diversi
- [ ] IsolateSOCKSAuth compreso e testato
- [ ] Seconda istanza Tor (tor@lab05) avviata su SocksPort 9060
- [ ] Guard node diversi tra le due istanze verificati con Stem
- [ ] Profili proxychains separati funzionanti
- [ ] Script di test automatico eseguito con successo
- [ ] Scenario identità separate compreso e configurato
- [ ] Cleanup eseguito, configurazione ripristinata

---

## Vedi anche

- [Multi-Istanza e Stream Isolation](../06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md) — Configurazione completa
- [Isolamento e Compartimentazione](../05-sicurezza-operativa/isolamento-e-compartimentazione.md) — Strategie di separazione
- [Controllo Circuiti e NEWNYM](../04-strumenti-operativi/controllo-circuiti-e-newnym.md) — Gestione circuiti
- [OPSEC e Errori Comuni](../05-sicurezza-operativa/opsec-e-errori-comuni.md) — Errori di correlazione
