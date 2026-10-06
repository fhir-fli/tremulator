/// Talks to the group's fhirant server. Never sees plaintext.
///
/// Everything on the server is an ordinary FHIR resource (docs/GATE2-PLAN.md,
/// "Mailbox"): each phone is a `Device`; every encrypted blob is a
/// `Communication` from one Device to others, carrying the bytes as an
/// attachment of type `message/mls`; the wake-up is fhirant's R4
/// `Subscription` websocket.
library;

export 'src/envelope.dart';
export 'src/labels.dart';
export 'src/mailbox.dart';
export 'src/session.dart';
export 'src/wakeup.dart';
