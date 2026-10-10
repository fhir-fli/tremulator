import 'package:flutter_test/flutter_test.dart';
import 'package:tremulator_calls/tremulator_calls.dart';

void main() {
  test('an offer, an answer and a hang-up survive the round trip', () {
    for (final s in const [
      Signal(type: SignalType.offer, call: 'c1', sdp: 'v=0\r\n'),
      Signal(type: SignalType.answer, call: 'c1', sdp: 'v=0\r\n'),
      Signal(type: SignalType.hangup, call: 'c1'),
    ]) {
      final back = Signal.decode(s.encode());
      expect((back.type, back.call, back.sdp), (s.type, s.call, s.sdp));
    }
  });

  test('malformed setup is a FormatException, never a crash', () {
    for (final text in [
      'not json',
      '[1]',
      '{"call":"c1","sdp":"v=0"}',
      '{"type":"ring","call":"c1"}',
      '{"type":"offer","sdp":"v=0"}',
      '{"type":"offer","call":"c1"}',
      '{"type":"answer","call":"c1","sdp":7}',
      '{"type":"hangup","call":"c1","sdp":"v=0"}',
    ]) {
      expect(
        () => Signal.decode(text),
        throwsA(isA<FormatException>()),
        reason: text,
      );
    }
  });
}
