> **Lingua / Language**: [Italiano](../../08-aspetti-legali-ed-etici/etica-contribuire-e-comunita.md) | English

# Ethics and Responsibility - Relays, Surveillance, and Contributing to Tor

Relay operator responsibility, Tor and mass surveillance, contributing
to the Tor network (relays, donations, translation, bug reporting),
community and resources, personal approach.

> **Extracted from** [Ethics and Responsibility in Using Tor](etica-e-responsabilita.md) -
> which also covers ethical principles, the anonymity dilemma, who Tor is
> designed for, and ethical case studies.

---

## Relay operator responsibility

Operating a Tor relay is one of the most direct contributions one can make
to the network. But it carries specific ethical responsibilities, especially
for exit nodes.

For technical details on exit node risks, see
[exit-nodes.md](../03-nodi-e-rete/exit-nodes.md).

### Middle relay and guard: minimal risk, real contribution

A middle relay or guard relay carries encrypted traffic. The operator
cannot see the content of the traffic, cannot know who is sending it
or where it is headed. The ethical responsibility is minimal: you are
providing infrastructure to the network, like someone who runs an
internet router.

Enormous resources are not required. A VPS with 1 GB of RAM and 10 Mbit/s
of bandwidth is sufficient for a middle relay that makes a difference.
It costs less than a cup of coffee per day.

### Exit node: the critical point

The exit node is the point where traffic leaves the Tor network and reaches
the internet. The exit node operator is the visible point - their IP appears
in the destination server's logs. All traffic transiting through the exit -
legitimate or illegal - appears to originate from that IP.

**Specific ethical risks**:

- **Illegal traffic in transit**: all types of traffic pass through your
  exit node. You could be carrying a journalist's communication or a
  criminal's. You cannot know which, and you cannot (and should not) filter.

- **Moral vs. legal responsibility**: legally, in Italy and the EU, the
  operator of an exit node enjoys protections similar to those of an ISP
  (the "mere conduit" principle - Directive 2000/31/EC). You are not liable
  for the traffic in transit. But moral responsibility is more nuanced:
  you are knowingly providing an infrastructure that can be used for illicit
  purposes. The ethical answer is that the net benefit to society outweighs
  the risk - but it is a personal assessment.

- **Abuse reports**: you will receive abuse complaints from your hosting
  provider. Websites that see malicious traffic from your IP will contact
  you. You must be prepared to respond, explain that you operate a Tor exit
  relay, and have a clear exit policy.

**How to handle abuse reports**:

1. Prepare a response template explaining what Tor is and your role
2. Set up a web page on the exit's IP explaining it is a Tor relay
3. Use a restrictive exit policy to exclude ports associated with abuse
   (typically: exclude port 25/SMTP to prevent spam)
4. Maintain a professional relationship with your hosting provider
5. Choose a hosting provider with experience hosting Tor relays

**My opinion**: operating an exit node is an act of civic courage. It is
not for everyone, and it does not need to be. But those who do it are
contributing to the most critical and most scarce part of the Tor network.
If I cannot run an exit, I can at least run a middle relay - and contribute
differently through donations, code, or documentation.

---

## Tor and mass surveillance

### Why mass surveillance is an ethical problem

In 2013, the Edward Snowden revelations confirmed what many suspected:
Western governments conduct mass surveillance programs on their own
citizens. Not targeted surveillance of suspects - **mass** surveillance,
indiscriminate, on entire populations.

Documented programs:

- **PRISM** (NSA): direct access to the servers of Google, Facebook, Apple,
  Microsoft, Yahoo. The NSA could read emails, chats, stored files,
  video calls - everything, without individual warrants.

- **XKeyscore** (NSA): a search engine for global internet traffic.
  An NSA analyst could search by name, email, IP address, or keyword
  and get real-time results from intercepted traffic. Anyone who had
  searched for "Tor" or "Tails" on a search engine was automatically
  flagged.

- **Tempora** (GCHQ, UK): direct interception of undersea fiber optic
  cables. GCHQ recorded all traffic passing through those cables -
  content and metadata - and stored it for 30 days (content) or one
  year (metadata).

- **Five Eyes** (USA, UK, Canada, Australia, New Zealand): an intelligence
  alliance that shares surveillance data. If one country cannot legally
  surveil its own citizens, it asks an ally to do it.

- **European programs**: do not think that Europe is immune. The German
  BND collaborated with the NSA. French services (DGSE) have their own
  interception programs. Italy has COPASIR and RIS/AISE, which operate
  with less transparency than we would like.

### Why resisting is an ethical imperative

Mass surveillance violates the fundamental principle of the presumption
of innocence. You do not surveil everyone because everyone is a suspect -
you surveil everyone because it is technically possible and politically
convenient. This inverts the relationship between citizen and state: it is
no longer the state that must justify surveillance, but the citizen who
must justify their privacy.

Using Tor is not an act of rebellion - it is an act of normalcy. You are
exercising the right to privacy that the Italian Constitution (Art. 15),
the EU Charter of Fundamental Rights (Art. 7 and 8), and the Universal
Declaration of Human Rights (Art. 12) guarantee you.

The more people use Tor, the harder it is for surveillance systems to
identify "who has something to hide." If only journalists and activists
use Tor, they become easy to identify. If everyone uses Tor, no one is
suspect.

### Tor as resistance infrastructure

Tor is not perfect. It has significant technical limitations (see
[attacchi-noti.md](../07-limitazioni-e-attacchi/attacchi-noti.md) for
a catalog of documented attacks). But it is the only widely available
tool that offers reasonably robust anonymity against nation-state
adversaries.

The NSA itself, in internal documents revealed by Snowden, admitted that
Tor is a significant problem for surveillance operations. The internal
presentation "Tor Stinks" shows that, while the NSA can deanonymize
specific Tor users under favorable circumstances, it cannot do so at
mass scale.

This is exactly the point: Tor does not need to be perfect. It needs to
be good enough to make mass surveillance impractical. And today, for the
majority of users, it is.

---

## Contributing to the Tor network - practical guide

### Operating a relay

The most direct way to contribute is by operating a relay. Here are the
practical details for doing so from Italy.

#### Hardware and bandwidth requirements

**Middle relay (the easiest to start with)**:
- CPU: any modern CPU (even a VPS with 1 vCPU is sufficient)
- RAM: minimum 512 MB, recommended 1 GB
- Bandwidth: minimum 2 Mbit/s symmetric, recommended 10+ Mbit/s
- Storage: minimal, Tor uses little disk space
- Operating system: Debian or Ubuntu LTS recommended (Kali also works,
  but for a production relay a minimal system is better)
- Uptime: the higher, the better. An unstable relay is penalized by the
  Directory Authorities consensus

**Guard relay (requires more commitment)**:
- Same requirements as middle relay, but with higher uptime
- Tor automatically promotes stable and fast relays to guard status
- Weeks or months of consistent uptime are needed to become a guard
- Recommended bandwidth: 20+ Mbit/s

**Exit relay (the most needed, the most complex)**:
- Same hardware requirements
- Dedicated IP (not shared with other services)
- Hosting provider that accepts Tor relays (not all do)
- Carefully configured exit policy
- Preparedness to handle abuse complaints
- Recommendation: consult a lawyer before operating an exit from Italy

**Bridge (helps those under censorship)**:
- Minimal requirements (even a Raspberry Pi can work)
- Not listed in public directories, therefore less visible
- Particularly useful if your IP is in a range not associated with Tor

#### Basic configuration for a middle relay on Debian/Kali

```bash
# Installation
sudo apt update && sudo apt install tor

# Minimal configuration in /etc/tor/torrc
ORPort 9001
Nickname MyRelay
ContactInfo tor-admin@example.com
RelayBandwidthRate 2 MBytes
RelayBandwidthBurst 4 MBytes
ExitRelay 0
```

```bash
# Start and verify
sudo systemctl enable tor
sudo systemctl start tor

# After a few hours, verify on Tor Metrics
# https://metrics.torproject.org/rs.html#search/MyRelay
```

#### Legal considerations for Italy

- Operating a middle relay in Italy is unquestionably legal
- Operating an exit relay is legally more complex but not prohibited
- The "mere conduit" principle (D.Lgs. 70/2003, implementing Directive
  2000/31/EC) protects those who provide mere transmission services
- There is no specific Italian case law on Tor exit relays
- Practical advice: if you operate an exit, keep documentation of your role
  and a copy of the exit policy
- For the complete legal framework, see [aspetti-legali.md](./aspetti-legali.md)

### Donations

The Tor Project is a non-profit organization (501(c)(3) in the USA) that
depends on donations for:

- Software development (Tor daemon, Tor Browser, ARTI - the new Tor client
  in Rust)
- Security research and code audits
- Hosting the Directory Authorities (the 9 servers that maintain the consensus)
- Community support and training
- Infrastructure (servers for metrics, website, repositories)

**How to donate**:
- Official website: `https://donate.torproject.org/`
- Accepts credit card, PayPal, cryptocurrency (Bitcoin)
- Even 5 EUR per month makes a difference
- Donations from Italy are not tax-deductible (the Tor Project is a US
  entity), but the ethical value remains

### Translation and documentation

The Tor Project always needs translators:
- Platform: `https://community.torproject.org/localization/`
- Uses Weblate for collaborative translation
- Italian is one of the supported languages but not always complete
- You can translate: Tor Browser, website, documentation, training materials

### Bug reporting

If you find a bug in Tor or its components:
- Official issue tracker: `https://gitlab.torproject.org/`
- Tor daemon: `https://gitlab.torproject.org/tpo/core/tor`
- Tor Browser: `https://gitlab.torproject.org/tpo/applications/tor-browser`
- Read the reporting guidelines before opening an issue
- If it is a security vulnerability, use the dedicated channel:
  `security@torproject.org` (PGP key available on the website)

### Reporting malicious relays

If while using Tor you observe anomalous behavior (exits injecting content,
relays interfering with circuits, relays suspected of surveillance), you
can report it:

- Email: `bad-relays@lists.torproject.org`
- Issue tracker: `https://gitlab.torproject.org/tpo/network-health`
- For details on known attacks and detection techniques, see
  [attacchi-noti.md](../07-limitazioni-e-attacchi/attacchi-noti.md)

---

## Community and resources

Tor is not just software - it is a community of people who believe in
privacy as a fundamental right.

### Communication channels

- **Mailing lists**:
  - `tor-talk@lists.torproject.org` - general discussion
  - `tor-relays@lists.torproject.org` - for relay operators
  - `tor-dev@lists.torproject.org` - technical development
  - Archives: `https://lists.torproject.org/`

- **IRC/Matrix**:
  - `#tor` on OFTC (IRC) / `#tor:matrix.org` (Matrix) - general support
  - `#tor-relays` - for relay operators
  - `#tor-dev` - development
  - `#tor-project` - internal project discussion
  - Many core developers are active on these channels

- **Forum**: `https://forum.torproject.org/` - official forum, excellent for
  questions and less time-sensitive discussions

### Conferences and events

- **DEF CON** (Las Vegas, August): the world's largest hacker conference.
  Always features talks on Tor, anonymity, and privacy. The Tor Project
  often has its own booth and organizes meetups.

- **Chaos Communication Congress (CCC)** (Germany, December): annual
  conference of the Chaos Computer Club. Very strong Tor and privacy
  community presence. Extremely high-level technical talks.

- **PETS (Privacy Enhancing Technologies Symposium)**: academic conference
  on privacy. Many papers on Tor and traffic analysis are presented here.

- **RightsCon**: conference on digital rights. Tor is always present with
  workshops and panels.

- **FOSDEM** (Brussels, February): European open source conference. Often
  features talks on Tor and privacy technologies.

- **Local meetups**: in Italy, look for groups related to digital privacy,
  ethical hacking, and free software. Milan and Rome have active communities.
  In Parma we are fewer, but the Polytechnic has a cybersecurity group where
  these topics are also discussed.

### Further resources

- **Tor Project Blog**: `https://blog.torproject.org/` - official updates,
  incident analysis, roadmap
- **Tor Spec**: `https://spec.torproject.org/` - the technical specifications
  of the protocol, essential for understanding the low-level operation
- **Tor Research**: `https://research.torproject.org/` - research program,
  available datasets, academic papers
- **Tor Metrics**: `https://metrics.torproject.org/` - real-time network
  statistics (number of relays, users, bandwidth)
- **EFF (Electronic Frontier Foundation)**: `https://www.eff.org/` - advocacy
  for digital rights, many resources on Tor and privacy
- **Privacy International**: `https://privacyinternational.org/` - research
  on global surveillance

---

## My approach

I use Tor with awareness of its limitations and its importance. But it was
not always this way - my journey with Tor has been gradual, and I want to
share it because I believe personal experience is the best teacher.

### How I started

I became interested in Tor during my second year of cybersecurity studies
in Parma. The trigger was a networking course that discussed onion routing
as a theoretical concept. I thought: "Does this actually work? How robust
is it? What are the real limitations?"

Academic curiosity quickly transformed into practical interest. I installed
Tor on Kali Linux, configured proxychains, created a dedicated Firefox
profile for the tor-proxy. I began reading the protocol specifications,
studying circuits with nyx, and verifying exit IPs with
`check.torproject.org`.

### What I learned

The first thing I learned is that Tor is not magic. It does not make you
invisible. It does not protect you from yourself. The majority of documented
deanonymizations (see
[opsec-e-errori-comuni.md](../05-sicurezza-operativa/opsec-e-errori-comuni.md))
are not due to protocol weaknesses, but to human errors: logging in with
personal accounts, misconfigured browsers, metadata in documents.

The second thing is that the Tor network is fragile. It depends on
volunteers, has few exit nodes relative to what is needed, and faces
constant attacks from adversaries with nearly unlimited resources (see
[attacchi-noti.md](../07-limitazioni-e-attacchi/attacchi-noti.md)).

The third thing - and the most important - is that Tor is necessary. It
is not a toy for hackers or a refuge for criminals. It is critical
infrastructure for human rights in the digital age. This awareness changed
my approach from "interesting tool to study" to "technology that deserves
contributions and respect."

### How my perspective changed

At the beginning, I saw Tor as a tool - one of many in the Kali Linux
toolkit. I used it for proxychains, to test anonymity, out of technical
curiosity.

Then I started reading the stories of people who depend on Tor. The
journalist in Syria. The activist in Iran. The woman fleeing an abusive
partner. The researcher studying censorship in China. These stories gave
a different weight to every Tor circuit my client builds.

Today, when I configure proxychains and open Firefox with the tor-proxy
profile, I am not just "using a tool." I am participating in an
infrastructure that protects real people. And this carries a responsibility
that goes beyond the code.

### My daily practice

- I use Tor for **study, research, and legitimate privacy**
- I do not abuse network resources - no heavy downloads, no streaming,
  no torrenting via Tor
- I understand that anonymity is a right, not a weapon
- I share knowledge (this guide) to help others use Tor in an informed
  and responsible manner
- I respect Italian laws and the rights of others
- I report anomalous behavior when I observe it
- I contribute to Italian-language documentation, because too much Tor
  material is available only in English
- I constantly study new research on traffic analysis, fingerprinting,
  and protocol attacks to keep my skills current

### The experience with the community

The Tor community is one of the most welcoming I have encountered in the
cybersecurity world. The IRC/Matrix channels are active, the mailing lists
are a goldmine of technical knowledge, and the developers respond patiently
to questions (even the basic ones I asked at the beginning).

There is a sense of shared mission that I rarely find in other projects.
It is not "just" open source - it is open source with an explicit ethical
purpose. And this attracts people who do not limit themselves to writing
code, but who believe in what they are building.

If you are reading this guide and wondering "should I contribute?", the
answer is yes. You do not need to be an expert. You do not need to donate
thousands of euros. You can translate a page, report a bug, operate a
middle relay, or simply use Tor regularly - because every user adds
diversity to the network and makes everyone's anonymity more robust.

---

## Conclusion

Privacy is not a crime. It is a fundamental right that Tor helps to
protect. Using it ethically is the best way to support its mission.

Ethics in using Tor comes down to a simple question: **am I using this
tool in a way that, if everyone used it the same way, would make the
network stronger or weaker?** If the answer is "stronger," you are doing
the right thing.

If you want to explore the specific legal aspects for Italy, see
[aspetti-legali.md](./aspetti-legali.md). For the technical risks of exit
nodes, see [exit-nodes.md](../03-nodi-e-rete/exit-nodes.md). For OPSEC
mistakes that can deanonymize you, see
[opsec-e-errori-comuni.md](../05-sicurezza-operativa/opsec-e-errori-comuni.md).

---

## See also

- [Legal Aspects](aspetti-legali.md) - Italy/EU legal framework, legal precedents
- [Exit Nodes](../03-nodi-e-rete/exit-nodes.md) - Exit operator responsibility
- [Bridges and Pluggable Transports](../03-nodi-e-rete/bridges-e-pluggable-transports.md) - Contributing to the anti-censorship network
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Responsible and informed use
