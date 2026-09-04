# Sourced by the checkpoint tests after tests/lib.sh. Builds a scratch
# orchestrator home in $WORK: a project map, the real model map, three stub
# skills carrying markers, a git-inited clone, and the stub claude.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export ORCH_HOME="$WORK"
mkdir -p "$WORK/config" "$WORK/state" "$WORK/clones/demo" "$WORK/skills"
printf 'demo\thttps://example.com/demo.git\n' > "$WORK/config/projects.tsv"
cp "$ROOT/config/models.tsv" "$WORK/config/models.tsv"
for s in boulder checkpoint-critic pebble; do
  mkdir -p "$WORK/skills/$s"
  printf -- '---\nname: %s\ndescription: stub\nuser-invocable: true\n---\n\nSKILL BODY MARKER %s\n' "$s" "$s" > "$WORK/skills/$s/SKILL.md"
done
git -C "$WORK/clones/demo" init -q
echo "hello" > "$WORK/clones/demo/README.md"
git -C "$WORK/clones/demo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false add -A
git -C "$WORK/clones/demo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init
export CHECKPOINT_SKILLS_DIR="$WORK/skills"
export CHECKPOINT_CLAUDE="$ROOT/tests/checkpoint-fixtures/claude"
export STUB_LOG="$WORK/claude-args.log"
export STUB_PROMPTS="$WORK/prompts"
printf 'Let people sign in without a password.\n' > "$WORK/idea.txt"
