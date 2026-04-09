# Configurazione Bridge, meek, Snowflake e Confronto

Configurazione dei bridge nel torrc, debug del bootstrap, meek (CDN),
Snowflake (peer-to-peer) e confronto tra pluggable transports.

Estratto da [Bridges e Pluggable Transports](bridges-e-pluggable-transports.md).

---

## Indice

- [Configurazione dei bridge nel torrc](#configurazione-dei-bridge-nel-torrc)
- [meek - Incapsulamento in CDN](#meek--incapsulamento-in-cdn)
- [Snowflake - Bridge peer-to-peer](#snowflake--bridge-peer-to-peer)
- [Confronto tra i Pluggable Transport](#confronto-tra-i-pluggable-transport)

---

## Configurazione dei bridge nel torrc

### Configurazione completa

```ini
# Abilitare bridge
UseBridges 1

# Registrare il pluggable transport
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy

# Bridge (sostituire con valori reali)
Bridge obfs4 198.51.100.42:4431 AABBCCDD... cert=BASE64CERT... iat-mode=0
Bridge obfs4 203.0.113.88:13630 EEFFGGHH... cert=BASE64CERT... iat-mode=2
```

### Regole per le righe Bridge

- Il formato è rigido: `Bridge <transport> <IP>:<PORT> <FINGERPRINT> <parametri>`
- **Nessuno spazio** all'inizio della riga
- Il fingerprint è esadecimale, senza separatori (40 hex char per SHA-1)
- `cert=` è base64 senza spazi
- `iat-mode=` accetta 0, 1, o 2
- Si possono specificare più bridge: Tor li prova in ordine e usa il primo che risponde

### Verifica e debug

```bash
# Verificare la configurazione
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config

# Riavviare e monitorare
sudo systemctl restart tor@default.service
sudo journalctl -u tor@default.service -f
```

**Output di successo**:
```
Bootstrapped 5% (conn): Connecting to a relay
Bootstrapped 10% (conn_done): Connected to a relay
... (progressione fino a 100%)
Bootstrapped 100% (done): Done
```

**Output di fallimento**:
```
Bootstrapped 5% (conn): Connecting to a relay
[warn] Problem bootstrapping. Stuck at 5% (conn). (Connection timed out;
  NOROUTE; count 1; recommendation warn; host AABBCCDD at 198.51.100.42:4431)
```

Se vedo `Connection timed out` per tutti i bridge:
1. Verifico che `obfs4proxy` sia installato e eseguibile
2. Verifico che il formato dei bridge sia corretto
3. Testo la raggiungibilità dell'IP: `nc -zv 198.51.100.42 4431 -w 5`
4. Se tutto OK, i bridge sono probabilmente saturi → richiederne di nuovi

---

## meek - Incapsulamento in CDN

### Come funziona

meek nasconde il traffico Tor all'interno di connessioni HTTPS normali verso CDN
come Amazon CloudFront o Microsoft Azure:

```
[Client] ──HTTPS──► [Amazon CloudFront] ──► [meek bridge] ──► [Tor Network]
```

Il censore vede solo una connessione HTTPS verso `d2cly7j4zqgua7.cloudfront.net`
(Amazon). Bloccare questo significherebbe bloccare tutto Amazon CloudFront,
causando danni collaterali enormi. Questo è il principio del **domain fronting**.

### Limiti di meek

- **Lento**: il traffico passa attraverso una CDN → latenza aggiuntiva
- **Costoso**: il Tor Project paga per l'hosting sulle CDN
- **Domain fronting in declino**: alcuni provider (Google, Amazon) hanno limitato
  il domain fronting

### Configurazione

```ini
UseBridges 1
ClientTransportPlugin meek_lite exec /usr/bin/obfs4proxy
Bridge meek_lite 192.0.2.18:80 ... url=https://meek.azureedge.net/ front=ajax.aspnetcdn.com
```

---

## Snowflake - Bridge peer-to-peer

### Come funziona

Snowflake usa volontari che eseguono un'estensione del browser come "proxy":

```
[Client] ──WebRTC──► [Volontario browser] ──► [Snowflake bridge] ──► [Tor Network]
```

1. Il client contatta un broker (tramite domain fronting) per trovare un volontario
2. Stabilisce una connessione WebRTC con il volontario
3. Il traffico Tor viene incapsulato nel canale WebRTC
4. Il volontario lo inoltra al bridge Snowflake
5. Il bridge lo immette nella rete Tor

### Vantaggi

- I "bridge" sono milioni di browser di volontari → impossibile bloccarli tutti
- Nessuna configurazione manuale dei bridge necessaria
- Funziona anche in paesi con censura estrema

### Svantaggi

- Dipende dalla disponibilità dei volontari
- Banda limitata dalla connessione del volontario
- WebRTC può avere problemi di NAT traversal
- Latenza variabile

---

## Confronto tra i Pluggable Transport

| Caratteristica | obfs4 | meek | Snowflake |
|---------------|-------|------|-----------|
| Resistenza DPI | Alta | Molto alta | Alta |
| Active probing resistance | Alta | Molto alta | Alta |
| Velocità | Buona | Scarsa | Variabile |
| Stabilità | Buona | Buona | Media |
| Facilità config | Media | Media | Facile |
| Necessita bridge manuali | Si | No | No |
| Collateral damage per censore | Basso | Alto (bloccare CDN) | Alto (bloccare WebRTC) |
| Disponibilità | Dipende dai bridge | Limitato da costi | Dipende dai volontari |

### La mia scelta

Uso obfs4 perché:
- Offre il miglior compromesso tra velocità e sicurezza
- Ho bridge configurati e funzionanti
- Su reti universitarie dove l'ho testato, è stato sufficiente
- Non ho bisogno del livello di anti-censura di meek/Snowflake (non sono in Cina/Iran)

Per scenari di censura estrema, meek o Snowflake sarebbero la scelta migliore perché
non richiedono bridge specifici che possono essere scoperti e bloccati.

---

## Vedi anche

- [Bridges e Pluggable Transports](bridges-e-pluggable-transports.md) - Perché bridge, obfs4, resistenza censura
- [torrc - Guida Completa](../02-installazione-e-configurazione/torrc-guida-completa.md) - Configurazione bridge
- [Traffic Analysis](../05-sicurezza-operativa/traffic-analysis.md) - DPI e bridge
- [VPN e Tor Ibrido](../06-configurazioni-avanzate/vpn-e-tor-ibrido.md) - Bridge vs VPN
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
