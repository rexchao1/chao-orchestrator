---
name: spec
description: Write a task in blueprint's shape, grounded in the real code, and decide whether it needs browser review. Use after triage says spec-worthy.
---

# Spec

Write one task that a fresh agent can finish without making a product or
technical decision. The spec is the contract: it is frozen at admission and
every stage receives it complete.

## Ground it first

Never write a spec from memory of a codebase.

```bash
bin/orch-clone <project>
```

Then read the files the change touches. A vague spec is the main cause of a bad
run, and the difference between a vague spec and a good one is usually five
minutes of reading. You may read anything in `clones/`. You may not write to
it, and you may not touch `~/.factory/` at all.

## The shape

Use blueprint's task shape exactly. Do not invent headings. Copied verbatim
from `skills/plan/SKILL.md`:

```markdown
## <Plain action and result>

### What are we building?
In one to three short sentences, say what is wrong or missing and what will work after this task.

### Why?
In one or two short sentences, explain the practical value to a user, operator, or developer.

### Done when
- Three to seven observable results.

### How to check
Exact commands and required manual checks.

### Agent notes
- Depends on: <task titles, or None>
- Source: <durable design, brief, issue, or request path/URL, pinned when needed>
- Only the definitions, decisions, constraints, and failure behavior specific to this task.

### Out of scope
- Related work this task is likely to absorb by mistake.
```

Note the question marks on the first two headings, and that `Out of scope` is
part of the shape. It is load bearing: the first real run on this factory was
judged partly on having violated nothing in it.

Aim for 250 to 500 words. Hard ceiling 700. If it will not fit, it is more than
one task, so split it.

The first sections are for the human and must be readable in under a minute:
no requirement IDs, no acronyms, no implementation detail. Put decisions,
interfaces, and constraints in `Agent notes`.

## Then decide whether to render it

Render in the browser when **any** of these holds:

- **Size.** More than three `Done when` results, or more than three files.
- **Risk.** It touches authentication or authorization, a migration or schema
  change, money, deletion of user data, a public interface others consume, or
  concurrency and locking.
- **They asked.** "render it" always forces the browser path.

Otherwise print the spec in the conversation and take approval there.

Rendering is two commands, and the order matters.

```bash
bin/spec-render state/specs/<slug>.md
```

That builds the page, opens the session, prints a review URL and returns. **Say
that URL to them in your next message.** They cannot open a link they have not
been shown, and your shell output does not reach them on its own.

Then, and only then:

```bash
bin/spec-render --wait state/specs/<slug>.md
```

That blocks until they send feedback or end the session. Expect it to sit there
for minutes: that is the review happening, not a hang. One spec at a time. Do
not background it, and never tell them it is being watched while you are not
actually polling.

If the wait dies, or your session is restarted under it, nothing is lost.
Re-run `--wait`, or `lavish-axi poll .lavish/<slug>.html` directly. Queued
feedback survives.

Apply their feedback to the markdown, which is the contract, and re-run
`bin/spec-render` on it so the page they read and the file that gets submitted
stay the same thing. Never hand-edit the HTML: that is exactly how the two
drift apart.

## Then

Once they have approved, in the browser or in the conversation, go to
`skills/submit`. Approval means they read this spec, not that they described
the request earlier.
