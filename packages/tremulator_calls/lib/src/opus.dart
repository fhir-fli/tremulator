/// How a phone asks the other phone to send its sound. These are the Opus
/// receive parameters of RFC 7587 (read whole from rfc-editor.org,
/// 2026-10-18): each is "a unidirectional receive-only parameter" (section
/// 7.1), carried in the description this phone sends, so it binds the other
/// phone's encoder and changes nothing in this phone's own description.
class OpusReceive {
  /// Asks for at most [maxAverageBitrate] bit/s and packets of [ptime] ms.
  /// Null leaves that parameter as the description has it.
  const OpusReceive({this.maxAverageBitrate, this.ptime, this.dtx});

  /// `maxaveragebitrate` (section 6.1): "The sender of the other side MUST
  /// NOT send with an average bitrate higher than" this (section 7.1).
  /// Values outside 6000 to 510000 "SHOULD be ignored".
  final int? maxAverageBitrate;

  /// `ptime` (section 6.1), "the preferred duration of media represented by
  /// a packet": 3, 5, 10, 20, 40, 60 or a multiple of a frame size up to 120.
  /// Longer packets carry fewer headers per second (section 5) at the cost
  /// of delay and of more sound lost with each lost packet.
  final int? ptime;

  /// `usedtx` (section 6.1): whether the other phone should leave silence
  /// untransmitted. RFC 7587 section 3.1.3 (rfc-editor.org text, read
  /// 2026-10-18): DTX has "slightly lower speech or audio quality than
  /// continuous transmission. Therefore, using continuous transmission is
  /// RECOMMENDED unless constraints on available network bandwidth are
  /// severe."
  final bool? dtx;

  /// [sdp] with these parameters in every audio section that offers Opus:
  /// `maxaveragebitrate` in that payload type's `a=fmtp` line and `ptime` as
  /// the section's `a=ptime` (section 7). Everything else is left as it was.
  String applyTo(String sdp) {
    final params = {
      'maxaveragebitrate': ?maxAverageBitrate?.toString(),
      'usedtx': ?switch (dtx) {
        true => '1',
        false => '0',
        null => null,
      },
    };
    final packet = ptime;
    if (params.isEmpty && packet == null) {
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
        out.addAll(_section(lines.sublist(start, i), params, packet));
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
  static List<String> _section(
    List<String> lines,
    Map<String, String> params,
    int? packet,
  ) {
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
        out.add(fmtp + _with(l.substring(fmtp.length), params));
        if (packet != null) {
          out.add('a=ptime:$packet');
        }
        placed = true;
      } else {
        out.add(l);
        if (_opus.hasMatch(l) && !lines.any((x) => x.startsWith(fmtp))) {
          // No fmtp line for Opus: one is added after its rtpmap.
          if (params.isNotEmpty) {
            out.add(fmtp + _with('', params));
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

  /// The fmtp parameter list [list] with each of [set] put in, replacing
  /// any it already has.
  static String _with(String list, Map<String, String> set) {
    final kept = [
      for (final p in list.split(';'))
        if (p.trim().isNotEmpty &&
            !set.containsKey(p.trim().split('=').first.toLowerCase()))
          p.trim(),
    ];
    return [
      ...kept,
      for (final e in set.entries) '${e.key}=${e.value}',
    ].join(';');
  }
}
