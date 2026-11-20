import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamTrackWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack;
import 'package:http/http.dart' as http;
import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_keys/tremulator_keys.dart';

/// The lab helper served beside the page (lab/gate2/browser/lab_helper.py,
/// behind the same origin): it appends log lines to the run's file, answers
/// whether the stop sign exists, and takes the exit code.
final Uri _helper = Uri.base.replace(path: '/lab/', query: '');

/// The page's query as a command line: `name=bob` is `--name bob`, an empty
/// value is a flag (`video=` is `--video`), a repeated key repeats.
/// calls_browser.sh builds the query from the Linux app's arguments.
List<String> labArguments(List<String> args) => [
  for (final e in Uri.base.queryParametersAll.entries)
    for (final v in e.value) ...['--${e.key}', if (v.isNotEmpty) v],
];

/// The run's log: each line posted to the helper in order, and printed to
/// the console as well.
LabSink openLabSink(String out) => _PostSink();

/// Keys for this run only: a fresh storage key and identity, the key store
/// in the browser's own storage (IndexedDB) under a per-device name. The lab
/// starts Chrome on an empty profile each call, as the Linux phone starts on
/// an empty state directory.
Future<KeyStore> openLabKeyStore(String state, String name) async {
  final rng = Random.secure();
  return KeyStore.open(
    dbPath: 'tremulator-lab-$name',
    storageKey: Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256))),
    identity: await Identity.create(name),
  );
}

/// Waits until the helper says the stop sign exists.
Future<void> waitForStop(String untilFile, Report report) async {
  while ((await http.get(_helper.resolve('stop'))).statusCode != 200) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  report({'event': 'stop-sign', 'file': untilFile});
}

/// Hands [code] to the helper, which ends the browser.
void finishLab(int code) {
  unawaited(http.post(_helper.resolve('exit'), body: '$code'));
}

/// Where a lab run's events go.
abstract interface class LabSink {
  /// Records one event.
  void call(Map<String, Object?> event);

  /// Writes out what is pending; the run ends after.
  Future<void> close();
}

class _PostSink implements LabSink {
  // Posted one at a time, so the file keeps the order they happened in.
  Future<void> _last = Future.value();

  @override
  void call(Map<String, Object?> event) {
    final line = jsonEncode({
      't': DateTime.now().toUtc().toIso8601String(),
      ...event,
    });
    // ignore: avoid_print, the console is the log's second copy, read when the helper's is not there.
    print('TREMLAB $line');
    _last = _last.then(
      (_) => http.post(_helper.resolve('log'), body: line).then((_) {}),
      onError: (_) {},
    );
  }

  @override
  Future<void> close() => _last;
}

/// Marks the lab's picture as moving video (W3C MediaStreamTrack Content
/// Hints, WD 2025-09-19, section 4.3: "motion" makes the sender keep the
/// frame rate). The lab's screen stands in for a camera. Chrome otherwise
/// kept full resolution at 1-2 frames a second on P2 (calls47ba: 148 frames
/// decoded in 120 s, "bandwidth" limited at 1280 wide).
void markAsCamera(MediaStreamTrack track) {
  (track as MediaStreamTrackWeb).jsTrack.contentHint = 'motion';
}
