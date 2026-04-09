#!/bin/bash
# setup.sh - Installa e configura Tor + strumenti su Kali/Debian
#
# Questo script:
# 1. Installa Tor, obfs4proxy, proxychains4, torsocks, nyx, stem
# 2. Configura torrc con SocksPort, DNSPort, ControlPort, bridge
# 3. Aggiunge l'utente al gruppo debian-tor
# 4. Crea il profilo Firefox tor-proxy
# 5. Copia gli script di gestione
#
# Uso: sudo ./setup.sh
# ATTENZIONE: richiede root per installazione pacchetti e configurazione

set -euo pipefail

# Colori
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; }
section() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

# --- Verifica root ---
if [ "$EUID" -ne 0 ]; then
    err "Questo script richiede root. Esegui con: sudo ./setup.sh"
    exit 1
fi

# Utente reale (non root)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║     Tor Networking Guide - Setup Script      ║"
echo "║     Kali Linux / Debian                      ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"
echo "Utente: $REAL_USER"
echo "Home:   $REAL_HOME"
echo "Script: $SCRIPT_DIR"
echo ""

# ============================================================
section "1. Installazione pacchetti"
# ============================================================

apt-get update -qq

PACKAGES=(tor tor-geoipdb obfs4proxy proxychains4 torsocks nyx curl netcat-openbsd xxd)
INSTALLED=0
SKIPPED=0

for pkg in "${PACKAGES[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        log "$pkg: già installato"
        SKIPPED=$((SKIPPED+1))
    else
        apt-get install -y -qq "$pkg"
        log "$pkg: installato"
        INSTALLED=$((INSTALLED+1))
    fi
done

# Stem (Python library per ControlPort)
if python3 -c "import stem" 2>/dev/null; then
    log "stem (Python): già installato"
else
    pip3 install stem 2>/dev/null || apt-get install -y -qq python3-stem
    log "stem (Python): installato"
fi

echo ""
log "Pacchetti: $INSTALLED installati, $SKIPPED già presenti"

# ============================================================
section "2. Configurazione torrc"
# ============================================================

TORRC="/etc/tor/torrc"
TORRC_BACKUP="/etc/tor/torrc.backup.$(date +%s)"

# Backup
if [ -f "$TORRC" ]; then
    cp "$TORRC" "$TORRC_BACKUP"
    log "Backup torrc salvato in $TORRC_BACKUP"
fi

# Configurazione base (preserva il file se già configurato)
if grep -q "SocksPort 9050" "$TORRC" 2>/dev/null; then
    log "torrc già configurato, non sovrascrivo"
else
    # Copiare template se disponibile
    if [ -f "$SCRIPT_DIR/config-examples/torrc/torrc-client.example" ]; then
        cp "$SCRIPT_DIR/config-examples/torrc/torrc-client.example" "$TORRC"
        log "torrc copiato da template client"
    else
        cat > "$TORRC" << 'TORRC_CONTENT'
## torrc - Configurazione client Tor
## Generato da setup.sh

# Porta SOCKS5 per le applicazioni
SocksPort 9050

# DNS via Tor
DNSPort 5353
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10

# ControlPort per nyx, stem, newnym
ControlPort 9051
CookieAuthentication 1

# Disabilitare IPv6
ClientUseIPv6 0

# Logging
Log notice file /var/log/tor/notices.log

# Padding per resistenza traffic analysis
ConnectionPadding 1
TORRC_CONTENT
        log "torrc scritto con configurazione base"
    fi
fi

# Permessi
chown debian-tor:debian-tor "$TORRC"
chmod 644 "$TORRC"

# ============================================================
section "3. Configurazione proxychains"
# ============================================================

PROXYCHAINS_CONF="/etc/proxychains4.conf"

if [ -f "$PROXYCHAINS_CONF" ]; then
    # Verificare che proxy_dns sia attivo
    if grep -q "^#proxy_dns" "$PROXYCHAINS_CONF"; then
        sed -i 's/^#proxy_dns/proxy_dns/' "$PROXYCHAINS_CONF"
        log "proxy_dns abilitato in proxychains4.conf"
    else
        log "proxychains4.conf: proxy_dns già attivo"
    fi

    # Verificare che socks5 127.0.0.1 9050 sia nella lista
    if ! grep -q "socks5.*127.0.0.1.*9050" "$PROXYCHAINS_CONF"; then
        echo "socks5 127.0.0.1 9050" >> "$PROXYCHAINS_CONF"
        log "Aggiunto socks5 127.0.0.1 9050 a proxychains4.conf"
    else
        log "proxychains4.conf: proxy Tor già configurato"
    fi
fi

# ============================================================
section "4. Gruppo debian-tor"
# ============================================================

if id -nG "$REAL_USER" | grep -qw "debian-tor"; then
    log "$REAL_USER già nel gruppo debian-tor"
else
    usermod -aG debian-tor "$REAL_USER"
    log "$REAL_USER aggiunto al gruppo debian-tor"
    warn "Necessario logout/login per attivare il gruppo"
fi

# ============================================================
section "5. Profilo Firefox tor-proxy"
# ============================================================

if [ -f "$SCRIPT_DIR/scripts/setup-tor-profile.sh.example" ]; then
    # Esegui come utente reale (non root)
    su - "$REAL_USER" -c "bash '$SCRIPT_DIR/scripts/setup-tor-profile.sh.example'" 2>/dev/null || \
        warn "Creazione profilo Firefox: esegui manualmente scripts/setup-tor-profile.sh.example"
else
    warn "Script setup-tor-profile.sh.example non trovato, skip"
fi

# ============================================================
section "6. Script operativi"
# ============================================================

SCRIPTS_DEST="$REAL_HOME/scripts"
mkdir -p "$SCRIPTS_DEST"

# Copiare script (senza .example)
for script in "$SCRIPT_DIR/scripts/"*.example; do
    if [ -f "$script" ]; then
        BASENAME=$(basename "$script" .example)
        cp "$script" "$SCRIPTS_DEST/$BASENAME"
        chmod +x "$SCRIPTS_DEST/$BASENAME"
        log "Copiato: $BASENAME → $SCRIPTS_DEST/$BASENAME"
    fi
done

chown -R "$REAL_USER:$REAL_USER" "$SCRIPTS_DEST"

# ============================================================
section "7. Avvio e verifica Tor"
# ============================================================

# Abilitare e avviare Tor
systemctl enable tor@default.service 2>/dev/null
systemctl restart tor@default.service

log "Tor avviato. Attendo bootstrap..."

# Attendere bootstrap (max 60 secondi)
for i in $(seq 1 60); do
    if journalctl -u tor@default.service --no-pager 2>/dev/null | grep -q "Bootstrapped 100%"; then
        log "Bootstrap completato!"
        break
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        warn "Bootstrap non completato in 60s. Controlla: sudo journalctl -u tor@default.service"
    fi
done

# Verifica porte
PORTS_OK=true
for port in 9050 9051; do
    if ss -tlnp | grep -q ":${port} "; then
        log "Porta $port: in ascolto"
    else
        err "Porta $port: NON in ascolto"
        PORTS_OK=false
    fi
done

# ============================================================
section "Riepilogo"
# ============================================================

echo ""
echo -e "${BOLD}Installazione completata!${NC}"
echo ""
echo "Comandi rapidi:"
echo "  sudo systemctl start tor@default.service    # Avviare Tor"
echo "  proxychains curl https://api.ipify.org       # Verificare IP"
echo "  ~/scripts/newnym-with-verify.sh              # Cambiare IP"
echo "  nyx                                          # Monitor TUI"
echo "  proxychains firefox -no-remote -P tor-proxy & # Browser anonimo"
echo ""

if ! id -nG "$REAL_USER" | grep -qw "debian-tor"; then
    warn "IMPORTANTE: fai logout e login per attivare il gruppo debian-tor"
fi

echo -e "${GREEN}Setup completato.${NC}"
