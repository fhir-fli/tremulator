/// Who did the field phone talk to, and how much? Reads a capture from
/// capture.sh through tcpdump in the lab image and aggregates by remote
/// endpoint. A UDP flow to the home LAN (the consultant phone, through NAT)
/// is a peer-to-peer call; UDP to the internet is a relayed one. Writes
/// `<pcap>.flows.json` and prints a table.
///
///   dart run bin/baseline_flows.dart results/p2-call.pcap --phone 10.42.0.23 \
///       [--ap 10.42.0.] [--home 192.168.8.]
library;

import 'dart:convert';
import 'dart:io';

import 'package:tremulator_lab/baseline.dart';
import 'package:tremulator_lab/network_lab.dart' show sh;

const img = 'tremulator-lab:latest';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty || argv.first.startsWith('-')) {
    stderr.writeln(
      'usage: baseline_flows.dart <pcap> --phone <ip> [--ap p] [--home p]',
    );
    exit(2);
  }
  final pcap = File(argv.first).absolute;
  if (!pcap.existsSync()) {
    stderr.writeln('${pcap.path} not found');
    exit(2);
  }
  String opt(String k, String d) {
    final i = argv.indexOf('--$k');
    return i >= 0 && i + 1 < argv.length ? argv[i + 1] : d;
  }

  final phone = opt('phone', '');
  if (phone.isEmpty) {
    stderr.writeln('--phone <ip> is required');
    exit(2);
  }
  final r = await sh([
    'docker',
    'run',
    '--rm',
    '--network',
    'none',
    '-v',
    '${pcap.parent.path}:/cap:ro',
    img,
    'tcpdump',
    '-r',
    '/cap/${pcap.uri.pathSegments.last}',
    '-nn',
    '-q',
    '-tt',
  ]);
  if (r.code != 0) {
    stderr.writeln('tcpdump failed: ${r.err}');
    exit(1);
  }
  final flows = classifyFlows(
    r.out,
    phone: phone,
    ap: opt('ap', '10.42.0.'),
    home: opt('home', '192.168.8.'),
  );
  final byKind = <String, Map<String, int>>{};
  for (final f in flows) {
    final k = byKind.putIfAbsent(
      f.kind,
      () => {'packets': 0, 'bytes': 0, 'flows': 0},
    );
    k['packets'] = k['packets']! + f.packetsIn + f.packetsOut;
    k['bytes'] = k['bytes']! + f.bytesIn + f.bytesOut;
    k['flows'] = k['flows']! + 1;
  }
  final out = File('${pcap.path}.flows.json')
    ..writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'pcap': pcap.path,
        'phone': phone,
        'by_kind': byKind,
        'flows': flows.map((f) => f.toJson()).toList(),
      }),
    );
  print('kind        flows  packets      bytes');
  for (final e in byKind.entries) {
    print(
      '${e.key.padRight(11)} ${e.value['flows'].toString().padLeft(5)} '
      '${e.value['packets'].toString().padLeft(8)} '
      '${e.value['bytes'].toString().padLeft(10)}',
    );
  }
  print('\ntop endpoints');
  for (final f in flows.take(15)) {
    print(
      '${f.proto.padRight(4)} ${f.kind.padRight(9)} '
      '${'${f.remote}:${f.port}'.padRight(22)} '
      'out ${f.packetsOut}/${f.bytesOut} B  in ${f.packetsIn}/${f.bytesIn} B  '
      '${((f.last ?? 0) - (f.first ?? 0)).toStringAsFixed(1)} s',
    );
  }
  print('\nwritten ${out.path}');
}
