/// Anything the encryption library refuses to do.
///
/// The library reports failures as plain strings. They are wrapped here so a
/// caller can catch one type and show the text, and so no caller has to know
/// what the library throws.
class KeysError implements Exception {
  /// Wraps [message].
  const KeysError(this.message);

  /// What went wrong, in the library's words.
  final String message;

  @override
  String toString() => 'KeysError: $message';
}

/// Runs [body] and turns whatever the library throws into a [KeysError].
Future<T> guarded<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on KeysError {
    rethrow;
  } catch (e) {
    throw KeysError('$e');
  }
}
