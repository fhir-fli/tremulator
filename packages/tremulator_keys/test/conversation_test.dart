import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tremulator_keys/tremulator_keys.dart';

import 'helpers.dart';

void main() {
  late KeyStore alice;
  late KeyStore bob;
  late KeyStore carol;

  setUp(() async {
    alice = await phone('alice-phone');
    bob = await phone('bob-phone');
    carol = await phone('carol-phone');
  });

  tearDown(() async {
    await alice.close();
    await bob.close();
    await carol.close();
  });

  test('two phones exchange ten messages each way', () async {
    final (a, b) = await pair(alice, bob);
    expect((await a.members()).map((m) => m.name), [
      'alice-phone',
      'bob-phone',
    ]);
    expect((await b.members()).length, 2);
    expect(await a.epoch(), await b.epoch());

    for (var i = 0; i < 10; i++) {
      final toBob = await b.receive(await a.encrypt(bytes('a→b $i')));
      expect(text(toBob), 'a→b $i');
      final toAlice = await a.receive(await b.encrypt(bytes('b→a $i')));
      expect(text(toAlice), 'b→a $i');
      expect((toBob as ReceivedMessage).senderIndex, await a.ownIndex());
    }
  });

  test(
    'a third phone added mid-conversation reads only what follows',
    () async {
      final (a, b) = await pair(alice, bob);
      final before = await a.encrypt(bytes('before carol'));
      expect(text(await b.receive(before)), 'before carol');

      final change = await a.add([await carol.makeKeyPackage()]);
      final applied = await b.receive(change.commit);
      expect(applied, isA<ReceivedChange>());
      expect((applied as ReceivedChange).stillMember, isTrue);
      final c = await carol.join(change.welcome!);
      expect((await c.members()).length, 3);
      expect(await c.epoch(), await a.epoch());

      // Carol was not there for the earlier message and cannot read it.
      expect(() => c.receive(before), throwsA(isA<KeysError>()));

      final after = await a.encrypt(bytes('after carol'));
      expect(text(await b.receive(after)), 'after carol');
      expect(text(await c.receive(after)), 'after carol');
    },
  );

  test('a removed phone reads nothing sent after its removal', () async {
    final (a, b) = await pair(alice, bob);
    final add = await a.add([await carol.makeKeyPackage()]);
    await b.receive(add.commit);
    final c = await carol.join(add.welcome!);

    final bobIndex = (await a.members())
        .firstWhere((m) => m.name == 'bob-phone')
        .index;
    final removal = await a.remove([bobIndex]);
    final seenByBob = await b.receive(removal.commit);
    expect((seenByBob as ReceivedChange).stillMember, isFalse);
    expect(await b.isMember(), isFalse);
    final seenByCarol = await c.receive(removal.commit);
    expect((seenByCarol as ReceivedChange).stillMember, isTrue);
    expect((await a.members()).map((m) => m.name), [
      'alice-phone',
      'carol-phone',
    ]);

    final secret = await a.encrypt(bytes('without bob'));
    expect(text(await c.receive(secret)), 'without bob');
    expect(() => b.receive(secret), throwsA(isA<KeysError>()));
    expect(() => b.encrypt(bytes('still here?')), throwsA(isA<KeysError>()));
  });

  test(
    'two phones change the same epoch; the loser rejoins and recovers',
    () async {
      final (a, b) = await pair(alice, bob);
      final epochBefore = await a.epoch();

      // Both rotate keys at once. The library has already applied each one
      // locally, so both phones now claim the next epoch with different keys.
      final aliceChange = await a.refreshKeys();
      final bobChange = await b.refreshKeys();
      expect(await a.epoch(), epochBefore + BigInt.one);
      expect(await b.epoch(), epochBefore + BigInt.one);

      // The server took Alice's first. Bob's commit is for an epoch Alice has
      // already closed, and she refuses it.
      expect(() => a.receive(bobChange.commit), throwsA(isA<KeysError>()));

      // Bob learns his commit was rejected, discards his stale state and
      // rejoins from the snapshot Alice published beside her commit.
      await b.destroy();
      expect(b.epoch, throwsA(isA<KeysError>()));
      final rejoined = await bob.rejoin(aliceChange.snapshot);
      final b2 = rejoined.conversation;
      expect(b2.id, a.id);

      // Alice applies Bob's rejoin like any other change.
      final seen = await a.receive(rejoined.commit);
      expect(seen, isA<ReceivedChange>());
      expect(await a.epoch(), await b2.epoch());
      expect(await a.epoch(), epochBefore + BigInt.two);
      expect(
        (await a.members()).map((m) => m.name),
        unorderedEquals(['alice-phone', 'bob-phone']),
      );
      expect((await a.members()).length, 2, reason: 'the old leaf is gone');

      expect(
        text(await b2.receive(await a.encrypt(bytes('back in step')))),
        'back in step',
      );
      expect(
        text(await a.receive(await b2.encrypt(bytes('thanks')))),
        'thanks',
      );
    },
  );

  test('a phone that is not a member cannot read anything', () async {
    final (a, b) = await pair(alice, bob);
    final blob = await a.encrypt(bytes('private'));
    final stranger = carol.conversation(a.id);
    expect(() => stranger.receive(blob), throwsA(isA<KeysError>()));
    expect(text(await b.receive(blob)), 'private');
  });

  test('blobs can be routed without being decrypted', () async {
    final (a, b) = await pair(alice, bob);
    final message = await a.encrypt(bytes('route me'));
    expect(peekConversationId(message), a.id);
    expect(peekKind(message), BlobKind.message);
    expect(peekEpoch(message), await a.epoch());

    final change = await a.add([await carol.makeKeyPackage()]);
    expect(peekKind(change.commit), BlobKind.commit);
    expect(peekConversationId(change.commit), a.id);
    expect(
      peekKind(change.welcome!),
      BlobKind.other,
      reason: 'a welcome is not a protocol message; the mailbox labels it',
    );
    expect(
      () => peekConversationId(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<KeysError>()),
    );
    expect(peekKind(Uint8List.fromList([1, 2, 3])), BlobKind.other);
    await b.receive(change.commit);
  });

  test('a key package is single use', () async {
    final a = await alice.start();
    final kp = await bob.makeKeyPackage();
    final first = await a.add([kp]);
    await bob.join(first.welcome!);
    final other = await carol.start();
    final second = await other.add([kp]);
    // The private half was consumed by the first join.
    expect(() => bob.join(second.welcome!), throwsA(isA<KeysError>()));
  });
}
