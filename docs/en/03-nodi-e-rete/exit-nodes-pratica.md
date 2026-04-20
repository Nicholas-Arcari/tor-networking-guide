> **Lingua / Language**: [Italiano](../../03-nodi-e-rete/exit-nodes-pratica.md) | English

# Exit Nodes in Practice - Blocks, DNS, and Identification

Blocks and CAPTCHAs from websites, DNS resolution from the exit node,
selectivity principle in exit policies, and identifying exits in the consensus.

Extracted from [Exit Nodes](exit-nodes.md).

---

## Table of Contents

- [Blocks and CAPTCHAs - How sites react to Exit Nodes](#blocks-and-captchas--how-sites-react-to-exit-nodes)
- [Exit Node and DNS - Who resolves what](#exit-node-and-dns--who-resolves-what)
- [Exit Policy and the selectivity principle](#exit-policy-and-the-selectivity-principle)
- [Identifying Exit Nodes in the consensus](#identifying-exit-nodes-in-the-consensus)
- [Summary of risks and mitigations](#summary-of-risks-and-mitigations)

---

## Blocks and CAPTCHAs - How sites react to Exit Nodes

### Why sites block Tor

Tor exit node IPs are **publicly known** (they are in the consensus). Sites can:

1. **Download the exit list** from `https://check.torproject.org/torbulkexitlist`
2. **Block or rate-limit** connections from these IPs
3. **Require additional CAPTCHAs**
4. **Reduce functionality** (no login, no purchases, no API)

### Sites I personally tested

| Site | Behavior via Tor |
|------|-----------------|
| Google Search | Frequent CAPTCHAs, sometimes total block |
| Google Maps | Works with occasional CAPTCHAs |
| Amazon | Login blocked, additional verification required |
| Reddit | Works but requires frequent login |
| GitHub | Generally works well |
| Wikipedia | Reading OK, editing blocked |
| PayPal | Login blocked, "suspicious activity" |
| Instagram/Meta | Login very difficult, frequent blocks |
| Stack Overflow | Works well |
| Italian banks | Total block or forced 2FA |

### Strategies for dealing with blocks

1. **NEWNYM and retry**: sometimes the block is on the specific exit. Changing exit
   (NEWNYM) might give you an unblocked exit.

2. **Do not log in**: use Tor for anonymous browsing, not for personal accounts.
   Logging in with personal accounts over Tor is an OPSEC mistake (see the security section).

3. **Accept the limitations**: certain services will never work well via Tor. This is
   a trade-off of anonymity.

---

## Exit Node and DNS - Who resolves what

### The DNS flow in a Tor circuit

```
1. The user requests a connection to "example.com"
2. The hostname is sent to the SocksPort as DOMAINNAME (not resolved locally)
3. Tor creates a RELAY_BEGIN cell with "example.com:443"
4. The Exit Node receives "example.com:443"
5. The Exit Node uses ITS OWN DNS resolver to resolve "example.com"
6. The Exit Node connects to the resulting IP
```

### Implications

- **DNS NEVER leaves your computer** (if you use proxychains/torsocks correctly)
- **The Exit Node performs DNS resolution** → uses the DNS of the datacenter where it is located
- **Different exits may resolve hostnames differently** (CDN, load balancing, geo-DNS)

### DNS leak

If an application resolves the hostname BEFORE sending it to the SocksPort, the DNS
goes out in cleartext to your ISP. This is a **DNS leak**:

```
CORRECT (no leak):
curl --socks5-hostname 127.0.0.1:9050 https://example.com
  → "example.com" sent as a string to Tor → Exit resolves

WRONG (leak):
curl --socks5 127.0.0.1:9050 https://example.com
  → curl resolves "example.com" locally → DNS leak!
  → then sends the IP to Tor

The difference is --socks5-hostname (resolves via proxy) vs --socks5 (resolves locally)
```

Proxychains with `proxy_dns` enabled handles this automatically, intercepting DNS
calls and sending them to the proxy.

---

## Exit Policy and the selectivity principle

### Reduced Exit Policy

Many exit operators use a reduced policy that only allows the most common and
safe ports:

```
accept *:20-23     # FTP, SSH, Telnet
accept *:43        # WHOIS
accept *:53        # DNS
accept *:80        # HTTP
accept *:443       # HTTPS
accept *:993       # IMAPS
accept *:995       # POP3S
reject *:*         # Block everything else
```

### Why exit policies are restrictive

- **Reduce abuse complaints**: ports like 25 (SMTP) generate spam. Ports like
  6667 (IRC) generate floods. By blocking them, the operator receives fewer reports.
- **Reduce legal risk**: fewer open ports = fewer chances of being associated
  with illegal traffic.
- **Focus bandwidth**: exit bandwidth is limited. Serving only web ports (80/443)
  maximizes utility for the majority of users.

### Impact on circuit selection

Tor selects the exit BEFORE the port requested by the stream. If the stream
requests port 22 (SSH), Tor looks for an exit that allows port 22. If few exits
allow it, the pool is restricted and latency potentially worse.

---

## Identifying Exit Nodes in the consensus

### List of active exits

```bash
# Download the consensus and filter exits
proxychains curl -s http://128.31.0.34:9131/tor/status-vote/current/consensus > /tmp/consensus.txt

# Count relays with the Exit flag
grep -c "^s.*Exit" /tmp/consensus.txt

# Extract exit IPs
grep -B1 "^s.*Exit" /tmp/consensus.txt | grep "^r " | awk '{print $7}'
```

### Typical numbers

- ~7000 total relays
- ~1000-1500 relays with the Exit flag
- ~800-1000 exits that accept port 443
- ~400-600 exits that also accept port 22

The relatively low number of exits compared to total relays is the reason why:
- Exits are the network's bottleneck
- Bandwidth weights in the consensus favor exits
- Sites can easily enumerate and block all exits

---

## Summary of risks and mitigations

| Risk | Condition | Mitigation |
|------|-----------|------------|
| Content sniffing | Only if HTTP (not HTTPS) | ALWAYS use HTTPS |
| DNS spoofing | Malicious exit | Verify TLS certificates |
| SSL stripping | Site reached via initial HTTP | HSTS, Tor Browser |
| Download injection | File downloaded via HTTP | Verify hash/signature |
| Metadata logging | Always possible | Tor Browser reduces metadata |
| MITM on TLS | Exit generates fake cert | Never ignore certificate errors |
| Blocks/CAPTCHAs | Exit IP is public | NEWNYM, accept the compromise |
| Restrictive exit policy | Non-standard ports | Retry with NEWNYM |

---

## See also

- [Exit Nodes](exit-nodes.md) - Role, exit policy, risks
- [DNS Leak](../05-sicurezza-operativa/dns-leak.md) - In-depth DNS leak analysis
- [IP, DNS, and Leak Verification](../04-strumenti-operativi/verifica-ip-dns-e-leak.md) - Practical tests
- [OpSec and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Logging in via Tor
- [Real-World Scenarios](scenari-reali.md) - Practical operational cases from a pentester
