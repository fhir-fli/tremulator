import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:tremulator_keys/tremulator_keys.dart';
import 'package:tremulator_mailbox/tremulator_mailbox.dart';

/// What the client reports as it goes. Every event is one line in the log.
typedef Report = void Function(Map<String, Object?> event);

/// A decrypted message handed to the caller.
class Incoming {
  /// From [conversation], sent by Device [from].
  const Incoming({
    required this.conversation,
    required this.from,
    required this.text,
  });

  /// The conversation id.
  final Uint8List conversation;

  /// The sender's Device id, if the envelope said.
  final String? from;

  /// The plaintext.
  final String text;
}

/// One phone's worth of behaviour, with no screen.
///
/// Composition only: every cryptographic call is in `tremulator_keys`, every
/// server call in `tremulator_mailbox`. This class decides the order.
class Client {
  Client._({
    required this.keys,
    required this.mailbox,
    required this.report,
  });

  /// The key store.
  final KeyStore keys;

  /// The server connection.
  final Mailbox mailbox;

  /// Where events go.
  final Report report;

  /// Conversations this client is in, by hex id.
  final Map<String, Conversation> _conversations = {};

  /// Decrypted messages, as they arrive.
  Stream<Incoming> get incoming => _incoming.stream;
  final StreamController<Incoming> _incoming = StreamController.broadcast();

  Wakeup? _wakeup;
  bool _collecting = false;
  bool _again = false;
  Future<int>? _inFlight;

  /// Opens the keys, registers the Device and tops the key package stock up
  /// to [stock].
  static Future<Client> start({
    required KeyStore keys,
    required Mailbox mailbox,
    int stock = 5,
    Report? report,
  }) async {
    final client = Client._(
      keys: keys,
      mailbox: mailbox,
      report: report ?? (_) {},
    );
    final deviceId = await mailbox.register(
      deviceName: keys.identity.name,
      publicKey: keys.identity.publicKey,
    );
    client.report({'event': 'registered', 'device': deviceId});
    final packages = [
      for (var i = 0; i < stock; i++) await keys.makeKeyPackage(),
    ];
    await mailbox.publishKeyPackages(packages);
    client.report({'event': 'key-packages-published', 'count': stock});
    return client;
  }

  /// This phone's Device id on the server.
  String get device => mailbox.device;

  /// Starts a conversation with the phone named [peerName]: takes one of its
  /// key packages, adds it, sends the welcome, and offers the commit. Returns
  /// the conversation.
  Future<Conversation> open(String peerName) async {
    final peer = await mailbox.findDevice(peerName);
    if (peer == null) {
      throw MailboxError('no device named $peerName');
    }
    final kp = await mailbox.takeKeyPackage(peer);
    if (kp == null) {
      throw MailboxError('$peerName has no key packages left');
    }
    final conversation = await keys.start();
    final change = await conversation.add([kp]);
    _conversations[conversationKey(conversation.id)] = conversation;
    await mailbox.send(to: peer, label: Label.welcome, bytes: change.welcome!);
    final accepted = await _offer(conversation, change, [peer]);
    report({
      'event': 'opened',
      'conversation': conversationKey(conversation.id),
      'peer': peer,
      'commit-accepted': accepted,
    });
    return conversation;
  }

  /// Encrypts [text] and sends it to every other member of [conversation].
  Future<void> send(Conversation conversation, String text) async {
    final blob = await conversation.encrypt(
      Uint8List.fromList(utf8.encode(text)),
    );
    for (final to in await _others(conversation)) {
      await mailbox.send(to: to, label: Label.message, bytes: blob);
    }
  }

  /// Rotates this phone's keys in [conversation] and offers the commit. If
  /// another phone's commit for the same epoch got there first, this phone
  /// is out of step and rejoins at once.
  Future<void> refreshKeys(Conversation conversation) async {
    final change = await conversation.refreshKeys();
    final accepted = await _offer(
      conversation,
      change,
      await _others(conversation),
    );
    report({
      'event': 'refreshed-keys',
      'conversation': conversationKey(conversation.id),
      'commit-accepted': accepted,
    });
    if (!accepted) {
      await _catchUp(conversation);
    }
  }

  /// Collects everything waiting on the server, in order: welcomes join,
  /// messages decrypt to [incoming], and each is acknowledged once handled.
  /// Then walks every conversation forward through newer commits. A call
  /// while one runs returns 0 at once and makes the running one go round
  /// again when it finishes, so nothing that arrived meanwhile waits for the
  /// next wake-up (run4 P2: two messages waited 74 s for the final sweep).
  Future<int> collect() {
    if (_collecting) {
      _again = true;
      return Future.value(0);
    }
    _collecting = true;
    return _inFlight = _collectNow();
  }

  Future<int> _collectNow() async {
    try {
      var handled = 0;
      for (final e in await mailbox.collect()) {
        try {
          await _handle(e);
          handled++;
        } on KeysError catch (err) {
          report({
            'event': 'undecryptable',
            'id': e.id,
            'label': e.label.code,
            'error': err.message,
          });
        }
        await mailbox.acknowledge(e.id);
      }
      for (final c in _conversations.values.toList()) {
        try {
          handled += await _catchUp(c);
        } on KeysError catch (err) {
          report({
            'event': 'catch-up-failed',
            'conversation': conversationKey(c.id),
            'error': err.message,
          });
        }
      }
      if (_again) {
        _again = false;
        return handled + await _collectNow();
      }
      return handled;
    } finally {
      _collecting = false;
    }
  }

  /// Holds the wake-up connection open and collects on every ping.
  Future<void> listen() async {
    _wakeup = await mailbox.wakeups();
    report({'event': 'listening', 'subscription': _wakeup!.subscriptionId});
    _wakeup!.pings.listen((_) {
      unawaited(collect());
    });
  }

  /// Closes everything, after any collect still running.
  Future<void> close() async {
    await _wakeup?.close();
    await _inFlight;
    await _incoming.close();
    mailbox.close();
    await keys.close();
  }

  Future<void> _handle(Envelope e) async {
    switch (e.label) {
      case Label.welcome:
        final c = await keys.join(e.bytes);
        _conversations[conversationKey(c.id)] = c;
        report({
          'event': 'joined',
          'conversation': conversationKey(c.id),
          'from': e.from,
        });
      case Label.message:
      case Label.call:
        final id = peekConversationId(e.bytes);
        var c = _conversations[conversationKey(id)];
        if (c == null) {
          // Known to the store (this phone was in it before a restart), or
          // not ours at all: epoch() throws for an unknown conversation and
          // the caller reports the blob as undecryptable.
          c = keys.conversation(id);
          await c.epoch();
          _conversations[conversationKey(id)] = c;
        }
        await _catchUp(c);
        final r = await c.receive(e.bytes);
        if (r is ReceivedMessage) {
          _incoming.add(
            Incoming(
              conversation: id,
              from: e.from,
              text: utf8.decode(r.bytes),
            ),
          );
        }
      case Label.keyPackage:
      case Label.commit:
        report({'event': 'unexpected-label', 'label': e.label.code});
    }
  }

  /// Checks this phone is in step, then applies every commit the server
  /// holds beyond its epoch. Out of step means rejoin from the newest
  /// snapshot.
  Future<int> _catchUp(Conversation c) async {
    // Self-check first: the commit that produced this phone's current epoch
    // must carry the confirmation tag this phone holds. If not, this phone
    // applied a commit the server never took (its own, rejected or never
    // offered) and is out of step.
    final current = await c.epoch();
    if (current > BigInt.zero) {
      final mine = await mailbox.commitAfter(c.id, current - BigInt.one);
      if (mine != null &&
          mine.extra.length > 2 &&
          !_sameBytes(mine.extra[2], await c.confirmationTag())) {
        report({
          'event': 'out-of-step',
          'conversation': conversationKey(c.id),
          'epoch': current.toString(),
          'error': "confirmation tag differs from the server's commit",
        });
        return _rejoin(c, mine, current);
      }
    }
    var applied = 0;
    while (true) {
      final epoch = await c.epoch();
      final next = await mailbox.commitAfter(c.id, epoch);
      if (next == null) {
        return applied;
      }
      try {
        await c.receive(next.bytes);
        applied++;
      } on KeysError catch (err) {
        report({
          'event': 'out-of-step',
          'conversation': conversationKey(c.id),
          'epoch': epoch.toString(),
          'error': err.message,
        });
        return applied + await _rejoin(c, next, epoch + BigInt.one);
      }
    }
  }

  /// Rejoins [stale] from the newest snapshot the server holds. [from] is a
  /// commit the server holds and [produces] the epoch it leads to.
  Future<int> _rejoin(
    Conversation stale,
    Envelope from,
    BigInt produces,
  ) async {
    // Walk to the newest commit first: the snapshot to rejoin from is the one
    // beside the last commit the server holds. `commitAfter(e)` answers the
    // commit that produces e + 1, so the walk counts epochs itself.
    var newest = from;
    var epoch = produces;
    while (true) {
      final next = await mailbox.commitAfter(stale.id, epoch);
      if (next == null) {
        break;
      }
      newest = next;
      epoch += BigInt.one;
    }
    await stale.destroy();
    final rejoined = await keys.rejoin(
      Snapshot(
        groupInfo: newest.extra[0],
        ratchetTree: newest.extra[1],
        confirmationTag: newest.extra[2],
      ),
    );
    final c = rejoined.conversation;
    _conversations[conversationKey(c.id)] = c;
    final accepted = await _offer(
      c,
      Change(commit: rejoined.commit, snapshot: await c.snapshot()),
      await _others(c),
    );
    report({
      'event': 'rejoined',
      'conversation': conversationKey(c.id),
      'epoch': (await c.epoch()).toString(),
      'commit-accepted': accepted,
    });
    return 1;
  }

  Future<bool> _offer(Conversation c, Change change, List<String> to) async =>
      mailbox.sendCommit(
        to: to,
        conversation: c.id,
        epoch: await c.epoch(),
        commit: change.commit,
        groupInfo: change.snapshot.groupInfo,
        ratchetTree: change.snapshot.ratchetTree,
        confirmationTag: change.snapshot.confirmationTag,
      );

  Future<List<String>> _others(Conversation c) async {
    final me = await c.ownIndex();
    final others = <String>[];
    for (final m in await c.members()) {
      if (m.index != me) {
        final d = await mailbox.findDevice(m.name);
        if (d == null) {
          report({'event': 'member-not-registered', 'name': m.name});
        } else {
          others.add(d);
        }
      }
    }
    return others;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
