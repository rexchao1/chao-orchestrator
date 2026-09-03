# Factory Foundation Implementation Plan

**Status: done. Findings and deviations are in [fork-notes.md](../fork-notes.md). Reconciled 2026-09-03.**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a forked `owainlewis/factory` entirely on the Mac mini, reachable from any device with an SSH terminal and a browser, and take one real vertical sliver to a reviewed pull request using entirely stock software.

**Architecture:** One host. The Mac mini runs `factory-server` (SQLite, admission, leases, cockpit on loopback) and `factory-worker` (repository caches, worktrees, Claude Code processes), and also holds the Go toolchain and the fork clone so it builds itself. Every other device is a thin client: an SSH terminal and a browser, nothing installed. Go source is edited through VS Code Remote-SSH against the host's single clone.

**Tech Stack:** Go 1.25.13 (host only), `just`, SQLite via pure-Go `modernc.org/sqlite`, `gh` CLI, Claude Code CLI, tmux, Tailscale, Docker Desktop for Mac, Node 24.

## Global Constraints

- Go toolchain must be exactly `1.25.13` or newer on the 1.25 line, built for `darwin/arm64`. Source: the fork's `.release/go-version` and `go.mod` both pin `1.25.13`.
- **Nothing irreplaceable lives on a client.** All state is on the host. Source is a git clone, tooling is reinstallable. If a client dies you lose nothing but an SSH key.
- **No client needs a Go toolchain.** The host builds itself: `ssh factorymac 'cd ~/factory && git pull && just build'`.
- The fork must stay thin. Confine every future change to the areas named in Task 10 so upstream merges stay cheap. Upstream is developer preview and expects breaking changes.
- No process binds `0.0.0.0`. `factory-server` binds loopback on the host. Remote access is `tailscale serve` or an SSH tunnel, never a wider bind.
- Only the `claude-code` runtime will be available. `codex` and `pi` are not installed; do not configure them.
- Long-running processes run under tmux, not bare SSH sessions, so a dropped connection never kills a run or the orchestrator.
- Docs written in this repository follow blueprint house style: plain words, and no em dashes.
- Design invariants `INV-1` through `INV-10` in `docs/factory/design.md` govern later plans. This plan implements none of them; it establishes the baseline they are measured against.

## Machine legend

- **[mac]** runs on the Mac mini, over SSH or at the machine.
- **[client]** runs on whatever device you are holding.
- **[browser]** is done in the cockpit UI.

Task 1 needs physical or screen-sharing access to the Mac for GUI steps: Docker Desktop's first run, Tailscale sign-in, and enabling Remote Login. Everything after that is reachable over SSH from anywhere.

---

### Task 1: Prepare the Mac mini **[mac]**

**Files:**
- Modify: `~/.zprofile` on the host (PATH entries)

**Interfaces:**
- Consumes: nothing.
- Produces: a host with Remote Login on, Homebrew, git, `gh` authenticated, Claude Code authenticated, Go 1.25.13, `just`, tmux, Docker Desktop running, and Tailscale connected.

- [ ] **Step 1: Enable Remote Login**

Open System Settings, then General, then Sharing, and turn on Remote Login. Without this, every remaining task requires you at the machine.

- [ ] **Step 2: Install Homebrew and command line tools**

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
xcode-select --install || true
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

- [ ] **Step 3: Install the tools the host needs**

```bash
brew install git gh node just tmux
brew install --cask docker tailscale
```

- [ ] **Step 4: Install Go 1.25.13 for arm64**

Homebrew installs whatever Go is current, which may not match the fork's pin. Use the official tarball.

```bash
cd /tmp
curl -fsSLO https://go.dev/dl/go1.25.13.darwin-arm64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.25.13.darwin-arm64.tar.gz
echo 'export PATH="$PATH:/usr/local/go/bin"' >> ~/.zprofile
export PATH="$PATH:/usr/local/go/bin"
go version
```

Expected: `go version go1.25.13 darwin/arm64`

- [ ] **Step 5: Authenticate GitHub**

The worker clones managed repositories using this authentication. Factory advertises GitHub access only while `gh auth status` succeeds.

```bash
gh auth login
gh auth status --hostname github.com
```

Expected: logged in with a valid token.

- [ ] **Step 6: Install and authenticate Claude Code**

This is the only Claude authentication in the system. Clients never need one.

```bash
npm install -g @anthropic-ai/claude-code
claude
```

Complete the browser login flow, then exit with `/exit`. Verify:

Run: `claude --version`
Expected: a version string with no authentication prompt.

- [ ] **Step 7: Start Docker Desktop and Tailscale**

Launch both from Finder and complete their first-run prompts. Tailscale needs you to sign in to your tailnet.

```bash
docker info > /dev/null && echo "docker ok"
tailscale status | head -5
```

Expected: `docker ok`, and a status listing this Mac.

- [ ] **Step 8: Prevent sleep**

A sleeping host stalls runs and drops your orchestrator session. In System Settings, Energy, set the computer to never sleep on power.

Run: `pmset -g | grep -E '^\s*sleep'`
Expected: `sleep 0`

- [ ] **Step 9: Record the host's addresses**

```bash
tailscale ip -4
tailscale status --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["Self"]["DNSName"])'
```

Record both. Later tasks use the tailnet DNS name.

---

### Task 2: Reach the host from any device **[client]**

Do this once per client device. The steps are identical on WSL, a laptop, or anything else with an SSH client.

**Files:**
- Modify: `~/.ssh/config` on the client

**Interfaces:**
- Consumes: the host addresses from Task 1 Step 9.
- Produces: passwordless SSH to the host as alias `factorymac`, plus the design repository cloned on the host.

- [ ] **Step 1: Set the address**

```bash
export MAC="<the tailnet DNS name recorded in Task 1 Step 9>"
```

Replace the placeholder with the real value before running. Use the Mac's LAN IP instead if both machines are on the same network and the tailnet is not yet reachable.

- [ ] **Step 2: Create an SSH key if this device lacks one**

```bash
test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -C "$USER@$(hostname)" -f ~/.ssh/id_ed25519 -N ""
```

- [ ] **Step 3: Install the key and add a host alias**

```bash
ssh-copy-id "$USER@$MAC"
cat >> ~/.ssh/config <<EOF

Host factorymac
  HostName $MAC
  User $USER
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 30
EOF
chmod 600 ~/.ssh/config
```

- [ ] **Step 4: Verify passwordless SSH and the architecture**

Run: `ssh factorymac 'uname -m && sw_vers -productVersion && go version'`
Expected: `arm64`, a macOS version, and `go version go1.25.13 darwin/arm64`, with no password prompt.

- [ ] **Step 5: Push the design repository so the host can clone it**

`fork-notes.md` is written on the host from here on, so the design repository has to be reachable. Run this from the device that currently holds the working copy.

```bash
cd ~/projects/ChaoFactory
git add -A
git commit -m "docs: retire walking skeleton, add factory design and plans"
git push origin main
```

- [ ] **Step 6: Clone the design repository on the host**

```bash
ssh factorymac 'mkdir -p ~/projects && cd ~/projects && test -d ChaoFactory || gh repo clone rexchao1/ChaoFactory'
ssh factorymac 'ls ~/projects/ChaoFactory/docs/factory/'
```

Expected: `design.md`, `roadmap.md`, and a `plans` directory.

- [ ] **Step 7: Confirm VS Code Remote-SSH works**

Install the Remote-SSH extension, then connect to the `factorymac` host and open `~/projects/factory` once it exists after Task 3. For now, confirm the connection succeeds and a terminal opens on the host.

---

### Task 3: Fork, clone, and build on the host **[mac]**

**Files:**
- Create: `~/projects/factory/` on the host (the clone)
- Create: `~/.factory/bin/factory`, `factory-server`, `factory-worker` on the host

**Interfaces:**
- Consumes: the toolchain from Task 1, SSH access from Task 2.
- Produces: three binaries under `~/.factory/bin`, and a clone whose `origin` is your fork and `upstream` is `owainlewis/factory`.

- [ ] **Step 1: Fork and clone on the host**

```bash
ssh factorymac
mkdir -p ~/projects && cd ~/projects
gh repo fork owainlewis/factory --clone --remote --fork-name factory
cd ~/projects/factory
git remote -v
```

Expected: `origin` at `github.com/rexchao1/factory`, `upstream` at `github.com/owainlewis/factory`. If `upstream` is missing:

```bash
git remote add upstream https://github.com/owainlewis/factory.git
```

- [ ] **Step 2: Confirm the pinned Go version still matches**

Run: `cat .release/go-version && head -3 go.mod`
Expected: `1.25.13` and `go 1.25.13`. If upstream has moved, install the version named here instead and record the change.

- [ ] **Step 3: Build**

Run: `just build`
Expected: `Factory binaries built in /Users/<you>/.factory/bin`

- [ ] **Step 4: Verify the binaries run**

Run: `~/.factory/bin/factory --help`
Expected: usage text listing `build`, `run`, `procedures`, `status`, `show`, and `workers`.

- [ ] **Step 5: Confirm the clone is unmodified**

Run: `git status --porcelain`
Expected: empty output.

- [ ] **Step 6: Verify the one-line deploy path works**

This is the command you will use from every device from now on. Prove it now.

Run (from a client): `ssh factorymac 'cd ~/projects/factory && git pull && just build'`
Expected: `Already up to date.` and a successful rebuild.

---

### Task 4: Establish a green baseline **[mac]**

Prove the fork's own checks pass before changing anything. A later failure then means your change, not the environment.

**Files:**
- Create: `~/projects/ChaoFactory/docs/factory/fork-notes.md` on the host

**Interfaces:**
- Consumes: the clone from Task 3.
- Produces: a recorded baseline so Plans 2, 4, and 5 can tell regression from pre-existing failure.

- [ ] **Step 1: Run the Go test suite**

```bash
ssh factorymac 'cd ~/projects/factory && go test ./... 2>&1 | tail -40'
```

Expected: every package reports `ok` or `no test files`. Record the total runtime and any failure.

- [ ] **Step 2: Run static analysis and formatting checks**

```bash
ssh factorymac 'cd ~/projects/factory && just vet && just format-check'
```

Expected: no output, exit 0 from both.

- [ ] **Step 3: Run the architectural boundary check**

This proves worker code does not import control-plane code. Plans 2, 4, and 5 must keep it passing.

Run: `ssh factorymac 'cd ~/projects/factory && just boundary'`
Expected: exit 0, no output.

- [ ] **Step 4: Record the baseline on the host**

```bash
ssh factorymac
cd ~/projects/factory
UPSTREAM_SHA=$(git rev-parse upstream/main)
cat > ~/projects/ChaoFactory/docs/factory/fork-notes.md <<EOF
# Fork notes

Fork of \`owainlewis/factory\`. Clone and toolchain both live on the Mac mini at
\`~/projects/factory\`. Client devices hold no source and no Go toolchain.

## Baseline

Recorded on first build, before any local change.

- Upstream commit: $UPSTREAM_SHA
- \`go test ./...\`: RESULT
- \`just vet\`: RESULT
- \`just format-check\`: RESULT
- \`just boundary\`: RESULT

## Gap map

Filled in by Task 10.
EOF
```

Replace each `RESULT` with the real observed outcome. Do not leave the word `RESULT` in the file.

- [ ] **Step 5: Commit and push**

```bash
cd ~/projects/ChaoFactory
git add docs/factory/fork-notes.md
git commit -m "docs: record factory fork baseline"
git push origin main
```

---

### Task 5: Run the control plane and worker **[mac]**

**Files:**
- Create: `~/.factory/worker.toml` on the host

**Interfaces:**
- Consumes: binaries from Task 3.
- Produces: `factory-server` on `127.0.0.1:7337` with one registered worker advertising `claude-code`, reachable from any client.

- [ ] **Step 1: Write the worker config**

Only `claude-code` is installed. Advertising an unauthenticated runtime is allowed but pointless.

```bash
ssh factorymac 'mkdir -p ~/.factory && cat > ~/.factory/worker.toml' <<'EOF'
server = "http://127.0.0.1:7337"
name = "macmini"
runtime = "claude-code"
runtimes = ["claude-code"]
max_concurrent = 2
[labels]
environment = "development"
host = "macmini"
EOF
```

- [ ] **Step 2: Start the server under tmux**

A bare SSH session dies with your connection and takes the server with it. tmux does not.

```bash
ssh factorymac
tmux new -d -s factory-server '~/.factory/bin/factory-server'
tmux ls
```

Expected: a session named `factory-server`.

- [ ] **Step 3: Start the worker under tmux**

```bash
tmux new -d -s factory-worker '~/.factory/bin/factory-worker ~/.factory/worker.toml'
tmux ls
```

Expected: sessions named `factory-server` and `factory-worker`.

- [ ] **Step 4: Verify the worker registered**

Run: `ssh factorymac '~/.factory/bin/factory workers'`
Expected: one row named `macmini`, ready, advertising `claude-code`.

If it is absent, read the logs with `ssh factorymac 'tmux capture-pane -pt factory-worker | tail -30'`.

- [ ] **Step 5: Confirm the listener is loopback only**

Run: `ssh factorymac 'lsof -nP -iTCP:7337 -sTCP:LISTEN'`
Expected: the address column shows `127.0.0.1:7337`. If it shows `*:7337`, stop and investigate; that violates a global constraint.

- [ ] **Step 6: Expose the cockpit over the tailnet**

```bash
ssh factorymac 'tailscale serve --bg http://127.0.0.1:7337 && tailscale serve status'
```

Expected: a proxy entry mapping the tailnet name to `127.0.0.1:7337`.

- [ ] **Step 7: Verify the cockpit from a client**

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "https://$MAC/"
```

Expected: `200`.

If this returns a 4xx, the server may be rejecting the proxied Host header. Use an SSH tunnel instead, which needs no cooperation from the server:

```bash
ssh -f -N -L 7337:127.0.0.1:7337 factorymac
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:7337/
```

Record which method worked. Open the cockpit in a browser and confirm the UI renders.

---

### Task 6: Create a scratch repository with real tests and blueprint skills **[mac]**

The factory needs a target repository whose tests actually run, or `/test` has nothing to prove.

**Files:**
- Create: `~/projects/factory-scratch/` on the host

**Interfaces:**
- Consumes: `gh` authentication from Task 1.
- Produces: `rexchao1/factory-scratch` on GitHub with a passing `npm test` and blueprint skills installed.

- [ ] **Step 1: Create the repository**

```bash
ssh factorymac
cd ~/projects
gh repo create factory-scratch --private --clone
cd factory-scratch
```

- [ ] **Step 2: Add a package with a real test command**

```bash
cat > package.json <<'EOF'
{
  "name": "factory-scratch",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test test/"
  }
}
EOF
mkdir -p src test
cat > src/greet.js <<'EOF'
export function greet(name) {
  return `Hello, ${name}!`;
}
EOF
cat > test/greet.test.js <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { greet } from '../src/greet.js';

test('greet addresses the given name', () => {
  assert.equal(greet('world'), 'Hello, world!');
});
EOF
npm test
```

Expected: `# pass 1` and `# fail 0`.

- [ ] **Step 3: Install blueprint skills**

```bash
npx skills add owainlewis/blueprint
ls .claude/skills/
```

Expected: directories including `design`, `plan`, `task-to-pr`, `test`, and `review`.

- [ ] **Step 4: Commit and push**

```bash
git add -A
git commit -m "chore: scratch repository with tests and blueprint skills"
git push -u origin main
gh repo view rexchao1/factory-scratch --json defaultBranchRef -q .defaultBranchRef.name
```

Expected: `main`

---

### Task 7: Drive one sliver to a pull request **[browser]**

This is the task that proves the thesis. Everything before it was setup.

**Files:**
- Modify: none by hand. The agent writes the code.

**Interfaces:**
- Consumes: the running server from Task 5, the scratch repository from Task 6.
- Produces: an open pull request on `rexchao1/factory-scratch` created entirely by the factory.

- [ ] **Step 1: Register the scratch repository**

In the cockpit, add `github.com/rexchao1/factory-scratch` as a managed repository. The host clones it on demand using the `gh` authentication from Task 1 Step 5; no separate credential setup is required.

- [ ] **Step 2: Verify it was accepted**

Run: `ssh factorymac '~/.factory/bin/factory status'`
Expected: the repository appears and no error is reported.

- [ ] **Step 3: Submit one vertical sliver**

Submit through the cockpit, selecting the `claude-code` runtime:

```text
Use /task-to-pr for this task.

## Add a farewell function

### What are we building?
The module can greet someone but cannot say goodbye. Add a farewell function
alongside the existing greet function.

### Why?
Callers need both halves of a conversation from one module.

### Done when
- `farewell('world')` returns the string `Goodbye, world!`
- The existing `greet` behavior is unchanged.
- `npm test` passes with tests covering both functions.

### How to check
Run `npm test`. Both the existing greet test and a new farewell test pass.

### Agent notes
- Depends on: None
- Source: this task
- Match the existing export style in `src/greet.js`.

### Out of scope
- Renaming or restructuring the existing module.
```

- [ ] **Step 4: Watch the run**

Run: `ssh factorymac '~/.factory/bin/factory status'`

Watch the cockpit as the run moves through `queued` and `running`. Expected end state: `ready` or `succeeded`.

- [ ] **Step 5: Verify a real pull request exists and its branch passes**

```bash
ssh factorymac '
  cd /tmp && rm -rf pr-check
  BRANCH=$(gh pr list --repo rexchao1/factory-scratch --json headRefName -q ".[0].headRefName")
  gh repo clone rexchao1/factory-scratch pr-check -- --branch "$BRANCH"
  cd pr-check && npm test
'
```

Expected: one open pull request, and `# pass 2` with `# fail 0`.

- [ ] **Step 6: Record what actually happened**

Append a `## First run` section to `~/projects/ChaoFactory/docs/factory/fork-notes.md` on the host: the Work ID, the end state, wall-clock duration, whether the agent used `needs-input`, and whether the pull request needed any manual fix. Record failures plainly. This is the evidence that Plans 2 through 5 are improvements rather than repairs.

- [ ] **Step 7: Commit and push**

```bash
ssh factorymac 'cd ~/projects/ChaoFactory && git add docs/factory/fork-notes.md && git commit -m "docs: record first end-to-end factory run" && git push origin main'
```

---

### Task 8: Verify the mid-run question path **[browser]**

`AC-5` says an agent that reports `needs-input` leaves no running process and no held lease, and that answering resumes from the recorded checkpoint. This is stock behavior, and the entire "nothing runs in the dark" story rests on it. Prove it rather than assuming it.

**Files:**
- Modify: `~/projects/ChaoFactory/docs/factory/fork-notes.md` on the host

**Interfaces:**
- Consumes: the running server from Task 5, the scratch repository from Task 6.
- Produces: a recorded confirmation or refutation of `AC-5` against stock factory.

- [ ] **Step 1: Submit a deliberately underspecified sliver**

The task must contain a real decision the spec does not answer, so the agent has to ask rather than guess.

```text
Use /task-to-pr for this task.

## Add input validation to greet

### What are we building?
`greet` accepts any value. It should reject invalid input.

### Done when
- Invalid input is rejected.
- `npm test` passes.

### How to check
Run `npm test`.

### Agent notes
- Depends on: None
- The definition of invalid, and whether rejection throws or returns a value,
  are not decided. Do not choose one yourself.
```

- [ ] **Step 2: Verify the run stops with a question**

Run: `ssh factorymac '~/.factory/bin/factory status'`
Expected: the Work reaches `needs-input`, not `failed` and not `succeeded`.

If it instead picks a behavior and finishes, record that. It means stock factory trusts the agent further than `AC-5` assumes, and Plan 2 must account for it.

- [ ] **Step 3: Verify no process and no lease survive**

```bash
ssh factorymac 'pgrep -af claude | grep -v pgrep || echo "no claude process"'
ssh factorymac '~/.factory/bin/factory workers'
```

Expected: no agent process remains, and the worker reports a free slot rather than a held lease.

- [ ] **Step 4: Record the checkpoint SHA before answering**

```bash
ssh factorymac '~/.factory/bin/factory show <work-id>'
```

Substitute the Work ID from Step 2. Record the stored checkpoint SHA; you compare against it in Step 6.

- [ ] **Step 5: Answer the question**

Answer from the cockpit. The fork's architecture notes state the finite CLI does not yet expose the answer control, so the browser is the only path. Give a concrete decision, for example: reject non-string input by throwing a `TypeError`.

- [ ] **Step 6: Verify it resumed from the checkpoint**

Run: `ssh factorymac '~/.factory/bin/factory show <work-id>'`
Expected: the run restarts from the exact SHA recorded in Step 4, not from the current default branch tip. `INV-5` requires this, and a fallback to another ref would be a genuine upstream bug worth reporting.

- [ ] **Step 7: Record, commit, and push**

Append an `## AC-5 verification` section to `fork-notes.md` stating whether the run stopped, whether processes and leases were released, the checkpoint SHA, and whether the resume used it. Record a failure plainly if it failed.

```bash
ssh factorymac 'cd ~/projects/ChaoFactory && git add docs/factory/fork-notes.md && git commit -m "docs: verify needs-input and resume against stock factory" && git push origin main'
```

---

### Task 9: Docker preflight **[mac]**

Plan 4 adds a `docker` execution backend and depends on `--network none` actually isolating. Prove the mechanism now, on the machine that will use it.

**Files:**
- Modify: `~/projects/ChaoFactory/docs/factory/fork-notes.md` on the host

**Interfaces:**
- Consumes: Docker Desktop from Task 1 Step 7.
- Produces: a recorded yes or no on whether Plan 4's core assumptions hold.

- [ ] **Step 1: Verify the daemon and a container**

```bash
ssh factorymac 'docker info > /dev/null && echo ok && docker run --rm alpine:3 echo container-ok'
```

Expected: `ok` and `container-ok`.

- [ ] **Step 2: Verify network isolation blocks egress**

This is the mechanism `INV-6` and `AC-7` depend on.

Run: `ssh factorymac 'docker run --rm --network none alpine:3 wget -q -T 3 -O - https://example.com'`
Expected: **failure**, with a DNS or network-unreachable error. A success here means `--network none` is not isolating and Plan 4's design assumption is wrong.

- [ ] **Step 3: Verify a bind mount works**

The Docker backend must mount a worktree into the container. Docker Desktop for Mac restricts which host paths are shareable, so test the path that will actually be used.

```bash
ssh factorymac 'mkdir -p ~/.factory/mnttest && echo hello > ~/.factory/mnttest/f.txt && docker run --rm -v "$HOME/.factory/mnttest:/w" alpine:3 cat /w/f.txt'
```

Expected: `hello`. If it fails, add the path under Docker Desktop Settings, Resources, File Sharing, and record that `~/.factory` must be shared before Plan 4 can start.

- [ ] **Step 4: Record, commit, and push**

Append a `## Docker preflight` section to `fork-notes.md` recording each result. If any step failed, record that Plan 4 is blocked and why. Do not silently skip this.

```bash
ssh factorymac 'cd ~/projects/ChaoFactory && git add docs/factory/fork-notes.md && git commit -m "docs: record docker preflight" && git push origin main'
```

---

### Task 10: Map the four gaps to real code **[mac]**

This task exists so Plans 2, 4, and 5 can be written with real file paths instead of guesses. It is the deliverable that unblocks them.

**Files:**
- Modify: `~/projects/ChaoFactory/docs/factory/fork-notes.md` on the host

**Interfaces:**
- Consumes: the clone from Task 3.
- Produces: a `## Gap map` section naming, for each of the four changes, the exact files and functions to modify.

Run these on the host, or through VS Code Remote-SSH with the clone open.

- [ ] **Step 1: Locate the Work state machine**

```bash
cd ~/projects/factory
grep -rn "needs-input\|needs_input" internal/controlplane/*.go | head -20
grep -rn "queued" internal/controlplane/state.go internal/controlplane/work.go | head -20
ls migrations/
```

Record: which file declares the Work state constants, which function performs transitions, and the highest existing migration number. Plan 2 adds `draft` ahead of `queued`.

- [ ] **Step 2: Locate the admission path**

```bash
grep -rn "func.*[Aa]dmit\|request_key\|requestKey" internal/controlplane/*.go | head -20
sed -n '1,80p' internal/controlplane/work_http.go
```

Record: the handler that accepts a submission, and where it would read a `pre_approved` field.

- [ ] **Step 3: Locate the execution profile seam**

```bash
sed -n '1,120p' internal/controlplane/execution_profiles.go
grep -rn "persistent-auto\|backend" internal/controlplane/execution_profiles.go | head -20
grep -rn "fake_cloud\|FakeCloud" internal/controlplane/*.go | head -10
```

Record: the type that declares a backend, the valid backend values, and how the fake provider is wired. Plan 4 adds a `docker` backend against this contract, and the fake provider is the model to copy.

- [ ] **Step 4: Locate pipeline stage execution**

```bash
sed -n '1,100p' internal/controlplane/pipelines.go
grep -rn "stage" internal/controlplane/stage_runs.go | head -20
grep -rn "func.*[Ss]tage" internal/worker/*.go | head -20
```

Record: the stage type definition, where a stage prompt is rendered, and where the worker spawns a runtime for a stage. Plan 4 adds `kind: code`, which must skip both.

- [ ] **Step 5: Locate pull request evidence verification**

```bash
grep -rn "pull.\?[Rr]equest\|prBranch\|pr_head" internal/controlplane/*.go | head -20
grep -rn "ready" internal/controlplane/work.go | head -20
```

Record: the function that validates a `ready` outcome against repository, publish branch, local HEAD, remote ref, and pull request head. Plan 5 extends this path with auto-merge.

- [ ] **Step 6: Locate the prompt assembly point**

`INV-9` requires the full frozen spec in every stage prompt. Find where a stage prompt is assembled, so Plan 2 adds the `AC-9` test in the right place.

```bash
grep -rn "prompt" internal/controlplane/pipelines.go internal/controlplane/stage_runs.go | head -20
```

- [ ] **Step 7: Write the gap map**

Replace the `## Gap map` line in `fork-notes.md` with four subsections, one per change, each naming exact file paths, the functions to modify, and the migration number to add. Every entry must name a real file that exists in the clone. An entry you could not locate is recorded as "not found, investigate during the plan", never as a guess.

- [ ] **Step 8: Commit and push**

```bash
cd ~/projects/ChaoFactory
git add docs/factory/fork-notes.md
git commit -m "docs: map the four factory changes to real code"
git push origin main
```

---

## Done when

- `ssh factorymac` works passwordlessly from a client and reports `arm64` and `go version go1.25.13 darwin/arm64`.
- `ssh factorymac 'cd ~/projects/factory && git pull && just build'` succeeds from a client, proving no client needs a Go toolchain.
- The fork's `go test ./...`, `just vet`, `just format-check`, and `just boundary` all pass on the host and are recorded as a baseline.
- A worker named `macmini` registers, both processes run under tmux, and `lsof` shows the listener bound to `127.0.0.1:7337`, not `*:7337`.
- The cockpit answers `200` from a client over either `tailscale serve` or an SSH tunnel, and the working method is recorded.
- One submitted sliver produced a real open pull request on `rexchao1/factory-scratch` whose branch passes `npm test`.
- An underspecified sliver stopped at `needs-input`, released its process and lease, and resumed from its recorded checkpoint SHA.
- `docker run --rm --network none alpine:3 wget https://example.com` **fails** on the host, and a bind mount of `~/.factory` succeeds.
- `docs/factory/fork-notes.md` is committed and pushed, containing a baseline, a first-run record, an `AC-5` verification, a docker preflight result, and a gap map with real file paths and no placeholders.

## What this plan deliberately does not do

- It writes no Go. Every code change is Plans 2, 4, and 5.
- It builds no orchestrator. That is Plan 3, and it also lives on the host.
- It adds no approval gate. Task 7 submits directly, which is exactly what stock factory supports today. `INV-1` and `INV-10` arrive in Plan 2.
- It does not make the host processes survive a reboot. tmux survives a dropped SSH connection but not a restart. A launchd service is worth adding once the system has earned it, and is out of scope.
- It does not enroll a second worker. That is deferred Plan 6, and it requires operator-managed TLS certificates.
