---
name: checkpoint
description: Turn a boulder, an idea bigger than one spec, into checkpoints the factory builds one at a time. Use when triage says a request is more than one spec's worth, when the human says "boulder", or when a checkpoint PRD is in review, fog, or frozen and needs its next step.
---

# Checkpoint

A boulder is an idea too big for one spec.
This skill walks it through the chain, one checkpoint at a time:

```
boulder -> route -> loop -> review -> freeze -> (wayfinder for fog) -> pebble -> submit -> closure
```

Every model pass in it is read-only and runs from `bin/`.
You run the scripts, say the outcomes, and hold the gates.
You never draft a PRD in the conversation, and you never build.

## 1. Route and loop

Save the idea in the human's words to a file under `state/`, then:

```bash
bin/orch-clone <project>
bin/checkpoint-loop <project> <n> --idea state/<file>
```

The loop writes the route on the first run, drafts the PRD for checkpoint `n`, and runs critique and revise rounds with fresh context each.
It takes minutes.
It ends with the PRD in status `review` and prints the rounds, the surviving questions, and the cost so far.
Say those numbers to the human, then move to the review.

If a pass fails, say what the script said and stop.
Do not retry in a loop, and do not edit the PRD yourself.

## 2. Review, the one human gate

Two commands, and the order matters.

```bash
bin/checkpoint-review <project> <n>
```

Say the URL it prints in your next message.
Then, and only then:

```bash
bin/checkpoint-review --wait <project> <n>
```

That blocks until they send answers or end the session.
It saves the answers next to the PRD and prints the freeze command.
One review at a time, foreground, never backgrounded.

## 3. Freeze

```bash
bin/checkpoint-pass freeze <project> <n> --answers state/checkpoints/<project>/<n>.answers.txt
```

Read the new status line.

- `frozen`: every decision is cited. Go to pebble.
- `fog`: some questions need research, a prototype, or a grilling first. Read the Fog section to the human and stop. A wayfinder session on the project picks those lines up as its first tickets; this conversation does not chart maps. When they say the map is resolved, save the decisions to a file and run freeze again with it as `--answers`.

A frozen PRD never changes.
If it turns out wrong, that is a new checkpoint on the route.

## 4. Pebble

Only when the PRD is frozen and the human confirms no ticket is open for it:

```bash
bin/checkpoint-pass pebble <project> <n> --no-open-tickets
```

It writes numbered task files in blueprint's shape under `state/checkpoints/<project>/<n>/tasks/` and a credentials line.
More than five tasks fails as oversized: the checkpoint splits, it does not get bigger tasks.

Then the credentials.
Read the hosts to the human and ask whether each one has a rule in the vault.
A missing rule stops here.
Nothing about a credential's value ever passes through you.

## 5. Submit, through the existing gate

The task files are specs.
Present them as a batch exactly as `skills/submit` says, wait for the go, then submit them in file order with `bin/factory-submit`.
The closure task is last and is submitted with the rest; the factory orders them by their dependencies.

Nothing in this skill relaxes rule 3.
A frozen PRD is approval of the plan, not of each spec.
The batch presentation is where they approve the specs.

## 6. Closure, then the next checkpoint

When the closure task's pull request merges, the checkpoint is built.
Set its route line to built by running the next loop: `bin/checkpoint-loop <project> <n+1>` drafts the next PRD from the route and what closure recorded.

## Cost

```bash
bin/checkpoint-cost                 every project
bin/checkpoint-cost <project>       one project, every checkpoint
bin/checkpoint-cost <project> <n>   every pass of one checkpoint
```

Planning passes are measured from what claude reports.
Build cost is an estimate until the factory records it, and the output says which is which.
The review page shows both, and the project total, so the human sees the money before they answer.

## Models

`config/models.tsv` sets the model and effort per role: `plan` for draft, revise, freeze, route, and pebble; `critic` for critique.
The human changes a row to switch models; `--model` and `--effort` on a single `bin/checkpoint-pass` override once.
The factory's build model is its execution profile, set in the cockpit.
