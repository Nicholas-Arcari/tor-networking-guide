> **Lingua / Language**: [Italiano](../../08-aspetti-legali-ed-etici/aspetti-legali-relay-e-confronto.md) | English

# Legal Aspects - Relays, Data Retention, and International Comparison

Operating a Tor relay in Italy, ISP obligations and data retention,
European framework (GDPR, NIS2, DSA), legal precedents, international
comparison, Tor in the corporate context.

> **Extracted from** [Legal Aspects of Using Tor](aspetti-legali.md) -
> which also covers legality in Italy, legal basis, offenses, and specific
> legal nuances.

---

## Operating a Tor relay in Italy

### Relay types and legal risk

| Relay type | Legal risk in Italy | Notes |
|------------|-------------------|-------|
| Bridge (non-public) | Minimal | Obfuscated traffic, you are not in the public list |
| Guard/Middle relay | Low | Encrypted traffic in transit, you are not the origin |
| Exit node | Medium-high | Traffic exits from your IP |
| Directory Authority | N/A | Only 9 worldwide, operated by the Tor Project |

### Considerations for middle/guard relays

```
Legal risk: low
  - The traffic in transit is encrypted
  - You cannot see the content
  - You are neither the origin nor the destination
  - You are equivalent to an ISP carrying traffic

Practical risk:
  - Consumes bandwidth (check your ISP contract)
  - May violate your ISP's ToS (verify)
  - Your IP could end up on some blocklists (rare for non-exit)

Recommendation:
  - Check your ISP's ToS
  - Use a dedicated instance (not your main PC)
  - Configure AccountingMax to limit traffic
```

### Carrier liability (safe harbor)

In Italy and the EU, the "mere conduit" principle from Directive 2000/31/EC
(e-Commerce Directive) provides protection to those who offer data transport
services:

**Art. 12 (mere conduit)**:
> The service provider is not liable for the information transmitted on the
> condition that the provider does not initiate the transmission, does not
> select the receiver, and does not select or modify the information transmitted.

A Tor relay satisfies all three conditions:
1. It does not originate the traffic (it receives and forwards it)
2. It does not select the receiver (the circuit is chosen by the client)
3. It does not modify the information (it forwards it encrypted)

However, this protection has not been specifically tested for Tor relays
in Italian courts.

---

## ISP obligations and data retention

### What my ISP (Comeser) logs

Under Italian data retention regulations (D.Lgs. 109/2008, as amended by
D.Lgs. 132/2021), ISPs are required to retain:

```
Data retained (6 years for telephone traffic, 1 year for internet):
- Date and time of the connection
- Duration of the connection
- Assigned IP
- Connection type (ADSL, fiber, mobile)

Data NOT retained (for web browsing):
- Visited URLs (browsing content is not logged)
- Individual DNS queries (not mandatory)
- Content of communications

Exception: with a judicial authority order, the ISP can be
required to monitor a specific user's traffic
(telematic interception, Art. 266-bis c.p.p.)
```

### What the ISP sees when I use Tor

```
Without bridge:
- The ISP sees: TCP connection to the IP of a known Tor Guard
- The ISP knows: "this user is using Tor"
- The ISP does NOT know: what they are doing on Tor

With obfs4 bridge:
- The ISP sees: connection to an IP not known as a Tor relay
- The ISP sees: traffic that looks like normal HTTPS (obfuscated)
- The ISP does NOT know: that you are using Tor
- The ISP does NOT know: what you are doing
```

### Data retention and Tor

Italian data retention stores connection metadata, not content.
The ISP logs that at 14:30 my IP (151.x.x.x) connected to an IP
(the Guard). It does not log what I did on Tor.

If the ISP identifies the connection as Tor (without bridge), it only logs:
"connection to Tor relay IP." It cannot log the final destination.

---

## European framework

### GDPR and privacy

The GDPR recognizes privacy as a fundamental right. The use of tools
like Tor is consistent with the right to personal data protection
(Art. 5, 25, 32 GDPR).

The Court of Justice of the EU has repeatedly affirmed that personal data
protection is a fundamental right (Art. 8 of the EU Charter of Fundamental
Rights).

### NIS2 Directive (2022/2555)

The NIS2 Directive on the security of network and information systems
does not prohibit Tor. On the contrary, encryption and anonymization are
recommended as security measures for critical organizations.

### Digital Services Act (DSA) - Regulation 2022/2065

The DSA regulates online platforms but does not prohibit the use of
anonymization tools. It imposes content moderation obligations on platform
operators, not on users. It does not mention Tor.

### ePrivacy Directive (2002/58/EC)

Protects the confidentiality of electronic communications. Using Tor is
consistent with this directive: the user is protecting the confidentiality
of their own communications.

### Proposed ePrivacy Regulation (under discussion)

The proposed ePrivacy Regulation, under discussion since 2017, could
strengthen online privacy protections. It contains no provisions that
would prohibit anonymization tools.

---

## Relevant legal precedents

### Italy

**There are no known Italian court rulings that condemn the use of Tor itself.**

There are rulings where Tor is mentioned as a tool used during a crime
(e.g., unauthorized access), but in no case has the use of Tor been
considered a standalone offense or an aggravating factor.

Cases where Tor is mentioned in Italian proceedings:
- Investigations into darknet markets involving Italian users
- Child exploitation cases where Tor was used for access
- Hacking cases where Tor was used for anonymization

In all these cases, the charged offense is the activity carried out (trafficking,
possession of CSAM, unauthorized access), not the use of Tor.

### Europe

**Daniel Moritz Haikal (Germany, 2016)**:
A German exit node operator was acquitted of aiding and abetting charges
for the traffic that transited through his relay. The court established that
the operator of a relay is not liable for the content of the traffic.

**Zwiebelfreunde e.V. (Germany, 2018)**:
German police seized the servers of an association that operated Tor
relays. The seizure was subsequently declared unlawful.

### USA

**Various exit node operator cases**:
In the US, several exit node operators have received search warrants
or had equipment seized. In no known case were they convicted for
third-party traffic. The EFF (Electronic Frontier Foundation) has
provided legal assistance in many cases.

---

## International comparison

### Countries where Tor is legal and not blocked

| Country | Status | Notes |
|---------|--------|-------|
| Italy | Legal, not blocked | No restrictions |
| Germany | Legal, not blocked | Strong privacy tradition |
| France | Legal, not blocked | |
| Spain | Legal, not blocked | |
| Netherlands | Legal, not blocked | Many relays hosted |
| Switzerland | Legal, not blocked | ProtonMail headquarters |
| USA | Legal, not blocked | Tor originated from a US Navy project |
| UK | Legal, not blocked | But extensive surveillance (GCHQ) |
| Japan | Legal, not blocked | |
| Brazil | Legal, not blocked | |

### Countries where Tor is blocked or restricted

| Country | Status | Details |
|---------|--------|---------|
| China | Blocked (DPI) | Bridges partially functional, meek useful |
| Russia | Blocked since 2021 | obfs4 bridges work, Snowflake works |
| Iran | Blocked | Bridges required, obfs4 works |
| Turkmenistan | Heavily filtered Internet | Tor very difficult to use |
| Belarus | Blocked since 2022 | Bridges required |
| Egypt | Partially blocked | Bridges work |
| Kazakhstan | Partially blocked | Intermittent DPI |
| Venezuela | Partially blocked | Periods of intermittent blocking |

### Countries where using Tor can be risky

| Country | Risk | Notes |
|---------|------|-------|
| China | High | Possible legal consequences for circumventing censorship |
| Saudi Arabia | High | Possible criminalization of VPN/Tor |
| UAE | High | Use of VPN/Tor can be fined |
| North Korea | Extreme | Internet not accessible to the general population |

**In Italy and the EU**: Tor is neither blocked nor restricted. Its use is an
implicit right under privacy legislation.

---

## Tor in the corporate context

### Using Tor in organizations

Using Tor in a corporate context is legal but may be restricted by
company policies:

```
Legitimate corporate uses:
- Threat intelligence (monitoring darknet for corporate data leaks)
- OSINT (anonymous reconnaissance on competitors or threat actors)
- Security testing (checking how services appear from anonymous IPs)
- Protection of sensitive research (R&D, M&A)
- Communication with confidential sources (investigative journalism)

Problematic uses:
- Bypassing the corporate firewall (possible policy violation)
- Unauthorized activities during working hours
- Exfiltration of corporate data
```

### Recommended corporate policy

```
A corporate policy on Tor should:
1. Not generically prohibit Tor (it is a legitimate tool)
2. Authorize use for specific purposes (CTI, OSINT, testing)
3. Require authorization for installation
4. Log usage (without logging content)
5. Define liability in case of incidents
```

---

## Who uses Tor legitimately

Tor is used daily by millions of people for legitimate purposes:

- **Journalists**: protecting sources and communications (SecureDrop uses Tor)
- **Human rights activists**: in countries with mass surveillance
- **Security researchers**: anonymous testing, threat analysis, OSINT
- **Ordinary citizens**: privacy from ISPs and trackers
- **Companies**: competitive intelligence without revealing their IP
- **Law enforcement**: undercover investigations (yes, law enforcement uses Tor)
- **Military and diplomats**: secure communications (Tor originated from a US Navy project)
- **Whistleblowers**: anonymous reporting (SecureDrop, GlobaLeaks)
- **Domestic violence victims**: secure communication with shelters
- **LGBTQ+ people in hostile countries**: protection from persecution
- **Users in countries with censorship**: access to free information

### Tor network statistics (2024-2025)

```
Estimated daily users: ~2-4 million
Active relays: ~7,000-8,000
Active bridges: ~2,000-3,000
Total bandwidth: ~400-600 Gbit/s
Countries with most users: USA, Russia, Germany, France, UK
```

---

## In my experience

Before starting to use Tor, I researched the legality in Italy.
My conclusions:

1. **Using Tor is legal**: no Italian law prohibits it
2. **Bridges and NEWNYM are legal**: they are technical features, not illicit activities
3. **Accessing foreign sites is legal**: millions of people do it daily
4. **What matters is what you do**: Tor is a tool, legality depends on usage
5. **Your ISP cannot prevent you from using Tor**: it does not violate any standard contract

The configurations documented in this guide are for study, security, and
legitimate privacy. They do not encourage or facilitate illegal activities.

My use case falls fully within the right to privacy:
- Study of the protocol and the network
- Authorized security testing
- Privacy from ISP profiling
- Understanding anonymization techniques

---

## See also

- [Ethics and Responsibility](etica-e-responsabilita.md) - Ethical dilemma, case studies, responsible use
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Legal consequences of mistakes
- [Exit Nodes](../03-nodi-e-rete/exit-nodes.md) - Practical risks of operating an exit
- [Bridges and Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Legal use in countries with censorship
- [Anonymous Reconnaissance](../09-scenari-operativi/ricognizione-anonima.md) - Legal OSINT via Tor
