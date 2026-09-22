/// Mutation test for the adversary harness (docs/GATE1.md), ported from
/// lab/adversary/mutation_test.py.
///
/// Runs the Dart toy once correctly and once per deliberate defect. For each
/// mode the server container captures its own traffic with tcpdump while
/// storing messages in SQLite and logging headers; the client sends
/// canary-bearing messages, fetches them, keeps and purges a local history.
/// Then the canary scanner reads everything an adversary could hold: server
/// DB, server log, packet capture, and the client's purged local DB.
///
/// Pass: the correct run is CLEAN and every defect is CAUGHT where it should
/// appear. One network and one container per role are created once and reused,
/// because per-mode create/remove raised "disconnected" alerts on Grey's
/// laptop. Usage: dart run bin/mutation_test.dart LABEL
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tremulator_lab/canary_scan.dart';

const img = 'tremulator-toy-dart:latest';
const srv = 'tadv-srv';
const cli = 'tadv-cli';
const net = 'tadv-net';
const modes = <String, List<String>>{
  'none': [],
  'plaintext_body': ['traffic.pcap', 'server.db'],
  'plaintext_attachment': ['traffic.pcap', 'server.db'],
  'preview_leak': ['traffic.pcap', 'server.db'],
  'purge_unlink_only': ['client.db'],
  'key_in_header': ['server.log', 'traffic.pcap'],
  'base64_only': ['traffic.pcap', 'server.db'],
  'gzip_only': ['traffic.pcap', 'server.db'],
};

final _rnd = Random.secure();
String _hex(int n) => List.generate(
  n,
  (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

Future<ProcessResult> sh(List<String> c) => Process.run(c.first, c.sublist(1));

Future<void> teardown() async {
  await sh(['docker', 'rm', '-f', srv, cli]);
  await sh(['docker', 'network', 'rm', net]);
}

Future<void> main(List<String> args) async {
  final label = args.first;
  final lab = File(Platform.script.toFilePath()).parent.parent.parent.path;
  final outRoot = Directory('$lab/adversary/out/$label')
    ..createSync(recursive: true);
  final results = File(
    '$lab/adversary/results/$label.jsonl',
  ).openWrite(mode: FileMode.append);
  await teardown();
  await sh(['docker', 'network', 'create', net]);
  for (final c in [srv, cli]) {
    final r = await sh([
      'docker',
      'run',
      '-d',
      '--name',
      c,
      '--network',
      net,
      '-v',
      '${outRoot.path}:/out',
      img,
      'sleep',
      'infinity',
    ]);
    if (r.exitCode != 0) throw StateError('${r.stderr}');
  }
  try {
    for (final e in modes.entries) {
      final mode = e.key;
      final base = Directory('${outRoot.path}/$mode');
      if (base.existsSync()) base.deleteSync(recursive: true);
      for (final d in ['in', 'srv', 'cli']) {
        Directory('${base.path}/$d').createSync(recursive: true);
      }
      final cb = '/out/$mode';
      final key = _hex(32);
      final msgs = [for (var i = 0; i < 5; i++) 'm$i\tCANARY-${_hex(8)}'];
      File(
        '${base.path}/in/msgs.tsv',
      ).writeAsStringSync('${msgs.join('\n')}\n');
      final canaries = '${base.path}/canaries.tsv';
      File(
        canaries,
      ).writeAsStringSync('${[...msgs, 'key\t$key'].join('\n')}\n');
      final serverCmd =
          'tcpdump -i eth0 -U -w $cb/srv/traffic.pcap & sleep 1; '
          'TOY_DB=$cb/srv/server.db TOY_LOG=$cb/srv/server.log '
          'exec /toy/server/bin/toy_server';
      await sh(['docker', 'exec', '-d', srv, 'sh', '-c', serverCmd]);
      await Future<void>.delayed(const Duration(seconds: 3));
      final r = await sh([
        'docker',
        'exec',
        '-e',
        'DEFECT=$mode',
        '-e',
        'TOY_KEY_HEX=$key',
        '-e',
        'TOY_LOCAL_DB=$cb/cli/client.db',
        cli,
        '/toy/client/bin/toy_client',
        srv,
        '$cb/in/msgs.tsv',
      ]);
      final clientOut = '${r.stdout}${r.stderr}'.trim();
      await Future<void>.delayed(const Duration(seconds: 1));
      await sh([
        'docker',
        'exec',
        srv,
        'sh',
        '-c',
        'pkill -INT tcpdump; pkill -f toy_server; sleep 1',
      ]);
      // hand the outputs back to the invoking user before scanning
      await sh([
        'docker',
        'exec',
        srv,
        'chown',
        '-R',
        '${await _id('-u')}:${await _id('-g')}',
        cb,
      ]);
      final hitsSink = File('${base.path}/hits.jsonl').openWrite();
      final hits = await scanPaths(canaries, [
        '${base.path}/srv',
        '${base.path}/cli',
      ], hitsSink);
      await hitsSink.close();
      final where =
          hits
              .map(
                (h) =>
                    h.where.split('#').first.split('|').first.split('/').last,
              )
              .toSet()
              .toList()
            ..sort();
      final artefacts = [
        for (final d in ['srv', 'cli'])
          ...Directory(
            '${base.path}/$d',
          ).listSync().map((f) => f.uri.pathSegments.last),
      ]..sort();
      final ok = mode == 'none' ? hits.isEmpty : e.value.any(where.contains);
      final rec = {
        'run': label,
        'mode': mode,
        'client': clientOut.substring(max(0, clientOut.length - 300)),
        'artefacts': artefacts,
        'hits': hits.length,
        'hit_in': where,
        'expected_in': e.value,
        'verdict': hits.isEmpty ? 'CLEAN' : 'CAUGHT',
        'pass': ok,
        't': DateTime.now().toIso8601String().substring(0, 19),
      };
      results.writeln(jsonEncode(rec));
      await results.flush();
      print(jsonEncode(rec));
    }
  } finally {
    await teardown();
    await results.close();
  }
}

Future<String> _id(String flag) async =>
    ((await Process.run('id', [flag])).stdout as String).trim();
