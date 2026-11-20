import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack;

import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_keys/tremulator_keys.dart';

/// The command line, as given.
List<String> labArguments(List<String> args) => args;

/// The run's log: JSON lines appended to [out], flushed per line.
LabSink openLabSink(String out) => _FileSink(LabLog(out));

/// Keys kept in the directory [state], made on first use.
Future<KeyStore> openLabKeyStore(String state, String name) =>
    openLabKeys(Directory(state)..createSync(recursive: true), name);

/// Waits until the file [untilFile] exists.
Future<void> waitForStop(String untilFile, Report report) =>
    waitForFile(untilFile, report);

/// Ends the process with [code].
void finishLab(int code) => exit(code);

/// Where a lab run's events go.
abstract interface class LabSink {
  /// Records one event.
  void call(Map<String, Object?> event);

  /// Writes out what is pending; the run ends after.
  Future<void> close();
}

class _FileSink implements LabSink {
  _FileSink(this._log);

  final LabLog _log;

  @override
  void call(Map<String, Object?> event) => _log(event);

  @override
  Future<void> close() async => _log.close();
}

/// Nothing to do: the Linux plugin sends the screen as it would a camera
/// (calls47nat: 2,897 frames decoded in 120 s on P2).
void markAsCamera(MediaStreamTrack track) {}
