# Checkpoints

How a boulder, an idea too big for one spec, becomes factory work.
The assessment that sized this lives in agent-skills as a Lavish artifact; this is the part that survived it.

## The chain

```
boulder -> route -> checkpoint loop -> lavish review -> freeze -> (wayfinder, fog only) -> pebble -> factory -> closure -> next checkpoint
```

| Step | Who | Artifact |
|---|---|---|
| route | boulder skill, one pass | `state/checkpoints/<project>/route.md` |
| draft, critique, revise | boulder and checkpoint-critic, one fresh pass each | `<n>.md`, `<n>.critique-<r>.json` |
| review | the human, in Lavish | `<n>.answers.txt` |
| freeze | boulder skill, one pass | `<n>.md` with status `frozen` or `fog` |
| fog | a wayfinder session on the project | issues on the project |
| pebble | pebble skill, one pass | `<n>/tasks/NN-*.md`, `<n>/credentials.txt` |
| preflight | `bin/checkpoint-preflight`, against the vault's service rules | one line per host, MISSING fails |
| submit | `skills/submit`, batch gate | factory runs |
| closure | the last task | acceptance checks and the decision record |
| close | `bin/checkpoint-close`, run when the closure PR merges | PRD and route line say `built` |

The skills come from agent-skills and are installed at the user level.
`bin/checkpoint-pass` inlines the installed skill body into the prompt, so a pass runs the same words the human can read in `~/.claude/skills/`.

## Rules that make it checkable

- **Certainty.** Every decision in a PRD is cited or marked Not yet specified. The critic looks for the third thing, a guess written as a decision.
- **Split.** More than five factory tasks from pebble means the checkpoint splits.
- **Fog.** A question the human can answer in the review becomes a decision; one that needs research becomes a wayfinder ticket; too many of those is the split rule again.
- **Read-only.** A pass has Read, Grep, Glob, WebFetch, and WebSearch, nothing else, under `--permission-mode dontAsk`. It prints its output and the script writes it. INV-2 holds because the pass sees only the read-only clone and the script writes only under `state/`.
- **Credentials by name.** pebble names hosts, preflight checks each against the vault's service rules through the vault CLI, and a missing rule stops the submit. No value passes through an agent; the broker adds it at request time.
- **One human gate per checkpoint,** the review. The batch presentation before submit is the existing gate from `skills/submit` and is unchanged.

## Cost

Every pass appends a row to `state/checkpoints/ledger.tsv` with the cost claude reports, at list rates, subscription or not.
`bin/checkpoint-cost` rolls the ledger up per checkpoint and per project and adds a build estimate from `config/models.tsv` prices.
The estimate is labelled as one everywhere it appears.

## Status lives in two files and never disagrees

The PRD carries `Status:` and the route carries one status word per checkpoint line.
`bin/checkpoint-pass freeze` flips the route line to frozen when the PRD lands frozen, and `bin/checkpoint-close` flips both to built.
No pass edits the route after it is written; the two scripts are the only writers, so a stale route means a script was skipped, not a model that forgot.
The vault link on the review page comes from `config/vault.url` and the preflight's vault name from `config/vault.name`; `config/vault.*` is gitignored because both are private.

## Models

`config/models.tsv`: `plan` runs on Fable 5.1 at high effort, `critic` on Opus 5 at xhigh.
Edit the row to switch; `--model` and `--effort` override one pass.
The build model is the factory execution profile's, set in the cockpit.

## Follow-ups in the factory fork

Three small changes would close the gaps this design works around.
None is needed to run the chain.

1. **Attempt cost.** The worker already parses claude's final `result` event and keeps its text. Keep `total_cost_usd` and `usage` too, store them on the attempt, expose them on the Work API. Then `bin/checkpoint-cost` replaces its build estimate with the measured number.
2. **Execution profile at admission.** `AdmitWorkRequest` has no profile field, so a submission cannot pick the build model. Adding one lets `config/models.tsv`'s build row mean something.
3. **Actor on the answer API.** `AnswerWork` hardcodes the operator actor. An actor field is what lets a future overseer answer a needs-input question with a citation and be seen doing it.
