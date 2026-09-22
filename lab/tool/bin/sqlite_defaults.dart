/// Print the SQLite version, the secure_delete default and the SECURE_DELETE
/// compile option of the SQLite that package:sqlite3 bundles. A plain DELETE
/// only zeroes freed pages if secure_delete is on; Debian's system SQLite has
/// it on, and that hid a purge defect once (docs/GATE1.md). Gate 3 must run
/// the same check on the real client's SQLite or SQLCipher build.
library;

import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.openInMemory();
  final v = db.select('select sqlite_version() as v').first['v'];
  final sd = db.select('pragma secure_delete').first.values.first;
  final opts = db
      .select('pragma compile_options')
      .map((r) => r.values.first.toString())
      .where((o) => o.contains('SECURE'))
      .toList();
  print('sqlite $v | default secure_delete = $sd | compile options: $opts');
  db.close();
}
