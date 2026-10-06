/// What a blob on the server is. Carried as `Communication.category`, since
/// a welcome cannot be told from its header and the server must not decrypt.
enum Label {
  /// A phone's single-use public key bundle, waiting to be taken.
  keyPackage('key-package'),

  /// What a newly added phone needs to join a conversation.
  welcome('welcome'),

  /// A change to a conversation, with the snapshot an out-of-step phone
  /// rejoins from. One per epoch; the server keeps the first.
  commit('commit'),

  /// A text or other application message.
  message('message'),

  /// Call setup, itself encrypted.
  call('call');

  const Label(this.code);

  /// The code on the wire.
  final String code;

  /// The label for [code], or null.
  static Label? fromCode(String? code) {
    for (final l in values) {
      if (l.code == code) {
        return l;
      }
    }
    return null;
  }
}

/// The code system every [Label] is drawn from.
const labelSystem = 'https://tremulator.fhirfli.dev/CodeSystem/blob-label';

/// `Device.identifier` system for the phone's own name (its device id).
const deviceNameSystem = 'https://tremulator.fhirfli.dev/device-name';

/// `Device.identifier` system for the phone's public signing key, base64url.
const signingKeySystem = 'https://tremulator.fhirfli.dev/signing-key';

/// `Communication.identifier` system for a commit: value
/// `<conversation>:<epoch>`,
/// where conversation is the hex of its id and epoch is the one the commit
/// produces. The server keeps one per value (conditional create).
const commitSystem = 'https://tremulator.fhirfli.dev/commit';

/// Media type of an MLS message, RFC 9420 section 17.10 (read from the
/// rfc-editor.org page 2026-10-06: type "message", subtype "mls").
const mlsMediaType = 'message/mls';

/// Media type for the raw key tree beside a commit.
const octetStream = 'application/octet-stream';
