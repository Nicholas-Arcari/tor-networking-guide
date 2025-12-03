# Rotazione IP con Tor – NEWNYM

## Obiettivo
Richiedere a Tor un nuovo circuito / IP senza riavviare il servizio.

---

## Esperienza personale
- Usando il ControlPort, ho creato uno script che legge il cookie di autenticazione.
- NEWNYM funziona solo se si rispetta il cooldown (~10s tra richieste).
- Permette test ripetuti su IP diversi, utile per debug o scraping anonimo.

Il comando `~/newnym` inizialmente dava errore:
`514 Authentication required`  
→ risolto inserendo l’utente nel gruppo `debian-tor`.

---

## Aggiungere utente al gruppo debian-tor
```bash
sudo usermod -aG debian-tor $USER           # poi bisogna riavviare la sessione del dispostivo
firefox -no-remote -CreateProfile tor-proxy # questo crea un profilo Firefox dedicato a Tor ed evita crash e conflitti con il profilo normale
```

---

## Script CLI
```bash
#!/bin/bash
COOKIE=$(xxd -p /run/tor/control.authcookie | tr -d '\n')
printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051
```

| Comando                              | Cosa fa                                   |
| ------------------------------------ | ----------------------------------------- |
| `xxd -p /run/tor/control.authcookie` | legge il cookie di autenticazione         |
| `printf "AUTHENTICATE ..."`          | invia il comando di autenticazione        |
| `SIGNAL NEWNYM`                      | chiede a Tor un nuovo circuito (nuovo IP) |
| `nc 127.0.0.1 9051`                  | comunica con il ControlPort via netcat    |


Successivamente eseguire (per comodità):

```bash
chmod +x ~/scripts/newnym
~/scripts/newnym
```

Ora non bisognerà più ceracre il percorso del file ma basta eseguire da cli: newnym

# Verifica
```bash
> newnym                                        # eseguire quando vuoi cambiare IP Tor senza riavviare o aspettare 10 min, oppure durante test, scraping, anonimizzazione
250 OK
250 closing connection

> proxychains curl https://api.ipify.org
[proxychains] config file found: /etc/proxychains4.conf
[proxychains] preloading /usr/lib/x86_64-linux-gnu/libproxychains.so.4
[proxychains] DLL init: proxychains-ng 4.17
[proxychains] Dynamic chain  ...  127.0.0.1:9050  ...  api.ipify.org:443  ...  OK
185.220.101.143                                 # questo è il nodo Tor appena modificato dal comando precedente
```