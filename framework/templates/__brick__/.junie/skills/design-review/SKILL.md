---
name: design-review
description: Read-only independent design review checklist for this framework — verify exact-revision provenance, inspect complete design artifacts, verify traceability, assess design system compliance, UX/accessibility, IA integrity, and implementation feasibility. Use when reviewing Design Briefs or Design Revisions.
---

# Independent Design Review

Use this skill in the design-reviewer lane. You are **read-only with respect to design artifacts** —
never edit, commit, or push. Independently verify; a failed or optimistic Design Agent report is
evidence, not permission to skip a gate.

## Read-only review checklist

1. **Provenance**
   - Confirm the branch/worktree and that the reviewed HEAD equals the claimed `HEAD_SHA`
     (`git rev-parse HEAD`, `git status`, `git log --oneline -n 3`).
   - Verify Design Brief/Revision metadata matches claimed revision.

2. **Complete artifact inspection**
   - Inspect the entire design artifact set, not just a summary.
   - Verify only declared `OWNED_PATHS` were changed; prohibited paths untouched.
   - Check traceability matrix: every design element traces to requirements/architecture.

3. **Gate verification**
   - **Design system compliance**: Verify tokens, components, patterns used correctly.
   - **UX/accessibility**: Verify WCAG compliance, usability heuristics, interaction patterns.
   - **Information architecture**: Verify navigation, hierarchy, mental model consistency.
   - **Implementation feasibility**: Assess technical feasibility, complexity, risk.

4. **Risk level assessment**
   - Independently assess risk level (0-3) per DESIGN_GOVERNANCE.md.
   - Record agreement/disagreement with Design Agent's assessment.

5. **Traceability completeness**
   - Confirm all requirements covered or explicitly gapped.
   - No orphan design elements without requirement trace.

6. **Learning completeness**
   - Confirm durable discoveries were classified and persisted per
     `docs/engineering/LEARNING_POLICY.md`, in the correct authoritative artifact.

## Verdicts

- `DESIGN_REVIEW_APPROVED` — no blockers; gates pass; provenance verified; risk level agreed.
- `DESIGN_REVIEW_CHANGES_REQUIRED` — changes needed. Set `CORRECTION_REQUIRED: YES` unless finding is genuine `HUMAN_DECISION_REQUIRED`.
- `DESIGN_REVIEW_HUMAN_DECISION_REQUIRED` — Level 2/3 risk requiring human approval. Set `HUMAN_DECISION_REQUIRED: YES` and `HUMAN_DECISION_TYPE: DESIGN`.

For a Design Brief review, restrict scope to completeness, feasibility, traceability, and risk assessment.
For a Design Revision review, include all above plus design system/UX/IA/feasibility gates.