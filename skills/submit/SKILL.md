---
name: submit
description: Send an approved spec to the factory queue. Use after triage says isolated, or after the human approved a spec.
---

# Submit

You own the decision to send. You do not own the payload.

```bash
bin/factory-submit --project <name> --name "<title>" --spec-file <path>
```

Write the spec to a file first. Never pass it as an argument: quoting will
corrupt it eventually, and the script reads a file precisely so that cannot
happen.

## Reviewed work needs the three stage pipeline

The project map names a default pipeline. `--pipeline` overrides it by name,
and the script resolves the name against the factory's own list, so you never
write an id.

```bash
bin/factory-submit --project <name> --name "<title>" --spec-file <path> \
  --pipeline "Implement, review, deliver"
```

Use a three stage pipeline for anything that should be reviewed before it is
delivered, which is everything triage sent to a spec. Two stages cannot do it:
`Gap 10` and `Gap 11` in ChaoFactory's `fork-notes.md` mean a reviewing stage
that also reports the outcome loses its verdict, and only the final stage is
told the publish branch. If you get the name wrong the script prints the real
ones, so guess and read rather than asking them.

## You do not choose delivery

There is no delivery flag, on purpose. Whether a pull request merges
automatically is a per-project setting, made once in the cockpit behind a
confirmation, and a submission is the wrong place to revisit it. If they ask
for auto-merge, tell them where the toggle is. Do not look for a way around it.

## Show the whole batch before you send any of it

Submitting no longer stops to ask permission per command. That prompt used to
be the moment a human saw the work. It is gone, so this section is the gate
now, and it is the only one left. Treat it that way.

**When you have more than one thing to submit, present all of them together,
then send the whole set once they say go.** Not one at a time, and not silently.

Keep the presentation short enough to read on a phone. One block each:

```
1. Reject invalid names in greet          scratch
   greet('') returns "Hello, !" today. After this it throws a TypeError.
   Judgment call: whitespace-only names are invalid, ' bob ' is valid.

2. Add a farewell function                scratch
   New farewell(name) beside greet, same validation rules.
   Judgment call: none.
```

Title, project, one or two lines of what changes and why, and the single
decision most likely to be wrong. Not the spec text. They can ask for any spec
in full, and `bin/spec-render` is there when they want to read one properly in
a browser.

Then stop and wait.

- A clear go means submit the whole set and report every run id in one block.
- A comment on one item means revise that item and present the set again. Do
  not submit the rest ahead of it: they are reviewing a set, and a set that
  changes underneath them is not the set they approved.
- Silence is not a go.

## One small thing goes straight through

A single change they described themselves in this conversation, which triage
called isolated, does not need a batch presentation. Submit it and tell them
what you sent.

The exception is exactly that narrow. It is not for the first of several, and
it is not for a spec you wrote and they have not seen. If you are deciding
whether something qualifies, it does not.

## Pre-approved is an assertion, not a default

The script sends `pre_approved: true`, which tells the factory a human was in
the loop. That is true when:

- triage said **isolated**, and they described the change themselves, or
- triage said **spec-worthy** and they approved the spec you showed them, or
- it was in a batch you presented and they said go.

It is not true if you wrote a spec and submitted it without showing them. If
that ever happens, use `--draft`, which admits it as a draft that waits for
approval in the cockpit.

Nothing in the environment enforces this any more. `bin/factory-submit` runs
without a permission prompt, so the honesty of `pre_approved` now rests
entirely on you following the two sections above.

## Reading the result

Three states come back.

| State | Means |
|---|---|
| `queued` | admitted and assigned to a worker |
| `blocked` | admitted, no worker free right now. Not an error, not a gate |
| `draft` | waiting for approval. Only from `--draft` |

Report the state plainly and give them the run id. Then stop. Do not poll.

## Known errors and what they mean

| Code | What went wrong |
|---|---|
| `invalid_repository` | the project map has a URL, not `github.com/owner/name` |
| `repository_not_found` | the repository is not registered with the factory |
| `pre_approval_not_permitted` | only orchestrator submissions may pre-approve |
| `invalid_task_runtime` | should not happen; the script pins `claude-code` |
| `agent_prompt_too_large` | the spec is too big. Split it |
