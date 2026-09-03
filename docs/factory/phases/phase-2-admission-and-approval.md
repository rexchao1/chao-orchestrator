# Phase 2: Admission and approval

**Status: done. Landed in the fork through commits `729f6bd` to `e60a9b1` (draft state, admission API, approve control). Reconciled 2026-09-03.**

**Goal:** work submitted without a human present waits as a draft until approved,
and work submitted by the orchestrator runs immediately because a human was
already in the loop.

**Language:** Go, plus TypeScript for one cockpit control.
**Blocked by:** Phase 1.
**Blocks:** Phase 3. The orchestrator has nothing to submit against until the
admission contract exists.

## Read first

- `design.md` section 6, the admission table and Work states.
- `design.md` `INV-1`, `INV-9`, `INV-10`.
- `fork-notes.md`, the gap map subsections for the Work state machine, the
  admission path, and the prompt assembly point.
- In the clone: `internal/controlplane/work.go`, `work_http.go`, `state.go`,
  `internal/protocol/`, and `migrations/`.

## Already decided, do not relitigate

- **One queue, two admission paths.** They differ by one field, not by code path.
- **Only `source = "orchestrator"` may set `pre_approved = true`.** A cockpit or
  GitHub submission cannot self-approve. This is the enforcement point that lets
  the orchestrator stay a soft prompt-driven thing.
- **`draft` never expires and never runs.** It is the safe resting state.
- **At most one human gate per run, before the first stage.** `needs-input` is
  agent-initiated and does not count as a gate.
- Approval records the approving actor, not just a boolean.

## Scope

**In:**

1. A `draft` Work state ahead of `queued`. Full set becomes `draft`, `queued`,
   `running`, `needs-input`, `ready`, `succeeded`, `failed`, `no-change`,
   `cancelled`.
2. Admission fields `source`, `pre_approved`, and `delivery` on the submission
   payload. Note that `source` already exists on Run with values `manual` and
   `schedule`; extend that enum rather than inventing a parallel one.
3. `POST /api/work/{id}/approve`, which moves `draft` to `queued` and records
   the actor. Rejects any other source state.
4. A migration adding the state and the new columns.
5. One cockpit control: a drafts view and an Approve button.
6. A test proving the frozen spec appears in every rendered stage prompt
   (`AC-9`, `INV-9`). This may be a pure verification if the behavior already
   holds; if it does not, making it hold is in scope.

**Out:**

- Rejecting or editing a draft. Deleting is enough for now; editing means
  deciding what happens to an in-flight edit, which is a design question.
- GitHub issue ingestion. The fork has `docs/github-ingest/design.md` and
  `docs/github-webhooks.md`; that is its own phase when wanted.
- Any change to how work executes once queued.

## Change surface

Confirm every path against the gap map before editing; these are the expected
locations, not verified ones.

| Change | Expected location |
|---|---|
| State constants | `internal/controlplane/state.go` or `work.go` |
| Transition function | `internal/controlplane/work.go` |
| Admission handler | `internal/controlplane/work_http.go` |
| Wire types | `internal/protocol/` |
| Schema | `migrations/`, next unused number |
| Cockpit | `web/` |

## Invariants and criteria satisfied

`INV-1`, `INV-9`, `INV-10`. `AC-1`, `AC-2`, `AC-3`, `AC-9`.

## Test approach

Follow the existing `work_http_test.go` and `work_lifecycle_test.go` patterns
against a temporary SQLite database.

- `AC-1`: a submission with `pre_approved: false` lands in `draft` and no worker
  claims it. Assert by advancing the scheduler and checking no Attempt exists.
- `AC-2`: a submission with `source: "orchestrator"` and `pre_approved: true`
  reaches `queued` with no approval record required.
- A submission with `source: "cockpit"` and `pre_approved: true` is **rejected**.
  This is the real teeth of `INV-1` and is easy to forget.
- `AC-3`: the same `request_key` twice creates one Work record.
- `AC-9`: assemble a multi-stage Run and assert the frozen spec text appears in
  every rendered stage prompt.
- `INV-10`: assert a queued Run has exactly zero approval gates remaining.

Keep `just boundary`, `just vet`, and `just format-check` passing.

## Known unknowns to resolve first

- **Where the Work state enum actually lives.** The gap map answers this. If
  states are declared in `internal/core/wire.ts`-style shared protocol code,
  adding one touches both the control plane and the worker, and the boundary
  check will tell you.
- **Whether the cockpit needs a Node build.** The fork ships committed embedded
  UI assets and says Node is only required when changing the browser UI. Adding
  an Approve button means running `just ui-install` and `just ui-build` and
  committing regenerated assets. Budget for it, and check whether the
  regenerated bundle produces a large diff that will make upstream merges
  painful. If it does, consider whether the approve action can live in the CLI
  for this phase and reach the UI later.
- **Whether `delivery` belongs on Work or on the execution profile.** The
  profile is immutable per Run and already carries backend, runtime, provider,
  and model. Delivery mode is the same shape of thing. Prefer the profile unless
  the gap map shows that is awkward.

## Done when

- A cockpit submission waits in `draft` and does not run.
- An orchestrator submission with `pre_approved: true` runs without further
  action.
- A non-orchestrator submission claiming `pre_approved: true` is rejected.
- Approving a draft records who approved it.
- All Phase 1 baseline checks still pass.
