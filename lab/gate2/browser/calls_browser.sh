#!/bin/bash
# The browser phone (E1): runs the app's web build in Chrome as a lab phone,
# with the same arguments the Linux app takes, and exits with the code the
# run reports, as /app/tremulator does.
#
#     calls_browser.sh WHO OUTDIR --lab --server http://srv:port --name bob ...
#
# nginx serves the page and, on the same origin, the mailbox server at
# /fhir/ (fhirant publishes no cross-origin policy unless configured) and the
# lab helper at /lab/. Chrome (Chrome for Testing, pinned in calls.py) runs
# on the phone's virtual screen and sound card, on an empty profile, with
# camera and screen prompts answered yes. Its console goes to
# OUTDIR/WHO_chrome.log.
set -u
who=$1; d=$2; shift 2
server=""; out=""; until=""
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --server) server=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --until-file) until=$2; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
[ -n "$server" ] && [ -n "$out" ] || { echo "need --server and --out" >&2; exit 64; }
stop=${until:-/nonexistent}
mkdir -p /tmp/browser /tmp/state
# Chrome lists no PulseAudio monitor source as a microphone (calls41: the
# phone's default source mic.monitor gave getUserMedia "NotFoundError:
# Requested device not found"), so the browser phone's microphone is a plain
# source copied from it. What Alice's microphone recording hears is still
# mic.monitor; the copy's own buffering is inside the measured voice delay.
if ! pactl list short sources | grep -q $'\tmicsrc\t'; then
  pactl load-module module-remap-source master=mic.monitor source_name=micsrc > /dev/null
fi
pactl set-default-source micsrc
rm -f /tmp/browser/exit
cat > /tmp/browser/nginx.conf <<EOF
daemon off;
worker_processes 1;
pid /tmp/browser/nginx.pid;
error_log /tmp/browser/nginx_error.log;
events {}
http {
  access_log off;
  client_body_temp_path /tmp/browser/nb;
  proxy_temp_path /tmp/browser/np;
  fastcgi_temp_path /tmp/browser/nf;
  uwsgi_temp_path /tmp/browser/nu;
  scgi_temp_path /tmp/browser/ns;
  include /etc/nginx/mime.types;
  types { application/wasm wasm; }
  client_max_body_size 32m;
  map \$http_upgrade \$conn { default upgrade; '' close; }
  server {
    listen 127.0.0.1:8099;
    # Cross-origin isolation, so the encryption library's WASM can share
    # memory (flutter_rust_bridge "web-cross-origin"; without it Chrome
    # logged "Buffers cannot be shared due to missing cross-origin headers").
    add_header Cross-Origin-Opener-Policy same-origin always;
    add_header Cross-Origin-Embedder-Policy require-corp always;
    location / { root /web; }
    location /fhir/ {
      proxy_pass ${server%/}/;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$conn;
      proxy_buffering off;
      proxy_read_timeout 3600s;
    }
    location /lab/ { proxy_pass http://127.0.0.1:8098; }
  }
}
EOF
nginx -c /tmp/browser/nginx.conf > /tmp/browser/nginx.out 2>&1 &
nginx_pid=$!
python3 -I /usr/local/bin/lab_helper.py 8098 "$out" "$stop" /tmp/browser/exit \
  > /tmp/browser/helper.out 2>&1 &
helper_pid=$!
for _ in $(seq 1 40); do
  curl -fsS -o /dev/null http://127.0.0.1:8099/index.html \
    && curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8099/lab/stop | grep -qE '200|404' \
    && break
  sleep 0.25
done
query=$(python3 -I -c '
import sys, urllib.parse
a, q, i = sys.argv[1:], [], 0
while i < len(a):
    k = a[i][2:]
    if i + 1 < len(a) and not a[i + 1].startswith("--"):
        q.append((k, a[i + 1])); i += 2
    else:
        q.append((k, "")); i += 1
print(urllib.parse.urlencode(q))
' "${args[@]}" --server http://localhost:8099/fhir --out "$out" ${until:+--until-file "$until"})
# --test-type and --kiosk: no warning bars over the page (calls42: two bars
# covered the top 113 px of Bob's screen).
/opt/chrome/chrome --no-sandbox --test-type --kiosk --no-first-run --no-default-browser-check \
  --user-data-dir=/tmp/state/chrome --password-store=basic \
  --use-fake-ui-for-media-stream --auto-select-desktop-capture-source="Entire screen" \
  --autoplay-policy=no-user-gesture-required --enable-unsafe-swiftshader \
  --disable-features=WebRtcHideLocalIpsWithMdns,Translate \
  --window-position=0,0 --window-size=1280,720 \
  --enable-logging=stderr --v=0 \
  --app="http://localhost:8099/?$query" > "$d/${who}_chrome.log" 2>&1 &
chrome_pid=$!
code=3
while kill -0 $chrome_pid 2>/dev/null; do
  if [ -s /tmp/browser/exit ]; then code=$(cat /tmp/browser/exit); break; fi
  sleep 0.5
done
[ -s /tmp/browser/exit ] && code=$(cat /tmp/browser/exit)
kill $chrome_pid $nginx_pid $helper_pid 2>/dev/null
wait 2>/dev/null
exit "$code"
