import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// The kept-open connection that tells the phone something arrived (D13).
///
/// fhirant's R4 subscription websocket (`websocket_subscriptions.dart`, read
/// 2026-10-06): the client sends `bind :id`, the server answers `bound :id`,
/// then sends `ping :id` each time a resource matching the subscription is
/// written. No payload travels; the phone collects afterwards.
class Wakeup {
  Wakeup._(this.subscriptionId, this._channel, this._pings);

  /// The Subscription on the server this socket is bound to.
  final String subscriptionId;
  final WebSocketChannel _channel;
  final StreamController<void> _pings;

  /// One event per `ping`.
  Stream<void> get pings => _pings.stream;

  /// Connects to [socket] (ws://host:port/ws) and binds [subscriptionId].
  /// Returns once the server has answered `bound`.
  static Future<Wakeup> bind({
    required Uri socket,
    required String subscriptionId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final channel = WebSocketChannel.connect(socket);
    await channel.ready.timeout(timeout);
    final pings = StreamController<void>.broadcast();
    final bound = Completer<void>();
    channel.stream.listen(
      (message) {
        if (message is! String) {
          return;
        }
        final t = message.trim();
        if (t == 'bound $subscriptionId' && !bound.isCompleted) {
          bound.complete();
        } else if (t == 'ping $subscriptionId') {
          pings.add(null);
        }
      },
      onDone: pings.close,
      onError: (Object e) {
        if (!bound.isCompleted) {
          bound.completeError(e);
        }
        pings.addError(e);
      },
    );
    channel.sink.add('bind $subscriptionId');
    await bound.future.timeout(timeout);
    return Wakeup._(subscriptionId, channel, pings);
  }

  /// Drops the connection.
  Future<void> close() async {
    await _channel.sink.close();
    await _pings.close();
  }
}
