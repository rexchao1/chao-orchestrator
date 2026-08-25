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

## Pre-approved is an assertion, not a default

The script sends `pre_approved: true`, which tells the factory a human was in
the loop. That is true when:

- triage said **isolated**, and they described the change themselves, or
- triage said **spec-worthy** and they approved the spec you showed them.

It is not true if you wrote a spec and submitted it without showing them. If
that ever happens, use `--draft`, which admits it as a draft that waits for
approval in the cockpit.

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
