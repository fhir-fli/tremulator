import 'dart:convert';
import 'dart:typed_data';

import 'package:openmls/openmls.dart';

/// The one cipher suite every conversation uses.
///
/// RFC 9420 section 17.1, read verbatim from rfc9420.txt (rfc-editor.org,
/// 2026-10-06): "The mandatory-to-implement cipher suite for MLS 1.0 is
/// MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519 ... MLS clients MUST
/// implement this cipher suite." Its registered value is 0x0001.
const MlsCiphersuite suite =
    MlsCiphersuite.mls128DhkemX25519Aes128GcmSha256Ed25519;

/// The registered value of [suite], for the capabilities list.
const int suiteValue = 0x0001;

/// A phone's signing identity: who it is, and the key it signs with.
///
/// The private half lives in [secret]. The app keeps it in the platform's
/// secure storage and hands it back on every launch. It is never written by
/// this package and never leaves the phone.
class Identity {
  Identity._({
    required this.name,
    required this.publicKey,
    required this.secret,
  });

  /// Restores an identity from what the app stored.
  factory Identity.restore({
    required String name,
    required Uint8List publicKey,
    required Uint8List secret,
  }) => Identity._(name: name, publicKey: publicKey, secret: secret);

  /// Makes a brand-new identity for [name] (a device id, not a person's
  /// name: one phone, one identity). Loads the library first, so this is the
  /// one call that can be made before any [KeyStore] is open.
  static Future<Identity> create(String name) async {
    await Openmls.init();
    final pair = MlsSignatureKeyPair.generate(ciphersuite: suite);
    final public = pair.publicKey();
    final secret = serializeSigner(
      ciphersuite: suite,
      privateKey: pair.privateKey(),
      publicKey: public,
    );
    return Identity._(name: name, publicKey: public, secret: secret);
  }

  /// The device id this identity signs as.
  final String name;

  /// The public signing key. Safe to publish; the roster carries it.
  final Uint8List publicKey;

  /// The private signing key in the library's own serialised form.
  /// Store it in secure storage. Never log it.
  final Uint8List secret;

  /// [name] as the bytes the library binds into every signature.
  Uint8List get credentialIdentity => Uint8List.fromList(utf8.encode(name));
}

/// The name bound into a member's credential, as a string.
String nameFromCredential(List<int> credentialBytes) => utf8.decode(
  MlsCredential.deserialize(
    bytes: Uint8List.fromList(credentialBytes),
  ).identity(),
);
