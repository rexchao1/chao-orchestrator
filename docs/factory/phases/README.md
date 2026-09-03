# Phases

One document per phase. Each is written so a session with zero prior context can
pick it up cold: what to read first, what is already decided, what is still
unknown, and what "done" means.

| Phase | Status | Blocked by | Language |
|---|---|---|---|
| [1. Factory foundation](../plans/2026-08-24-factory-foundation.md) | Plan written, not started | nothing | none, setup only |
| [2. Admission and approval](phase-2-admission-and-approval.md) | Scoped | Phase 1 | Go, TypeScript |
| [3. Orchestrator](phase-3-orchestrator.md) | Scoped | Phase 2 | Markdown, bash |
| [4. Sandbox and gates](phase-4-sandbox-and-gates.md) | Scoped | Phase 1 | Go |
| [5. Auto-merge](phase-5-auto-merge.md) | Scoped | Phase 4 | Go |
| [6. Second worker](phase-6-second-worker.md) | Deferred | Phase 1 | Go, ops |

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
