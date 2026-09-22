/// Scan files and packet captures for planted canary strings.
///
/// Each canary is searched in these forms: UTF-8, UTF-16LE, UTF-16BE, hex
/// (both cases), URL-encoded, JSON \u-escaped, and base64 at all three
/// alignments. Gzip and zlib streams found in a blob are decompressed, base64
/// runs are decoded, and JSON string literals containing \u escapes are decoded;
/// each result is scanned too, to two levels (base64 wrapping gzip is a common
/// way plaintext hides). Files ending .pcap are also parsed: TCP streams are
/// reassembled per direction and UDP payloads extracted.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One place a canary was found.
class Hit {
  Hit(this.where, this.canary, this.form, this.offset);
  final String where;
  final String canary;
  final String form;
  final int offset;
  Map<String, Object> toJson() =>
      {'where': where, 'canary': canary, 'form': form, 'offset': offset};
}

/// Python's urllib.parse.quote with its default safe="/".
String _quote(String s) {
  final out = StringBuffer();
  for (final b in utf8.encode(s)) {
    final c = String.fromCharCode(b);
    if (RegExp(r'[A-Za-z0-9_.\-~/]').hasMatch(c)) {
      out.write(c);
    } else {
      out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

List<int> _utf16(String s, {required bool little}) {
  final out = <int>[];
  for (final u in s.codeUnits) {
    final hi = u >> 8, lo = u & 0xff;
    out.addAll(little ? [lo, hi] : [hi, lo]);
  }
  return out;
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Every encoded form searched for one canary.
Map<String, List<int>> variants(String text) {
  final b = utf8.encode(text);
  final v = <String, List<int>>{
    'utf8': b,
    'utf16le': _utf16(text, little: true),
    'utf16be': _utf16(text, little: false),
    'hex': ascii.encode(_hex(b)),
    'HEX': ascii.encode(_hex(b).toUpperCase()),
    'url': ascii.encode(_quote(text)),
    'json_u': ascii.encode(text.codeUnits
        .map((c) => '\\u${c.toRadixString(16).padLeft(4, '0')}')
        .join()),
  };
  for (var pad = 0; pad < 3; pad++) {
    // base64 of the canary at each alignment; keep the stable middle.
    final enc = ascii.encode(base64.encode([...List.filled(pad, 0), ...b]));
    final skip = (pad * 4 + 2) ~/ 3 + (pad > 0 ? 1 : 0);
    if (enc.length - 4 - skip >= 8) {
      v['b64_$pad'] = enc.sublist(skip, enc.length - 4);
    }
  }
  return v;
}

/// Index of [needle] in [hay], or -1.
int indexOfBytes(List<int> hay, List<int> needle) {
  if (needle.isEmpty || needle.length > hay.length) return -1;
  final first = needle[0];
  outer:
  for (var i = 0; i <= hay.length - needle.length; i++) {
    if (hay[i] != first) continue;
    for (var j = 1; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Inflate from [start], tolerating trailing data after the stream ends, the
/// way Python's decompressobj does. Returns what was decoded, or null.
List<int>? _inflate(List<int> blob, int start, {required bool gzip}) {
  final filter = RawZLibFilter.inflateFilter(gzip: gzip);
  final out = <int>[];
  try {
    const chunk = 512;
    for (var i = start; i < blob.length; i += chunk) {
      final end = i + chunk < blob.length ? i + chunk : blob.length;
      filter.process(blob, i, end);
      List<int>? o;
      while ((o = filter.processed(flush: false)) != null) {
        out.addAll(o!);
      }
    }
    List<int>? o;
    while ((o = filter.processed()) != null) {
      out.addAll(o!);
    }
  } on Exception {
    // Trailing bytes after the compressed stream, or not a stream at all.
  }
  return out.isEmpty ? null : out;
}

final _b64Run = RegExp('[A-Za-z0-9+/]{16,}={0,2}');
final _jsonLit = RegExp(
    r'"(?:[^"\\]|\\.){0,4096}?\\u[0-9a-fA-F]{4}(?:[^"\\]|\\.){0,4096}"');

/// Yield (how, bytes) for compressed streams, JSON literals and base64 runs.
Iterable<(String, List<int>)> decodedChildren(List<int> blob) sync* {
  for (var i = 0; i + 2 < blob.length; i++) {
    if (blob[i] == 0x1f && blob[i + 1] == 0x8b && blob[i + 2] == 0x08) {
      final d = _inflate(blob, i, gzip: true);
      if (d != null) yield ('gzip', d);
    }
    if (blob[i] == 0x78 && const [0x01, 0x5e, 0x9c, 0xda].contains(blob[i + 1])) {
      final d = _inflate(blob, i, gzip: false);
      if (d != null) yield ('zlib', d);
    }
  }
  final text = latin1.decode(blob);
  for (final m in _jsonLit.allMatches(text)) {
    try {
      final s = jsonDecode(m.group(0)!) as String;
      yield ('json', utf8.encode(s));
    } on FormatException {
      // not a JSON literal after all
    }
  }
  for (final m in _b64Run.allMatches(text)) {
    var s = m.group(0)!;
    if (!s.endsWith('=')) s = s.substring(0, s.length - s.length % 4);
    try {
      yield ('base64', base64.decode(s));
    } on FormatException {
      // not base64
    }
  }
}

/// Scan one blob, then what can be decoded out of it, to two levels.
void scanBlob(List<int> blob, Map<String, Map<String, List<int>>> canaries,
    String where, void Function(Hit) emit,
    [int depth = 0]) {
  canaries.forEach((cid, forms) {
    forms.forEach((form, needle) {
      final i = indexOfBytes(blob, needle);
      if (i >= 0) emit(Hit(where, cid, form, i));
    });
  });
  if (depth < 2) {
    for (final (how, child) in decodedChildren(blob)) {
      scanBlob(child, canaries, '$where|$how', emit, depth + 1);
    }
  }
}

/// Classic libpcap: TCP streams reassembled per direction, and UDP payloads.
(Map<String, List<int>>, List<List<int>>) pcapStreams(Uint8List data) {
  final segs = <String, Map<int, List<int>>>{};
  final udp = <List<int>>[];
  if (data.length < 24) return ({}, udp);
  final bd = ByteData.sublistView(data);
  final m = data.sublist(0, 4);
  final little = (m[0] == 0xd4 && m[1] == 0xc3) || (m[0] == 0x4d && m[1] == 0x3c);
  final e = little ? Endian.little : Endian.big;
  final linktype = bd.getUint32(20, e);
  var off = 24;
  while (off + 16 <= data.length) {
    final incl = bd.getUint32(off + 8, e);
    off += 16;
    if (off + incl > data.length) break;
    final pkt = data.sublist(off, off + incl);
    off += incl;
    List<int> eth;
    Uint8List l3;
    if (linktype == 1 && pkt.length > 14) {
      eth = pkt.sublist(12, 14); l3 = pkt.sublist(14);
    } else if (linktype == 113 && pkt.length > 16) {
      eth = pkt.sublist(14, 16); l3 = pkt.sublist(16);
    } else if (linktype == 276 && pkt.length > 20) {
      eth = pkt.sublist(0, 2); l3 = pkt.sublist(20);
    } else {
      continue;
    }
    int proto;
    List<int> src, dst;
    Uint8List l4;
    if (eth[0] == 0x08 && eth[1] == 0x00 && l3.length >= 20) {
      final ihl = (l3[0] & 15) * 4;
      proto = l3[9]; src = l3.sublist(12, 16); dst = l3.sublist(16, 20);
      if (ihl > l3.length) continue;
      l4 = l3.sublist(ihl);
    } else if (eth[0] == 0x86 && eth[1] == 0xdd && l3.length >= 40) {
      proto = l3[6]; src = l3.sublist(8, 24); dst = l3.sublist(24, 40);
      l4 = l3.sublist(40);
    } else {
      continue;
    }
    final l4d = ByteData.sublistView(l4);
    if (proto == 6 && l4.length >= 20) {
      final sp = l4d.getUint16(0), dp = l4d.getUint16(2), seq = l4d.getUint32(4);
      final doff = (l4[12] >> 4) * 4;
      if (doff > l4.length) continue;
      final payload = l4.sublist(doff);
      if (payload.isNotEmpty) {
        final flow = '${_hex(src)}:$sp>${_hex(dst)}:$dp';
        // Retransmissions share a sequence number and collapse.
        (segs[flow] ??= {})[seq] = payload;
      }
    } else if (proto == 17 && l4.length >= 8) {
      udp.add(l4.sublist(8));
    }
  }
  final streams = <String, List<int>>{};
  segs.forEach((flow, d) {
    final keys = d.keys.toList()..sort();
    streams[flow] = [for (final k in keys) ...d[k]!];
  });
  return (streams, udp);
}

/// Scan [paths] (files or directories) for the canaries in [canaryFile]
/// ("id<TAB>text" per line). Every hit is appended to [out] and flushed.
Future<List<Hit>> scanPaths(
    String canaryFile, List<String> paths, IOSink out) async {
  final canaries = <String, Map<String, List<int>>>{};
  for (final line in File(canaryFile).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final tab = line.indexOf('\t');
    canaries[line.substring(0, tab)] = variants(line.substring(tab + 1));
  }
  final files = <String>[];
  for (final p in paths) {
    if (FileSystemEntity.isDirectorySync(p)) {
      files.addAll(Directory(p)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path));
    } else if (File(p).existsSync()) {
      files.add(p);
    }
  }
  files.sort();
  final hits = <Hit>[];
  void emit(Hit h) {
    hits.add(h);
    out.writeln(jsonEncode(h.toJson()));
  }

  for (final f in files) {
    final data = File(f).readAsBytesSync();
    scanBlob(data, canaries, f, emit);
    if (f.endsWith('.pcap')) {
      final (streams, udp) = pcapStreams(data);
      streams.forEach((flow, s) => scanBlob(s, canaries, '$f#tcp', emit));
      for (var i = 0; i < udp.length; i++) {
        scanBlob(udp[i], canaries, '$f#udp$i', emit);
      }
    }
    await out.flush();
  }
  return hits;
}
