/// Decides when a phone stops sending its video because the link cannot
/// carry it, and when it tries again (E7, docs/GATE2-CALLS-PLAN.md; Gate 5
/// in docs/SUCCESS.md: "when bandwidth falls below the floor, the call drops
/// to audio and says so, rather than freezing").
///
/// The signal is the round trip of the connected pair, measured by the
/// connection's own checks, which wait in the same queue as the media. A link
/// that cannot carry what is sent queues it, and the round trip grows past
/// the link's own. calls8 (video on, 3 minutes per profile): on P1 (50 kbit/s)
/// the round trip ran 8.6-26 s (10th to 90th percentile) against the
/// profile's 0.4 s; on P2 and P3, direct and relayed, it stayed within 10% of
/// the profile's own. WebRTC's bandwidth estimate could not serve: on P1 it
/// stayed at 84.4 kbit/s throughout.
///
/// The thresholds and times are choices, not measurements; the lab runs of
/// E7 test them.
class VideoGuard {
  /// A guard with its thresholds.
  VideoGuard({
    this.weakSamples = 5,
    this.ratio = 2,
    this.margin = const Duration(milliseconds: 500),
    this.firstHold = const Duration(seconds: 30),
    this.maxHold = const Duration(seconds: 240),
    this.probe = const Duration(seconds: 20),
  });

  /// How many weak samples in a row stop the video.
  final int weakSamples;

  /// A sample is weak when its round trip is over [ratio] times the lowest
  /// seen and over the lowest plus [margin].
  final double ratio;

  /// See [ratio].
  final Duration margin;

  /// How long the video stays off, with no weak sample, before it is tried
  /// again; doubled each time a try fails, up to [maxHold].
  final Duration firstHold;

  /// See [firstHold].
  final Duration maxHold;

  /// How long video sent again must go without stopping for the try to count
  /// as good, which resets the hold to [firstHold].
  final Duration probe;

  double? _lowest;
  int _weak = 0;
  bool _sending = true;
  late DateTime _offSince;
  DateTime? _onSince;
  late Duration _hold = firstHold;

  /// Whether video should be sent now.
  bool get sending => _sending;

  /// How long the video will stay off once stopped, as things stand.
  Duration get hold => _hold;

  /// Forgets the lowest round trip: the route changed (a reconnect), so the
  /// old one no longer describes the link.
  void newRoute() {
    _lowest = null;
    _weak = 0;
  }

  /// One round trip of [seconds], measured at [now]. Returns the new state
  /// when it changes (false: stop the video; true: send it again), else
  /// null.
  bool? sample(DateTime now, double seconds) {
    final lowest = _lowest = _lowest == null || seconds < _lowest!
        ? seconds
        : _lowest!;
    final weak =
        seconds > lowest * ratio &&
        seconds > lowest + margin.inMicroseconds / 1e6;
    _weak = weak ? _weak + 1 : 0;
    if (_sending) {
      final on = _onSince;
      if (on != null && now.difference(on) >= probe) {
        _hold = firstHold;
        _onSince = null;
      }
      if (_weak >= weakSamples) {
        if (_onSince != null) {
          // Tried again and the link could not carry it: wait longer.
          final doubled = _hold * 2;
          _hold = doubled > maxHold ? maxHold : doubled;
        }
        _sending = false;
        _offSince = now;
        _onSince = null;
        _weak = 0;
        return false;
      }
      return null;
    }
    if (weak) {
      _offSince = now;
      return null;
    }
    if (now.difference(_offSince) >= _hold) {
      _sending = true;
      _onSince = now;
      _weak = 0;
      return true;
    }
    return null;
  }
}
