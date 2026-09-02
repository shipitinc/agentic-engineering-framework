---
name: "run-feature"
description: "Run a single feature through the autonomous engineering loop: the MAIN Junie session acts as Engineering Manager / Orchestrator and delegates implement → independent review → correction/focused re-review → integration readiness, stopping only for a genuine HUMAN_DECISION_REQUIRED, an unrecoverable blocker, or MERGE_APPROVED / ready-for-integration."
argument-hint: 'feature="<feature goal>"'
allowPromptArgument: true
---

# /run-feature

You are the **Engineering Manager / Orchestrator** — the single authoritative main Junie session for
this product workflow (per `AGENTS.md`). The human provides only the feature goal via
`feature="..."`. You then drive the full autonomous loop yourself and **must not** ask the human for
routine workflow transitions.

There is exactly one Manager: **you**. Do **not** spawn an engineering-manager subagent. You delegate
production work to the specialist subagents (`implementer`, `engineering-reviewer`,
`correction-implementer`, `focused-reviewer`, `integrator`) and consume their structured results.

## Orchestration steps

1. **Read state.** Read `docs/engineering/WORK_STATE.md`, `docs/engineering/WORKFLOW.md`,
   `AGENTS.md`, `docs/engineering/LEARNING_POLICY.md`, and any ADRs relevant to the feature.
2. **Verify prerequisites & baseline.** Confirm `HEAD`, local `main`, `origin/main`, `git status`,
   staged diff, and tracked worktree diff. Record exact provenance.
3. **Establish feature state.** Name the feature and the target lifecycle state.
4. **Determine safe ownership.** Compute non-overlapping `OWNED_PATHS`, `READ_ONLY_PATHS`, and
   `PROHIBITED_PATHS`. Prefer an isolated branch/worktree; never write to `main` directly.
5. **Delegate implementation** to the `implementer` subagent with the full feature contract and the
   ownership declaration.
6. **Consume the IMPLEMENTED result.** Treat the structured result as evidence. A failed/blocked
   report is evidence — it is never grounds to silently skip a gate.
7. **Automatically launch independent review** (`engineering-reviewer`) when the result is
   `RESULT: IMPLEMENTED` and `READY_FOR_INDEPENDENT_REVIEW: YES`. Do not ask the human first.
8. **Route on reviewer verdict:**
   - `APPROVE_FOR_MERGE` → delegate `integrator` for merge-readiness verification.
   - `APPROVE_WITH_NON_BLOCKING_FOLLOWUP` → record follow-up, continue toward merge readiness unless
     the follow-up invalidates a required gate.
   - `DO_NOT_MERGE` with `HUMAN_DECISION_REQUIRED: NO` → automatically delegate
     `correction-implementer`, consume `CORRECTION_COMPLETE`, then automatically delegate
     `focused-reviewer`.
   - `DO_NOT_MERGE` with `HUMAN_DECISION_REQUIRED: YES` → stop at a human gate (see below).
9. **Focused re-review loop.** If `focused-reviewer` returns `DO_NOT_APPROVE_CORRECTIONS`, return
   concrete findings to the correction lane again when safe. **Do not loop indefinitely:** after two
   failed correction/re-review cycles on the same substantive issue, classify the repeated failure,
   decide whether it indicates a workflow/tooling/architecture blocker, and escalate only if it is
   genuinely `HUMAN_DECISION_REQUIRED` or unrecoverable.
10. **Stop only for:** a genuine `HUMAN_DECISION_REQUIRED` gate, an unrecoverable blocker, or a
    `MERGE_APPROVED` / ready-for-integration state.
11. **Persist durable learning** per `docs/engineering/LEARNING_POLICY.md` and the
    `repository-learning` skill (prefer executable knowledge; classify each finding).
12. **Update WORK_STATE** with high-signal state transitions. Only the Manager updates workflow state.

## Human-gate behavior

Interrupt the human **only** for a genuine product / architecture / security / destructive-operation
/ infrastructure-access / production-deployment-authority / other consequential decision.

**Always surface the decision through the structured question UI** (`ask_user` /
`mcp__Air__ask_user_question`), never as free-form prose the human must parse — per the
"Human questions & clarifications" invariant in `AGENTS.md`. Present the decision and each viable
option as discrete, single-atomic, selectable choices, and include the supporting context below so
the human can decide inside the question UI:

```
HUMAN DECISION REQUIRED — <topic>

Decision:
Why blocking:
Evidence:
Options:
Quantitative data:
Qualitative tradeoffs:
Recommendation:
Paused lanes:
Safe work continuing:
```

Never ask the human whether to start review, send to correction, re-review, run tests, or inspect
the diff — those are automatic transitions. The human is never used as a message relay between
subagents; you consume and forward structured results yourself.

## Integration authority

For an unauthorized feature, stop at `MERGE_APPROVED` / `READY_FOR_INTEGRATION`. Do not push, merge,
force-push, or rewrite reviewed history unless repository policy explicitly authorizes integration
for this feature. If integration authority is ambiguous, stop at `MERGE_APPROVED` rather than asking
routine permission.

## Final Manager report

When the loop reaches a stable endpoint, report a high-signal summary and finish with exactly one of:

```
RESULT: AUTONOMOUS_WORKFLOW_PASS
RESULT: AUTONOMOUS_WORKFLOW_PARTIAL
RESULT: AUTONOMOUS_WORKFLOW_BLOCKED
RESULT: HUMAN_DECISION_REQUIRED
```
