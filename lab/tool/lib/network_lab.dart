/// Validate the tremulator network profiles (docs/GATE1.md), ported from
/// lab/network/validate.py with every fix it accumulated:
/// - receiver-side iperf3 figures (`end.sum_received`), not the sender's;
/// - iperf3 retried up to 5 times with a fresh server, because its own setup
///   crosses the shaped link (A/B: 0/40 errors at 0% loss, 20/29 at 30%);
/// - neighbour entries pinned, because the lab is one Ethernet segment and ARP
///   for the peer fails during a P4 outage;
/// - a command that never finishes is recorded as a result, not a crash;
/// - loss tests sized so two runs on an identical link land within ±10%;
/// - two networks and two container pairs created once per run, because
///   per-profile create/remove raised "disconnected" alerts on Grey's laptop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const img = 'tremulator-lab:latest';
const payloadRate = 1000;
const payloadLoss = 64;
const overhead = 42; // UDP 8 + IPv4 20 + Ethernet 14 bytes

/// name: (rate kbit/s, RTT ms, loss %, internal network)
const profiles = <String, (int, int, double, bool)>{
  'P1': (50, 400, 5.0, false),
  'P2': (300, 200, 2.0, false),
  'P3': (1000, 700, 1.0, false),
  'P4': (300, 250, 2.0, false),
  'P5': (10000, 5, 0.0, true),
};
const nets = {false: 'tlab-net', true: 'tlab-internal'};
const pairs = {
  false: ('tlab-srv', 'tlab-cli'),
  true: ('tlab-srv-int', 'tlab-cli-int'),
};

class Proc {
  Proc(this.code, this.out, this.err);
  final int? code; // null = timed out
  final String out;
  final String err;
}

Future<Proc> sh(List<String> cmd, {int timeoutS = 600}) async {
  final p = await Process.start(cmd.first, cmd.sublist(1));
  final out = p.stdout.transform(utf8.decoder).join();
  final err = p.stderr.transform(utf8.decoder).join();
  try {
    final code = await p.exitCode.timeout(Duration(seconds: timeoutS));
    return Proc(code, await out, await err);
  } on TimeoutException {
    p.kill();
    return Proc(null, '', 'TIMEOUT after ${timeoutS}s');
  }
}

class Lab {
  Lab(this.label, this.sink, {required this.onlyLoss, required this.onlyP0});
  final String label;
  final IOSink sink;
  final bool onlyLoss;
  final bool onlyP0;
  late String srv;
  late String cli;

  void log(Map<String, Object?> rec) {
    rec['t'] = DateTime.now().toIso8601String().substring(0, 19);
    final line = jsonEncode(rec);
    sink.writeln(line);
    stdout.writeln(line);
  }

  Future<Proc> dx(String c, List<String> args, {int timeoutS = 600}) =>
      sh(['docker', 'exec', c, ...args], timeoutS: timeoutS);

  Future<void> netem(String c, num rate, num delayMs, num loss) async {
    final args = [
      'tc',
      'qdisc',
      'replace',
      'dev',
      'eth0',
      'root',
      'netem',
      'delay',
      '${delayMs}ms',
      'loss',
      '$loss%',
    ];
    if (rate > 0) args.addAll(['rate', '${rate}kbit']);
    final r = await dx(c, args);
    if (r.code != 0) throw StateError('netem on $c: ${r.err}');
  }

  Future<(String, String)> ipMac(String c) async {
    final ip = (await dx(c, [
      'sh',
      '-c',
      r"ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1",
    ])).out.trim();
    final mac = (await dx(c, [
      'cat',
      '/sys/class/net/eth0/address',
    ])).out.trim();
    return (ip, mac);
  }

  Future<void> pinNeighbours(String a, String b) async {
    final (aip, amac) = await ipMac(a);
    final (bip, bmac) = await ipMac(b);
    await dx(a, [
      'ip',
      'neigh',
      'replace',
      bip,
      'lladdr',
      bmac,
      'dev',
      'eth0',
      'nud',
      'permanent',
    ]);
    await dx(b, [
      'ip',
      'neigh',
      'replace',
      aip,
      'lladdr',
      amac,
      'dev',
      'eth0',
      'nud',
      'permanent',
    ]);
  }

  Future<void> teardown() async {
    for (final (s, c) in pairs.values) {
      await sh(['docker', 'rm', '-f', s, c]);
    }
    for (final n in nets.values) {
      await sh(['docker', 'network', 'rm', n]);
    }
  }

  Future<void> setup() async {
    await teardown();
    for (final internal in [false, true]) {
      final r = await sh([
        'docker',
        'network',
        'create',
        if (internal) '--internal',
        nets[internal]!,
      ]);
      if (r.code != 0) throw StateError('network create: ${r.err}');
      final (s, c) = pairs[internal]!;
      for (final name in [s, c]) {
        final q = await sh([
          'docker',
          'run',
          '-d',
          '--rm',
          '--name',
          name,
          '--network',
          nets[internal]!,
          '--cap-add',
          'NET_ADMIN',
          img,
        ]);
        if (q.code != 0) throw StateError('docker run $name: ${q.err}');
      }
      await dx(s, ['iperf3', '-s', '-D']);
      await pinNeighbours(s, c);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> use(bool internal) async {
    final pair = pairs[internal]!;
    srv = pair.$1;
    cli = pair.$2;
    for (final c in [srv, cli]) {
      await dx(c, [
        'sh',
        '-c',
        "pkill -f 'while true' ; tc qdisc del dev eth0 root 2>/dev/null; true",
      ]);
    }
  }

  Future<String> srvIp() async => (await ipMac(srv)).$1;

  Future<List<double>> pingRtts(
    String ip, {
    int count = 100,
    double interval = 0.2,
  }) async {
    final r = await dx(
      cli,
      [
        'ping',
        '-n',
        '-c',
        '$count',
        '-i',
        '$interval',
        '-s',
        '16',
        '-W',
        '3',
        ip,
      ],
      timeoutS: (count * interval + 60).ceil(),
    );
    return RegExp(
      r'time=([\d.]+) ms',
    ).allMatches(r.out).map((m) => double.parse(m.group(1)!)).toList();
  }

  Future<Map<String, Object?>> iperfUdp(
    String ip,
    num rateBps,
    int length,
    int secs, {
    int tries = 5,
  }) async {
    final errors = <String>[];
    for (var attempt = 0; attempt < tries; attempt++) {
      await dx(srv, ['sh', '-c', 'pkill iperf3; sleep 0.5; iperf3 -s -D']);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final r = await dx(
        cli,
        [
          'iperf3',
          '-c',
          ip,
          '-u',
          '-b',
          '${rateBps.toInt()}',
          '-l',
          '$length',
          '-t',
          '$secs',
          '-J',
        ],
        timeoutS: secs + 120,
      );
      Map<String, dynamic> j;
      try {
        j = jsonDecode(r.out) as Map<String, dynamic>;
      } on FormatException {
        final tail = '${r.out}${r.err}';
        errors.add(tail.substring(max(0, tail.length - 150)));
        continue;
      }
      if (j['error'] != null) {
        errors.add('${j['error']}');
        continue;
      }
      final end = j['end'] as Map<String, dynamic>;
      final s = (end['sum_received'] ?? end['sum']) as Map<String, dynamic>;
      return {
        'bps': s['bits_per_second'],
        'lost': s['lost_packets'],
        'packets': s['packets'],
        'seconds': s['seconds'],
        'sent_bps': (end['sum_sent'] as Map?)?['bits_per_second'],
        'retries': attempt,
        'retry_errors': errors,
      };
    }
    return {
      'error': errors.isEmpty ? 'unknown' : errors.last,
      'retries': tries,
      'retry_errors': errors,
    };
  }

  static (double, double) wilson(int k, int n, [double z = 1.96]) {
    if (n == 0) return (0, 1);
    final p = k / n;
    final d = 1 + z * z / n;
    final c = (p + z * z / (2 * n)) / d;
    final h = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d;
    return (max(0, c - h), min(1, c + h));
  }

  static double median(List<double> xs) {
    final s = [...xs]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  Future<void> lossTest(String name, int rate, double loss, String ip) async {
    final pps = rate * 1000 * 0.5 / ((payloadLoss + overhead) * 8);
    final p = loss / 100;
    final need = p > 0 ? ((1 - p) / (p * 0.0013)).ceil() : 2000;
    final secs = max(15, (need / pps).ceil() + 2);
    final u = await iperfUdp(ip, rate * 1000 * 0.5, payloadLoss, secs);
    final n = u['packets'] as int?;
    if (n != null && n > 0) {
      final lost = u['lost']! as int;
      final (lo, hi) = wilson(lost, n);
      log({
        'run': label,
        'profile': name,
        'metric': 'loss',
        'target_pct': loss,
        'measured_pct': 100 * lost / n,
        'ci95_pct': [100 * lo, 100 * hi],
        ...u,
        'pass': lo <= p && p <= hi && n >= 2000,
      });
    } else {
      log({
        'run': label,
        'profile': name,
        'metric': 'loss',
        'target_pct': loss,
        ...u,
        'pass': false,
      });
    }
  }

  Future<void> steady(String name, int rate, int rtt, double loss) async {
    final ip = await srvIp();
    if (onlyLoss) return lossTest(name, rate, loss, ip);
    final rtts = await pingRtts(ip);
    final med = rtts.isEmpty ? null : median(rtts);
    log({
      'run': label,
      'profile': name,
      'metric': 'rtt_ms',
      'target': rtt,
      'median': med,
      'n_replies': rtts.length,
      'pass': med != null && (med - rtt).abs() <= 0.10 * rtt,
    });
    final exp =
        rate * 1000 * payloadRate / (payloadRate + overhead) * (1 - loss / 100);
    final u = await iperfUdp(ip, rate * 1000 * 1.2, payloadRate, 30);
    final bps = u['bps'] as num?;
    log({
      'run': label,
      'profile': name,
      'metric': 'delivered_bps',
      'expected': exp,
      ...u,
      'pass': bps != null && (bps - exp).abs() <= 0.10 * exp,
    });
    await lossTest(name, rate, loss, ip);
  }

  Future<bool> internetProbe() async =>
      (await dx(
        cli,
        ['ping', '-n', '-c', '3', '-W', '2', '1.1.1.1'],
        timeoutS: 30,
      )).code ==
      0;

  Future<void> dutyCycle(String name, int rate, int rtt, double loss) async {
    final up =
        'tc qdisc replace dev eth0 root netem delay ${rtt / 2}ms '
        'loss $loss% rate ${rate}kbit';
    const down = 'tc qdisc replace dev eth0 root netem loss 100%';
    final loop = 'while true; do $up; sleep 30; $down; sleep 60; done';
    for (final c in [srv, cli]) {
      await sh(['docker', 'exec', '-d', c, 'sh', '-c', loop]);
    }
    final r = await dx(
      cli,
      [
        'ping',
        '-n',
        '-D',
        '-i',
        '0.2',
        '-W',
        '1',
        '-w',
        '185',
        await srvIp(),
      ],
      timeoutS: 240,
    );
    final stamps = RegExp(
      r'^\[([\d.]+)\].*time=',
      multiLine: true,
    ).allMatches(r.out).map((m) => double.parse(m.group(1)!)).toList();
    final ups = <double>[];
    final downs = <double>[];
    double? start;
    for (var i = 0; i + 1 < stamps.length; i++) {
      start ??= stamps[i];
      if (stamps[i + 1] - stamps[i] > 2.0) {
        ups.add(stamps[i] - start);
        downs.add(stamps[i + 1] - stamps[i]);
        start = null;
      }
    }
    if (start != null && stamps.isNotEmpty) ups.add(stamps.last - start);
    final fullUps = ups.length > 2 ? ups.sublist(1, ups.length - 1) : ups;
    double r1(double x) => (x * 10).round() / 10;
    log({
      'run': label,
      'profile': name,
      'metric': 'duty_cycle',
      'up_windows_s': ups.map(r1).toList(),
      'down_gaps_s': downs.map(r1).toList(),
      'judged_up': fullUps.map(r1).toList(),
      'pass':
          fullUps.isNotEmpty &&
          fullUps.every((u) => (u - 30).abs() <= 3) &&
          downs.isNotEmpty &&
          downs.every((d) => (d - 60).abs() <= 6),
    });
  }

  Future<void> run() async {
    try {
      await setup();
      if (!onlyP0) {
        for (final e in profiles.entries) {
          final (rate, rtt, loss, internal) = e.value;
          await use(internal);
          for (final c in [srv, cli]) {
            await netem(c, rate, rtt / 2, loss);
          }
          await steady(e.key, rate, rtt, loss);
          if (onlyLoss) continue;
          if (e.key == 'P2') {
            final reach = await internetProbe();
            log({
              'run': label,
              'profile': 'P2',
              'metric': 'internet_reachable_control',
              'reachable': reach,
              'pass': reach,
            });
          }
          if (e.key == 'P5') {
            final reach = await internetProbe();
            log({
              'run': label,
              'profile': 'P5',
              'metric': 'no_internet',
              'reachable': reach,
              'pass': !reach,
            });
          }
          if (e.key == 'P4') await dutyCycle(e.key, rate, rtt, loss);
        }
      }
      if (!onlyLoss) {
        await use(false);
        for (final c in [srv, cli]) {
          await netem(c, 0, 0, 100);
        }
        final ip = await srvIp();
        final rtts = await pingRtts(ip, count: 20);
        final u = await iperfUdp(
          ip,
          100000,
          64,
          5,
          tries: 1,
        ); // a dead link must not be retried into success
        log({
          'run': label,
          'profile': 'P0',
          'metric': 'zero_link_fails',
          'ping_replies': rtts.length,
          'iperf': u,
          'pass': rtts.isEmpty && (u.containsKey('error') || u['bps'] == null),
        });
      }
    } finally {
      await teardown();
      await sink.flush();
    }
  }
}
