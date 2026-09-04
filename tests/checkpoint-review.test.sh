#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
. "$ROOT/tests/checkpoint-fixtures/setup.sh"
REV="$ROOT/bin/checkpoint-review"
PASS="$ROOT/bin/checkpoint-pass"
DIR="$WORK/state/checkpoints/demo"

# Stub lavish exactly as tests/spec-render.test.sh does.
mkdir -p "$WORK/stub"
cat > "$WORK/stub/lavish-axi" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  poll) echo "Answer Q1 Rotation interval: take the recommendation: Hourly, matching the session ttl. Note: fine"; exit 0 ;;
  end|stop) exit 0 ;;
  *) echo "session:"; echo "  url: \"http://$LAVISH_AXI_HOST:4387/session/deadbeef\""; exit 0 ;;
esac
STUB
chmod +x "$WORK/stub/lavish-axi"
export PATH="$WORK/stub:$PATH"
export LAVISH_AXI_HOST=100.64.0.1
export CHECKPOINT_LAVISH=lavish-axi
printf 'https://vault.example.test/rules\n' > "$WORK/config/vault.url"

"$REV" >/dev/null 2>&1;                     assert_eq "no args exits 2" "2" "$?"
"$REV" demo 1 >/dev/null 2>&1;              assert_eq "no PRD exits 2" "2" "$?"
"$REV" --wait demo 1 >/dev/null 2>&1;       assert_eq "--wait with no artifact exits 2" "2" "$?"

"$PASS" route demo - --idea "$WORK/idea.txt" >/dev/null 2>&1
"$PASS" draft demo 1 >/dev/null 2>&1

out="$("$REV" demo 1 2>&1)"; rc=$?
assert_eq "open exits 0" "0" "$rc"
html="$WORK/.lavish/checkpoint-demo-1.html"
[ -f "$html" ] && ok "wrote the artifact" || notok "no artifact at $html"
body="$(cat "$html" 2>/dev/null)"
assert_contains "has a doctype"                 "<!doctype html" "$body"
assert_contains "renders the title"             "Checkpoint 1: Sign-in" "$body"
assert_contains "renders the decisions"         "Sessions live in cookies" "$body"
assert_contains "flags what is not specified"   'class="nys"' "$body"
assert_contains "one form per question"         'data-lavish-question="Q1"' "$body"
assert_contains "the recommendation is an option" "take the recommendation: Hourly" "$body"
assert_contains "research is an option"         "send to research" "$body"
assert_contains "a form per proposed experiment" 'data-lavish-question="experiment-1"' "$body"
assert_contains "credentials link to the vault" "https://vault.example.test/rules" "$body"
assert_contains "shows this checkpoint's cost"  "this checkpoint, planning, measured over 1 run(s)" "$body"
assert_contains "shows the whole project's cost" "whole project" "$body"
assert_contains "labels the build number an estimate" "build, estimate" "$body"
assert_contains "queues through lavish"         "window.lavish.queuePrompt" "$body"
assert_contains "answers carry the tag answer"  'tag: "answer"' "$body"
assert_contains "no raw credential value slot"  "Host and purpose only" "$body"
case "$body" in *"<script src="*) notok "the page loads something external" ;; *) ok "the page is self-contained" ;; esac

assert_contains "prints the review URL"         "$LAVISH_AXI_HOST:4387" "$out"
case "$out" in *"take the recommendation: Hourly"*) notok "open polled for answers" ;; *) ok "open returns without polling" ;; esac
assert_contains "tells you what to run next"    "--wait demo 1" "$out"
assert_contains "saves the URL"                 "$LAVISH_AXI_HOST:4387" "$(cat "$WORK/.lavish/checkpoint-demo-1.url" 2>/dev/null)"

before="$(cat "$html")"
wout="$("$REV" --wait demo 1 2>&1)"; wrc=$?
assert_eq "--wait exits 0" "0" "$wrc"
assert_contains "--wait returns the answers"    "take the recommendation: Hourly" "$wout"
assert_contains "--wait saves the answers"      "take the recommendation: Hourly" "$(cat "$DIR/1.answers.txt" 2>/dev/null)"
assert_contains "--wait names the freeze command" "checkpoint-pass freeze demo 1 --answers $DIR/1.answers.txt" "$wout"
assert_eq "--wait leaves the artifact alone"    "$before" "$(cat "$html")"

"$REV" --end demo 1 >/dev/null 2>&1;         assert_eq "--end exits 0" "0" "$?"

# Without a vault URL the page still renders, with no dangling link.
rm "$WORK/config/vault.url"
"$REV" demo 1 >/dev/null 2>&1
case "$(cat "$html")" in *"Add them in the vault"*) notok "vault link shown with no vault configured" ;; *) ok "no vault link without a vault URL" ;; esac

exit "$TESTS_FAILED"
