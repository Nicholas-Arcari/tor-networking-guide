# Configurazione torrc con bridges obfs4

## Obiettivo

Configurare Tor per:

- funzionare con ProxyChains
- usare bridges obfs4
- evitare leak IPv6
- avere il controllo del circuito Tor via ControlPort

---

## Esperienza personale

- Ho provato a prendere un bridge dal sito ufficiale Tor: `https://bridges.torproject.org/bridges` (generatomi da ChatGPT). Non funzionava, quindi ho utilizzato bridges pubblici già disponibili.
- Ho provato un setup "ibrido" con `UseBridges` e connessione normale via Tor da un altro paese: non compatibile con la migration IP perché Tor cerca di mantenere il circuito stabile su quella exit.
  → Conclusione: bridges e routing da un altro paese vanno usati separatamente.

---

## Modifica torrc

```bash
sudo nano /etc/tor/torrc                                    # apre il file di configurazione principale di Tor, farlo per configurare bridges, porte, DNS, ControlPort
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config    # da eseguire se  i bridges cambiano, se Tor non parte
sudo systemctl restart tor@default.service                  # da eseguire se vuoi abilitare obfs4 
journalctl -u tor@default.service -f                        # mostra i log in tempo reale, serve per vedere se i bridges si connettono
```

# Aggiunte principali

SocksPort 9050              # Permette ai programmi (es. ProxyChains) di connettersi alla rete Tor
DNSPort 5353                # Tor intercetta le richieste DNS → evita DNS leak
AutomapHostsOnResolve 1     # Risolve automaticamente richieste DNS attraverso Tor
ClientUseIPv6 0             # Disabilita IPv6 per evitare leak

DataDirectory /var/lib/tor  # Deve essere accessibile solo all’utente debian-tor

ControlPort 9051            # Apre una porta di controllo usata per NEWNYM
CookieAuthentication 1      # Usa un file cookie per autenticare i comandi al ControlPort

UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy # /usr/bin/obfs4proxy deve essere eseguibile

# Esempio di bridge

Bridge obfs4 xxx.xxx.xxx.xxx:4431 F829D39509... cert=... iat-mode=0
  → sostituire xxx con indirizzo IPv4 dato dal sito ufficiale Tor, sostituire ... con informazioni date dal sito ufficiale Tor
  → aggirano blocchi Tor, camuffano il traffico tramite offuscamento.
