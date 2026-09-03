# Phase 3: Orchestrator

**Status: done. This repository is the deliverable. Reconciled 2026-09-03.**

**Goal:** you talk to one agent session, describe work in plain language, and a
spec reaches the factory queue. It triages small work past the spec step
entirely.

**Language:** markdown and bash. No compiled code, deliberately.
**Blocked by:** Phase 2.
**Blocks:** nothing. This is the layer that makes the system pleasant rather
than possible.

## Read first

- `design.md` section 4, the decisions on the distro, on the host placement, on
  triage, and on read-only repo access.
- `design.md` `INV-2`, `INV-10`, `AC-8`, `AC-10`.
- `kunchenguid/firstmate`, specifically `AGENTS.md` and `docs/architecture.md`.
  It is the reference implementation of this idea.
- `owainlewis/blueprint`, specifically `skills/plan/SKILL.md`. Its task shape is
  the spec format. Do not invent another one.

## Already decided, do not relitigate

- **This is a distro, not a program.** A repository of `AGENTS.md`, markdown
  skills, and bash helpers. Launching a harness inside it instantiates the
  orchestrator. A program would need a driver per harness and would recreate the
  per-provider adapter problem the whole design exists to avoid.
- **It runs on the host in a tmux session**, reached by SSH from any device, so
  one Claude authentication serves every device and the conversation survives
  switching machines.
- **It never writes to any repository outside its own directory**, including the
  worker's repository caches and worktrees. They now share a machine.
- **Prompts for judgment, scripts for input and output.** Anything that must be
  byte-exact, such as an API payload or a state file, is a script in `bin/`.
- **Triage first.** Isolated work skips the spec and the gate. Only multi-file or
  behavior-defining work gets a written spec and an approval gate.

## Scope

**In:**

1. A new repository, cloned on the host, containing:
   - `AGENTS.md`, the always-loaded operating contract and routing index.
   - `skills/triage`, which classifies a request as isolated or spec-worthy.
   - `skills/spec`, which writes a task in blueprint's `/plan` shape and grounds
     it by reading the relevant read-only clone.
   - `skills/submit`, which calls the toolbelt.
   - `skills/status`, which reports factory state in plain language.
2. A `bin/` toolbelt: `factory-submit`, `factory-status`, `factory-answer`.
   These are the only things that touch the API, so the payload is never
   improvised by a model.
3. Read-only project clones under the distro's own directory, pulled on demand.
4. lavish-axi rendering for specs that pass the triage threshold, so review
   happens in a browser rather than in scrollback.
5. A tmux launch convention so the session is always reattachable.

**Out:**

- Spawning worker sessions. The factory does that. This orchestrator writes
  specs and queues them; it is not firstmate's full crew model.
- Any persistent state the factory could hold instead. If the factory knows it,
  read it; do not cache it.
- Multi-user or Relay-style public interfaces.

## Invariants and criteria satisfied

`INV-2`, `INV-10`. `AC-8`, `AC-10`.

## Test approach

The distro is prose, so most of it cannot be unit tested. Two things can and
must be.

- `AC-8` and `INV-2`: a scripted session against a scratch repository, asserting
  `git status --porcelain` is empty in every read-only clone and in the worker's
  caches afterward. This is the one invariant that a prompt cannot enforce, so it
  gets a real test.
- `AC-10`: submit a request that triage should classify as isolated, and assert
  the resulting Work reached `queued` with no `draft` transition and no written
  spec artifact.
- The `bin/` scripts get ordinary bash tests: correct payload shape, correct
  handling of a rejected submission, correct exit codes.

## Known unknowns to resolve first

- **The triage threshold.** "Isolated versus spec-worthy" is a judgment the skill
  has to make consistently. Start with a concrete rule, such as single file and
  no new public interface, and revise from real misclassifications. Do not start
  with a vague instruction to use judgment.
- **How lavish-axi is invoked from a skill.** It is an AXI, meaning a CLI the
  agent runs. Read `npx -y lavish-axi --help` before designing around it.
- **Whether `claude` is the right harness for this session.** It is the only one
  installed. If Codex or Pi gets installed later, the distro should work
  unchanged; if it does not, that is a bug in the distro, not a reason to add a
  driver.
- **Where the distro repository lives.** A new GitHub repository is the obvious
  answer. Decide whether it is public.

## Done when

- `ssh factorymac && tmux attach -t orchestrator` from any device continues the
  same conversation.
- A plain-language request for a small fix reaches `queued` with no spec step.
- A plain-language request for a feature produces a spec in blueprint task shape,
  renders it for review, and reaches `draft` until approved.
- A full session leaves no diff in any repository outside the distro's own
  directory.
