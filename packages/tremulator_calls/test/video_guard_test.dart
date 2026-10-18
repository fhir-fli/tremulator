import 'package:flutter_test/flutter_test.dart';
import 'package:tremulator_calls/tremulator_calls.dart';

final _t0 = DateTime.utc(2026, 10, 18);

/// Feeds [rtts] one second apart from [start]; returns each change with the
/// second it happened.
List<(int, bool)> _feed(VideoGuard g, List<double> rtts, {int start = 0}) => [
  for (var i = 0; i < rtts.length; i++)
    if (g.sample(_t0.add(Duration(seconds: start + i)), rtts[i])
        case final bool change)
      (start + i, change),
];

void main() {
  test('a link within 10% of its own round trip never stops video (P2, P3 '
      'in calls8)', () {
    final g = VideoGuard();
    // P3 relayed: 1.409-1.443 s; with a low of 1.40, never weak.
    final rtts = [for (var i = 0; i < 600; i++) 1.40 + (i % 5) * 0.01];
    expect(_feed(g, rtts), isEmpty);
    expect(g.sending, isTrue);
  });

  test('a queue building on P1 stops video after five weak samples', () {
    final g = VideoGuard();
    // calls8 P1: 0.44 s at first, then the queue: 3.8, 8.6 s and up.
    final changes = _feed(g, [0.44, 0.45, 3.8, 5.0, 8.6, 9.0, 10.0, 12.0]);
    expect(changes, [(6, false)]);
    expect(g.sending, isFalse);
  });

  test('a single slow sample is not a weak link', () {
    final g = VideoGuard();
    expect(_feed(g, [0.4, 0.4, 3.0, 0.4, 3.0, 0.4, 3.0, 3.0, 3.0, 3.0, 3]), [
      (10, false),
    ]);
  });

  test('both thresholds must be passed: twice a tiny round trip is not '
      'weak', () {
    final g = VideoGuard();
    // 5 ms to 50 ms is ten times, but only 45 ms more.
    expect(_feed(g, [0.005, ...List.filled(20, 0.05)]), isEmpty);
  });

  test('video comes back after the hold with no weak sample, and stays if '
      'the link holds', () {
    final g = VideoGuard();
    expect(_feed(g, [0.4, ...List<double>.filled(5, 9)]), [(5, false)]);
    // The queue drains over 10 s (still weak), then the link is good: the
    // 30 s hold runs from the last weak sample (second 15).
    final changes = _feed(g, [
      ...List<double>.filled(10, 9),
      ...List.filled(40, 0.4),
    ], start: 6);
    expect(changes, [(45, true)]);
    expect(g.sending, isTrue);
    // 20 s good after that resets the hold.
    _feed(g, List.filled(25, 0.4), start: 56);
    expect(g.hold, const Duration(seconds: 30));
  });

  test('a failed try doubles the hold, up to the cap', () {
    final g = VideoGuard();
    var second = 0;
    List<(int, bool)> run(List<double> r) {
      final c = _feed(g, r, start: second);
      second += r.length;
      return c;
    }

    run([0.4, ...List<double>.filled(5, 9)]);
    for (final want in [60, 120, 240, 240]) {
      // Good until video returns, then weak again at once.
      final back = run(List.filled(g.hold.inSeconds + 1, 0.4));
      expect(back.single.$2, isTrue);
      final off = run(List<double>.filled(5, 9));
      expect(off.single.$2, isFalse);
      expect(g.hold, Duration(seconds: want));
    }
  });

  test('a new route forgets the old round trip', () {
    final g = VideoGuard();
    _feed(g, [0.05, 0.05]);
    g.newRoute();
    // Relayed now at 1.4 s: not weak against the old 0.05.
    expect(_feed(g, List.filled(10, 1.4), start: 2), isEmpty);
  });
}
