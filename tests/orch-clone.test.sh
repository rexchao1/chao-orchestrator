#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
CLONE="$ROOT/bin/orch-clone"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export ORCH_HOME="$WORK"
mkdir -p "$WORK/config" "$WORK/clones"

# A local origin, so the test needs no network.
ORIGIN="$WORK/origin"
mkdir -p "$ORIGIN" && cd "$ORIGIN" && git init -q -b main
printf 'hello\n' > file.txt && git add -A
git -c user.email=t@t -c user.name=t commit -qm init
cd "$ROOT"

# Column three is the pipeline, not delivery. orch-clone reads only column two,
# but the fixture must still be a valid project map.
printf 'demo\t%s\t\n' "$ORIGIN" > "$WORK/config/projects.tsv"

"$CLONE" >/dev/null 2>&1; assert_eq "no args exits 2" "2" "$?"

out="$("$CLONE" demo 2>&1)"; rc=$?
assert_eq "clone succeeds" "0" "$rc"
assert_contains "prints the clone path" "clones/demo" "$out"
[ -f "$WORK/clones/demo/file.txt" ] && ok "content was fetched" || notok "content missing"

# Push must be impossible, not merely discouraged.
pushurl="$(git -C "$WORK/clones/demo" remote get-url --push origin 2>/dev/null)"
assert_contains "push url is disabled" "DISABLED" "$pushurl"

# The string is not the property. Assert a real push is refused, with an
# explicit refspec so that it is the disabled url doing the refusing and not
# the detached HEAD, which objects for its own unrelated reason.
if git -C "$WORK/clones/demo" push origin HEAD:refs/heads/orch-push-probe >/dev/null 2>&1; then
  notok "a push succeeded: the disabled push url is not actually blocking one"
else
  ok "an explicit refspec push is refused"
fi

# Disabling push must not have cost us fetch, which is the whole point of the
# clone. set-url --push writes pushurl and leaves url alone; prove it.
if git -C "$WORK/clones/demo" fetch --dry-run origin >/dev/null 2>&1; then
  ok "fetch still works after the push url was disabled"
else
  notok "disabling push also broke fetch"
fi

# Refresh is idempotent and does not fail on a second call.
"$CLONE" demo >/dev/null 2>&1; assert_eq "refresh is idempotent" "0" "$?"

# The clone must be clean after use, which is what INV-2 rests on.
dirty="$(git -C "$WORK/clones/demo" status --porcelain | wc -l | tr -d ' ')"
assert_eq "clone is clean after refresh" "0" "$dirty"

exit "$TESTS_FAILED"
