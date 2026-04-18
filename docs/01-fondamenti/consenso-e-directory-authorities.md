> **Lingua / Language**: Italiano | [English](../en/01-fondamenti/consenso-e-directory-authorities.md)

# Consenso e Directory Authorities - Il Sistema Nervoso di Tor

Questo documento analizza in dettaglio come la rete Tor mantiene una visione condivisa
del proprio stato: il meccanismo del consenso, il ruolo delle Directory Authorities,
il processo di votazione, i descriptor dei relay, e le implicazioni per la sicurezza.

Include osservazioni dalla mia esperienza nell'analisi dei log di Tor durante il
bootstrap e nella comprensione di perché certi relay vengono selezionati.

---
---

## Indice

- [Perché serve un consenso?](#perché-serve-un-consenso)
- [Directory Authorities - Chi sono e cosa fanno](#directory-authorities-chi-sono-e-cosa-fanno)
- [Il processo di votazione - Ora per ora](#il-processo-di-votazione-ora-per-ora)
- [Struttura del documento di consenso](#struttura-del-documento-di-consenso)
- [Flag del consenso - Analisi approfondita](#flag-del-consenso-analisi-approfondita)
- [Bandwidth Authorities e misurazione della banda](#bandwidth-authorities-e-misurazione-della-banda)
- [Server Descriptors - L'identità di un relay](#server-descriptors-lidentità-di-un-relay)
- [Microdescriptor vs Server Descriptor](#microdescriptor-vs-server-descriptor)
- [Cache del consenso e persistenza](#cache-del-consenso-e-persistenza)
- [Attacchi al sistema del consenso](#attacchi-al-sistema-del-consenso)
- [Consultare il consenso manualmente](#consultare-il-consenso-manualmente)
- [Riepilogo](#riepilogo)


## Perché serve un consenso?

Tor è una rete decentralizzata di ~7000 relay volontari. Il client deve sapere:

- Quali relay esistono e sono attivi
- Quali sono i loro indirizzi IP e porte
- Quali chiavi pubbliche usano (per l'handshake ntor)
- Quanto bandwidth offrono (per la selezione pesata)
- Quale exit policy hanno (per scegliere l'exit corretto)
- Quali flag hanno (Guard, Exit, Stable, Fast, etc.)

Senza queste informazioni, il client non può costruire circuiti. Il **consenso** è il
documento che contiene tutto questo.

---

## Directory Authorities - Chi sono e cosa fanno

### Le 9 Directory Authorities

Le DA sono server hardcoded nel codice sorgente di Tor. Al momento della scrittura,
sono gestite da:

| Nome | Operatore | Giurisdizione |
|------|-----------|---------------|
| moria1 | MIT (Roger Dingledine) | USA |
| tor26 | Peter Palfrader | Austria |
| dizum | Alex de Joode | Paesi Bassi |
| Serge | Serge Hallyn | USA |
| gabelmoo | Sebastian Hahn | Germania |
| dannenberg | CCC | Germania |
| maatuska | Linus Nordberg | Svezia |
| Faravahar | Sina Rabbani | USA |
| longclaw | Riseup | USA |

Queste 9 autorità **votano ogni ora** per produrre il consenso. Il consenso è valido
solo se firmato da almeno **5 delle 9** DA (maggioranza semplice).

### Bridge Authority

Esiste anche una **bridge authority** separata (attualmente `Serge` ha anche questo ruolo)
che gestisce il database dei bridge. I bridge non compaiono nel consenso pubblico -
sono distribuiti tramite `https://bridges.torproject.org` e altri canali.

### Fallback Directories

Per ridurre il carico sulle DA durante il bootstrap iniziale, Tor include una lista di
**fallback directory mirrors** hardcoded. Questi sono relay normali con flag `V2Dir` che
hanno una copia del consenso. Il client li usa per il primo download, poi passa alle DA.

Nella mia esperienza, il bootstrap usa quasi sempre i fallback. Lo vedo nei log:
```
Bootstrapped 5% (conn): Connecting to a relay
```
Quel "relay" è un fallback directory, non una DA. Le DA vengono contattate direttamente
solo se i fallback non rispondono.

---

## Il processo di votazione - Ora per ora

Ogni ora, il consenso viene rinnovato. Il processo è:

### Fase 1: Pubblicazione dei voti (T+0 min)

Ogni DA produce il proprio **voto** basandosi sui relay che ha testato:

```
Il voto di una singola DA contiene:
- Lista di tutti i relay noti alla DA
- Flag assegnati a ciascun relay
- Bandwidth misurata (se la DA è anche bandwidth authority)
- Timestamp di validità
- Firma della DA
```

I voti vengono pubblicati e condivisi tra le DA.

### Fase 2: Calcolo del consenso (T+5 min)

Ogni DA calcola il consenso combinando tutti i voti ricevuti:

1. **Per ogni relay**: viene incluso nel consenso solo se **almeno la metà delle DA**
   che hanno votato lo include.

2. **Per ogni flag**: un relay riceve un flag se **almeno la metà delle DA** che lo
   conoscono gli assegna quel flag.

3. **Per la bandwidth**: se ci sono misurazioni da bandwidth authorities, queste
   prevalgono sulla bandwidth autodichiarata dal relay.

4. **Firma**: ogni DA firma il consenso risultante.

### Fase 3: Pubblicazione (T+10 min)

Il consenso firmato viene pubblicato. I client (e i relay) lo scaricano.

### Tempistica completa del consenso

```
Ora X + 00:00  → Le DA iniziano a raccogliere i voti
Ora X + 00:05  → Le DA calcolano il consenso
Ora X + 00:10  → Il consenso è pubblicato
Ora X + 01:00  → Nuovo ciclo di votazione

Il consenso è valido per 3 ore dal momento della pubblicazione,
con un periodo di "fresh" di 1 ora. Questo permette ai client
con connessioni lente di usare un consenso leggermente datato.
```

### Nella mia esperienza

Il download del consenso è la prima cosa che Tor fa al bootstrap. Se il consenso è
corrotto, scaduto, o non raggiungibile, il bootstrap fallisce. Ho visto questo errore:

```
[warn] Our clock is 3 hours behind the consensus published time.
```

Questo accadeva su una VM dove NTP non era configurato. L'orologio era indietro di
3 ore, e Tor rifiutava il consenso perché fuori dalla finestra di validità. La
soluzione è stata:

```bash
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
```

---


---

> **Continua in**: [Struttura Consenso e Flag](struttura-consenso-e-flag.md) per il formato
> del documento e i flag, e in [Descriptor, Cache e Attacchi](descriptor-cache-e-attacchi.md)
> per i server descriptor, la cache e gli attacchi al consenso.

---

## Vedi anche

- [Struttura Consenso e Flag](struttura-consenso-e-flag.md) - Formato documento, flag, bandwidth auth
- [Descriptor, Cache e Attacchi](descriptor-cache-e-attacchi.md) - Server descriptor, cache, attacchi al consenso
- [Architettura di Tor](architettura-tor.md) - Componenti e panoramica
- [Costruzione Circuiti](costruzione-circuiti.md) - Come il consenso viene usato per la path selection
- [Scenari Reali](scenari-reali.md) - Casi operativi da pentester
