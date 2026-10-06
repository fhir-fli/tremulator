import 'dart:math';
import 'dart:typed_data';

import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_keys/tremulator_keys.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

Uint8List randomKey() {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
}

/// A client named [name] on [base], keys in memory, events into [log].
Future<Client> phone(
  String name,
  Uri base, {
  List<Map<String, Object?>>? log,
}) async => Client.start(
  keys: await KeyStore.open(
    dbPath: ':memory:',
    storageKey: randomKey(),
    identity: await Identity.create(name),
  ),
  mailbox: Mailbox(base: base),
  report: log?.add,
);
