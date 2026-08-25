# Minimal TAP-ish reporters plus a fake factory API, so tests never touch the
# live queue. There is exactly one factory-server and one SQLite database on
# the host holding real work; no test may submit to it.
set -uo pipefail

TESTS_FAILED=0
ok()    { printf 'ok - %s\n' "$1"; }
notok() { printf 'not ok - %s\n' "$1"; TESTS_FAILED=1; }

assert_eq() { # assert_eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"
  else notok "$1: expected [$2] got [$3]"; fi
}

assert_contains() { # assert_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) notok "$1: [$2] not found in [$3]" ;;
  esac
}

# fake_api_start <port> <status> <body>
# Serves one canned response to every request and appends the full request,
# headers and body, to $FAKE_LOG so a test can assert on what was sent.
#
# python3 rather than nc: the two common netcats disagree about -l and -p, and
# a test harness that only works on one of them is worse than no harness.
# python3 is present on both the WSL box and the Mac.
fake_api_start() {
  FAKE_PORT="$1"; FAKE_STATUS="$2"; FAKE_BODY="$3"
  FAKE_LOG="$(mktemp)"
  FAKE_DIR="$(mktemp -d)"
  cat > "$FAKE_DIR/serve.py" <<'INNER'
import sys, http.server
status, body, log = int(sys.argv[2]), sys.argv[3], sys.argv[4]

class H(http.server.BaseHTTPRequestHandler):
    def _handle(self):
        n = int(self.headers.get('Content-Length') or 0)
        payload = self.rfile.read(n).decode('utf-8', 'replace') if n else ''
        with open(log, 'a') as f:
            f.write(f"{self.command} {self.path}\n{self.headers}\n{payload}\n")
        raw = body.encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
    do_GET = do_POST = do_PUT = _handle
    def log_message(self, *a): pass

http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
INNER
  python3 "$FAKE_DIR/serve.py" "$FAKE_PORT" "${FAKE_STATUS%% *}" "$FAKE_BODY" "$FAKE_LOG" &
  FAKE_PID=$!
  sleep 0.5
}

fake_api_stop() {
  # wait after kill, so bash reaps the job itself instead of printing
  # "Terminated: 15" into the middle of the test output.
  if [ -n "${FAKE_PID:-}" ]; then
    kill "$FAKE_PID" 2>/dev/null
    wait "$FAKE_PID" 2>/dev/null
  fi
  [ -n "${FAKE_DIR:-}" ] && rm -rf "$FAKE_DIR"
}
