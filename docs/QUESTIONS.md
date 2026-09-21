# Tremulator — open decisions

**4 questions are open.** Nothing is built until each is
answered or deferred with a date.

When one is answered, DELETE the question from this file and record the ruling
in the document it governs. Never leave an answered question sitting here.

## Closed

- **Q8, the reference app, is WhatsApp.** Agreed 2026-09-21: it is what
  clinicians use now, so matching it on bad networks is what makes them switch.
  Its Gate 1 numbers are the bar for Gates 3 to 5.
- **Q7, a phone seized while unlocked, moves to bumblebee.** Grey, 2026-09-21: it
  is bigger than messages, since the chart on the same phone matters as much.
  Bumblebee's SECURITY-MODEL.md already names checkpoint seizure as a threat,
  keeps restricted records off standard phones, purges by cryptographic erase
  (NIST SP 800-88r2) and plans remote wipe. It has no quick-wipe or duress PIN;
  that is to be decided there, once, for the whole app. Tremulator follows it,
  and its messages already purge by destroying keys (D8).
- **Q12, ringing a closed app over the internet, is answered by D12.** One
  app; FHIR-FLI runs a separate wake-up relay that stores nothing.
- **Q2, who runs the servers, is answered by D11.** Each group runs its own;
  FHIR-FLI runs nothing; everything must work with no internet. One piece it
  leaves open is Q12 below.
- **Q5, browser access, is answered by D10.** Installed app on every platform
  Flutter builds for; no web for now.
- **Q3, whether the chat is part of the record, is closed by D8.** It is not.
  Messages are deleted on a schedule; decisions go into the record first.
- **Q6, messaging with no internet, is answered.** Yes, at least text between
  phones on the same local network. How ordering works for those
  conversations is in D4, still open.
- **Q1, the AGPL question, is closed by D1 in DECISIONS.md.** The stack is MLS
  through the MIT `openmls` package, so nothing in it is AGPL and the repo stays
  MIT.

**Q4. Patient-to-clinician: in scope now, later, or never?**
It changes identity, consent and the regulatory surface completely.

**Q9. Which deployment is first, and therefore whose law binds?**
The answer decides the regulatory register. If it is the Miami group's next
deployment, the binding regime is the host country's act, not HIPAA.

**Q10. Does tremulator go to pub.dev, or does it stay inside the apps?**
Depends on Q1, and on whether anyone outside FHIR-FLI is meant to use it.

**Q11. Is there money for an external cryptographic review?**
If there is not, the correct decision is to adopt more and build less, because
an unreviewed protocol we wrote ourselves is worse than a reviewed one we did
not.
