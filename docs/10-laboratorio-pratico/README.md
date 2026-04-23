> **Lingua / Language**: Italiano | [English](../en/10-laboratorio-pratico/README.md)

# Sezione 10 - Laboratorio Pratico

Cinque laboratori hands-on progressivi: dal setup base alla stream
isolation avanzata. Ogni lab include obiettivi, prerequisiti, comandi
da eseguire, verifica dei risultati e troubleshooting.

---

## Laboratori

| Lab | Documento | Contenuto |
|-----|-----------|-----------|
| 01 | [Setup e Verifica](lab-01-setup-e-verifica.md) | Installazione Tor, verifica connessione, ControlPort, primo NEWNYM |
| 02 | [Analisi Circuiti](lab-02-analisi-circuiti.md) | Nyx, ispezione circuiti, guard/middle/exit, NEWNYM e cambio circuito |
| 03 | [DNS Leak Testing](lab-03-dns-leak-testing.md) | Verifica DNS leak, tcpdump, DNSPort, iptables anti-leak |
| 04 | [Onion Service](lab-04-onion-service.md) | Creare un onion service v3, HiddenServiceDir, client authorization |
| 05 | [Stream Isolation](lab-05-stream-isolation.md) | IsolateSOCKSAuth, multi-SocksPort, verifica circuiti separati |

---

## Percorso consigliato

```
Lab 01 → Lab 02 → Lab 03 → Lab 04 → Lab 05
  ↓         ↓         ↓         ↓         ↓
Setup    Circuiti   DNS Leak  Onion Svc  Isolation
(base)   (analisi)  (difesa)  (server)   (avanzato)
```

Ogni lab è autocontenuto ma assume la conoscenza dei lab precedenti.

---

## Prerequisiti

- Kali Linux (o Debian-based) con Tor installato
- Accesso root per iptables e configurazione torrc
- `nyx`, `proxychains`, `torsocks`, `curl` installati
- Conoscenza base del terminale Linux

---

## Sezioni correlate

- [02 - Installazione e Configurazione](../02-installazione-e-configurazione/) - torrc, ControlPort, servizio
- [04 - Strumenti Operativi](../04-strumenti-operativi/) - proxychains, torsocks, Nyx, NEWNYM
- [05 - Sicurezza Operativa](../05-sicurezza-operativa/) - DNS leak, isolamento
- [06 - Configurazioni Avanzate](../06-configurazioni-avanzate/) - Stream isolation, multi-istanza
