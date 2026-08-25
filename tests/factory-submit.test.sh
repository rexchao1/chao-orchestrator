#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
SUB="$ROOT/bin/factory-submit"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/config" "$WORK/state"
printf 'scratch\tgithub.com/rexchao1/factory-scratch\t\n' > "$WORK/config/projects.tsv"
printf '## Add a farewell function\n\n### Done when\n- it works\n' > "$WORK/spec.md"

export ORCH_HOME="$WORK"

# 1. Usage.
"$SUB" >/dev/null 2>&1; assert_eq "no args exits 2" "2" "$?"

# 2. An unknown project fails locally, before any request.
out="$(FACTORY_BASE=http://127.0.0.1:1 "$SUB" --project nope --name x --spec-file "$WORK/spec.md" 2>&1)"
assert_eq "unknown project exits 2" "2" "$?"
assert_contains "unknown project names the config file" "projects.tsv" "$out"

# 3. An oversized spec is refused locally, not by an opaque server error.
head -c 40000 /dev/zero | tr '\0' 'x' > "$WORK/big.md"
out="$(FACTORY_BASE=http://127.0.0.1:1 "$SUB" --project scratch --name x --spec-file "$WORK/big.md" 2>&1)"
assert_eq "oversized spec exits 2" "2" "$?"
assert_contains "oversized spec says so plainly" "too large" "$out"

# 4. A successful submission parses the response and records the pointer.
RESP='{"run_id":"5edf217d-53dc-4099-ad56-55e1f27bdd68","task_id":"3bf8ba22-935d-4ef8-9445-9139c3413fc7","work_ids":["b22e40aa-b348-4738-a7a1-051d1c046f72"],"state":"queued","source":"orchestrator"}'
fake_api_start 18085 "201" "$RESP"
out="$(FACTORY_BASE=http://127.0.0.1:18085 "$SUB" --project scratch --name 'Add a farewell function' --spec-file "$WORK/spec.md" 2>/dev/null)"
rc=$?
sent="$(cat "$FAKE_LOG")"
fake_api_stop

assert_eq "success exits 0" "0" "$rc"
assert_contains "prints the run id" "5edf217d" "$out"
assert_contains "prints the work id" "b22e40aa" "$out"
assert_contains "prints the state" "queued" "$out"

# 5. The payload it sent must satisfy the admission contract exactly.
assert_contains "sends runtime claude-code, never the codex default" '"runtime":"claude-code"' "$sent"
assert_contains "sends source orchestrator" '"source":"orchestrator"' "$sent"
assert_contains "defaults to pre_approved true" '"pre_approved":true' "$sent"
if printf '%s' "$sent" | grep -q '"concurrency_limit"\|"execution_profile_id"'; then
  notok "sent a field AdmitWorkRequest does not have: DisallowUnknownFields makes it a 400"
else
  ok "sends no unknown fields"
fi
if printf '%s' "$sent" | grep -q '"delivery"'; then
  notok "sent delivery: the project's server side default_delivery must decide, not a prompt"
else
  ok "sends no delivery, so the project's own setting decides"
fi

# 6. The spec reached the server intact, with the reporting contract appended.
assert_contains "spec text survived JSON encoding" "Add a farewell function" "$sent"
assert_contains "appends the reporting contract" 'Reporting, required' "$sent"

# 7. The pointer was recorded.
assert_contains "records the run id locally" "5edf217d-53dc-4099-ad56-55e1f27bdd68" "$(cat "$WORK/state/submissions.tsv")"

# 8. --draft flips pre_approved, which is the cockpit path, not ours.
fake_api_start 18086 "201" "$RESP"
FACTORY_BASE=http://127.0.0.1:18086 "$SUB" --project scratch --name x --spec-file "$WORK/spec.md" --draft >/dev/null 2>&1
sent2="$(cat "$FAKE_LOG")"
fake_api_stop
assert_contains "--draft sends pre_approved false" '"pre_approved":false' "$sent2"

# 9. A named pipeline is resolved to its id through the API, never guessed.
# One canned body answers both requests, so it carries both shapes.
BOTH='{"pipelines":[{"id":"7ad8c32a-1f0e-4b2a-9c31-2d5f4a6b8e10","name":"Implement, review, deliver"}],"run_id":"5edf217d-53dc-4099-ad56-55e1f27bdd68","task_id":"3bf8ba22-935d-4ef8-9445-9139c3413fc7","work_ids":["b22e40aa-b348-4738-a7a1-051d1c046f72"],"state":"queued","source":"orchestrator"}'
fake_api_start 18087 "200" "$BOTH"
FACTORY_BASE=http://127.0.0.1:18087 "$SUB" --project scratch --name x --spec-file "$WORK/spec.md" \
  --pipeline 'Implement, review, deliver' >/dev/null 2>&1
sent3="$(cat "$FAKE_LOG")"
fake_api_stop
assert_contains "resolves the pipeline name to an id" '"pipeline_id":"7ad8c32a-1f0e-4b2a-9c31-2d5f4a6b8e10"' "$sent3"

# 10. An unknown pipeline name fails locally, and never submits.
fake_api_start 18088 "200" "$BOTH"
out4="$(FACTORY_BASE=http://127.0.0.1:18088 "$SUB" --project scratch --name x --spec-file "$WORK/spec.md" \
  --pipeline 'No Such Pipeline' 2>&1)"
rc4=$?
sent4="$(cat "$FAKE_LOG")"
fake_api_stop
assert_eq "unknown pipeline exits 2" "2" "$rc4"
assert_contains "unknown pipeline lists the real ones" "Implement, review, deliver" "$out4"
if printf '%s' "$sent4" | grep -q 'POST'; then
  notok "submitted anyway after failing to resolve the pipeline"
else
  ok "never submits when the pipeline cannot be resolved"
fi

exit "$TESTS_FAILED"
