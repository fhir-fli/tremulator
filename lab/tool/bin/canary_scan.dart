/// Usage: dart run bin/canary_scan.dart CANARIES_FILE OUT_JSONL PATH [PATH ...]
/// Exit status 1 if any canary was found, 0 if clean.
library;

import 'dart:convert';
import 'dart:io';

import 'package:tremulator_lab/canary_scan.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('usage: canary_scan CANARIES_FILE OUT_JSONL PATH [PATH ...]');
    exit(2);
  }
  final out = File(args[1]).openWrite();
  final hits = await scanPaths(args[0], args.sublist(2), out);
  await out.close();
  stdout.writeln(jsonEncode({'hits': hits.length}));
  exit(hits.isEmpty ? 0 : 1);
}
