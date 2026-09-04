#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
. "$ROOT/tests/checkpoint-fixtures/setup.sh"
LOOP="$ROOT/bin/checkpoint-loop"
DIR="$WORK/state/checkpoints/demo"

"$LOOP" >/dev/null 2>&1;                 assert_eq "no args exits 2" "2" "$?"
"$LOOP" demo 1 >/dev/null 2>&1;          assert_eq "no route and no --idea exits 2" "2" "$?"
"$LOOP" demo 1 --rounds 0 --idea "$WORK/idea.txt" >/dev/null 2>&1; assert_eq "zero rounds exits 2" "2" "$?"

# The whole loop: route, draft, two rounds of critique and revise, review.
out="$("$LOOP" demo 1 --idea "$WORK/idea.txt" 2>&1)"; rc=$?
assert_eq "loop exits 0" "0" "$rc"
[ -f "$DIR/route.md" ] && ok "loop wrote the route" || notok "no route"
assert_eq "loop ends in review" "Status: review" "$(grep '^Status:' "$DIR/1.md")"
assert_eq "two critique rounds by default" "2" "$(ls "$DIR"/1.critique-*.json | wc -l | tr -d ' ')"
modes="$(awk -F'\t' 'NR > 1 { print $4 }' "$WORK/state/checkpoints/ledger.tsv" | tr '\n' ' ')"
assert_eq "passes run in order" "route draft critique revise critique revise " "$modes"
assert_contains "loop reports the rounds"      "round 2: verdict revise" "$out"
assert_contains "loop reports open questions"  "open questions in the PRD: 1" "$out"
assert_contains "loop reports credentials"     "api.example.com" "$out"
assert_contains "loop reports the cost"        "planning run(s) measured" "$out"
assert_contains "loop says what comes next"    "bin/checkpoint-review demo 1" "$out"

# Resume: a PRD in review is not redrafted.
out="$("$LOOP" demo 1 --rounds 1 2>&1)"; rc=$?
assert_eq "resume exits 0" "0" "$rc"
assert_contains "resume skips the draft" "resuming" "$out"
assert_eq "resume drafts nothing" "0" "$(grep -c 'Mode: draft' "$STUB_PROMPTS/draft.txt" | awk '{ print ($1 > 1) }')"

# A ready verdict stops the loop early.
rm -rf "$DIR/2.md" "$DIR"/2.critique-*.json
out="$(STUB_VERDICT=ready "$LOOP" demo 2 2>&1)"; rc=$?
assert_eq "ready loop exits 0" "0" "$rc"
assert_contains "ready stops early" "stopping early" "$out"
assert_eq "ready runs one critique" "1" "$(ls "$DIR"/2.critique-*.json | wc -l | tr -d ' ')"
[ -f "$DIR/2.md.prev" ] && notok "ready still revised" || ok "ready skips the revise"
assert_eq "ready still ends in review" "Status: review" "$(grep '^Status:' "$DIR/2.md")"

# A frozen PRD never loops again.
sed -i.bak 's/^Status:.*/Status: frozen/' "$DIR/2.md" && rm -f "$DIR/2.md.bak"
"$LOOP" demo 2 >/dev/null 2>&1;          assert_eq "a frozen PRD exits 2" "2" "$?"

# A failing pass stops the loop and says so.
rm -rf "$DIR/3.md"
out="$(STUB_FAIL=1 "$LOOP" demo 3 2>&1)"; rc=$?
assert_eq "a failed pass exits 1" "1" "$rc"
[ -f "$DIR/3.md" ] && notok "a failed draft left a PRD" || ok "a failed draft leaves nothing"

exit "$TESTS_FAILED"
