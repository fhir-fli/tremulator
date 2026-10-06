/// Drive WhatsApp on the field Android over adb, so nobody sits tapping for
/// three hours. Every action is appended at once to
/// lab/baseline/results/android_`label`.jsonl with the wall clock in ms.
/// Delivery is read from WhatsApp's own tick (the `status` widget's
/// content-desc: Pending, Sent, Delivered, Read), polled about twice a second;
/// the screen recording is the finer clock when it matters.
///
///   dart run bin/baseline_android.dart current
///       name of the chat on screen, and the newest tick
///   dart run bin/baseline_android.dart open `number`
///   dart run bin/baseline_android.dart number-of "`contact name`"
///       open that chat from the list, then its contact page, print the number
///   dart run bin/baseline_android.dart texts `number` `label` [n=10] [gap_s=10] [wait_s=300]
///   dart run bin/baseline_android.dart photo `number` `local.jpg` `label`
///   dart run bin/baseline_android.dart call `number` voice|video `label`
///   dart run bin/baseline_android.dart hangup `label`
///   dart run bin/baseline_android.dart watch `label` `seconds`
///       log the phone's Wi-Fi address; exit 3 the moment it leaves 10.42.0.x
///   dart run bin/baseline_android.dart wait-incoming `label` `seconds`
///       log each new incoming bubble as it appears (the iPhone → Android leg)
///   dart run bin/baseline_android.dart dump
///       print the ids and descriptions on screen (for finding new widgets)
library;

import 'dart:convert';
import 'dart:io';

import 'package:tremulator_lab/android_ui.dart';
import 'package:tremulator_lab/lab_dir.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) _usage();
  final cmd = argv.first;
  final a = argv.sublist(1);
  switch (cmd) {
    case 'dump':
      final nodes = await _nodes();
      for (final n in nodes) {
        if (n.id.isNotEmpty || n.desc.isNotEmpty) print(n);
      }
    case 'current':
      final nodes = await _nodes();
      print('chat: ${byId(nodes, 'conversation_contact_name')?.text}');
      print('newest tick: ${lastStatus(nodes)?.desc}');
      print('newest text: ${lastMessageText(nodes)?.text}');
      print('newest is incoming: ${newestIsIncoming(nodes)}');
    case 'open':
      if (a.length != 1) _usage();
      await _open(a[0]);
    case 'number-of':
      if (a.length != 1) _usage();
      await _numberOf(a[0]);
    case 'texts':
      if (a.length < 2) _usage();
      final log = _Log(a[1], cmd);
      final n = a.length > 2 ? int.parse(a[2]) : 10;
      final gap = a.length > 3 ? double.parse(a[3]) : 10.0;
      final waitS = a.length > 4 ? int.parse(a[4]) : 300;
      await _texts(a[0], log, n, gap, waitS);
      await log.close();
    case 'photo':
      if (a.length != 3) _usage();
      final log = _Log(a[2], cmd);
      await _photo(a[0], a[1], log);
      await log.close();
    case 'call':
      if (a.length != 3 || !{'voice', 'video'}.contains(a[1])) _usage();
      final log = _Log(a[2], cmd);
      await _call(a[0], a[1], log);
      await log.close();
    case 'hangup':
      if (a.length != 1) _usage();
      final log = _Log(a[0], cmd);
      await _hangup(log);
      await log.close();
    case 'watch':
      if (a.length != 2) _usage();
      final log = _Log(a[0], cmd);
      await _watch(log, int.parse(a[1]));
      await log.close();
    case 'wait-incoming':
      if (a.length != 2) _usage();
      final log = _Log(a[0], cmd);
      await _waitIncoming(log, int.parse(a[1]));
      await log.close();
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln(
    'usage: baseline_android.dart dump | current | open <number> | '
    'texts <number> <label> [n] [gap_s] | photo <number> <file> <label> | '
    'call <number> voice|video <label> | hangup <label> | '
    'wait-incoming <label> <seconds>',
  );
  exit(2);
}

/// One file per label AND per command. Dart's FileMode.append seeks to the
/// end once at open, it is not O_APPEND, so two processes sharing a file
/// overwrite each other (seen 2026-10-06: the hotspot watch and the call
/// driver erased each other's records).
class _Log {
  _Log(this.label, String command)
    : _sink = File(
        '${labDir()}/baseline/results/android_${label}_$command.jsonl',
      ).openWrite(mode: FileMode.append) {
    Directory('${labDir()}/baseline/results').createSync();
  }
  final String label;
  final IOSink _sink;

  Future<void> add(
    String event, [
    Map<String, Object?> extra = const {},
  ]) async {
    final now = DateTime.now();
    final rec = {
      't': now.toIso8601String(),
      'ms': now.millisecondsSinceEpoch,
      'event': event,
      ...extra,
    };
    _sink.writeln(jsonEncode(rec));
    await _sink.flush();
    print(
      '${now.toIso8601String().substring(11, 23)} $event '
      '${extra.isEmpty ? '' : jsonEncode(extra)}',
    );
  }

  Future<void> close() => _sink.close();
}

Future<String> _adb(List<String> args) async {
  final r = await Process.run('adb', args);
  if (r.exitCode != 0) {
    throw StateError('adb ${args.join(' ')}: ${r.stderr}');
  }
  return r.stdout as String;
}

/// The phone's Wi-Fi address. Every poll checks it: a run on a phone that has
/// left the shaped hotspot measures nothing, so it stops at once.
Future<String> _wlan0() async {
  final out = await _adb(['shell', 'ip', '-4', '-o', 'addr', 'show', 'wlan0']);
  return RegExp(r'inet (\d+\.\d+\.\d+\.\d+)').firstMatch(out)?.group(1) ??
      'none';
}

String hotspotPrefix = '10.42.0.';

Future<void> _assertOnHotspot(_Log log, String where) async {
  final ip = await _wlan0();
  if (!ip.startsWith(hotspotPrefix)) {
    await log.add('PHONE_LEFT_HOTSPOT', {'wlan0': ip, 'during': where});
    throw StateError('phone left the hotspot (wlan0=$ip) during $where');
  }
}

Future<List<UiNode>> _nodes() async {
  await _adb(['shell', 'uiautomator', 'dump', '/sdcard/ui.xml']);
  return parseNodes(await _adb(['exec-out', 'cat', '/sdcard/ui.xml']));
}

Future<void> _tap(UiNode n) async {
  final (x, y) = n.center;
  await _adb(['shell', 'input', 'tap', '$x', '$y']);
}

Future<UiNode?> _tryFor(
  UiNode? Function(List<UiNode>) pick, {
  required int seconds,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    final n = pick(await _nodes());
    if (n != null) return n;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return null;
}

Future<UiNode> _waitFor(
  UiNode? Function(List<UiNode>) pick, {
  int seconds = 10,
  String what = 'widget',
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    final n = pick(await _nodes());
    if (n != null) return n;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw StateError('$what not on screen after $seconds s');
}

/// Open the chat. A target of digits goes through the wa.me link, which
/// WhatsApp resolves online and which lands on the contact picker when the
/// link is down (seen on P4). Anything else is a contact name: WhatsApp's
/// own chat list is opened and the row tapped, no network involved. Text, if
/// given, is typed into the entry box after clearing any draft.
Future<void> _open(String target, {String text = ''}) async {
  if (RegExp(r'^\d+$').hasMatch(target)) {
    final url =
        'https://wa.me/$target'
        '${text.isEmpty ? '' : '?text=${Uri.encodeQueryComponent(text)}'}';
    await _adb([
      'shell',
      'am',
      'start',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      url,
      '-p',
      'com.whatsapp',
    ]);
    await _waitFor(
      (n) => byId(n, 'entry'),
      seconds: 90,
      what: 'chat entry box',
    );
    return;
  }
  final header = (await _nodes()).cast<UiNode?>().firstWhere(
    (n) => n!.id == '${waId}conversation_contact_name',
    orElse: () => null,
  );
  if (header == null || header.text != target) {
    await _adb([
      'shell',
      'am',
      'start',
      '-n',
      'com.whatsapp/.home.ui.HomeActivity',
    ]);
    final row = await _waitFor(
      (ns) => ns.cast<UiNode?>().firstWhere(
        (n) =>
            n!.id == '${waId}conversations_row_contact_name' &&
            n.text == target,
        orElse: () => null,
      ),
      seconds: 30,
      what: 'chat row "$target"',
    );
    await _tap(row);
    final h = await _waitFor(
      (ns) => byId(ns, 'conversation_contact_name'),
      what: 'chat header',
    );
    if (h.text != target) {
      throw StateError('opened "${h.text}", not "$target"; stopping');
    }
  }
  if (text.isNotEmpty) {
    final entry = await _waitFor((n) => byId(n, 'entry'), what: 'entry box');
    await _tap(entry);
    // clear a stale draft: select all, delete
    await _adb(['shell', 'input', 'keycombination', '113', '29']);
    await _adb(['shell', 'input', 'keyevent', '67']);
    final typed = text.replaceAll("'", '').replaceAll(' ', '%s');
    await _adb(['shell', "input text '$typed'"]);
  }
}

/// Launch WhatsApp's chat list, open the chat whose row shows `name`, verify
/// the header shows it, open the contact page and print any phone number on
/// it. Every tap is on a widget found in the current screen dump.
Future<void> _numberOf(String name) async {
  await _adb([
    'shell',
    'am',
    'start',
    '-n',
    'com.whatsapp/.home.ui.HomeActivity',
  ]);
  final row = await _waitFor(
    (ns) => ns.cast<UiNode?>().firstWhere(
      (n) => n!.id == '${waId}conversations_row_contact_name' && n.text == name,
      orElse: () => null,
    ),
    what: 'chat row "$name"',
  );
  await _tap(row);
  final header = await _waitFor(
    (ns) => byId(ns, 'conversation_contact_name'),
    what: 'chat header',
  );
  if (header.text != name) {
    throw StateError('opened "${header.text}", not "$name"; stopping');
  }
  print('chat open: ${header.text}');
  final contact = await _waitFor(
    (ns) => byId(ns, 'conversation_contact'),
    what: 'chat header button',
  );
  await _tap(contact);
  await Future<void>.delayed(const Duration(seconds: 2));
  final ns = await _nodes();
  final numbers = ns
      .map((n) => n.text)
      .where((t) => RegExp(r'^\+?[0-9][0-9 ()-]{7,}$').hasMatch(t))
      .toSet();
  print('numbers on contact page: $numbers');
  await _adb(['shell', 'input', 'keyevent', 'KEYCODE_BACK']);
}

Future<void> _texts(
  String number,
  _Log log,
  int n,
  double gap, [
  int waitS = 300,
]) async {
  for (var i = 1; i <= n; i++) {
    final body =
        'tremulator ${log.label} $i of $n: '
        'patient stable, repeat obs in one hour, call if BP under ninety.';
    await _open(number, text: body);
    final send = await _waitFor(
      (ns) => byId(ns, 'send') ?? byDesc(ns, 'Send'),
      what: 'send button',
    );
    await _tap(send);
    final t0 = DateTime.now();
    await log.add('text_tap', {'i': i, 'chars': body.length});
    String? last;
    final deadline = t0.add(Duration(seconds: waitS));
    while (DateTime.now().isBefore(deadline)) {
      await _assertOnHotspot(log, 'text $i');
      final s = lastStatus(await _nodes())?.desc;
      if (s != null && s != last) {
        last = s;
        await log.add('text_tick', {
          'i': i,
          'tick': s,
          'since_tap_s': DateTime.now().difference(t0).inMilliseconds / 1000,
        });
        if (s == 'Delivered' || s == 'Read') break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (last != 'Delivered' && last != 'Read') {
      await log.add('text_timeout', {'i': i, 'last_tick': last});
    }
    final wait = gap - DateTime.now().difference(t0).inMilliseconds / 1000;
    if (i < n && wait > 0) {
      await Future<void>.delayed(Duration(milliseconds: (wait * 1000).round()));
    }
  }
}

Future<void> _photo(String number, String local, _Log log) async {
  final name = local.split('/').last;
  final remote = '/sdcard/Download/$name';
  await _adb(['push', local, remote]);
  await _adb([
    'shell',
    'am',
    'broadcast',
    '-a',
    'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
    '-d',
    'file://$remote',
  ]);
  // One shell string, so the phone's shell keeps the SQL quotes.
  final query =
      'content query --uri content://media/external/images/media '
      '--projection _id --where "_display_name=\'$name\'"';
  final q = await _adb(['shell', query]);
  final id = RegExp(r'_id=(\d+)').firstMatch(q)?.group(1);
  if (id == null) throw StateError('media store has no row for $name: $q');
  await _adb([
    'shell',
    'am',
    'start',
    '-a',
    'android.intent.action.SEND',
    '-t',
    'image/jpeg',
    '-n',
    'com.whatsapp/.contact.ui.picker.ExternalShareAlias',
    '--es',
    'jid',
    '$number@s.whatsapp.net',
    '--eu',
    'android.intent.extra.STREAM',
    'content://media/external/images/media/$id',
    '--grant-read-uri-permission',
  ]);
  final send = await _waitFor(
    (ns) => byId(ns, 'send') ?? byDesc(ns, 'Send'),
    seconds: 20,
    what: 'photo send button',
  );
  await _tap(send);
  final t0 = DateTime.now();
  await log.add('photo_tap', {'file': name, 'bytes': File(local).lengthSync()});
  String? last;
  final deadline = t0.add(const Duration(minutes: 10));
  while (DateTime.now().isBefore(deadline)) {
    await _assertOnHotspot(log, 'photo');
    final s = lastStatus(await _nodes())?.desc;
    if (s != null && s != last) {
      last = s;
      await log.add('photo_tick', {
        'tick': s,
        'since_tap_s': DateTime.now().difference(t0).inMilliseconds / 1000,
      });
      if (s == 'Delivered' || s == 'Read') break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  if (last != 'Delivered' && last != 'Read') {
    await log.add('photo_timeout', {'last_tick': last});
  }
}

Future<void> _call(String number, String kind, _Log log) async {
  await _open(number);
  final label = kind == 'voice' ? 'Voice call' : 'Video call';
  final btn = await _waitFor((ns) => byDesc(ns, label), what: '$label button');
  await _tap(btn);
  await log.add('call_tap', {'kind': kind});
  // A confirmation sheet ("Call <name>?") appears on some builds.
  final confirm = await _tryFor(
    (ns) => byDesc(ns, 'Call') ?? _byText(ns, 'Call'),
    seconds: 3,
  );
  if (confirm != null) {
    await _tap(confirm);
    await log.add('call_confirm');
  }
  // Watch the call screen for its state text for up to 60 s.
  final t0 = DateTime.now();
  String? last;
  while (DateTime.now().difference(t0).inSeconds < 60) {
    await _assertOnHotspot(log, 'call setup');
    final ns = await _nodes();
    final state = _callState(ns);
    if (state != null && state != last) {
      last = state;
      await log.add('call_state', {
        'state': state,
        'since_tap_s': DateTime.now().difference(t0).inMilliseconds / 1000,
      });
      if (RegExp(r'^\d+:\d\d').hasMatch(state)) break; // timer: connected
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

UiNode? _byText(List<UiNode> ns, String text) {
  for (final n in ns) {
    if (n.text == text) return n;
  }
  return null;
}

/// WhatsApp's call screen shows "Calling…", "Ringing…", then a mm:ss timer.
String? _callState(List<UiNode> ns) {
  for (final n in ns) {
    final t = n.text.trim();
    if (t.isEmpty) continue;
    if (RegExp(
      '^(Calling|Ringing|Connecting|Reconnecting|Call ended|'
      'Not answered|No answer|Unavailable|Busy)',
    ).hasMatch(t)) {
      return t;
    }
    if (RegExp(r'^\d+:\d\d$').hasMatch(t)) return t;
  }
  return null;
}

Future<void> _hangup(_Log log) async {
  // A video call hides its controls after a few seconds: tap the screen to
  // bring them back, then find the end button. Fall back to the position the
  // red button had on this phone (1272x2772) when the dump has no button.
  await _adb(['shell', 'input', 'tap', '636', '1386']);
  await Future<void>.delayed(const Duration(milliseconds: 600));
  final btn = await _tryFor(
    (ns) =>
        byDesc(ns, 'End call') ??
        byDesc(ns, 'Leave call') ??
        byDesc(ns, 'Hang up') ??
        byId(ns, 'end_call_button'),
    seconds: 4,
  );
  if (btn != null) {
    await _tap(btn);
    await log.add('hangup', {'via': btn.desc});
  } else {
    await _adb(['shell', 'input', 'tap', '636', '1386']);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _adb(['shell', 'input', 'tap', '1086', '2527']);
    await log.add('hangup', {'via': 'fixed position, button not in dump'});
  }
}

/// Log the phone's Wi-Fi address every 2 s for [seconds]; exits non-zero the
/// moment it leaves the hotspot. Run beside a call.
Future<void> _watch(_Log log, int seconds) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  var last = '';
  while (DateTime.now().isBefore(end)) {
    final ip = await _wlan0();
    if (ip != last) {
      await log.add('wlan0', {'ip': ip});
      last = ip;
    }
    if (!ip.startsWith(hotspotPrefix)) {
      await log.add('PHONE_LEFT_HOTSPOT', {'wlan0': ip, 'during': 'watch'});
      exit(3);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

Future<void> _waitIncoming(_Log log, int seconds) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  String? lastText;
  var count = 0;
  while (DateTime.now().isBefore(end)) {
    final ns = await _nodes();
    final t = lastMessageText(ns);
    if (t != null && newestIsIncoming(ns) && t.text != lastText) {
      lastText = t.text;
      count++;
      await log.add('incoming', {'n': count, 'text': t.text});
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  await log.add('wait_incoming_end', {'count': count});
}
