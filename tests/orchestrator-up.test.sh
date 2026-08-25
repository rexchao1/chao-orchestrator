#!/usr/bin/env bash
# Runs anywhere. Uses a stub tmux, because the real one on the host holds the
# live factory sessions and this test must never touch them.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
UP="$ROOT/bin/orchestrator-up"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stub"

make_tmux() { # make_tmux <showenv-output> <ls-output>
  cat > "$WORK/stub/tmux" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "showenv -g") printf '%s\n' "$1" ;;
  "has-session -t") exit 1 ;;
  *)
    case "\$1" in
      ls) printf '%s\n' "$2" ;;
      new-session) echo "CREATED \$*" >> "$WORK/created.log" ;;
      set-option) : ;;
      *) : ;;
    esac ;;
esac
exit 0
STUB
  chmod +x "$WORK/stub/tmux"
}
export PATH="$WORK/stub:$PATH"
export ORCH_HOME="$WORK"
FIXED_UUID=6f1b9d24-7c3e-4a58-9b02-1d5e8c4a7f30
export ORCH_SESSION_UUID="$FIXED_UUID"
# Point the transcript lookup at the temp dir, so the test never depends on,
# or is confused by, the real conversations under ~/.claude/projects.
export CLAUDE_PROJECTS_DIR="$WORK/projects"

# 1. A server with no GUI provenance must be refused, not used.
make_tmux "SOME_VAR=1" "factory-server: 1 windows"
out="$("$UP" 2>&1)"; rc=$?
assert_eq "refuses a non-GUI tmux server" "1" "$rc"
assert_contains "explains why" "Terminal.app" "$out"

# 2. An empty server must be refused: exit-empty is on, so creating a session
#    there would mean the server is new, and a new server over SSH is poisoned.
make_tmux "TERM_PROGRAM=Apple_Terminal" ""
out="$("$UP" 2>&1)"; rc=$?
assert_eq "refuses when no factory session exists" "1" "$rc"
assert_contains "names the exit-empty hazard" "exit-empty" "$out"

# 3. The good case creates the session.
rm -f "$WORK/created.log"
make_tmux "TERM_PROGRAM=Apple_Terminal
__CFBundleIdentifier=com.apple.Terminal" "factory-server: 1 windows
factory-worker: 1 windows"
out="$("$UP" 2>&1)"; rc=$?
assert_eq "creates the session" "0" "$rc"
created="$(cat "$WORK/created.log" 2>/dev/null)"
assert_contains "names the session orchestrator" "orchestrator" "$created"
assert_contains "pins the fixed session id" "$FIXED_UUID" "$created"

# The first launch must CREATE the conversation. claude --resume exits 1 with
# "No conversation found" on an id it has never seen, so a plain --resume here
# would produce a tmux session whose command dies immediately.
assert_contains "first launch creates with --session-id" "--session-id" "$created"
if grep -q -- '--resume' <<< "$created"; then
  notok "used --resume on a conversation that does not exist yet"
else
  ok "does not resume a conversation that does not exist"
fi

# Once the transcript exists, it must resume rather than try to create again.
rm -f "$WORK/created.log"
mkdir -p "$WORK/projects/-some-slug"
: > "$WORK/projects/-some-slug/$FIXED_UUID.jsonl"
"$UP" >/dev/null 2>&1
created2="$(cat "$WORK/created.log" 2>/dev/null)"
assert_contains "a later launch resumes" "--resume" "$created2"
if grep -q -- '--session-id' <<< "$created2"; then
  notok "tried to create a conversation that already exists"
else
  ok "does not re-create an existing conversation"
fi
if grep -q -- '--bare' <<< "$created"; then
  notok "must never use --bare: it never reads the keychain"
else
  ok "does not use --bare"
fi

exit "$TESTS_FAILED"
