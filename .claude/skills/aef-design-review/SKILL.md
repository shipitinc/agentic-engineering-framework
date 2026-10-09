---
name: aef-design-review
description: Read-only independent design review checklist for this framework — verify exact-revision provenance, inspect complete design artifacts, verify traceability, assess design system compliance, UX/accessibility, IA integrity, and implementation feasibility, and classify every finding by blast radius (REACHES_IMPLEMENTATION | EVIDENCE_HYGIENE). Use when reviewing Design Briefs or Design Revisions.
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
   - Where the artifact cites `file:line` references or publishes commands, run the read-only
     `framework check-citations` drift check where available and weigh its output: the checker
     detects drift *symptoms* (e.g. `CITATION_DRIFT`, `CITATION_UNVERIFIED`) — it does not
     classify them. Blast-radius classification stays the reviewer's position-based judgement
     (step 6). An indeterminate or unreadable citation is recorded as an **open
     `EVIDENCE_HYGIENE` finding — never a pass**.

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

6. **Finding disposition — classify by reach, not by symptom**
   - Assign every finding a `blast_radius` per DESIGN_GOVERNANCE.md § Finding Classification by
     Blast Radius. The discriminator is one question: *can this finding change what the
     implementation does?*
   - `REACHES_IMPLEMENTATION` → always blocking. A normative rule the code contradicts; a MUST-add
     snippet that does not compile; an ownership file list that breaks path-ownership serialisation;
     a privacy/disclosure boundary; a state or ownership transition.
   - `EVIDENCE_HYGIENE` → non-blocking by default in a pre-implementation artifact. A stale
     `file:line` range, a stale count, a table preamble that misdescribes its own table, a
     non-reproducing published command, or a register that disagrees with itself in a non-normative
     position.
   - Judge by **position**, not by surface form: a "register that disagrees with itself" is hygiene
     when it is a count table and `REACHES_IMPLEMENTATION` when it is a traceability row asserting
     which requirement a normative rule serves. Classifying by symptom is taxonomy gaming.
   - Never drop a finding silently. A hygiene finding is recorded in `NON_BLOCKING_FINDINGS` and
     remains **required before Gate D5** (Design Contract Freeze); "non-blocking" governs the gate
     between the revision and its freeze, never the freeze.
   - Give each hygiene finding a stable `finding_id` and carry it forward **verbatim** into every
     later `DESIGN_REVIEW` of the same `revision_id`, recording `resolution: CORRECTED` with a
     `resolution_ref` once it is fixed. A `finding_id` you do not mention stays **open** — never let
     absence stand for closure. The Manager determines "still open" from `resolution`, not from
     absence, per DESIGN_GOVERNANCE.md Gate D5.
   - **Per-artifact cap**: a revision gets at most one full review pass plus one correction pass
     (DESIGN_GOVERNANCE.md § Per-artifact review cap). A post-correction re-review reports
     **regressions only**; anything else routes by blast radius — `EVIDENCE_HYGIENE` onto the Gate
     D5 open set, `REACHES_IMPLEMENTATION` to a Design Contract Revision. Boundless re-review of
     the same revision is out of scope.

7. **Learning completeness**
   - Confirm durable discoveries were classified and persisted per
     `docs/engineering/LEARNING_POLICY.md`, in the correct authoritative artifact.

## Verdicts

- `DESIGN_REVIEW_APPROVED` — no blockers; gates pass; provenance verified; risk level agreed.
- `DESIGN_REVIEW_APPROVED_WITH_NON_BLOCKING_FINDINGS` — no `REACHES_IMPLEMENTATION` finding is open, and one or more `EVIDENCE_HYGIENE` findings are recorded in `NON_BLOCKING_FINDINGS`, each carrying its `finding_id` and `resolution`. Set `CORRECTION_REQUIRED: NO` and `HUMAN_DECISION_REQUIRED: NO`; the recorded findings are carried to Gate D5 as the open set, where they must be corrected before the freeze.
- `DESIGN_REVIEW_CHANGES_REQUIRED` — changes needed. Set `CORRECTION_REQUIRED: YES` unless finding is genuine `HUMAN_DECISION_REQUIRED`.
- `DESIGN_REVIEW_HUMAN_DECISION_REQUIRED` — Level 2/3 risk requiring human approval. Set `HUMAN_DECISION_REQUIRED: YES` and `HUMAN_DECISION_TYPE: DESIGN`.

For a Design Brief review, restrict scope to completeness, feasibility, traceability, and risk assessment.
For a Design Revision review, include all above plus design system/UX/IA/feasibility gates.