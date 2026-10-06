import 'dart:convert';

import 'package:http/http.dart' as http;

/// Signs in to a fhirant server with a username and password and returns the
/// bearer token. fhirant's `POST /auth/login` answers `{"token": ...}`
/// (`login_handler.dart`, read 2026-10-06).
Future<String> login({
  required Uri base,
  required String username,
  required String password,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final r = await c
      .post(
        base.replace(path: '${base.path}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      )
      .timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) {
    throw MailboxError('login failed: ${r.statusCode} ${r.body}');
  }
  final token = (jsonDecode(r.body) as Map<String, dynamic>)['token'];
  if (token is! String) {
    throw const MailboxError('login answered without a token');
  }
  return token;
}

/// Registers an account. The first account on a fresh server needs no
/// authority (fhirant `register_handler.dart`: "if no users exist, anyone can
/// register and is forced to admin role"); later ones need an admin's [token].
Future<void> register({
  required Uri base,
  required String username,
  required String password,
  String? token,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final r = await c
      .post(
        base.replace(path: '${base.path}/auth/register'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'username': username, 'password': password}),
      )
      .timeout(const Duration(seconds: 30));
  if (r.statusCode != 200 && r.statusCode != 201) {
    throw MailboxError('register failed: ${r.statusCode} ${r.body}');
  }
}

/// Anything the server refused, with its words.
class MailboxError implements Exception {
  /// Wraps [message].
  const MailboxError(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'MailboxError: $message';
}
