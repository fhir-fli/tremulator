# Threat model

Draft. Gate 0 closes when Grey has signed off on the in/out columns.

## Adversaries

| # | Adversary | Tremulator must prevent | Tremulator does not prevent |
|---|---|---|---|
| A1 | Whoever operates the server (us, a deployment, a hosting provider) | reading message content, media, or attachments | seeing who talked to whom, when, how long, how big |
| A2 | Network observer in-country, including a lawful-intercept order on the carrier | content | that a clinical conversation happened, and with which endpoint |
| A3 | A seized or stolen handset, powered off | reading stored history without the device credential | anything, if the device is unlocked when seized |
| A4 | A seized handset, unlocked, at a border or checkpoint | nothing | everything. This is a duress problem, not a crypto problem. See Q7 |
| A5 | A malicious or compromised app on the same handset | reading our storage outside the OS sandbox | screen capture and accessibility abuse on a rooted device |
| A6 | A clinician inside the deployment misusing access | reading a conversation they are not party to; writing to the chart as someone else | screenshotting their own conversations |
| A7 | A lost device that is never recovered | that device reading anything sent after revocation | that device reading what it already received |
| A8 | Litigation or subpoena | nothing. Retention policy decides what exists to produce | — |
| A9 | A future adversary recording ciphertext now to decrypt later | forward secrecy on the message channel | traffic already recorded if long-term keys leak and the protocol lacks PCS. Check at Gate 2 |

## Things the pasted analyses did not raise, and that matter here

- **Encryption law in the host country.** Some states restrict or licence
  end-to-end encrypted communication tools. An app that looks like a secure
  messenger can also put the clinician carrying it at risk at a checkpoint.
  Gate 0 must check this per deployment country, not assume.
- **Identity, not just confidentiality.** Signal proves a phone number. It does
  not prove the person on the other end is the on-call surgeon. The roster is
  the trust anchor, and it belongs to the deploying organisation.
- **Push infrastructure is a dependency and a leak.** Native ringing needs Apple
  Push Notification service or Firebase Cloud Messaging. Firebase needs Google
  Play services, which a field handset may not have, and push metadata goes
  through Apple or Google regardless. Offline-LAN calling needs a path that
  does not touch either.

## 45 CFR 164.312 conformance matrix

Text read verbatim from eCFR on 2026-09-20. Fill the right-hand column in
Gate 0; each row becomes a test in [SUCCESS.md](SUCCESS.md).

| Cite | Standard / specification | Required or Addressable | How tremulator meets it |
|---|---|---|---|
| (a)(1) | Access control | Standard | |
| (a)(2)(i) | Unique user identification | Required | |
| (a)(2)(ii) | **Emergency access procedure** | **Required** | **open conflict, see below** |
| (a)(2)(iii) | Automatic logoff | Addressable | |
| (a)(2)(iv) | Encryption and decryption | Addressable | |
| (b) | Audit controls | Standard | |
| (c)(1) | Integrity | Standard | |
| (c)(2) | Mechanism to authenticate ePHI | Addressable | |
| (d) | Person or entity authentication | Standard | |
| (e)(1) | Transmission security | Standard | |
| (e)(2)(i) | Integrity controls | Addressable | |
| (e)(2)(ii) | Encryption | Addressable | |

**The conflict.** (a)(2)(ii) requires procedures for obtaining necessary ePHI
during an emergency, and it is Required, not Addressable. End-to-end encryption
means the server holds no key, so there is no server-side break-glass. Either
the clinical content lives in the chart and the message channel is explicitly
not the source of ePHI, which resolves it, or a key-escrow mechanism is needed,
which undoes the security model. This is the strongest argument for the Grady
design: keep consequential content out of the channel. Q3 decides it.

Also open: whether the 2025 proposed Security Rule update has been finalised.
The eCFR text above is still the 2013 amendment. Status UNKNOWN, check in Gate 0.
