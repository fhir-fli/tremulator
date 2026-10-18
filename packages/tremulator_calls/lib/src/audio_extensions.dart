/// RTP header extensions this phone leaves out of the audio section of each
/// description it sends (RFC 8285, read whole from rfc-editor.org,
/// 2026-10-18). Section 7: "An answerer that has no desire to receive the
/// extension or does not understand the extension SHOULD remove it from the
/// SDP answer"; and "Only extensions that appeared with an identifier in the
/// valid range in SDP originated by the sender can be sent." The same
/// section also lets either party send extensions not negotiated, so
/// whether libwebrtc stops sending one is measured in the lab, not assumed.
///
/// Why: in calls22 (the relay on a 50 kbit/s link, sound only), the silent
/// phone sent 25 packets a second, about 22 of them padding, and opened the
/// call with 99 and 111 padding packets in two seconds (26 kB): 148 kB of
/// its 596 kB. libwebrtc pads to probe the link, which needs a send time
/// and congestion feedback on the packets ([absSendTime], [transportCc]).
class AudioExtensions {
  /// Drops the extensions whose URIs are in [drop].
  const AudioExtensions({this.drop = const {}});

  /// The send time on each packet, for the receiver's link estimate.
  static const absSendTime =
      'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time';

  /// A sequence number across all streams, for the sender's link estimate
  /// from the receiver's feedback (`a=rtcp-fb:<pt> transport-cc`).
  static const transportCc =
      'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01';

  /// The extension URIs left out.
  final Set<String> drop;

  /// [sdp] without the `a=extmap` lines for [drop] in audio sections, and
  /// without their `a=rtcp-fb:<pt> transport-cc` lines when [transportCc]
  /// is dropped. Everything else is left as it was.
  String applyTo(String sdp) {
    if (drop.isEmpty) {
      return sdp;
    }
    final eol = sdp.contains('\r\n') ? '\r\n' : '\n';
    final out = <String>[];
    var audio = false;
    for (final l in sdp.split(eol)) {
      if (l.startsWith('m=')) {
        audio = l.startsWith('m=audio');
      } else if (audio && _dropped(l)) {
        continue;
      }
      out.add(l);
    }
    return out.join(eol);
  }

  bool _dropped(String line) {
    if (line.startsWith('a=extmap:')) {
      final uri = line.split(' ').elementAtOrNull(1);
      return drop.contains(uri);
    }
    return drop.contains(transportCc) &&
        line.startsWith('a=rtcp-fb:') &&
        line.endsWith(' transport-cc');
  }
}
