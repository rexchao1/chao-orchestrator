# Boulder: the orchestrator watches its own checkpoints

Project: chao-orchestrator, `github.com/rexchao1/chao-orchestrator`.

## The idea

Once a checkpoint's tasks are submitted, a human watches the factory: answers needs-input questions, notices a failed run, and runs close after the closure task merges.
The frozen PRD already decides most of what a needs-input question asks.
An overseer should answer from the PRD when the PRD decides it, citing the line, and bring the human in only when the PRD is silent.
Two smaller things ride along: an approved experiment has nowhere to run, and pebble's task output is parsed from marker lines when structured output would do.

## Checkpoints, in this order

1. Overseer.
   `bin/checkpoint-watch <project> <n>` polls the checkpoint's runs through the existing factory scripts.
   On needs-input it runs a read-only pass (a new `checkpoint-answer` skill in agent-skills) over the frozen PRD and the question; the pass returns either an answer with a citation or "not decided".
   A decided answer goes back through `bin/factory-answer --actor overseer`; an undecided one is escalated to the human with the question and the PRD section it touches.
   When the closure task merges it runs `bin/checkpoint-close`; on a failed run it reports and stops.
   It never approves anything.
2. Experiments and structured pebble.
   An experiment the human approved on the review page becomes task 01 of pebble's cut, runs in the factory under the broker posture, and its PR records the result.
   Pebble returns its tasks through `--json-schema` instead of `=== NN-slug.md` marker lines.

## Constraints

- AGENTS.md hard rules hold: never write outside this repository, never improvise an API payload, never approve on the human's behalf, never start or restart a factory process.
- The overseer's answers are labeled with their actor, which needs the fork's actor field deployed first.
- Tests follow `tests/lib.sh` and the checkpoint fixtures; every new script has a test file.
- Skills live in agent-skills and are installed from there; this repository only calls them.
