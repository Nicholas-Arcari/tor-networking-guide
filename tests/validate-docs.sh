#!/bin/bash
# validate-docs.sh - Validazione struttura e contenuto della documentazione
#
# Verifica che tutti i documenti, config, e script esistano e siano ben formati.
# Uso: ./tests/validate-docs.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
WARN=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}[OK]${NC}  $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}[!!]${NC}  $1"; FAIL=$((FAIL+1)); }
warn_() { echo -e "  ${YELLOW}[??]${NC}  $1"; WARN=$((WARN+1)); }
section() { echo -e "\n${BOLD}--- $1 ---${NC}"; }

# ============================================================
section "1. Struttura directory"
# ============================================================

EXPECTED_DIRS=(
    "docs/01-fondamenti"
    "docs/02-installazione-e-configurazione"
    "docs/03-nodi-e-rete"
    "docs/04-strumenti-operativi"
    "docs/05-sicurezza-operativa"
    "docs/06-configurazioni-avanzate"
    "docs/07-limitazioni-e-attacchi"
    "docs/08-aspetti-legali-ed-etici"
    "docs/09-scenari-operativi"
    "docs/10-laboratorio-pratico"
    "config-examples/torrc"
    "config-examples/proxychains"
    "config-examples/iptables"
    "scripts"
    "tests"
)

for dir in "${EXPECTED_DIRS[@]}"; do
    if [ -d "$REPO_ROOT/$dir" ]; then
        pass "$dir/"
    else
        fail "$dir/ non trovata"
    fi
done

# ============================================================
section "2. Documenti - esistenza"
# ============================================================

EXPECTED_DOCS=(
    "docs/01-fondamenti/architettura-tor.md"
    "docs/01-fondamenti/costruzione-circuiti.md"
    "docs/01-fondamenti/isolamento-e-modello-minaccia.md"
    "docs/01-fondamenti/circuiti-crittografia-e-celle.md"
    "docs/01-fondamenti/crittografia-e-handshake.md"
    "docs/01-fondamenti/stream-padding-e-pratica.md"
    "docs/01-fondamenti/consenso-e-directory-authorities.md"
    "docs/01-fondamenti/struttura-consenso-e-flag.md"
    "docs/01-fondamenti/descriptor-cache-e-attacchi.md"
    "docs/01-fondamenti/scenari-reali.md"
    "docs/02-installazione-e-configurazione/installazione-e-verifica.md"
    "docs/02-installazione-e-configurazione/configurazione-iniziale.md"
    "docs/02-installazione-e-configurazione/troubleshooting-e-struttura.md"
    "docs/02-installazione-e-configurazione/torrc-guida-completa.md"
    "docs/02-installazione-e-configurazione/torrc-bridge-e-sicurezza.md"
    "docs/02-installazione-e-configurazione/torrc-performance-e-relay.md"
    "docs/02-installazione-e-configurazione/gestione-del-servizio.md"
    "docs/02-installazione-e-configurazione/manutenzione-e-monitoraggio.md"
    "docs/02-installazione-e-configurazione/scenari-reali.md"
    "docs/03-nodi-e-rete/guard-nodes.md"
    "docs/03-nodi-e-rete/middle-relay.md"
    "docs/03-nodi-e-rete/exit-nodes.md"
    "docs/03-nodi-e-rete/exit-nodes-pratica.md"
    "docs/03-nodi-e-rete/bridges-e-pluggable-transports.md"
    "docs/03-nodi-e-rete/bridge-configurazione-e-alternative.md"
    "docs/03-nodi-e-rete/onion-services-v3.md"
    "docs/03-nodi-e-rete/relay-monitoring-e-metriche.md"
    "docs/03-nodi-e-rete/monitoring-avanzato.md"
    "docs/03-nodi-e-rete/scenari-reali.md"
    "docs/04-strumenti-operativi/proxychains-guida-completa.md"
    "docs/04-strumenti-operativi/torsocks.md"
    "docs/04-strumenti-operativi/controllo-circuiti-e-newnym.md"
    "docs/04-strumenti-operativi/verifica-ip-dns-e-leak.md"
    "docs/04-strumenti-operativi/nyx-e-monitoraggio.md"
    "docs/04-strumenti-operativi/tor-browser-e-applicazioni.md"
    "docs/04-strumenti-operativi/tor-e-dns-risoluzione.md"
    "docs/04-strumenti-operativi/nyx-avanzato.md"
    "docs/04-strumenti-operativi/applicazioni-via-tor.md"
    "docs/04-strumenti-operativi/torsocks-avanzato.md"
    "docs/04-strumenti-operativi/dns-avanzato-e-hardening.md"
    "docs/04-strumenti-operativi/scenari-reali.md"
    "docs/05-sicurezza-operativa/dns-leak.md"
    "docs/05-sicurezza-operativa/traffic-analysis.md"
    "docs/05-sicurezza-operativa/fingerprinting.md"
    "docs/05-sicurezza-operativa/opsec-e-errori-comuni.md"
    "docs/05-sicurezza-operativa/isolamento-e-compartimentazione.md"
    "docs/05-sicurezza-operativa/hardening-sistema.md"
    "docs/05-sicurezza-operativa/analisi-forense-e-artefatti.md"
    "docs/05-sicurezza-operativa/dns-leak-prevenzione-e-hardening.md"
    "docs/05-sicurezza-operativa/fingerprinting-avanzato.md"
    "docs/05-sicurezza-operativa/isolamento-avanzato.md"
    "docs/05-sicurezza-operativa/opsec-casi-reali-e-difese.md"
    "docs/05-sicurezza-operativa/traffic-analysis-attacchi-e-difese.md"
    "docs/05-sicurezza-operativa/hardening-avanzato.md"
    "docs/05-sicurezza-operativa/forense-browser-e-mitigazione.md"
    "docs/05-sicurezza-operativa/scenari-reali.md"
    "docs/06-configurazioni-avanzate/vpn-e-tor-ibrido.md"
    "docs/06-configurazioni-avanzate/transparent-proxy.md"
    "docs/06-configurazioni-avanzate/multi-istanza-e-stream-isolation.md"
    "docs/06-configurazioni-avanzate/tor-e-localhost.md"
    "docs/06-configurazioni-avanzate/transparent-proxy-avanzato.md"
    "docs/06-configurazioni-avanzate/vpn-tor-routing-e-dns.md"
    "docs/06-configurazioni-avanzate/stream-isolation-avanzato.md"
    "docs/06-configurazioni-avanzate/localhost-docker-e-sviluppo.md"
    "docs/06-configurazioni-avanzate/scenari-reali.md"
    "docs/07-limitazioni-e-attacchi/limitazioni-protocollo.md"
    "docs/07-limitazioni-e-attacchi/limitazioni-applicazioni.md"
    "docs/07-limitazioni-e-attacchi/attacchi-noti.md"
    "docs/07-limitazioni-e-attacchi/attacchi-noti-avanzati.md"
    "docs/07-limitazioni-e-attacchi/limitazioni-applicazioni-pratica.md"
    "docs/07-limitazioni-e-attacchi/scenari-reali.md"
    "docs/08-aspetti-legali-ed-etici/aspetti-legali.md"
    "docs/08-aspetti-legali-ed-etici/etica-e-responsabilita.md"
    "docs/08-aspetti-legali-ed-etici/aspetti-legali-relay-e-confronto.md"
    "docs/08-aspetti-legali-ed-etici/etica-contribuire-e-comunita.md"
    "docs/08-aspetti-legali-ed-etici/scenari-reali.md"
    "docs/09-scenari-operativi/ricognizione-anonima.md"
    "docs/09-scenari-operativi/comunicazione-sicura.md"
    "docs/09-scenari-operativi/sviluppo-e-test.md"
    "docs/09-scenari-operativi/incident-response.md"
    "docs/09-scenari-operativi/scenari-reali.md"
    "docs/10-laboratorio-pratico/lab-01-setup-e-verifica.md"
    "docs/10-laboratorio-pratico/lab-02-analisi-circuiti.md"
    "docs/10-laboratorio-pratico/lab-03-dns-leak-testing.md"
    "docs/10-laboratorio-pratico/lab-04-onion-service.md"
    "docs/10-laboratorio-pratico/lab-05-stream-isolation.md"
    "docs/10-laboratorio-pratico/scenari-reali.md"
    "docs/glossario.md"
)

for doc in "${EXPECTED_DOCS[@]}"; do
    if [ -f "$REPO_ROOT/$doc" ]; then
        pass "$doc"
    else
        fail "$doc non trovato"
    fi
done

# ============================================================
section "3. Documenti - dimensione minima"
# ============================================================

MIN_LINES=80

for doc in "${EXPECTED_DOCS[@]}"; do
    filepath="$REPO_ROOT/$doc"
    if [ -f "$filepath" ]; then
        lines=$(wc -l < "$filepath")
        if [ "$lines" -ge $MIN_LINES ]; then
            pass "$doc ($lines righe)"
        else
            warn_ "$doc solo $lines righe (minimo: $MIN_LINES)"
        fi
    fi
done

# ============================================================
section "4. Documenti - intestazione e struttura"
# ============================================================

for doc in "${EXPECTED_DOCS[@]}"; do
    filepath="$REPO_ROOT/$doc"
    if [ -f "$filepath" ]; then
        # Verifica che inizi con un heading H1
        if head -1 "$filepath" | grep -q "^# "; then
            pass "$doc ha heading H1"
        else
            fail "$doc manca heading H1"
        fi

        # Verifica almeno una sezione H2
        if grep -q "^## " "$filepath"; then
            pass "$doc ha sezioni H2"
        else
            warn_ "$doc manca sezioni H2"
        fi
    fi
done

# ============================================================
section "5. Config examples"
# ============================================================

EXPECTED_CONFIGS=(
    "config-examples/torrc/torrc-client.example"
    "config-examples/torrc/torrc.example"
    "config-examples/torrc/torrc-relay.example"
    "config-examples/torrc/torrc-hidden-service.example"
    "config-examples/torrc/torrc-bridge.example"
    "config-examples/torrc/torrc-exit.example"
    "config-examples/proxychains/proxychains4.conf.example"
    "config-examples/iptables/transparent-proxy.sh.example"
)

for cfg in "${EXPECTED_CONFIGS[@]}"; do
    if [ -f "$REPO_ROOT/$cfg" ]; then
        pass "$cfg"
    else
        fail "$cfg non trovato"
    fi
done

# ============================================================
section "6. Scripts"
# ============================================================

EXPECTED_SCRIPTS=(
    "scripts/newnym.example"
    "scripts/tor-newip.sh.example"
    "scripts/check-dns-leak.sh.example"
    "scripts/verify-tor-connection.sh.example"
    "scripts/tor-circuit-info.py.example"
    "scripts/tor-health-monitor.sh.example"
    "scripts/newnym-with-verify.sh.example"
    "scripts/setup-tor-profile.sh.example"
)

for script in "${EXPECTED_SCRIPTS[@]}"; do
    if [ -f "$REPO_ROOT/$script" ]; then
        pass "$script"
    else
        fail "$script non trovato"
    fi
done

# Verifica setup.sh nella root
if [ -f "$REPO_ROOT/setup.sh" ]; then
    pass "setup.sh"
    if [ -x "$REPO_ROOT/setup.sh" ]; then
        pass "setup.sh è eseguibile"
    else
        warn_ "setup.sh non è eseguibile"
    fi
else
    fail "setup.sh non trovato"
fi

# ============================================================
section "7. File progetto"
# ============================================================

for file in README.md LICENSE; do
    if [ -f "$REPO_ROOT/$file" ]; then
        pass "$file"
    else
        fail "$file non trovato"
    fi
done

# ============================================================
section "8. Link interni (cross-reference)"
# ============================================================

# Verifica che i link relativi nei documenti puntino a file esistenti
BROKEN_LINKS=0
for doc in "${EXPECTED_DOCS[@]}"; do
    filepath="$REPO_ROOT/$doc"
    if [ -f "$filepath" ]; then
        docdir=$(dirname "$filepath")
        # Estrai link markdown relativi: [text](../path/file.md)
        { grep -oP '\]\(\K[^)]+\.md' "$filepath" 2>/dev/null || true; } | while read -r link; do
            # Ignora URL http
            if [[ "$link" == http* ]]; then continue; fi
            # Risolvi percorso relativo
            resolved=$(cd "$docdir" && realpath -m "$link" 2>/dev/null || echo "")
            if [ -n "$resolved" ] && [ ! -f "$resolved" ]; then
                fail "Link rotto in $doc: $link"
                BROKEN_LINKS=$((BROKEN_LINKS+1))
            fi
        done
    fi
done

if [ $BROKEN_LINKS -eq 0 ]; then
    pass "Nessun link interno rotto trovato"
fi

# ============================================================
echo ""
echo -e "${BOLD}=== RISULTATO ===${NC}"
echo -e "  ${GREEN}OK:${NC}       $PASS"
echo -e "  ${RED}FALLITI:${NC}  $FAIL"
echo -e "  ${YELLOW}WARNING:${NC} $WARN"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}Tutti i test superati!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL test falliti. Correggere prima del commit.${NC}"
    exit 1
fi