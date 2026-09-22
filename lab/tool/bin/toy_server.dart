/// Toy relay server for the adversary-harness mutation test. It is NOT
/// tremulator: it exists so the scanner can be shown to catch known defects.
/// Stores whatever it receives in SQLite, logs request headers, serves
/// fetches. Honest and dumb, as the real delivery service should be.
/// Environment: TOY_DB, TOY_LOG.
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

Future<void> main() async {
  final db = sqlite3.open(Platform.environment['TOY_DB'] ?? '/work/server.db')
    ..execute(
      'create table if not exists msg '
      '(id integer primary key, recipient text, payload text)',
    );
  final log = File(
    Platform.environment['TOY_LOG'] ?? '/work/server.log',
  ).openWrite(mode: FileMode.append);
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  await for (final req in server) {
    if (req.method == 'POST' && req.uri.path == '/send') {
      final headers = <String, String>{};
      req.headers.forEach((k, v) => headers[k] = v.join(','));
      log.writeln(jsonEncode({'path': req.uri.path, 'headers': headers}));
      await log.flush();
      final body = await utf8.decoder.bind(req).join();
      final m = jsonDecode(body) as Map<String, dynamic>;
      db.execute('insert into msg (recipient, payload) values (?, ?)', [
        m['to'],
        body,
      ]);
      req.response.write('ok');
    } else if (req.method == 'GET' && req.uri.path.startsWith('/fetch/')) {
      final who = req.uri.pathSegments.last;
      final rows = db
          .select('select payload from msg where recipient = ?', [who])
          .map((r) => jsonDecode(r['payload'] as String))
          .toList();
      req.response.write(jsonEncode(rows));
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  }
}
