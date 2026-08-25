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

out="$(claude -p 'Answer in exactly two lines. Line 1: "SENTINEL:" followed by the loading sentinel from your operating contract, or NONE. Line 2: "SKILLS:" followed by a comma separated list of the names of every skill defined in this project, or NONE.' 2>&1)"

printf '%s\n' "$out"

if grep -q 'ORCHESTRATOR-LOADED' <<< "$out"; then
  ok "AGENTS.md is loaded through the CLAUDE.md import"
else
  notok "AGENTS.md was NOT loaded. Check that CLAUDE.md contains @AGENTS.md"
fi

if [ -L .claude/skills ] && [ -d .claude/skills ]; then
  ok ".claude/skills resolves to a directory"
else
  notok ".claude/skills is not a working symlink"
fi

# The symlink resolving is a filesystem fact. Discovery is the thing that
# actually matters, and it is only observable by asking the harness. Repo-root
# skills/ was measured not to be found on its own, so this is the assertion
# that would catch the symlink being lost in a checkout.
missing=""
for skill in triage spec submit status; do
  grep -qi "$skill" <<< "$out" || missing="$missing $skill"
done
if [ -z "$missing" ]; then
  ok "all four skills are discovered through the symlink"
else
  notok "skills not discovered:$missing"
fi

exit "$fail"
