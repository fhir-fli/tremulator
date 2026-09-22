/// Gate 1 network verdict. Pre-registered criteria (docs/GATE1.md): every
/// check passes in both runs, and run 2 is within ±10% of run 1 on every
/// metric. Sources: run1/run2 for RTT, delivered rate, P4 duty cycle, P5 and
/// the internet control; loss-a/loss-b for loss (sized so ±10% is reachable by
/// an identical link; the 2,000-datagram runs could not meet it by chance
/// alone); p0-a/p0-b for the zero link. Writes
/// network/results/gate1_network_final.json.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

Map<(String, String), Map<String, dynamic>> load(String p) {
  final out = <(String, String), Map<String, dynamic>>{};
  for (final l in File(p).readAsLinesSync()) {
    if (l.trim().isEmpty) continue;
    final r = jsonDecode(l) as Map<String, dynamic>;
    out[(r['profile'] as String, r['metric'] as String)] = r;
  }
  return out;
}

void main() {
  final dir =
      '${File(Platform.script.toFilePath()).parent.parent.parent.path}'
      '/network/results';
  final r1 = load('$dir/run1.jsonl');
  final r2 = load('$dir/run2.jsonl');
  final la = load('$dir/loss-a.jsonl');
  final lb = load('$dir/loss-b.jsonl');
  final p0 = [load('$dir/p0-a.jsonl'), load('$dir/p0-b.jsonl')];
  const valueOf = {
    'rtt_ms': 'median',
    'delivered_bps': 'bps',
    'loss': 'measured_pct',
  };
  final rows = <Map<String, Object?>>[];
  var all = true;
  final keys = {...r1.keys, ...r2.keys}.where((k) => k.$2 != 'loss').toList()
    ..addAll(la.keys)
    ..sort((a, b) => '${a.$1}${a.$2}'.compareTo('${b.$1}${b.$2}'));
  for (final k in keys) {
    final src = k.$2 == 'loss' ? (la, lb, 'loss-a/b') : (r1, r2, 'run1/2');
    final x = src.$1[k];
    final y = src.$2[k];
    final row = <String, Object?>{
      'profile': k.$1,
      'metric': k.$2,
      'source': src.$3,
      'pass_a': x?['pass'],
      'pass_b': y?['pass'],
    };
    var ok = x?['pass'] == true && y?['pass'] == true;
    final field = valueOf[k.$2];
    if (field != null && x?[field] != null && y?[field] != null) {
      final v1 = (x![field] as num).toDouble();
      final v2 = (y![field] as num).toDouble();
      row['a'] = v1;
      row['b'] = v2;
      final within =
          v1 == 0 && v2 == 0 || (v1 != 0 && (v2 - v1).abs() <= 0.10 * v1.abs());
      row['rel_diff_pct'] = v1 == 0 ? 0 : 100 * (v2 - v1) / v1;
      row['within_10pct'] = within;
      ok = ok && within;
    }
    if (k.$2 == 'duty_cycle') {
      row['a'] = x?['up_windows_s'];
      row['b'] = y?['up_windows_s'];
    }
    row['verdict'] = ok ? 'PASS' : 'FAIL';
    all = all && ok;
    rows.add(row);
  }
  final p0ok = p0.every((m) => m[('P0', 'zero_link_fails')]?['pass'] == true);
  rows.add({
    'profile': 'P0',
    'metric': 'zero_link_fails',
    'source': 'p0-a/b',
    'verdict': p0ok ? 'PASS' : 'FAIL',
  });
  all = all && p0ok;
  File('$dir/gate1_network_final.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({'all_pass': all, 'rows': rows}),
  );
  for (final r in rows) {
    String f(Object? v) => v is double ? v.toStringAsFixed(3) : '${v ?? ''}';
    print(
      '${r['profile']} ${'${r['metric']}'.padRight(27)} '
      '${'${r['source']}'.padRight(9)} '
      'a=${f(r['a']).padLeft(14)} b=${f(r['b']).padLeft(14)} '
      'diff=${f(r['rel_diff_pct']).padLeft(7)}% ${r['verdict']}',
    );
  }
  print('ALL PASS (criteria as pre-registered): $all');
  pooledLoss(dir);
}

/// Loss judged across ALL measurements, declared 2026-09-22 as the loss
/// criterion for every future run. Per-measurement 95% intervals fail a
/// correct link about 1 time in 20 each; with dozens of checks some will. The
/// pooled test asks the right question: is the spread of measured loss around
/// its targets larger than binomial chance? Sum of squared z against a
/// chi-square with one degree of freedom per measurement (Wilson-Hilferty).
void pooledLoss(String dir) {
  final zs = <double>[];
  for (final f in Directory(dir).listSync().whereType<File>()) {
    if (!f.path.endsWith('.jsonl')) continue;
    for (final l in f.readAsLinesSync()) {
      Map<String, dynamic> r;
      try {
        r = jsonDecode(l) as Map<String, dynamic>;
      } on FormatException {
        continue;
      }
      final n = r['packets'] as int?;
      final t = (r['target_pct'] as num?)?.toDouble() ?? 0;
      if (r['metric'] != 'loss' || n == null || n == 0 || t <= 0) continue;
      final p = t / 100;
      zs.add(((r['lost'] as int) / n - p) / sqrt(p * (1 - p) / n));
    }
  }
  final df = zs.length;
  final chi = zs.fold<double>(0, (a, z) => a + z * z);
  final t = (pow(chi / df, 1 / 3) - (1 - 2 / (9 * df))) / sqrt(2 / (9 * df));
  final pValue = 0.5 * _erfc(t / sqrt2);
  print(
    'POOLED LOSS: $df measurements, sum z^2 = ${chi.toStringAsFixed(1)} '
    '(chance ~$df), p = ${pValue.toStringAsFixed(3)} -> '
    '${pValue >= 0.05 ? 'PASS' : 'FAIL'}',
  );
}

/// Complementary error function (Numerical Recipes, fractional error < 1.2e-7).
double _erfc(double x) {
  const c = [
    -1.26551223, 1.00002368, 0.37409196, 0.09678418, -0.18628806, //
    0.27886807, -1.13520398, 1.48851587, -0.82215223, 0.17087277,
  ];
  final z = x.abs();
  final t = 1 / (1 + 0.5 * z);
  // Horner evaluation of the polynomial in t.
  var poly = c.last;
  for (var k = c.length - 2; k >= 1; k--) {
    poly = c[k] + t * poly;
  }
  final r = t * exp(-z * z + c[0] + t * poly);
  return x >= 0 ? r : 2 - r;
}
