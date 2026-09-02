---
name: independent-review
description: Read-only independent-review checklist for this framework — verify exact-revision provenance, inspect the complete diff, verify required gates, verify tests, and check learning/documentation completeness while challenging implementer claims. Use when reviewing or focused-re-reviewing a change before integration.
---

# Independent review

Use this skill in the engineering-reviewer and focused-reviewer lanes. You are **read-only with
respect to production code** — never edit, commit, or push. Independently verify; a failed or
optimistic implementer report is evidence, not permission to skip a gate.

## Read-only review checklist

1. **Provenance**
   - Confirm the branch/worktree and that the reviewed HEAD equals the claimed `HEAD_SHA`
     (`git rev-parse HEAD`, `git status`, `git log --oneline -n 3`).
   - Any runtime/browser evidence must correspond to that exact revision; reject stale evidence.

2. **Complete diff inspection**
   - Inspect the entire diff (`git diff <base>..<head>`), not a summary.
   - Verify only declared `OWNED_PATHS` were changed; product-only / prohibited paths untouched.
   - Check architecture and ownership boundaries against `AGENTS.md`, `docs/engineering/WORKFLOW.md`,
     and relevant ADRs (e.g. ADR 0002 exit-code/result contracts for the framework CLI).

3. **Gates verification**
   - Re-run each required gate yourself and record the command + result
     (`dart format --output=none --set-exit-if-changed .`, `dart analyze`, `dart test`).
   - Confirm no test was weakened, skipped, or removed to force green.

4. **Tests**
   - Confirm tests genuinely cover the change, including negative/edge cases and the specific
     behaviors required by the feature contract.

5. **Learning completeness**
   - Confirm durable discoveries were classified and persisted per
     `docs/engineering/LEARNING_POLICY.md`, in the correct authoritative artifact.

## Verdicts

- `APPROVE_FOR_MERGE` — no blockers; gates pass; provenance verified.
- `APPROVE_WITH_NON_BLOCKING_FOLLOWUP` — approvable now; record follow-ups that do not invalidate a
  required gate.
- `DO_NOT_MERGE` — blockers exist. Set `CORRECTION_REQUIRED: YES` unless the finding is a genuine
  `HUMAN_DECISION_REQUIRED` (product/architecture/security/destructive/infra/deployment).

For a **focused** re-review, restrict scope to the corrected findings plus regression risk from the
corrections; do not repeat a full review unless evidence requires it.
