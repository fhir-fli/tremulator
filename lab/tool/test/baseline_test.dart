import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tremulator_lab/baseline.dart';

void main() {
  group('sizing and targets', () {
    test('expected rate matches the lab formula', () {
      // 300 kbit/s, 2% loss: 300000 * 1000/1042 * 0.98
      expect(expectedBps(300, 2), closeTo(282149.7, 0.1));
    });
    test('loss sample size follows (1-p)/(p*0.0013), floor 2000', () {
      expect(lossSampleSize(0.05), 14616);
      expect(lossSampleSize(0.01), 76154);
      expect(lossSampleSize(0), 2000);
    });
    test('two-way loss', () {
      expect(twoWayLoss(0.05), closeTo(0.0975, 1e-9));
      expect(twoWayLoss(0), 0);
    });
    test('ping interval keeps pings under a quarter of the cap', () {
      expect(pingInterval(50), closeTo(0.03712, 1e-5));
      expect(pingInterval(300), 0.01);
      expect(pingInterval(0), 0.01);
    });
    test('rtt tolerance is max(10%, 2 ms)', () {
      expect(rttTolerance(400), 40);
      expect(rttTolerance(9), 2);
    });
  });

  group('ping parsing', () {
    const out = '''
PING 10.42.0.23 (10.42.0.23) 16(44) bytes of data.
[1759680000.100000] 24 bytes from 10.42.0.23: icmp_seq=1 ttl=64 time=203 ms
[1759680000.300000] 24 bytes from 10.42.0.23: icmp_seq=2 ttl=64 time=201.5 ms
[1759680000.500000] 24 bytes from 10.42.0.23: icmp_seq=3 ttl=64 time=205 ms
''';
    test('rtts', () {
      expect(rttsFromPing(out), [203, 201.5, 205]);
      expect(median(rttsFromPing(out)), 203);
    });
    test('stamps', () {
      expect(stampsFromPing(out), [1759680000.1, 1759680000.3, 1759680000.5]);
    });
    test('duty windows from a 30/60 pattern', () {
      final stamps = <double>[];
      var t = 0.0;
      for (var cycle = 0; cycle < 3; cycle++) {
        for (var i = 0; i <= 150; i++) {
          stamps.add(t + i * 0.2);
        }
        t += 90;
      }
      final w = dutyWindows(stamps);
      expect(w.ups.length, 3);
      expect(w.downs.length, 2);
      expect(w.ups.first, closeTo(30, 0.01));
      expect(w.downs.first, closeTo(60, 0.01));
      expect(w.judgedUps.length, 1);
    });
  });

  group('iperf3 server JSON', () {
    test('udp: end.sum is the receiver', () {
      const j = '''
{"end":{"sum":{"bits_per_second":281900.5,"lost_packets":41,"packets":2040,"seconds":30.0}}}''';
      final r = parseIperfServerJson(j);
      expect(r['bps'], 281900.5);
      expect(r['lost'], 41);
      expect(r['packets'], 2040);
    });
    test('tcp: sum_received wins', () {
      const j = '''
{"end":{"sum_sent":{"bits_per_second":999},"sum_received":{"bits_per_second":900,"seconds":10}}}''';
      expect(parseIperfServerJson(j)['bps'], 900);
    });
    test('error surfaces', () {
      expect(
        parseIperfServerJson('{"error":"unable to receive control message"}'),
        {'error': 'unable to receive control message'},
      );
    });
  });

  group('flows', () {
    const text = '''
1759680000.000001 IP 10.42.0.23.40000 > 157.240.1.1.443: tcp 517
1759680000.100001 IP 157.240.1.1.443 > 10.42.0.23.40000: tcp 1200
1759680000.200001 IP 10.42.0.23.3478 > 192.168.8.50.3478: UDP, length 172
1759680000.300001 IP 192.168.8.50.3478 > 10.42.0.23.3478: UDP, length 160
1759680000.400001 IP 10.42.0.23.5353 > 224.0.0.251.5353: UDP, length 80
1759680000.500001 IP 10.42.0.1.67 > 10.42.0.23.68: UDP, length 300
1759680000.600001 IP 192.168.8.9.1234 > 192.168.8.50.1234: UDP, length 1
1759680000.700001 IP 10.42.0.23 > 157.240.1.1: ICMP echo request, id 1, seq 1, length 24
''';
    test('classifies by remote and sums both directions', () {
      final flows = classifyFlows(
        text,
        phone: '10.42.0.23',
        ap: '10.42.0.',
        home: '192.168.8.',
      );
      final byKey = {for (final f in flows) '${f.proto} ${f.remote}': f};
      final relay = byKey['tcp 157.240.1.1']!;
      expect(relay.kind, 'internet');
      expect(relay.packetsOut, 1);
      expect(relay.bytesOut, 517);
      expect(relay.packetsIn, 1);
      expect(relay.bytesIn, 1200);
      expect(relay.last! - relay.first!, closeTo(0.1, 1e-6));
      final p2p = byKey['udp 192.168.8.50']!;
      expect(p2p.kind, 'home-lan');
      expect(p2p.bytesOut + p2p.bytesIn, 332);
      expect(byKey['udp 224.0.0.251']!.kind, 'multicast');
      expect(byKey['udp 10.42.0.1']!.kind, 'ap-lan');
      expect(
        byKey.containsKey('udp 192.168.8.9'),
        isFalse,
        reason: 'not the phone',
      );
      expect(
        byKey.containsKey('icmp 157.240.1.1'),
        isFalse,
        reason: 'ICMP lines have no port and are not matched',
      );
      expect(
        flows.first.bytesIn + flows.first.bytesOut,
        1717,
        reason: 'sorted by bytes, largest first',
      );
    });
  });

  group('wav and onsets', () {
    Uint8List wav(List<int> samples, int rate) {
      final data = ByteData(44 + samples.length * 2);
      void str(int at, String s) {
        for (var i = 0; i < s.length; i++) {
          data.setUint8(at + i, s.codeUnitAt(i));
        }
      }

      str(0, 'RIFF');
      str(8, 'WAVE');
      str(12, 'fmt ');
      str(36, 'data');
      data
        ..setUint32(4, 36 + samples.length * 2, Endian.little)
        ..setUint32(16, 16, Endian.little)
        ..setUint16(20, 1, Endian.little)
        ..setUint16(22, 1, Endian.little)
        ..setUint32(24, rate, Endian.little)
        ..setUint32(28, rate * 2, Endian.little)
        ..setUint16(32, 2, Endian.little)
        ..setUint16(34, 16, Endian.little)
        ..setUint32(40, samples.length * 2, Endian.little);
      for (var i = 0; i < samples.length; i++) {
        data.setInt16(44 + 2 * i, samples[i], Endian.little);
      }
      return data.buffer.asUint8List();
    }

    test('two clicks 250 ms apart', () {
      const rate = 16000;
      final s = List<int>.filled(rate, 0);
      for (var i = 0; i < 20; i++) {
        s[4000 + i] = 20000; // 0.25 s
        s[8000 + i] = -9000; // 0.5 s, quieter (speaker)
      }
      s[12000] = 300; // noise, under threshold
      final (r, samples) = parseWav16(wav(s, rate));
      expect(r, rate);
      expect(samples.length, rate);
      final ts = onsets(samples, r, threshold: 0.4);
      expect(ts, [0.25, 0.5]);
    });
    test('rejects stereo', () {
      final bad = wav([0, 0], 8000)
        ..buffer.asByteData().setUint16(22, 2, Endian.little);
      expect(() => parseWav16(bad), throwsFormatException);
    });
    test('silence has no onsets', () {
      expect(onsets(Int16List(100), 8000), isEmpty);
    });
  });
}
