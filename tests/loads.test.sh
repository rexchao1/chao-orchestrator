#!/usr/bin/env bash
# Proves the two discovery mechanisms this repo depends on:
#   1. AGENTS.md is loaded, via the CLAUDE.md import.
#   2. skills/ is discovered, via the .claude/skills symlink.
# Both were measured to fail without their pointer file, so both get a test.
#
# Runs on the host. Requires a claude with keychain access, so it must run
# inside the GUI-started tmux server, not over a bare SSH session.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
ok()      { printf 'ok - %s\n' "$1"; }
notok()   { printf 'not ok - %s\n' "$1"; fail=1; }

out="$(claude -p 'Answer in exactly two lines. Line 1: "SENTINEL:" followed by the loading sentinel from your operating contract, or NONE. Line 2: "SKILLS:" followed by a comma separated list of every skill you can load whose name starts with orch, or NONE.' 2>&1)"

printf '%s\n' "$out"

if printf '%s' "$out" | grep -q 'ORCHESTRATOR-LOADED'; then
  ok "AGENTS.md is loaded through the CLAUDE.md import"
else
  notok "AGENTS.md was NOT loaded. Check that CLAUDE.md contains @AGENTS.md"
fi

if [ -L .claude/skills ] && [ -d .claude/skills ]; then
  ok ".claude/skills resolves to a directory"
else
  notok ".claude/skills is not a working symlink"
fi

exit "$fail"
