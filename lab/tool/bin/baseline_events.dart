/// Timestamp what the operator sees during a WhatsApp run. Type one line per
/// event and press Enter; each line is appended at once to
/// lab/baseline/results/events_<label>.jsonl with the wall clock (ms) and the
/// seconds since the previous event. Suggested words: `sent 1`, `delivered 1`,
/// `seen 1`, `photo sent`, `photo delivered`, `dial`, `ringing`, `connected`,
/// `video on`, `freeze`, `resumed`, `dropped`, `hangup`, `clap`. Human reaction
/// adds about 0.3 s to each stamp; the capture and screen recording are the
/// fine clock. `q` quits.
///
///   dart run bin/baseline_events.dart <label>
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tremulator_lab/lab_dir.dart';

void main(List<String> argv) {
  if (argv.length != 1 || argv.first.startsWith('-')) {
    stderr.writeln('usage: baseline_events.dart <label>');
    exit(2);
  }
  final label = argv.first;
  final dir = Directory('${labDir()}/baseline/results')..createSync();
  final f = File('${dir.path}/events_$label.jsonl');
  final sink = f.openWrite(mode: FileMode.append);
  print('logging to ${f.path}; type an event and Enter, q to quit');
  DateTime? prev;
  var n = 0;
  while (true) {
    stdout.write('> ');
    final line = stdin.readLineSync()?.trim();
    if (line == null || line == 'q') break;
    if (line.isEmpty) continue;
    final now = DateTime.now();
    n++;
    final rec = {
      'n': n,
      't': now.toIso8601String(),
      'ms': now.millisecondsSinceEpoch,
      'since_prev_s': prev == null
          ? null
          : now.difference(prev).inMilliseconds / 1000,
      'event': line,
    };
    sink.writeln(jsonEncode(rec));
    unawaited(sink.flush());
    print(
      '  #$n ${now.toIso8601String().substring(11, 23)}'
      '${rec['since_prev_s'] == null ? '' : '  +${rec['since_prev_s']} s'}',
    );
    prev = now;
  }
  unawaited(sink.close());
}
