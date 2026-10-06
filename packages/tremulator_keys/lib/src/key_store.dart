import 'dart:typed_data';

import 'package:openmls/openmls.dart';

import 'package:tremulator_keys/src/conversation.dart';
import 'package:tremulator_keys/src/errors.dart';
import 'package:tremulator_keys/src/identity.dart';

/// How long a key package is good for. RFC 9420 section 10.1 leaves the
/// value to the application; 90 days is a derived choice, not a measured one,
/// chosen so a stock refilled monthly never runs stale.
const Duration keyPackageLifetime = Duration(days: 90);

/// The capabilities every key package and leaf advertises: only the one cipher
/// suite. The library otherwise lists ten experimental post-quantum suites
/// (openmls 3.2.1 README, "What your peers see", read 2026-10-06). Versions,
/// proposals, extensions and credentials are left empty, which the library
/// maps to its defaults (`rust/src/api/types.rs`, `capabilities_to_native`).
/// RFC 9420 section 7.2, read verbatim from rfc9420.txt (rfc-editor.org,
/// 2026-10-06): the default proposal and extension types "are considered
/// "default" and MUST NOT be listed".
final MlsCapabilities ourCapabilities = MlsCapabilities(
  versions: Uint16List(0),
  ciphersuites: Uint16List.fromList([suiteValue]),
  extensions: Uint16List(0),
  proposals: Uint16List(0),
  credentials: Uint16List(0),
);

/// What rejoining produced: the conversation, now in step, and the commit
/// everyone else must receive.
class Rejoined {
  /// Bundles both.
  const Rejoined({required this.conversation, required this.commit});

  /// The conversation, at the new epoch.
  final Conversation conversation;

  /// Send to every member through the server.
  final Uint8List commit;
}

/// One phone's whole key state: an encrypted database on disk, opened with a
/// key the app keeps in secure storage, and the phone's [Identity].
class KeyStore {
  KeyStore._(this._engine, this.identity);

  final MlsEngine _engine;

  /// Who this phone signs as.
  final Identity identity;

  /// Opens (or creates) the database at [dbPath] with the 32-byte
  /// [storageKey]. Use `:memory:` for tests.
  static Future<KeyStore> open({
    required String dbPath,
    required Uint8List storageKey,
    required Identity identity,
  }) async {
    if (storageKey.length != 32) {
      throw const KeysError('storageKey must be 32 bytes');
    }
    await Openmls.init();
    final engine = await guarded(
      () => MlsEngine.create(dbPath: dbPath, encryptionKey: storageKey),
    );
    return KeyStore._(engine, identity);
  }

  /// Whether [close] has been called.
  bool get isClosed => _engine.isClosed();

  /// Releases the database and wipes the key from memory. Call on lock or
  /// background; [open] again on unlock.
  Future<void> close() => guarded(_engine.close);

  /// A fresh key package to publish. Single use, unless [lastResort], which
  /// the server hands out only when the stock is empty.
  Future<Uint8List> makeKeyPackage({bool lastResort = false}) =>
      guarded(() async {
        final r = await _engine.createKeyPackageWithOptions(
          ciphersuite: suite,
          signerBytes: identity.secret,
          credentialIdentity: identity.credentialIdentity,
          signerPublicKey: identity.publicKey,
          options: KeyPackageOptions(
            lifetimeSeconds: BigInt.from(keyPackageLifetime.inSeconds),
            lastResort: lastResort,
            capabilities: ourCapabilities,
          ),
        );
        return r.keyPackageBytes;
      });

  /// Starts a conversation with only this phone in it. Add others with
  /// [Conversation.add].
  Future<Conversation> start({Uint8List? id}) => guarded(() async {
    final r = await _engine.createGroupWithBuilder(
      config: _config(),
      signerBytes: identity.secret,
      credentialIdentity: identity.credentialIdentity,
      signerPublicKey: identity.publicKey,
      groupId: id,
      capabilities: ourCapabilities,
    );
    return conversation(r.groupId);
  });

  /// Joins the conversation a [welcome] invites this phone into.
  Future<Conversation> join(Uint8List welcome) => guarded(() async {
    final r = await _engine.joinGroupFromWelcome(
      config: _config(),
      welcomeBytes: welcome,
      signerBytes: identity.secret,
    );
    return conversation(r.groupId);
  });

  /// Rejoins a conversation this phone has fallen out of step with, from the
  /// newest [Snapshot] another member published (RFC 9420 section 12.4.3.2,
  /// external commit). Destroy the stale local state first with
  /// [Conversation.destroy].
  Future<Rejoined> rejoin(Snapshot snapshot) => guarded(() async {
    final r = await _engine.joinGroupExternalCommit(
      config: _config(),
      groupInfoBytes: snapshot.groupInfo,
      ratchetTreeBytes: snapshot.ratchetTree,
      signerBytes: identity.secret,
      credentialIdentity: identity.credentialIdentity,
      signerPublicKey: identity.publicKey,
    );
    return Rejoined(conversation: conversation(r.groupId), commit: r.commit);
  });

  /// A handle on a conversation already in the database.
  Conversation conversation(Uint8List id) =>
      Conversation.internal(engine: _engine, identity: identity, id: id);

  MlsGroupConfig _config() => MlsGroupConfig.defaultConfig(ciphersuite: suite);
}
