import 'package:flutter_test/flutter_test.dart';
import 'package:tremulator_calls/tremulator_calls.dart';

void main() {
  test('an offer, an answer and a hang-up survive the round trip', () {
    for (final s in const [
      Signal(type: SignalType.offer, call: 'c1', sdp: 'v=0\r\n', number: 0),
      Signal(type: SignalType.answer, call: 'c1', sdp: 'v=0\r\n', number: 3),
      Signal(type: SignalType.hangup, call: 'c1'),
    ]) {
      final back = Signal.decode(s.encode());
      expect(
        (back.type, back.call, back.sdp, back.number),
        (s.type, s.call, s.sdp, s.number),
      );
    }
  });

  test('malformed setup is a FormatException, never a crash', () {
    for (final text in [
      'not json',
      '[1]',
      '{"call":"c1","sdp":"v=0"}',
      '{"type":"ring","call":"c1"}',
      '{"type":"offer","sdp":"v=0","n":0}',
      '{"type":"offer","call":"c1","n":0}',
      '{"type":"answer","call":"c1","sdp":7,"n":0}',
      '{"type":"hangup","call":"c1","sdp":"v=0"}',
      // the offer's number: missing, negative, not a whole number
      '{"type":"offer","call":"c1","sdp":"v=0"}',
      '{"type":"answer","call":"c1","sdp":"v=0","n":-1}',
      '{"type":"offer","call":"c1","sdp":"v=0","n":"1"}',
      '{"type":"offer","call":"c1","sdp":"v=0","n":1.5}',
      '{"type":"hangup","call":"c1","n":0}',
    ]) {
      expect(
        () => Signal.decode(text),
        throwsA(isA<FormatException>()),
        reason: text,
      );
    }
  });
}
