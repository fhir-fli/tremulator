import 'package:test/test.dart';
import 'package:tremulator_client/tremulator_client.dart';

import 'helpers.dart';
import 'server.dart';

void main() {
  late TestServer server;
  late Client alice;
  late Client bob;
  late List<Map<String, Object?>> aliceLog;
  late List<Map<String, Object?>> bobLog;

  setUp(() async {
    server = await TestServer.start();
    aliceLog = [];
    bobLog = [];
    alice = await phone('alice-phone', server.base, log: aliceLog);
    bob = await phone('bob-phone', server.base, log: bobLog);
  });

  tearDown(() async {
    await alice.close();
    await bob.close();
    await server.stop();
  });

  test(
    'two phones talk through the server and it keeps nothing readable',
    () async {
      final c = await alice.open('bob-phone');
      final bobGot = <String>[];
      bob.incoming.listen((m) => bobGot.add(m.text));
      for (var i = 0; i < 10; i++) {
        await alice.send(c, 'a→b $i');
      }
      expect(await bob.collect(), 11, reason: 'the welcome and ten messages');
      expect(bobGot, [for (var i = 0; i < 10; i++) 'a→b $i']);
      expect(bobLog.where((e) => e['event'] == 'joined').length, 1);

      final aliceGot = <String>[];
      alice.incoming.listen((m) => aliceGot.add(m.text));
      final bobsView = bob.keys.conversation(c.id);
      for (var i = 0; i < 10; i++) {
        await bob.send(bobsView, 'b→a $i');
      }
      expect(await alice.collect(), 10);
      expect(aliceGot, [for (var i = 0; i < 10; i++) 'b→a $i']);
      expect(await alice.mailbox.pending(), 0);
      expect(await bob.mailbox.pending(), 0, reason: 'commits not counted');
    },
  );

  test('a wake-up ping makes the listener collect on its own', () async {
    final c = await alice.open('bob-phone');
    await bob.listen();
    final first = bob.incoming.first.timeout(const Duration(seconds: 10));
    await alice.send(c, 'ring ring');
    expect((await first).text, 'ring ring');
  });

  test('a phone whose commit lost the race rejoins and talks again', () async {
    final a = await alice.open('bob-phone');
    await bob.collect();
    final b = bob.keys.conversation(a.id);
    expect(await a.epoch(), await b.epoch());

    // Both rotate keys at once; Alice's commit reaches the server first.
    // Bob's is refused, so inside refreshKeys he rejoins from Alice's
    // snapshot and offers his rejoin commit.
    await alice.refreshKeys(a);
    await bob.refreshKeys(b);
    final offers = bobLog.where((e) => e['event'] == 'refreshed-keys');
    expect(offers.single['commit-accepted'], isFalse);
    expect(bobLog.where((e) => e['event'] == 'out-of-step').length, 1);
    final rejoined = bobLog.where((e) => e['event'] == 'rejoined').single;
    expect(rejoined['commit-accepted'], isTrue);

    // Alice collects Bob's rejoin commit and they are in step again.
    await alice.collect();
    final a2 = alice.keys.conversation(a.id);
    final b2 = bob.keys.conversation(a.id);
    expect(await a2.epoch(), await b2.epoch());
    expect((await a2.members()).length, 2);

    final bobGot = <String>[];
    bob.incoming.listen((m) => bobGot.add(m.text));
    await alice.send(a2, 'still here');
    await bob.collect();
    expect(bobGot, ['still here']);
    final aliceGot = <String>[];
    alice.incoming.listen((m) => aliceGot.add(m.text));
    await bob.send(b2, 'me too');
    await alice.collect();
    expect(aliceGot, ['me too']);
  });
  test('a wake-up during a collect is not lost', () async {
    final c = await alice.open('bob-phone');
    await bob.collect();
    final got = <String>[];
    bob.incoming.listen((m) => got.add(m.text));
    await alice.send(c, 'first');
    // Start a collect, and while it runs a second message arrives with a
    // second wake-up. The second collect call must make the first go round
    // again rather than be dropped.
    final running = bob.collect();
    await alice.send(c, 'second');
    final dropped = await bob.collect();
    expect(dropped, 0, reason: 'the call during a collect returns at once');
    await running;
    expect(got, ['first', 'second']);
  });
}
