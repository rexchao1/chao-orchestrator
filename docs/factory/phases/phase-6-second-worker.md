# Phase 6: Second worker

**Status: deferred. Do not start this until the Mac mini is measurably
saturated.**

**Goal:** a second machine claims work from the same control plane, so runs are
not bounded by one host's slots.

**Language:** Go configuration and operations, likely no code change.
**Blocked by:** Phase 1.

## Why it is deferred

The fork's Known Limitations state that remote workers require operator-managed
TLS certificates and enrollment. That is real setup and real ongoing maintenance,
and it buys nothing until one worker is actually the bottleneck. The Mac mini is
configured with `max_concurrent = 2`; raising that number is free and should be
exhausted first.

Start this phase only when you can point at queued Work waiting on slots.

## Read first

- The fork's `docs/remote-workers.md`.
- `design.md` section 8, the trust boundary.
- Phase 1's worker configuration, `~/.factory/worker.toml` on the host.

## Already decided, do not relitigate

- Workers poll **outbound** to the server. Nothing connects into a worker host.
  This holds for remote workers too and is why the topology is safe.
- The operator API stays loopback. Remote workers use the separate authenticated
  TLS listener, which is a different port and a different credential.

## Scope

**In:** enrolling one additional worker, its TLS certificate, its per-worker
bearer credential, and its own `gh` and Claude Code authentication.

**Out:** load balancing policy, worker affinity, or moving an in-flight session
between workers. The fork states a Session cannot move between workers, so
scheduling stays simple.

## Known unknowns to resolve first

- **Authentication multiplies.** Each worker needs its own `gh` login and its own
  Claude Code login. That is the real cost of a second worker, more than the
  certificates.
- **Whether the second worker should be the WSL box or something else.** A Linux
  worker sandboxes better than macOS, since Docker is native rather than a VM.
  If Phase 4 concluded that macOS Docker is awkward, a Linux worker may be worth
  doing sooner for that reason rather than for capacity.

## Done when

- Two workers register against one control plane.
- Work is claimed by whichever worker has a free slot.
- Killing one worker mid-run returns its Work to `queued` after the lease
  expires, and the other worker picks it up.
