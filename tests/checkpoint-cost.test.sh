#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
. "$ROOT/tests/checkpoint-fixtures/setup.sh"
COST="$ROOT/bin/checkpoint-cost"
PASS="$ROOT/bin/checkpoint-pass"
DIR="$WORK/state/checkpoints/demo"

"$COST" --bogus >/dev/null 2>&1;          assert_eq "unknown flag exits 2" "2" "$?"
out="$("$COST" 2>&1)"; rc=$?
assert_eq "no ledger exits 0" "0" "$rc"
assert_contains "no ledger says so" "nothing recorded yet" "$out"

# Four runs at $0.25 each.
"$PASS" route demo - --idea "$WORK/idea.txt" >/dev/null 2>&1
"$PASS" draft demo 1 >/dev/null 2>&1
"$PASS" critique demo 1 --round 1 >/dev/null 2>&1
"$PASS" revise demo 1 --round 1 >/dev/null 2>&1

out="$("$COST" demo 1 2>&1)"
assert_contains "one checkpoint lists its passes" "critique  r1" "$out"
assert_contains "one checkpoint sums its runs" "3 planning run(s) measured \$0.75" "$out"
assert_contains "the build number is an estimate" "build estimate" "$out"
assert_contains "before pebble the task count is assumed" "5 task(s) assumed" "$out"

out="$("$COST" demo 2>&1)"
assert_contains "a project lists its checkpoints" "checkpoint 1" "$out"
assert_contains "a project has a total" "demo       total" "$out"
assert_contains "the route row has no build estimate" "checkpoint -   planning  1 run(s)     \$0.25 measured   build    \$0.00 estimate" "$out"

js="$("$COST" demo --json 2>&1)"
assert_eq "--json is JSON" "0" "$(jq -e . <<< "$js" >/dev/null 2>&1; echo $?)"
assert_eq "--json measured total" "true" "$(jq -r '.projects.demo.measured_usd == 1' <<< "$js")"
assert_eq "--json project total adds the estimate" "true" "$(jq -r '.projects.demo.total_usd > .projects.demo.measured_usd' <<< "$js")"
assert_eq "--json says when tasks are assumed" "true" "$(jq -r '[.checkpoints[] | select(.checkpoint == "1")][0].estimate.assumed' <<< "$js")"

# Once pebble has cut tasks, the estimate uses the real count.
sed -i.bak 's/^Status:.*/Status: frozen/' "$DIR/1.md" && rm -f "$DIR/1.md.bak"
"$PASS" pebble demo 1 --no-open-tickets >/dev/null 2>&1
js="$("$COST" demo 1 --json 2>&1)"
assert_eq "after pebble the task count is measured" "false" "$(jq -r '.checkpoints[0].estimate.assumed' <<< "$js")"
assert_eq "after pebble the task count is pebble's" "2" "$(jq -r '.checkpoints[0].estimate.tasks' <<< "$js")"

# The estimate follows the build row's prices and the environment factors.
one="$(CHECKPOINT_BUILD_STAGES=1 CHECKPOINT_BUILD_RETRY=1 "$COST" demo 1 --json | jq -r '.checkpoints[0].estimate.cost_usd')"
two="$(CHECKPOINT_BUILD_STAGES=2 CHECKPOINT_BUILD_RETRY=1 "$COST" demo 1 --json | jq -r '.checkpoints[0].estimate.cost_usd')"
assert_eq "two stages cost twice one" "yes" "$(awk -v a="$one" -v b="$two" 'BEGIN { d = b - 2 * a; if (d < 0) d = -d; print (d <= 0.011) ? "yes" : "no " b " vs " 2 * a }')"

exit "$TESTS_FAILED"
