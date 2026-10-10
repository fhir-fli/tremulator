import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tremulator_calls/tremulator_calls.dart';
import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_keys/tremulator_keys.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';
import 'package:tremulator_test_server/tremulator_test_server.dart';

// Two phones in one process, a real fhirant in the same process, the real
// WebRTC plugin. The call setup goes through the mailbox encrypted; the
// connection itself is over loopback, no relay.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late TestServer server;
  late Client alice;
  late Client bob;
  late Conversation conversation;
  late List<Map<String, Object?>> aliceLog;
  late List<Map<String, Object?>> bobLog;

  setUp(() async {
    server = await TestServer.start();
    aliceLog = [];
    bobLog = [];
    alice = await _phone('alice-phone', server.base, aliceLog);
    bob = await _phone('bob-phone', server.base, bobLog);
    conversation = await alice.open('bob-phone');
    await bob.collect();
    await alice.listen();
    await bob.listen();
  });

  tearDown(() async {
    await alice.close();
    await bob.close();
    await server.stop();
  });

  testWidgets('a call set up through the mailbox connects, then hangs up', (
    _,
  ) async {
    final aliceCalls = Calls(alice);
    final bobCalls = Calls(bob);
    final bobsCall = Completer<Call>();
    bobCalls.ringing.listen((c) async {
      await c.answer();
      bobsCall.complete(c);
    });

    final call = await aliceCalls.start(conversation);
    await call.connected.timeout(const Duration(seconds: 30));
    final answered = await bobsCall.future;
    await answered.connected.timeout(const Duration(seconds: 30));

    final route = await call.route();
    expect(route, isNotNull);
    expect(route!.relayed, isFalse, reason: 'loopback, no relay configured');

    // The offer and the answer each went through the server as a `call`
    // blob, never as chat.
    expect(
      aliceLog.where((e) => e['event'] == 'offer-sent' && e['call'] == call.id),
      hasLength(1),
    );
    expect(
      bobLog.where((e) => e['event'] == 'answer-sent' && e['call'] == call.id),
      hasLength(1),
    );

    await call.hangUp();
    await _until(
      () => bobLog.any(
        (e) => e['event'] == 'call-ended' && e['why'] == 'remote-hangup',
      ),
    );
    await aliceCalls.close();
    await bobCalls.close();
  });

  testWidgets(
    'a changed certificate fingerprint in the setup is refused',
    (_) async {
      // Alice reads Bob's answer with one hex digit of its fingerprint
      // changed, as a dishonest relay of the setup would deliver it. Bob's
      // real certificate then fails the check (RFC 8122 section 6.2).
      final aliceCalls = Calls(alice, alterRemoteSdp: _changeFingerprint);
      final bobCalls = Calls(bob);
      bobCalls.ringing.listen((c) => c.answer());

      final call = await aliceCalls.start(conversation);
      await expectLater(
        call.connected.timeout(const Duration(seconds: 30)),
        throwsA(isA<StateError>()),
      );
      // The description was accepted and the handshake tried: the failure
      // is the certificate check, not a garbled description.
      final states = [
        for (final e in aliceLog)
          if (e['event'] == 'call-state') e['state'],
      ];
      expect(states, contains('RTCPeerConnectionStateConnecting'));
      expect(states.last, 'RTCPeerConnectionStateFailed');
      expect(states, isNot(contains('RTCPeerConnectionStateConnected')));
      await aliceCalls.close();
      await bobCalls.close();
    },
  );
}

Future<Client> _phone(
  String name,
  Uri base,
  List<Map<String, Object?>> log,
) async {
  final rng = Random.secure();
  return Client.start(
    keys: await KeyStore.open(
      dbPath: ':memory:',
      storageKey: Uint8List.fromList(
        List.generate(32, (_) => rng.nextInt(256)),
      ),
      identity: await Identity.create(name),
    ),
    mailbox: Mailbox(base: base),
    report: log.add,
  );
}

/// Changes the last hex digit of the first fingerprint line's first byte.
String _changeFingerprint(String sdp) {
  final line = RegExp(
    r'^a=fingerprint:(\S+) ([0-9A-F]{2})',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(sdp);
  if (line == null) {
    throw StateError('no fingerprint in the session description');
  }
  final byte = line.group(2)!;
  final changed = byte[0] + (byte[1].toUpperCase() == 'A' ? 'B' : 'A');
  return sdp.replaceRange(line.end - 2, line.end, changed);
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met in 30 s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
