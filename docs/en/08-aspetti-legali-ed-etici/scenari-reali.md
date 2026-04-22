> **Lingua / Language**: [Italiano](../../08-aspetti-legali-ed-etici/scenari-reali.md) | English

# Real-World Scenarios - Legal and Ethical Aspects of Tor in Action

Operational cases in which legal aspects, relay operator liability,
ethics of anonymity, and legality boundaries had concrete impact during
penetration tests, professional activities, and incident management.

---

## Table of Contents

- [Scenario 1: Exit relay operated by a consultant receives abuse complaint during pentest](#scenario-1-exit-relay-operated-by-a-consultant-receives-abuse-complaint-during-pentest)
- [Scenario 2: Pentest via Tor - scope creep and legal risk](#scenario-2-pentest-via-tor--scope-creep-and-legal-risk)
- [Scenario 3: Corporate whistleblower - insufficient legal OPSEC](#scenario-3-corporate-whistleblower--insufficient-legal-opsec)
- [Scenario 4: Dual-use tool downloaded from .onion - implications for the team](#scenario-4-dual-use-tool-downloaded-from-onion--implications-for-the-team)

---

## Scenario 1: Exit relay operated by a consultant receives abuse complaint during pentest

### Context

An Italian security consultant was operating a Tor exit relay on a VPS
in Germany as a contribution to the network. Separately, another team
from his company was conducting an authorized pentest on a client. By
coincidence, part of the pentest traffic transited through the consultant's
exit relay.

### Problem

The client's SOC detected suspicious activity (scanning) from the exit
relay's IP. Not knowing it was a Tor relay, they sent an abuse complaint
to the German hosting provider:

```
Abuse complaint -> hosting provider (Hetzner)
  "Your IP 168.x.x.x performed port scanning on our server"
  
Hetzner -> consultant:
  "We received an abuse report for your server.
   You have 24 hours to respond or we will suspend the service."

Timeline:
  1. The consultant responds with the Tor Exit Notice template
  2. Hetzner accepts the explanation (Hetzner is Tor-friendly)
  3. But the pentest client sees "Tor exit" in the response
  4. The client asks: "Why is a Tor exit from your company
     scanning our servers?"
  -> Coincidence, but the perception is devastating
```

### How it was handled

```
1. The consultant documented:
   - The exit relay is a personal contribution, not corporate
   - The pentest traffic transited coincidentally
   - The relay logs contain no useful information (by design)

2. The company updated its internal policy:
   - Employees operating Tor relays must disclose it
   - Exit relays on IPs not traceable to the company
   - Or use different hosting providers for relays and corporate infrastructure

3. Communication to the client:
   - Technical explanation of how Tor works
   - Demonstration that the pentest used different IPs (Burp logs)
   - Report updated with a note about the coincidence
```

### Lesson learned

Operating an exit relay is legal and commendable, but it creates a
reputational risk if the IP is traceable to your organization. Separate
relay infrastructure from professional infrastructure.
See [Legal Aspects - Relays](aspetti-legali-relay-e-confronto.md)
for details on liability and safe harbor.

---

## Scenario 2: Pentest via Tor - scope creep and legal risk

### Context

A pentester was using Tor for the external reconnaissance phase on an
authorized target. The contract specified the scope as "*.target.com."
During reconnaissance, they found a subdomain (dev.target.com) that
pointed to an IP on a different cloud provider, managed by a third party.

### Problem

```
Contractual scope: *.target.com
dev.target.com -> 35.x.x.x (AWS, managed by third-party vendor)

The pentester executed:
  proxychains nmap -sT -Pn dev.target.com -p 80,443,8080
  proxychains nikto -h https://dev.target.com

Technically: the domain is in scope (*.target.com)
Legally: the underlying infrastructure belongs to a third party (the AWS vendor)
-> The pentester is scanning UNAUTHORIZED infrastructure

If the vendor reports the activity:
  - The exit IP is a Tor exit -> not traceable to the pentester
  - But the logs show scanning from Tor on AWS infrastructure
  - AWS could report abuse to the Tor Project
  - If identified: potential Art. 615-ter c.p. (unauthorized access)
```

### Procedural fix

```
1. BEFORE testing any target:
   - Verify infrastructure ownership (whois, ASN)
   - If the infrastructure belongs to a third party -> request specific authorization
   - Document in the report: "excluded dev.target.com (third-party infra)"

2. In the contract:
   - Clause defining scope by IP, not just by domain
   - Clause explicitly excluding third-party infrastructure
   - Indemnification clause for in-scope activities

3. Tor is not a legal shield:
   - Anonymity does NOT erase the offense
   - "I was using Tor" is not a defense in court
   - Written authorization is the ONLY legal protection
```

### Lesson learned

Tor hides the IP, not legal liability. A pentest without explicit
authorization for the specific infrastructure is a crime
(Art. 615-ter c.p.), regardless of whether Tor is used.
Reconnaissance via Tor does not make legal what is illegal.
See [Legal Aspects](aspetti-legali.md) for the complete regulatory framework.

---

## Scenario 3: Corporate whistleblower - insufficient legal OPSEC

### Context

An employee of an Italian company discovered serious accounting
irregularities. They decided to report to ANAC (Autorita Nazionale
Anticorruzione - Italian National Anti-Corruption Authority) using
Tor to protect against retaliation. Italy has a whistleblowing law
(D.Lgs. 24/2023).

### Problem

The employee used Tor correctly for the technical submission, but
made legal OPSEC mistakes:

```
What they did right:
  + Tor Browser for the ANAC submission
  + No login with personal accounts
  + Submission from a public WiFi network (not corporate)

What they did wrong:
  x Attached a Word document to the submission
    -> The file metadata contained: username, PC name, creation date
    -> The username matched their corporate account
    -> The creation date was during working hours

  x Used information that only 3 people could have known
    -> The company identified the circle of suspects by elimination
    -> The document with metadata confirmed the identity

  x Did not consult a lawyer BEFORE the submission
    -> The whistleblowing law provides protection, but documentation is needed
    -> Without legal assistance, the protection is weaker
```

### How they should have proceeded

```
1. Consult a specialized lawyer BEFORE taking action
   -> The lawyer guides on the necessary documentation
   -> Legal protection is stronger with professional assistance

2. Clean document metadata:
   exiftool -all= documento.docx
   # Or copy the content into a new text file

3. Evaluate whether the information is identifying:
   -> If only 3 people know X, reporting X identifies the circle
   -> Include only information accessible to many employees
   -> Or accept the risk with adequate legal protection

4. Use dedicated channels:
   -> Newspaper's SecureDrop (if available)
   -> GlobaLeaks for anonymous reports
   -> ANAC has a dedicated whistleblowing channel
```

### Lesson learned

Technical anonymity (Tor) is not sufficient without OPSEC on the content.
Document metadata, the content of the information, and timing can
deanonymize you even with a perfectly anonymous connection. For
whistleblowing, legal protection (D.Lgs. 24/2023) is as important as
technical protection. See [Ethics and Responsibility](etica-e-responsabilita.md)
for ethical principles and [OPSEC](../05-sicurezza-operativa/opsec-e-errori-comuni.md)
for common mistakes.

---

## Scenario 4: Dual-use tool downloaded from .onion - implications for the team

### Context

During a red team engagement, an operator found a custom exploitation tool
on a .onion forum for a specific vulnerability of the target. The tool was
not available on public repositories. The operator downloaded it and wanted
to use it in the engagement.

### Problem

```
Risks identified by the team lead:

1. Unknown provenance:
   - The tool could contain backdoors
   - The tool could be a law enforcement honeypot
   - No possibility of source code audit

2. Legal implications:
   - Possession of exploitation tools is not a crime in Italy
     (if for legitimate professional purposes)
   - BUT: if the tool contains undisclosed functionality
     (e.g., data exfiltration to third parties), the operator could
     be held jointly liable

3. Contractual implications:
   - The pentest contract specifies the approved tools
   - Tools from unverified sources could violate the contract
   - If the tool causes unexpected damage, the team is liable

4. Chain of custody:
   - The pentest report must document the tools used
   - "Tool downloaded from a .onion forum" is not presentable
   - The client could challenge the results
```

### Team decision

```
1. DO NOT use the tool directly
   -> Backdoor risk too high for a professional engagement

2. Analyze the tool in an isolated environment:
   - VM without network, pre-analysis snapshot
   - Reverse engineering of the binary
   - If it contains suspicious functionality -> discard
   - If the code is clean -> evaluate

3. Recreate the functionality with own tools:
   - Study the exploitation technique from the tool
   - Reimplement with known and verified tools (Metasploit, custom script)
   - Documentable and auditable in the report

4. Updated policy:
   - Tools from unverified sources: mandatory analysis before use
   - Documentation of provenance in the internal report
   - Team lead approval for any non-standard tools
```

### Lesson learned

Accessing .onion is legal, but downloaded content can create legal,
contractual, and security problems. In a professional context, the
provenance of tools is as important as their effectiveness. Never use
unverified tools in an engagement - the risk outweighs the benefit.
See [Ethics and Responsibility](etica-e-responsabilita.md) for the ethical
framework and [Legal Aspects](aspetti-legali.md) for the legality of
dual-use tools.

---

## Summary

| Scenario | Area | Risk mitigated |
|----------|------|----------------|
| Exit relay and abuse complaint | Relay liability | Conflict between personal contribution and professional role |
| Scope creep in pentest | Pentest legality | Unauthorized access to out-of-scope third-party infra |
| Whistleblower with metadata leak | Legal OPSEC | Deanonymization via document metadata |
| Tool from .onion in engagement | Professional ethics | Backdoors, liability, chain of custody |

---

## See also

- [Legal Aspects](aspetti-legali.md) - Legality in Italy, criminal code, GDPR
- [Legal Aspects - Relays and Comparison](aspetti-legali-relay-e-confronto.md) - Operating relays, safe harbor
- [Ethics and Responsibility](etica-e-responsabilita.md) - Ethical principles, anonymity dilemma
- [OPSEC and Common Mistakes](../05-sicurezza-operativa/opsec-e-errori-comuni.md) - Mistakes and metadata
- [Forensic Analysis](../05-sicurezza-operativa/analisi-forense-e-artefatti.md) - Artifacts and traces
