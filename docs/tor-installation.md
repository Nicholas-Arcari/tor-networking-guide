# Tor – Installazione e avvio su Kali Linux

## Obiettivo
Installare Tor e farlo funzionare come servizio, pronto per l’uso con bridges e obfs4.

---

## Esperienza personale
- Ho aggiornato i repository Kali e installato `tor` e `obfs4proxy`.
- Tor era già alla versione più recente.
- obfs4proxy serve per offuscare il traffico e aggirare blocchi, DPI o restrizioni ISP.

---

## Comandi eseguiti

```bash
sudo apt update                                             # aggiorna la lista dei pacchetti disponibili, da eseguire per evitare errori di pacchetti obsoleti o mancanti
sudo apt install tor obfs4proxy                             # installa Tor e il plugin per obfs4 (offuscazione traffico), obfs4 serve per i bridges, utili in reti censurate
sudo systemctl restart tor@default.service                  # ricarica la configurazione e riavvia Tor, da eseguire ogni qualvolta dopo modifiche al torrc
systemctl status tor@default.service                        # mostra se il servizio è attivo, errori, PID, log, da eseguire per capire se Tor sta funzionando o perché non parte
sudo -u debian-tor tor -f /etc/tor/torrc --verify-config    # verifica che il file torrc sia scritto correttamente
```