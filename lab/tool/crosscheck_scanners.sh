#!/bin/sh
# Run the Python and Dart canary scanners over the same saved mutation-test
# artefacts and compare their hit sets (where, canary, form). One line per case
# to adversary/results/scanner_crosscheck.tsv.
set -u
cd "$(dirname "$0")/.."
OUT=adversary/results/scanner_crosscheck.tsv
printf 'run\tmode\tpython_hits\tdart_hits\tidentical\n' > $OUT
dart compile exe tool/bin/canary_scan.dart -o /tmp/claude-1000/canary_scan_dart >/dev/null
for run in m2 m3; do
  for d in adversary/out/$run/*/; do
    mode=$(basename $d)
    python3 adversary/canary_scan.py $d/canaries.tsv /tmp/claude-1000/py_${run}_${mode}.jsonl $d/srv $d/cli >/dev/null
    /tmp/claude-1000/canary_scan_dart $d/canaries.tsv /tmp/claude-1000/da_${run}_${mode}.jsonl $d/srv $d/cli >/dev/null
    r=$(python3 - /tmp/claude-1000/py_${run}_${mode}.jsonl /tmp/claude-1000/da_${run}_${mode}.jsonl <<'PY'
import json,sys
def load(p): return {(h['where'],h['canary'],h['form']) for h in map(json.loads,open(p))}
a,b=load(sys.argv[1]),load(sys.argv[2])
print(f"{len(a)}\t{len(b)}\t{a==b}")
if a!=b:
    for x in sorted(a-b)[:3]: print('  python only:',x,file=sys.stderr)
    for x in sorted(b-a)[:3]: print('  dart only:',x,file=sys.stderr)
PY
)
    printf '%s\t%s\t%s\n' $run $mode "$r" >> $OUT
  done
done
cat $OUT
