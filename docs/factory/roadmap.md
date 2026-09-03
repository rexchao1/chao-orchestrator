# Implementation roadmap

Source design: [design.md](design.md). Per-phase scopes: [phases/](phases/README.md).

The design covers three independent subsystems in two languages, so it is built
as six plans rather than one. Each plan produces a working, testable result on
its own, and each is written only when its predecessor has made its details
knowable.

## Why not one plan

Plans 2, 4, and 5 change Go code in a repository that is not cloned yet. A plan
for them written today could not name a real file or line, and a plan full of
"find the relevant handler" is not a plan. Plan 1 ends by producing
`fork-notes.md`, which maps each remaining change to exact files and functions.
Plans 2, 4, and 5 are written from that.

## Machines

One host. Every other device is a thin client.

| Role | Machine | Holds |
|---|---|---|
| Host | Mac mini, Apple silicon | Everything: `factory-server`, `factory-worker`, the Go toolchain, the fork clone, the orchestrator session, SQLite state, Docker, repository caches, worktrees, `gh` and Claude Code authentication, tailscale. |
| Client | WSL box, laptop, phone | An SSH terminal and a browser. Nothing installed. |

Nothing irreplaceable lives on a client. Source is a git clone, tooling is
reinstallable, and all state is on the host. This is deliberate: you should be
able to open a laptop, `ssh factorymac`, attach to the orchestrator session, and
continue mid-thought.

Go lives on the host so the host builds itself. A deploy from any device is
`ssh factorymac 'cd ~/factory && git pull && just build'`, which means no client
ever needs a Go toolchain. Go source is edited through VS Code Remote-SSH
against the host's single clone, so there is no push-and-pull round trip while
iterating.

Workers poll outbound to the server. The operator API binds loopback and is
reached through `tailscale serve` or an SSH tunnel.

## The plans

### Plan 1: Factory foundation

**Status:** written, [plans/2026-08-24-factory-foundation.md](plans/2026-08-24-factory-foundation.md)

Prepare the Mac mini, fork and build `owainlewis/factory` on it, install
blueprint skills into a scratch repository, and drive one real sliver to a pull
request using entirely stock software.

**Deliverable:** a working end-to-end factory with zero custom code, a verified
`needs-input` and resume path (`AC-5`), a recorded docker preflight, and
`docs/factory/fork-notes.md` mapping the four remaining gaps to real code.

**Why first:** it de-risks everything. If stock factory plus blueprint skills
already delivers a reviewed pull request, the remaining four changes are
improvements to a working system rather than prerequisites for an unproven one.

### Plan 2: Admission and approval

**Depends on:** Plan 1.

Add the `draft` Work state ahead of `queued`, a `POST /api/work/{id}/approve`
endpoint that records the approving actor, the `pre_approved` and `source`
admission fields, and an approve control in the cockpit.

**Deliverable:** work submitted without a human present waits as a draft;
`AC-1`, `AC-2`, `AC-3` pass.

**Why second:** it is the smallest Go change, and Plan 3 has nothing to submit
against until the admission contract exists.

### Plan 3: Orchestrator distro

**Depends on:** Plan 2.

A new repository, cloned on the host, containing `AGENTS.md`, a triage skill, a
spec-authoring skill built on blueprint's `/plan` task shape, a `bin/` toolbelt
that submits to the factory and reads its state, and lavish-axi rendering for
review. It runs in a persistent multiplexer session so any device that can SSH
attaches to the same conversation.

**Deliverable:** you describe work in plain language to one agent session and a
spec reaches the factory queue; `AC-8` and `AC-10` pass.

**Language:** markdown and bash. No compiled code, by design.

### Plan 4: Sandbox and mechanical gates

**Depends on:** Plan 1. Independent of Plans 2 and 3.

A `docker` execution-profile backend, and `kind: code` pipeline stages that run
a declared command with no model and no tokens.

**Deliverable:** agent runs are network-isolated and mechanically verified;
`AC-6`, `AC-7`, `INV-6`, `INV-7` pass.

**Environment note:** Docker runs on the Mac mini, not on the WSL box, because
the worker is what executes agents. The earlier WSL Docker Desktop blocker no
longer applies. Plan 1 still verifies Docker and `--network none` isolation on
the Mac before this plan starts.

### Plan 5: Auto-merge

**Depends on:** Plan 4.

Per-project auto-merge, off by default, gated on passing checks and an Approve
verdict.

**Deliverable:** `AC-4` extended to merge; `INV-8` passes.

**Why last:** deliberately. It is the only change that removes a human from the
loop permanently, and it should only run on a system whose gates have already
earned trust.

### Plan 6: Second worker

**Depends on:** Plan 1. Not scheduled.

Enroll the WSL box as a second worker so runs can execute on either machine.

**Deliverable:** two workers advertising capacity to one control plane.

**Why deferred:** the fork's own limitations state that remote workers require
operator-managed TLS certificates and enrollment. That cost buys nothing until
one worker is actually saturated. Written when the Mac mini becomes a
bottleneck, not before.

## Dependency order

```text
Plan 1 ──┬── Plan 2 ── Plan 3
         ├── Plan 4 ── Plan 5
         └── Plan 6 (deferred)
```

Plans 2 and 4 can run in parallel. Plan 3 is the only one that is not Go.
