/// Toy client for the mutation test. Usage: toy_client SERVER MSGS_TSV
/// Sends every canary as a message body (and the first as an attachment),
/// fetches them back, keeps a local history in SQLite, and purges it.
///
/// DEFECT (environment) selects one deliberate flaw. "none" is the correct
/// behaviour, which the scanner must NOT flag.
///
/// - none: AES-GCM on body and attachment, with a key the server never
///   sees; local history encrypted under a key per message; purge destroys
///   the keys, with secure_delete on.
/// - plaintext_body: body sent unencrypted.
/// - plaintext_attachment: attachment unencrypted, body encrypted.
/// - preview_leak: encrypted body plus a plaintext notification preview.
/// - purge_unlink_only: history stored in plaintext; purge is a plain
///   DELETE with secure_delete explicitly off (Debian's SQLite has it on by
///   default, which hid this defect once).
/// - key_in_header: message key sent in a debug header the server logs.
/// - base64_only: body base64-encoded, not encrypted.
/// - gzip_only: body gzip-compressed and base64-encoded, not encrypted.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

final _rnd = Random.secure();
List<int> _bytes(int n) => List.generate(n, (_) => _rnd.nextInt(256));
final _aes = AesGcm.with256bits();

Future<String> _enc(List<int> key, String pt) async {
  final nonce = _bytes(12);
  final box = await _aes.encrypt(
    utf8.encode(pt),
    secretKey: SecretKey(key),
    nonce: nonce,
  );
  return base64.encode([...nonce, ...box.cipherText, ...box.mac.bytes]);
}

Future<String> _decAes(List<int> key, String ct) async {
  final raw = base64.decode(ct);
  final box = SecretBox(
    raw.sublist(12, raw.length - 16),
    nonce: raw.sublist(0, 12),
    mac: Mac(raw.sublist(raw.length - 16)),
  );
  return utf8.decode(await _aes.decrypt(box, secretKey: SecretKey(key)));
}

List<int> _unhex(String h) => [
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
];

Future<void> main(List<String> args) async {
  final server = args[0];
  final defect = Platform.environment['DEFECT'] ?? 'none';
  final keyHex = Platform.environment['TOY_KEY_HEX']!;
  final key = _unhex(keyHex);
  // Each canary is a short unique token wrapped in clinical-looking filler, so
  // a truncated 40-character preview still contains the whole token.
  final canaries = [
    for (final l in File(args[1]).readAsLinesSync())
      if (l.trim().isNotEmpty)
        '${l.split('\t')[1]} | pt febrile 39.4, HIV PEP day 3',
  ];
  final client = HttpClient();
  for (var i = 0; i < canaries.length; i++) {
    final c = canaries[i];
    final m = <String, Object>{'to': 'bob', 'n': i};
    m['body'] = switch (defect) {
      'plaintext_body' => c,
      'base64_only' => base64.encode(utf8.encode(c)),
      'gzip_only' => base64.encode(gzip.encode(utf8.encode(c))),
      _ => await _enc(key, c),
    };
    if (i == 0) {
      m['attachment'] = defect == 'plaintext_attachment'
          ? c
          : await _enc(key, c);
    }
    if (defect == 'preview_leak') m['preview'] = c.substring(0, 40);
    final req = await client.post(server, 8080, '/send');
    req.headers.contentType = ContentType.json;
    if (defect == 'key_in_header') req.headers.set('X-Debug-Key', keyHex);
    req.write(jsonEncode(m));
    await (await req.close()).drain<void>();
  }
  final res = await (await client.get(server, 8080, '/fetch/bob')).close();
  final rows = jsonDecode(await utf8.decoder.bind(res).join()) as List<dynamic>;
  client.close();

  Future<String> dec(String ct) async => switch (defect) {
    'plaintext_body' => ct,
    'base64_only' => utf8.decode(base64.decode(ct)),
    'gzip_only' => utf8.decode(gzip.decode(base64.decode(ct))),
    _ => await _decAes(key, ct),
  };
  final local = sqlite3.open(
    Platform.environment['TOY_LOCAL_DB'] ?? '/work/client.db',
  );
  if (defect == 'purge_unlink_only') {
    local
      ..execute('pragma secure_delete = off')
      ..execute('create table hist (id integer primary key, body text)');
    for (final r in rows) {
      local.execute('insert into hist (body) values (?)', [
        await dec((r as Map)['body'] as String),
      ]);
    }
    local.execute('delete from hist'); // unlink only: pages keep the bytes
  } else {
    local
      ..execute('pragma secure_delete = on')
      ..execute(
        'create table hist (id integer primary key, ct text, key_id integer)',
      )
      ..execute('create table keys (id integer primary key, k blob)');
    for (final r in rows) {
      final mk = _bytes(32);
      local.execute('insert into keys (k) values (?)', [mk]);
      final kid = local.lastInsertRowId;
      local.execute('insert into hist (ct, key_id) values (?, ?)', [
        await _enc(mk, await dec((r as Map)['body'] as String)),
        kid,
      ]);
    }
    local
      ..execute('delete from keys') // crypto-erase: ciphertext left, keys gone
      ..execute('vacuum');
  }
  local.close();
  stdout.writeln(
    jsonEncode({
      'defect': defect,
      'sent': canaries.length,
      'fetched': rows.length,
    }),
  );
}
