#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
REN="$ROOT/bin/spec-render"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export ORCH_HOME="$WORK"

cat > "$WORK/spec.md" <<'SPEC'
## Add input validation to greet

### What are we building?
`greet` accepts any value. It should reject invalid input.

### Done when
- Invalid input is rejected.
- `npm test` passes.

### Out of scope
- Renaming the module.
SPEC

# Stub lavish so the test never starts a real server.
mkdir -p "$WORK/stub"
cat > "$WORK/stub/lavish-axi" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  poll) echo "feedback: put the toggle in settings"; exit 0 ;;
  end|stop) exit 0 ;;
  *) echo "session:"; echo "  url: \"http://$LAVISH_AXI_HOST:4387/session/deadbeef\""; exit 0 ;;
esac
STUB
chmod +x "$WORK/stub/lavish-axi"
export PATH="$WORK/stub:$PATH"
# A generic address from the 100.64.0.0/10 CGNAT range Tailscale draws from.
# Never the real one: this repository is public.
export LAVISH_AXI_HOST=100.64.0.1
export SPEC_RENDER_LAVISH=lavish-axi

"$REN" >/dev/null 2>&1; assert_eq "no args exits 2" "2" "$?"
"$REN" "$WORK/nope.md" >/dev/null 2>&1; assert_eq "missing file exits 2" "2" "$?"

out="$("$REN" "$WORK/spec.md" 2>&1)"; rc=$?
assert_eq "render exits 0" "0" "$rc"

html="$(ls "$WORK"/.lavish/*.html 2>/dev/null | head -1)"
[ -n "$html" ] && ok "wrote an HTML artifact" || notok "no HTML artifact written"

body="$(cat "$html" 2>/dev/null)"
assert_contains "has a doctype"            "<!doctype html" "$body"
assert_contains "paints its own background" "background"    "$body"
assert_contains "renders the task title"    "Add input validation to greet" "$body"
assert_contains "renders a section heading" "Done when"     "$body"
assert_contains "renders list items"        "<li>"          "$body"
assert_contains "renders inline code"       "<code>"        "$body"

# The markdown spec is the contract. The HTML must not be what gets submitted.
assert_contains "prints the review URL" "$LAVISH_AXI_HOST:4387" "$out"

# Opening must NOT block. It used to print the URL and then poll in the same
# command, so through an agent's shell tool the URL stayed buffered until the
# review was over and the reviewer never saw a link. Opening returns; waiting
# is a second command.
if grep -q 'put the toggle in settings' <<< "$out"; then
  notok "opening polled for feedback: the URL cannot reach a reviewer if the command never returns"
else
  ok "opening returns without polling"
fi
assert_contains "tells you what to run next" "--wait" "$out"

urlfile="$(ls "$WORK"/.lavish/*.url 2>/dev/null | head -1)"
[ -n "$urlfile" ] && ok "saves the URL beside the artifact" || notok "no .url file written"
assert_contains "the saved URL is the review URL" "$LAVISH_AXI_HOST:4387" "$(cat "$urlfile" 2>/dev/null)"

# --wait is the blocking half, and it returns what the reviewer sent.
wout="$("$REN" --wait "$WORK/spec.md" 2>&1)"; wrc=$?
assert_eq "--wait exits 0" "0" "$wrc"
assert_contains "--wait returns the human's feedback" "put the toggle in settings" "$wout"

# --wait must not rebuild the page under a reviewer who is reading it.
before="$(cat "$html")"
"$REN" --wait "$WORK/spec.md" >/dev/null 2>&1
assert_eq "--wait leaves the artifact alone" "$before" "$(cat "$html")"

# --wait before anything was rendered is a usage error, not a silent hang.
rm -rf "$WORK/.lavish"
"$REN" --wait "$WORK/spec.md" >/dev/null 2>&1
assert_eq "--wait with no artifact exits 2" "2" "$?"

exit "$TESTS_FAILED"
