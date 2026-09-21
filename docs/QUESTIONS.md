# Tremulator — open decisions

**Nothing is open.** Every Phase 0 question is answered; rulings are in
DECISIONS.md. New questions go below, with the open count updated here.

When one is answered, DELETE the question from this file and record the ruling
in the document it governs. Never leave an answered question sitting here.

## Closed

- **Q9, whose law binds, is answered by D15.** All 195 countries were checked
  on 2026-09-21 and the defaults hold in every country with data. Each
  deployment still reads its own country's law first.
- **Q4, patients messaging clinicians, is later.** Grey, 2026-09-21. Out of
  scope for the first build.
- **Q10, pub.dev, is fine but not the goal.** Grey, 2026-09-21: publishing is
  acceptable, unlike the FHIR packages it is not the primary aim. Everything in
  the stack is MIT, so nothing blocks it.
- **Q11, money for review, is none at present.** Grey, 2026-09-21. The free routes
  in DESIGN.md step 6 are the plan: the Open Technology Fund's Red Team Lab, if
  it qualifies, and putting the design in front of the MLS working group and the
  OpenMLS maintainers.
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
