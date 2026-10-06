import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tremulator_keys/tremulator_keys.dart';

import 'helpers.dart';

void main() {
  test('the storage key must be 32 bytes', () async {
    final id = await Identity.create('x');
    expect(
      () => KeyStore.open(
        dbPath: ':memory:',
        storageKey: Uint8List(16),
        identity: id,
      ),
      throwsA(isA<KeysError>()),
    );
  });

  test(
    'state survives close and reopen with the same key and identity',
    () async {
      final dir = Directory('${Directory.current.path}/build/keys_test')
        ..createSync(recursive: true);
      final path = '${dir.path}/alice.db';
      if (File(path).existsSync()) {
        File(path).deleteSync();
      }
      final key = randomKey();
      final id = await Identity.create('alice-phone');
      var alice = KeyStore.open(dbPath: path, storageKey: key, identity: id);
      final bob = await phone('bob-phone');

      var store = await alice;
      final (a, b) = await pair(store, bob);
      final conversationId = a.id;
      expect(text(await b.receive(await a.encrypt(bytes('one')))), 'one');
      await store.close();
      expect(store.isClosed, isTrue);
      expect(a.epoch, throwsA(isA<KeysError>()));

      alice = KeyStore.open(
        dbPath: path,
        storageKey: key,
        identity: Identity.restore(
          name: id.name,
          publicKey: id.publicKey,
          secret: id.secret,
        ),
      );
      store = await alice;
      final a2 = store.conversation(conversationId);
      expect(await a2.epoch(), await b.epoch());
      expect(text(await b.receive(await a2.encrypt(bytes('two')))), 'two');
      expect(text(await a2.receive(await b.encrypt(bytes('three')))), 'three');
      await store.close();
      await bob.close();

      // The wrong key opens nothing.
      expect(
        () =>
            KeyStore.open(dbPath: path, storageKey: randomKey(), identity: id),
        throwsA(isA<KeysError>()),
      );
    },
  );
}
