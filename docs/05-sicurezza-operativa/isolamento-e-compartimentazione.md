# Isolamento e Compartimentazione — Protezione a Livello di Sistema

Questo documento analizza le soluzioni per isolare completamente il traffico Tor
dal traffico normale a livello di sistema operativo: Whonix, Tails, Qubes OS,
network namespaces Linux, e containerizzazione.

---

## Perché l'isolamento è necessario

Il mio setup (Tor daemon + proxychains su Kali) ha un problema fondamentale:
**il traffico non-Tor può ancora uscire**. Se un'applicazione non rispetta il proxy
o fa leak DNS, il mio IP reale viene esposto.

L'isolamento a livello di sistema risolve questo:

```
Senza isolamento:
[App] ─proxy→ [Tor] → Internet    (traffico intenzionale)
[App] ─diretto→ Internet           (leak!)
[OS services] ─diretto→ Internet   (NTP, updates, etc.)

Con isolamento:
[App] → [firewall: DEVE passare da Tor] → [Tor] → Internet
[App] → [firewall: BLOCCATO] ✗ Internet   (leak impossibile)
```

---

## Soluzioni di isolamento

### 1. Whonix

Whonix è un sistema a due VM:

```
┌─────────────────────┐     ┌──────────────────────┐
│  Whonix-Workstation  │     │   Whonix-Gateway     │
│  (dove lavori)       │────►│   (Tor daemon)       │────► Internet
│  No rete diretta     │     │   Firewall totale    │
└─────────────────────┘     └──────────────────────┘
```

- **Whonix-Gateway**: contiene Tor e un firewall che blocca tutto il traffico
  non-Tor. È l'unica macchina con accesso alla rete.
- **Whonix-Workstation**: non ha accesso diretto alla rete. Tutto il traffico
  è forzato attraverso il Gateway → attraverso Tor.

**Vantaggi**:
- Leak impossibili (la Workstation non ha interfaccia di rete verso Internet)
- Anche se un'app è compromessa, non può bypassare Tor
- DNS leak impossibili (il Gateway forza tutto il DNS via Tor)

**Svantaggi**:
- Richiede virtualizzazione (VirtualBox, KVM, etc.)
- Performance leggermente ridotte (overhead VM)
- Più complesso da configurare rispetto a Tor da solo

### 2. Tails (The Amnesic Incognito Live System)

Tails è un sistema operativo live che:
- Si avvia da USB
- Instrada TUTTO il traffico attraverso Tor
- Non lascia tracce sul disco (amnesico)
- Si resetta completamente ad ogni riavvio

**Vantaggi**:
- Nessuna traccia sul computer host
- Isolamento totale del traffico
- Include Tor Browser, client email cifrato, etc.
- Ideale per scenari ad alto rischio

**Svantaggi**:
- Non persistente di default (i file si perdono al riavvio)
- Richiede riavvio del computer (non può coesistere con l'OS principale)
- Non personalizzabile come un sistema installato

### 3. Qubes OS

Qubes OS usa la virtualizzazione per compartimentare il sistema in "qubes":

```
[Qube: Personal]     → [Qube: sys-firewall] → [Qube: sys-net]
[Qube: Work]         → [Qube: sys-firewall] → [Qube: sys-net]
[Qube: Tor-Browser]  → [Qube: sys-whonix]   → [Qube: sys-net]
[Qube: Untrusted]    → [Qube: sys-whonix]   → [Qube: sys-net]
```

Ogni qube è isolato. Il qube Tor passa attraverso `sys-whonix`. Il qube Personal
passa attraverso la rete normale. Non possono interferire.

**Vantaggi**:
- Compartimentazione estrema (lavoro, personal, Tor sono completamente separati)
- Se un qube è compromesso, gli altri rimangono sicuri
- Integrazione con Whonix per il traffico Tor

**Svantaggi**:
- Requisiti hardware elevati (16+ GB RAM, CPU con VT-x)
- Curva di apprendimento ripida
- Non supporta tutti i hardware

### 4. Network Namespaces Linux (soluzione leggera)

I network namespaces di Linux permettono di creare ambienti di rete isolati
senza virtualizzazione:

```bash
# Creare un namespace isolato
sudo ip netns add tor_ns

# Creare un'interfaccia veth (virtual ethernet)
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns tor_ns

# Configurare gli indirizzi
sudo ip addr add 10.200.1.1/24 dev veth0
sudo ip link set veth0 up
sudo ip netns exec tor_ns ip addr add 10.200.1.2/24 dev veth1
sudo ip netns exec tor_ns ip link set veth1 up
sudo ip netns exec tor_ns ip link set lo up

# Configurare il routing nel namespace
sudo ip netns exec tor_ns ip route add default via 10.200.1.1

# Eseguire Tor nel namespace
sudo ip netns exec tor_ns tor -f /etc/tor/torrc

# Eseguire applicazioni nel namespace (forzate attraverso Tor)
sudo ip netns exec tor_ns proxychains curl https://api.ipify.org
```

**Vantaggi**:
- Nessuna virtualizzazione necessaria
- Overhead minimo
- Nativo Linux

**Svantaggi**:
- Configurazione manuale complessa
- Meno robusto di Whonix (se il namespace è configurato male, possono esserci leak)
- Non amnesico

### 5. Docker/Container

Eseguire Tor e le applicazioni in un container Docker isolato:

```dockerfile
FROM debian:bookworm
RUN apt-get update && apt-get install -y tor proxychains4 curl
COPY torrc /etc/tor/torrc
COPY proxychains4.conf /etc/proxychains4.conf
CMD ["tor"]
```

**Vantaggi**:
- Portabile e riproducibile
- Isolamento di rete configurabile
- Facile da avviare e distruggere

**Svantaggi**:
- Docker non è progettato per la sicurezza (il daemon gira come root)
- L'isolamento di rete di Docker non è pensato per l'anonimato
- Meno robusto di Whonix/Tails per scenari ad alto rischio

---

## La mia posizione

Per il mio caso d'uso (studio, test, privacy dall'ISP), il setup attuale
(Tor daemon + proxychains su Kali) è sufficiente. Le soluzioni di isolamento
sono per scenari dove l'anonimato è critico:

| Scenario | Soluzione consigliata |
|----------|---------------------|
| Studio e test (il mio caso) | Tor + proxychains |
| Privacy dall'ISP | Tor + proxychains + bridge obfs4 |
| Navigazione anonima seria | Tor Browser |
| Alto rischio (giornalismo, attivismo) | Tails o Whonix |
| Compartimentazione totale | Qubes OS + Whonix |
| Protezione system-wide leggera | iptables transparent proxy |

La scelta dipende dal modello di minaccia. Non esiste una soluzione "migliore"
in assoluto — esiste la soluzione adatta al rischio specifico.
