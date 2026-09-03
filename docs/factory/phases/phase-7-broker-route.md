# Phase 7: Broker route for sandboxed runs

**Status: done 2026-09-03.
Built directly as Claude Code in the fork, not through the factory.**

**Goal:** an agent running inside the factory's docker sandbox reaches third party APIs through the agent-vault broker on the host, and never holds a raw API key.

**Language:** Go, in the fork.
**Blocked by:** Phase 4, which is done.

## Context

The host runs [Infisical agent-vault](https://github.com/Infisical/agent-vault) as a launchd user agent, loopback only: API on `127.0.0.1:14321`, MITM proxy on `127.0.0.1:14322`.
Everything about it lives in the private `infra` repository, `docs/broker.md`.
A process uses the broker by setting `HTTPS_PROXY` to `http://<agent-token>:<vault>@127.0.0.1:14322` and trusting the proxy's root CA.
The proxy adds the `Authorization` header for hosts that have a service rule.

Today the worker passes real tokens into the sandbox.
`CLAUDE_CODE_OAUTH_TOKEN`, `GH_TOKEN`, and `GITHUB_TOKEN` are on the environment allowlist in `internal/worker/sandbox.go`.
That is fine for those two credentials, and this phase does not remove them.
It adds a route for everything else.

## What was built

A fourth network posture, `broker`, in the fork at `7302ebd` plus this change.

- `internal/protocol/stage_kind.go` holds `NetworkBroker`, and both `SupportedNetworkPosture` and `ImplementedNetworkPosture` accept it.
  This file, not `execution_profiles.go`, is the authority for the posture vocabulary.
- `internal/controlplane/execution_profiles.go` accepts it and names it in the two validation errors.
  The control plane does not check whether the worker that will run it holds a broker credential: it cannot know which worker claims the run.
- `internal/worker/sandbox.go` maps `broker` onto bridge networking, and for that posture only, adds `--add-host host.docker.internal:host-gateway`, mounts the proxy root read-only at `/etc/factory/broker-ca.pem`, and derives the proxy and CA variables.
- `internal/worker/supervisor.go` fails the attempt at the boundary when the worker cannot honour the posture, reporting `supervisor_error` with the name of the missing variable.

No migration, and no protocol version bump.
`protocol.Sandbox` is unchanged, so a version-mismatched supervisor is not affected: the posture is a string that already crossed the wire.

### The worker's side of the contract

Read from the worker's own environment, never forwarded to the container.

| Variable | Required | Default |
|---|---|---|
| `AGENT_VAULT_TOKEN` | yes | none, exported by `vault-run` |
| `AGENT_VAULT_VAULT` | yes | none, exported by `vault-run` |
| `FACTORY_BROKER_CA` | no | `$HOME/.agent-vault/ca/ca.crt.pem` |
| `FACTORY_BROKER_PROXY_HOST` | no | `host.docker.internal:14322` |

So `vault-run --device factory-worker -- factory worker` is sufficient on its own.
That was not true of the original scope, which named a CA path in another repository that the worker process cannot see.

## Corrections to the original scope

Three things in the version of this document written on 2026-09-03 were wrong, found by reading the code rather than by reasoning about it.

1. **Scope item 1 named the wrong mechanism.**
   It said to extend `sandboxEnvironmentAllowlist` with the proxy and CA variables.
   That allowlist is a passthrough filter over the worker's own `os.Environ()`, so adding those names would forward whatever the worker happened to hold, into every posture, including `none` and `open`.
   It would also hand the container the worker's `127.0.0.1:14322`, which inside a container is the container's own loopback.
   The worker derives these values per container instead and applies them on top of the allowlist.
2. **The document pointed at the wrong file.**
   It sent the reader to `internal/controlplane/execution_profiles.go` lines 47 to 52 for the posture gate.
   The authority is `internal/protocol/stage_kind.go`.
   A reader following the original would have patched the wrong file and still been rejected.
3. **The variable list was incomplete and case-wrong.**
   It was a copy of `vault-run`'s list minus `DENO_CERT`, and inherited its uppercase-only bug.
   `curl`, and therefore git over libcurl, reads `http_proxy` in lower case only; `man 1 curl` on this machine says so explicitly.
   Both cases of all four proxy variables are set, and all six CA variables are set.
   `NODE_USE_ENV_PROXY` is kept for other Node tooling, but it is not the lever for Claude Code, which does its own proxying and reads `NODE_EXTRA_CA_CERTS`.

A fourth claim could not be met as written and was reinterpreted rather than dropped: see the acceptance section.

## Not in scope

- Removing `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN` from the allowlist.
  Claude Code authenticates with claude.ai OAuth, not through a proxyable API key, and `gh` in the sandbox is simpler with a real token.
  Revisit when agent-vault supports either.
- Egress filtering.
  Posture `broker` is still bridge networking.
  A true allowlist posture is a separate change to the control plane.

## Done means

All three criteria are met, and the first two are Go tests rather than shell transcripts.

- **`INV-6` still holds: a run with posture `none` has no network.**
  `TestSandboxNetworkNoneCannotReachTheNetwork` is unchanged and still passes, and `TestSandboxNonBrokerPosturesGetNoProxy` asserts that no broker wiring appears under any other posture.
- **A run with posture `broker` completes a GitHub API call with no `GITHUB_TOKEN` in its environment.**
  `TestSandboxBrokerPostureReachesGitHubWithNoGitHubToken` strips both GitHub variables, asserts the container reports zero of them in its own environment, and gets `status=200` with a `"login"` back from `https://api.github.com/user`.
  It skips unless the test process itself holds a broker credential, so it runs under `vault-run --device factory-worker -- go test ./internal/worker` and nowhere else.
- **Revoking the `factory-worker` agent makes the same run fail at the proxy.**
  The same test's negative control substitutes a token the broker does not honour and asserts the request never reaches GitHub.
  The observed shape is not a 407 on the request: the proxy refuses the CONNECT, so curl reports `status=000` and exit 56 without opening the tunnel.
  The original wording predicted a 407 and is corrected here.

### The criterion that could not be met as written

The original said `docker inspect` shows no raw token.
That is unsatisfiable by construction, and the document contradicted itself: it also specified putting the device token in the proxy URL.
Every variable is passed as inline `--env KEY=VALUE`, so the proxy URL lands in `Config.Env` and in the docker CLI's argv.

Read as "no raw upstream API key", it is met, and that is the criterion the posture actually exists to satisfy.
The token in the container is the broker's own: scoped to `proxy` on vault `chao`, `no-access` on the instance, and revocable in one place.
Every third party key stays on the host.
The code says this at the point where the variables are built, so nobody rediscovers it as a defect.

## Measured, not assumed

- A container reaches the loopback-bound proxy through `host.docker.internal`, with and without `--add-host`.
  The flag is sent always: it is redundant on Docker Desktop and required on a Linux engine, and a posture that worked on one operator's machine and not another's would be worse than a redundant flag.
- The proxy passes through hosts it has no service rule for.
  `api.anthropic.com` answers a proxied request exactly as it answers a direct one, so `NO_PROXY` exempts only the container's own loopback and Claude Code's own traffic is not a special case.
  The cost is that a broker container's egress depends on the broker being up, which is the posture working as intended.

## Known limits, outside this phase

- There is still no sandbox agent image in the fork, and the docker sandbox has never run a real attempt on this host: 0 execution profiles exist and all 10 runs used the persistent backend.
  The posture is proven by tests that build the real argument vector and run real containers, not by a factory run.
- The broker has a service rule for `api.github.com` and not for `github.com`, so git over HTTPS through the proxy is not covered.
  Git push from a container would fail on credentials in any case: the cached repository is configured with the `osxkeychain` helper.
- Code stages are not sandboxed at all.
  They run `sh -c` on the host with the worker's environment minus two variables, so the broker posture says nothing about them.
