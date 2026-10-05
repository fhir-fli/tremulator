/// Read an Android screen through `uiautomator dump` and find widgets by
/// resource id or content description. WhatsApp's ids seen on the field phone
/// (CPH2749, Android 16, 2026-10-05): `entry` (text box), `send` (send
/// button once there is text), `status` (the tick on a sent bubble; its
/// content-desc reads Pending / Sent / Delivered / Read),
/// `conversation_contact_name`; the call buttons have no id and are found by
/// content-desc "Voice call" / "Video call".
library;

import 'dart:math';

class UiNode {
  UiNode({
    required this.id,
    required this.desc,
    required this.text,
    required this.cls,
    required this.bounds,
  });
  final String id;
  final String desc;
  final String text;
  final String cls;
  final (int, int, int, int) bounds; // x1 y1 x2 y2

  (int, int) get center =>
      ((bounds.$1 + bounds.$3) ~/ 2, (bounds.$2 + bounds.$4) ~/ 2);
  int get bottom => bounds.$4;

  @override
  String toString() => 'UiNode($id, "$desc", "$text", $bounds)';
}

final _node = RegExp(r'<node\b([^>]*)/?>');
final _attr = RegExp(r'(\w[\w-]*)="([^"]*)"');
final _bounds = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]');

String _unescape(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

List<UiNode> parseNodes(String xml) {
  final out = <UiNode>[];
  for (final m in _node.allMatches(xml)) {
    final a = <String, String>{};
    for (final x in _attr.allMatches(m.group(1)!)) {
      a[x.group(1)!] = _unescape(x.group(2)!);
    }
    final b = _bounds.firstMatch(a['bounds'] ?? '');
    if (b == null) continue;
    out.add(
      UiNode(
        id: a['resource-id'] ?? '',
        desc: a['content-desc'] ?? '',
        text: a['text'] ?? '',
        cls: a['class'] ?? '',
        bounds: (
          int.parse(b.group(1)!),
          int.parse(b.group(2)!),
          int.parse(b.group(3)!),
          int.parse(b.group(4)!),
        ),
      ),
    );
  }
  return out;
}

const waId = 'com.whatsapp:id/';

UiNode? byId(List<UiNode> nodes, String shortId) {
  for (final n in nodes) {
    if (n.id == '$waId$shortId') return n;
  }
  return null;
}

/// First node whose content-desc starts with `prefix` (WhatsApp appends
/// ", Button" and hints to some descriptions).
UiNode? byDesc(List<UiNode> nodes, String prefix) {
  for (final n in nodes) {
    if (n.desc.startsWith(prefix)) return n;
  }
  return null;
}

/// The lowest `status` tick on screen: the newest outgoing message.
UiNode? lastStatus(List<UiNode> nodes) {
  UiNode? best;
  for (final n in nodes) {
    if (n.id == '${waId}status' && (best == null || n.bottom > best.bottom)) {
      best = n;
    }
  }
  return best;
}

/// The lowest message bubble text on screen.
UiNode? lastMessageText(List<UiNode> nodes) {
  UiNode? best;
  for (final n in nodes) {
    if (n.id == '${waId}message_text' &&
        (best == null || n.bottom > best.bottom)) {
      best = n;
    }
  }
  return best;
}

/// Where the newest bubble sits relative to the status tick: an incoming
/// bubble has no tick, so a message_text lower than every tick is incoming.
bool newestIsIncoming(List<UiNode> nodes) {
  final t = lastMessageText(nodes);
  final s = lastStatus(nodes);
  if (t == null) return false;
  if (s == null) return true;
  return t.bottom > s.bottom + max(0, s.bounds.$4 - s.bounds.$2);
}
