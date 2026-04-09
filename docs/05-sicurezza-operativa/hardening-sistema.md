# Hardening di Sistema per l'Uso di Tor

Questo documento copre le misure di hardening a livello di sistema operativo per
massimizzare la sicurezza quando si usa Tor. Include configurazione kernel, firewall,
profili AppArmor, servizi da disabilitare, e prevenzione leak a livello OS.

> **Vedi anche**: [DNS Leak](./dns-leak.md) per la prevenzione DNS,
> [Isolamento e Compartimentazione](./isolamento-e-compartimentazione.md) per VM/container,
> [OPSEC e Errori Comuni](./opsec-e-errori-comuni.md) per errori operativi,
> [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) per iptables.

---

## Indice

- [Panoramica del threat model](#panoramica-del-threat-model)
- [Kernel hardening - sysctl](#kernel-hardening--sysctl)
- [Firewall - nftables/iptables](#firewall--nftablesiptables)
- [Disabilitare IPv6](#disabilitare-ipv6)
- [AppArmor per Tor](#apparmor-per-tor)
**Approfondimenti** (file dedicati):
- [Hardening Avanzato](hardening-avanzato.md) - Servizi, rete, filesystem, logging, Firefox, checklist

---

## Panoramica del threat model

L'hardening di sistema protegge da:

| Minaccia | Senza hardening | Con hardening |
|----------|----------------|---------------|
| DNS leak via UDP | Possibile | Bloccato (iptables) |
| IPv6 leak | Possibile | Bloccato (sysctl + iptables) |
| Servizi che comunicano in chiaro | Attivi di default | Disabilitati |
| Kernel info leak | Esposto | Ridotto (sysctl) |
| Traffic correlation via timing | Possibile | Ridotto (disabilita NTP leak) |
| Crash dump con dati sensibili | Attivo | Disabilitato |
| File temporanei su disco | Persistenti | tmpfs / shred |

---

## Kernel hardening - sysctl

### Parametri di rete

```bash
# /etc/sysctl.d/99-tor-hardening.conf

# --- IPv6: disabilitare completamente ---
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# --- Prevenire leak di informazioni di rete ---
# Disabilitare ICMP redirect (potrebbe bypassare routing Tor)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Disabilitare source routing (attacco per bypassare routing)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Attivare reverse path filtering (anti-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignorare broadcast ICMP (prevenzione smurf attack)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignorare ICMP bogus error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disabilitare IP forwarding (a meno che non sia gateway Tor)
net.ipv4.ip_forward = 0

# Log pacchetti marziani (impossibili)
net.ipv4.conf.all.log_martians = 1
```

### Parametri kernel generici

```bash
# --- Protezione kernel ---
# Nascondere puntatori kernel nei log
kernel.kptr_restrict = 2

# Restringere accesso a dmesg
kernel.dmesg_restrict = 1

# Disabilitare SysRq (prevenire dump)
kernel.sysrq = 0

# Restringere ptrace (prevenire attach ai processi)
kernel.yama.ptrace_scope = 2

# ASLR massimo
kernel.randomize_va_space = 2

# Disabilitare core dump (potrebbero contenere dati sensibili)
fs.suid_dumpable = 0
```

### Applicare

```bash
# Applicare immediatamente
sudo sysctl --system

# Verificare
sysctl net.ipv6.conf.all.disable_ipv6
# net.ipv6.conf.all.disable_ipv6 = 1
```

---

## Firewall - nftables/iptables

### Strategia: deny-all, allow-Tor

L'obiettivo è bloccare TUTTO il traffico che non passa da Tor:

```bash
#!/bin/bash
# tor-firewall.sh - Firewall restrittivo per uso Tor

TOR_UID=$(id -u debian-tor)

# === OUTPUT: cosa può uscire ===

# Flush
iptables -F OUTPUT

# Permetti traffico di Tor (il daemon stesso)
iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT

# Permetti localhost (ControlPort, SocksPort, DNSPort)
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT

# Permetti LAN (opzionale, per DHCP, stampanti, NAS)
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# Blocca TUTTO il resto
iptables -A OUTPUT -j LOG --log-prefix "[TOR-FW-DROP] " --log-level 4
iptables -A OUTPUT -j DROP

# === IPv6: blocca tutto ===
ip6tables -F OUTPUT
ip6tables -A OUTPUT -j DROP

echo "Firewall Tor attivo. Solo traffico via Tor permesso."
```

### Differenza con il transparent proxy

```
Transparent proxy:
  → Tutto il traffico TCP viene RIDIREZIONATO a Tor (TransPort)
  → Le app non sanno di usare Tor
  → UDP bloccato

Firewall restrittivo:
  → Il traffico diretto viene BLOCCATO
  → Le app devono essere configurate per usare SocksPort
  → Se un'app non usa il proxy → connessione bloccata → NO leak
  → Approccio più conservativo
```

Il firewall restrittivo è un **complemento** a proxychains/torsocks, non un
sostituto. Cattura tutto ciò che sfugge al wrapper LD_PRELOAD.

### Regole per scenari specifici

```bash
# Permettere NTP (accettare il leak di timing per avere orologio corretto)
iptables -I OUTPUT -p udp --dport 123 -j ACCEPT

# Permettere apt update senza Tor (molto più veloce)
APT_UID=$(id -u _apt)
iptables -I OUTPUT -m owner --uid-owner $APT_UID -j ACCEPT

# Permettere un utente specifico di bypassare il firewall
iptables -I OUTPUT -m owner --uid-owner 1001 -j ACCEPT
```

---

## Disabilitare IPv6

IPv6 è un vettore di leak critico perché:
- Tor ha supporto IPv6 limitato (client-side)
- iptables non copre IPv6 (serve ip6tables separato)
- Molte applicazioni preferiscono IPv6 quando disponibile

### Metodo completo

```bash
# 1. sysctl (già visto sopra)
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1

# 2. ip6tables (blocco a livello firewall)
sudo ip6tables -P INPUT DROP
sudo ip6tables -P OUTPUT DROP
sudo ip6tables -P FORWARD DROP

# 3. GRUB (disabilita a livello kernel boot)
# /etc/default/grub:
# GRUB_CMDLINE_LINUX="ipv6.disable=1"
# sudo update-grub

# 4. Verificare
ip -6 addr show
# Nessun output = IPv6 disabilitato

cat /proc/sys/net/ipv6/conf/all/disable_ipv6
# 1
```

---

## AppArmor per Tor

### Profilo AppArmor per Tor daemon

Kali/Debian include un profilo AppArmor per Tor. Verificare:

```bash
# Stato AppArmor
sudo aa-status | grep tor
# /usr/bin/tor (enforce)

# Se non attivo:
sudo aa-enforce /etc/apparmor.d/system_tor
```

### Cosa limita il profilo

Il profilo AppArmor per Tor:
- Limita l'accesso filesystem: solo `/var/lib/tor/`, `/var/log/tor/`, config
- Impedisce l'accesso a home directory, `/tmp`, e altri percorsi
- Limita le capability di rete
- Impedisce l'accesso ad altri processi

### Profilo personalizzato più restrittivo

```
# /etc/apparmor.d/local/system_tor
# Override locale per restrizioni aggiuntive

# Negare accesso a device
deny /dev/** rw,

# Negare accesso a proc (tranne necessario)
deny /proc/*/maps r,
deny /proc/*/status r,

# Permettere solo le porte necessarie
network tcp,
# Implicitamente nega raw socket, UDP (tranne DNS interno)
```


---

> **Continua in**: [Hardening Avanzato](hardening-avanzato.md) per servizi da
> disabilitare, MAC/hostname randomization, filesystem, logging e hardening Firefox.

---

## Vedi anche

- [Hardening Avanzato](hardening-avanzato.md) - Servizi, rete, filesystem, Firefox, checklist
- [DNS Leak](dns-leak.md) - Prevenzione DNS leak con firewall
- [Isolamento e Compartimentazione](isolamento-e-compartimentazione.md) - Whonix, Tails, network namespaces
- [Transparent Proxy](../06-configurazioni-avanzate/transparent-proxy.md) - iptables/nftables per Tor system-wide
- [OPSEC e Errori Comuni](opsec-e-errori-comuni.md) - Hardening come parte dell'OPSEC
- [Analisi Forense e Artefatti](analisi-forense-e-artefatti.md) - Ridurre artefatti con hardening
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
