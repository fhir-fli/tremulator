import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tremulator_calls/src/signal.dart';
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
    Report? report,
    @visibleForTesting this.alterRemoteSdp,
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

  /// Where events go.
  final Report report;

  /// Changes the other side's session description before it is used. Only
  /// for tests that play a dishonest relay of the setup.
  final String Function(String sdp)? alterRemoteSdp;

  late final StreamSubscription<Incoming> _subscription;
  final Map<String, Call> _calls = {};
  final StreamController<Call> _ringing = StreamController.broadcast();

  /// Calls arriving, not yet answered.
  Stream<Call> get ringing => _ringing.stream;

  /// Calls the other members of [conversation], sending [media] if given.
  /// With no media the call carries only its control channel.
  Future<Call> start(Conversation conversation, {MediaStream? media}) async {
    final call = Call._(this, conversation, _newId(), outgoing: true);
    _calls[call.id] = call;
    report({'event': 'call-started', 'call': call.id});
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
        await known._remote(RTCSessionDescription(s.sdp, 'answer'));
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
  }) : _remoteOffer = remoteOffer;

  final Calls _calls;

  /// The conversation whose members are called.
  final Conversation conversation;

  /// The call id.
  final String id;

  /// True if this phone placed the call.
  final bool outgoing;

  RTCPeerConnection? _pc;
  RTCDataChannel? _control;
  final String? _remoteOffer;
  bool _ended = false;
  final Completer<void> _connected = Completer();
  final StreamController<MediaStream> _remoteMedia =
      StreamController.broadcast();

  /// Completes when media can flow; fails if the connection fails (a
  /// certificate that does not match the fingerprint in the setup ends here,
  /// RFC 8122 section 6.2) or the call ends first.
  Future<void> get connected => _connected.future;

  /// The other side's media, as it arrives.
  Stream<MediaStream> get remoteMedia => _remoteMedia.stream;

  /// The underlying connection, for statistics.
  RTCPeerConnection? get connection => _pc;

  /// Answers an incoming call, sending [media] if given.
  Future<void> answer({MediaStream? media}) async {
    final offer = _remoteOffer;
    if (outgoing || offer == null) {
      throw StateError('only a ringing incoming call can be answered');
    }
    await _open(media);
    await _remote(RTCSessionDescription(offer, 'offer'));
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
      ..onTrack = (e) {
        if (e.streams.isNotEmpty) {
          _remoteMedia.add(e.streams.first);
        }
      }
      ..onDataChannel = _adopt;
    if (media != null) {
      for (final t in media.getTracks()) {
        await pc.addTrack(t, media);
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
      if (m.text == 'hangup') {
        unawaited(_end('remote-hangup', tell: false));
      }
    };
  }

  Future<void> _offer() async {
    final offer = await _pc!.createOffer();
    await _sendDescription(offer, SignalType.offer);
  }

  /// Sets [description] locally, waits for this phone's addresses (or
  /// [Calls.gatherTimeout]), and sends the description with them in it.
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
    await _calls.client.sendCall(
      conversation,
      Signal(type: type, call: id, sdp: full!.sdp).encode(),
    );
    _calls.report({'event': '${type.name}-sent', 'call': id});
  }

  Future<void> _remote(RTCSessionDescription description) async {
    final alter = _calls.alterRemoteSdp;
    final sdp = alter == null ? description.sdp! : alter(description.sdp!);
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdp, description.type),
    );
  }

  void _onState(RTCPeerConnectionState s) {
    _calls.report({'event': 'call-state', 'call': id, 'state': s.name});
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        if (!_connected.isCompleted) {
          _connected.complete();
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        if (!_connected.isCompleted) {
          _connected.completeError(StateError('connection failed'));
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        break;
    }
  }

  Future<void> _end(String why, {required bool tell}) async {
    if (_ended) {
      return;
    }
    _ended = true;
    _calls._calls.remove(id);
    _calls.report({'event': 'call-ended', 'call': id, 'why': why});
    if (tell) {
      final control = _control;
      if (control?.state == RTCDataChannelState.RTCDataChannelOpen) {
        await control!.send(RTCDataChannelMessage('hangup'));
      }
      // Through the mailbox as well, in case the control channel never
      // opened or the link drops the message.
      await _calls.client.sendCall(
        conversation,
        Signal(type: SignalType.hangup, call: id).encode(),
      );
    }
    if (!_connected.isCompleted) {
      _connected.completeError(StateError('call ended: $why'));
    }
    await _pc?.close();
    await _remoteMedia.close();
  }
}
