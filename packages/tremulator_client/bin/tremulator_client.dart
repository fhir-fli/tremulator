import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

/// A phone with no screen, for the lab.
///
/// Every event is one JSON line appended to --out and flushed as it happens.
/// Message plaintexts carry the sender's clock, so the receiver's line has
/// the one-way time when both run on the same clock (the Docker lab does).
/// With --canary, every message also carries a secret word the lab then
/// hunts for in the server's store and the packet capture.
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
    ..addOption(
      'until-file',
      help: "stay and collect until this file exists (the lab's stop sign)",
    )
    ..addOption('canary', help: 'secret word put in every message')
    ..addOption('timeout-s', defaultsTo: '30', help: 'per request')
    ..addFlag('poll', help: 'collect every second instead of on wake-up');
  final args = parser.parse(argv);

  final log = LabLog(args['out'] as String);

  final state = Directory(args['state'] as String)..createSync(recursive: true);
  final keys = await openLabKeys(state, args['name'] as String);
  final Client client;
  try {
    client = await Client.start(
      keys: keys,
      mailbox: Mailbox(
        base: Uri.parse(args['server'] as String),
        token: args['token'] as String?,
        requestTimeout: Duration(
          seconds: int.parse(args['timeout-s'] as String),
        ),
      ),
      report: log.call,
    );
  } catch (e) {
    // A dead link ends here: the record says so instead of a crash.
    log({'event': 'start-failed', 'error': '$e'});
    log.close();
    exit(2);
  }
  client.incoming.where((m) => m.label == Label.message).listen((m) {
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

  await keepCollecting(client, poll: args['poll'] as bool);

  final peer = args['peer'] as String?;
  final count = int.parse(args['send'] as String);
  final canary = args['canary'] as String?;
  if (peer != null && count > 0) {
    final gap = Duration(
      milliseconds: int.parse(args['interval-ms'] as String),
    );
    final c = await openWithRetry(client, peer, gap: gap);
    for (var i = 0; c != null && i < count; i++) {
      final sentAt = DateTime.now().toUtc().toIso8601String();
      final body = {
        'seq': i,
        'sent': sentAt,
        if (canary != null) 'canary': '$canary-$i',
      };
      var delivered = false;
      for (var attempt = 1; !delivered && attempt <= 3; attempt++) {
        try {
          await client.send(c, jsonEncode(body));
          delivered = true;
          log({'event': 'sent', 'seq': i, 'sent': sentAt, 'attempt': attempt});
        } catch (e) {
          log({
            'event': 'send-failed',
            'seq': i,
            'attempt': attempt,
            'error': '$e',
          });
        }
      }
      await Future<void>.delayed(gap);
    }
  }

  final listen = int.parse(args['listen-s'] as String);
  if (listen > 0) {
    await Future<void>.delayed(Duration(seconds: listen));
  }
  final untilFile = args['until-file'] as String?;
  if (untilFile != null) {
    // run6 P4: Bob's fixed window ended before Alice's slowed run did, and
    // four messages sat on the server uncollected.
    await waitForFile(untilFile, log.call);
  }
  await guardedCollect(client);
  log({'event': 'done'});
  try {
    await client.close();
  } catch (e) {
    log({'event': 'close-failed', 'error': '$e'});
  }
  log.close();
  exit(0);
}
