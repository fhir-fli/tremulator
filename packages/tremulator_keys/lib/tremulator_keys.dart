/// Each phone's keys, and all encryption and decryption, for tremulator.
///
/// This is the only package in the repo that imports `openmls`. Everything
/// else talks to [KeyStore] and [Conversation] in plain terms: make a key
/// package, start or join a conversation, encrypt, receive. If the library
/// underneath ever has to change, this package is rewritten and nothing
/// else moves (DECISIONS.md D16).
library;

export 'src/conversation.dart';
export 'src/errors.dart';
export 'src/identity.dart';
export 'src/key_store.dart';
export 'src/peek.dart';
