import 'package:flutter_test/flutter_test.dart';
import 'package:tremulator_calls/tremulator_calls.dart';

// An audio and a video section in libwebrtc's shape (unified plan, Opus as
// payload type 111 with its usual fmtp line), and a data section.
const _sdp =
    'v=0\r\n'
    'o=- 1 2 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111 63 9\r\n'
    'a=mid:0\r\n'
    'a=rtpmap:111 opus/48000/2\r\n'
    'a=rtcp-fb:111 transport-cc\r\n'
    'a=fmtp:111 minptime=10;useinbandfec=1\r\n'
    'a=rtpmap:63 red/48000/2\r\n'
    'a=fmtp:63 111/111\r\n'
    'a=rtpmap:9 G722/8000\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
    'a=mid:1\r\n'
    'a=rtpmap:96 VP8/90000\r\n'
    'm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n'
    'a=mid:2\r\n';

List<String> _lines(String sdp) => sdp.split('\r\n');

void main() {
  test('nothing asked, nothing changed', () {
    expect(const OpusReceive().applyTo(_sdp), _sdp);
  });

  test("the bitrate goes in Opus's fmtp line, other parameters kept", () {
    final out = const OpusReceive(maxAverageBitrate: 20000).applyTo(_sdp);
    expect(
      _lines(out),
      contains('a=fmtp:111 minptime=10;useinbandfec=1;maxaveragebitrate=20000'),
    );
    // Only that line changed.
    expect(_lines(out).length, _lines(_sdp).length);
    expect(out.replaceFirst(';maxaveragebitrate=20000', ''), _sdp);
  });

  test('a bitrate already there is replaced, not repeated', () {
    final once = const OpusReceive(maxAverageBitrate: 20000).applyTo(_sdp);
    final twice = const OpusReceive(maxAverageBitrate: 16000).applyTo(once);
    expect(
      _lines(twice).where((l) => l.contains('maxaveragebitrate')),
      ['a=fmtp:111 minptime=10;useinbandfec=1;maxaveragebitrate=16000'],
    );
  });

  test('ptime goes in the audio section only, once', () {
    final out = const OpusReceive(ptime: 60).applyTo(
      _sdp.replaceFirst('a=mid:0\r\n', 'a=mid:0\r\na=ptime:20\r\n'),
    );
    final lines = _lines(out);
    expect(lines.where((l) => l.startsWith('a=ptime:')), ['a=ptime:60']);
    final video = lines.indexWhere((l) => l.startsWith('m=video'));
    expect(lines.indexOf('a=ptime:60'), lessThan(video));
  });

  test('an Opus section with no fmtp line gets one', () {
    final bare = _sdp.replaceFirst(
      'a=fmtp:111 minptime=10;useinbandfec=1\r\n',
      '',
    );
    final out = const OpusReceive(
      maxAverageBitrate: 20000,
      ptime: 60,
    ).applyTo(bare);
    final lines = _lines(out);
    final at = lines.indexOf('a=rtpmap:111 opus/48000/2');
    expect(lines.sublist(at + 1, at + 3), [
      'a=fmtp:111 maxaveragebitrate=20000',
      'a=ptime:60',
    ]);
  });

  test('a description without Opus is left alone', () {
    final noOpus = _sdp
        .replaceFirst('a=rtpmap:111 opus/48000/2\r\n', '')
        .replaceFirst('a=fmtp:111 minptime=10;useinbandfec=1\r\n', '');
    expect(
      const OpusReceive(maxAverageBitrate: 20000, ptime: 60).applyTo(noOpus),
      noOpus,
    );
  });
}
