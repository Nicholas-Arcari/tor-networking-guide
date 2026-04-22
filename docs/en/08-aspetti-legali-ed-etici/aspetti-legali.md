> **Lingua / Language**: [Italiano](../../08-aspetti-legali-ed-etici/aspetti-legali.md) | English

# Legal Aspects of Using Tor - Italy and the EU

This document analyzes the legal framework for using Tor in Italy and the European
Union: what is legal, what is not, relevant legal precedents, ISP obligations,
relay operator liability, and the legal nuances of bridges, NEWNYM, accessing
foreign websites, and data retention.

Based on my personal experience: I researched the legality before starting to use
Tor, and confirmed that in Italy the use of Tor is fully legal.

---

## Table of Contents

- [In Italy: using Tor is legal](#in-italy-using-tor-is-legal)
- [Detailed legal basis](#detailed-legal-basis)
- [What remains illegal (with or without Tor)](#what-remains-illegal-with-or-without-tor)
- [Specific legal nuances](#specific-legal-nuances)
- **Further reading** (dedicated files)
  - [Relays, Data Retention, and International Comparison](aspetti-legali-relay-e-confronto.md)

---

## In Italy: using Tor is legal

### The clear position

**Using Tor is legal in Italy.** There is no law that prohibits:
- Installing and running the Tor software
- Using obfs4 bridges to obfuscate traffic
- Rotating your IP via NEWNYM
- Using ProxyChains or torsocks
- Browsing the web through the Tor network
- Accessing websites of other countries through foreign exit nodes
- Accessing onion services (.onion)

### What is legal to do with Tor - Complete table

| Activity | Legal? | Notes |
|----------|--------|-------|
| Installing Tor on any system | YES | Open source software, BSD license |
| Browsing the web via Tor | YES | Right to privacy |
| Using obfs4/meek/Snowflake bridges | YES | Anti-censorship tools |
| Changing IP with NEWNYM | YES | Equivalent to ISP reconnection |
| Accessing websites of other countries | YES | Normal Internet routing |
| Using ProxyChains / torsocks | YES | Standard networking tools |
| Operating a Tor relay (middle/guard) | YES | Infrastructure contribution |
| Operating a Tor exit node | YES | But with significant practical risks |
| Accessing onion services (.onion) | YES | Not illegal by nature |
| Using Tor for security research | YES | Recognized professional practice |
| Using Tor for OSINT | YES | Common in cybersecurity |
| Running a Tor bridge | YES | Anti-censorship contribution |
| Using Tor in combination with VPN | YES | Legitimate network configuration |
| Conducting penetration testing via Tor | YES | With target authorization |

---

## Detailed legal basis

### Italian Constitution

**Art. 15 - Secrecy of correspondence**:
> La liberta e la segretezza della corrispondenza e di ogni altra forma di
> comunicazione sono inviolabili. La loro limitazione puo avvenire soltanto
> per atto motivato dell'autorita giudiziaria con le garanzie stabilite dalla legge.

(The freedom and secrecy of correspondence and of every other form of
communication are inviolable. They may only be restricted by a reasoned
order of the judiciary with the safeguards established by law.)

This article protects the right to privacy of communications.
The use of anonymization tools such as Tor is consistent with this right.

**Art. 21 - Freedom of expression**:
> Tutti hanno diritto di manifestare liberamente il proprio pensiero con la parola,
> lo scritto e ogni altro mezzo di diffusione.

(Everyone has the right to freely express their thoughts through speech,
writing, and every other means of dissemination.)

Freedom of expression includes the right to express oneself anonymously,
as long as no crimes are committed.

### Criminal Code - Relevant articles

**Art. 615-ter c.p. - Unauthorized access to a computer system**
(Accesso abusivo a un sistema informatico):
Punishes anyone who gains unauthorized access to a computer system protected by
security measures. Using Tor does not constitute unauthorized access: Tor is a
transport tool, not an intrusion tool.

**Art. 617-quater c.p. - Interception of computer communications**
(Intercettazione di comunicazioni informatiche):
Punishes anyone who intercepts communications. Using Tor to protect one's own
communications is the opposite: it is a defense against interception.

**Art. 640-ter c.p. - Computer fraud** (Frode informatica):
Punishes anyone who alters the operation of a system to gain an advantage.
Using Tor for anonymous browsing does not alter any system.

### Electronic Communications Code (D.Lgs. 259/2003)

Contains no provision that prohibits the use of anonymization tools.
It regulates telecommunications but does not impose identification obligations
on end users for web browsing.

### GDPR (EU Regulation 2016/679)

The GDPR explicitly recognizes:

**Art. 5 - Principle of data minimization**:
Personal data must be "adequate, relevant, and limited to what is necessary."
Using Tor is consistent with minimization: it reduces exposed personal data.

**Art. 25 - Privacy by design and by default**:
The GDPR encourages privacy protection from the design stage.
Tor implements privacy by design.

**Art. 32 - Security of processing**:
Requires adequate technical measures to protect data. Encryption and
anonymization are expressly mentioned as adequate measures.

**Recital 26**:
Anonymized data is not personal data. Tor anonymizes network traffic.

---

## What remains illegal (with or without Tor)

Tor does not change the law. Illegal activities remain illegal regardless
of the technical means used.

| Activity | Criminal Code Article | Legal without Tor? | Legal with Tor? |
|----------|----------------------|-------------------|-----------------|
| Unauthorized access to systems | Art. 615-ter c.p. | NO | NO |
| Malware distribution | Art. 615-quinquies c.p. | NO | NO |
| Computer fraud | Art. 640-ter c.p. | NO | NO |
| Illegal substance trafficking | D.P.R. 309/1990 | NO | NO |
| CSAM distribution | Art. 600-ter, 600-quater c.p. | NO | NO |
| Phishing | Art. 640 + 615-ter c.p. | NO | NO |
| Extortion | Art. 629 c.p. | NO | NO |
| Defamation | Art. 595 c.p. | NO | NO |
| Copyright infringement (large scale) | L. 633/1941 | NO | NO |
| Money laundering | Art. 648-bis c.p. | NO | NO |
| Terrorism and advocacy | Art. 270-bis c.p. et seq. | NO | NO |
| Threats | Art. 612 c.p. | NO | NO |

**The principle is simple**: if an activity is illegal without Tor, it remains
illegal with Tor. Tor is a neutral tool, like a telephone, an automobile, or a
kitchen knife. Legality depends on the use, not the tool.

### The question of anonymity as an aggravating factor

In Italy, the use of anonymization tools during a computer crime **is not a
specific aggravating factor** under the criminal code. However, a judge could
consider premeditation (deliberate use of Tor to cover one's tracks) as an
element of criminal intent (dolo).

Likewise, anonymity is not an excuse: a crime committed via Tor is prosecutable
exactly like one committed without Tor.

---

## Specific legal nuances

### Operating an exit node in Italy

Operating an exit node is legal, but carries significant practical risks:

**The problem**:
```
Traffic from unknown users exits from your public IP.
If a user commits a crime via Tor:
  1. Investigations start from the exit node IP (YOUR IP)
  2. Authorities may preemptively seize your server
  3. You must demonstrate that you are a relay, not the author of the traffic
  4. The process is lengthy, expensive, and stressful
```

**Legal mitigations**:
1. **Tor Exit Notice**: the Tor Project provides an HTML template to display
   on port 80 of your exit, explaining that it is a Tor relay
2. **Registration as a relay**: publicly document that you operate a relay
3. **Legal counsel**: consult a lawyer BEFORE operating an exit in Italy
4. **Preemptive communication**: some operators inform the Polizia Postale
   (Italian Postal Police / cybercrime unit) that they operate a Tor relay

**In Italian practice**: there are no known legal precedents of Tor exit
node operators convicted in Italy for transited traffic. But the risk of
precautionary seizure and legal expenses exists.

### Accessing websites of other countries

Accessing foreign websites (exiting through an exit in the USA, UK, Japan, etc.)
is perfectly legal. Millions of people do it daily through VPNs, CDNs, and normal
Internet routing.

The only exception would be if a website is specifically subject to an Italian
court order:
- Unauthorized gambling sites blocked by ADM (ex AAMS - Italian customs and
  monopolies agency)
- Websites with child exploitation material on the CNCPO list
- Websites subject to a blocking order from the GIP (preliminary investigations
  judge)

**Note**: the ADM block is implemented at the DNS level by the ISP. It is not a
criminal prohibition for the user. Bypassing the DNS block is not a crime for
the user (it is an obligation of the ISP to implement it, not of the user to
respect it).

### Bridges and obfuscation

Using bridges and pluggable transports (obfs4, meek, Snowflake) is legal in Italy.
They are anti-censorship tools developed to protect users in countries where Tor is
blocked. There is no censorship of Tor in Italy, but using bridges for privacy is
a right.

Traffic obfuscation is not a crime. It is equivalent to the use of encryption,
which is legal and protected by the GDPR.

### NEWNYM and IP rotation

Changing your exit IP is not illegal. It is equivalent to:
- Reconnecting to the Internet (the modem assigns a new IP)
- Switching VPN servers
- Moving from one 4G cell to another
- Using a different WiFi network

There is no law that requires maintaining the same IP.

### Use of .onion

Accessing .onion sites is not illegal. Onion services are a technology,
not a type of content. There are perfectly legal .onion sites:

```
Legal and well-known .onion services:
- Facebook: facebookwkhpilnemxj7asaniu7vnjjbiltxjqhye3mhbshg7kx5tfyd.onion
- New York Times: nytimesn7cgmftshazwhfgzm37qxb44r64ytbb2dj3x62d2lnez7pnzl.onion
- BBC: bbcnewsd73hkzno2ini43t4gblxvycyac5aw4gnv7t2rccijh7745uqd.onion
- ProtonMail: protonmailrmez3lotccipshtkleegetolb73fuirgj7r4o4vfu7ozyd.onion
- DuckDuckGo: duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion
- SecureDrop (various media): onion services for whistleblowing
- Debian packages: 2s4yqjx5ul6okpp3f2gaunr2syex5jgbfpfvhxxbbjdbez5dp4rbd2ad.onion
```

---

> **Continues in** [Legal Aspects - Relays, Data Retention, and International Comparison](aspetti-legali-relay-e-confronto.md)
> - operating relays in Italy, ISP obligations, data retention, European framework,
> legal precedents, international comparison, Tor in corporate settings.

---

## See also

- [Ethics and Responsibility](etica-e-responsabilita.md) - Ethical dilemma, case studies, responsible use
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Legal consequences of mistakes
- [Exit Nodes](../03-nodi-e-rete/exit-nodes.md) - Practical risks of operating an exit
- [Bridges and Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Legal use in countries with censorship
