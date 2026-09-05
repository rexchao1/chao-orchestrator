#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
. "$ROOT/tests/checkpoint-fixtures/setup.sh"
PASS="$ROOT/bin/checkpoint-pass"
DIR="$WORK/state/checkpoints/demo"
LEDGER="$WORK/state/checkpoints/ledger.tsv"

# Usage errors exit 2 before a single token is spent.
"$PASS" >/dev/null 2>&1;                          assert_eq "no args exits 2" "2" "$?"
"$PASS" bogus demo 1 >/dev/null 2>&1;             assert_eq "unknown mode exits 2" "2" "$?"
"$PASS" draft nope 1 >/dev/null 2>&1;             assert_eq "unknown project exits 2" "2" "$?"
"$PASS" draft demo x >/dev/null 2>&1;             assert_eq "non-numeric checkpoint exits 2" "2" "$?"
"$PASS" draft demo 1 >/dev/null 2>&1;             assert_eq "draft without a route exits 2" "2" "$?"
"$PASS" critique demo 1 >/dev/null 2>&1;          assert_eq "critique without a PRD exits 2" "2" "$?"
"$PASS" route demo - >/dev/null 2>&1;             assert_eq "route without --idea exits 2" "2" "$?"
[ -f "$STUB_LOG" ] && notok "a usage error still ran the model" || ok "usage errors never run the model"

# route: the plan row, read-only flags, the skill body without its frontmatter.
out="$("$PASS" route demo - --idea "$WORK/idea.txt" 2>&1)"; rc=$?
assert_eq "route exits 0" "0" "$rc"
assert_contains "route wrote the route file" "# Route: demo sign-in" "$(cat "$DIR/route.md")"
args="$(tail -n1 "$STUB_LOG")"
assert_contains "plan passes use the plan model"   "--model claude-fable-5-1" "$args"
assert_contains "plan passes use the plan effort"  "--effort high" "$args"
assert_contains "passes never ask"                 "--permission-mode dontAsk" "$args"
assert_contains "passes get the read-only allow list" "--allowedTools Read,Grep,Glob,WebFetch,WebSearch" "$args"
assert_contains "passes are bounded by money"      "--max-budget-usd 5" "$args"
assert_contains "passes return JSON"               "--output-format json" "$args"
case "$args" in *Edit*|*Bash*|*Write*) notok "a write tool leaked into the allow list" ;; *) ok "no write tool in the allow list" ;; esac
prompt="$(cat "$STUB_PROMPTS/route.txt")"
assert_contains "the prompt carries the skill body"  "SKILL BODY MARKER boulder" "$prompt"
assert_contains "the prompt carries the idea"        "sign in without a password" "$prompt"
case "$prompt" in *user-invocable*) notok "the skill frontmatter leaked into the prompt" ;; *) ok "the skill frontmatter stays out of the prompt" ;; esac
assert_contains "the prompt names the clone"         "$WORK/clones/demo" "$prompt"
assert_contains "route reports the cost"             '$0.25' "$out"

# A fence around the whole output is stripped; the file is the contents.
rm "$DIR/route.md"
STUB_FENCE=1 "$PASS" route demo - --idea "$WORK/idea.txt" >/dev/null 2>&1
assert_eq "a fenced answer is unwrapped" "# Route: demo sign-in" "$(head -n1 "$DIR/route.md")"

# draft
"$PASS" draft demo 1 >/dev/null 2>&1;             assert_eq "draft exits 0" "0" "$?"
assert_eq "draft writes status draft" "Status: draft" "$(grep '^Status:' "$DIR/1.md")"
assert_contains "draft sees the route" "Password reset" "$(cat "$STUB_PROMPTS/draft.txt")"
"$PASS" draft demo 1 >/dev/null 2>&1;             assert_eq "draft refuses to overwrite a PRD" "2" "$?"

# critique: the critic row, a schema, JSON on disk.
out="$("$PASS" critique demo 1 --round 1 2>&1)"; rc=$?
assert_eq "critique exits 0" "0" "$rc"
args="$(tail -n1 "$STUB_LOG")"
assert_contains "critique uses the critic model"  "--model claude-opus-5" "$args"
assert_contains "critique uses the critic effort" "--effort xhigh" "$args"
assert_contains "critique asks for the findings schema" "--json-schema" "$args"
assert_eq "critique wrote the findings" "revise" "$(jq -r .verdict "$DIR/1.critique-1.json")"
assert_contains "critique sees the PRD" "Tokens rotate hourly" "$(cat "$STUB_PROMPTS/critique.txt")"
assert_contains "critique sees the critic skill" "SKILL BODY MARKER checkpoint-critic" "$(cat "$STUB_PROMPTS/critique.txt")"
assert_contains "critique reports the verdict" "verdict revise, 1 finding(s)" "$out"

# Overrides: a flag beats the row, an environment variable beats the row.
"$PASS" critique demo 1 --round 2 --model claude-sonnet-5 --effort low >/dev/null 2>&1
assert_contains "--model overrides the row"  "--model claude-sonnet-5" "$(tail -n1 "$STUB_LOG")"
assert_contains "--effort overrides the row" "--effort low" "$(tail -n1 "$STUB_LOG")"
CHECKPOINT_MODEL=claude-haiku-4-5 "$PASS" critique demo 1 --round 3 >/dev/null 2>&1
assert_contains "CHECKPOINT_MODEL overrides the row" "--model claude-haiku-4-5" "$(tail -n1 "$STUB_LOG")"
rm -f "$DIR/1.critique-2.json" "$DIR/1.critique-3.json"

# revise: needs the round's findings, keeps the previous PRD, feeds the findings in.
"$PASS" revise demo 1 --round 4 >/dev/null 2>&1;  assert_eq "revise without findings exits 2" "2" "$?"
"$PASS" revise demo 1 --round 1 >/dev/null 2>&1;  assert_eq "revise exits 0" "0" "$?"
assert_contains "revise rewrote the PRD" "D2 now cites src/auth.ts:9" "$(cat "$DIR/1.md")"
[ -f "$DIR/1.md.prev" ] && ok "revise keeps the previous PRD" || notok "no .prev kept"
assert_contains "revise sees the findings" "D2 is a guess dressed as a decision" "$(cat "$STUB_PROMPTS/revise.txt")"

# A tree change under a pass: the pass has no tool that can write, so the change
# is someone else's. It is reported and the output is kept.
before="$(cat "$DIR/1.md")"
printf 'MARKER the old PRD\n' >> "$DIR/1.md"
out="$(STUB_STRAY="$WORK/clones/demo" "$PASS" revise demo 1 --round 1 2>&1)"; rc=$?
rm -f "$WORK/clones/demo/stray.txt"
assert_eq "a tree change does not fail the pass" "0" "$rc"
assert_contains "the tree change is named" "the tree changed during the revise pass" "$out"
assert_contains "the tree change says what moved" "stray.txt" "$out"
assert_eq "a changed tree keeps the output" "$before" "$(cat "$DIR/1.md")"

# A model error is reported, not written.
out="$(STUB_FAIL=1 "$PASS" revise demo 1 --round 1 2>&1)"; rc=$?
assert_eq "a model error exits 1" "1" "$rc"
assert_contains "a model error is named" "pass failed" "$out"
assert_eq "a failed pass leaves the PRD alone" "$before" "$(cat "$DIR/1.md")"

# Denials are noted and counted, the pass still lands.
out="$(STUB_DENY=1 "$PASS" revise demo 1 --round 1 2>&1)"; rc=$?
assert_eq "a denied tool call does not fail the pass" "0" "$rc"
assert_contains "denials are noted" "1 tool call(s) it is not allowed" "$out"

# freeze
"$PASS" freeze demo 1 >/dev/null 2>&1;            assert_eq "freeze without answers exits 2" "2" "$?"
printf 'Answer Q1 Rotation interval: take the recommendation\n' > "$DIR/1.answers.txt"
"$PASS" freeze demo 1 --answers "$DIR/1.answers.txt" >/dev/null 2>&1; assert_eq "freeze exits 0" "0" "$?"
assert_eq "freeze writes status frozen" "Status: frozen" "$(grep '^Status:' "$DIR/1.md")"
assert_contains "freeze sees the answers" "take the recommendation" "$(cat "$STUB_PROMPTS/freeze.txt")"
"$PASS" revise demo 1 --round 1 >/dev/null 2>&1;  assert_eq "a frozen PRD does not revise" "2" "$?"
"$PASS" critique demo 1 --round 9 >/dev/null 2>&1; assert_eq "a frozen PRD does not critique" "2" "$?"

# pebble
"$PASS" pebble demo 1 >/dev/null 2>&1;            assert_eq "pebble without --no-open-tickets exits 2" "2" "$?"
out="$("$PASS" pebble demo 1 --no-open-tickets 2>&1)"; rc=$?
assert_eq "pebble exits 0" "0" "$rc"
assert_eq "pebble writes one file per task" "2" "$(ls "$DIR/1/tasks"/*.md | wc -l | tr -d ' ')"
assert_contains "pebble task files carry the task" "### What are we building?" "$(cat "$DIR/1/tasks/01-task-1.md")"
assert_eq "pebble records the credentials line" "Credentials: api.example.com" "$(cat "$DIR/1/credentials.txt")"
assert_contains "pebble reports the credentials" "credentials: Credentials: api.example.com" "$out"
assert_contains "pebble uses the plan model" "--model claude-fable-5-1" "$(tail -n1 "$STUB_LOG")"
out="$(STUB_TASKS=6 "$PASS" pebble demo 1 --no-open-tickets 2>&1)"; rc=$?
assert_eq "six tasks is oversized" "1" "$rc"
assert_contains "oversized says so" "oversized" "$out"

# The ledger: one row per run, money kept even for failures.
assert_eq "ledger has the documented columns" "17" "$(head -n1 "$LEDGER" | awk -F'\t' '{ print NF }')"
rows="$(tail -n +2 "$LEDGER" | wc -l | tr -d ' ')"
runs="$(wc -l < "$STUB_LOG" | tr -d ' ')"
assert_eq "one ledger row per model run" "$runs" "$rows"
crit="$(awk -F'\t' '$4 == "critique" && $5 == "1" { print $7, $8, $13, $17 }' "$LEDGER" | head -n1)"
assert_eq "the ledger records model, effort, cost, outcome" "claude-opus-5 xhigh 0.25 ok" "$crit"
assert_eq "the ledger records only ok and error" "error ok " "$(awk -F'\t' 'NR > 1 { print $17 }' "$LEDGER" | sort -u | tr '\n' ' ')"
assert_contains "the ledger records a failed run" "error" "$(awk -F'\t' '{ print $17 }' "$LEDGER" | sort -u | tr '\n' ' ')"
assert_eq "the ledger counts denials" "1" "$(awk -F'\t' '$16 == "1"' "$LEDGER" | wc -l | tr -d ' ')"

# The orchestrator home itself stays clean apart from state/.
stray="$(cd "$WORK" && ls | grep -v -E '^(config|state|clones|skills|idea.txt|claude-args.log|prompts)$')"
[ -z "$stray" ] && ok "passes write only under state/" || notok "unexpected files in the orchestrator home: $stray"

exit "$TESTS_FAILED"
