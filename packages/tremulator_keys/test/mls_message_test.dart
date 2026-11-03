import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tremulator_keys/tremulator_keys.dart';

import 'helpers.dart';

/// What leaves this package is an MLSMessage, the form the `message/mls`
/// media type carries (RFC 9420 §17.10 and §6, rfc9420.txt read 2026-11-02),
/// and the snapshot is the signed GroupInfo alone: it holds the key tree
/// (openmls exports it with the ratchet_tree extension, §12.4.3.3) and the
/// epoch's confirmation tag (§12.4.3, GroupInfo.confirmation_tag).
void main() {
  late KeyStore alice;
  late KeyStore bob;

  setUp(() async {
    alice = await phone('alice-phone');
    bob = await phone('bob-phone');
  });

  tearDown(() async {
    await alice.close();
    await bob.close();
  });

  test('a key package goes out as an MLSMessage of kind 5', () async {
    final kp = await bob.makeKeyPackage();
    // ProtocolVersion mls10 (1), WireFormat mls_key_package (5).
    expect(kp.sublist(0, 4), [0x00, 0x01, 0x00, 0x05]);
    final a = await alice.start();
    expect(
      () => a.add([Uint8List.sublistView(kp, 4)]),
      throwsA(isA<KeysError>()),
      reason: 'a bare KeyPackage is not an MLSMessage',
    );
    final change = await a.add([kp]);
    await bob.join(change.welcome!);
  });

  test("the snapshot's tag is the epoch's, read from its GroupInfo", () async {
    final (a, b) = await pair(alice, bob);
    final first = await a.snapshot();
    expect(first.groupInfo.sublist(0, 4), [0x00, 0x01, 0x00, 0x04]);
    expect(first.confirmationTag, await a.confirmationTag());
    expect(first.confirmationTag, await b.confirmationTag());

    final change = await b.refreshKeys();
    expect(change.snapshot.confirmationTag, await b.confirmationTag());
    expect(change.snapshot.confirmationTag, isNot(first.confirmationTag));
    await a.receive(change.commit);
    expect(change.snapshot.confirmationTag, await a.confirmationTag());
  });

  test('a GroupInfo that is not well formed is refused', () async {
    final (a, _) = await pair(alice, bob);
    final good = (await a.snapshot()).groupInfo;
    Uint8List changed(int at, int to) => Uint8List.fromList(good)..[at] = to;
    final bad = <String, Uint8List>{
      'cut short': Uint8List.sublistView(good, 0, good.length - 1),
      'a byte left over': Uint8List.fromList([...good, 0]),
      'not mls10': changed(1, 2),
      'not a GroupInfo (a welcome)': changed(3, 3),
      // The group id's length, first <V> in GroupContext (offset 8): prefix
      // 11 is invalid (§2.1.2), and 01 with a value under 64 is longer than
      // it need be.
      'length prefix 11': changed(8, 0xC0 | good[8]),
      'length not minimal': Uint8List.fromList([
        ...good.sublist(0, 8),
        0x40,
        ...good.sublist(8),
      ]),
    };
    expect(good[8], lessThan(64), reason: 'the group id length fits one byte');
    for (final MapEntry(key: what, value: b) in bad.entries) {
      expect(
        () => Snapshot(groupInfo: b).confirmationTag,
        throwsA(isA<KeysError>()),
        reason: what,
      );
    }
  });
}
