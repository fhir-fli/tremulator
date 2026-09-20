# Open: 11. Nothing is built until these are answered or deferred with a date.

Delete a question when it is answered, and record the ruling in the document it
governs.

**Q1. Can tremulator, and anything that uses it, be AGPL-3.0?**
The Matrix Dart SDK and the Dart vodozemac bindings are both AGPL. Linking them
makes bumblebee AGPL and stops a permissive pub.dev release. FluffyChat ships
AGPL on both app stores, so distribution is not the blocker. The blocker is
whether MayJuun ever needs a closed consumer of this package. If no, the Matrix
path opens and this gets much cheaper. If yes, we write our own bindings to the
permissive Rust library, which is months.

**Q2. Who runs the server, the TURN relay and the push credentials, per
deployment, and who is on the hook when it goes down at 3 a.m.?**
This is an operating cost and a legal exposure, not a technical detail. The
University of Miami and Panamerican Trauma Society team, MayJuun, or the
deployment itself.

**Q3. Is the message channel part of the record, or deliberately unsuitable for
anything that matters?**
Grady chose the second: purge every 72 hours, and an explicit prohibition on
using it for critical information, urgent results, or peer-review content. That
also resolves the emergency-access conflict in the HIPAA technical safeguards.
The opposite design, where the consult is the record, is defensible but
demands retention, break-glass and discovery handling. These are opposite
builds. Pick one before anything is written.

**Q4. Patient-to-clinician: in scope now, later, or never?**
It changes identity, consent and the regulatory surface completely.

**Q5. Must a remote consultant be reachable without installing anything?**
If the consultant is "whoever is on call at a university hospital", a browser
client is mandatory and that rules out some options. If it is a named volunteer
panel who will install an app, it does not.

**Q6. Must it work with no internet at all, two handsets on a field LAN?**
If yes, native ringing cannot depend on Apple or Google push, and that is a
real design constraint from day one rather than a later addition.

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
