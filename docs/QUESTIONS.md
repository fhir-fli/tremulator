# Tremulator — open decisions

**8 questions are open.** Nothing is built until each is
answered or deferred with a date.

When one is answered, DELETE the question from this file and record the ruling
in the document it governs. Never leave an answered question sitting here.

## Closed

- **Q3, whether the chat is part of the record, is closed by D8.** It is not.
  Messages are deleted on a schedule; decisions go into the record first.
- **Q6, messaging with no internet, is answered.** Yes, at least text between
  phones on the same local network. How ordering works for those
  conversations is in D4, still open.
- **Q1, the AGPL question, is closed by D1 in DECISIONS.md.** The stack is MLS
  through the MIT `openmls` package, so nothing in it is AGPL and the repo stays
  MIT.

**Q2. Who runs the server, the TURN relay and the push credentials, per
deployment, and who is on the hook when it goes down at 3 a.m.?**
This is an operating cost and a legal exposure, not a technical detail. The
University of Miami and Panamerican Trauma Society team, MayJuun, or the
deployment itself.

**Q4. Patient-to-clinician: in scope now, later, or never?**
It changes identity, consent and the regulatory surface completely.

**Q5. Must a remote consultant be reachable without installing anything?**
If the consultant is "whoever is on call at a university hospital", a browser
client is mandatory and that rules out some options. If it is a named volunteer
panel who will install an app, it does not.

**Q7. Duress and device seizure: requirement or accepted risk?**
An unlocked handset at a checkpoint gives up everything. Options exist, such as
a short history window on the device or a duress credential, and they all cost
usability. State the position rather than leaving it implied.

**Q8. Which existing app do we baseline against?**
Whatever we measure it on, it becomes the number every later gate is judged
against. Signal, Element or WhatsApp.

**Q9. Which deployment is first, and therefore whose law binds?**
The answer decides the regulatory register. If it is the Miami group's next
deployment, the binding regime is the host country's act, not HIPAA.

**Q10. Does tremulator go to pub.dev, or does it stay inside the apps?**
Depends on Q1, and on whether anyone outside FHIR-FLI is meant to use it.

**Q11. Is there money for an external cryptographic review?**
If there is not, the correct decision is to adopt more and build less, because
an unreviewed protocol we wrote ourselves is worse than a reviewed one we did
not.
