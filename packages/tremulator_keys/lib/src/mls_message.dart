import 'dart:typed_data';

import 'package:tremulator_keys/src/errors.dart';

/// The MLSMessage header, RFC 9420 section 6 (rfc9420.txt, read
/// 2026-11-02): ProtocolVersion `mls10(1)`, then the WireFormat from the
/// IANA "MLS Wire Formats" registry (mls-wire-formats.csv, read 2026-11-02).
/// `message/mls` (section 17.10) carries an MLSMessage, so every blob this
/// package hands out starts with one.
const _mls10 = 1;
const _groupInfo = 4;
const _keyPackage = 5;

/// [keyPackage] (a bare KeyPackage, as the library makes it) as an
/// MLSMessage of kind mls_key_package. The KeyPackage follows the header
/// as it is: section 6 selects it in place, with no length of its own.
Uint8List wrapKeyPackage(Uint8List keyPackage) => Uint8List.fromList([
  0,
  _mls10,
  0,
  _keyPackage,
  ...keyPackage,
]);

/// The bare KeyPackage inside [message], for the library.
Uint8List unwrapKeyPackage(Uint8List message) {
  final r = _Reader(message)..header(_keyPackage);
  return Uint8List.sublistView(message, r.at);
}

/// The confirmation tag inside [groupInfo], an MLSMessage of kind
/// mls_group_info. Section 12.4.3:
///
///     struct {
///         GroupContext group_context;
///         Extension extensions<V>;
///         MAC confirmation_tag;
///         uint32 signer;
///         opaque signature<V>;
///     } GroupInfo;
///
/// and section 8.1, GroupContext: version (uint16), cipher_suite (uint16),
/// `group_id<V>`, epoch (uint64), `tree_hash<V>`,
/// `confirmed_transcript_hash<V>`, `extensions<V>`. MAC is `opaque MAC<V>`
/// (section 6.1). The whole message must be read exactly.
Uint8List confirmationTagOf(Uint8List groupInfo) {
  final r = _Reader(groupInfo)
    ..header(_groupInfo)
    ..fixed(2) // version
    ..fixed(2) // cipher_suite
    ..vector() // group_id
    ..fixed(8) // epoch
    ..vector() // tree_hash
    ..vector() // confirmed_transcript_hash
    ..vector() // GroupContext.extensions
    ..vector(); // GroupInfo.extensions
  final tag = r.vector();
  r
    ..fixed(4) // signer
    ..vector() // signature
    ..end();
  return tag;
}

/// The MAC value in [serialized], an `opaque MAC<V>` as the library hands
/// a confirmation tag out (its length first), so it compares with
/// [confirmationTagOf].
Uint8List macValue(Uint8List serialized) {
  final r = _Reader(serialized);
  final value = r.vector();
  r.end();
  return value;
}

class _Reader {
  _Reader(this.b);

  final Uint8List b;
  int at = 0;

  void header(int wireFormat) {
    if (_uint16() != _mls10) {
      throw const KeysError('not an MLS 1.0 message');
    }
    final kind = _uint16();
    if (kind != wireFormat) {
      throw KeysError('MLS message of kind $kind, expected $wireFormat');
    }
  }

  Uint8List fixed(int n) {
    _need(n);
    return Uint8List.sublistView(b, at, at += n);
  }

  /// An `opaque x<V>`: the length as a variable-size integer (section
  /// 2.1.2: the top two bits of the first byte give 1, 2 or 4 bytes, 11 is
  /// invalid, and the shortest encoding is required), then the bytes.
  Uint8List vector() {
    _need(1);
    final prefix = b[at] >> 6;
    if (prefix == 3) {
      throw const KeysError('malformed MLS message: length prefix 11');
    }
    final size = 1 << prefix;
    _need(size);
    var n = b[at] & 0x3F;
    for (var i = 1; i < size; i++) {
      n = (n << 8) | b[at + i];
    }
    if (prefix > 0 && n < const [0, 64, 16384][prefix]) {
      throw const KeysError('malformed MLS message: length not minimal');
    }
    at += size;
    return fixed(n);
  }

  void end() {
    if (at != b.length) {
      throw const KeysError('malformed MLS message: bytes left over');
    }
  }

  int _uint16() {
    final x = fixed(2);
    return (x[0] << 8) | x[1];
  }

  void _need(int n) {
    if (at + n > b.length) {
      throw const KeysError('malformed MLS message: cut short');
    }
  }
}
