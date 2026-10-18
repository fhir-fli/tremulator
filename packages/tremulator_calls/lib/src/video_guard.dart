/// Decides when a phone stops sending its video because the link cannot
/// carry it (E7, docs/GATE2-CALLS-PLAN.md; Gate 5
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
/// A call starts with sound only, and video starts once the round trip has
/// stayed near its lowest for [startHold]: in calls18-19 the video sent
/// before the guard first stopped it (8-60 s) filled the link's queue, and
/// on P1 that queue took the whole 300 s call to drain, with the sound
/// waiting behind it (calls19a P1: round trip 15 s falling to 0.53 s).
///
/// Stopped video comes back only when the person taps to try again
/// ([retry]), never on its own (Grey, 2026-10-18). Each automatic try in
/// calls19-20 refilled the queue and slowed the voice for minutes: calls19b
/// P1, every try jammed the link within 9-10 s; calls20d, after the second
/// try, clicks took 2.7-2.8 s for two minutes on a 0.47 s round trip.
///
/// The thresholds and times are choices, not measurements; the lab runs of
/// E7 test them.
class VideoGuard {
  /// A guard with its thresholds.
  VideoGuard({
    this.weakSamples = 5,
    this.ratio = 2,
    this.margin = const Duration(milliseconds: 500),
    this.startHold = const Duration(seconds: 10),
    this.startSending = false,
  }) : _sending = startSending,
       _starting = !startSending;

  /// How many weak samples in a row stop the video.
  final int weakSamples;

  /// A sample is weak when its round trip is over [ratio] times the lowest
  /// seen and over the lowest plus [margin].
  final double ratio;

  /// See [ratio].
  final Duration margin;

  /// How long a call that starts with sound only waits, with no weak sample,
  /// before it first sends video.
  final Duration startHold;

  /// Whether video is sent from the start, as before calls20.
  final bool startSending;

  double? _lowest;
  int _weak = 0;
  bool _sending;
  bool _starting;
  DateTime? _quietSince;

  /// Whether video should be sent now.
  bool get sending => _sending;

  /// The person tapped to try video again. Returns true if video is to be
  /// sent now, false if it already was. The next weak samples stop it
  /// again, as before.
  bool retry() {
    if (_sending) {
      return false;
    }
    _starting = false;
    _sending = true;
    _weak = 0;
    return true;
  }

  String? _route;

  /// The connection is on [route] (local and remote candidate types) after
  /// connecting or reconnecting. A different route from before forgets the
  /// lowest round trip, which described the old one. The same route keeps
  /// it: after a reconnect the first round trips can still be a full queue,
  /// and taken as the lowest they made 37 s look normal (calls18 P1-blocked:
  /// video sent again at a 37 s round trip).
  void onRoute(String route) {
    if (_route != null && route != _route) {
      _lowest = null;
      _weak = 0;
    }
    _route = route;
  }

  /// One round trip of [seconds], measured at [now]. Returns the new state
  /// when it changes (false: stop the video; true: start it, once, at the
  /// start of a call), else null.
  bool? sample(DateTime now, double seconds) {
    final lowest = _lowest = _lowest == null || seconds < _lowest!
        ? seconds
        : _lowest!;
    final weak =
        seconds > lowest * ratio &&
        seconds > lowest + margin.inMicroseconds / 1e6;
    _weak = weak ? _weak + 1 : 0;
    if (_starting) {
      // Sound only so far, and nothing said: the link is either shown weak
      // (video stays off, and now it is said) or quiet long enough to try.
      if (_weak >= weakSamples) {
        _starting = false;
        _weak = 0;
        return false;
      }
      final quiet = _quietSince = weak ? null : (_quietSince ?? now);
      if (quiet != null && now.difference(quiet) >= startHold) {
        _starting = false;
        _sending = true;
        _weak = 0;
        return true;
      }
      return null;
    }
    if (_sending && _weak >= weakSamples) {
      _sending = false;
      _weak = 0;
      return false;
    }
    return null;
  }
}
