#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
ST="$ROOT/bin/factory-status"

# 1. The runs list. Shape copied from the live host on 2026-08-25.
RUNS='{"runs":[{"id":"5edf217d-53dc-4099-ad56-55e1f27bdd68","state":"failed","source":"orchestrator","session_count":1,"needs_input_count":0,"task":{"name":"Orchestrator runs without a gate (3459c2c3)","submitted_name":"Orchestrator runs without a gate","runtime":"claude-code"}}],"workers":[]}'

fake_api_start 18083 "200" "$RUNS"
out="$(FACTORY_BASE=http://127.0.0.1:18083 "$ST" 2>/dev/null)"
rc=$?
fake_api_stop

assert_eq "exits 0 on success" "0" "$rc"
assert_contains "prints the submitted name, not the dedup artifact" "Orchestrator runs without a gate" "$out"
if grep -q '(3459c2c3)' <<< "$out"; then
  notok "must print submitted_name, not tasks.name with its request-key suffix"
else
  ok "does not print the request-key suffix"
fi
assert_contains "prints the state" "failed" "$out"
assert_contains "prints the run id" "5edf217d" "$out"
# In full, not truncated: the detail view takes a run id and the API rejects a
# prefix with not_found, so a truncated id is one you cannot hand back.
assert_contains "prints the run id in full" "5edf217d-53dc-4099-ad56-55e1f27bdd68" "$out"

# 2. An API error must not be reported as an empty factory.
fake_api_start 18084 "503" '{"error":{"code":"storage_unavailable","message":"database is unavailable"}}'
out2="$(FACTORY_BASE=http://127.0.0.1:18084 "$ST" 2>&1)"
rc2=$?
fake_api_stop
assert_eq "API error exits 1" "1" "$rc2"
assert_contains "API error is reported, not swallowed" "storage_unavailable" "$out2"

# 3. Run detail. GET /api/v1/runs/{id} returns {"run":..,"sessions":..}, NOT a
#    flat run, and publish_branch lives on session.target, not on the session.
#    Both were measured against the live host on 2026-08-25.
DETAIL='{"run":{"id":"81b799f3-b81e-461d-8aaa-93adbe174798","state":"succeeded","source":"manual","task":{"name":"Phase 5 auto-merge sliver v2 (aabbccdd)","submitted_name":"Phase 5 auto-merge sliver v2"}},"sessions":[{"id":"2425fa21-24a0-4c85-a982-546093896f31","state":"ready","delivery":"pr+automerge","pull_request_url":"https://github.com/rexchao1/factory-scratch/pull/4","terminal_message":"Pushed reviewed commit adding PHASE5.md and opened PR #4 against main.","target":{"publish_branch":"factory/work-2425fa2124a04c85"},"stages":[{"position":0,"name":"Implement","state":"succeeded"},{"position":1,"name":"Review","state":"succeeded"},{"position":2,"name":"Deliver","state":"succeeded"}]}]}'

fake_api_start 18085 "200" "$DETAIL"
det="$(FACTORY_BASE=http://127.0.0.1:18085 "$ST" 81b799f3-b81e-461d-8aaa-93adbe174798 2>/dev/null)"
rcd=$?
fake_api_stop

assert_eq "run detail exits 0" "0" "$rcd"
assert_contains "run detail reads .run.state, not a flat .state" "succeeded" "$det"
assert_contains "run detail names the task" "Phase 5 auto-merge sliver v2" "$det"
assert_contains "run detail prints the work id" "2425fa21" "$det"
assert_contains "run detail reads the publish branch from session.target" "factory/work-2425fa2124a04c85" "$det"
assert_contains "run detail prints the pull request url" "pull/4" "$det"
assert_contains "run detail prints the delivery mode" "pr+automerge" "$det"
assert_contains "run detail lists every stage" "Deliver" "$det"
if grep -q 'null' <<< "$det"; then
  notok "printed a null: a field was read from the wrong level of the payload"
else
  ok "prints no nulls"
fi

# 4. On pr+automerge the script must not claim a merge it cannot see. The
#    merged ledger row is not exposed by any API route: see Gap 12.
assert_contains "does not claim a merge it cannot observe" "not observable" "$det"

# 5. A refused automatic merge IS observable, because recordMergeRefusal
#    appends the reason to sessions.terminal_message.
REFUSED='{"run":{"id":"35edbeca-6e7d-41ce-a257-2d1ef88c10e1","state":"succeeded","source":"manual","task":{"name":"Phase 5 negative case","submitted_name":"Phase 5 negative case"}},"sessions":[{"id":"90d49170-267e-4176-9769-4158e84ecdfd","state":"ready","delivery":"pr+automerge","pull_request_url":"https://github.com/rexchao1/factory-scratch/pull/5","terminal_message":"Opened PR #5.\nAutomatic merge was refused: the reviewing stage did not record an approve verdict","target":{"publish_branch":"factory/work-90d49170267e4176"},"stages":[{"position":0,"name":"Implement","state":"succeeded"}]}]}'
fake_api_start 18086 "200" "$REFUSED"
ref="$(FACTORY_BASE=http://127.0.0.1:18086 "$ST" 35edbeca-6e7d-41ce-a257-2d1ef88c10e1 2>/dev/null)"
fake_api_stop
assert_contains "surfaces a refused automatic merge" "refused" "$ref"
assert_contains "names the condition that failed" "approve verdict" "$ref"

exit "$TESTS_FAILED"
