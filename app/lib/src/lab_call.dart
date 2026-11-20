import 'dart:async';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tremulator/src/lab_host.dart';
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
        'opus-max-bitrate',
        help: 'maxaveragebitrate this phone asks for (RFC 7587)',
      )
      ..addOption('opus-ptime', help: 'ptime this phone asks for (RFC 7587)')
      ..addFlag('opus-dtx', help: 'ask for usedtx=1 (RFC 7587)')
      ..addMultiOption(
        'audio-drop',
        allowed: _audioExtensions.keys,
        help: 'leave this header extension out of the audio section (RFC 8285)',
      )
      ..addFlag(
        'separate-streams',
        defaultsTo: true,
        help:
            'send the video in a stream of its own (no lip sync, RFC 8830; '
            'D17); --no-separate-streams puts it in the sound stream',
      )
      ..addFlag(
        'suspend-video',
        defaultsTo: true,
        help:
            'let the video engine stop sending video while the link allows '
            'less than its lowest rate (Calls.suspendVideoBelowMinimum); '
            '--no-suspend-video sends it at its lowest rate whatever the link',
      )
      ..addOption(
        'tap-video-after',
        help:
            "seconds after this phone's video stops to press its "
            "'try video again' (the lab's tap; once per stop)",
      )
      ..addFlag(
        'plant-changed-fingerprint',
        help:
            "planted defect (E1, E3a): read the other phone's session "
            'description with one hex digit of its certificate fingerprint '
            'changed; the call must fail at the handshake',
      )
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

  /// How this phone asks the other to send its sound.
  OpusReceive get opus {
    int? n(String name) {
      final v = _a[name] as String?;
      return v == null ? null : int.parse(v);
    }

    return OpusReceive(
      maxAverageBitrate: n('opus-max-bitrate'),
      ptime: n('opus-ptime'),
      dtx: (_a['opus-dtx'] as bool) ? true : null,
    );
  }

  /// Header extensions this phone leaves out of its audio section.
  AudioExtensions get audioExtensions => AudioExtensions(
    drop: {
      for (final n in _a['audio-drop'] as List<String>) _audioExtensions[n]!,
    },
  );

  /// Whether the video goes in a stream of its own.
  bool get separateStreams => _a['separate-streams'] as bool;

  /// Whether video stops while the link allows less than its lowest rate.
  bool get suspendVideo => _a['suspend-video'] as bool;

  /// How long after this phone's video stops the lab presses its "try
  /// video again", or null for never.
  Duration? get tapVideoAfter {
    final v = _a['tap-video-after'] as String?;
    return v == null ? null : Duration(seconds: int.parse(v));
  }

  /// The stop sign.
  String? get untilFile => _a['until-file'] as String?;

  /// Whether this phone reads the other's fingerprint with a digit changed.
  bool get plantChangedFingerprint => _a['plant-changed-fingerprint'] as bool;
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

  /// In a browser, sound plays only from a page element, which a renderer
  /// makes for the stream it is given (flutter_webrtc web
  /// rtc_video_renderer_impl.dart). With separate streams the sound has its
  /// own stream, so it gets its own renderer, never shown. Unused elsewhere:
  /// the Linux and phone builds play every incoming sound by themselves.
  final RTCVideoRenderer _sound = RTCVideoRenderer();
  bool _ready = false;

  /// What the screen says about video, or null: Gate 5's "says so". With
  /// a retry, it offers a tap to try this phone's video again.
  final ValueNotifier<_Notice?> _notice = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await _remote.initialize();
    if (kIsWeb) {
      await _sound.initialize();
    }
    setState(() => _ready = true);
    final log = openLabSink(widget.options.out);
    try {
      await _run(widget.options, log, _remote, _sound, _notice);
      log({'event': 'done'});
      await log.close();
      finishLab(0);
    } catch (e, st) {
      log({'event': 'run-failed', 'error': '$e', 'stack': '$st'});
      await log.close();
      finishLab(2);
    }
  }

  @override
  // Dark grey, not black: a screenshot then tells this window from the bare
  // screen behind it, which is black.
  // The Stack below resolves its alignment against a text direction, and
  // with no app widget above there is none: on the web build the first
  // frame threw "Null check operator used on a null value" in
  // AlignmentDirectional.resolve and the picture was never shown (calls42).
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0xFF303030),
      // RTCVideoView chooses texture or placeholder when it is built, so it is
      // rebuilt whenever the renderer changes (a stream set, a first frame).
      // Built once, it kept the placeholder for the whole call (calls1).
      child: _ready
          ? Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<RTCVideoValue>(
                  valueListenable: _remote,
                  builder: (_, _, _) => RTCVideoView(_remote),
                ),
                ValueListenableBuilder<_Notice?>(
                  valueListenable: _notice,
                  builder: (_, notice, _) => notice == null
                      ? const SizedBox.shrink()
                      : Center(
                          child: GestureDetector(
                            onTap: notice.retry,
                            child: Text(
                              notice.retry == null
                                  ? notice.text
                                  : '${notice.text}\nTap to try video again.',
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 32,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            )
          : const SizedBox.expand(),
    ),
  );
}

Future<void> _run(
  LabOptions o,
  LabSink log,
  RTCVideoRenderer remote,
  RTCVideoRenderer sound,
  ValueNotifier<_Notice?> notice,
) async {
  log({
    'event': 'opus-asked',
    'maxaveragebitrate': o.opus.maxAverageBitrate,
    'ptime': o.opus.ptime,
    'usedtx': o.opus.dtx,
    'audio-drop': o.audioExtensions.drop.toList(),
    'separate-streams': o.separateStreams,
    'suspend-video': o.suspendVideo,
    'plant-changed-fingerprint': o.plantChangedFingerprint,
  });
  log({'event': 'platform', 'web': kIsWeb});
  final keys = await openLabKeyStore(o.state, o.name);
  final client = await Client.start(
    keys: keys,
    mailbox: Mailbox(base: o.server),
    report: log.call,
  );
  await keepCollecting(client);
  final calls = Calls(
    client,
    iceServers: o.iceServers,
    opus: o.opus,
    audioExtensions: o.audioExtensions,
    separateStreams: o.separateStreams,
    suspendVideoBelowMinimum: o.suspendVideo,
    // ignore: invalid_use_of_visible_for_testing_member, the lab's planted defect is a test; the hook exists for it.
    alterRemoteSdp: o.plantChangedFingerprint ? _changeFingerprint : null,
    report: log.call,
  );
  final media = await _media(o, log);

  final Call call;
  final peer = o.peer;
  if (peer == null) {
    final ringing = calls.ringing.first;
    log({'event': 'waiting-for-call'});
    call = await ringing;
    _show(call, remote, sound, notice, log, o.tapVideoAfter);
    await call.answer(media: media);
  } else {
    final c = await openWithRetry(client, peer);
    if (c == null) {
      throw MailboxError('could not open a conversation with $peer');
    }
    call = await calls.start(c, media: media);
    _show(call, remote, sound, notice, log, o.tapVideoAfter);
  }
  // No timeout of its own: the call's setup deadline (90 s) bounds this.
  // A 60 s one here cut setup short of it (calls11 P4-blocked).
  await call.connected;
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
    await waitForStop(untilFile, log.call);
  }
  await guardedCollect(client);
  for (final t in media?.getTracks() ?? <MediaStreamTrack>[]) {
    await t.stop();
  }
  await calls.close();
  await client.close();
}

void _show(
  Call call,
  RTCVideoRenderer remote,
  RTCVideoRenderer sound,
  ValueNotifier<_Notice?> notice,
  LabSink log,
  Duration? tapAfter,
) {
  call.video.listen((c) {
    final shown = c.held
        ? _Notice(
            c.local
                ? 'Your video is paused: the connection is too slow for it. '
                      'Sound continues.'
                : 'Their video is paused: the connection is too slow for it. '
                      'Sound continues.',
          )
        : c.sending
        ? null
        : c.local
        ? _Notice(
            'Your video is off: weak connection. Sound continues.',
            retry: () {
              log({'event': 'video-retry-tapped'});
              unawaited(call.retryVideo());
            },
          )
        : const _Notice(
            'Their video is off: weak connection. Sound continues.',
          );
    notice.value = shown;
    final retry = shown?.retry;
    if (retry != null && tapAfter != null) {
      // The lab's tap: the same press a person would make, if the notice is
      // still up by then.
      Timer(tapAfter, () {
        if (identical(notice.value, shown)) {
          retry();
        }
      });
    }
  });
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
    // With separate streams (the default) the sound and the picture arrive
    // as two streams; the picture's is the one to show (the sound plays
    // either way).
    final hasVideo = s.getTracks().any((t) => t.kind == 'video');
    if (remote.srcObject == null || hasVideo) {
      remote.srcObject = s;
    }
    // In a browser a sound-only stream gets the sound renderer; a stream
    // with video already plays its sound through the picture's renderer.
    if (kIsWeb && !hasVideo) {
      sound.srcObject = s;
    }
  });
}

/// The media this phone sends: the default microphone, and this whole
/// screen as the picture (the lab has no camera; see GATE2-CALLS-PLAN).
Future<MediaStream?> _media(LabOptions o, LabSink log) async {
  MediaStream? stream;
  if (o.audio) {
    stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
  }
  if (o.video) {
    // A browser picks the screen itself (the lab starts Chrome with
    // --auto-select-desktop-capture-source) and takes standard constraints
    // (W3C Screen Capture); the Linux plugin wants the screen's id.
    final screen = await navigator.mediaDevices.getDisplayMedia(
      kIsWeb
          ? {
              'video': {'frameRate': 30},
              'audio': false,
            }
          : {
              'video': {
                'deviceId': {'exact': '0'},
                'mandatory': {'frameRate': 30.0},
              },
              'audio': false,
            },
    );
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

/// What the screen says about video, and the tap that tries this phone's
/// video again, if it is this phone's.
class _Notice {
  const _Notice(this.text, {this.retry});

  final String text;
  final VoidCallback? retry;
}

/// One hex digit of the first certificate fingerprint changed, as a
/// different phone's would be (the same change as calls_test's).
String _changeFingerprint(String sdp) {
  final line = RegExp(
    r'^a=fingerprint:(\S+) ([0-9A-F]{2})',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(sdp);
  if (line == null) {
    throw StateError('no fingerprint in the session description');
  }
  final byte = line.group(2)!;
  final changed = byte[0] + (byte[1].toUpperCase() == 'A' ? 'B' : 'A');
  return sdp.replaceRange(line.end - 2, line.end, changed);
}

/// The lab's names for the header extensions it can leave out.
const Map<String, String> _audioExtensions = {
  'abs-send-time': AudioExtensions.absSendTime,
  'transport-cc': AudioExtensions.transportCc,
};
