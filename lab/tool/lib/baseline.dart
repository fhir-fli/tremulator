/// Shared pieces of the WhatsApp baseline instruments (lab/baseline/): the
/// profile table, the same checks the Docker lab applied (network_lab.dart),
/// and parsers for ping, iperf3 server JSON, tcpdump text and PCM WAV.
///
/// Pre-registered 2026-10-05, before the first run over Wi-Fi:
/// - RTT target on Wi-Fi is the profile's RTT plus the unshaped Wi-Fi RTT to
///   the same phone measured in the same session; tolerance is the larger of
///   the same phone measured in the same session; tolerance is the larger
/// - Loss by ping is two-way: the target is 1 - (1 - p)^2 (GATE1.md: a ping
///   crosses both directions). Judged by the Wilson 95% interval, sized the
///   same way as the lab's loss tests.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:tremulator_lab/network_lab.dart'
    show Lab, overhead, payloadRate;

export 'package:tremulator_lab/network_lab.dart'
    show overhead, payloadLoss, payloadRate;

/// name: (rate kbit/s, RTT ms, loss %) — SUCCESS.md Gate 1 table, P0 = dead.
const baselineProfiles = <String, (int, int, double)>{
  'P0': (0, 0, 100),
  'P1': (50, 400, 5),
  'P2': (300, 200, 2),
  'P3': (1000, 700, 1),
  'P4': (300, 250, 2),
  'P5': (10000, 5, 0),
};

double median(List<double> xs) => Lab.median(xs);
(double, double) wilson(int k, int n) => Lab.wilson(k, n);

/// RTT tolerance in ms: max(10% of target, 2 ms).
double rttTolerance(double targetMs) => max(0.10 * targetMs, 2);

/// Delivered UDP payload rate expected from a cap, as the lab computed it.
double expectedBps(int rateKbit, double lossPct) =>
    rateKbit *
    1000 *
    payloadRate /
    (payloadRate + overhead) *
    (1 - lossPct / 100);

/// Datagrams needed so two runs on an identical link land within ±10%:
/// (1 - p) / (p · 0.0013), at least 2,000 (the lab's sizing).
int lossSampleSize(double p) =>
    p > 0 ? max(2000, ((1 - p) / (p * 0.0013)).ceil()) : 2000;

/// Two-way loss a ping sees when each direction drops `p`.
double twoWayLoss(double p) => 1 - (1 - p) * (1 - p);

/// Ping interval (s) that keeps 58-byte pings under a quarter of the cap and
/// never below 10 ms (the unprivileged minimum is 2 ms; 10 ms is plenty).
double pingInterval(int rateKbit) {
  if (rateKbit <= 0) return 0.01;
  const bytes = 16 + 8 + 20 + 14; // payload, ICMP, IPv4, Ethernet
  return max(0.01, bytes * 8 * 4 / (rateKbit * 1000));
}

List<double> rttsFromPing(String out) => RegExp(
  r'time=([\d.]+) ms',
).allMatches(out).map((m) => double.parse(m.group(1)!)).toList();

/// `ping -D` reply timestamps, seconds.
List<double> stampsFromPing(String out) => RegExp(
  r'^\[([\d.]+)\].*time=',
  multiLine: true,
).allMatches(out).map((m) => double.parse(m.group(1)!)).toList();

/// Up windows and down gaps from reply timestamps; a gap over 2 s is an outage.
/// Same derivation as the lab's dutyCycle (network_lab.dart).
({List<double> ups, List<double> downs, List<double> judgedUps}) dutyWindows(
  List<double> stamps,
) {
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
  final judged = ups.length > 2 ? ups.sublist(1, ups.length - 1) : ups;
  return (ups: ups, downs: downs, judgedUps: judged);
}

/// Receiver-side figures from `iperf3 -s -1 -J` output. For UDP the server's
/// `end.sum` is what arrived; for TCP `end.sum_received`.
Map<String, Object?> parseIperfServerJson(String text) {
  final j = jsonDecode(text) as Map<String, dynamic>;
  if (j['error'] != null) return {'error': '${j['error']}'};
  final end = j['end'] as Map<String, dynamic>;
  final s = (end['sum_received'] ?? end['sum']) as Map<String, dynamic>;
  return {
    'bps': s['bits_per_second'],
    'lost': s['lost_packets'],
    'packets': s['packets'],
    'seconds': s['seconds'],
  };
}

/// One traffic endpoint seen from the phone's side of the capture.
class Flow {
  Flow(this.proto, this.remote, this.port, this.kind);
  final String proto;
  final String remote;
  final String port;
  final String kind; // ap-lan | home-lan | internet | multicast
  int packetsOut = 0;
  int packetsIn = 0;
  int bytesOut = 0;
  int bytesIn = 0;
  double? first;
  double? last;

  Map<String, Object?> toJson() => {
    'proto': proto,
    'remote': remote,
    'port': port,
    'kind': kind,
    'packets_out': packetsOut,
    'packets_in': packetsIn,
    'bytes_out': bytesOut,
    'bytes_in': bytesIn,
    'first_s': first,
    'last_s': last,
  };
}

final _tcpdumpLine = RegExp(
  r'^(\d+\.\d+) IP (\d+\.\d+\.\d+\.\d+)\.(\d+) > (\d+\.\d+\.\d+\.\d+)\.(\d+): '
  r'(UDP, length (\d+)|tcp (\d+)|(\w+))',
);

String classifyRemote(String ip, {required String ap, required String home}) {
  if (ip.startsWith('224.') || ip.startsWith('239.') || ip.endsWith('.255')) {
    return 'multicast';
  }
  if (ip.startsWith(ap)) return 'ap-lan';
  if (ip.startsWith(home)) return 'home-lan';
  return 'internet';
}

/// Aggregate `tcpdump -r x -nn -q -tt` text by remote endpoint. `phone` is the
/// field phone's address; `ap`/`home` are subnet prefixes ("10.42.0.").
List<Flow> classifyFlows(
  String text, {
  required String phone,
  required String ap,
  required String home,
}) {
  final flows = <String, Flow>{};
  for (final line in LineSplitter.split(text)) {
    final m = _tcpdumpLine.firstMatch(line);
    if (m == null) continue;
    final t = double.parse(m.group(1)!);
    final src = m.group(2)!;
    final dst = m.group(4)!;
    final bool out;
    final String remote;
    final String port;
    if (src == phone) {
      out = true;
      remote = dst;
      port = m.group(5)!;
    } else if (dst == phone) {
      out = false;
      remote = src;
      port = m.group(3)!;
    } else {
      continue;
    }
    final proto = m.group(7) != null
        ? 'udp'
        : m.group(8) != null
        ? 'tcp'
        : m.group(9)!.toLowerCase();
    final len = int.tryParse(m.group(7) ?? m.group(8) ?? '') ?? 0;
    final key = '$proto $remote $port';
    final f = flows.putIfAbsent(
      key,
      () =>
          Flow(proto, remote, port, classifyRemote(remote, ap: ap, home: home)),
    );
    if (out) {
      f.packetsOut++;
      f.bytesOut += len;
    } else {
      f.packetsIn++;
      f.bytesIn += len;
    }
    f.first = f.first == null ? t : min(f.first!, t);
    f.last = f.last == null ? t : max(f.last!, t);
  }
  final list = flows.values.toList()
    ..sort(
      (a, b) => (b.bytesIn + b.bytesOut).compareTo(a.bytesIn + a.bytesOut),
    );
  return list;
}

/// 16-bit PCM mono WAV -> (sample rate, samples).
(int, Int16List) parseWav16(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }
  var pos = 12;
  int? rate;
  int? channels;
  int? bits;
  while (pos + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final size = d.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ') {
      final fmt = d.getUint16(body, Endian.little);
      channels = d.getUint16(body + 2, Endian.little);
      rate = d.getUint32(body + 4, Endian.little);
      bits = d.getUint16(body + 14, Endian.little);
      if (fmt != 1 || channels != 1 || bits != 16) {
        throw FormatException(
          'need 16-bit PCM mono, got fmt=$fmt ch=$channels bits=$bits',
        );
      }
    } else if (id == 'data') {
      if (rate == null) throw const FormatException('data before fmt');
      final n = min(size, bytes.length - body) ~/ 2;
      final out = Int16List(n);
      for (var i = 0; i < n; i++) {
        out[i] = d.getInt16(body + 2 * i, Endian.little);
      }
      return (rate, out);
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('no data chunk');
}

/// Onset times (s): first sample whose magnitude exceeds `threshold` of the
/// recording's peak, then nothing for `deadMs` after each onset.
List<double> onsets(
  Int16List samples,
  int rate, {
  double threshold = 0.5,
  int deadMs = 150,
}) {
  var peak = 0;
  for (final s in samples) {
    peak = max(peak, s.abs());
  }
  if (peak == 0) return const [];
  final level = peak * threshold;
  final dead = rate * deadMs ~/ 1000;
  final out = <double>[];
  var i = 0;
  while (i < samples.length) {
    if (samples[i].abs() >= level) {
      out.add(i / rate);
      i += dead;
    } else {
      i++;
    }
  }
  return out;
}
