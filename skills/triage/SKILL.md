---
name: triage
description: Classify a request as isolated or spec-worthy, before any other work. Use at the start of every request for work.
---

# Triage

Decide whether this request gets a written spec and a review, or goes straight
to the queue. Treating every request the same is the main way a factory becomes
slower than just opening a terminal.

`design.md` sets the boundary: only multi-file or behavior-defining work gets a
written spec and an approval gate.

## The rule

A request is **isolated** only when all five hold. Any single failure makes it
spec-worthy.

1. **One file.** The change is confined to a single source file, plus that
   file's existing test file.
2. **No new public interface.** No new exported function, type, endpoint, CLI
   flag, config key, schema column, migration, or event. Changing the body of
   an existing one is fine. Adding a name other code can call is not.
3. **No unresolved choice.** Nothing in the request leaves an open choice that
   would change behavior, interfaces, data, security, scale, performance,
   compatibility, operations, cost, or proof. This list is blueprint's own
   escalation trigger, used verbatim.
4. **An existing mechanical check proves it.** The repository's test command
   already covers the changed behavior, or the request names the command that
   will.
5. **An end state, not a goal.** "Rename X to Y", "bump Z to 3.2", "the error
   message says Helo, fix the typo" are end states. "Make the login flow less
   confusing" is a goal.

**Ties break toward spec-worthy.** Misclassifying spec-worthy work as isolated
skips the human gate, which is the expensive error. The reverse costs a minute
of reading.

## Worked examples

| Request | 1 | 2 | 3 | Verdict |
|---|---|---|---|---|
| "the error message says Helo, fix the typo" | yes | yes | yes | isolated |
| "add a farewell function next to greet" | yes | **no**, new export | yes | spec-worthy |
| "greet should reject invalid input" | yes | yes | **no**, "invalid" is undefined | spec-worthy |
| "make the dashboard faster" | no | no | no | spec-worthy |

The third is the one that matters. It passes rules 1 and 2, so a simpler rule
would call it isolated and skip the gate on a request whose whole problem is an
undecided question.

## What to do next

- **Isolated:** write the task in the same blueprint shape anyway, because the
  agent still needs it, but do not render it and do not ask for approval. Go
  straight to `skills/submit` and submit with `--assurance fast`. Fast work uses
  one implementation agent and may auto-merge after Factory delivery and
  repository checks. The person already told you what they wanted; that is the
  human in the loop.
- **Spec-worthy:** go to `skills/spec`.

## Record misclassifications

When a submitted item comes back wrong in a way triage should have caught, say
so plainly and propose a change to this rule. The rule is meant to be revised
from real misclassifications, not guarded.
