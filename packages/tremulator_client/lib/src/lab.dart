import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:tremulator_client/src/client.dart';
import 'package:tremulator_keys/tremulator_keys.dart';

/// The lab's event log: one JSON line per event, written synchronously and
/// flushed, so a killed run still has everything. An async sink threw
/// "StreamSink is bound to a stream" when a line landed during the previous
/// flush (run4 P4).
class LabLog {
  /// Appends to [path].
  LabLog(String path) : _out = File(path).openSync(mode: FileMode.append);

  final RandomAccessFile _out;

  /// Writes [event] with the current UTC time as `t`.
  void call(Map<String, Object?> event) {
    _out
      ..writeStringSync(
        '${jsonEncode({
          't': DateTime.now().toUtc().toIso8601String(),
          ...event,
        })}\n',
      )
      ..flushSync();
  }

  /// Closes the file.
  void close() => _out.closeSync();
}

/// Keys live in [state]: a 32-byte storage key and the identity, written on
/// first run. In the app these go in secure storage; the lab has none.
Future<KeyStore> openLabKeys(Directory state, String name) async {
  final keyFile = File('${state.path}/storage.key');
  final idFile = File('${state.path}/identity.json');
  late Uint8List storageKey;
  late Identity identity;
  if (keyFile.existsSync() && idFile.existsSync()) {
    storageKey = keyFile.readAsBytesSync();
    final j = jsonDecode(idFile.readAsStringSync()) as Map<String, dynamic>;
    identity = Identity.restore(
      name: j['name'] as String,
      publicKey: base64.decode(j['public'] as String),
      secret: base64.decode(j['secret'] as String),
    );
  } else {
    final rng = Random.secure();
    storageKey = Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );
    identity = await Identity.create(name);
    keyFile.writeAsBytesSync(storageKey);
    idFile.writeAsStringSync(
      jsonEncode({
        'name': name,
        'public': base64.encode(identity.publicKey),
        'secret': base64.encode(identity.secret),
      }),
    );
  }
  return KeyStore.open(
    dbPath: '${state.path}/keys.db',
    storageKey: storageKey,
    identity: identity,
  );
}

/// Collects, reporting a failure instead of throwing.
Future<void> guardedCollect(Client client) async {
  try {
    await client.collect();
  } catch (e) {
    client.report({'event': 'collect-failed', 'error': '$e'});
  }
}

/// Collects on every wake-up, or every second when [poll] is true or the
/// wake-up connection cannot be had, so a run still measures what arrives.
Future<void> keepCollecting(Client client, {bool poll = false}) async {
  if (!poll) {
    try {
      await client.listen();
      return;
    } catch (e) {
      client.report({'event': 'listen-failed', 'error': '$e'});
    }
  }
  Timer.periodic(const Duration(seconds: 1), (_) => guardedCollect(client));
}

/// Opens a conversation with [peer], up to [attempts] times [gap] apart.
/// Null if every attempt failed.
Future<Conversation?> openWithRetry(
  Client client,
  String peer, {
  int attempts = 5,
  Duration gap = const Duration(seconds: 1),
}) async {
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await client.open(peer);
    } catch (e) {
      client.report({
        'event': 'open-failed',
        'attempt': attempt,
        'error': '$e',
      });
      await Future<void>.delayed(gap);
    }
  }
  return null;
}

/// Waits until [path] exists: the lab's stop sign.
Future<void> waitForFile(String path, Report report) async {
  while (!File(path).existsSync()) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  report({'event': 'stop-sign', 'file': path});
}
