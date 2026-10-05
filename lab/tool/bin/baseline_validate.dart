/// Validate the shaped Wi-Fi path to the field phone before any WhatsApp
/// number is taken (lab/baseline/README.md). Runs from the laptop; the phone
/// side is `ping` replies and, unless --ping-only, iperf3 client runs typed
/// into Termux (Android) or a Mac on the same hotspot. The server side runs
/// in the lab image on the host network. Results append to
/// lab/baseline/results/validate_<label>.jsonl as they happen.
///
///   dart run bin/baseline_validate.dart --profile off --phone 10.42.0.23 \
///       --label v1
///       unshaped: measures the Wi-Fi RTT to the phone; pass it back as
///       --base-rtt
///   dart run bin/baseline_validate.dart --profile P2 --phone 10.42.0.23 \
///       --label v1 --base-rtt 4.1 [--ping-only] [--server 10.42.0.1]
///   dart run bin/baseline_validate.dart --profile P4 --phone ... --label v1 --duty
///       P4 only: 185 s of 0.2 s pings while shape.sh P4 is looping
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tremulator_lab/baseline.dart';
import 'package:tremulator_lab/lab_dir.dart';
import 'package:tremulator_lab/network_lab.dart' show sh;

const img = 'tremulator-lab:latest';

Future<void> main(List<String> argv) async {
  final a = _args(argv);
  final profile = a['profile'] ?? _die('--profile is required');
  final phone = a['phone'] ?? _die('--phone <ip> is required');
  final label = a['label'] ?? _die('--label is required');
  if (label.startsWith('-')) _die('label must not start with -');
  final server = a['server'] ?? '10.42.0.1';
  final baseRtt = double.tryParse(a['base-rtt'] ?? '') ?? 0;
  final pingOnly = a.containsKey('ping-only');
  final duty = a.containsKey('duty');

  final dir = Directory('${labDir()}/baseline/results')..createSync();
  final sink = File(
    '${dir.path}/validate_$label.jsonl',
  ).openWrite(mode: FileMode.append);
  Future<void> log(Map<String, Object?> rec) async {
    rec['t'] = DateTime.now().toIso8601String().substring(0, 19);
    rec['label'] = label;
    rec['profile'] = profile;
    final line = jsonEncode(rec);
    sink.writeln(line);
    await sink.flush();
    print(line);
  }

  if (profile == 'off') {
    final rtts = await _ping(phone, 100, 0.2);
    await log({
      'metric': 'rtt_ms_unshaped',
      'median': rtts.isEmpty ? null : median(rtts),
      'n_replies': rtts.length,
      'note': 'pass this median as --base-rtt to the shaped runs',
    });
    await sink.close();
    return;
  }

  final p = baselineProfiles[profile] ?? _die('unknown profile $profile');
  final (rate, rtt, loss) = p;

  if (duty) {
    if (profile != 'P4') _die('--duty is for P4');
    print('start `shape.sh P4` now if it is not looping; 185 s of pings...');
    final r = await sh(
      ['ping', '-n', '-D', '-i', '0.2', '-W', '1', '-w', '185', phone],
      timeoutS: 240,
    );
    final w = dutyWindows(stampsFromPing(r.out));
    double r1(double x) => (x * 10).round() / 10;
    await log({
      'metric': 'duty_cycle',
      'up_windows_s': w.ups.map(r1).toList(),
      'down_gaps_s': w.downs.map(r1).toList(),
      'judged_up': w.judgedUps.map(r1).toList(),
      'pass':
          w.judgedUps.isNotEmpty &&
          w.judgedUps.every((u) => (u - 30).abs() <= 3) &&
          w.downs.isNotEmpty &&
          w.downs.every((d) => (d - 60).abs() <= 6),
    });
    await sink.close();
    return;
  }

  if (profile == 'P0') {
    final rtts = await _ping(phone, 20, 0.5);
    await log({
      'metric': 'dead_link',
      'n_replies': rtts.length,
      'pass': rtts.isEmpty,
    });
    await sink.close();
    return;
  }

  // RTT: target plus the unshaped Wi-Fi RTT; tolerance max(10%, 2 ms).
  final target = rtt + baseRtt;
  final rtts = await _ping(phone, 100, max(0.2, pingInterval(rate)));
  final med = rtts.isEmpty ? null : median(rtts);
  await log({
    'metric': 'rtt_ms',
    'target': target,
    'base_rtt': baseRtt,
    'tolerance': rttTolerance(target),
    'median': med,
    'n_replies': rtts.length,
    'pass': med != null && (med - target).abs() <= rttTolerance(target),
  });

  if (pingOnly) {
    final p1 = loss / 100;
    final p2 = twoWayLoss(p1);
    final n = lossSampleSize(p2);
    final interval = pingInterval(rate);
    print(
      'loss by ping: $n pings at ${interval}s '
      '(${(n * interval / 60).toStringAsFixed(1)} min)',
    );
    final r = await sh(
      [
        'ping',
        '-n',
        '-q',
        '-c',
        '$n',
        '-i',
        '$interval',
        '-s',
        '16',
        '-W',
        '3',
        phone,
      ],
      timeoutS: (n * interval + 120).ceil(),
    );
    final m = RegExp(
      r'(\d+) packets transmitted, (\d+) received',
    ).firstMatch(r.out);
    final sent = int.tryParse(m?.group(1) ?? '') ?? 0;
    final got = int.tryParse(m?.group(2) ?? '') ?? 0;
    final lost = sent - got;
    final (lo, hi) = wilson(lost, sent);
    await log({
      'metric': 'loss_two_way_ping',
      'target_pct': 100 * p2,
      'per_direction_pct': loss,
      'measured_pct': sent == 0 ? null : 100 * lost / sent,
      'ci95_pct': [100 * lo, 100 * hi],
      'sent': sent,
      'lost': lost,
      'pass': sent >= 2000 && lo <= p2 && p2 <= hi,
      'rate': 'unmeasured in --ping-only mode',
    });
    await sink.close();
    return;
  }

  // Delivered rate: phone sends UDP at 1.2 × cap for 30 s.
  final exp = expectedBps(rate, loss);
  final u = await _iperfServer(
    'iperf3 -c $server -u -b ${(rate * 1000 * 1.2).toInt()} '
    '-l $payloadRate -t 30',
    timeoutS: 400,
  );
  final bps = u['bps'] as num?;
  await log({
    'metric': 'delivered_bps',
    'expected': exp,
    ...u,
    'pass': bps != null && (bps - exp).abs() <= 0.10 * exp,
  });

  // Loss: phone sends UDP at half the cap, sized like the lab.
  final pps = rate * 1000 * 0.5 / ((payloadLoss + overhead) * 8);
  final need = lossSampleSize(loss / 100);
  final secs = max(15, (need / pps).ceil() + 2);
  final l = await _iperfServer(
    'iperf3 -c $server -u -b ${(rate * 1000 * 0.5).toInt()} '
    '-l $payloadLoss -t $secs',
    timeoutS: secs + 300,
  );
  final n = l['packets'] as int?;
  if (n != null && n > 0) {
    final lost = l['lost']! as int;
    final (lo, hi) = wilson(lost, n);
    await log({
      'metric': 'loss',
      'target_pct': loss,
      'measured_pct': 100 * lost / n,
      'ci95_pct': [100 * lo, 100 * hi],
      ...l,
      'pass': lo <= loss / 100 && loss / 100 <= hi && n >= 2000,
    });
  } else {
    await log({'metric': 'loss', 'target_pct': loss, ...l, 'pass': false});
  }
  await sink.close();
}

Future<List<double>> _ping(String ip, int count, double interval) async {
  final r = await sh(
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
  return rttsFromPing(r.out);
}

/// Start a one-shot iperf3 server, tell the operator what to type on the
/// phone, and return the receiver-side figures when the client run ends.
Future<Map<String, Object?>> _iperfServer(
  String phoneCommand, {
  required int timeoutS,
}) async {
  print(
    '\n>>> on the phone (Termux) or the Mac, run:\n    $phoneCommand\n'
    '    waiting up to $timeoutS s for the run to finish...',
  );
  final r = await sh(
    [
      'docker',
      'run',
      '--rm',
      '--network',
      'host',
      img,
      'iperf3',
      '-s',
      '-1',
      '-J',
    ],
    timeoutS: timeoutS,
  );
  if (r.code == null) return {'error': r.err};
  try {
    return {...parseIperfServerJson(r.out), 'phone_command': phoneCommand};
  } on FormatException {
    final tail = '${r.out}${r.err}';
    return {'error': tail.substring(max(0, tail.length - 200))};
  }
}

Map<String, String> _args(List<String> argv) {
  final m = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final k = argv[i];
    if (!k.startsWith('--')) _die('unexpected argument $k');
    final next = i + 1 < argv.length ? argv[i + 1] : null;
    if (next != null && !next.startsWith('--')) {
      m[k.substring(2)] = next;
      i++;
    } else {
      m[k.substring(2)] = '';
    }
  }
  return m;
}

Never _die(String msg) {
  stderr.writeln(msg);
  exit(2);
}
