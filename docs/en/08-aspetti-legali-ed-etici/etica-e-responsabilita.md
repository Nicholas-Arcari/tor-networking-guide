> **Lingua / Language**: [Italiano](../../08-aspetti-legali-ed-etici/etica-e-responsabilita.md) | English

# Ethics and Responsibility in Using Tor

This document addresses the ethical dimension of using Tor: the responsibility
that comes with anonymity, contributing to the network, and the boundary between
legitimate privacy and abuse.

Written from the perspective of a student and cybersecurity analyst in Parma,
who uses Tor daily on Kali Linux - with proxychains, a Firefox tor-proxy
profile, and a curiosity that started academic and became a personal conviction.

---

## Table of Contents

- [Anonymity entails responsibility](#anonymity-entails-responsibility)
- [The ethical dilemma of anonymity](#the-ethical-dilemma-of-anonymity)
- [Who Tor is designed for](#who-tor-is-designed-for)
- [Ethical case studies](#ethical-case-studies)
- **Further reading** (dedicated files)
  - [Relays, Surveillance, and Contributing to Tor](etica-contribuire-e-comunita.md)

---

## Anonymity entails responsibility

Tor provides a powerful anonymity tool. Like any powerful tool, it can be used
to protect or to harm. The difference lies in the user's responsibility.

Anonymity is not a passive state - it is an active condition that requires
continuous choices. Every time I open a terminal and type `proxychains firefox`,
I am choosing to exercise a right. But with that right comes the responsibility
not to abuse it.

### Ethical principles in using Tor

1. **Do not confuse anonymity with impunity**: Tor protects your privacy,
   it does not authorize you to break laws or harm others. Technical anonymity
   does not erase moral responsibility. Those who use Tor to commit crimes
   are not "smarter" - they are abusing an infrastructure built by volunteers
   to protect human rights.

2. **Respect terms of service**: even if you are anonymous, websites have
   rules. Abusing anonymity for spam, aggressive scraping, or ban evasion
   is ethically questionable. I have seen people use Tor to create multiple
   accounts, bypass rate limiting, or brute force logins. This is not
   "research" - it is abuse, and it damages the reputation of exit nodes
   for all other users.

3. **Do not abuse network resources**: Tor is run by volunteers. Using it
   for massive downloads, streaming, or unnecessary traffic overloads the
   network at the expense of those who truly need it (activists, journalists,
   people under surveillance). I learned early that downloading a 3 GB ISO
   via Tor is disrespectful - that bandwidth could serve a journalist in
   Iran who is transmitting a report.

4. **Contribute if you can**: if you have bandwidth and resources, consider
   operating a Tor relay. Every relay adds capacity and diversity to the
   network. A powerful server is not required - even a middle relay on a
   5 EUR/month VPS makes a difference.

5. **Report issues**: if you discover vulnerabilities in Tor or malicious
   relay behavior, report them to the Tor Project. The security of the
   network depends on the vigilance of the entire community.

6. **Educate, do not judge**: when someone asks "how do I use Tor for X?"
   the answer should not be a moral judgment, but accurate information
   about the risks, limitations, and responsibilities. Ignorance is more
   dangerous than knowledge.

---

## The ethical dilemma of anonymity

### Anonymity as a fundamental right

Anonymity is not an invention of the internet. For centuries, writers, thinkers,
and activists have used pseudonyms to protect themselves and their ideas.
The Federalist Papers were published under the pseudonym "Publius." Voltaire
was not his real name. George Orwell was not his real name.

In the digital context, anonymity is even more critical: every online action
leaves traces that can be collected, analyzed, and used against us. Anonymity
is not a luxury - it is a necessity for exercising fundamental rights such as
freedom of expression, freedom of association, and the right to privacy.

The Council of Europe has recognized online anonymity as a component of freedom
of expression. The UN, in the 2015 report by David Kaye (Special Rapporteur
on Freedom of Expression), stated that encryption and anonymity are essential
for the exercise of human rights in the digital age.

### Anonymity as a tool of abuse

But anonymity has a dark side. The same tool that protects a whistleblower
can protect a criminal. The same exit node that allows an activist in China
to access censored information allows a fraudster to mask their identity.

This is the fundamental paradox: **you cannot have selective anonymity**.
You cannot build a system that protects "the good guys" but not "the bad
guys," because the entity that decides who is "good" and who is "bad" is
exactly the type of authority that anonymity is meant to protect against.

### The privacy paradox

There is an aspect that struck me deeply while studying Tor: **those who
need privacy most are often the most vulnerable**. A woman fleeing an
abusive partner. A journalist in an authoritarian regime. An LGBTQ+
activist in a country where homosexuality is a crime. A political dissident.

These people do not have the technical skills of a cybersecurity analyst.
They do not know how to configure proxychains, they do not understand the
difference between a guard node and an exit node (see
[exit-nodes.md](../03-nodi-e-rete/exit-nodes.md) for technical details).
Yet they are the ones who risk their lives if they are deanonymized.

This creates an ethical imperative: those who have the technical skills to
understand and contribute to the Tor network have a responsibility to do so.
Not out of obligation, but out of solidarity with those who cannot do it
alone.

### My position

After years of study and daily use, my position is this: anonymity is a
right, and like every right it must be exercised with responsibility. The
fact that someone can abuse Tor does not justify its elimination, just as
the fact that someone can use a knife to cause harm does not justify
banning knives.

The answer to abuse is not less anonymity - it is more education, more
awareness, and more contributions to the network to make it more robust
and accessible to those who need it.

---

## Who Tor is designed for

Tor was created to protect people in situations where privacy is critical:

- **Journalists in authoritarian countries**: who risk their lives to inform.
  I think of journalists in Turkey, Egypt, Russia, who use Tor to communicate
  with newsrooms and transmit material. SecureDrop, the whistleblower platform
  used by the New York Times, Washington Post, and Guardian, operates
  exclusively through an onion service.

- **Whistleblowers**: who report corruption and abuses of power. Edward Snowden
  used Tor to communicate with journalists. Chelsea Manning used Tor.
  Reality Winner did not - and was caught partly due to OPSEC mistakes
  (see [opsec-e-errori-comuni.md](../05-sicurezza-operativa/opsec-e-errori-comuni.md)
  for real cases of deanonymization).

- **Domestic violence victims**: who seek help without being monitored.
  An abusive partner who controls the home router can see every website
  visited. Tor is the only tool that allows someone to search for a shelter,
  a lawyer, or an emergency number without leaving traces in the router's
  history.

- **Citizens under mass surveillance**: who want to exercise fundamental
  rights without being profiled. This includes us in Europe as well - the
  GDPR is a good start, but mass surveillance does not stop at legislative
  boundaries.

- **Researchers**: who study censorship, security, and privacy. I fall into
  this category. When I study exit node behavior, when I test fingerprinting
  resistance, when I analyze circuits with nyx - I am contributing to the
  collective knowledge about the network.

- **Ordinary citizens who want privacy**: no "special justification" is needed
  to want privacy. Privacy is the default, not the exception. You do not
  have to explain to anyone why you close the bathroom door.

When I use Tor for study and personal privacy, I am using resources shared
with these people. Using them responsibly is an act of respect toward the
community.

---

## Ethical case studies

The ethics of Tor usage are never black or white. Here are some real-world
scenarios where the boundary between legitimate use and abuse is blurred.

### Case 1: The journalist and the source

**Scenario**: An Italian investigative journalist receives documents proving
corruption in a public company. The source uses Tor to send the documents
via SecureDrop. The journalist uses Tor to communicate with the source and
verify the documents.

**Ethical analysis**: This is the use case Tor was designed for. The source
risks being fired (or worse). The journalist risks legal pressure. Anonymity
protects both and allows the information to reach the public.

**But**: the same mechanism also protects those who spread false documents,
who engage in doxxing, who disseminate private information for revenge. The
technology does not distinguish - the responsibility lies with the people.

### Case 2: The security researcher

**Scenario**: A security researcher (like myself) uses Tor to test
vulnerabilities in web services. They use proxychains + nmap to scan a
target, then use Tor Browser to verify XSS or SQL injection on a web
application.

**Ethical analysis**: If the researcher has authorization (bug bounty program,
penetration testing contract, own lab), it is perfectly legitimate. Tor adds
a layer of protection in case the testing is detected and generates false
alarms.

**But**: without authorization, the same activity is illegal and harmful.
"I was just testing the security" is not a legal defense. The difference
between a penetration tester and a criminal is the target's consent.
For the complete legal framework, see [aspetti-legali.md](./aspetti-legali.md).

### Case 3: The corporate whistleblower

**Scenario**: An employee of an Italian company discovers that the company
is illegally dumping toxic waste. They want to report it to the authorities
but fears retaliation. They use Tor to submit an anonymous report to ANAC
(Autorita Nazionale Anticorruzione - Italian National Anti-Corruption
Authority) and to journalists.

**Ethical analysis**: Italy has a whistleblowing law (D.Lgs. 24/2023,
transposing EU Directive 2019/1937) that protects whistleblowers. But legal
protection is not always sufficient - retaliation can be subtle (workplace
bullying, demotion, exclusion). Tor's technical anonymity adds a layer of
protection that the law alone does not guarantee.

**The complexity**: the whistleblower is acting in the public interest. But
what about the employee who uses Tor to leak trade secrets to a competitor?
The technology is identical - the ethics are opposite.

### Case 4: The activist and surveillance

**Scenario**: An environmental activist in Italy uses Tor to organize
protests and communicate with other activists. They are not doing anything
illegal, but they know that protest movements are often surveilled by law
enforcement.

**Ethical analysis**: The right to assembly and association is protected
by the Italian Constitution (Art. 17 and 18). Using Tor to organize is the
digital equivalent of meeting in a private location. But preventive
surveillance of protest movements is a documented reality, even in Western
democracies.

**The dilemma**: if the police surveil a movement to prevent violence, is
it legitimate? If an activist uses Tor to avoid that surveillance, is it
legitimate? Both can be right - and this is exactly the type of dilemma
that Tor makes visible.

---

> **Continues in** [Ethics - Relays, Surveillance, and Contributing to Tor](etica-contribuire-e-comunita.md)
> - relay operator responsibility, mass surveillance, contributing to
> the network (relays, donations, translation), community and resources.

---

## See also

- [Legal Aspects](aspetti-legali.md) - Italy/EU legal framework, legal precedents
- [Exit Nodes](../03-nodi-e-rete/exit-nodes.md) - Exit operator responsibility
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Responsible and informed use
