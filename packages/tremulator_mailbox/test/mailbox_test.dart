import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:test/test.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

import 'server.dart';

Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

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
      await bob.publishKeyPackages([bytes('kp1'), bytes('kp2'), bytes('kp3')]);
      final taken = <String>{};
      for (var i = 0; i < 3; i++) {
        final kp = await alice.takeKeyPackage(bob.device);
        expect(kp, isNotNull);
        taken.add(String.fromCharCodes(kp!));
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
        bytes: bytes('hello bob'),
      );
      await alice.send(
        to: bob.device,
        label: Label.welcome,
        bytes: bytes('welcome'),
      );
      final got = await bob.collect();
      expect(got.map((e) => e.label), [Label.message, Label.welcome]);
      expect(String.fromCharCodes(got.first.bytes), 'hello bob');
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
        commit: bytes('alice commit'),
        groupInfo: bytes('alice info'),
        ratchetTree: bytes('alice tree'),
      );
      expect(accepted, isTrue);
      final rejected = await bob.sendCommit(
        to: [alice.device],
        conversation: conversation,
        epoch: BigInt.two,
        commit: bytes('bob commit'),
        groupInfo: bytes('bob info'),
        ratchetTree: bytes('bob tree'),
      );
      expect(rejected, isFalse);

      final next = await bob.commitAfter(conversation, BigInt.one);
      expect(next, isNotNull);
      expect(String.fromCharCodes(next!.bytes), 'alice commit');
      expect(next.extra.map(String.fromCharCodes), [
        'alice info',
        'alice tree',
      ]);
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
      bytes: bytes('ring'),
    );
    await ping;
    expect((await bob.collect()).length, 1);
    await wakeup.close();
  });
}
