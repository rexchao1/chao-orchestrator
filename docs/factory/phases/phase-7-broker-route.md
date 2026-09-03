# Phase 7: Broker route for sandboxed runs

**Status: scoped 2026-09-03, not started.
Do this once a run needs a key other than the GitHub token.**

**Goal:** an agent running inside the factory's docker sandbox reaches third party APIs through the agent-vault broker on the host, and never holds a raw API key.

**Language:** Go, in the fork.
**Blocked by:** Phase 4, which is done.

## Context

The host runs [Infisical agent-vault](https://github.com/Infisical/agent-vault) as a launchd user agent, loopback only: API on `127.0.0.1:14321`, MITM proxy on `127.0.0.1:14322`.
Everything about it lives in the private `infra` repository, `docs/broker.md`.
A process uses the broker by setting `HTTPS_PROXY` to `http://<agent-token>:<vault>@127.0.0.1:14322` and trusting the proxy's root CA.
The proxy adds the `Authorization` header for hosts that have a service rule.
This is verified on the host with `curl` and with agent-vault's own `run` launcher.

Today the worker passes real tokens into the sandbox.
`CLAUDE_CODE_OAUTH_TOKEN`, `GH_TOKEN`, and `GITHUB_TOKEN` are on the environment allowlist in `internal/worker/sandbox.go`.
That is fine for those two credentials, and this phase does not remove them.
It adds a route for everything else.

## Read first

- `infra/docs/broker.md` and `infra/docs/secrets.md`, for how a device token is minted and stored.
  An agent named `factory-worker` already exists on the broker with role `proxy` on vault `chao`, and its token is in `infra/secrets/devices/factory-worker.enc.yaml`.
- `internal/worker/sandbox.go`: `sandboxEnvironmentAllowlist` and `sandboxNetworkArgument`.
- `internal/controlplane/execution_profiles.go` lines 47 to 52: the control plane rejects an `allowlist` network posture, so today the choice is `open` (bridge) or `none`.
- `design.md` section 8, the trust boundary.

## Decided

- **The proxy, not tsnet, is the transport.**
  The old idea of a tsnet spike to work around `tailscale serve` rewriting the Host header is moot: factory commit `590487f` ("WithPublicHost trusts one operator-named Host") fixed it.
  The broker does not use `tailscale serve` at all, because the tailnet is shared with the clinic and has no ACLs; see `infra/docs/tailscale.md`.
- **The sandbox reaches the broker over the docker host gateway**, not over loopback.
  The container's `127.0.0.1` is its own.
  Docker Desktop on macOS exposes the host as `host.docker.internal`, so the proxy URL inside the container is `http://<token>:chao@host.docker.internal:14322`.
- **The worker owns the token.**
  It reads `AGENT_VAULT_TOKEN` and `AGENT_VAULT_VAULT` from its own environment, started through `vault-run --device factory-worker`, and derives the container variables.
  Runs never see the worker's config.

## Scope

1. Extend `sandboxEnvironmentAllowlist` with `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`, `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, `GIT_SSL_CAINFO`, `NODE_USE_ENV_PROXY`.
   `AGENT_VAULT_TOKEN` stays off the list; the token only appears inside the proxy URL.
2. Mount the proxy CA read-only into the container, from `infra/broker/mitm-ca.pem`, at a fixed path the CA variables point to.
3. A new network posture, `broker`, that maps to bridge networking plus `--add-host host.docker.internal:host-gateway` on Linux workers (a no-op on Docker Desktop) and sets the proxy variables.
   The control plane accepts it alongside `open` and `none`.
4. `NO_PROXY` must not include `host.docker.internal`, and must include the update socket if it is ever exposed over TCP.
5. A test in the fork that starts a run with posture `broker`, hits `https://api.github.com/user` from inside the container with no `GITHUB_TOKEN` in the environment, and gets the expected login back.

## Not in scope

- Removing `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN` from the allowlist.
  Claude Code authenticates with claude.ai OAuth, not through a proxyable API key, and `gh` in the sandbox is simpler with a real token.
  Revisit when agent-vault supports either.
- Egress filtering.
  Posture `broker` is still bridge networking.
  A true allowlist posture is a separate change to the control plane.

## Done means

- `INV-6` still holds: a run with posture `none` has no network.
- A run with posture `broker` completes a GitHub API call with no `GITHUB_TOKEN` in its environment, and `docker inspect` shows no raw token.
- Revoking the `factory-worker` agent on the broker makes the same run fail with a 407 from the proxy.
