import 'dart:typed_data';

import 'package:openmls/openmls.dart';

import 'package:tremulator_keys/src/errors.dart';
import 'package:tremulator_keys/src/identity.dart';

/// One member of a conversation, as the key tree sees them.
class Member {
  /// A row of the member list.
  const Member({
    required this.index,
    required this.name,
    required this.publicKey,
  });

  /// The member's position in the key tree. Needed to remove them.
  final int index;

  /// The device id bound into their credential.
  final String name;

  /// Their public signing key, to compare against the roster.
  final Uint8List publicKey;
}

/// A change to a conversation, already applied locally, to be sent on.
///
/// The library applies every change to this phone's state the moment it is
/// made (openmls_dart 3.2.1, `rust/src/api/engine.rs`, read 2026-10-06:
/// `add_members`, `remove_members`, `self_update` and `flexible_commit` all
/// call `merge_pending_commit` before returning). So a change cannot be held
/// back until the server accepts it. If the server rejects [commit] because
/// another member's change for the same epoch got there first, this phone is
/// out of step and must [KeyStore.rejoin] from the newest [Snapshot] another
/// member published. RFC 9750 section 5.2, read verbatim from rfc9750.txt
/// (rfc-editor.org, 2026-10-06): "the group must agree on a single MLS
/// Commit message that ends each epoch and begins the next one."
class Change {
  /// Bundles what a change produced.
  const Change({required this.commit, required this.snapshot, this.welcome});

  /// Send to every member through the server.
  final Uint8List commit;

  /// Send to the member being added, if the change added one.
  final Uint8List? welcome;

  /// Publish beside the commit so an out-of-step member can rejoin.
  final Snapshot snapshot;
}

/// What a member needs to rejoin a conversation it has fallen out of step
/// with: the signed group description for the current epoch and the key tree.
///
/// RFC 9420 section 12.4.3.2, read verbatim from rfc9420.txt
/// (rfc-editor.org, 2026-10-06): "a member of the group can enable new
/// clients to join by making a GroupInfo object available to them ... each
/// GroupInfo object can be used for one external join".
class Snapshot {
  /// Bundles both parts.
  const Snapshot({required this.groupInfo, required this.ratchetTree});

  /// The signed group description, with the external public key.
  final Uint8List groupInfo;

  /// The full key tree, so the joiner need not fetch it separately.
  final Uint8List ratchetTree;
}

/// What came out of [Conversation.receive].
sealed class Received {
  const Received({required this.epoch});

  /// The epoch the blob was written in.
  final BigInt epoch;
}

/// A decrypted application message.
class ReceivedMessage extends Received {
  /// A decrypted message from [senderIndex].
  const ReceivedMessage({
    required super.epoch,
    required this.bytes,
    required this.senderIndex,
  });

  /// The plaintext.
  final Uint8List bytes;

  /// The sender's position in the key tree, or null if unknown.
  final int? senderIndex;
}

/// A change to the conversation, now applied.
class ReceivedChange extends Received {
  /// A change from [senderIndex], applied; [stillMember] false means this
  /// phone was removed by it.
  const ReceivedChange({
    required super.epoch,
    required this.senderIndex,
    required this.stillMember,
  });

  /// Who made the change.
  final int? senderIndex;

  /// False when the change removed this phone.
  final bool stillMember;
}

/// A proposed change, not yet committed.
class ReceivedProposal extends Received {
  /// A proposal of [kind] from [senderIndex].
  const ReceivedProposal({
    required super.epoch,
    required this.senderIndex,
    required this.kind,
  });

  /// Who proposed it.
  final int? senderIndex;

  /// What was proposed.
  final MlsProposalType? kind;
}

/// One conversation this phone is a member of.
///
/// Every method goes through the engine the [KeyStore] opened; nothing is
/// cached here, so two [Conversation] objects for the same id are
/// interchangeable.
class Conversation {
  /// Internal: made by [KeyStore].
  Conversation.internal({
    required MlsEngine engine,
    required Identity identity,
    required this.id,
  }) : _engine = engine,
       _identity = identity;

  final MlsEngine _engine;
  final Identity _identity;

  /// The conversation's id, as the library assigned or as given at start.
  final Uint8List id;

  /// The current epoch. Every change advances it by one.
  Future<BigInt> epoch() => guarded(() => _engine.groupEpoch(groupIdBytes: id));

  /// Whether this phone is still a member.
  Future<bool> isMember() =>
      guarded(() => _engine.groupIsActive(groupIdBytes: id));

  /// Everyone in the conversation, in key-tree order.
  Future<List<Member>> members() => guarded(() async {
    final rows = await _engine.groupMembers(groupIdBytes: id);
    return [
      for (final m in rows)
        Member(
          index: m.index,
          name: nameFromCredential(m.credential),
          publicKey: m.signatureKey,
        ),
    ];
  });

  /// This phone's position in the key tree.
  Future<int> ownIndex() =>
      guarded(() => _engine.groupOwnIndex(groupIdBytes: id));

  /// Adds the phones whose [keyPackages] these are. Returns the commit for
  /// everyone and one welcome for the newcomers.
  Future<Change> add(List<Uint8List> keyPackages) => guarded(() async {
    final r = await _engine.addMembers(
      groupIdBytes: id,
      signerBytes: _identity.secret,
      keyPackagesBytes: keyPackages,
    );
    return Change(
      commit: r.commit,
      welcome: r.welcome,
      snapshot: await snapshot(),
    );
  });

  /// Removes the members at [indices] (from [members]).
  Future<Change> remove(List<int> indices) => guarded(() async {
    final r = await _engine.removeMembers(
      groupIdBytes: id,
      signerBytes: _identity.secret,
      memberIndices: indices,
    );
    return Change(commit: r.commit, snapshot: await snapshot());
  });

  /// Rotates this phone's keys. Everyone derives a new epoch key, so a copy
  /// of the old state cannot read what follows.
  Future<Change> refreshKeys() => guarded(() async {
    final r = await _engine.selfUpdate(
      groupIdBytes: id,
      signerBytes: _identity.secret,
    );
    return Change(commit: r.commit, snapshot: await snapshot());
  });

  /// The current [Snapshot], signed by this phone.
  Future<Snapshot> snapshot() => guarded(
    () async => Snapshot(
      groupInfo: await _engine.exportGroupInfo(
        groupIdBytes: id,
        signerBytes: _identity.secret,
      ),
      ratchetTree: await _engine.exportRatchetTree(groupIdBytes: id),
    ),
  );

  /// Encrypts [plaintext] for every current member.
  Future<Uint8List> encrypt(Uint8List plaintext) => guarded(() async {
    final r = await _engine.createMessage(
      groupIdBytes: id,
      signerBytes: _identity.secret,
      message: plaintext,
    );
    return r.ciphertext;
  });

  /// Decrypts or applies one blob collected from the server. Blobs must be
  /// handed in the order the server holds them.
  Future<Received> receive(Uint8List blob) => guarded(() async {
    final r = await _engine.processMessageWithInspect(
      groupIdBytes: id,
      messageBytes: blob,
    );
    switch (r.messageType) {
      case ProcessedMessageType.application:
        return ReceivedMessage(
          epoch: r.epoch,
          bytes: r.applicationMessage ?? Uint8List(0),
          senderIndex: r.senderIndex,
        );
      case ProcessedMessageType.stagedCommit:
        return ReceivedChange(
          epoch: r.epoch,
          senderIndex: r.senderIndex,
          stillMember: await isMember(),
        );
      case ProcessedMessageType.proposal:
        return ReceivedProposal(
          epoch: r.epoch,
          senderIndex: r.senderIndex,
          kind: r.proposalType,
        );
    }
  });

  /// Destroys this phone's state for the conversation, keys included, so
  /// anything still stored cannot be read (DECISIONS.md D8 addendum).
  Future<void> destroy() =>
      guarded(() => _engine.deleteGroup(groupIdBytes: id));
}
