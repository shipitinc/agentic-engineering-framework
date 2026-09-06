---
name: design-workflow
description: Procedure for design lifecycle in this framework — declare path ownership, produce Design Briefs and Revisions with risk assessment, maintain traceability, and never self-approve. Use when designing or revising a design artifact.
---

# Design Workflow

Use this skill whenever you produce or revise a design artifact in a design-writing lane (Design Agent).
It encodes the non-negotiable discipline required by `AGENTS.md`, `docs/engineering/WORKFLOW.md`,
and `docs/engineering/DESIGN_GOVERNANCE.md`.

## 1. Declare ownership before writing

Before editing anything, declare explicitly:

- `OWNED_PATHS` — the only paths you may create/modify (design artifacts: briefs, revisions, contracts, DCRs).
- `READ_ONLY_PATHS` — paths you may read but must not change (requirements, architecture ADRs, design system, QA Contracts).
- `PROHIBITED_PATHS` — paths you must never touch (implementation code, QA test code, deployment configs, golden baselines).

Ownership must not overlap with any concurrent writer. If it would overlap, stop and report it —
work must be serialized or re-partitioned (AGENTS.md concurrency invariant).

## 2. Design process discipline

- **Design Brief first**: Produce a Design Brief from requirements and architecture constraints before any design exploration.
- **Risk assessment mandatory**: Every Design Revision must include a risk level (0-3) with rationale per DESIGN_GOVERNANCE.md.
- **Traceability mandatory**: Every design element must trace to requirements/architecture. Record `requirements_covered` and `requirements_gaps`.
- **Version explicitly**: Each Design Revision gets a revision number, metadata file, and changelog from previous revision.
- **Design system compliance**: Verify against established design system (tokens, components, patterns).
- **UX/accessibility**: Assess against WCAG standards and usability heuristics.
- **Implementation feasibility**: Rate as HIGH/MEDIUM/LOW/UNKNOWN with rationale.

## 3. Report exact HEAD / provenance

Every result must include the branch/worktree, `BASE_SHA`, and `HEAD_SHA` you actually produced,
plus the concrete `ARTIFACT_PATHS`. Provenance must be verifiable by an independent reviewer.

## 4. No placeholder completion claims

- `RESULT: DESIGN_REVISION_COMPLETE` means the work is genuinely done and ready for independent review.
- If it is not done or a required gate cannot pass, report `RESULT: DESIGN_REVISION_BLOCKED` with evidence — never a false green.
- Stubs/not-yet-designed behavior must be explicit and must not report success or mutate state.

## 5. You never approve your own work

Hand a completed Design Revision to independent review. Set `READY_FOR_INDEPENDENT_DESIGN_REVIEW: YES`
only when the result is genuinely ready.

## 6. Human gates for consequential design decisions

- Level 2 (Feature UX Change) and Level 3 (Major Workflow/Navigation/IA Change) require `HUMAN_DECISION_REQUIRED`.
- Stop and report as blocker — do not decide yourself.
- The Engineering Manager will surface via structured question UI.

## 7. Classify durable discoveries

Before finishing, apply the `repository-learning` skill to classify and persist durable findings.
New categories: `DESIGN_DISCOVERY`, `QA_DISCOVERY`, `DEPLOYMENT_DISCOVERY`, `HUMAN_DECISION_RECORD`.