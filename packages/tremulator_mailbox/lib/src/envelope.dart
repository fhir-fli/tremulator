import 'dart:typed_data';

import 'package:tremulator_mailbox/src/labels.dart';

/// One blob collected from the server, still encrypted.
class Envelope {
  /// A collected blob.
  const Envelope({
    required this.id,
    required this.label,
    required this.bytes,
    this.from,
    this.extra = const [],
    this.sent,
  });

  /// The server's id for it; pass to `acknowledge` once stored.
  final String id;

  /// What it is.
  final Label label;

  /// The first payload: the MLS message.
  final Uint8List bytes;

  /// Further payloads, in order. For a commit: the GroupInfo, then the key
  /// tree, which together are the snapshot an out-of-step phone rejoins from.
  final List<Uint8List> extra;

  /// The sending Device's id, if the sender said.
  final String? from;

  /// When the sender said it was sent, as the server stored it.
  final String? sent;
}
