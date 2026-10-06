import 'dart:typed_data';

import 'package:openmls/openmls.dart';

import 'package:tremulator_keys/src/errors.dart';

/// What kind of thing an encrypted blob is, read from its unencrypted header.
enum BlobKind {
  /// A text or other application message.
  message,

  /// A change to the conversation (someone added, removed, or keys rotated).
  commit,

  /// A proposed change that has not been committed.
  proposal,

  /// Something else, or unreadable. A welcome lands here: the library reads
  /// the header of protocol messages only (openmls_dart 3.2.1
  /// `rust/src/api/engine.rs`, `mls_message_content_type`: "Not a protocol
  /// message"). The mailbox knows a welcome by its Communication category.
  other,
}

/// Which conversation a blob belongs to, without decrypting it.
///
/// The mailbox uses this to route a collected blob to the right
/// conversation before anything is decrypted.
Uint8List peekConversationId(Uint8List blob) {
  try {
    return mlsMessageExtractGroupId(messageBytes: blob);
  } catch (e) {
    throw KeysError('not an MLS message: $e');
  }
}

/// The epoch a blob was written in, without decrypting it.
BigInt peekEpoch(Uint8List blob) {
  try {
    return mlsMessageExtractEpoch(messageBytes: blob);
  } catch (e) {
    throw KeysError('not an MLS message: $e');
  }
}

/// What kind of blob this is, from its header.
BlobKind peekKind(Uint8List blob) {
  final String kind;
  try {
    kind = mlsMessageContentType(messageBytes: blob);
  } catch (_) {
    return BlobKind.other;
  }
  switch (kind.toLowerCase()) {
    case 'application':
      return BlobKind.message;
    case 'commit':
      return BlobKind.commit;
    case 'proposal':
      return BlobKind.proposal;
    default:
      return BlobKind.other;
  }
}
