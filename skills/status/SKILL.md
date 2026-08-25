---
name: status
description: Report what the factory is doing, in plain language. Use for any question about state, progress, or what happened to a piece of work.
---

# Status

```bash
bin/factory-status            # everything
bin/factory-status <run_id>   # one run in detail
bin/factory-answer --list     # anything waiting on a human
```

Read it, then say what it means. Do not paste the output and leave them to
parse it.

## Say the useful thing first

"The farewell function is done and opened PR #3" beats a table of five runs.
Lead with what changed since they last asked.

## A `ready` run is not a merged run

`ready` means the agent opened a pull request and the server verified it against
GitHub itself: repository, publish branch, remote ref, and pull request head.
What happens after that belongs to the project, not to the run.

- Project on `pr`. The pull request waits for a human. This is the default, and
  it is not a stall. Say so, and give the URL.
- Project on `pr+automerge`. The factory merges it once an independent reviewing
  stage recorded `approve` and no check is failing. You cannot see that it
  happened. The merge is written as a work update that no API route exposes,
  which is `Gap 12` in ChaoFactory's `fork-notes.md`, so `bin/factory-status`
  prints `merge not observable` and you should say the same. Never read the
  absence of a refusal as a merge: it is equally absent when no merge was ever
  attempted.

If a project is on `pr+automerge` and a `ready` run has not merged, one of the
three `INV-8` conditions did not hold. Name the one that failed rather than
guessing: the refusal reason is appended to the session's terminal message.

```bash
bin/factory-status <run_id>
```

Never round any of this into "it worked" or "it failed". Say both halves: what
the factory did, and what is now waiting on whom.

## When something is waiting

`bin/factory-answer --list` shows every question. Bring the question to them in
their words, take their answer, and send it:

```bash
bin/factory-answer <work_id> "<their answer>"
```

Answering requeues the work from its checkpoint. The final stage re-runs.
