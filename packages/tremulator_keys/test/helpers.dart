import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:tremulator_keys/tremulator_keys.dart';

/// A random 32-byte storage key, as the app would draw from secure storage.
Uint8List randomKey() {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
}

/// A phone with an in-memory key store.
Future<KeyStore> phone(String name) async => KeyStore.open(
  dbPath: ':memory:',
  storageKey: randomKey(),
  identity: await Identity.create(name),
);

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

String text(Received r) =>
    r is ReceivedMessage ? utf8.decode(r.bytes) : 'not a message: $r';

/// Alice starts a conversation and adds Bob; returns both handles.
Future<(Conversation, Conversation)> pair(KeyStore alice, KeyStore bob) async {
  final a = await alice.start();
  final change = await a.add([await bob.makeKeyPackage()]);
  final b = await bob.join(change.welcome!);
  return (a, b);
}
