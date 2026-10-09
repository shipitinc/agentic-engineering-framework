# Subtask Prompt Template

Use this template whenever the Manager dispatches a specialist subagent session. Copy it, fill in
**every** field, persist the filled copy under `<DISPATCH_STATE_DIR>/tasks/<TASK_ID>/prompt.md`
**before** launching, and pass it as the child's prompt. See the `aef-orchestrator` skill for the
dispatch contract and preconditions.

> Conventions (paths, concurrency limit, isolation command, routing classes) come from the project's
> `AGENTS.md` § Orchestration; where it declares none, use the `aef-orchestrator` skill § 3 defaults.

## Mandatory header (YAML — no key may be omitted)

```yaml
MANAGER: <Manager session identifier>
TASK_ID: <work-item id, unique and stable>
TASK_TYPE: design-review | implement | review | correct | re-review | integrate | research | design-produce | qa-contract | qa-execute | deploy
FEATURE: <one-line work-item name>
AREA: <bounded area label>
WORKTREE: <absolute path to the dedicated isolated worktree>
BRANCH: <branch name>
BASE_SHA: <short SHA the worktree was created from>
OWNED_PATHS:
  - <files or directories this child may edit>
READ_ONLY_PATHS:
  - <files this child may read for context but must not modify>
PROHIBITED_PATHS:
  - <generated code, other lanes' source, credentials/secrets>
ACCEPTANCE_CRITERIA: <inline checklist, or path to a durable list>
VALIDATION_COMMANDS:
  - <exact command the child must run and report>
ROUTING_CLASS: CHEAP_READ | STANDARD | PRECISION
```

## Isolation pre-flight (the child runs this first)

```bash
cd <WORKTREE>
git branch --show-current    # must equal BRANCH
git rev-parse HEAD           # must equal BASE_SHA
```

If either check fails, STOP and report `IMPLEMENTATION_BLOCKED` (or the applicable blocked result)
with the observed values. Do not write anything.

## Original request (verbatim)

Paste the request, bug report, or work-item text exactly as received. Do not summarize it away — if
it is ambiguous, do **not** guess: describe the ambiguity under **Unresolved issues** and report your
own blocked `RESULT:` token (`IMPLEMENTATION_BLOCKED`, `CORRECTION_BLOCKED`, or whichever applies to
your lane), adding `HUMAN_DECISION_REQUIRED: YES` only when the clarification is a consequential human
decision.

## Context and authoritative sources

- Product/requirement artifact(s): <paths or ids>
- Architecture / repository rules: <paths, e.g. `AGENTS.md`, architecture doc>
- Design Contract / approved design revision ref: <id or path, or `n/a`>
- QA Contract ref: <id or path, or `n/a`>
- ADRs / recorded decisions that apply: <list>
- Dependencies that must already be merged: <list>
- Other lanes currently running (and their `OWNED_PATHS`): <list, or `none`>
- Work this lane blocks: <list>
- Open Human Decision ids this lane depends on: <list>

## Acceptance criteria

- [ ] <first concrete, verifiable deliverable>
- [ ] <second concrete deliverable>
- [ ] <evidence the Manager will require, e.g. exact gate output, artifact ref, screenshot set>

## Required validation commands

Run each command below and report its exact result. Report `n/a` only with a stated reason.

- [ ] <command> — <what it must prove>
- [ ] <runtime/browser check, when applicable> — evidence must correspond to the exact `HEAD_SHA`

Do not weaken, skip, delete, or ignore a test to reach a green result. If a required command cannot
pass, report the failure with evidence instead of working around it.

## Hard rules for the child

- Write only inside `OWNED_PATHS`; never touch `PROHIBITED_PATHS`.
- Do not commit or push unless the prompt explicitly instructs it and repository policy authorizes it.
- Do not approve your own work. Reviewer lanes never modify production code.
- Stop and report rather than resolving a product, architecture, security, infrastructure,
  destructive-operation, or deployment-authority question yourself; it is a
  `HUMAN_DECISION_REQUIRED` blocker.
- Every result carries exact repository/worktree/HEAD provenance.
- **Fail fast on missing capability.** If a required tool, dependency, or declared capability is
  unavailable, STOP and report your lane's blocked `RESULT:` token with the missing capability
  named under **Unresolved issues** — do not improvise a substitute, and do not claim a check
  you could not run.

## Cleanup before returning

- [ ] Stop every server, watcher, or stub process you started; report any port/PID left running.
- [ ] Remove temporary build/download artifacts outside the project's declared evidence directory.
- [ ] Leave the worktree's tracked files clean and committed, matching the reported `HEAD_SHA`.

## Report format

Return a report conforming to `subtask-report.md` (this directory). It must be
parseable without reading conversational prose, and must include the mandatory header, files
touched, validation results, documentation updated, unresolved issues, the model/reasoning effort
actually used, and a recommended next action.

The report's `RESULT:` is **your own agent file's token**, copied verbatim — not an envelope `status`,
and not a value you choose. You never emit an envelope `status`; the Manager normalizes your token into
one using the table in `subtask-report.md` § Result normalization. For review lanes, `CORRECTION_REQUIRED`
and `HUMAN_DECISION_REQUIRED` are likewise your agent's fields, not new tokens. Do not invent tokens,
and do not add a `VERDICT` field — the report template defines none.

## Terminal step

Your lane ends at the report. After writing `report.md` to the path the Manager gave you, emit
**exactly one** `RESULT: <TOKEN>` line and make **no further tool calls** — the report on disk is
the durable signal the Manager waits on; a report returned only as a message but never written, or
a lane that keeps working after reporting, is a contract violation.
