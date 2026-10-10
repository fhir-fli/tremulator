import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

import 'package:tremulator_test_server/tremulator_test_server.dart';

void main() {
  test(
    'with authentication on, a signed-in phone works and a stranger is refused',
    () async {
      final server = await TestServer.start(devMode: false);
      addTearDown(server.stop);
      await register(
        base: server.base,
        username: 'alice',
        password: 'a-long-enough-password-123',
      );
      final token = await login(
        base: server.base,
        username: 'alice',
        password: 'a-long-enough-password-123',
      );

      final stranger = Mailbox(base: server.base);
      expect(
        () => stranger.register(deviceName: 'x', publicKey: Uint8List(1)),
        throwsA(isA<MailboxError>()),
      );

      final alice = Mailbox(base: server.base, token: token);
      final id = await alice.register(
        deviceName: 'alice-phone',
        publicKey: Uint8List(32),
      );
      expect(id, isNotEmpty);
      expect(await alice.pending(), 0);
      alice.close();
      stranger.close();
    },
  );
}
