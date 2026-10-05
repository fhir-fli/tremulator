#!/usr/bin/env bash
# Type one command into Termux on the field phone over adb and press Enter.
# Termux must be installed; the command runs in its foreground session. Spaces
# are sent as %s, which `adb shell input text` turns back into spaces.
# With a second argument, the command's output is sent to that file on the
# phone (under /sdcard/Download), so the laptop can read it with adb.
#   termux.sh "iperf3 -c 10.42.0.1 -u -b 360000 -l 1000 -t 30" [outfile]
set -euo pipefail
cmd="${1:?command}"
if [ -n "${2:-}" ]; then cmd="$cmd > /sdcard/Download/$2 2>&1"; fi
adb shell am start -n com.termux/.app.TermuxActivity >/dev/null
sleep 2
# Quote for the phone's shell too, or it interprets > | & itself.
typed="$(printf '%s' "$cmd" | sed "s/ /%s/g; s/'/'\\\\''/g")"
adb shell "input text '$typed'"
adb shell input keyevent 66
printf '%s termux: %s\n' "$(date -Is)" "$cmd" >>"$(dirname "$0")/results/termux.log"
