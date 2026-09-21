# Tremulator — open decisions

**8 questions are open.** Nothing is built until each is
answered or deferred with a date.

When one is answered, DELETE the question from this file and record the ruling
in the document it governs. Never leave an answered question sitting here.

## Closed

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

**Q12. Over the internet, how does a closed app ring?**
Apple and Google only deliver a push signed with keys issued to whoever
published the app in their stores. FHIR-FLI will not run anything, so one of
these has to give: each group publishes its own build of the app and holds its
own keys; or the app rings a closed phone only on the deployment's local Wi-Fi,
and a remote consultant sees a call or message when they next open the app.

