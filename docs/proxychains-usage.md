# Uso di ProxyChains con Tor

## Esperienza personale
Ho utilizzato ProxyChains per forzare applicazioni come `curl` a passare dentro Tor.  
La prima cosa che ho notato è che, quando il servizio Tor non era in esecuzione, ProxyChains bloccava ogni connessione restituendo: !!! need more proxies !!!


Questo perché ProxyChains tentava di collegarsi al SocksPort (9050), ma Tor non era attivo.

Una volta avviato Tor correttamente ed eseguito NEWNYM, ProxyChains ha iniziato a funzionare subito.

---

## Configurazione ProxyChains

### Aprire il file di configurazione
```bash
sudo nano /etc/proxychains4.conf
```

# Aggiunte Principali
dynamic_chain               # Se un proxy fallisce, passa automaticamente al successivo
proxy_dns                   # Impedisce DNS leak (obbligatorio per privacy!)
tcp_read_time_out 15000
tcp_connect_time_out 8000
[ProxyList]
socks5 127.0.0.1 9050       # Tor come unico proxy

# Verifica
```bash
proxychains curl https://api.ipify.org      # mostra l’IP pubblico usato attraverso Tor, questo dopo aver lanciato NEWNYM o modificato torrc.
```

Se Tor fosse spento uscirebbe questo messaggio a linea di comando:

timeout

!!! need more proxies !!!

soluzione:
```bash
sudo systemctl start tor@default.service
```