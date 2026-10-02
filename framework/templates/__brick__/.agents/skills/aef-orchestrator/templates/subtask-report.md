# Subtask Report Template

Every specialist subagent session returns this report to the Manager when a subtask completes, is
blocked, or needs clarification. Persist the returned report verbatim under
`<DISPATCH_STATE_DIR>/tasks/<TASK_ID>/report.md`. See the `aef-orchestrator` skill.

The report is the lane's only contract with the Manager: the Manager parses it, never the
conversation. Report only what was actually executed — a check that was not run is `NOT_RUN`, never
`pass`.

## Mandatory header

```yaml
RESULT: <this lane's own RESULT: token — see "RESULT: vocabulary per lane" below; never invented>
TASK_ID: <work-item id>
TASK_TYPE: design-review | implement | review | correct | re-review | integrate | research | design-produce | qa-contract | qa-execute | deploy
FEATURE: <one-line work-item name>
WORKTREE: <absolute worktree path>
BRANCH: <branch name>
BASE_SHA: <base short SHA>
HEAD_SHA: <current short SHA>
COMMITTED: YES | NO            # NO when repository policy forbids the child from committing
```

`RESULT:` is **the agent's own vocabulary, not this template's**. Every shipped agent declares its own
`RESULT:` token set in its agent file under `.agents/agents/`, and the child emits one of those tokens
verbatim. This template never defines, renames, or extends that vocabulary — there is no template-level
`RESULT:` vocabulary and no template-level `VERDICT` field.

## `RESULT:` vocabulary per lane

| `TASK_TYPE` | Emitting agent | `RESULT:` tokens (verbatim from the agent file) |
|-------------|----------------|-----------------------------------------------|
| `design-review` | `design-reviewer` — `.agents/agents/design-reviewer.md` | `DESIGN_REVIEW_APPROVED` \| `DESIGN_REVIEW_CHANGES_REQUIRED` \| `DESIGN_REVIEW_HUMAN_DECISION_REQUIRED` |
| `implement` | `implementer` — `.agents/agents/implementer.md` | `IMPLEMENTED` \| `IMPLEMENTATION_BLOCKED` |
| `review` | `engineering-reviewer` — `.agents/agents/engineering-reviewer.md` | `APPROVE_FOR_MERGE` \| `APPROVE_WITH_NON_BLOCKING_FOLLOWUP` \| `DO_NOT_MERGE` |
| `correct` | `correction-implementer` — `.agents/agents/correction-implementer.md` | `CORRECTION_COMPLETE` \| `CORRECTION_BLOCKED` |
| `re-review` | `focused-reviewer` — `.agents/agents/focused-reviewer.md` | `APPROVE_CORRECTIONS` \| `DO_NOT_APPROVE_CORRECTIONS` |
| `integrate` | `integrator` — `.agents/agents/integrator.md` | `MERGE_APPROVED` \| `INTEGRATION_BLOCKED` |
| `research` | **no dedicated research agent exists.** Manager-self research runs in the Manager's own lane and yields **no** child report (it is a ledger entry, not a lane result). If the Manager dispatches research to an isolated lane it uses a read-only agent, and that child then emits **that agent's** tokens from this table | *(whichever agent the Manager dispatched)* |
| `design-produce` | `design-agent` — `.agents/agents/design-agent.md` | `DESIGN_REVISION_COMPLETE` \| `DESIGN_REVISION_BLOCKED` |
| `qa-contract` | `qa-architect` — `.agents/agents/qa-architect.md` | `QA_CONTRACT_CREATED` \| `QA_CONTRACT_FROZEN` \| `QA_CONTRACT_BLOCKED` |
| `qa-execute` | `qa-executor` — `.agents/agents/qa-executor.md` | `QA_RESULT_PASS` \| `QA_RESULT_FAIL` \| `QA_RESULT_PARTIAL` \| `QA_RESULT_BLOCKED` |
| `deploy` | `deployment-authority` — `.agents/agents/deployment-authority.md` | `DEPLOYMENT_SUCCESSFUL` \| `DEPLOYMENT_FAILED` \| `DEPLOYMENT_ROLLED_BACK` \| `DEPLOYMENT_PARTIAL` |

The four fixed-agent phases the `aef-orchestrator` skill § 7 phase table dispatches to `design-agent`,
`qa-architect`, `qa-executor`, and `deployment-authority` carry a `TASK_TYPE` value (`design-produce`,
`qa-contract`, `qa-execute`, `deploy`) so the mandatory header above is satisfiable for them; the
`TASK_TYPE` names the lane, the agent file above owns the `RESULT:` vocabulary. Every agent's tokens are
normalized below.

## Result normalization (child token → envelope `status`)

**Precedence rule: the child's own `RESULT:` token is authoritative. The child emits only that token
and never emits an envelope `status` itself** — it has no vocabulary for one, and inventing one is a
contract violation. **The Manager** normalizes the token into the envelope `status` using the table
below and persists the envelope per `docs/engineering/STRUCTURED_RESULTS.md`. If a child's `RESULT:`
token is **absent from this table, misspelled, or replaced by an envelope `status` value, the Manager
rejects the result as malformed and the child must re-emit it** with its own token; a rejected result
never advances workflow state. Both the lane header here and the envelope are then distinct artifacts:
`RESULT:` is the child's outcome token, `status` is the Manager's normalized envelope member.

**Which `status` a token emits:** where the authority's own per-`result_type` payload section in
`docs/engineering/STRUCTURED_RESULTS.md` declares a `status` enum for that type, that per-type
declaration **binds** and this table emits one of its members; the global `Status Values (Enum)` table is
the fallback **only** for a `result_type` that declares none. One token currently has no legal per-type
member — `QA_CONTRACT` declares only `CREATED | FROZEN` — and that cell is marked below rather than
satisfied, because it is an open item for the contract owner.

| Agent | `RESULT:` token | Envelope `result_type` | Envelope `status` | Also set |
|-------|-----------------|------------------------|-------------------|----------|
| `implementer` | `IMPLEMENTED` | `IMPLEMENTATION_RESULT` | `COMPLETE` | — |
| `implementer` | `IMPLEMENTATION_BLOCKED` | `IMPLEMENTATION_RESULT` | `BLOCKED` | `blockers[]` |
| `correction-implementer` | `CORRECTION_COMPLETE` | `IMPLEMENTATION_RESULT` | `COMPLETE` | — |
| `correction-implementer` | `CORRECTION_BLOCKED` | `IMPLEMENTATION_RESULT` | `BLOCKED` | `blockers[]` |
| `engineering-reviewer` | `APPROVE_FOR_MERGE` | `ENGINEERING_REVIEW` | `APPROVED` | `REVIEWED_HEAD` |
| `engineering-reviewer` | `APPROVE_WITH_NON_BLOCKING_FOLLOWUP` | `ENGINEERING_REVIEW` | `APPROVED` | `REVIEWED_HEAD`, `non_blocking_followups[]` populated |
| `engineering-reviewer` | `DO_NOT_MERGE` | `ENGINEERING_REVIEW` | `CHANGES_REQUIRED` | `REVIEWED_HEAD`, `CORRECTION_REQUIRED: YES` **only when `HUMAN_DECISION_REQUIRED: NO`** (`.agents/agents/engineering-reviewer.md`); with `HUMAN_DECISION_REQUIRED: YES` use the next row instead |
| `engineering-reviewer` | `DO_NOT_MERGE` | `ENGINEERING_REVIEW` | `HUMAN_DECISION_REQUIRED` | `REVIEWED_HEAD`, `HUMAN_DECISION_REQUIRED: YES`, `HUMAN_DECISION_TYPE: <type>`; **no** `CORRECTION_REQUIRED` — a genuine human gate escalates per `aef-orchestrator` skill § 13 and never enters the correction loop |
| `focused-reviewer` | `APPROVE_CORRECTIONS` | `ENGINEERING_REVIEW` | `APPROVED` | — |
| `focused-reviewer` | `DO_NOT_APPROVE_CORRECTIONS` | `ENGINEERING_REVIEW` | `CHANGES_REQUIRED` | `READY_FOR_MERGE: NO`, open findings under `BLOCKERS` |
| `design-agent` | `DESIGN_REVISION_COMPLETE` | `DESIGN_REVISION` | `COMPLETE` | — |
| `design-agent` | `DESIGN_REVISION_BLOCKED` | `DESIGN_REVISION` | `BLOCKED` | `blockers[]` |
| `design-reviewer` | `DESIGN_REVIEW_APPROVED` | `DESIGN_REVIEW` | `APPROVED` | — |
| `design-reviewer` | `DESIGN_REVIEW_CHANGES_REQUIRED` | `DESIGN_REVIEW` | `CHANGES_REQUIRED` | `CORRECTION_REQUIRED: YES` |
| `design-reviewer` | `DESIGN_REVIEW_HUMAN_DECISION_REQUIRED` | `DESIGN_REVIEW` | `HUMAN_DECISION_REQUIRED` | `HUMAN_DECISION_REQUIRED: YES`, `HUMAN_DECISION_TYPE: DESIGN` |
| `qa-architect` | `QA_CONTRACT_CREATED` | `QA_CONTRACT` | `CREATED` | awaits the contract review/freeze gate |
| `qa-architect` | `QA_CONTRACT_FROZEN` | `QA_CONTRACT` | `FROZEN` | the freeze **is** the QA-contract approval gate |
| `qa-architect` | `QA_CONTRACT_BLOCKED` | `QA_CONTRACT` | **no legal per-type member** | `blockers[]`; `QA_CONTRACT` declares only `CREATED \| FROZEN`, so the blocked token has no status to emit — open item for the contract owner, see `docs/engineering/WORK_STATE.md`; the Manager **must not** silently substitute a global member |
| `qa-executor` | `QA_RESULT_PASS` | `QA_RESULT` | `PASS` | requires `OVERALL_VERDICT: READY_FOR_MERGE` |
| `qa-executor` | `QA_RESULT_FAIL` | `QA_RESULT` | `FAIL` | `failures[]` classified |
| `qa-executor` | `QA_RESULT_PARTIAL` | `QA_RESULT` | `PARTIAL` | `failures[]` classified |
| `qa-executor` | `QA_RESULT_BLOCKED` | `QA_RESULT` | `BLOCKED` | `blockers[]` |
| `integrator` | `MERGE_APPROVED` | `INTEGRATION_READINESS` | `READY` | `READY_FOR_INTEGRATION` |
| `integrator` | `INTEGRATION_BLOCKED` | `INTEGRATION_READINESS` | `BLOCKED` | `blockers[]` |
| `deployment-authority` | `DEPLOYMENT_SUCCESSFUL` | `DEPLOYMENT_RESULT` | `SUCCESS` | requires `OVERALL_VERDICT: DEPLOYMENT_SUCCESSFUL` (`.agents/agents/deployment-authority.md`) |
| `deployment-authority` | `DEPLOYMENT_FAILED` | `DEPLOYMENT_RESULT` | `FAILED` | `blockers[]` |
| `deployment-authority` | `DEPLOYMENT_ROLLED_BACK` | `DEPLOYMENT_RESULT` | `ROLLED_BACK` | `rollback_reason`, `rollback_result`; with `OVERALL_VERDICT: ROLLED_BACK` |
| `deployment-authority` | `DEPLOYMENT_PARTIAL` | `DEPLOYMENT_RESULT` | `PARTIAL` | `blockers[]`; with `OVERALL_VERDICT: REQUIRES_INTERVENTION` the Manager **parks** the work item per `aef-orchestrator` skill § 13/§ 16 — envelope `status: BLOCKED` on the `ORCHESTRATION_RESULT` this deployment blocks, one entry per `blockers[]` from `.agents/agents/deployment-authority.md` with `type` and `escalation_path` set, and a Human Decision created when the intervention is a consequential gate (`G4`/`G5` in § 13); the deployment lane is never auto-retried in place |
| Manager (main session) | `AUTONOMOUS_WORKFLOW_PASS` | `ORCHESTRATION_RESULT` | `COMPLETE` | — |
| Manager (main session) | `AUTONOMOUS_WORKFLOW_PARTIAL` | `ORCHESTRATION_RESULT` | `PARTIAL` | — |
| Manager (main session) | `AUTONOMOUS_WORKFLOW_BLOCKED` | `ORCHESTRATION_RESULT` | `BLOCKED` | `blockers[]` |
| Manager (main session) | `HUMAN_DECISION_REQUIRED` | `ORCHESTRATION_RESULT` | `HUMAN_DECISION_REQUIRED` | `open_decision_ids[]` |

Every `status` in the right-hand column is a real member of the authority's **per-`result_type`** `status`
declaration for that type, or of the global `Status Values (Enum)` table where that type declares none —
no value is invented here. The narrower per-type enums (`QA_CONTRACT` `CREATED | FROZEN`, `QA_RESULT`
`PASS | FAIL | PARTIAL | BLOCKED`, `DEPLOYMENT_RESULT` `SUCCESS | FAILED | ROLLED_BACK | PARTIAL`,
`INTEGRATION_READINESS` `READY | NOT_READY | BLOCKED`) are the binding ones for their own types, so
`MERGE_APPROVED` normalizes to `READY` — not to `READY_FOR_MERGE` — and `DEPLOYMENT_SUCCESSFUL` to
`SUCCESS` — not to `DEPLOYMENT_SUCCESSFUL`. When a review lane reports a `HUMAN_DECISION_REQUIRED`
outcome, the Manager sets envelope `status: HUMAN_DECISION_REQUIRED` for that token regardless of the
token's own prefix (for example `RESULT: DESIGN_REVIEW_HUMAN_DECISION_REQUIRED`).

## Review-lane supplementary fields

Review lanes (`design-review`, `review`, `re-review`) additionally set the agent's own review fields —
these are agent fields, echoed verbatim, not template-invented:

```yaml
REVIEWED_HEAD: <exact revision reviewed>   # every review lane
CORRECTION_REQUIRED: YES | NO              # review and design-review lanes
HUMAN_DECISION_REQUIRED: YES | NO          # review and design-review lanes
HUMAN_DECISION_TYPE: <type when YES>       # design-review lanes use DESIGN
REGRESSIONS: <found | none>                # re-review lanes only
```

Every non-review lane **omits** all of these and reports `RESULT:` alone.

## Files touched

```text
<path>
<path>
```

Include only paths inside the declared `OWNED_PATHS`. If anything outside them was touched, say so
under **Unresolved issues**.

## What changed and why

- <change, and the reason for it>
- <new abstraction, state/ownership change, interface or schema change — or `none`>
- <deviation from the original plan, and why>

## Validation results

| Command | Status | Evidence / note |
|---------|--------|-----------------|
| `<command>` | pass / fail / n/a / NOT_RUN | <output reference, log path, or reason> |

Status rules:

- `pass` only when the command genuinely ran and passed at `HEAD_SHA`.
- `NOT_RUN` when the command was applicable but not executed — this blocks advancement for
  required gates.
- Runtime/browser/visual evidence MUST name the revision it was captured at; evidence from another
  revision is invalid.

## Evidence (revision-pinned)

```yaml
EVIDENCE_REVISION: <SHA the evidence was produced at>
BUILD_COMMAND:
SERVE_OR_RUN_COMMAND:
ENVIRONMENT / BASE_URL:
ARTIFACTS:                      # paths, urls, or artifact refs (screenshots, logs, reports)
  - <ref>
```

For visual/UI work, add the viewports captured and, when the project has a canonical visual
authority, the exact design frame refs compared against, plus a categorized mismatch list
(`MATERIAL` / `AMBIGUOUS` / `TRIVIAL`). Do not claim automated pixel-diff verification unless the
project actually has that tooling.

## Documentation updated

```text
<path — or "none">
```

## Model and reasoning effort

```yaml
ROUTING_CLASS_REQUESTED: CHEAP_READ | STANDARD | PRECISION
MODEL_USED: <provider/model id as actually used, or n/a>
REASONING_EFFORT: <level actually used, or n/a>
ESCALATED_INSIDE_TASK: YES | NO   # YES if the child had to raise effort/class to finish
ESCALATION_REASON: <why, or n/a>
```

Routing is replaceable execution policy, not workflow authority: this block is observability, not a
gate. It never changes which validations or approvals apply.

## Unresolved issues and blockers

- <anything preventing completion, integration, or merge>
- <Human Decision ids this lane needs, with a one-sentence question each>
- <findings for other lanes, with the concrete evidence a correction lane needs>

## Safe parallelism

```yaml
SAFE_PARALLEL_WORK:       # lanes that may start now without waiting for this one
  - <lane>
PROHIBITED_PARALLEL_WORK: # lanes that must wait, and why
  - <lane — because ...>
```

## Cleanup confirmation

- [ ] All processes started by this lane are stopped (or any intentionally left running are reported with port/PID).
- [ ] Temporary artifacts removed.
- [ ] `git status --short` clean for tracked files in the worktree.
- [ ] No files modified outside `OWNED_PATHS`.

## Recommended next action

One line: the single value the **Manager must do next**. Every value below is a real member of the
`next_actions` array declared for that `result_type` in `docs/engineering/STRUCTURED_RESULTS.md`, and it
is written into the envelope **verbatim** — the Manager neither translates nor renames it.

| Report value | Lane that reports it | `result_type` | Meaning |
|--------------|---------------------|---------------|---------|
| `INDEPENDENT_ENGINEERING_REVIEW` | `implement`, `correct` | `IMPLEMENTATION_RESULT` | work is gated and complete; needs independent review |
| `CORRECTION_LOOP` | `implement`, `correct`, `review`, `re-review` | `IMPLEMENTATION_RESULT` / `ENGINEERING_REVIEW` | independent review requires changes |
| `FOCUSED_RE_REVIEW` | `correct`, `re-review` | `ENGINEERING_REVIEW` | correction is complete; a **fresh** focused re-review is required |
| `INDEPENDENT_DESIGN_REVIEW` | design production | `DESIGN_REVISION` | revision produced; needs Independent Design Review |
| `DCR_PROCESS` | design lanes | `DESIGN_REVISION` / `DESIGN_REVIEW` | DCR level 0/1 loop, or escalation at level 2/3 |
| `DESIGN_CONTRACT_FREEZE` | design lanes | `DESIGN_REVISION` / `DESIGN_REVIEW` | approved revision is ready to freeze |
| `DESIGN_REVISION` | design review | `DESIGN_REVIEW` | review requires a new revision |
| `HUMAN_APPROVAL` | design lanes | `DESIGN_REVISION` / `DESIGN_REVIEW` | design gate needs a human (ids under **Unresolved issues**) |
| `QA_CONTRACT_REVIEW` / `QA_CONTRACT_FREEZE` | QA-contract lane | `QA_CONTRACT` | contract created / ready to freeze |
| `IMPLEMENTATION` | QA-contract lane | `QA_CONTRACT` | frozen contract unblocks implementation |
| `CLASSIFY_FAILURES` / `REMEDIATION_ROUTING` | QA-execution lane | `QA_RESULT` | failures need classification / a remediation lane |
| `MERGE` | QA-execution lane, `integrate` | `QA_RESULT` / `INTEGRATION_READINESS` | gates pass and policy authorizes merge |
| `WAIT_FOR_GATES` | `integrate` | `INTEGRATION_READINESS` | integration waits on gates |
| `RESOLVE_CONFLICTS` | `integrate` | `INTEGRATION_READINESS` | conflicts block integration |
| `PRODUCTION_VALIDATION` / `ROLLBACK` / `MARK_DEPLOYED` | deployment lane | `DEPLOYMENT_RESULT` | post-deployment path |
| `HUMAN_DECISION_REQUIRED` | `implement`, `correct`, `review`, `re-review`, QA, deployment | several | a consequential human gate blocks this lane (ids under **Unresolved issues**) |
| `DISPATCH_NEXT_LANE` / `ADVANCE_STATE` / `AWAIT_HUMAN_DECISION` / `PARK` | Manager only | `ORCHESTRATION_RESULT` | Manager-lane outcomes |

Deliberately **not** report values:

- `RETRY_WITH_PRECISION` — raising the routing class is a **Manager dispatch decision**, recorded in the
  ledger with an escalation reason (`aef-orchestrator` skill § 12/§ 15); no lane recommends it and no
  `next_actions` member corresponds to it.
- `NO_ACTION` — there is no such member. A lane reports the action that still applies; a terminal Manager
  lane reports `PARK`.
- `NEEDS_DECISION <decision_id>` — there is no parameterized member. Report `HUMAN_DECISION_REQUIRED`
  (or `HUMAN_APPROVAL` / `AWAIT_HUMAN_DECISION`) and list the decision ids under **Unresolved issues**.

`READY_FOR_FOCUSED_REVIEW` is a **separate agent field** of `correction-implementer`
(`.agents/agents/correction-implementer.md`); it is echoed in the report when the lane is `correct`, and
the *recommended next action* for that lane is `FOCUSED_RE_REVIEW`.
