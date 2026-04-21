> **Lingua / Language**: Italiano | [English](../en/06-configurazioni-avanzate/README.md)

# Sezione 06 - Configurazioni Avanzate

Transparent proxy, VPN+Tor ibrido, multi-istanza con stream isolation
e gestione localhost/Docker: configurazioni avanzate per scenari
operativi specifici.

---

## Documenti

### Transparent proxy

| Documento | Contenuto |
|-----------|-----------|
| [Transparent Proxy](transparent-proxy.md) | TransPort, iptables riga per riga, nftables, IPv6, meccanismo kernel |
| [Transparent Proxy Avanzato](transparent-proxy-avanzato.md) | Gateway LAN, troubleshooting, hardening, script production-ready, confronto Whonix/Tails |

### VPN e Tor

| Documento | Contenuto |
|-----------|-----------|
| [VPN e Tor - Configurazioni Ibride](vpn-e-tor-ibrido.md) | Tor vs VPN, VPN→Tor, Tor→VPN (sconsigliato), TransPort quasi-VPN |
| [VPN e Tor - Routing, DNS e Kill Switch](vpn-tor-routing-e-dns.md) | Routing selettivo, DNS ibride, kill switch, WireGuard/OpenVPN, ExitNodes |

### Multi-istanza e isolamento

| Documento | Contenuto |
|-----------|-----------|
| [Multi-Istanza e Stream Isolation](multi-istanza-e-stream-isolation.md) | Modello minaccia, systemd templates, architetture, flag isolamento |
| [Stream Isolation Avanzato](stream-isolation-avanzato.md) | Tor Browser SOCKS auth, SessionGroup, curl/Python, gestione operativa |

### Localhost e Docker

| Documento | Contenuto |
|-----------|-----------|
| [Tor e Localhost](tor-e-localhost.md) | Problema localhost, Local Service Discovery attack, blocco tecnico, soluzioni |
| [Tor e Localhost - Docker e Sviluppo](localhost-docker-e-sviluppo.md) | Docker via Tor, sviluppo web locale, onion services, matrice compatibilità |

### Scenari operativi

| Documento | Contenuto |
|-----------|-----------|
| [Scenari Reali](scenari-reali.md) | Casi pratici: transparent proxy in engagement, stream isolation leak, VPN+Tor failure |

---

## Sezioni correlate

- [02 - Installazione e Configurazione](../02-installazione-e-configurazione/) - torrc per TransPort, SocksPort, DNSPort
- [04 - Strumenti Operativi](../04-strumenti-operativi/) - proxychains, torsocks, ControlPort
- [05 - Sicurezza Operativa](../05-sicurezza-operativa/) - DNS leak, isolamento, hardening
- [10 - Laboratorio Pratico](../10-laboratorio-pratico/) - Lab-05 (stream isolation)
