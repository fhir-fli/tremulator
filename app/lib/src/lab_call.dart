import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tremulator_calls/tremulator_calls.dart';
import 'package:tremulator_client/tremulator_client.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

/// What one lab run does. With `--peer` this phone calls; without, it
/// answers the first call that rings.
class LabOptions {
  const LabOptions._(this._a);

  /// Reads the command line.
  factory LabOptions.parse(List<String> argv) {
    final p = ArgParser()
      ..addFlag('lab')
      ..addOption('server', mandatory: true, help: 'http://host:port')
      ..addOption('name', mandatory: true, help: "this device's name")
      ..addOption('state', mandatory: true, help: 'directory for keys and db')
      ..addOption('out', mandatory: true, help: 'JSON lines log, appended')
      ..addOption('peer', help: 'call this device name')
      ..addOption('call-s', defaultsTo: '60', help: 'how long the call lasts')
      ..addFlag('video', help: 'send this screen as the picture')
      ..addFlag('audio', help: 'send the default microphone')
      ..addOption('turn', help: 'turn:host:port relay')
      ..addOption('turn-user', defaultsTo: 'lab')
      ..addOption('turn-pass', defaultsTo: 'lab')
      ..addOption('stats-ms', defaultsTo: '1000', help: 'between stats lines')
      ..addOption(
        'until-file',
        help: "the callee stays until this file exists (the lab's stop sign)",
      );
    return LabOptions._(p.parse(argv));
  }

  final ArgResults _a;

  String _s(String name) => _a[name] as String;

  /// The mailbox server.
  Uri get server => Uri.parse(_s('server'));

  /// This device's name.
  String get name => _s('name');

  /// Where keys and the key store live.
  String get state => _s('state');

  /// The log file.
  String get out => _s('out');

  /// Whom to call, or null to answer.
  String? get peer => _a['peer'] as String?;

  /// Call length.
  Duration get callLength => Duration(seconds: int.parse(_s('call-s')));

  /// Send a picture.
  bool get video => _a['video'] as bool;

  /// Send sound.
  bool get audio => _a['audio'] as bool;

  /// STUN and TURN servers for the call.
  List<Map<String, Object?>> get iceServers {
    final turn = _a['turn'] as String?;
    return [
      if (turn != null)
        {
          'urls': turn,
          'username': _s('turn-user'),
          'credential': _s('turn-pass'),
        },
    ];
  }

  /// Gap between stats lines.
  Duration get statsEvery => Duration(milliseconds: int.parse(_s('stats-ms')));

  /// The stop sign.
  String? get untilFile => _a['until-file'] as String?;
}

/// Runs one lab call and shows the other side's picture full window, so a
/// screen recording of this phone shows what arrived.
class LabCallApp extends StatefulWidget {
  /// A run with [options].
  const LabCallApp(this.options, {super.key});

  /// What to do.
  final LabOptions options;

  @override
  State<LabCallApp> createState() => _LabCallAppState();
}

class _LabCallAppState extends State<LabCallApp> {
  final RTCVideoRenderer _remote = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await _remote.initialize();
    setState(() => _ready = true);
    final log = LabLog(widget.options.out);
    try {
      await _run(widget.options, log, _remote);
      log({'event': 'done'});
      log.close();
      exit(0);
    } catch (e, st) {
      log({'event': 'run-failed', 'error': '$e', 'stack': '$st'});
      log.close();
      exit(2);
    }
  }

  @override
  // Dark grey, not black: a screenshot then tells this window from the bare
  // screen behind it, which is black.
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF303030),
    // RTCVideoView chooses texture or placeholder when it is built, so it is
    // rebuilt whenever the renderer changes (a stream set, a first frame).
    // Built once, it kept the placeholder for the whole call (calls1).
    child: _ready
        ? ValueListenableBuilder<RTCVideoValue>(
            valueListenable: _remote,
            builder: (_, _, _) => RTCVideoView(_remote),
          )
        : const SizedBox.expand(),
  );
}

Future<void> _run(LabOptions o, LabLog log, RTCVideoRenderer remote) async {
  final keys = await openLabKeys(
    Directory(o.state)..createSync(recursive: true),
    o.name,
  );
  final client = await Client.start(
    keys: keys,
    mailbox: Mailbox(base: o.server),
    report: log.call,
  );
  await keepCollecting(client);
  final calls = Calls(client, iceServers: o.iceServers, report: log.call);
  final media = await _media(o, log);

  final Call call;
  final peer = o.peer;
  if (peer == null) {
    final ringing = calls.ringing.first;
    log({'event': 'waiting-for-call'});
    call = await ringing;
    _show(call, remote, log);
    await call.answer(media: media);
  } else {
    final c = await openWithRetry(client, peer);
    if (c == null) {
      throw MailboxError('could not open a conversation with $peer');
    }
    call = await calls.start(c, media: media);
    _show(call, remote, log);
  }
  await call.connected.timeout(const Duration(seconds: 60));
  log({
    'event': 'connected',
    'call': call.id,
    'route': '${await call.route()}',
  });

  final ended = Completer<void>();
  final statsTimer = Timer.periodic(o.statsEvery, (_) async {
    try {
      log({
        'event': 'stats',
        'call': call.id,
        'reports': _keep(await call.stats()),
      });
    } catch (e) {
      log({'event': 'stats-failed', 'error': '$e'});
    }
  });
  unawaited(
    call.ended.then((why) {
      if (!ended.isCompleted) {
        ended.complete();
      }
    }),
  );
  if (peer != null) {
    await Future.any([Future<void>.delayed(o.callLength), ended.future]);
    await call.hangUp();
  } else {
    await ended.future;
  }
  statsTimer.cancel();
  final untilFile = o.untilFile;
  if (peer == null && untilFile != null) {
    await waitForFile(untilFile, log.call);
  }
  await guardedCollect(client);
  for (final t in media?.getTracks() ?? <MediaStreamTrack>[]) {
    await t.stop();
  }
  await calls.close();
  await client.close();
}

void _show(Call call, RTCVideoRenderer remote, LabLog log) {
  var sized = false;
  remote.onResize = () {
    if (!sized && remote.videoWidth > 0) {
      sized = true;
      log({
        'event': 'remote-video-sized',
        'width': remote.videoWidth,
        'height': remote.videoHeight,
        'texture': remote.textureId,
      });
    }
  };
  call.remoteMedia.listen((s) {
    log({
      'event': 'remote-media',
      'stream': s.id,
      'tracks': [for (final t in s.getTracks()) t.kind],
    });
    remote.srcObject = s;
  });
}

/// The media this phone sends: the default microphone, and this whole
/// screen as the picture (the lab has no camera; see GATE2-CALLS-PLAN).
Future<MediaStream?> _media(LabOptions o, LabLog log) async {
  MediaStream? stream;
  if (o.audio) {
    stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
  }
  if (o.video) {
    final screen = await navigator.mediaDevices.getDisplayMedia({
      'video': {
        'deviceId': {'exact': '0'},
        'mandatory': {'frameRate': 30.0},
      },
      'audio': false,
    });
    if (stream == null) {
      stream = screen;
    } else {
      for (final t in screen.getVideoTracks()) {
        await stream.addTrack(t);
      }
    }
  }
  log({
    'event': 'media',
    'tracks': [
      for (final t in stream?.getTracks() ?? <MediaStreamTrack>[]) t.kind,
    ],
  });
  return stream;
}

/// The stats a run needs: media in and out, the far end's view of what this
/// phone sent, and the connected pair. Raw values, JSON-safe.
List<Map<String, Object?>> _keep(List<StatsReport> reports) {
  const types = {
    'inbound-rtp',
    'outbound-rtp',
    'remote-inbound-rtp',
    'candidate-pair',
    'transport',
  };
  return [
    for (final r in reports)
      if (types.contains(r.type) &&
          (r.type != 'candidate-pair' || r.values['nominated'] == true))
        {
          'type': r.type,
          'id': r.id,
          ...jsonDecode(jsonEncode(r.values, toEncodable: (v) => '$v'))
              as Map<String, Object?>,
        },
  ];
}
