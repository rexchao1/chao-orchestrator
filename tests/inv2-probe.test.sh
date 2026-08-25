#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib.sh"
PROBE="$ROOT/bin/inv2-probe"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# A victim repo the orchestrator must never write to, and an owned one it may.
mk_repo() {
  mkdir -p "$1" && git -C "$1" init -q -b main
  printf 'ignored/\n' > "$1/.gitignore"
  mkdir -p "$1/ignored"; printf 'v1\n' > "$1/ignored/blob.bin"
  printf 'hello\n' > "$1/file.txt"
  git -C "$1" add -A
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm init
}
mk_repo "$WORK/victim"
mk_repo "$WORK/orchhome/ownclone"

export INV2_ORCH_HOME="$WORK/orchhome"
export INV2_QUIET_ROOTS="$WORK/victim:$WORK/orchhome/ownclone"
export INV2_STATE_DIR="$WORK/probestate"
export INV2_SKIP_WORKER_ZONE=1     # no factory on this box
export INV2_SETTLE_SECONDS=0       # nothing is moving in a temp dir

"$PROBE" >/dev/null 2>&1; assert_eq "no args exits 3" "3" "$?"

"$PROBE" baseline >/dev/null 2>&1; assert_eq "baseline exits 0" "0" "$?"
"$PROBE" check >/dev/null 2>&1;    assert_eq "no-op check PASSes" "0" "$?"

# Writing inside the orchestrator's own directory is permitted by INV-2.
printf 'mine\n' > "$WORK/orchhome/ownclone/notes.txt"
"$PROBE" check >/dev/null 2>&1; assert_eq "own directory is not a violation" "0" "$?"

# An untracked file in a foreign repo is a violation.
printf 'oops\n' > "$WORK/victim/orchestrator-was-here.txt"
out="$("$PROBE" check 2>&1)"; rc=$?
assert_eq "foreign untracked file FAILs" "1" "$rc"
assert_contains "names the offending path" "orchestrator-was-here.txt" "$out"
rm -f "$WORK/victim/orchestrator-was-here.txt"

# The case the OLD assertion could not see at all: an in place overwrite of a
# gitignored file. git status --porcelain reports nothing for this.
printf 'v2-tampered\n' > "$WORK/victim/ignored/blob.bin"
porcelain="$(git -C "$WORK/victim" status --porcelain | wc -l | tr -d ' ')"
assert_eq "git status is blind to the ignored write" "0" "$porcelain"
out="$("$PROBE" check 2>&1)"; rc=$?
assert_eq "probe still catches the ignored write" "1" "$rc"
assert_contains "names the ignored path" "ignored/blob.bin" "$out"

# A path that was already moving when the baseline was taken cannot be
# attributed to the orchestrator afterwards. Calibration must record it and
# check must ignore it, or every other process on the machine reads as a
# violation. Measured on the host: firstmate rewrites its state/ directory
# from three live bash processes.
rm -f "$WORK/victim/orchestrator-was-here.txt"
printf 'v1\n' > "$WORK/victim/ignored/blob.bin"
export INV2_SETTLE_SECONDS=2
( for i in 1 2 3 4 5 6 7 8; do
    head -c "$i" /dev/zero | tr '\0' 'x' > "$WORK/victim/moving.log"
    sleep 0.3
  done ) &
writer=$!
"$PROBE" baseline >/dev/null 2>&1
wait "$writer"
head -c 40 /dev/zero | tr '\0' 'x' > "$WORK/victim/moving.log"
out="$("$PROBE" check 2>&1)"; rc=$?
assert_eq "a path already moving at baseline is not a violation" "0" "$rc"
assert_contains "reports how many it ignored" "ignored 1 change" "$out"

# Calibration must not blind the probe: an unrelated write in a live repository
# is still SEEN and still NAMED. It is reported as unattributable rather than as
# a violation, because another process was writing that repository too, and
# blaming it on the orchestrator would be a guess. Exit 2, never 0.
printf 'oops\n' > "$WORK/victim/still-reported.txt"
out="$("$PROBE" check 2>&1)"; rc=$?
assert_eq "an unrelated write in a live repo is not silently passed" "2" "$rc"
assert_contains "still names the path" "still-reported.txt" "$out"
rm -f "$WORK/victim/still-reported.txt"
# A repository with a live writer cannot be spoken for at all, not even for
# paths that happened to be still during the settle window. That is
# INDETERMINATE, exit 2, and it must never be reported as a pass.
out="$("$PROBE" check 2>&1)"   # victim is live from the calibration above
printf 'later\n' > "$WORK/victim/appeared-after-baseline.txt"
out="$("$PROBE" check 2>&1)"; rc=$?
assert_eq "a live repository yields INDETERMINATE, not PASS" "2" "$rc"
assert_contains "says attribution was not possible" "INDETERMINATE" "$out"
assert_contains "names the path it cannot speak for" "appeared-after-baseline.txt" "$out"
assert_contains "says not to record it as a pass" "not record this as a pass" "$out"
rm -f "$WORK/victim/appeared-after-baseline.txt" "$WORK/victim/still-a-violation.txt"

export INV2_SETTLE_SECONDS=0

exit "$TESTS_FAILED"
