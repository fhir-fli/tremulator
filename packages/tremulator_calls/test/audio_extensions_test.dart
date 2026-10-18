import 'package:flutter_test/flutter_test.dart';
import 'package:tremulator_calls/tremulator_calls.dart';

// The audio and video sections as libwebrtc wrote them in calls22 (header
// extensions and Opus lines only), and a data section.
// As calls22's descriptions wrote it.
const _twcc =
    'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01';

const _sdp =
    'v=0\r\n'
    'o=- 1 2 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111 63\r\n'
    'a=mid:0\r\n'
    'a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\n'
    'a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\n'
    'a=extmap:3 $_twcc\r\n'
    'a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\r\n'
    'a=rtpmap:111 opus/48000/2\r\n'
    'a=rtcp-fb:111 transport-cc\r\n'
    'a=fmtp:111 minptime=10;useinbandfec=1\r\n'
    'a=rtpmap:63 red/48000/2\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
    'a=mid:1\r\n'
    'a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\r\n'
    'a=extmap:3 $_twcc\r\n'
    'a=rtpmap:96 VP8/90000\r\n'
    'a=rtcp-fb:96 transport-cc\r\n'
    'm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n'
    'a=mid:2\r\n';

void main() {
  test('nothing dropped, nothing changed', () {
    expect(const AudioExtensions().applyTo(_sdp), _sdp);
  });

  test('the send time and congestion feedback leave the audio section, and '
      'stay in the video section', () {
    final out = const AudioExtensions(
      drop: {AudioExtensions.absSendTime, AudioExtensions.transportCc},
    ).applyTo(_sdp);
    final video = out.indexOf('m=video');
    final audio = out.substring(0, video);
    expect(audio, isNot(contains('abs-send-time')));
    expect(audio, isNot(contains('transport-wide-cc')));
    expect(audio, isNot(contains('a=rtcp-fb:111 transport-cc')));
    expect(audio, contains('ssrc-audio-level'));
    expect(audio, contains('sdes:mid'));
    expect(out.substring(video), _sdp.substring(_sdp.indexOf('m=video')));
    // Three lines fewer, nothing else touched.
    expect(out.split('\r\n').length, _sdp.split('\r\n').length - 3);
  });

  test('a description written with plain newlines keeps them', () {
    final lf = _sdp.replaceAll('\r\n', '\n');
    final out = const AudioExtensions(
      drop: {AudioExtensions.transportCc},
    ).applyTo(lf);
    expect(out, isNot(contains('\r\n')));
    expect(out, isNot(contains('a=rtcp-fb:111 transport-cc')));
    expect(out, contains('a=rtcp-fb:96 transport-cc'));
  });
}
