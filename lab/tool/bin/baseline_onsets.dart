/// Onset times in a clap-test recording from audio_delay.sh. The first onset
/// is the click heard directly, the second is the same click out of the
/// receiving phone's speaker; their gap is the one-way audio delay.
///
///   dart run bin/baseline_onsets.dart results/p2-clap.wav [--threshold 0.5] [--dead-ms 150]
///   dart run bin/baseline_onsets.dart results/p1-clap.wav --transient [--ratio 6] [--floor 0.05] [--from s] [--to s]
library;

import 'dart:io';

import 'package:tremulator_lab/baseline.dart';

void main(List<String> argv) {
  if (argv.isEmpty || argv.first.startsWith('-')) {
    stderr.writeln(
      'usage: baseline_onsets.dart <wav> [--threshold f] [--dead-ms n]',
    );
    exit(2);
  }
  String opt(String k, String d) {
    final i = argv.indexOf('--$k');
    return i >= 0 && i + 1 < argv.length ? argv[i + 1] : d;
  }

  final (rate, samples) = parseWav16(File(argv.first).readAsBytesSync());
  final transient = argv.contains('--transient');
  final from = double.parse(opt('from', '0'));
  final to = double.parse(opt('to', '1e9'));
  var ts = transient
      ? transientOnsets(
          samples,
          rate,
          ratio: double.parse(opt('ratio', '6')),
          floor: double.parse(opt('floor', '0.05')),
          deadMs: int.parse(opt('dead-ms', '150')),
        )
      : onsets(
          samples,
          rate,
          threshold: double.parse(opt('threshold', '0.5')),
          deadMs: int.parse(opt('dead-ms', '150')),
        );
  ts = ts.where((t) => t >= from && t <= to).toList();
  print('${samples.length / rate} s at $rate Hz, ${ts.length} onsets');
  for (var i = 0; i < ts.length; i++) {
    final gap = i == 0 ? '' : '  +${((ts[i] - ts[i - 1]) * 1000).round()} ms';
    print('  ${ts[i].toStringAsFixed(3)} s$gap');
  }
  if (transient) {
    final pairs = onsetPairs(ts);
    print('${pairs.length} pairs 150-1500 ms apart (direct, then speaker):');
    for (final (t, gap) in pairs) {
      print('  ${t.toStringAsFixed(2)} s  one-way ${(gap * 1000).round()} ms');
    }
  } else if (ts.length >= 2) {
    print(
      'one-way delay (onset 2 - onset 1): '
      '${((ts[1] - ts[0]) * 1000).round()} ms',
    );
  }
}
