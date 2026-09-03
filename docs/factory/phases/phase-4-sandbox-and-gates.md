# Phase 4: Sandbox and mechanical gates

**Goal:** agent runs execute inside a container with an explicit network posture,
and pipelines can run deterministic commands that consume no tokens.

**Language:** Go.
**Blocked by:** Phase 1, specifically its Docker preflight.
**Blocks:** Phase 5.

This phase contains two independent changes. They are grouped because both touch
how a stage executes, but either can ship alone. **Do the code stages first**;
they are smaller, they carry less risk, and they make the sandbox more useful by
giving it something deterministic to verify.

## Read first

- `design.md` section 6, the pipeline stage and execution profile subsections.
- `design.md` `INV-6`, `INV-7`, `AC-6`, `AC-7`.
- `fork-notes.md`, the gap map subsections for the execution profile seam and
  pipeline stage execution, plus the Docker preflight results.
- In the clone: `internal/controlplane/execution_profiles.go`,
  `internal/controlplane/pipelines.go`, `internal/controlplane/stage_runs.go`,
  and the worker's runtime spawn path.
- The fork's own Known Limitations section, which states plainly that execution
  "isolates worktrees and process groups but does not sandbox hostile repository
  code or network egress."

## Already decided, do not relitigate

- The `docker` backend is a new provider **against the existing execution profile
  contract**, not a new abstraction. The fake Cloud Run provider is the model to
  copy.
- A `kind: code` stage carries no prompt and no model, and must skip both prompt
  rendering and runtime spawn. `INV-7` says it consumes zero tokens, and that is
  testable.
- A failing code stage returns control to the preceding agent stage with the
  command output. That is a correction loop, not a restart.
- Structure is gated before logic where a type checker exists. A type error
  caught against a skeleton costs one cheap loop; caught after implementation it
  costs a rewrite.

## Part A: code stages

**In:** a `kind` field on pipeline stages, `agent` or `code`. A `code` stage
declares a command, runs it in the worktree, and fails the stage on non-zero
exit. Typical stages are the repository's type checker, linter, and test command.

**Out:** branching, parallel stages, or conditional stages. The fork's
limitations note it does not do these, and this phase does not add them.

**Test approach:** a pipeline test asserting a `code` stage records no token
usage and no runtime invocation (`AC-6`, `INV-7`), and a test asserting a failing
code stage fails the run without invoking a model in that stage.

## Part B: the Docker backend

**In:** a `docker` value on the execution profile `backend` field, plus a
`sandbox` block carrying image, network posture, cpu, and memory. The worker
spawns the agent inside a container with the worktree bind-mounted.

**Out:** Kubernetes, Cloud Run, or any remote execution. Those are designed
upstream and out of scope here.

**Test approach:** an integration test running a container that attempts an
outbound connection and asserting failure (`AC-7`, `INV-6`).

## The risk that could sink Part B

**Agent authentication inside the container.** This is the thing to resolve
before writing any Go.

Claude Code on the host is authenticated against your subscription, and macOS
typically stores that credential in the Keychain. A Linux container cannot read
the Keychain. So running Claude Code inside a container means one of:

1. Mounting a credential file, if one exists in a portable location.
2. Using API-key authentication inside the container, which abandons
   subscription auth and starts costing per token. This directly contradicts the
   premise the `claude` lane was built on.
3. Sandboxing something other than the agent process, for example running the
   agent on the host but confining the commands it executes.
4. Accepting that the sandbox applies only to non-Claude runtimes.

**Resolve this before committing to an approach.** Investigate where Claude Code
stores credentials on macOS and whether they are portable into a Linux container.
If none of the four options is acceptable, this part of the phase changes shape,
and that is a legitimate outcome to record rather than force.

A second, smaller risk: Docker Desktop for Mac restricts which host paths are
shareable. Phase 1 Task 9 Step 3 tests a bind mount of `~/.factory` specifically
for this reason. Read its recorded result.

## Invariants and criteria satisfied

`INV-6`, `INV-7`. `AC-6`, `AC-7`.

## Done when

- A pipeline containing a failing `kind: code` stage fails the run with no model
  invoked in that stage.
- An agent run with `sandbox.network = "none"` cannot reach the network.
- The authentication question above is answered in writing, whichever way it
  goes.
- All Phase 1 baseline checks still pass, including `just boundary`.
