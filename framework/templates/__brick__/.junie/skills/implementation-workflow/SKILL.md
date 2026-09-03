---
name: implementation-workflow
description: Procedure for production implementation and correction lanes in this framework — declare path ownership, keep validation discipline, report exact HEAD/provenance, and never make placeholder completion claims. Use when implementing or correcting a delegated feature/change.
---

# Implementation workflow

Use this skill whenever you implement or correct a delegated change in a production-writing lane
(implementer or correction-implementer). It encodes the non-negotiable discipline required by
`AGENTS.md`, `docs/engineering/WORKFLOW.md`, and the ADRs.

## 1. Declare ownership before writing

Before editing anything, declare explicitly:

- `OWNED_PATHS` — the only paths you may create/modify.
- `READ_ONLY_PATHS` — paths you may read but must not change.
- `PROHIBITED_PATHS` — paths you must never touch.

Ownership must not overlap with any concurrent writer. If it would overlap, stop and report it —
work must be serialized or re-partitioned (AGENTS.md concurrency invariant).

## 2. Validation discipline

- Identify the required deterministic gates for the stack and run them for real. For this repo's
  Dart CLI they are: `dart format --output=none --set-exit-if-changed .`, `dart analyze`, `dart test`.
- Required gates must genuinely pass before claiming completion.
- Never weaken, delete, `@Skip`/`@Ignore`, or bypass tests (`-x`, skip flags) to force green.
- Assume test failures are caused by your change; make genuine fix attempts. After ~3 failed genuine
  attempts on the same issue, stop and report it as a blocker rather than hacking around it.
- Runtime/browser validation only when applicable, and it must correspond to the exact reviewed HEAD.

## 3. Report exact HEAD / provenance

Every result must include the branch/worktree, `BASE_SHA`, and `HEAD_SHA` you actually produced,
plus the concrete `FILES_CHANGED`. Provenance must be verifiable by an independent reviewer.

## 4. No placeholder completion claims

- `RESULT: IMPLEMENTED` / `CORRECTION_COMPLETE` means the work is genuinely done and gates pass.
- If it is not done or a required gate cannot pass, report `IMPLEMENTATION_BLOCKED` /
  `CORRECTION_BLOCKED` with evidence — never a false green.
- Stubs/not-yet-implemented behavior must be explicit and must not report success or mutate state.

## 5. You never approve your own work

Hand a completed change to independent review. Set `READY_FOR_INDEPENDENT_REVIEW` /
`READY_FOR_FOCUSED_REVIEW` to `YES` only when the result is genuinely ready.

## 6. Classify durable discoveries

Before finishing, apply the `repository-learning` skill to classify and persist durable findings.
