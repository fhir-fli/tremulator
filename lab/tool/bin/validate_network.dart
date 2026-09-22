/// Usage: dart run bin/validate_network.dart LABEL [--only-loss] [--only-p0]
/// Writes lab/network/results/LABEL.jsonl, one line per measurement, flushed.
library;

import 'dart:io';

import 'package:tremulator_lab/lab_dir.dart';
import 'package:tremulator_lab/network_lab.dart';

Future<void> main(List<String> args) async {
  // A label that looks like a flag is refused: '--help' once started a full
  // run under that label (2026-09-22).
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln('usage: validate_network LABEL [--only-loss] [--only-p0]');
    exit(2);
  }
  final dir = Directory('${labDir()}/network/results')
    ..createSync(recursive: true);
  final sink = File(
    '${dir.path}/${args[0]}.jsonl',
  ).openWrite(mode: FileMode.append);
  final lab = Lab(
    args[0],
    sink,
    onlyLoss: args.contains('--only-loss'),
    onlyP0: args.contains('--only-p0'),
  );
  var stopping = false;
  ProcessSignal.sigterm.watch().listen((_) async {
    if (stopping) return;
    stopping = true;
    await lab.teardown(); // a stop must still clean up the lab
    exit(143);
  });
  await lab.run();
  await sink.close();
  stdout.writeln('DONE');
  exit(0);
}
