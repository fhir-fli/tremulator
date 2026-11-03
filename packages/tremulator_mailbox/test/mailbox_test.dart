import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:test/test.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

import 'package:tremulator_test_server/tremulator_test_server.dart';

Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

/// [s] behind an MLSMessage header (RFC 9420 section 6: mls10, then the
/// wire format: 2 private message, 3 welcome, 4 group info, 5 key
/// package), the first bytes the server checks a `message/mls` file by.
/// The mailbox never reads past them.
Uint8List mls(int kind, String s) =>
    Uint8List.fromList([0, 1, 0, kind, ...s.codeUnits]);

/// What [mls] wrapped.
String body(Uint8List b) => String.fromCharCodes(b.sublist(4));

void main() {
  late TestServer server;
  late Mailbox alice;
  late Mailbox bob;

  setUp(() async {
    server = await TestServer.start();
    alice = Mailbox(base: server.base);
    bob = Mailbox(base: server.base);
    await alice.register(
      deviceName: 'alice-phone',
      publicKey: bytes('alice-key'),
    );
    await bob.register(deviceName: 'bob-phone', publicKey: bytes('bob-key'));
  });

  tearDown(() async {
    alice.close();
    bob.close();
    await server.stop();
  });

  test('a phone registers once and is found by name with its key', () async {
    final again = Mailbox(base: server.base);
    final id = await again.register(
      deviceName: 'alice-phone',
      publicKey: bytes('alice-key'),
    );
    expect(
      id,
      alice.device,
      reason: 'conditional create found the existing Device',
    );
    expect(await bob.findDevice('alice-phone'), alice.device);
    expect(await bob.findDevice('nobody'), isNull);
    expect(await bob.signingKeyOf(alice.device), bytes('alice-key'));
    again.close();
  });

  test(
    'key packages are taken one at a time until the stock is empty',
    () async {
      await bob.publishKeyPackages([
        mls(5, 'kp1'),
        mls(5, 'kp2'),
        mls(5, 'kp3'),
      ]);
      final taken = <String>{};
      for (var i = 0; i < 3; i++) {
        final kp = await alice.takeKeyPackage(bob.device);
        expect(kp, isNotNull);
        taken.add(body(kp!));
      }
      expect(taken, {'kp1', 'kp2', 'kp3'});
      expect(await alice.takeKeyPackage(bob.device), isNull);
    },
  );

  test(
    'a message is collected once and the server then holds nothing',
    () async {
      await alice.send(
        to: bob.device,
        label: Label.message,
        bytes: mls(2, 'hello bob'),
      );
      await alice.send(
        to: bob.device,
        label: Label.welcome,
        bytes: mls(3, 'welcome'),
      );
      final got = await bob.collect();
      expect(got.map((e) => e.label), [Label.message, Label.welcome]);
      expect(body(got.first.bytes), 'hello bob');
      expect(got.first.from, alice.device);
      expect(await alice.collect(), isEmpty, reason: 'addressed to bob only');
      for (final e in got) {
        await bob.acknowledge(e.id);
      }
      expect(await bob.collect(), isEmpty);
      expect(await bob.pending(), 0);
    },
  );

  test(
    'the server keeps the first commit for an epoch and refuses the second',
    () async {
      final conversation = Uint8List.fromList([1, 2, 3, 4]);
      final accepted = await alice.sendCommit(
        to: [bob.device],
        conversation: conversation,
        epoch: BigInt.two,
        commit: mls(2, 'alice commit'),
        groupInfo: mls(4, 'alice info'),
      );
      expect(accepted, isTrue);
      final rejected = await bob.sendCommit(
        to: [alice.device],
        conversation: conversation,
        epoch: BigInt.two,
        commit: mls(2, 'bob commit'),
        groupInfo: mls(4, 'bob info'),
      );
      expect(rejected, isFalse);

      final next = await bob.commitAfter(conversation, BigInt.one);
      expect(next, isNotNull);
      expect(body(next!.bytes), 'alice commit');
      expect(next.extra.map(body), ['alice info']);
      expect(next.from, alice.device);
      expect(await bob.commitAfter(conversation, BigInt.two), isNull);
      expect(await bob.collect(), isEmpty, reason: 'commits are not collected');

      // The instrument check: without the If-None-Exist header the server
      // takes a duplicate, so the header is what refused Bob's commit.
      final plain = await http.post(
        server.base.replace(
          path: '${server.base.path}/Communication',
          queryParameters: {'_format': 'json'},
        ),
        headers: {'Content-Type': 'application/fhir+json'},
        body: jsonEncode({
          'resourceType': 'Communication',
          'status': 'in-progress',
          'identifier': [
            {
              'system': commitSystem,
              'value': '${conversationKey(conversation)}:2',
            },
          ],
        }),
      );
      expect(plain.statusCode, 201);
    },
  );

  test('the wake-up pings when something is addressed to the phone', () async {
    final wakeup = await bob.wakeups();
    final ping = wakeup.pings.first.timeout(const Duration(seconds: 10));
    await alice.send(
      to: bob.device,
      label: Label.message,
      bytes: mls(2, 'ring'),
    );
    await ping;
    expect((await bob.collect()).length, 1);
    await wakeup.close();
  });
}
