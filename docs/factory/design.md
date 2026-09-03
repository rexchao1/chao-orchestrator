# Personal software factory: orchestrator, approval, and delivery

> **Status:** Proposed for review
> **Date:** 2026-08-24

## 1. Executive summary

Today a coding task means opening a terminal, explaining context to an agent,
watching it work, and remembering which window held which job. Running three
tasks at once means becoming a tab manager. The existing ChaoFactory walking
skeleton solves part of this: it queues a prompt, runs it in an isolated git
worktree, and records events. It stops at a local branch, has no spec step, no
human approval point, and no delivery.

This design replaces that with a four layer system. You talk to one agent, the
orchestrator. It reads your code, writes a short spec that both you and an
agent can read, and shows it to you. You approve. A factory host queues the
spec, runs a coding agent inside a sandbox on an isolated worktree, verifies
what the agent claims, and delivers a pull request. Auto merge is available and
off by default.

The main decision is to stop building the factory. A fork of
`owainlewis/factory` (MIT, Go) already implements leases, heartbeats, retries,
idempotent admission, worktree isolation, versioned pipelines, model routing,
a scoped agent report socket, and mid run question and resume. Four things it
lacks are added to the fork. All remaining effort goes into the orchestrator,
which is the part nobody has built for this workflow.

The main downside is a language split. The factory becomes Go rather than
TypeScript, and the ChaoFactory walking skeleton is retired as a working
prototype rather than shipped. The judgment is that reimplementing durable
lease and resume semantics in TypeScript costs more than learning enough Go to
change four contained areas of an existing implementation.

## 2. Context and scope

The current implementation is one Node process. `src/dispatcher.ts` polls
SQLite every second, claims the oldest queued task, creates a worktree, spawns
`claude -p`, and parses its stdout. `src/drivers/` holds one adapter per lane.
`config/routing.json` maps a task class to a lane and model.

Three properties of that design do not survive contact with the intended
workflow.

The dispatcher and the worker are the same process, and `inFlight` is a
variable in memory. Crash recovery assumes the only failure is your own
restart. Work claimed by a dead process stays `running` forever.

Behavior branches on lane kind strings rather than declared capabilities.
`dispatcher.ts` decides whether to create a worktree with
`route.config.kind !== 'ollama-chat'`. Every new lane adds a clause.

The result contract is a free text summary parsed out of one harness's stdout
format. Nothing downstream can verify a claim, and every new harness is a new
parser.

What changes once this ships: you describe work in plain language to one
persistent agent, review a written spec before anything runs, and receive pull
requests. What stays: your existing repositories, your existing subscription
authenticated CLIs, and loopback plus Tailscale as the only network exposure.

Out of scope for this design: multi user access, a hosted service, and any
model provider aggregation layer.

## 3. System context

```text
     you, from any device: laptop, desktop, phone
          |                              |
          | ssh + tmux                   | browser over `tailscale serve`
          v                              v
 +=====================================================================+
 |  Mac mini (the host)                                                |
 |                                                                     |
 |  +---------------------+        +---------------------------+       |
 |  | Orchestrator        |        | Factory cockpit           |       |
 |  | an agent distro     |        | drafts, runs, approvals   |       |
 |  | in a tmux session   |        +-------------+-------------+       |
 |  | own read-only clones|                      |                     |
 |  +----------+----------+                      |                     |
 |             | POST spec (pre-approved)        | POST spec (draft)   |
 |             +----------------+----------------+                     |
 |                              v                                      |
 |             +--------------------------------+                      |
 |             | factory-server (forked, Go)    |                      |
 |             | SQLite, admission, leases,     |                      |
 |             | draft state, execution         |                      |
 |             | profiles, PR evidence          |                      |
 |             +---------------+----------------+                      |
 |                             ^ claim / heartbeat / events / update   |
 |                             |                                       |
 |             +---------------+----------------+                      |
 |             | factory-worker                 |                      |
 |             | repo cache, worktrees,         |                      |
 |             | docker sandbox, agent procs    |                      |
 |             +---------------+----------------+                      |
 |                             |                                       |
 |                   Claude Code running blueprint skills              |
 +=====================================================================+
```

Everything runs on one host. Your devices are thin clients holding an SSH
terminal and a browser, nothing else. The orchestrator's read-only clones live
in its own directory and are distinct from the worker's repository caches,
which it must never touch.

The orchestrator never writes to a repository. The factory never makes
engineering decisions. The coding agent never receives an operator credential.

## 4. Proposed design

### How it works

You are on your laptop. You type into the orchestrator session: "the login
test is flaky, and I want dark mode."

The orchestrator reads its read-only clone of the project, decides these are
two independent slivers, and runs blueprint's `/plan` skill to write two specs
in its task shape: a plain language title, "What are we building", "Why", "Done
when", "How to check", and an "Agent notes" section carrying the decisions and
constraints. It renders both through `lavish-axi` and gives you a browser link.

You read them, annotate the dark mode one to say the toggle belongs in
settings rather than the header, and approve both. Because you were in the loop
while the spec was written, the orchestrator submits them **pre approved**, and
they enter the queue directly.

Separately, a week later, you open the cockpit on your phone and type a feature
request straight into it. Nobody has reviewed that text, so it is admitted as a
**draft**. It sits until you approve it from the cockpit.

For each queued item the factory creates one Work record with a frozen
execution profile naming the backend, runtime, provider, model, and timeout.
A worker claims it under a lease, prepares an isolated worktree, and starts the
pipeline stages in order inside a Docker sandbox. The stages run blueprint
skills: implement, then `/test` as a deterministic code stage, then `/review`
with a fresh agent that did not write the code.

The agent reports through `factory update`, a command the worker injects that
talks to an Attempt scoped Unix socket authenticated by Work ID, Attempt ID,
and a token. When it claims `ready`, the factory does not take its word. It
verifies the repository, publish branch, local HEAD, remote ref, and pull
request head before accepting.

If the agent hits a decision the spec does not contain, it commits a clean
checkpoint and reports `needs-input`. The attempt ends with no process and no
lease alive. The question appears in the cockpit. Your answer requeues the same
Work and resumes from that exact commit.

The delivered artifact is a pull request. Auto merge is a per project option,
off by default.

### Components and responsibilities

**Orchestrator (agent distro).** Owns conversation, triage, spec authoring, and
submission. It runs on the host in a persistent terminal multiplexer session, so
any device that can SSH reaches the same conversation. It reads its own
read-only clones to ground specs and reads factory state to report status. It
does not own the queue, does not run coding agents, and never writes to any
repository, including the worker's caches.

**Approval surface.** Owns the human decision point. `lavish-axi` renders
orchestrator authored specs for annotation. The cockpit owns approval of drafts
admitted without an orchestrator. Both end by setting one field.

**Factory server (forked).** Owns durable state, admission, the draft and
approval state machine, leases, scheduling, execution profiles, outcome
verification, and the cockpit. It is the only component that writes lifecycle
state.

**Factory worker.** Owns repository caches, worktrees, sandbox lifecycle, agent
child processes, and cleanup. It decides how to execute one claim safely on its
machine. It never imports control plane code.

**Blueprint skills.** Own the engineering phases. Installed into each target
repository, not into the factory. `/design`, `/plan`, `/task-to-pr`, `/test`,
`/review`.

### Decisions

**Fork rather than build.** The forked factory already implements the hardest
parts: lease and heartbeat semantics, idempotent admission with replay keys,
checkpoint and resume from an exact SHA, and evidence backed outcome
verification. Rebuilding these in TypeScript would take months and would be
less correct. The cost is writing Go for four contained changes and tracking
upstream, which is in developer preview and expects breaking changes.

**The orchestrator is a distro, not a program.** Its work is judgment, and a
program wrapping that work would need a driver per harness, recreating the
per provider adapter problem one layer up. A distro is `AGENTS.md` plus
markdown skills and runs unchanged on any harness. The cost is that its
behavior is requested rather than enforced.

**Invariants live in the factory, not the orchestrator.** This is what makes
the previous decision safe. The orchestrator can be soft because the boundary
it talks to is hard. An unapproved submission is rejected by the server, not by
a prompt. The rule: prompts for judgment, scripts for input and output, Go for
invariants.

**Both admission paths, one queue.** Orchestrator submissions and cockpit or
GitHub submissions differ by one field, not by code path. The orchestrator
submits pre approved because you were present while the spec was written, which
is also the token saving: the factory never re derives a decision already made.

**Structured report over stdout parsing.** The agent calls a scoped command
rather than printing a format the factory parses. Every harness can run a
command; none share a stdout format. Stream parsing remains, downgraded to
telemetry for the live view rather than the contract.

**The orchestrator runs on the host, not on your device.** Grounding in real
code is what separates a useful spec from a vague one, and vague specs are the
main cause of bad runs, so the orchestrator needs to read repositories. Putting
it on the host gives it that access against clones the worker already maintains,
while keeping every client device thin: one Claude Code authentication instead
of one per device, and a conversation that survives switching machines because
the session is attached rather than restarted. The cost is that a host outage
takes the orchestrator with it, which is not a real loss because the same outage
takes the queue.

**Orchestrator repo access is read only, and its clones are its own.** Clones
under the orchestrator's directory are a reading cache, never a working copy.
Now that the orchestrator shares a machine with the worker, `INV-2` also means
it must never write to the worker's repository caches or worktrees.

**Not every task enters the pipeline.** The orchestrator triages first. An
isolated fix or a single-file tweak is submitted as a one-stage Work item and
goes straight to execution. Only multi-file or behavior-defining work gets a
written spec and an approval gate. Treating every prompt the same is the main
way a factory becomes slower than a terminal.

**One gate, then autonomy.** There is exactly one human checkpoint, and it sits
before execution begins, not inside it. Once you approve a spec the agent runs
to a pull request without asking permission again. Mid-run stops exist, but the
agent decides when to take one and only when the spec genuinely does not
contain a needed decision. Stacking approval gates inside a run fragments the
agent's context and costs more than it catches.

**The spec is a lock, not a handoff note.** Every agent stage receives the
complete frozen spec, never a summary of what a previous stage did. This is what
makes multi-stage execution safe: a fresh process loses the previous process's
reasoning, but it does not lose the contract. Where a stage needs to know what
happened before it, that goes in the stage's own recorded result, additive to
the spec rather than replacing it.

**Fragment context only when independence is the point.** A pipeline that runs
implement, then test, then review as three fresh agent processes throws away
context twice for no gain. Prefer one agent running `/task-to-pr`, which invokes
test and review as subagents while holding the full picture. Use a separate
pipeline stage only where the fresh context is the feature, as with a reviewer
that must not have written the code.

**Gate on structure before logic.** Where a repository has a type checker or
compiler, the first code stage checks interfaces, signatures, and types before
any function body is written. A type error caught against a skeleton costs one
cheap loop. The same error caught after implementation costs a rewrite.

## 5. Invariants and requirements

### Invariants

- `INV-1`: Work never leaves `draft` without a recorded human approval, either
  an explicit cockpit approval or an orchestrator submission carrying the
  pre approved flag.
- `INV-2`: The orchestrator never writes to any path inside a repository
  outside its own directory.
- `INV-3`: An outcome of `ready` is accepted only after the server verifies
  repository, publish branch, local HEAD, remote ref, and pull request head.
- `INV-4`: A `needs-input` outcome requires a clean worktree and a checkpoint
  revalidated after the process stops.
- `INV-5`: Resume prepares from the pending checkpoint SHA. No other ref is
  used as a fallback.
- `INV-6`: Every agent process runs inside a sandbox with an explicit network
  posture. No agent process runs with the operator credential in its
  environment.
- `INV-7`: A code stage never invokes a model and never consumes tokens.
- `INV-8`: A pull request is merged automatically only when the project has
  auto merge enabled, checks pass, and the review verdict is Approve.
- `INV-9`: Every agent stage receives the complete frozen spec. No stage
  receives only a summary produced by a previous stage.
- `INV-10`: A run has at most one human approval gate, and it occurs before the
  first stage starts. `needs-input` is agent initiated and is not a gate.

### Requirements

- One factory host holds one queue. Any number of clients may submit.
- Admission is idempotent under a request key, so two clients submitting the
  same work create one Work record.
- The operator API binds loopback. Remote browser access is fronted by
  `tailscale serve`. No process binds `0.0.0.0`.
- The default delivered artifact is a pull request. Delivery mode is selectable
  per project and visible in the cockpit.

## 6. Interfaces and data

### Admission

`POST /api/work` accepts a spec in blueprint task shape plus:

| Field | Meaning |
|---|---|
| `repository` | managed repository identity |
| `spec` | markdown, blueprint task shape |
| `source` | `orchestrator`, `cockpit`, or `github` |
| `pre_approved` | boolean; only `orchestrator` may set true |
| `request_key` | idempotency key |
| `delivery` | `pr`, `pr+automerge`, or `branch`; defaults to project setting |

A submission with `pre_approved: false` creates Work in `draft`.
`POST /api/work/{id}/approve` moves `draft` to `queued` and records the actor.

### Work states

`draft` is added ahead of the existing set. Full set:
`draft`, `queued`, `running`, `needs-input`, `ready`, `succeeded`, `failed`,
`no-change`, `cancelled`.

### Pipeline stages

A stage gains a `kind` field. `kind: agent` is the existing behavior. `kind:
code` runs a declared command in the worktree, inside the same sandbox, and
fails the stage on a non zero exit. Code stages carry no prompt and no model.

Typical code stages are the repository's type checker or compiler, its linter,
and its test command. A failing code stage returns control to the preceding
agent stage with the command output, which is a cheap correction loop rather
than a restart.

### Execution profile

The existing immutable profile gains `sandbox`:

```
backend = "persistent-auto" | "docker"
sandbox = { image, network = "none" | "allowlist" | "open", cpu, memory }
```

### Naming and identity

Work IDs are server generated and never derived from spec content, so editing a
spec cannot collide with existing Work. Branch names derive from the Work ID,
not the spec title, so a retitled spec does not orphan a branch. The publish
branch is fixed at admission and is immutable for the life of the Work.

## 7. Failure behavior and lifecycle

A worker that dies mid run loses its lease after 30 seconds. The control plane
returns that Work to `queued` and a later attempt reclaims it. The retained
worktree is reported rather than deleted, so failed work stays inspectable.

An agent that exits without calling `factory update` fails the attempt with a
process exit outcome. An agent that claims `ready` but fails evidence
verification fails the attempt and retains the worktree.

A sandbox that cannot start fails the attempt before any agent runs, and the
Work returns to `queued` for a worker whose profile it can satisfy.

Orchestrator loss is not a factory event. Queued and running Work is unaffected
because the orchestrator holds no lifecycle state. Reattaching or restarting the
session reconciles by reading factory state. A dropped SSH connection does not
end the session, because it runs under a multiplexer on the host.

Host loss stops everything: queue, workers, and orchestrator. This is accepted.
A single host holding one queue is the property that makes submissions from many
devices safe, and splitting it to survive an outage would cost that.

A draft never expires and never runs. It is the safe resting state.

## 8. Security, privacy, and operations

The trust boundary is the tailnet. The operator API binds loopback and is
reached remotely only through `tailscale serve`, which supplies transport
security and device identity. No component binds a public interface.

The coding agent is the untrusted party inside this system. It runs in a Docker
sandbox with an explicit network posture and receives no operator credential.
Git push credentials are held by the worker, not passed into the agent
environment.

Repository code is the second untrusted input. Until the Docker backend lands,
agent runs remain limited to repositories you trust. That limit is the current
posture and is what the sandbox exists to remove.

Shared limits: one factory host, worker slots bounded per worker, per Run
concurrency frozen at admission. At the limit, Work waits in `queued` rather
than being rejected.

## 9. Acceptance criteria

- `AC-1`: A spec submitted with `pre_approved: false` appears in the cockpit as
  a draft and does not start a run until approved.
- `AC-2`: A spec submitted by the orchestrator with `pre_approved: true` starts
  without further action.
- `AC-3`: Submitting the same `request_key` twice creates one Work record.
- `AC-4`: A completed sliver produces a pull request whose head commit the
  server verified before marking the Work `ready`.
- `AC-5`: An agent that reports `needs-input` leaves no running process and no
  held lease, and answering it resumes from the recorded checkpoint SHA.
- `AC-6`: A pipeline containing a failing `kind: code` stage fails the run
  without invoking a model in that stage.
- `AC-7`: An agent run with `sandbox.network = "none"` cannot reach the
  network.
- `AC-8`: The orchestrator produces no diff in any repository outside its own
  directory across a full session.
- `AC-9`: In a multi-stage run, the rendered prompt for every stage contains the
  full spec text.
- `AC-10`: A task the orchestrator triages as isolated reaches execution without
  a written spec or an approval step.

## 10. Test approach

`AC-1` through `AC-3` and `INV-1` are covered by control plane HTTP tests
against a temporary SQLite database, following the existing
`work_http_test.go` pattern in the fork.

`AC-4`, `AC-5`, `INV-3`, `INV-4`, and `INV-5` are covered by lifecycle tests
using the existing deterministic fake provider, asserting on stored checkpoint
and pull request evidence rather than on live GitHub.

`AC-6` and `INV-7` are covered by a pipeline test asserting a code stage
records no token usage and no runtime invocation.

`AC-7` and `INV-6` are covered by an integration test that runs a container
attempting an outbound connection and asserts failure.

`AC-8` and `INV-2` are covered by a scripted orchestrator session against a
scratch repository, asserting `git status --porcelain` is empty afterward.

`AC-9` and `INV-9` are covered by a prompt-assembly test asserting the frozen
spec appears in every rendered stage prompt of a multi-stage Run.

`AC-10` and `INV-10` are covered by an admission test asserting a one-stage
submission carrying `pre_approved` reaches `queued` with no approval record
required and no `draft` transition.

## 11. Risks and tradeoffs

**Upstream churn.** The fork tracks a developer preview project that expects
breaking changes. Mitigation: keep the fork thin, keep changes in contained
areas, and offer the Docker backend and code stages upstream so they stop being
fork carried.

**Distro behavior is requested, not enforced.** The orchestrator can violate
its own rules. Mitigation: every rule that matters is an invariant in the
factory, so a misbehaving orchestrator is rejected rather than obeyed. `INV-2`
is the exception and is verified by test, not by prompt.

**Spec quality is the ceiling on run quality.** A vague spec produces a bad run
no matter how good the factory is. Mitigation: blueprint's `/plan` shape and
the human approval gate exist precisely for this, and `needs-input` catches
what the spec missed rather than guessing.

**Context fragmentation across stages.** The forked factory starts a fresh agent
process for each pipeline stage. A fresh process that receives only a handoff
note produces work that is locally correct and globally wrong. Mitigation is
`INV-9`, plus a strong default of one stage per Work item. Multi-stage is the
exception, justified per pipeline, not the normal shape.

**Over-gating.** Every added checkpoint is latency, cost, and one more place to
lose context, and checkpoints tend to accumulate. Mitigation is `INV-10`: the
gate count is an invariant with a test, not a preference.

**Language split.** Go for the factory, markdown and bash for the orchestrator,
TypeScript retired. Accepted deliberately in exchange for not reimplementing
lease and resume semantics.

## 12. Open questions

- Which repositories get blueprint skills installed first, and does the
  orchestrator install them or does each repository own that? Does not block
  starting work.
- Does the orchestrator run its own read-only clones, or read your existing
  checkouts when present? Does not block starting work; clones are the safer
  default.
- Should `lavish-axi` review be the default for every spec, or only above a
  size or risk threshold? Does not block starting work.

## 13. Out of scope

- Multi user access, role based access control, and per user attribution.
- Any model provider aggregation layer. The OpenAI compatible base URL seam is
  sufficient if a chat lane is ever needed, and LiteLLM would be a
  configuration change rather than a design change.
- Kubernetes or cloud execution backends.
- Branching or parallel pipeline stages.
- Retiring the ChaoFactory prototype is assumed, not designed. Its
  `config/routing.json` class matrix is the one idea worth carrying into
  execution profiles.
