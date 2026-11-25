#!/usr/bin/env bash
# Runs the tremulator_calls integration tests off the desktop: the window on
# the private virtual screen :99, the sound on silent dummy devices.
#
#     bash lab/tool/call_tests.sh LOG [flutter test options, e.g. --plain-name NAME]
#
# CALL_TEST picks the test file (default integration_test/calls_test.dart).
# field_trials_test.dart runs on its own: field trials are set once per
# process.
#
# DISPLAY=:99 alone is not enough. Grey's session is Wayland and exports
# GDK_BACKEND=wayland,x11 and WAYLAND_DISPLAY=wayland-0 (seen 2026-11-20), so
# GTK opened the test window on the live desktop and it took Grey's mouse,
# while the screen-capture tests captured the empty virtual screen. Here
# WAYLAND_DISPLAY is removed and GDK_BACKEND is x11, and the test app's own
# environment is checked once it starts: if it could reach the desktop, it is
# killed and the run fails.
set -uo pipefail
LOG=$1; shift
HERE=$(cd "$(dirname "$0")" && pwd)
EXAMPLE="$HERE/../../packages/tremulator_calls/example"
bash "$HERE/xvfb.sh" :99 || exit 1
rm -f "$LOG.desktop"
(
  cd "$EXAMPLE" &&
  exec env -u WAYLAND_DISPLAY GDK_BACKEND=x11 DISPLAY=:99 \
    bash "$HERE/quiet_sound.sh" "$LOG.sound" -- \
    flutter test "${CALL_TEST:-integration_test/calls_test.dart}" -d linux "$@"
) > "$LOG" 2>&1 &
RUN=$!
echo "call_tests.sh: pid $RUN, log $LOG" >&2
while kill -0 "$RUN" 2> /dev/null; do
  for app in $(pgrep -x tremulator_call); do  # comm is cut to 15 characters
    env_of=$(tr '\0' '\n' 2> /dev/null < "/proc/$app/environ") || continue  # gone or mid-start
    if grep -q '^WAYLAND_DISPLAY=' <<< "$env_of" ||
       ! grep -qx 'GDK_BACKEND=x11' <<< "$env_of" ||
       ! grep -qx 'DISPLAY=:99' <<< "$env_of"; then
      echo "$(date +%T) test app $app could reach the desktop; killing" | tee -a "$LOG.desktop" >&2
      kill "$app"; kill "$RUN"
    fi
  done
  sleep 0.5
done
wait "$RUN"; code=$?
[ -e "$LOG.desktop" ] && exit 98
exit "$code"
