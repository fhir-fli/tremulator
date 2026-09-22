/// Locate the lab/ directory from wherever the program runs: `dart run` runs
/// from bin/, a `dart build cli` bundle from `build/<name>/bundle/bin/`. Walk up
/// from the script until a directory holds both network/ and tool/.
library;

import 'dart:io';

String labDir() {
  var d = File(Platform.script.toFilePath()).parent;
  while (true) {
    if (Directory('${d.path}/network').existsSync() &&
        Directory('${d.path}/tool').existsSync()) {
      return d.path;
    }
    final up = d.parent;
    if (up.path == d.path) {
      throw StateError('lab/ not found above ${Platform.script}');
    }
    d = up;
  }
}
