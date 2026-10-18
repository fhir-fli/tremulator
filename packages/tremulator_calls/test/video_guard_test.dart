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
  test('a call starts with sound only and sends video after 10 quiet '
      'seconds', () {
    final g = VideoGuard();
    expect(g.sending, isFalse);
    // A slow sample restarts the quiet time; quiet from second 3 on.
    expect(_feed(g, [0.4, 0.4, 1.5, ...List.filled(12, 0.4)]), [(13, true)]);
    expect(g.sending, isTrue);
  });

  test('a call that starts on a weak link keeps video off and says so', () {
    final g = VideoGuard();
    // calls19a P1: the round trip climbs from the start.
    expect(_feed(g, [0.45, 1.2, 2.0, 3.1, 4.0, 5.2]), [(5, false)]);
    expect(g.sending, isFalse);
    // Then it waits for a tap, however good the link becomes.
    expect(_feed(g, List.filled(300, 0.45), start: 6), isEmpty);
    expect(g.retry(), isTrue);
    expect(g.sending, isTrue);
  });

  test('a link within 10% of its own round trip never stops video (P2, P3 '
      'in calls8)', () {
    final g = VideoGuard(startSending: true);
    // P3 relayed: 1.409-1.443 s; with a low of 1.40, never weak.
    final rtts = [for (var i = 0; i < 600; i++) 1.40 + (i % 5) * 0.01];
    expect(_feed(g, rtts), isEmpty);
    expect(g.sending, isTrue);
  });

  test('a queue building on P1 stops video after five weak samples', () {
    final g = VideoGuard(startSending: true);
    // calls8 P1: 0.44 s at first, then the queue: 3.8, 8.6 s and up.
    final changes = _feed(g, [0.44, 0.45, 3.8, 5.0, 8.6, 9.0, 10.0, 12.0]);
    expect(changes, [(6, false)]);
    expect(g.sending, isFalse);
  });

  test('a single slow sample is not a weak link', () {
    final g = VideoGuard(startSending: true);
    expect(_feed(g, [0.4, 0.4, 3.0, 0.4, 3.0, 0.4, 3.0, 3.0, 3.0, 3.0, 3]), [
      (10, false),
    ]);
  });

  test('both thresholds must be passed: twice a tiny round trip is not '
      'weak', () {
    final g = VideoGuard(startSending: true);
    // 5 ms to 50 ms is ten times, but only 45 ms more.
    expect(_feed(g, [0.005, ...List.filled(20, 0.05)]), isEmpty);
  });

  test('stopped video stays off on a good link until the person taps', () {
    final g = VideoGuard(startSending: true);
    expect(_feed(g, [0.4, ...List<double>.filled(5, 9)]), [(5, false)]);
    // The queue drains, then five minutes of a good link: nothing.
    expect(
      _feed(g, [
        ...List<double>.filled(10, 9),
        ...List.filled(300, 0.4),
      ], start: 6),
      isEmpty,
    );
    expect(g.sending, isFalse);
    expect(g.retry(), isTrue);
    expect(g.sending, isTrue);
    expect(_feed(g, List.filled(60, 0.4), start: 316), isEmpty);
  });

  test('a tap on a link still weak stops video again after five weak '
      'samples, and it waits for the next tap', () {
    final g = VideoGuard(startSending: true);
    _feed(g, [0.4, ...List<double>.filled(5, 9)]);
    expect(g.retry(), isTrue);
    expect(_feed(g, List<double>.filled(5, 9), start: 6), [(10, false)]);
    expect(_feed(g, List.filled(300, 0.4), start: 11), isEmpty);
    expect(g.sending, isFalse);
  });

  test('a tap while video is on changes nothing', () {
    final g = VideoGuard(startSending: true);
    expect(g.retry(), isFalse);
    expect(g.sending, isTrue);
  });

  test('a reconnect on the same route keeps the lowest round trip, so a '
      'queue still full after it is still weak', () {
    final g = VideoGuard(startSending: true)..onRoute('host→relay');
    expect(_feed(g, [0.8, ...List<double>.filled(5, 25)]), [(5, false)]);
    g.onRoute('host→relay');
    // calls18 P1-blocked: 30 s, then 37 s after the reconnect.
    expect(
      _feed(g, [30, ...List<double>.filled(60, 37)], start: 6),
      isEmpty,
    );
    expect(g.sending, isFalse);
  });

  test('a new route forgets the old round trip', () {
    final g = VideoGuard(startSending: true)..onRoute('host→host');
    _feed(g, [0.05, 0.05]);
    g.onRoute('host→relay');
    // Relayed now at 1.4 s: not weak against the old 0.05.
    expect(_feed(g, List.filled(10, 1.4), start: 2), isEmpty);
  });
}
