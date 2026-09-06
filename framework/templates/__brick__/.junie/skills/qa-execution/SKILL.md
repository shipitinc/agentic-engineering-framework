---
name: qa-execution
description: Procedure for automated, visual, and human QA execution in this framework — run tests per QA Contract, produce evidence pinned to target revision, classify failures, preserve artifacts. Use when executing QA.
---

# QA Execution Workflow

Use this skill whenever you execute QA in an execution lane (QA Executor). It encodes the
non-negotiable discipline required by `AGENTS.md`, `docs/engineering/WORKFLOW.md`,
and `docs/engineering/QA_GOVERNANCE.md`.

## 1. Declare ownership before writing

Before editing anything, declare explicitly:

- `OWNED_PATHS` — the only paths you may create/modify (QA Result artifacts, test outputs, screenshots, videos, logs).
- `READ_ONLY_PATHS` — paths you may read but must not change (implementation code, QA Contract, golden baselines, Design Contract).
- `PROHIBITED_PATHS` — paths you must never touch (implementation source modifications, design artifacts, deployment configs, golden baseline approvals).

**You are read-only with respect to production code and golden baselines** — never modify implementation or approve baseline changes.

Ownership must not overlap with any concurrent writer. If it would overlap, stop and report it.

## 2. QA execution discipline

- **Revision pinning mandatory**: All evidence must correspond to the exact `target_revision` (git SHA) under test. Stale evidence is invalid.
- **Automated QA**: Run unit, integration, contract, e2e tests per QA Contract. Record exact commands and results.
- **Visual QA**: Run perceptual/pixel diff against golden baselines per QA Contract thresholds. Record diffs and scores.
- **Human QA**: Coordinate exploratory/usability/accessibility sessions per QA Contract charters. Document evidence.
- **Deterministic evidence authority**: Test results are authoritative over reviewer opinion. Passing tests cannot be vetoed.

## 3. Failure classification (mandatory, exactly one per failure)

| Classification | Definition | Remediation Lane |
|----------------|------------|------------------|
| `IMPLEMENTATION_DEFECT` | Code doesn't meet Design/QA Contract | Correction Lane |
| `DESIGN_DEFECT` | Design Contract flaw correctly implemented | DCR Process |
| `REQUIREMENT_GAP` | Requirements ambiguous/incomplete | Requirements Clarification (Human Gate) |
| `ENVIRONMENT_DEFECT` | Test env/infra/data/config issue | Infra Remediation |

- Classification performed by QA Executor, reviewed by QA Architect.
- Misclassification is a process failure.

## 4. Regression policy

- **Every regression must have a regression test** added before re-verification.
- Regression test traces to original `failure_id`.
- QA Result records `regression_test_added: true` and `regression_test_ref`.

## 5. Golden baseline governance

- **Implementation agents cannot approve changed baselines** — only QA Architect or Human QA.
- Baseline changes require explicit `golden_baseline_changes` entry in QA Result with approval reference.
- All baseline versions retained for audit and rollback comparison.

## 6. Evidence preservation

- All QA artifacts preserved as evidence: test reports, screenshots, videos, logs, traces.
- Pinned to exact `target_revision`.
- Retained per QA Contract artifact retention policy.

## 7. Report exact HEAD / provenance

Every result must include `target_revision`, branch, `BASE_SHA`, `HEAD_SHA`, execution type,
environment, and concrete evidence paths. Provenance verifiable by QA Architect and Manager.

## 8. No placeholder completion claims

- `RESULT: QA_RESULT_PASS` / `FAIL` / `PARTIAL` means execution genuinely complete with evidence.
- If blocked, report `QA_RESULT_BLOCKED` with evidence — never a false green.

## 9. Classify durable discoveries

Before finishing, apply the `repository-learning` skill to classify and persist durable findings.
Categories: `QA_DISCOVERY`, `DEPLOYMENT_DISCOVERY`, `HUMAN_DECISION_RECORD`.