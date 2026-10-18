import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
  late _Link aliceLink;
  late _Link bobLink;

  setUp(() async {
    server = await TestServer.start();
    aliceLog = [];
    bobLog = [];
    aliceLink = _Link();
    bobLink = _Link();
    alice = await _phone('alice-phone', server.base, aliceLog, aliceLink);
    bob = await _phone('bob-phone', server.base, bobLog, bobLink);
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
    "the far phone's connection vanishes: the caller tries to reconnect, "
    'then ends the call as lost',
    (_) async {
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

      // Bob's connection goes with no hang-up, as when his phone dies.
      await answered.connection!.close();

      final why = await call.ended.timeout(const Duration(seconds: 150));
      expect(why, 'lost');
      expect(
        aliceLog.where(
          (e) => e['event'] == 'reconnecting' && e['call'] == call.id,
        ),
        hasLength(1),
      );
      expect(
        aliceLog.where(
          (e) => e['event'] == 'restart-sent' && e['call'] == call.id,
        ),
        isNotEmpty,
      );
      await aliceCalls.close();
      await bobCalls.close();
    },
  );

  testWidgets(
    'a restart on a working call is answered and the call carries on',
    (_) async {
      final aliceCalls = Calls(alice);
      final bobCalls = Calls(bob);
      final (call, answered) = await _connect(
        aliceCalls,
        bobCalls,
        conversation,
      );

      call.debugLinkLost();
      await _until(
        () => aliceLog.any(
          (e) => e['event'] == 'answer-applied' && e['n'] == 1,
        ),
      );
      expect(
        aliceLog.where(
          (e) => e['event'] == 'reconnected' && e['call'] == call.id,
        ),
        hasLength(1),
      );
      // Offer 1 went out and Bob answered offer 1, both through the mailbox.
      expect(
        aliceLog.where(
          (e) => e['event'] == 'offer-sent' && e['n'] == 1,
        ),
        hasLength(1),
      );
      expect(
        bobLog.where(
          (e) => e['event'] == 'answer-sent' && e['n'] == 1,
        ),
        hasLength(1),
      );
      final back = aliceLog.lastWhere((e) => e['event'] == 'reconnected');
      expect(back['control'], 'RTCDataChannelOpen');
      expect((await call.route())?.relayed, isFalse);

      // Still a call: the hang-up reaches Bob.
      await call.hangUp();
      expect(
        await answered.ended.timeout(const Duration(seconds: 30)),
        'remote-hangup',
      );
      await aliceCalls.close();
      await bobCalls.close();
    },
  );

  testWidgets(
    'a restart answer with a different certificate fingerprint ends the call',
    (_) async {
      // Bob's first answer arrives as sent; the answer to the restart has
      // one fingerprint digit changed, as a different phone's would.
      var answers = 0;
      final aliceCalls = Calls(
        alice,
        alterRemoteSdp: (sdp) => ++answers == 1 ? sdp : _changeFingerprint(sdp),
      );
      final bobCalls = Calls(bob);
      final (call, answered) = await _connect(
        aliceCalls,
        bobCalls,
        conversation,
      );

      call.debugLinkLost();
      expect(
        await call.ended.timeout(const Duration(seconds: 30)),
        'fingerprint-changed',
      );
      expect(
        await answered.ended.timeout(const Duration(seconds: 30)),
        'remote-hangup',
      );
      await aliceCalls.close();
      await bobCalls.close();
    },
  );

  testWidgets(
    'a restart offer with a different certificate fingerprint ends the call',
    (_) async {
      var offers = 0;
      final aliceCalls = Calls(alice);
      final bobCalls = Calls(
        bob,
        alterRemoteSdp: (sdp) => ++offers == 1 ? sdp : _changeFingerprint(sdp),
      );
      final (call, answered) = await _connect(
        aliceCalls,
        bobCalls,
        conversation,
      );

      call.debugLinkLost();
      expect(
        await answered.ended.timeout(const Duration(seconds: 30)),
        'fingerprint-changed',
      );
      expect(
        await call.ended.timeout(const Duration(seconds: 30)),
        'remote-hangup',
      );
      // Bob refused the offer, so he never answered it.
      expect(
        bobLog.where((e) => e['event'] == 'answer-sent' && e['n'] == 1),
        isEmpty,
      );
      await aliceCalls.close();
      await bobCalls.close();
    },
  );

  testWidgets(
    'a restart offer for a call this phone does not have does not ring',
    (_) async {
      final bobCalls = Calls(bob);
      final rang = <Call>[];
      bobCalls.ringing.listen(rang.add);

      await alice.sendCall(
        conversation,
        const Signal(
          type: SignalType.offer,
          call: 'no-such-call',
          sdp: 'v=0\r\n',
          number: 1,
        ).encode(),
      );
      await _until(
        () => bobLog.any(
          (e) => e['event'] == 'restart-ignored' && e['call'] == 'no-such-call',
        ),
      );
      expect(rang, isEmpty);
      await bobCalls.close();
    },
  );

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
      // It ends at once as failed: a call that cannot be set up for want
      // of a route keeps trying for Calls.setupDeadline (90 s), one whose
      // other end is the wrong certificate must not.
      expect(await call.ended.timeout(const Duration(seconds: 5)), 'failed');
      expect(
        aliceLog.where((e) => e['event'] == 'reconnecting'),
        isEmpty,
        reason: 'no retry after a refused certificate',
      );
      expect(
        aliceLog.where((e) => e['event'] == 'setup-deadline'),
        isEmpty,
      );
      // The handshake failed, read from the transport's own state (W3C
      // WebRTC 1.0, RTCDtlsTransportState "failed": "failure to validate
      // the remote fingerprint").
      final why = aliceLog.singleWhere((e) => e['event'] == 'setup-failed');
      expect(why['dtls'], contains('failed'));
      expect(why['why'], 'handshake');
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

  testWidgets(
    "an offer sent while the caller's link is down is sent again and the "
    'call connects',
    (_) async {
      final aliceCalls = Calls(
        alice,
        sendRetry: const Duration(milliseconds: 200),
      );
      final bobCalls = Calls(bob);
      final bobsCall = Completer<Call>();
      bobCalls.ringing.listen((c) async {
        await c.answer();
        bobsCall.complete(c);
      });

      aliceLink.down = true;
      final call = await aliceCalls.start(conversation);
      await _until(
        () => aliceLog.any(
          (e) => e['event'] == 'send-failed' && e['type'] == 'offer',
        ),
      );
      aliceLink.down = false;

      await call.connected.timeout(const Duration(seconds: 30));
      await (await bobsCall.future).connected.timeout(
        const Duration(seconds: 30),
      );
      final sent = aliceLog.singleWhere((e) => e['event'] == 'offer-sent');
      expect(sent['attempt'], greaterThan(1));
      expect(sent['n'], 0);
      await aliceCalls.close();
      await bobCalls.close();
    },
  );

  testWidgets(
    "an answer sent while the callee's link is down is sent again and the "
    'call connects',
    (_) async {
      final aliceCalls = Calls(alice);
      final bobCalls = Calls(
        bob,
        sendRetry: const Duration(milliseconds: 200),
      );
      final bobsCall = Completer<Call>();
      bobCalls.ringing.listen((c) async {
        bobLink.down = true;
        await c.answer();
        bobsCall.complete(c);
      });

      final call = await aliceCalls.start(conversation);
      await _until(
        () => bobLog.any(
          (e) => e['event'] == 'send-failed' && e['type'] == 'answer',
        ),
      );
      bobLink.down = false;

      await call.connected.timeout(const Duration(seconds: 30));
      await (await bobsCall.future).connected.timeout(
        const Duration(seconds: 30),
      );
      final sent = bobLog.singleWhere((e) => e['event'] == 'answer-sent');
      expect(sent['attempt'], greaterThan(1));
      expect(sent['n'], 0);
      await aliceCalls.close();
      await bobCalls.close();
    },
  );
}

/// A connection to the server that can be cut: while [down], every request
/// fails as a dead link's would. The wake-up connection is a web socket,
/// outside it, and stays up.
class _Link extends http.BaseClient {
  final http.Client _inner = http.Client();
  bool down = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (down) {
      throw http.ClientException('link down', request.url);
    }
    return _inner.send(request);
  }
}

/// Alice calls Bob and he answers; both are connected.
Future<(Call, Call)> _connect(
  Calls aliceCalls,
  Calls bobCalls,
  Conversation conversation,
) async {
  final bobsCall = Completer<Call>();
  bobCalls.ringing.listen((c) async {
    await c.answer();
    bobsCall.complete(c);
  });
  final call = await aliceCalls.start(conversation);
  await call.connected.timeout(const Duration(seconds: 30));
  final answered = await bobsCall.future;
  await answered.connected.timeout(const Duration(seconds: 30));
  return (call, answered);
}

Future<Client> _phone(
  String name,
  Uri base,
  List<Map<String, Object?>> log,
  http.Client link,
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
    mailbox: Mailbox(base: base, client: link),
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
