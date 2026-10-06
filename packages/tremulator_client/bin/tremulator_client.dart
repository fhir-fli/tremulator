import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_keys/tremulator_keys.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

/// A phone with no screen, for the lab.
///
/// Every event is one JSON line appended to --out and flushed as it happens.
/// Message plaintexts carry the sender's clock, so the receiver's line has
/// the one-way time when both run on the same clock (the Docker lab does).
Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('server', mandatory: true, help: 'http://host:port')
    ..addOption('name', mandatory: true, help: "this device's name")
    ..addOption('state', mandatory: true, help: 'directory for keys and db')
    ..addOption('out', mandatory: true, help: 'JSON lines log, appended')
    ..addOption('token', help: 'bearer token, if the server needs one')
    ..addOption('peer', help: 'open a conversation with this device name')
    ..addOption('send', defaultsTo: '0', help: 'messages to send to --peer')
    ..addOption('interval-ms', defaultsTo: '1000', help: 'between sends')
    ..addOption('listen-s', defaultsTo: '0', help: 'stay and collect for N s')
    ..addFlag('poll', help: 'collect every second instead of on wake-up');
  final args = parser.parse(argv);

  final out = File(args['out'] as String).openWrite(mode: FileMode.append);
  void log(Map<String, Object?> e) {
    out.writeln(
      jsonEncode({'t': DateTime.now().toUtc().toIso8601String(), ...e}),
    );
    // One line per event, flushed, so a killed run still has everything.
    unawaited(out.flush());
  }

  final state = Directory(args['state'] as String)..createSync(recursive: true);
  final keys = await _openKeys(state, args['name'] as String);
  final client = await Client.start(
    keys: keys,
    mailbox: Mailbox(
      base: Uri.parse(args['server'] as String),
      token: args['token'] as String?,
    ),
    report: log,
  );
  client.incoming.listen((m) {
    final now = DateTime.now().toUtc();
    Map<String, Object?> body;
    try {
      body = jsonDecode(m.text) as Map<String, Object?>;
    } catch (_) {
      body = {'text': m.text};
    }
    final sentAt = body['sent'] as String?;
    log({
      'event': 'received',
      'from': m.from,
      'seq': body['seq'],
      'sent': sentAt,
      'one-way-ms': sentAt == null
          ? null
          : now.difference(DateTime.parse(sentAt)).inMilliseconds,
    });
  });

  if (args['poll'] as bool) {
    Timer.periodic(const Duration(seconds: 1), (_) => client.collect());
  } else {
    await client.listen();
  }

  final peer = args['peer'] as String?;
  final count = int.parse(args['send'] as String);
  if (peer != null && count > 0) {
    final c = await client.open(peer);
    final gap = Duration(
      milliseconds: int.parse(args['interval-ms'] as String),
    );
    for (var i = 0; i < count; i++) {
      final sentAt = DateTime.now().toUtc().toIso8601String();
      await client.send(c, jsonEncode({'seq': i, 'sent': sentAt}));
      log({'event': 'sent', 'seq': i, 'sent': sentAt});
      await Future<void>.delayed(gap);
    }
  }

  final listen = int.parse(args['listen-s'] as String);
  if (listen > 0) {
    await Future<void>.delayed(Duration(seconds: listen));
  }
  await client.collect();
  log({'event': 'done'});
  await client.close();
  await out.close();
}

/// Keys live in --state: a 32-byte storage key and the identity, written on
/// first run. In the app these go in secure storage; the lab has none.
Future<KeyStore> _openKeys(Directory state, String name) async {
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
    storageKey = Uint8List.fromList(
      List.generate(32, (_) => DateTime.now().microsecond % 256),
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
