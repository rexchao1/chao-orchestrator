# Fork notes

Fork of `owainlewis/factory`. Clone and toolchain both live on the Mac mini at
`~/Projects/factory`. Client devices hold no source and no Go toolchain.

**2026-09-03: history detached.** `~/Projects/factory` no longer has an
`upstream` remote and its git history was rewritten down to just the commits
written here, starting at what was `994fe6c`. The commit SHAs quoted below as
"upstream" facts are still accurate as history, they just are not reachable
from `origin` anymore. `github.com/rexchao1/factory` is a plain standalone
repo now, not a GitHub fork of `owainlewis/factory`.

## Host

| Fact | Value |
|---|---|
| Machine | Mac mini, Apple silicon |
| macOS | 26.4 |
| Architecture | arm64 |
| SSH alias | `factorymac` |
| Tailnet name | `mickeys-mac-mini.taildcfadb.ts.net` |
| Tailnet IPv4 | `100.117.235.1` |
| Go | `go1.25.13 darwin/arm64` |
| gh | 2.98.0, authenticated as `rexchao1` |
| Claude Code | 2.1.241, at `~/.local/bin/claude` |
| Docker | 29.7.2 |
| Clone path | `~/Projects/factory` |
| Binaries | `~/.factory/bin/{factory,factory-server,factory-worker}` |

## Baseline

Recorded on first build, before any local change.

- Upstream commit: `a9adbded8f3e79b2c388895ddbda6154b2556070`
  (`a9adbde`, 2026-08-23, "Merge pull request #352 from
  owainlewis/codex/issue-343-resume-retry")
- Fork HEAD at clone: `a9adbde`, identical to upstream
- `go test ./...`: PASS. Every package `ok` or no test files. 1m24s total.
  The `internal/worker` package is 82s of that, `internal/controlplane` 9.8s.
- `just vet`: PASS, exit 0, no output
- `just format-check`: PASS, exit 0, no output
- `just boundary`: PASS, exit 0, no output
- Highest migration: `034_resume_recovery.sql`. Plan 2 adds `035`.

## Deviations from Plan 1

Recorded because Plans 2, 4, and 5 inherit them.

**The plan's fork command fails on gh 2.98.0.** `gh repo fork owainlewis/factory
--clone --remote --fork-name factory` is rejected with "the `--remote` flag is
unsupported when a repository argument is provided". Used `--clone
--fork-name` and added `upstream` by hand, which is the fallback Plan 1 Task 3
Step 1 already documents.

**The clone path is `~/Projects/factory`, with a capital P.** That is the
directory that already existed on the host. APFS is case insensitive, so the
lowercase form in the plans resolves to the same place, but the real name is
capitalized.

**The old TypeScript prototype was deleted, not moved.** It occupied the same
path. Its code is recoverable at commit `1358d9f`. Its gitignored `data/`
directory, holding a SQLite trace database and old worktrees from the Aug 20
runs, is gone.

**Claude Code installs to `~/.local/bin` and only writes `.zshrc`.** The native
installer puts its PATH entry in `.zshrc`, which only interactive shells read.
The worker runs under tmux, which starts a login shell, and a login shell reads
`.zprofile`. Without the entry in `.zprofile` the agent binary is not found.
Added to `~/.zprofile` on the host and to `scripts/bootstrap-host.sh`.

**`gh auth login` alone does not authenticate git.** The host had a valid `gh`
session but `git pull` over HTTPS failed with "could not read Username". Plan 1
assumes `gh auth login` is enough. It is not for plain git operations. Ran
`gh auth setup-git`, which installs the credential helper globally.

**`factory-worker` takes `-config PATH`, not a positional argument.** Plan 1
Task 5 Step 3 passes the config path positionally, where Go's flag package
ignores it. The default is `~/.factory/worker.toml`, so the mistake is silent.

**`node --test test/` fails on Node 22.23.2.** Plan 1 Task 6 Step 2 sets that as
the scratch repository's test command. Node resolves `test/` as a module entry
point and exits with `MODULE_NOT_FOUND`, so the suite never runs. Changed to
plain `node --test`, which auto discovers test files and also picks up whatever
new test file an agent adds. Verified `# pass 1`, `# fail 0`.

**Blueprint was installed by copying, not by `npx skills add`.** Blueprint
skills are portable single `SKILL.md` files, so installation is a file copy.
Copied all ten from a shallow clone of `owainlewis/blueprint` at commit
`722e5f99878abaf285188e3ca39bac1efacaf372` into
`.claude/skills/`. The five Plan 1 requires are present: `design`, `plan`,
`task-to-pr`, `test`, `review`.

## Submission works over the API, not only the cockpit

Plan 1 Tasks 7 and 8 are written as browser steps. Everything except answering
a `needs-input` question can be driven over the loopback API through an SSH
tunnel, which is also how the orchestrator will submit later.

| Step | Call |
|---|---|
| Register a repository | `POST /api/v1/repositories` with `{"remote_identity": "github.com/owner/name"}` |
| Check routing | `GET /api/v1/repositories/{id}/readiness` |
| Create a task | `POST /api/v1/tasks` with `protocol.SaveTaskRequest` |
| Start it | `POST /api/v1/tasks/{id}/run` with a `request_key` |

`SaveTaskRequest` requires `name`, `prompt`, `runtime`, `timeout_seconds`,
`concurrency_limit`, `repository_ids`, and `schedule`. Send
`{"enabled": false}` as the schedule for a one shot task.

A task created without a pipeline defaults to pipeline
`00000000-0000-0000-0000-000000000001`, "Single agent", and to
`outcome_contract: process_exit`. That default is worth noting against `INV-3`,
which requires evidence verification before accepting `ready`. Plan 5 has to
change the contract, not just the verification.

## Host findings that change how the system is run

### The worker must be started from a GUI session

Claude Code stores credentials in the macOS Keychain, not in
`~/.claude/.credentials.json`. A session started over SSH cannot read that
keychain, so `claude auth status --json` returns `loggedIn: false` and the
worker publishes the claude-code runtime as `unauthenticated`, leaving the
whole worker `unhealthy`. Verified both ways: `loggedIn: false` over SSH,
`loggedIn: true` in Terminal.app on the same machine, same user, same binary.

The tmux server inherits this from whatever started it. Starting it over SSH
poisons every process inside it, including the agent the worker spawns.

The host processes are therefore started by running `scripts/start-factory.sh`
in Terminal.app on the Mac. The script refuses to run when `SSH_CONNECTION` is
set and checks `claude auth status` before starting anything. After that the
sessions are inspectable over SSH normally. This also applies after a reboot,
since Plan 1 installs no launchd service.

With the tmux server started from a GUI session, all three capabilities report
`ready` and the worker reports `healthy`.

### `tailscale serve` cannot reach the operator API

This is a fifth gap, not covered by Plan 1's four.

`validateRequestHost` in `internal/controlplane/http.go:763` accepts only
loopback IPs and `localhost`. It guards the operator mux, applied at
`internal/controlplane/http.go:122`. Static assets are served by a second mux
that does not require it, at `internal/controlplane/http.go:146`.

The result is that over `tailscale serve` the cockpit HTML loads with a 200 and
then every `/api/v1/*` request it makes returns:

```json
{"error":{"code":"invalid_host","message":"Host must identify a loopback address"}}
```

Measured, with the server unchanged:

| Host header | `/` | `/api/v1/overview` |
|---|---|---|
| `127.0.0.1:7337` | 200 | 200 |
| `localhost:7337` | 200 | 200 |
| `mickeys-mac-mini.taildcfadb.ts.net` | 200 | 403 |

An SSH tunnel works completely, because the browser then sends a loopback Host:

```bash
ssh -N -L 7337:127.0.0.1:7337 factorymac
```

This contradicts the design's requirement that remote browser access is fronted
by `tailscale serve`, and it undercuts the phone submission path in design.md
section 4. Laptops are unaffected. A phone cannot easily hold an SSH tunnel.

Two candidate fixes, to be decided when Plan 2 is written:

- A Host rewriting reverse proxy on the host, with `tailscale serve` pointed at
  it instead of at the server. No Go change, one more component.
- An allowlist in the fork, so a configured hostname is accepted alongside
  loopback. A Go change in an area Plan 1 wanted to keep untouched.

## Confirmed by inspection

`factory --help` already exposes `factory update --status STATUS --message
MESSAGE [--pr URL]`. The structured agent report the design specifies exists
upstream today, so that decision is confirmed rather than assumed.

## First run

Stock factory, stock blueprint skills, no custom code, first attempt.

| Fact | Value |
|---|---|
| Task ID | `621f9585-a553-4388-a131-22d0d3f3f6d6` |
| Run ID | `38fc91e6-175f-4a81-a184-e20a33f977a0` |
| Attempt ID | `cf158076-9b4b-4e6e-a63d-28a129997bb6` |
| Submitted | over the loopback API, not the cockpit |
| Pipeline | `Single agent`, one stage, "Do the task" |
| End state | `succeeded` |
| Wall clock | 84 seconds, 10:42:12Z to 10:43:36Z |
| Used `needs-input` | no |
| Pull request | `rexchao1/factory-scratch#1` |
| Branch | `factory/646e0979-42c-cf158076-9b4` |
| Manual fix needed | none |
| `npm test` on the branch | `# pass 2`, `# fail 0` |

The diff was one commit, `6ca1e82`, adding `farewell` to `src/greet.js` in the
existing export style and a matching test. `greet` was untouched. Nothing in
the spec's "Out of scope" section was violated.

Two design properties confirmed rather than assumed:

- **Worktree isolation is real.** The worker keeps a bare cache at
  `~/.factory/workers/worker/repositories/{repository_id}` and checks each
  attempt out into `~/.factory/workers/worker/worktrees/{attempt_id}`.
- **Branch names derive from identifiers, not the spec title.** The branch was
  `factory/646e0979-42c-cf158076-9b4`, carrying run and attempt IDs. This is
  what design.md section 6 requires so that retitling a spec cannot orphan a
  branch.

## AC-5 verification

**`AC-5` is not verified. Stock factory plus stock blueprint never reaches
`needs-input`.** This is not a factory bug. The machinery is present and well
built. Nothing tells the agent to use it.

The deliberately underspecified sliver from Plan 1 Task 8 was submitted twice,
once under each outcome contract.

### Attempt 1, `outcome_contract: process_exit`

Run `af3997c4-821c-4649-966d-856788cf8f8d`, end state `succeeded` in 54
seconds. No pull request, no question in the cockpit, no checkpoint.

The agent's judgment was correct. It refused to guess and said so:

> the task's own agent notes say the definition of "invalid" and whether
> rejection throws vs. returns a value are undecided, and explicitly tell me not
> to choose myself. That's a real blocker [...] Per the task-to-pr process, I'm
> stopping here rather than guessing

It delivered that as prose on stdout and exited 0. Under `process_exit`, exit 0
means success, so a refusal to proceed was recorded as a successful run. This is
the dangerous failure mode: silent, and indistinguishable from real completion
in `factory status`.

### Attempt 2, `outcome_contract: agent_update`

Run `609a3fb0-cd3b-4623-983a-c4d039907235`, attempt
`7d41b526-5ab6-48c0-902c-04316ae576f7`, end state `failed`.

The worker log tells the story:

```
03:51:13 WARN attempt_completion_not_recorded error_class=pipeline_incomplete
03:51:13 INFO attempt_worktree_retained
```

The agent again exited 0 without reporting. Under `agent_update` no outcome was
recorded, the pipeline stayed incomplete, and the control plane expired the
lease and marked the attempt `lost`. The worker's own manifest still reads
`terminal_state: succeeded`, so worker and control plane disagree about the same
attempt.

This contract fails loudly rather than silently, which is the better default of
the two, but it still does not produce `needs-input`.

### Root cause

No blueprint skill mentions `factory update`, `FACTORY_UPDATE`, or
`needs-input`. Searching all ten installed skills returns zero matches.
Blueprint is deliberately harness agnostic, so it has no way to know about
factory's report channel.

The channel is real and is injected on every attempt.
`internal/worker/supervisor.go:480-493` puts `FACTORY_WORK_ID`,
`FACTORY_ATTEMPT_ID`, `FACTORY_UPDATE_SOCKET`, and `FACTORY_UPDATE_TOKEN` into
the agent environment, and `factory --help` advertises
`factory update --status STATUS --message MESSAGE [--pr URL]`. The control plane
side is complete too: `AnswerWork` at `internal/controlplane/resume.go:374`,
checkpoint revalidation at
`internal/worker/attempt_lifecycle.go:707-715`, and resume routing at
`resume.go:513`.

Every piece exists except the sentence telling the agent to call it.

### What this means for the plans

- `AC-5`, and the "nothing runs in the dark" story that rests on it, is
  currently unproven end to end. It stays unproven until an agent actually
  calls `factory update --status needs-input`.
- The work is instructional, not structural. Either the blueprint skills are
  extended, or the orchestrator wraps every submitted prompt with the reporting
  contract. The second is the better fit for the distro approach in design.md,
  since it keeps blueprint stock.
- `outcome_contract` should default to `agent_update`, not `process_exit`. A
  silent false success is worse than a loud failure.
- Retry after this failure is safe to inspect: the worktree is retained at
  `~/.factory/workers/worker/worktrees/{attempt_id}` with
  `retention_reason: succeeded attempt retained for inspection`, matching
  design.md section 7.

### Steps not reached

Plan 1 Task 8 Steps 4 through 6, recording a checkpoint SHA and answering from
the cockpit to confirm resume from that exact SHA, could not be executed. There
was no checkpoint to record and no question to answer. `INV-5` is therefore also
unproven against a live run, though the code path exists at `resume.go:513`.

## Docker preflight

Plan 4 is not blocked. All three assertions hold on this host.

| Check | Result |
|---|---|
| `docker info` | ok |
| `docker run --rm alpine:3 echo container-ok` | exit 0, `container-ok` |
| `docker run --rm --network none alpine:3 wget https://example.com` | exit 1, `wget: bad address 'example.com'`. Egress blocked, as `INV-6` and `AC-7` require. |
| `docker run --rm -v "$HOME/.factory/mnttest:/w" alpine:3 cat /w/f.txt` | exit 0, `hello`. `~/.factory` is bind mountable with no File Sharing change. |

Docker version 29.7.2.

### Docker also depends on the Keychain

`~/.docker/config.json` sets `"credsStore": "desktop"`, so every `docker pull`
routes through the Docker Desktop credential helper, which needs the macOS
Keychain. Over SSH that fails before any registry call, even for an anonymous
public image:

```
error getting credentials: keychain cannot be accessed because the current
session does not allow user interaction
```

This is the same root cause as the Claude Code authentication finding. It has
the same shape of answer: the worker is started from a GUI session, so the
Docker backend Plan 4 adds will have keychain access. Only SSH driven docker
commands are affected, and those can pass `--config` pointing at a directory
holding `{}` to skip the helper for anonymous pulls.

Plan 4 should not assume an SSH session can pull images.

## Gap map

Every path below exists in the clone at upstream `a9adbde`. The next migration
number is `035`; the highest present is `034_resume_recovery.sql`.

One structural note that affects all four changes. Work and session states are
not a Go enum. They appear as SQL string literals across
`internal/controlplane/state.go:809`, `resume.go:432`, `resume.go:491`,
`build.go:282`, `procedures.go:343`, `task_claim.go:208`, and `tasks.go:668`.
Only `SessionState` and `RunState` have Go constants, at
`internal/protocol/tasks.go:219` and `internal/protocol/tasks.go:281`. Adding
`draft` means finding every one of those SQL literals, not editing one list.

### Gap 1: draft state and pre-approved admission (Plan 2)

| What | Where |
|---|---|
| Task creation handler | `internal/controlplane/tasks_http.go:110`, `createTask` |
| Admission request shape | `internal/protocol/tasks.go:181`, `SaveTaskRequest` |
| Run start request | `internal/protocol/tasks.go:206`, `RunTaskRequest` |
| Idempotency key validation | `internal/controlplane/build.go:27` onward |
| State transitions | `internal/controlplane/state.go`, SQL literals listed above |
| Migration to add | `035` |

`pre_approved` has no field to read today. It is added to `SaveTaskRequest`, and
the `draft` state is added ahead of `queued` in the session state literals.

### Gap 2: docker backend and sandbox (Plan 4)

| What | Where |
|---|---|
| Backend constants | `internal/protocol/tasks.go:404-408`. Today: `persistent`, `fake_cloud_run` |
| Frozen profile | `internal/protocol/tasks.go:412`, `ExecutionSnapshot` |
| Profile record | `internal/protocol/tasks.go:424`, `ExecutionProfile` |
| Profile store | `internal/controlplane/execution_profiles.go` |
| Where the worker spawns the runtime | `internal/worker/supervisor.go:241` |
| Agent environment injection | `internal/worker/supervisor.go:480-493` |

Neither `ExecutionSnapshot` nor `ExecutionProfile` has a `sandbox` field. The
fake provider to copy is `BackendFakeCloudRun` plus the `FakeOutcome`,
`FakeResult`, and `FakeError` fields on `ExecutionProfile`.

### Gap 3: code stages (Plan 4)

| What | Where |
|---|---|
| Stage shape | `internal/protocol/tasks.go:27`, `PipelineStage` |
| Prompt rendering | `internal/controlplane/pipelines.go:297`, `renderPipelinePrompt` |
| Stage lifecycle | `internal/controlplane/stage_runs.go:35` `StartStage`, `:96` `CompleteStage` |
| Stage execution on the worker | `internal/worker/attempt_lifecycle.go:209` |

`PipelineStage` is `{Position, Name, Prompt}` only. `kind` is added here, and a
`kind: code` stage must skip both `renderPipelinePrompt` and the runtime spawn
at `supervisor.go:241`. `INV-7` says a code stage consumes no tokens, so the
test asserts no runtime invocation at that call site.

### Gap 4: pull request evidence and auto-merge (Plan 5)

This gap is smaller than design.md assumes, and it sits in a different place.

Stock factory already verifies delivery evidence, and does it well:

- On a `ready` report, `internal/worker/agent_update.go:181` calls
  `validateReadyDelivery`, then **overwrites** the agent's claimed head branch
  and head SHA with what it derived itself, at `agent_update.go:190-191`. The
  agent cannot assert a PR head it does not have.
- After the agent process stops, `internal/worker/attempt_lifecycle.go:695-705`
  revalidates and fails the attempt with "Delivery evidence could not be
  revalidated after the agent process stopped" on any mismatch.
- `needs-input` gets the same treatment through `validateNeedsInputCheckpoint`
  at `attempt_lifecycle.go:707-715`, which satisfies the substance of `INV-4`.
- Remote SHA comparison lives at `internal/worker/git.go:360-381`.

What the control plane does is shape validation only, at
`internal/controlplane/work.go:53-62`: `ready` must carry a non empty PR URL,
a non empty head branch, and a SHA that passes `validCommitSHA`
(`work.go:216`, a hex and length check). `internal/controlplane/` contains no
`exec.Command` at all, so the server never inspects a repository.

So `INV-3` is not satisfied, but not because verification is missing. It is
performed in the wrong place. `INV-3` requires the server to verify repository,
publish branch, local HEAD, remote ref, and pull request head before accepting
`ready`. Today the worker does that and the server accepts the worker's word
after a shape check.

Plan 5 therefore adds server side verification to satisfy `INV-3` as written.
The worker side checks stay where they are; they are a useful early rejection,
not a substitute. `INV-8` auto merge attaches after that verification, since it
must not merge on unverified evidence.

### Gap 5: the operator API rejects non loopback Host headers

Recorded above under host findings. Not one of the original four.
