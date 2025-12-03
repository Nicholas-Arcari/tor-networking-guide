# Controllo dell’IP pubblico (normale e attraverso Tor)

## Esperienza personale

Ho verificato più volte il mio IP reale e l’IP Tor.
Senza proxy il mio IP era italiano (Parma).
Con ProxyChains appariva un IP straniero fornito dal circuito Tor.

L’uso contemporaneo di Tor + VPN + bridges era inutile, perché Tor effettua tunneling completo e ignora la rete esterna.

---

## Controllare l’IP reale (senza Tor)

### Metodo 1 – tramite api.ipify.org

```bash
> curl https://api.ipify.org
xxx.xxx.xxx.xxx                         # censurata per ovvi motivi
```

### Metodo 2 – tramite api.ipinfo.org

Simile al precedente, offre semplicemente info dettagliate

```bash
> curl https://api.ipinfo.org
{
  "ip": "xxx.xxx.xxx.xxx",              # censurata per ovvi motivi
  "city": "Parma",
  "region": "Emilia-Romagna",
  "country": "IT",
  "loc": "xx.xx,xx.xx",                 # censurata per ovvi motivi
  "org": "ASxxx Comeser S.r.l.", 	      # censurata per ovvi motivi
  "postal": "43100",
  "timezone": "Europe/Rome",
  "readme": "https://ipinfo.io/missingauth"
}

```

## Controllare l’IP reale (con Tor)

### Tramite ProxyChains

```bash
> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
109.70.100.6 
```

Cosa succede?

- La richiesta passa a ProxyChains
- ProxyChains usa socks5 → 127.0.0.1:9050
- Tor crea un circuito → nuovo IP anonimo

Quando farlo?

- per verificare NEWNYM
- dopo modifiche alla configurazione Tor
- per test anonimato prima di visitare siti web

# riassunto
```bash
curl https://api.ipify.org              # mostra il mio IP reale
proxychains curl https://api.ipify.org  # mostra l’IP di uscita Tor
```

## Check se le porte sono in ascolto
```bash
sudo netstat -tlnp | grep -E "9050|9051|5353"
```

dovrebbe uscire qualcosa tipo:
```bash
tcp   0 0 127.0.0.1:9050  ...  tor
tcp   0 0 127.0.0.1:9051  ...  tor
udp   0 0 127.0.0.1:5353  ...  tor
```