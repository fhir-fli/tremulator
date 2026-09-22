// Known-positive and known-negative checks for the canary scanner, one per
// encoding; the same 13 cases as the Python version it replaces. A scanner that
// never fires is broken; so is one that fires on clean data.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:tremulator_lab/canary_scan.dart';

const c = 'CANARY-7f3a9c2e41b0d6f8 pt febrile HIV PEP day 3';

List<int> _utf16le(String s) => [
      for (final u in s.codeUnits) ...[u & 0xff, u >> 8],
    ];

String _quote(String s) => Uri.encodeComponent(s).replaceAll('%2F', '/');

void main() {
  final positives = <String, List<int>>{
    'utf8': utf8.encode(c),
    'utf16le': _utf16le(c),
    'hex': ascii.encode(
      utf8.encode(c).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ),
    'url': ascii.encode(_quote(c)),
    'json_u': utf8.encode(jsonEncode(c).replaceAll('C', 'C')),
    'b64_aligned': ascii.encode(base64.encode(utf8.encode(c))),
    'b64_offset1': ascii.encode(base64.encode(utf8.encode('x$c'))),
    'b64_offset2': ascii.encode(base64.encode(utf8.encode('xy$c'))),
    'gzip': gzip.encode(utf8.encode('{"m":"$c"}')),
    'zlib': zlib.encode(utf8.encode('prefix $c')),
    'b64_of_gzip': ascii.encode(base64.encode(gzip.encode(utf8.encode(c)))),
  };
  final rnd = Random(7);
  final negatives = <String, List<int>>{
    'random': List.generate(4096, (_) => rnd.nextInt(256)),
    'near_miss': utf8.encode(c.replaceAll('7f3a', '7f3b')),
  };
  late Directory tmp;
  late String canaryFile;
  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('canary');
    canaryFile = '${tmp.path}/c.tsv';
    File(canaryFile).writeAsStringSync('c1\t$c\n');
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<int> scan(String name, List<int> blob) async {
    final f = File('${tmp.path}/$name.bin')
      ..writeAsBytesSync(
        [...ascii.encode('junk'), ...blob, ...ascii.encode('junk')],
      );
    final sink = File('${tmp.path}/$name.jsonl').openWrite();
    final hits = await scanPaths(canaryFile, [f.path], sink);
    await sink.close();
    return hits.length;
  }

  positives.forEach((name, blob) {
    test(
      'finds $name',
      () async => expect(await scan(name, blob), greaterThan(0)),
    );
  });
  negatives.forEach((name, blob) {
    test('stays clean on $name', () async => expect(await scan(name, blob), 0));
  });
}
