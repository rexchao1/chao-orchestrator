# Phases

One document per phase. Each is written so a session with zero prior context can
pick it up cold: what to read first, what is already decided, what is still
unknown, and what "done" means.

| Phase | Status | Blocked by | Language |
|---|---|---|---|
| [1. Factory foundation](../plans/2026-08-24-factory-foundation.md) | Done, see [fork-notes.md](../fork-notes.md) | nothing | none, setup only |
| [2. Admission and approval](phase-2-admission-and-approval.md) | Done, fork commits `729f6bd` to `e60a9b1` | Phase 1 | Go, TypeScript |
| [3. Orchestrator](phase-3-orchestrator.md) | Done, this repository | Phase 2 | Markdown, bash |
| [4. Sandbox and gates](phase-4-sandbox-and-gates.md) | Done, fork commit `ceac419` | Phase 1 | Go |
| [5. Auto-merge](phase-5-auto-merge.md) | Done, fork commit `ceac419` | Phase 4 | Go |
| [6. Second worker](phase-6-second-worker.md) | Deferred | Phase 1 | Go, ops |
| [7. Broker route](phase-7-broker-route.md) | Scoped 2026-09-03 | Phase 4 | Go |

Statuses were reconciled on 2026-09-03 from the fork's history.
Each phase document carries the same status on its first lines.

The machines, secrets, and credential broker that the factory runs on are in
the private `infra` repository, and shared agent skills are in
`agent-skills`. Both are under `~/Projects` on the host.

## Reading order for any session

1. [design.md](../design.md), sections 4 and 5. The decisions and the invariants.
2. [roadmap.md](../roadmap.md), the Machines section. Where everything runs.
3. `fork-notes.md`, produced by Phase 1. The gap map naming real files.
4. This phase's own document.

Do not relitigate a decision recorded in design.md section 4 without saying so
explicitly and updating the document. The decisions are there so later sessions
inherit them instead of rediscovering them.

## The rule every phase serves

> Prompts for judgment. Scripts for input and output. Factory Go for invariants.

Anything that must always hold belongs in Go with a test behind it, not in a
prompt.
