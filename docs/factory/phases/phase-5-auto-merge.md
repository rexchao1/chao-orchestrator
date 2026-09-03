# Phase 5: Auto-merge

**Status: done. Landed in the fork in commit `ceac419`, off by default per project. Reconciled 2026-09-03.**

**Goal:** a project can opt in to having its pull requests merged automatically
once the gates pass.

**Language:** Go.
**Blocked by:** Phase 4.
**Blocks:** nothing.

## Read first

- `design.md` `INV-8` and `AC-4`.
- `fork-notes.md`, the gap map subsection for pull request evidence
  verification.
- `owainlewis/blueprint` `skills/task-to-pr/SKILL.md`, the "Merge only when
  asked" section. It already encodes the conditions.

## Already decided, do not relitigate

- **Off by default, per project.** Never global, never on by default.
- **Last, deliberately.** This is the only change that removes a human from the
  loop permanently. It runs on a system whose gates have already earned it,
  which is why it sits behind Phase 4 rather than beside it.
- Merge requires all of: auto-merge enabled for the project, checks passing, and
  a `/review` verdict of Approve. `INV-8` states this and it is one test.

## Scope

**In:**

1. A per-project auto-merge setting, default off, visible in the cockpit.
2. Extension of the existing `ready` verification path to optionally merge.
   The verification already checks repository, publish branch, local HEAD,
   remote ref, and pull request head; merging is a conditional step after it
   succeeds, never a replacement for it.
3. A recorded merge outcome distinguishable from a human merge.

**Out:**

- Merge queues, stacked-branch retargeting, or dependency-ordered batch merges.
  Blueprint's `/task-to-pr` describes those for multi-task work; a single sliver
  does not need them.
- Bypassing repository rules under any circumstance. If GitHub refuses the merge,
  the Work records that and stops.

## Test approach

- `INV-8`: a table test over the three conditions, asserting merge happens only
  when all three hold. Explicitly assert the negative cases; the failure mode
  worth preventing is merging on two of three.
- A test asserting a project with auto-merge disabled never merges, regardless of
  checks and verdict.
- Use the deterministic fake provider rather than live GitHub, as the existing
  lifecycle tests do.

## Known unknowns to resolve first

- **Where the review verdict is recorded.** `/review` is a blueprint skill, so
  its verdict arrives through the agent's outcome report rather than as
  structured factory state. Determine whether the outcome envelope carries
  something machine-readable enough to gate on, or whether Phase 5 must first add
  a field for it. If the verdict is only free text, gating on it is not honest
  and the phase needs that field first.
- **Whether GitHub's own auto-merge should be used** instead of merging directly.
  Enabling GitHub auto-merge on the pull request delegates the checks-passing
  condition to GitHub, which is more robust than polling. It also means the merge
  happens outside factory's view, so the recorded outcome may lag.

## Done when

- A project with auto-merge off never merges, even with green checks and an
  Approve verdict.
- A project with auto-merge on merges only when all three conditions hold.
- A refused merge is recorded, not retried silently.
