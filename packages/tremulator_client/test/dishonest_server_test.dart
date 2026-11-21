import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_keys/tremulator_keys.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';
import 'package:tremulator_test_server/tremulator_test_server.dart';

import 'helpers.dart';

/// E3 (c) and (e), docs/GATE2-CALLS-PLAN.md: call setup a dishonest server
/// swaps, or an outsider sends, must never reach the call code. Call setup
/// travels as an encrypted `call` message (RFC 9420 PrivateMessage); the
/// phone hands on only what decrypts in a conversation it is in, so every
/// swap here must be reported as undecryptable and nothing delivered.
///
/// The server is the real fhirant; the dishonesty is played at Bob's end of
/// the wire, by a mailbox that changes what Bob collects (a server can hand
/// a phone any bytes it likes, so this is what one could do).
void main() {
  late TestServer server;
  late Client alice;
  late Client bob;
  late Client carol;
  late SwappingMailbox bobsWire;
  late List<Map<String, Object?>> bobLog;
  late List<Incoming> bobGot;

  setUp(() async {
    server = await TestServer.start();
    bobLog = [];
    bobGot = [];
    alice = await phone('alice-phone', server.base);
    bobsWire = SwappingMailbox(base: server.base);
    bob = await phone('bob-phone', server.base, log: bobLog, mailbox: bobsWire);
    carol = await phone('carol-phone', server.base);
    bob.incoming.listen(bobGot.add);
  });

  tearDown(() async {
    await alice.close();
    await bob.close();
    await carol.close();
    await server.stop();
  });

  /// Alice and Bob's conversation, Bob joined, nothing else waiting.
  Future<Conversation> talking() async {
    final c = await alice.open('bob-phone');
    await alice.send(c, 'hello');
    await bob.collect();
    expect(bobGot.map((m) => m.text), ['hello']);
    bobGot.clear();
    return c;
  }

  /// Bob collects with [swap] applied to the next call message; checks
  /// that nothing reached the call code and the blob was reported.
  Future<void> refused(Envelope Function(Envelope) swap) async {
    bobsWire.swapNextCall = swap;
    await bob.collect();
    expect(bobsWire.swapNextCall, isNull, reason: 'the swap happened');
    expect(
      bobGot.where((m) => m.label == Label.call),
      isEmpty,
      reason: 'swapped call setup must not reach the call code',
    );
    expect(
      bobLog.where(
        (e) => e['event'] == 'undecryptable' && e['label'] == Label.call.code,
      ),
      hasLength(1),
    );
    // ignore: avoid_print, the reason each swap was refused goes in the log
    print('refused: ${bobLog.last['error']}');
  }

  // An offer as the call code writes one (tremulator_calls `Signal`).
  const offer = r'{"type":"offer","call":"forged","sdp":"v=0\r\n","n":0}';

  group('E3 (c): a server that swaps the call setup', () {
    test('for its own offer in plain text', () async {
      final c = await talking();
      await alice.sendCall(c, offer);
      await refused(
        (e) => e.copyWith(bytes: Uint8List.fromList(utf8.encode(offer))),
      );
    });

    test('for one Bob already had (a replay)', () async {
      final c = await talking();
      await alice.sendCall(c, offer);
      await bob.collect();
      final first = bobGot.single;
      expect(first.label, Label.call);
      bobGot.clear();
      final replay = bobsWire.lastCall!.bytes;
      await alice.sendCall(c, offer);
      await refused((e) => e.copyWith(bytes: replay));
    });

    test('for one from a conversation Bob is not in', () async {
      final c = await talking();
      final other = await alice.open('carol-phone');
      final foreign = await other.encrypt(
        Uint8List.fromList(utf8.encode(offer)),
      );
      await alice.sendCall(c, offer);
      await refused((e) => e.copyWith(bytes: foreign));
    });

    test('for the same message with one byte changed', () async {
      final c = await talking();
      await alice.sendCall(c, offer);
      await refused((e) {
        final b = Uint8List.fromList(e.bytes);
        b[b.length - 1] ^= 1;
        return e.copyWith(bytes: b);
      });
    });
  });

  group('E3 (e): a phone not in the conversation calls', () {
    test('from its own conversation', () async {
      final c = await talking();
      final own = await carol.open('alice-phone');
      final blob = await own.encrypt(Uint8List.fromList(utf8.encode(offer)));
      await alice.sendCall(c, offer);
      await refused((e) => e.copyWith(bytes: blob, from: carol.mailbox.device));
    });

    test("with Alice and Bob's conversation written in the header", () async {
      final c = await talking();
      final own = await carol.open('alice-phone');
      final blob = await own.encrypt(Uint8List.fromList(utf8.encode(offer)));
      final forged = withGroupId(blob, c.id);
      expect(peekConversationId(forged), c.id);
      await alice.sendCall(c, offer);
      await refused(
        (e) => e.copyWith(bytes: forged, from: carol.mailbox.device),
      );
    });
  });
}

/// A mailbox that hands back what the server holds, except that the next
/// `call` envelope collected goes through [swapNextCall] first (once).
class SwappingMailbox extends Mailbox {
  /// One on [base].
  SwappingMailbox({required super.base});

  /// Applied to the next call envelope, then cleared.
  Envelope Function(Envelope)? swapNextCall;

  /// The last call envelope the server held, before any swap.
  Envelope? lastCall;

  @override
  Future<List<Envelope>> collect({int count = 100}) async => [
    for (final e in await super.collect(count: count))
      if (e.label != Label.call) e else _call(e),
  ];

  Envelope _call(Envelope e) {
    lastCall = e;
    final swap = swapNextCall;
    if (swap == null) return e;
    swapNextCall = null;
    return swap(e);
  }
}

/// [blob] (an MLSMessage holding a PrivateMessage) with its group_id
/// replaced by [id] of the same length: RFC 9420 section 6, MLSMessage
/// version (2 bytes), wire_format (2), then PrivateMessage.group_id (a vector).
Uint8List withGroupId(Uint8List blob, Uint8List id) {
  expect(blob.sublist(2, 4), [0, 2], reason: 'a PrivateMessage');
  final prefix = blob[4];
  expect(prefix >> 6, 0, reason: 'a one-byte length (under 64)');
  expect(prefix, id.length, reason: 'group ids of the same length');
  return Uint8List.fromList(blob)..setRange(5, 5 + id.length, id);
}

extension on Envelope {
  Envelope copyWith({Uint8List? bytes, String? from}) => Envelope(
    id: id,
    label: label,
    bytes: bytes ?? this.bytes,
    from: from ?? this.from,
    extra: extra,
    sent: sent,
  );
}
