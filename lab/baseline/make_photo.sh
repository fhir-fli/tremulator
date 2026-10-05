#!/usr/bin/env bash
# The one photo every T2 run sends: a deterministic 1600x1200 JPEG with noise
# so it does not compress away, about 1 MB. Output results/photo.jpg
# (git-ignored; re-made by this script). WhatsApp recompresses on send; the
# README asks to record the size WhatsApp shows.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/results/photo.jpg"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=1600x1200:rate=1" \
  -vf "noise=alls=40:allf=t+u,drawtext=text='tremulator T2 photo':fontsize=72:fontcolor=white:x=40:y=40" \
  -frames:v 1 -q:v 2 "$out"
ls -l "$out"
