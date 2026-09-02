---
name: repository-learning
description: Procedure for classifying and persisting durable discoveries in this framework — assign exactly one learning category, prefer executable knowledge, distinguish product-specific from reusable framework findings, and respect human-review/governance authority levels. Use at the end of implementation, review, or correction.
---

# Repository learning

Use this skill to decide what to persist and where, per `docs/engineering/LEARNING_POLICY.md`.
Persist only evidence-backed findings; never invent facts.

## Classify (exactly one category)

- `EPHEMERAL` — no lasting value; do not persist.
- `PROJECT_FACT` — stable verified fact about a product/repo; persist in that repo's knowledge.
- `RUNTIME_DISCOVERY` — verified runtime/environment fact; persist in that repo's runtime knowledge.
- `ARCHITECTURE_DISCOVERY` — affects architecture; may need an ADR + human decision.
- `DESIGN_DISCOVERY` — affects UI/design or the Design Contract.
- `WORKFLOW_IMPROVEMENT` — improves the reusable workflow/framework itself.
- `AUTOMATION_OPPORTUNITY` — a manual step that should become a script/CI job.
- `CONTRADICTION` — conflicts with documented knowledge/policy; surface and reconcile, never overwrite.

## Prefer executable knowledge

Where appropriate, persist as a test, script, configuration, or command rather than prose — it is
self-verifying and harder to let rot.

## Product-specific vs. reusable

- **Product-specific** findings update the product repository's knowledge and may be persisted
  automatically when evidence-backed (`PROJECT_FACT`, `RUNTIME_DISCOVERY`).
- **Generally reusable** findings become **framework improvement candidates**.

## Authority levels (do not exceed your authority)

- Automatic: verified `PROJECT_FACT` / `RUNTIME_DISCOVERY` and similar operational knowledge.
- Independent review: `WORKFLOW_IMPROVEMENT`, `AUTOMATION_OPPORTUNITY`, other reusable workflow changes.
- Human decision: `ARCHITECTURE_DISCOVERY` and consequential governance/architecture; `CONTRADICTION`
  touching governance/architecture escalates here.

A production-writing or review lane should **report** classified discoveries in its structured result
and only persist within its authority; higher-authority items are handed to the Manager, who routes
them to independent review or a human gate. Do not make unrelated governance changes as a side effect.
