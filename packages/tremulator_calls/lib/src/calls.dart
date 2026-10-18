import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tremulator_calls/src/opus.dart';
import 'package:tremulator_calls/src/signal.dart';
import 'package:tremulator_calls/src/video_guard.dart';
import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_keys/tremulator_keys.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

/// How the media of a connected call travels.
class Route {
  /// The two ends of the connected pair, by ICE candidate type (RFC 8445
  /// section 5.1.1: host, srflx, prflx, relay).
  const Route({required this.local, required this.remote});

  /// This phone's end.
  final String local;

  /// The other phone's end.
  final String remote;

  /// True when either end is a relay (TURN) address.
  bool get relayed => local == 'relay' || remote == 'relay';

  @override
  String toString() => '$local→$remote';
}

/// Starts and answers calls for one [Client].
class Calls {
  /// Calls over [client]. [iceServers] are STUN and TURN servers in the
  /// WebRTC configuration shape (`{'urls': ..., 'username': ...,
  /// 'credential': ...}`).
  Calls(
    this.client, {
    this.iceServers = const [],
    this.gatherTimeout = const Duration(seconds: 5),
    this.reconnectGrace = const Duration(seconds: 90),
    this.restartDelay = const Duration(seconds: 2),
    this.restartRetry = const Duration(seconds: 30),
    this.setupDeadline = const Duration(seconds: 90),
    this.sendRetry = const Duration(seconds: 2),
    this.opus = const OpusReceive(),
    this.videoGuard = VideoGuard.new,
    this.guardEvery = const Duration(seconds: 1),
    Report? report,
    @visibleForTesting this.alterRemoteSdp,
    @visibleForTesting this.roundTrip,
  }) : report = report ?? client.report {
    _subscription = client.incoming
        .where((m) => m.label == Label.call)
        .listen(_onSignal);
  }

  /// The client the setup travels through.
  final Client client;

  /// STUN and TURN servers.
  final List<Map<String, Object?>> iceServers;

  /// How long to wait for this phone's own addresses before sending what it
  /// has.
  final Duration gatherTimeout;

  /// How long a connected call that has lost its link keeps trying to
  /// reconnect before both phones end it as `lost`. 90 s outlasts the
  /// longest outage in the lab's network profiles (P4: 60 s of no link,
  /// docs/SUCCESS.md).
  final Duration reconnectGrace;

  /// How long the link must stay "disconnected" before the caller restarts
  /// the connection. Source, W3C WebRTC 1.0, the note under
  /// RTCOfferOptions.iceRestart (read whole from w3.org/TR/webrtc,
  /// 2026-10-17): a restart "is recommended when iceConnectionState
  /// transitions to failed", and an application "may additionally choose to
  /// listen for the iceConnectionState transition to disconnected and then
  /// use other sources of information" to decide. Still disconnected after
  /// this long is that information.
  final Duration restartDelay;

  /// How long the caller waits for a restart to reconnect before sending
  /// another. Long enough for an offer and an answer to cross the mailbox on
  /// the slowest profile (call setup took 23.7 s on P1 relayed, calls8).
  final Duration restartRetry;

  /// How long a call that has never connected keeps trying, from when this
  /// phone placed or answered it, before it ends as `failed` on both
  /// phones. 90 s, as [reconnectGrace]: it outlasts P4's 60 s outage, so a
  /// call placed just before one still connects (calls11 P4: placed, then
  /// the link went, and setup was never retried). It runs from the start of
  /// setup, so time spent ringing on a phone a person must answer counts
  /// against it; the lab's callee answers at once.
  final Duration setupDeadline;

  /// How long after a failed send of an offer or answer it is sent again,
  /// until it gets through, the call ends, or a newer one replaces it.
  /// The value is a choice, unmeasured: a failed request costs one more
  /// request. A repeat is harmless: the number on it marks it as one
  /// already seen.
  final Duration sendRetry;

  /// How this phone asks the other to send its sound, put into every offer
  /// and answer this phone sends.
  final OpusReceive opus;

  /// Makes the guard that stops this phone's video when the link cannot
  /// carry it (one per call); null sends video whatever the link.
  final VideoGuard Function()? videoGuard;

  /// How often a connected call sending video reads its round trip for the
  /// guard.
  final Duration guardEvery;

  /// Where events go.
  final Report report;

  /// Changes the other side's session description before it is used. Only
  /// for tests that play a dishonest relay of the setup.
  final String Function(String sdp)? alterRemoteSdp;

  /// Replaces the round trip read from the call's statistics, in seconds.
  /// Only for tests that play a slow link.
  final Future<double?> Function(Call call)? roundTrip;

  late final StreamSubscription<Incoming> _subscription;
  final Map<String, Call> _calls = {};
  final Set<Future<void>> _ending = {};
  final StreamController<Call> _ringing = StreamController.broadcast();

  /// Calls arriving, not yet answered.
  Stream<Call> get ringing => _ringing.stream;

  /// Calls the other members of [conversation], sending [media] if given.
  /// With no media the call carries only its control channel.
  Future<Call> start(Conversation conversation, {MediaStream? media}) async {
    final call = Call._(this, conversation, _newId(), outgoing: true);
    _calls[call.id] = call;
    report({'event': 'call-started', 'call': call.id});
    call._startSetupClock();
    await call._open(media);
    await call._offer();
    return call;
  }

  /// Stops listening and ends every call.
  Future<void> close() async {
    await _subscription.cancel();
    for (final c in _calls.values.toList()) {
      await c.hangUp();
    }
    // Calls ended by a timer (`lost`) may still be sending their hang-up.
    await Future.wait(_ending.toList());
    await _ringing.close();
  }

  Future<void> _onSignal(Incoming m) async {
    final Signal s;
    try {
      s = Signal.decode(m.text);
    } on FormatException catch (e) {
      report({'event': 'bad-signal', 'error': e.message});
      return;
    }
    report({'event': 'signal-received', 'call': s.call, 'type': s.type.name});
    final known = _calls[s.call];
    switch (s.type) {
      case SignalType.offer:
        if (known != null) {
          // A repeat of an offer already seen, or a restart of a call this
          // phone has: never a new ring.
          if (!known.outgoing) {
            await known._serial(() => known._restartOffer(s.sdp!, s.number!));
          }
          return;
        }
        if (s.number != 0) {
          // A restart for a call this phone does not have (ended, or never
          // rang here) must not ring as a new call.
          report({'event': 'restart-ignored', 'call': s.call, 'n': s.number});
          return;
        }
        final call = Call._(
          this,
          client.keys.conversation(m.conversation),
          s.call,
          outgoing: false,
          remoteOffer: s.sdp,
        );
        _calls[call.id] = call;
        _ringing.add(call);
      case SignalType.answer:
        if (known == null || !known.outgoing) {
          return;
        }
        await known._serial(() => known._answer(s.sdp!, s.number!));
      case SignalType.hangup:
        await known?._end('remote-hangup', tell: false);
    }
  }

  static String _newId() {
    final rng = Random.secure();
    return List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

/// One call, outgoing or incoming.
class Call {
  Call._(
    this._calls,
    this.conversation,
    this.id, {
    required this.outgoing,
    String? remoteOffer,
  }) : _remoteOffer = remoteOffer {
    // A call can end before it connects (hung up while ringing) with no one
    // waiting on [connected]; its failure must not then surface as an
    // unhandled error. Whoever does wait on it still gets the error.
    _connected.future.ignore();
  }

  final Calls _calls;

  /// The conversation whose members are called.
  final Conversation conversation;

  /// The call id.
  final String id;

  /// True if this phone placed the call.
  final bool outgoing;

  RTCPeerConnection? _pc;
  RTCDataChannel? _control;

  /// The offer a ringing call will answer: the first, or a restart that
  /// replaced it before this phone answered.
  String? _remoteOffer;
  final Completer<void> _connected = Completer();
  Timer? _setupTimer;
  RTCIceConnectionState? _ice;

  /// The caller's latest offer number; the callee's latest answered one.
  int _number = 0;

  /// The number of the offer whose answer the caller has applied.
  int _answered = -1;

  /// The other phone's certificate fingerprints, from its first
  /// description; every later description must carry the same.
  String? _remoteFingerprints;

  /// Set while a call that had connected has lost its link.
  DateTime? _lostAt;
  Timer? _grace;
  Timer? _restartTimer;
  Completer<void>? _back;
  Future<void> _queue = Future.value();
  final Completer<String> _ended = Completer();
  final StreamController<MediaStream> _remoteMedia =
      StreamController.broadcast();
  final StreamController<VideoChange> _video = StreamController.broadcast();
  VideoGuard? _guard;
  Timer? _guardTimer;

  /// This phone's video senders and the track each sends while video is on.
  final Map<RTCRtpSender, MediaStreamTrack> _videoSenders = {};
  bool _guardBusy = false;

  /// Video stops and starts, one after another: a tap can land while the
  /// guard's own change is still replacing tracks.
  Future<void> _videoSends = Future.value();

  /// Completes when media can flow; fails if the connection fails (a
  /// certificate that does not match the fingerprint in the setup ends here,
  /// RFC 8122 section 6.2) or the call ends first.
  Future<void> get connected => _connected.future;

  /// Completes with why the call ended: `hangup` (this phone),
  /// `remote-hangup`, `failed` (it never connected: the other phone's
  /// certificate did not match its fingerprint, or [Calls.setupDeadline]
  /// passed), `lost`
  /// (it connected, lost its link and did not reconnect within
  /// [Calls.reconnectGrace]) or `fingerprint-changed` (a later description
  /// carried a different certificate fingerprint from the first).
  Future<String> get ended => _ended.future;

  /// The other side's media, as it arrives.
  Stream<MediaStream> get remoteMedia => _remoteMedia.stream;

  /// This phone's video stopping when the link cannot carry it
  /// ([VideoGuard]) and starting again on a tap ([retryVideo]), and the
  /// other phone's, as it reports them over the
  /// control channel. The screen says so from these (Gate 5: "drops to
  /// audio and says so").
  Stream<VideoChange> get video => _video.stream;

  /// Sends this phone's video again after the guard stopped it, because the
  /// person tapped to try again. Video never comes back on its own
  /// ([VideoGuard]). Does nothing if video is already sent, or this phone
  /// sends none.
  Future<void> retryVideo() async {
    final guard = _guard;
    if (guard == null || _ended.isCompleted || !guard.retry()) {
      return;
    }
    await _sendVideo(true, null, 'tap');
  }

  /// The underlying connection, for statistics.
  RTCPeerConnection? get connection => _pc;

  /// Answers an incoming call, sending [media] if given.
  Future<void> answer({MediaStream? media}) async {
    final offer = _remoteOffer;
    if (outgoing || offer == null) {
      throw StateError('only a ringing incoming call can be answered');
    }
    _startSetupClock();
    await _open(media);
    if (!await _remote(RTCSessionDescription(offer, 'offer'))) {
      return;
    }
    final answer = await _pc!.createAnswer();
    await _sendDescription(answer, SignalType.answer);
  }

  /// The connection's statistics (W3C webrtc-stats).
  Future<List<StatsReport>> stats() async => await _pc?.getStats() ?? [];

  /// The connected candidate pair, or null before connection.
  Future<Route?> route() async {
    final reports = await stats();
    final byId = {for (final r in reports) r.id: r};
    String? pairId;
    for (final r in reports) {
      if (r.type == 'transport') {
        pairId = r.values['selectedCandidatePairId'] as String?;
      }
    }
    var pair = pairId == null ? null : byId[pairId];
    pair ??= reports
        .where(
          (r) =>
              r.type == 'candidate-pair' &&
              r.values['state'] == 'succeeded' &&
              r.values['nominated'] == true,
        )
        .firstOrNull;
    if (pair == null) {
      return null;
    }
    final local = byId[pair.values['localCandidateId']];
    final remote = byId[pair.values['remoteCandidateId']];
    if (local == null || remote == null) {
      return null;
    }
    return Route(
      local: '${local.values['candidateType']}',
      remote: '${remote.values['candidateType']}',
    );
  }

  /// Ends the call and tells the other side.
  Future<void> hangUp() => _end('hangup', tell: true);

  Future<void> _open(MediaStream? media) async {
    final pc = await createPeerConnection({
      'iceServers': _calls.iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;
    pc
      ..onConnectionState = _onState
      ..onIceConnectionState = (s) {
        _ice = s;
        _calls.report({'event': 'ice-state', 'call': id, 'state': s.name});
      }
      ..onTrack = (e) {
        if (e.streams.isNotEmpty) {
          _remoteMedia.add(e.streams.first);
        }
      }
      ..onDataChannel = _adopt;
    if (media != null) {
      final guarded = _calls.videoGuard != null;
      for (final t in media.getTracks()) {
        final sender = await pc.addTrack(t, media);
        if (guarded && t.kind == 'video') {
          // Sound first: the video track is held back until the guard
          // starts it (VideoGuard.startSending). The sender, and the video
          // in the offer or answer, stay.
          _videoSenders[sender] = t;
          await sender.replaceTrack(null);
        }
      }
    }
    if (outgoing) {
      // The caller opens the control channel: it makes a media-less call
      // possible and carries the hang-up straight to the other phone.
      _adopt(await pc.createDataChannel('control', RTCDataChannelInit()));
    }
  }

  void _adopt(RTCDataChannel channel) {
    _control = channel;
    channel.onMessage = (m) {
      switch (m.text) {
        case 'hangup':
          unawaited(_end('remote-hangup', tell: false));
        case 'video-off' || 'video-on':
          final sending = m.text == 'video-on';
          _calls.report({
            'event': 'remote-video',
            'call': id,
            'sending': sending,
          });
          if (!_video.isClosed) {
            _video.add(VideoChange(local: false, sending: sending));
          }
      }
    };
  }

  Future<void> _offer() async {
    final offer = await _pc!.createOffer();
    await _sendDescription(offer, SignalType.offer);
  }

  /// Ends the call as `failed` on both phones if it has not connected
  /// within [Calls.setupDeadline].
  void _startSetupClock() {
    _setupTimer = Timer(_calls.setupDeadline, () {
      if (!_connected.isCompleted) {
        _calls.report({'event': 'setup-deadline', 'call': id});
        unawaited(_end('failed', tell: true));
      }
    });
  }

  /// Sets [description] locally, waits for this phone's addresses (or
  /// [Calls.gatherTimeout]), and starts sending the description with them
  /// in it (see [_deliver]); returns before it has got through.
  Future<void> _sendDescription(
    RTCSessionDescription description,
    SignalType type,
  ) async {
    final pc = _pc!;
    final gathered = Completer<void>();
    pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !gathered.isCompleted) {
        gathered.complete();
      }
    };
    await pc.setLocalDescription(description);
    final started = DateTime.now();
    var timedOut = false;
    await gathered.future.timeout(
      _calls.gatherTimeout,
      onTimeout: () => timedOut = true,
    );
    final full = await pc.getLocalDescription();
    _calls.report({
      'event': 'gathered',
      'call': id,
      'ms': DateTime.now().difference(started).inMilliseconds,
      'timed-out': timedOut,
    });
    unawaited(_deliver(type, _calls.opus.applyTo(full!.sdp!), _number));
  }

  /// Sends an offer or answer through the mailbox, again every
  /// [Calls.sendRetry] while the send fails (the link is down, and with it
  /// the mailbox), until it gets through, the call ends, or a newer number
  /// replaces it. calls11 P4: the answer's one send fell in the outage and
  /// the call never connected.
  Future<void> _deliver(SignalType type, String sdp, int number) async {
    final text = Signal(
      type: type,
      call: id,
      sdp: sdp,
      number: number,
    ).encode();
    for (var attempt = 1; ; attempt++) {
      if (_ended.isCompleted || number != _number) {
        return;
      }
      try {
        await _calls.client.sendCall(conversation, text);
        _calls.report({
          'event': '${type.name}-sent',
          'call': id,
          'n': number,
          'attempt': attempt,
        });
        return;
      } on Object catch (e) {
        // A send can time out here yet reach the server (calls11 P1); the
        // repeat is then a duplicate, which the number marks.
        _calls.report({
          'event': 'send-failed',
          'call': id,
          'type': type.name,
          'n': number,
          'attempt': attempt,
          'error': '$e',
        });
      }
      await Future<void>.delayed(_calls.sendRetry);
    }
  }

  /// Applies the other phone's [description]. Returns false, having ended
  /// the call, if its certificate fingerprints differ from the first
  /// description's. A restart replaces only the ICE credentials (the
  /// restartIce() steps, W3C WebRTC 1.0, read whole 2026-10-17), so the
  /// same phone sends the same fingerprint; a new one means a different
  /// certificate answering.
  Future<bool> _remote(RTCSessionDescription description) async {
    final alter = _calls.alterRemoteSdp;
    final sdp = alter == null ? description.sdp! : alter(description.sdp!);
    final fingerprints = _fingerprints(sdp);
    _remoteFingerprints ??= fingerprints;
    if (fingerprints != _remoteFingerprints) {
      _calls.report({'event': 'fingerprint-changed', 'call': id});
      await _end('fingerprint-changed', tell: true);
      return false;
    }
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdp, description.type),
    );
    return true;
  }

  static String _fingerprints(String sdp) {
    final lines = [
      for (final l in sdp.split(RegExp(r'\r?\n')))
        if (l.toLowerCase().startsWith('a=fingerprint:')) l.trim(),
    ]..sort();
    return lines.join('\n');
  }

  /// Runs [step] after every earlier one for this call, so two setup
  /// messages arriving together are applied in order.
  Future<void> _serial(Future<void> Function() step) {
    final next = _queue.then((_) => _ended.isCompleted ? null : step());
    return _queue = next.catchError((Object e) {
      _calls.report({'event': 'setup-failed', 'call': id, 'error': '$e'});
    });
  }

  /// The caller: applies the answer to its latest offer, ignoring any
  /// answer to an offer since replaced.
  Future<void> _answer(String sdp, int number) async {
    if (number != _number || number == _answered) {
      _calls.report({'event': 'answer-ignored', 'call': id, 'n': number});
      return;
    }
    if (await _remote(RTCSessionDescription(sdp, 'answer'))) {
      _answered = number;
      _calls.report({'event': 'answer-applied', 'call': id, 'n': number});
      // A restart applied while the transport still works brings no state
      // change, so no "connected" event would end the grace period.
      if (_pc?.connectionState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _reconnected();
      }
    }
  }

  /// The callee: answers a restart offer newer than any it has answered.
  /// Before this phone has answered, a newer offer replaces the one it will
  /// answer.
  Future<void> _restartOffer(String sdp, int number) async {
    if (number <= _number) {
      _calls.report({'event': 'offer-ignored', 'call': id, 'n': number});
      return;
    }
    if (_pc == null) {
      _remoteOffer = sdp;
      _number = number;
      _calls.report({'event': 'offer-replaced', 'call': id, 'n': number});
      return;
    }
    _number = number;
    if (!await _remote(RTCSessionDescription(sdp, 'offer'))) {
      return;
    }
    await _sendDescription(await _pc!.createAnswer(), SignalType.answer);
    if (_pc?.connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _reconnected();
    }
  }

  /// The link is gone: the caller restarts the connection, and a call
  /// that had connected starts the grace period on both phones (one that
  /// never connected is bounded by [Calls.setupDeadline] instead). Only the
  /// caller offers, so the two never offer at once.
  void _onLost(RTCPeerConnectionState s) {
    if (_lostAt != null || _ended.isCompleted) {
      return;
    }
    _lostAt = DateTime.now();
    _calls.report({
      'event': 'reconnecting',
      'call': id,
      'state': s.name,
      'ever-connected': _connected.isCompleted,
    });
    if (_connected.isCompleted) {
      _grace = Timer(_calls.reconnectGrace, () {
        unawaited(_end('lost', tell: true));
      });
    }
    if (outgoing) {
      unawaited(_restartLoop());
    }
  }

  /// The link is back: ends the grace period and the caller's restarts.
  void _reconnected() {
    final lostAt = _lostAt;
    if (lostAt == null) {
      return;
    }
    _lostAt = null;
    _grace?.cancel();
    unawaited(_routeToGuard());
    _calls.report({
      'event': 'reconnected',
      'call': id,
      'ms': DateTime.now().difference(lostAt).inMilliseconds,
      'control': _control?.state?.name,
    });
    if (_back?.isCompleted == false) {
      _back!.complete();
    }
  }

  /// Acts as if the link had just been lost, so a test on a working
  /// connection can drive a restart.
  @visibleForTesting
  void debugLinkLost() =>
      _onLost(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);

  Future<void> _restartLoop() async {
    var attempt = 0;
    while (_lostAt != null && !_ended.isCompleted) {
      attempt++;
      _number++;
      final back = _back = Completer<void>();
      try {
        // restartIce(), W3C WebRTC 1.0 (read whole 2026-10-17): "Subsequent
        // calls to createOffer will create descriptions that will restart
        // ICE".
        await _pc!.restartIce();
        _calls.report({
          'event': 'restart-sent',
          'call': id,
          'n': _number,
          'attempt': attempt,
        });
        await _sendDescription(await _pc!.createOffer(), SignalType.offer);
      } on Object catch (e) {
        // While the link is down the mailbox is out of reach as well.
        _calls.report({
          'event': 'restart-failed',
          'call': id,
          'n': _number,
          'error': '$e',
        });
      }
      if (_lostAt == null || _ended.isCompleted) {
        return;
      }
      await back.future.timeout(_calls.restartRetry, onTimeout: () {});
    }
  }

  void _onState(RTCPeerConnectionState s) {
    _calls.report({'event': 'call-state', 'call': id, 'state': s.name});
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _restartTimer?.cancel();
        _setupTimer?.cancel();
        if (!_connected.isCompleted) {
          _connected.complete();
          unawaited(_startGuard());
        }
        _reconnected();
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _restartTimer?.cancel();
        if (_connected.isCompleted) {
          _onLost(s);
        } else {
          unawaited(_failedBeforeConnecting(s));
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        if (_lostAt == null) {
          _restartTimer?.cancel();
          _restartTimer = Timer(_calls.restartDelay, () => _onLost(s));
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        break;
    }
  }

  /// A connection that never connected has failed. W3C WebRTC 1.0 (read
  /// whole 2026-10-17): a connection is "failed" when "either
  /// [[IceConnectionState]] is "failed" or any RTCDtlsTransports are in the
  /// "failed" state" (RTCPeerConnectionState), and a DTLS transport fails
  /// on "failure to validate the remote fingerprint" (RTCDtlsTransportState).
  /// So a failed DTLS transport is the other end's certificate (RFC 8122
  /// section 6.2) and ends the call at once; otherwise the route failed,
  /// and the call keeps trying until [Calls.setupDeadline].
  ///
  /// The DTLS state is read from the transport's statistics (`dtlsState`,
  /// required in RTCTransportStats, W3C webrtc-stats, read whole
  /// 2026-10-17), not from state events: with a refused certificate the
  /// plugin reported the connection failed while its last ICE event still
  /// said "checking" (calls_test, 2026-10-17). Unreadable statistics end
  /// the call as a refused certificate would.
  Future<void> _failedBeforeConnecting(RTCPeerConnectionState s) async {
    List<String>? dtls;
    try {
      dtls = [
        for (final r in await stats())
          if (r.type == 'transport') '${r.values['dtlsState']}',
      ];
    } on Object catch (e) {
      _calls.report({'event': 'stats-failed', 'call': id, 'error': '$e'});
    }
    final refused = dtls == null || dtls.isEmpty || dtls.contains('failed');
    _calls.report({
      'event': 'setup-failed',
      'call': id,
      'dtls': dtls,
      'ice': _ice?.name,
      'why': refused ? 'handshake' : 'route',
    });
    if (_ended.isCompleted || _connected.isCompleted) {
      return;
    }
    if (refused) {
      _connected.completeError(StateError('connection failed'));
      await _end('failed', tell: false);
    } else {
      _onLost(s);
    }
  }

  Future<void> _end(String why, {required bool tell}) async {
    if (_ended.isCompleted) {
      return;
    }
    _calls._calls.remove(id);
    _calls.report({'event': 'call-ended', 'call': id, 'why': why});
    _ended.complete(why);
    final done = Completer<void>();
    _calls._ending.add(done.future);
    try {
      await _finish(why, tell: tell);
    } finally {
      _calls._ending.remove(done.future);
      done.complete();
    }
  }

  /// Sends the hang-up through the mailbox as well, in case the control
  /// channel never opened or the link drops the message: again every
  /// [Calls.sendRetry] while the send fails, for up to
  /// [Calls.reconnectGrace], after which the other phone has ended the call
  /// as `lost` by itself. calls12 P4: the one send fell in an outage and Bob
  /// heard the hang-up 70 s late, as `lost`.
  Future<void> _deliverHangUp() async {
    final text = Signal(type: SignalType.hangup, call: id).encode();
    final until = DateTime.now().add(_calls.reconnectGrace);
    for (var attempt = 1; ; attempt++) {
      try {
        await _calls.client.sendCall(conversation, text);
        _calls.report({'event': 'hangup-sent', 'call': id, 'attempt': attempt});
        return;
      } on Object catch (e) {
        _calls.report({
          'event': 'hangup-not-sent',
          'call': id,
          'attempt': attempt,
          'error': '$e',
        });
      }
      if (DateTime.now().isAfter(until)) {
        return;
      }
      await Future<void>.delayed(_calls.sendRetry);
    }
  }

  Future<void> _finish(String why, {required bool tell}) async {
    _guardTimer?.cancel();
    _grace?.cancel();
    _restartTimer?.cancel();
    _setupTimer?.cancel();
    _lostAt = null;
    if (_back?.isCompleted == false) {
      _back!.complete();
    }
    if (tell) {
      try {
        final control = _control;
        if (control?.state == RTCDataChannelState.RTCDataChannelOpen) {
          await control!.send(RTCDataChannelMessage('hangup'));
        }
      } on Object catch (e) {
        _calls.report({'event': 'hangup-not-sent', 'call': id, 'error': '$e'});
      }
      await _deliverHangUp();
    }
    if (!_connected.isCompleted) {
      _connected.completeError(StateError('call ended: $why'));
    }
    try {
      await _pc?.close();
    } on Object catch (e) {
      // Already closed underneath the call (the plugin then has no
      // connection by this id); the call is over either way.
      _calls.report({'event': 'close-failed', 'call': id, 'error': '$e'});
    }
    await _remoteMedia.close();
    await _video.close();
  }

  /// Starts the [VideoGuard] if this phone sends video.
  Future<void> _startGuard() async {
    final make = _calls.videoGuard;
    final pc = _pc;
    if (make == null || pc == null || _ended.isCompleted) {
      return;
    }
    if (_videoSenders.isEmpty) {
      return;
    }
    final guard = _guard = make();
    if (guard.startSending) {
      await _sendVideo(true, null, 'start');
    }
    await _routeToGuard();
    _guardTimer = Timer.periodic(_calls.guardEvery, (_) async {
      if (_guardBusy || _ended.isCompleted || _lostAt != null) {
        return;
      }
      _guardBusy = true;
      try {
        final rtt = await (_calls.roundTrip?.call(this) ?? _roundTrip());
        if (rtt == null || _ended.isCompleted) {
          return;
        }
        final change = guard.sample(DateTime.now(), rtt);
        if (change != null) {
          await _sendVideo(change, rtt, 'guard');
        }
      } on Object catch (e) {
        _calls.report({
          'event': 'video-guard-failed',
          'call': id,
          'error': '$e',
        });
      } finally {
        _guardBusy = false;
      }
    });
  }

  /// Tells the guard which route the connection is on now.
  Future<void> _routeToGuard() async {
    final guard = _guard;
    if (guard == null) {
      return;
    }
    try {
      final r = await route();
      if (r != null) {
        guard.onRoute('$r');
      }
    } on Object catch (e) {
      _calls.report({'event': 'video-guard-failed', 'call': id, 'error': '$e'});
    }
  }

  /// The connected pair's current round trip in seconds (W3C webrtc-stats,
  /// RTCIceCandidatePairStats.currentRoundTripTime), or null if none yet.
  Future<double?> _roundTrip() async {
    final reports = await stats();
    final byId = {for (final r in reports) r.id: r};
    for (final r in reports) {
      if (r.type == 'transport') {
        final pair = byId[r.values['selectedCandidatePairId']];
        final rtt = pair?.values['currentRoundTripTime'];
        if (rtt is num) {
          return rtt.toDouble();
        }
      }
    }
    return null;
  }

  /// Stops or starts this phone's video, and tells the other phone.
  /// replaceTrack with no track: "If sending is true, and withTrack is null,
  /// have the sender stop sending" (W3C WebRTC 1.0, RTCRtpSender
  /// replaceTrack(), read 2026-10-18); the same sender is given its track
  /// back to start again, with no new offer or answer. Not
  /// RTCRtpEncodingParameters.active: flutter_webrtc 1.6.2+hotfix.4 on Linux
  /// accepts it and the encoding stays active (calls_test, 2026-10-18; its
  /// updateRtpParameters changes a copy of the encodings and never sets them
  /// back).
  ///
  /// [by] is who decided: `start`, `guard` or `tap`; [rtt] is the round trip
  /// the guard decided on, if it did.
  Future<void> _sendVideo(bool sending, double? rtt, String by) =>
      _videoSends = _videoSends.then((_) async {
        for (final MapEntry(key: sender, value: track)
            in _videoSenders.entries) {
          await sender.replaceTrack(sending ? track : null);
        }
        _calls.report({
          'event': 'video-sending',
          'call': id,
          'sending': sending,
          'by': by,
          'rtt': rtt,
        });
        if (!_video.isClosed) {
          _video.add(VideoChange(local: true, sending: sending));
        }
        final control = _control;
        if (control?.state == RTCDataChannelState.RTCDataChannelOpen) {
          await control!.send(
            RTCDataChannelMessage(sending ? 'video-on' : 'video-off'),
          );
        }
      });
}

/// Video stopped or started, on this phone ([local]) or the other.
class VideoChange {
  /// A change.
  const VideoChange({required this.local, required this.sending});

  /// True for this phone's own video, false for the other phone's.
  final bool local;

  /// Whether that video is being sent now.
  final bool sending;
}
