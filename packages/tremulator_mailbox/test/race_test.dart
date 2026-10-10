import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

import 'package:tremulator_test_server/tremulator_test_server.dart';

Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  test('twenty phones offer a commit for the same epoch at once; '
      'the server accepts exactly one', () async {
    final server = await TestServer.start();
    addTearDown(server.stop);
    final phones = <Mailbox>[];
    for (var i = 0; i < 20; i++) {
      final m = Mailbox(base: server.base);
      await m.register(deviceName: 'phone-$i', publicKey: bytes('k$i'));
      phones.add(m);
    }
    addTearDown(() {
      for (final m in phones) {
        m.close();
      }
    });
    final conversation = Uint8List.fromList([9, 9, 9, 9]);
    // All twenty requests are in flight together.
    final results = await Future.wait([
      for (var i = 0; i < 20; i++)
        phones[i].sendCommit(
          to: [phones[(i + 1) % 20].device],
          conversation: conversation,
          epoch: BigInt.from(7),
          commit: bytes('commit $i'),
          groupInfo: bytes('info $i'),
          ratchetTree: bytes('tree $i'),
          confirmationTag: bytes('tag $i'),
        ),
    ]);
    final accepted = results.where((r) => r).length;
    final stored = await phones.first.commitAfter(conversation, BigInt.from(6));
    expect(stored, isNotNull);
    expect(
      accepted,
      1,
      reason:
          'the delivery service must keep one commit per epoch '
          '(RFC 9750 section 5.2); $accepted were accepted',
    );
  });
}
