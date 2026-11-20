import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:openmls/openmls.dart';
import 'package:test/test.dart';
import 'package:tremulator_keys/src/mls_message.dart';
import 'package:tremulator_keys/tremulator_keys.dart';

/// E2, the part that runs through this package: the MLS working group's
/// published test vectors (mlswg/mls-implementations `test-vectors.md`, files
/// in `test/mls_vectors/`, see SOURCE.md there) against the code here that
/// reads MLS bytes itself (`mls_message.dart`) and the library calls the
/// mailbox uses to sort blobs unopened (`peek.dart`).
///
/// The vectors ask, for these files:
/// - deserialization: each `vlbytes_header` decodes to `length`;
/// - messages: each field decodes as its structure and re-encodes to the
///   same bytes.
///
/// What is checked here, for every entry: the vector-length headers; key
/// packages unwrapped and wrapped again give the same bytes; GroupInfo
/// messages read exactly to the end; every PublicMessage and PrivateMessage
/// gives the group, epoch and kind its header holds; welcomes are not taken
/// for a key package or a protocol message.
///
/// The header fields are read by a second, separate reader in this file
/// (`_framing`, from RFC 9420 section 6, rfc9420.txt read 2026-11-20), not by
/// the code under test. The checks the rest of the vectors ask for (key
/// schedule, secret tree, joining from a welcome with given private keys,
/// following a group as a passive member, ...) need steps the Dart library
/// does not offer; they run against the library itself in
/// `lab/e2/openmls_kats.sh`.
void main() {
  setUpAll(Openmls.init);

  test('deserialization.json: every length header gives its length', () {
    final cases = _load('deserialization');
    expect(cases, hasLength(14));
    for (final c in cases) {
      final header = _hex(c['vlbytes_header']! as String);
      expect(
        vectorLengthOf(header),
        c['length'],
        reason: c['vlbytes_header']! as String,
      );
    }
  });

  group('messages.json', () {
    final cases = _load('messages');

    test('has the 300 entries it had when copied', () {
      expect(cases, hasLength(300));
    });

    test('every key package unwraps and wraps back to the same bytes', () {
      for (final (i, c) in cases.indexed) {
        _roundTrip(_hex(c['mls_key_package']! as String), 'entry $i');
      }
    });

    test('every GroupInfo reads exactly to its end', () {
      for (final (i, c) in cases.indexed) {
        final m = _hex(c['mls_group_info']! as String);
        expect(() => confirmationTagOf(m), returnsNormally, reason: 'entry $i');
      }
    });

    test(
      'every public and private message gives its group, epoch and kind',
      () {
        var n = 0;
        for (final (i, c) in cases.indexed) {
          for (final field in [
            'public_message_application',
            'public_message_proposal',
            'public_message_commit',
            'private_message',
          ]) {
            _peeks(_hex(c[field]! as String), 'entry $i $field');
            n++;
          }
        }
        expect(n, 1200);
      },
    );

    test('a welcome is neither a key package nor a protocol message', () {
      for (final (i, c) in cases.indexed) {
        _welcome(_hex(c['mls_welcome']! as String), 'entry $i');
      }
    });
  });

  test('welcome.json: key packages round-trip, welcomes are welcomes', () {
    final cases = _load('welcome');
    expect(cases, hasLength(7));
    for (final c in cases) {
      final suite = c['cipher_suite'];
      _roundTrip(_hex(c['key_package']! as String), 'suite $suite');
      _welcome(_hex(c['welcome']! as String), 'suite $suite');
    }
  });

  for (final (file, count) in [
    ('passive-client-welcome', 56),
    ('passive-client-handling-commit', 91),
    ('passive-client-random', 1),
  ]) {
    test("$file.json: key packages, welcomes and every epoch's messages", () {
      final cases = _load(file);
      expect(cases, hasLength(count));
      var messages = 0;
      for (final (i, c) in cases.indexed) {
        _roundTrip(_hex(c['key_package']! as String), 'entry $i');
        _welcome(_hex(c['welcome']! as String), 'entry $i');
        for (final (e, epoch)
            in (c['epochs']! as List).cast<Map<String, Object?>>().indexed) {
          for (final p in (epoch['proposals']! as List).cast<String>()) {
            _peeks(_hex(p), 'entry $i epoch $e proposal');
            messages++;
          }
          _peeks(_hex(epoch['commit']! as String), 'entry $i epoch $e commit');
          messages++;
        }
      }
      // ignore: avoid_print
      print('$file: $count scenarios, $messages messages');
    });
  }
}

List<Map<String, Object?>> _load(String name) {
  final f = File('test/mls_vectors/$name.json');
  return (jsonDecode(f.readAsStringSync())! as List)
      .cast<Map<String, Object?>>();
}

Uint8List _hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

void _roundTrip(Uint8List message, String where) {
  expect(message.sublist(0, 4), [0, 1, 0, 5], reason: '$where: header');
  expect(
    wrapKeyPackage(unwrapKeyPackage(message)),
    message,
    reason: where,
  );
}

void _welcome(Uint8List message, String where) {
  expect(message.sublist(0, 4), [0, 1, 0, 3], reason: '$where: header');
  expect(
    () => unwrapKeyPackage(message),
    throwsA(isA<KeysError>()),
    reason: where,
  );
  expect(peekKind(message), BlobKind.other, reason: where);
}

void _peeks(Uint8List message, String where) {
  final f = _framing(message);
  expect(peekConversationId(message), f.groupId, reason: where);
  expect(peekEpoch(message), f.epoch, reason: where);
  expect(
    peekKind(message),
    const {
      1: BlobKind.message,
      2: BlobKind.proposal,
      3: BlobKind.commit,
    }[f.contentType],
    reason: '$where: content type ${f.contentType}',
  );
}

/// group_id, epoch and content_type of an MLSMessage holding a
/// PublicMessage (wire format 1: FramedContent `group_id<V>`, uint64 epoch,
/// Sender, `authenticated_data<V>`, ContentType) or a PrivateMessage (wire
/// format 2: `group_id<V>`, uint64 epoch, ContentType), RFC 9420 sections 6,
/// 6.2 and 6.3. Sender: uint8 sender_type, then a uint32 for member (1) and
/// external (2), nothing for new_member_proposal (3) and new_member_commit
/// (4).
({Uint8List groupId, BigInt epoch, int contentType}) _framing(Uint8List m) {
  var at = 0;
  int uint(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 8) | m[at++];
    }
    return v;
  }

  Uint8List opaque() {
    final first = m[at];
    final size = 1 << (first >> 6);
    var n = first & 0x3F;
    for (var i = 1; i < size; i++) {
      n = (n << 8) | m[at + i];
    }
    at += size;
    return Uint8List.sublistView(m, at, at += n);
  }

  expect(uint(2), 1, reason: 'mls10');
  final wireFormat = uint(2);
  final groupId = opaque();
  final epoch = (BigInt.from(uint(4)) << 32) + BigInt.from(uint(4));
  if (wireFormat == 1) {
    final senderType = uint(1);
    if (senderType == 1 || senderType == 2) uint(4);
    opaque(); // authenticated_data
  } else {
    expect(wireFormat, 2, reason: 'public or private message');
  }
  return (groupId: groupId, epoch: epoch, contentType: uint(1));
}
