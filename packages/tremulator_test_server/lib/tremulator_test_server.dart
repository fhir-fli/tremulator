import 'dart:io';

import 'package:drift/native.dart';
import 'package:fhirant_db/fhirant_db.dart';
import 'package:fhirant_server/fhirant_server.dart';

/// A fhirant started in this process on a free port.
class TestServer {
  TestServer._(this.server, this.db, this.base);

  /// The running server.
  final FhirAntServer server;

  /// Its store, in memory.
  final FhirAntDb db;

  /// Where to reach it.
  final Uri base;

  /// Starts one. [devMode] true turns authentication off.
  static Future<TestServer> start({bool devMode = true}) async {
    final db = FhirAntDb(NativeDatabase.memory());
    await db.initialize();
    final server = FhirAntServer(
      db,
      jwtSecret: 'tremulator-test-secret-0123456789abcdef0123456789abcdef',
      devMode: devMode,
    );
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    await server.startHttp(port);
    return TestServer._(server, db, Uri.parse('http://127.0.0.1:$port'));
  }

  /// Stops the server and closes the store.
  Future<void> stop() async {
    await server.stop();
    await db.close();
  }
}
