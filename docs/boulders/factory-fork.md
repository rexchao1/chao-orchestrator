# Boulder: the fork learns actor, cost, and profile

Project: the factory fork, `github.com/rexchao1/factory`.

## The idea

The checkpoint chain in chao-orchestrator plans work and submits it to the factory, but three things it needs are missing from the factory's API.
An answer to a needs-input question is always recorded as the operator, so an overseer could never be seen answering.
The cost of an attempt is thrown away, so the orchestrator's cost view has to estimate the build side.
A submission cannot name an execution profile, so the build model is a cockpit setting instead of a line in the orchestrator's `config/models.tsv`.

## Checkpoints, in this order

1. Actor on the answer API and attempt cost capture.
   `AnswerWork` takes an actor and the audit trail shows it; `bin/factory-answer --actor` in the orchestrator sends it.
   The worker's result capture (`internal/worker/supervisor.go`, `claudeResultCapture`) keeps `total_cost_usd` and `usage` from claude's final result event, a migration stores them on the attempt, and the Work API exposes them.
2. Execution profile at admission.
   `AdmitWorkRequest` gains an optional execution profile id, admission validates it against the configured profiles, and `bin/factory-submit --profile` sends it.

## Constraints

- Every change carries a Go test.
  Invariants live in Go, not prompts.
- Nothing here changes what is approved or by whom.
  An actor field labels an answer; it does not grant one.
- The orchestrator's side of each change (`bin/factory-answer`, `bin/factory-submit`, `bin/checkpoint-cost` reading the measured cost) is its own checkpoint in the orchestrator, not part of this route.
- Deploying a merged checkpoint needs a restart of the factory, which the human does.
