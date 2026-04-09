#!/bin/bash
# smoke-test-tor.sh - Smoke test per verificare che Tor funzioni correttamente
#
# Verifica: servizio, porte, bootstrap, connessione, ControlPort, NEWNYM, DNS.
# Richiede: Tor attivo, utente nel gruppo debian-tor
#
# Uso: ./tests/smoke-test-tor.sh

set -euo pipefail

PASS=0
FAIL=0
SKIP=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
skip() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; SKIP=$((SKIP+1)); }
section() { echo -e "\n${BOLD}--- $1 ---${NC}"; }

echo -e "${BOLD}=== Tor Smoke Test ===${NC}"
echo ""

# ============================================================
section "1. Servizio Tor"
# ============================================================

if systemctl is-active --quiet tor@default.service 2>/dev/null; then
    pass "tor@default.service attivo"
else
    fail "tor@default.service non attivo"
    echo "  → Avvia con: sudo systemctl start tor@default.service"
    echo "  → I test successivi probabilmente falliranno"
fi

# ============================================================
section "2. Porte in ascolto"
# ============================================================

for port_info in "9050:SocksPort:tcp" "9051:ControlPort:tcp" "5353:DNSPort:udp"; do
    IFS=: read -r port name proto <<< "$port_info"
    flag="-tlnp"
    [ "$proto" = "udp" ] && flag="-ulnp"

    if ss $flag 2>/dev/null | grep -q ":${port} "; then
        pass "$name ($port/$proto) in ascolto"
    else
        fail "$name ($port/$proto) non in ascolto"
    fi
done

# ============================================================
section "3. Bootstrap"
# ============================================================

if journalctl -u tor@default.service --no-pager 2>/dev/null | grep -q "Bootstrapped 100%"; then
    pass "Bootstrap completato al 100%"
else
    fail "Bootstrap non al 100%"
fi

# ============================================================
section "4. Connessione via Tor"
# ============================================================

TOR_IP=$(curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://api.ipify.org 2>/dev/null || echo "")
if [ -n "$TOR_IP" ]; then
    pass "Connessione SOCKS5 funzionante (exit: $TOR_IP)"
else
    fail "Connessione SOCKS5 fallita"
fi

# Verifica IsTor
IS_TOR=$(curl --socks5-hostname 127.0.0.1:9050 -s --max-time 20 https://check.torproject.org/api/ip 2>/dev/null || echo "")
if echo "$IS_TOR" | grep -q '"IsTor":true'; then
    pass "IP confermato come exit Tor"
else
    fail "IP non riconosciuto come exit Tor"
fi

# ============================================================
section "5. ControlPort"
# ============================================================

if [ -r /run/tor/control.authcookie ]; then
    pass "Cookie di autenticazione leggibile"

    COOKIE=$(xxd -p /run/tor/control.authcookie 2>/dev/null | tr -d '\n')
    RESULT=$(printf "AUTHENTICATE %s\r\nGETINFO version\r\nQUIT\r\n" "$COOKIE" | \
             nc -w 5 127.0.0.1 9051 2>/dev/null || echo "")

    if echo "$RESULT" | grep -q "250"; then
        VERSION=$(echo "$RESULT" | grep "version=" | head -1 | cut -d= -f2)
        pass "Autenticazione ControlPort OK (Tor $VERSION)"
    else
        fail "Autenticazione ControlPort fallita"
    fi
else
    fail "Cookie non leggibile (sei nel gruppo debian-tor?)"
fi

# ============================================================
section "6. NEWNYM"
# ============================================================

if [ -r /run/tor/control.authcookie ]; then
    COOKIE=$(xxd -p /run/tor/control.authcookie 2>/dev/null | tr -d '\n')
    NEWNYM_RESULT=$(printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | \
                    nc -w 5 127.0.0.1 9051 2>/dev/null || echo "")

    if echo "$NEWNYM_RESULT" | grep -c "250 OK" | grep -q "2"; then
        pass "SIGNAL NEWNYM accettato"
    else
        fail "SIGNAL NEWNYM fallito"
    fi
else
    skip "NEWNYM (cookie non leggibile)"
fi

# ============================================================
section "7. ProxyChains"
# ============================================================

if command -v proxychains4 &>/dev/null || command -v proxychains &>/dev/null; then
    pass "proxychains installato"

    PC_IP=$(proxychains curl -s --max-time 20 https://api.ipify.org 2>/dev/null || echo "")
    if [ -n "$PC_IP" ]; then
        pass "proxychains funzionante (exit: $PC_IP)"
    else
        fail "proxychains non riesce a connettersi via Tor"
    fi
else
    skip "proxychains non installato"
fi

# ============================================================
section "8. torsocks"
# ============================================================

if command -v torsocks &>/dev/null; then
    pass "torsocks installato"

    TS_IP=$(torsocks curl -s --max-time 20 https://api.ipify.org 2>/dev/null || echo "")
    if [ -n "$TS_IP" ]; then
        pass "torsocks funzionante (exit: $TS_IP)"
    else
        fail "torsocks non riesce a connettersi via Tor"
    fi
else
    skip "torsocks non installato"
fi

# ============================================================
section "9. nyx"
# ============================================================

if command -v nyx &>/dev/null; then
    pass "nyx installato"
else
    skip "nyx non installato"
fi

# ============================================================
section "10. DNS via Tor"
# ============================================================

if command -v tor-resolve &>/dev/null; then
    RESOLVED=$(tor-resolve example.com 2>/dev/null || echo "")
    if [ -n "$RESOLVED" ]; then
        pass "tor-resolve funzionante (example.com → $RESOLVED)"
    else
        fail "tor-resolve fallito"
    fi
else
    skip "tor-resolve non disponibile"
fi

# ============================================================
echo ""
echo -e "${BOLD}=== RISULTATO ===${NC}"
echo -e "  ${GREEN}PASS:${NC} $PASS"
echo -e "  ${RED}FAIL:${NC} $FAIL"
echo -e "  ${YELLOW}SKIP:${NC} $SKIP"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}Tutti i test superati! Tor è completamente operativo.${NC}"
    exit 0
else
    echo -e "${RED}$FAIL test falliti. Controlla i problemi sopra.${NC}"
    exit 1
fi
