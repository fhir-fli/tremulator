#!/usr/bin/env bash
# E3's lab runs, one after another (each builds the app from its own copy):
#   e3b-planted2  call setup in plain text (plant b), profile none
#   e3b-main      the same, nothing planted
#   e3d-wrong     relay forced (none-blocked), wrong relay password
#   e3d-right     relay forced, right password (the control)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
bash lab/e3/plant.sh b-call-setup-unencrypted bash lab/e3/lab_call.sh e3b-planted2
bash lab/e3/plant.sh none bash lab/e3/lab_call.sh e3b-main
bash lab/e3/plant.sh none bash lab/e3/lab_call.sh e3d-wrong --profiles none-blocked --call-s 30 --wrong-relay-password
bash lab/e3/plant.sh none bash lab/e3/lab_call.sh e3d-right --profiles none-blocked --call-s 30
echo "lab_runs.sh done"
