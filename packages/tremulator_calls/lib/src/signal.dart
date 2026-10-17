import 'dart:convert';

/// What a piece of call setup is.
enum SignalType {
  /// The caller's connection details. A call's first offer is number 0;
  /// each restart of the connection (see `Call`) sends the next number.
  offer,

  /// The callee's connection details, in reply to the offer of the same
  /// number.
  answer,

  /// Either side ending the call.
  hangup,
}

/// One piece of call setup. It travels as the plaintext of an encrypted
/// `call` message, so the server sees neither the connection details nor the
/// certificate fingerprint inside them.
///
/// The connection details are sent whole, once, after this phone has finished
/// finding its own addresses (no "trickle", RFC 8838): every mailbox message
/// costs at least one server round trip, seconds on the bad profiles, so one
/// offer and one answer beat a stream of address messages.
class Signal {
  /// A signal of [type] for call [call].
  const Signal({
    required this.type,
    required this.call,
    this.sdp,
    this.number,
  });

  /// Reads one from the plaintext of a `call` message.
  /// Throws [FormatException] if [text] is not one.
  factory Signal.decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) {
      throw FormatException('call setup is not an object', text);
    }
    final type = SignalType.values
        .where((t) => t.name == json['type'])
        .firstOrNull;
    final call = json['call'];
    final sdp = json['sdp'];
    final number = json['n'];
    if (type == null || call is! String) {
      throw FormatException('call setup lacks a type or a call id', text);
    }
    final needsSdp = type != SignalType.hangup;
    if (needsSdp ? sdp is! String : sdp != null) {
      throw FormatException(
        'an offer or answer carries a session description, a hang-up none',
        text,
      );
    }
    if (needsSdp ? (number is! int || number < 0) : number != null) {
      throw FormatException(
        'an offer or answer carries a number of 0 or more, a hang-up none',
        text,
      );
    }
    return Signal(
      type: type,
      call: call,
      sdp: sdp as String?,
      number: number as int?,
    );
  }

  /// What this is.
  final SignalType type;

  /// The call it belongs to, chosen by the caller.
  final String call;

  /// The session description (RFC 8866) for an offer or an answer.
  final String? sdp;

  /// Which offer of the call this is, or answers: 0 for the first, one more
  /// for each restart. A stale answer (one whose offer has been replaced) is
  /// recognised by it and ignored. None for a hang-up.
  final int? number;

  /// The plaintext for a `call` message.
  String encode() => jsonEncode({
    'type': type.name,
    'call': call,
    if (sdp != null) 'sdp': sdp,
    if (number != null) 'n': number,
  });
}
