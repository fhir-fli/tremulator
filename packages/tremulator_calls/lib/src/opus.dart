/// How a phone asks the other phone to send its sound. These are the Opus
/// receive parameters of RFC 7587 (read whole from rfc-editor.org,
/// 2026-10-18): each is "a unidirectional receive-only parameter" (section
/// 7.1), carried in the description this phone sends, so it binds the other
/// phone's encoder and changes nothing in this phone's own description.
class OpusReceive {
  /// Asks for at most [maxAverageBitrate] bit/s and packets of [ptime] ms.
  /// Null leaves that parameter as the description has it.
  const OpusReceive({this.maxAverageBitrate, this.ptime});

  /// `maxaveragebitrate` (section 6.1): "The sender of the other side MUST
  /// NOT send with an average bitrate higher than" this (section 7.1).
  /// Values outside 6000 to 510000 "SHOULD be ignored".
  final int? maxAverageBitrate;

  /// `ptime` (section 6.1), "the preferred duration of media represented by
  /// a packet": 3, 5, 10, 20, 40, 60 or a multiple of a frame size up to 120.
  /// Longer packets carry fewer headers per second (section 5) at the cost
  /// of delay and of more sound lost with each lost packet.
  final int? ptime;

  /// [sdp] with these parameters in every audio section that offers Opus:
  /// `maxaveragebitrate` in that payload type's `a=fmtp` line and `ptime` as
  /// the section's `a=ptime` (section 7). Everything else is left as it was.
  String applyTo(String sdp) {
    final rate = maxAverageBitrate;
    final packet = ptime;
    if (rate == null && packet == null) {
      return sdp;
    }
    final eol = sdp.contains('\r\n') ? '\r\n' : '\n';
    final lines = sdp.split(eol);
    final trailing = lines.isNotEmpty && lines.last.isEmpty;
    if (trailing) {
      lines.removeLast();
    }
    final out = <String>[];
    var start = 0;
    for (var i = 0; i <= lines.length; i++) {
      if (i == lines.length || (i > 0 && lines[i].startsWith('m='))) {
        out.addAll(_section(lines.sublist(start, i), rate, packet));
        start = i;
      }
    }
    return out.join(eol) + (trailing ? eol : '');
  }

  static final _opus = RegExp(
    r'^a=rtpmap:(\d+) opus/48000',
    caseSensitive: false,
  );

  /// One media section (or the session part before the first `m=`).
  static List<String> _section(List<String> lines, int? rate, int? packet) {
    if (lines.isEmpty || !lines.first.startsWith('m=audio')) {
      return lines;
    }
    String? pt;
    for (final l in lines) {
      pt ??= _opus.firstMatch(l)?.group(1);
    }
    if (pt == null) {
      return lines;
    }
    final fmtp = 'a=fmtp:$pt ';
    final out = <String>[];
    var placed = false;
    for (final l in lines) {
      if (packet != null && l.startsWith('a=ptime:')) {
        continue;
      }
      if (l.startsWith(fmtp)) {
        out.add(
          rate == null ? l : fmtp + _withRate(l.substring(fmtp.length), rate),
        );
        if (packet != null) {
          out.add('a=ptime:$packet');
        }
        placed = true;
      } else {
        out.add(l);
        if (_opus.hasMatch(l) && !lines.any((x) => x.startsWith(fmtp))) {
          // No fmtp line for Opus: one is added after its rtpmap.
          if (rate != null) {
            out.add('${fmtp}maxaveragebitrate=$rate');
          }
          if (packet != null) {
            out.add('a=ptime:$packet');
          }
          placed = true;
        }
      }
    }
    assert(placed, 'Opus payload type $pt found but nothing placed');
    return out;
  }

  /// The fmtp parameter list with `maxaveragebitrate` set to [rate].
  static String _withRate(String params, int rate) {
    final kept = [
      for (final p in params.split(';'))
        if (p.trim().isNotEmpty &&
            p.trim().split('=').first.toLowerCase() != 'maxaveragebitrate')
          p.trim(),
    ];
    return [...kept, 'maxaveragebitrate=$rate'].join(';');
  }
}
