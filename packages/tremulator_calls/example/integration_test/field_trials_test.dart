import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tremulator_calls/tremulator_calls.dart';
import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_keys/tremulator_keys.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';
import 'package:tremulator_test_server/tremulator_test_server.dart';

// libwebrtc field trials passed through WebRTC.initialize's `fieldTrials`
// option. Field trials are process global and read once, when the peer
// connection factory is made, so this file runs on its own
// (CALL_TEST=integration_test/field_trials_test.dart lab/tool/call_tests.sh).
//
// The trial used to prove the pass-through is one whose effect shows in the
// statistics: `WebRTC-PcFactoryDefaultBitrates` sets the call's lowest,
// starting and highest total rate (pc/peer_connection_factory.cc,
// libwebrtc branch-heads/7871, the m150 the plugin's prebuilt is built
// from; defaults 30, 300 and 2,000 kbit/s). With the lowest at 4,000 kbit/s,
// the sender's bandwidth estimate (availableOutgoingBitrate) never falls
// below it. Without the trial it does: over loopback with video, the stock
// plugin's estimates were 1.2-3.0 Mbit/s
// (lab/tool/results/field_trials_without.log). A cap on the highest is no
// test: the stock run's 3.0 Mbit/s was already above the default 2,000.
const _minBps = 4000000;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a field trial given to initialize reaches libwebrtc: the lowest total '
    'rate it sets floors the bandwidth estimate',
    (_) async {
      await WebRTC.initialize(
        options: {
          'fieldTrials': [
            'WebRTC-PcFactoryDefaultBitrates/min:4000kbps,start:4000kbps,max:8000kbps/',
          ],
        },
      );
      final server = await TestServer.start();
      final alice = await _phone('alice-phone', server.base);
      final bob = await _phone('bob-phone', server.base);
      final conversation = await alice.open('bob-phone');
      await bob.collect();
      await alice.listen();
      await bob.listen();

      final aliceCalls = Calls(alice, videoGuard: null);
      final bobCalls = Calls(bob, videoGuard: null);
      final screen = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'deviceId': {'exact': '0'},
          'mandatory': {'frameRate': 30.0},
        },
        'audio': false,
      });
      final bobsCall = Completer<Call>();
      bobCalls.ringing.listen((c) async {
        await c.answer();
        bobsCall.complete(c);
      });
      final call = await aliceCalls.start(conversation, media: screen);
      await call.connected.timeout(const Duration(seconds: 30));
      await (await bobsCall.future).connected.timeout(
        const Duration(seconds: 30),
      );

      // Ten seconds of estimates, every half second.
      final estimates = <int>[];
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        for (final r in await call.stats()) {
          final v = r.values;
          if (r.type == 'candidate-pair' &&
              v['nominated'] == true &&
              v['availableOutgoingBitrate'] != null) {
            estimates.add((v['availableOutgoingBitrate'] as num).toInt());
          }
        }
      }
      expect(estimates, isNotEmpty, reason: 'the sender reports an estimate');
      expect(
        estimates,
        everyElement(greaterThanOrEqualTo(_minBps)),
        reason: 'estimates seen: $estimates',
      );

      await call.hangUp();
      await aliceCalls.close();
      await bobCalls.close();
      await alice.close();
      await bob.close();
      await server.stop();
    },
  );
}

Future<Client> _phone(String name, Uri base) async {
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
  );
}
