---
name: qa-contract
description: Procedure for QA Contract creation and validation in this framework — declare ownership, define acceptance criteria, test strategy, evidence standards, golden baselines, and regression requirements. Use when creating or validating a QA Contract.
---

# QA Contract Workflow

Use this skill whenever you create or validate a QA Contract in a QA-strategy lane (QA Architect).
It encodes the non-negotiable discipline required by `AGENTS.md`, `docs/engineering/WORKFLOW.md`,
and `docs/engineering/QA_GOVERNANCE.md`.

## 1. Declare ownership before writing

Before editing anything, declare explicitly:

- `OWNED_PATHS` — the only paths you may create/modify (QA Contracts, golden baselines, QA configs, evidence standards).
- `READ_ONLY_PATHS` — paths you may read but must not change (requirements, Design Contract, architecture ADRs, implementation code for reference).
- `PROHIBITED_PATHS` — paths you must never touch (implementation source code, design artifacts, deployment configs, QA test code).

Ownership must not overlap with any concurrent writer. If it would overlap, stop and report it —
work must be serialized or re-partitioned (AGENTS.md concurrency invariant).

## 2. QA Contract discipline

- **Parallel with Design Contract**: QA Contract must be created in parallel with Design Contract, frozen before implementation completion.
- **Acceptance criteria traceability**: Every acceptance criterion traces to requirements/design.
- **Test strategy completeness**: Define scope, tools, coverage targets for unit, integration, contract, e2e, visual, human QA.
- **Evidence standards**: Define deterministic evidence requirements, revision pinning, artifact retention.
- **Golden baselines**: Define baseline components, source revisions, approval process (QA Architect or Human QA only).
- **Regression requirements**: New regressions must add regression tests before re-verification.
- **Gate criteria**: Explicit pass/fail thresholds per test category.

## 3. Report exact HEAD / provenance

Every result must include the branch/worktree, `BASE_SHA`, and `HEAD_SHA` you actually produced,
plus the concrete `CONTRACT_PATH`. Provenance must be verifiable.

## 4. No placeholder completion claims

- `RESULT: QA_CONTRACT_CREATED` / `QA_CONTRACT_FROZEN` means the work is genuinely done and gates pass.
- If not done or a required gate cannot pass, report `QA_CONTRACT_BLOCKED` with evidence — never a false green.
- Stubs/not-yet-defined behavior must be explicit and must not report success.

## 5. Human gates for consequential QA decisions

- Human QA initiation requires `HUMAN_DECISION_REQUIRED` (QA_GOVERNANCE.md Gate Q5).
- Stop and report as blocker — do not decide yourself.

## 6. Classify durable discoveries

Before finishing, apply the `repository-learning` skill to classify and persist durable findings.
New categories: `QA_DISCOVERY`, `DEPLOYMENT_DISCOVERY`, `HUMAN_DECISION_RECORD`.