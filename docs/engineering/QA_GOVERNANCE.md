# QA_GOVERNANCE.md — QA Governance Policy

This document defines the governance framework for quality assurance activities within the agentic
engineering lifecycle. It establishes roles, artifacts, processes, and gates that ensure QA rigor,
evidence-based decisions, and proper separation of concerns between QA definition, execution, and
implementation.

---

## Roles

### QA Architect
- **Authority**: Defines QA strategy, QA Contracts, golden baselines, and evidence standards.
- **Responsibilities**:
  - Produce the **QA Contract** in parallel with the Design Contract (required before implementation completion).
  - Define acceptance criteria, test strategy, automated/visual/human QA scope.
  - Establish and maintain **visual golden baselines** for visual regression testing.
  - Define evidence standards: what constitutes valid deterministic evidence, how evidence is pinned to revisions.
  - Approve rebaselining of golden baselines (implementation agents **cannot** approve changed baselines).
  - Classify QA failures and route to appropriate remediation lane.
- **Constraints**:
  - Does not execute QA tests (that is QA Executor).
  - Does not implement production code.
  - Must declare `OWNED_PATHS` (QA Contracts, golden baselines, QA configs), `READ_ONLY_PATHS` (requirements, design contract, implementation code), `PROHIBITED_PATHS` (implementation source, deployment configs).

### QA Executor
- **Authority**: Executes automated, visual, and human QA per QA Contract; produces QA Results.
- **Responsibilities**:
  - Run automated test suites (unit, integration, contract, e2e) per QA Contract.
  - Execute visual regression against golden baselines.
  - Coordinate and document human QA sessions (exploratory, usability, accessibility).
  - Preserve **all QA artifacts as evidence** (test reports, screenshots, videos, logs, traces).
  - Classify each failure per the QA Failure Classification taxonomy.
  - Produce machine-readable QA Results for the Engineering Manager.
- **Constraints**:
  - **Read-only with respect to production code and golden baselines** — never modifies implementation or approves baseline changes.
  - Does not define QA strategy or contracts.
  - Must declare `READ_ONLY_PATHS` (implementation, QA Contract, golden baselines), `OWNED_PATHS` (QA Result artifacts, test outputs), `PROHIBITED_PATHS` (implementation source, design artifacts, deployment configs).

---

## Artifacts

### QA Contract
**Purpose**: Defines the complete QA strategy and acceptance criteria for a feature/change. Required
**before implementation completion** (defined in parallel with Design Contract).

**Lifecycle**: Created → Reviewed → Approved → Frozen (triggers Implementation QA readiness).

**Required Fields**:
- `contract_id`: UUID
- `design_contract_ref`: UUID (references Design Contract)
- `version`: semver
- `status`: `DRAFT` | `UNDER_REVIEW` | `APPROVED` | `FROZEN` | `SUPERSEDED`
- `acceptance_criteria`: array of testable conditions (traceable to requirements/design)
- `test_strategy`:
  - `unit`: scope, coverage targets, tools
  - `integration`: scope, service boundaries, tools
  - `contract`: consumer-driven contracts, schema validation
  - `e2e`: critical user flows, environments, tools
  - `visual`: pages/components, baseline references, tolerance thresholds
  - `human`: exploratory charters, usability tasks, accessibility standards (WCAG level)
- `evidence_standards`:
  - `deterministic_evidence_required`: boolean
  - `revision_pinning_required`: boolean (evidence must correspond to exact code revision)
  - `artifact_retention_policy`: duration and storage location
- `golden_baselines`: array of baseline IDs with source revision and approval status
- `regression_test_requirements`: new regressions must add regression tests before re-verification
- `gate_criteria`: pass/fail thresholds per test category
- `created_by`: agent ID (QA Architect)
- `created_at`: ISO8601 timestamp
- `reviewed_by`: reviewer ID
- `reviewed_at`: ISO8601 timestamp
- `approved_by`: human ID (when required)
- `approved_at`: ISO8601 timestamp

### QA Result
**Purpose**: Machine-readable record of QA execution outcome with evidence and failure classification.

**Lifecycle**: Created per QA execution (automated, visual, human) → Archived as evidence.

**Required Fields** (`qa-result.yaml`):
```yaml
result_id: UUID
contract_id: UUID (references QA Contract)
execution_type: AUTOMATED | VISUAL | HUMAN | COMBINED
target_revision: string (git SHA)
target_environment: string (QA, STAGING, PRODUCTION)
status: PASS | FAIL | PARTIAL | BLOCKED
executed_by: agent ID (QA Executor)
executed_at: ISO8601 timestamp
duration_seconds: integer
summary:
  total_tests: integer
  passed: integer
  failed: integer
  skipped: integer
  flaky: integer
evidence:
  test_reports: array of paths/URLs
  screenshots: array of paths/URLs
  videos: array of paths/URLs
  logs: array of paths/URLs
  traces: array of paths/URLs
failures:
  - failure_id: UUID
    classification: IMPLEMENTATION_DEFECT | DESIGN_DEFECT | REQUIREMENT_GAP | ENVIRONMENT_DEFECT
    severity: CRITICAL | HIGH | MEDIUM | LOW
    description: string
    evidence_refs: array of evidence IDs
    suggested_remediation_lane: CORRECTION | DCR | REQUIREMENTS_CLARIFICATION | INFRA_REMEDIATION
    regression_test_added: boolean
    regression_test_ref: string (if added)
golden_baseline_changes:
  - baseline_id: UUID
    change_type: NEW | UPDATED | REMOVED
    approved_by: QA_ARCHITECT | HUMAN_QA
    approval_ref: string
gate_results:
  unit: PASS | FAIL | N/A
  integration: PASS | FAIL | N/A
  contract: PASS | FAIL | N/A
  e2e: PASS | FAIL | N/A
  visual: PASS | FAIL | N/A
  human: PASS | FAIL | N/A
overall_verdict: READY_FOR_MERGE | BLOCKED | HUMAN_DECISION_REQUIRED
```

---

## QA Execution Types

### Automated QA
- **Scope**: Unit, integration, contract, e2e tests defined in QA Contract.
- **Execution**: QA Executor runs in CI/CD pipeline or locally per QA Contract.
- **Evidence**: Test reports (JUnit, JSON), coverage reports, logs — all pinned to target revision.
- **Gate**: All required automated tests must pass (`PASS`) for `READY_FOR_MERGE`.
- **Deterministic Evidence Authority**: Test results are **authoritative over reviewer opinion**.
  A passing test suite cannot be overridden by a reviewer's subjective assessment.

### Visual QA
- **Scope**: Visual regression of pages/components against golden baselines.
- **Execution**: QA Executor runs perceptual/pixel diff tools per QA Contract thresholds.
- **Golden Baselines**:
  - Established by QA Architect, approved by Human QA or QA Architect.
  - **Implementation agents cannot approve changed golden baselines** — only QA Architect or Human QA.
  - Baseline changes require explicit approval recorded in QA Result.
- **Evidence**: Screenshots, diff images, perceptual scores — pinned to target revision.
- **Gate**: Visual regressions classified as failures; require classification and remediation.

### Human QA
- **Scope**: Exploratory testing, usability evaluation, accessibility audit per QA Contract.
- **Execution**: Human testers (or AI-assisted) following charters; QA Executor coordinates and documents.
- **Evidence**: Session notes, screen recordings, annotated screenshots, accessibility reports — pinned to target revision.
- **Gate**: Required when QA Contract specifies `human: REQUIRED` or when automated/visual QA cannot cover critical usability/accessibility criteria.
- **Trigger**: `HUMAN_DECISION_REQUIRED` for Human QA initiation; results feed into QA Verdict.

---

## QA Failure Classification

Every QA failure **must** be classified as exactly one of:

| Classification | Definition | Remediation Lane |
|----------------|------------|------------------|
| `IMPLEMENTATION_DEFECT` | Code does not meet Design Contract or QA Contract acceptance criteria. | Correction Lane (Implementation) |
| `DESIGN_DEFECT` | Design Contract itself has a flaw (usability, accessibility, IA) that implementation correctly followed. | DCR Process (Design Governance) |
| `REQUIREMENT_GAP` | Requirements are ambiguous, incomplete, or contradictory; neither design nor implementation can resolve. | Requirements Clarification (Human Gate) |
| `ENVIRONMENT_DEFECT` | Failure caused by test environment, infrastructure, data, or configuration not under code control. | Infrastructure/Environment Remediation |

**Rules**:
- Classification is performed by QA Executor, reviewed by QA Architect.
- Misclassification is a process failure — requires retrospective.
- `IMPLEMENTATION_DEFECT` → routes to Correction / Re-review loop (WORKFLOW.md steps 22-23).
- `DESIGN_DEFECT` → routes to DCR (DESIGN_GOVERNANCE.md).
- `REQUIREMENT_GAP` → routes to Human Decision (HUMAN_DECISIONS.md).
- `ENVIRONMENT_DEFECT` → routes to Infra/DevOps remediation.

---

## Regression Policy

- **Every regression must have a regression test** added before re-verification.
- Regression test must be traceable to the original failure (`failure_id`).
- Regression test becomes part of the QA Contract for future runs.
- QA Result must record `regression_test_added: true` and `regression_test_ref`.

---

## Golden Baseline Governance

1. **Creation**: QA Architect creates baseline from a known-good revision; Human QA or QA Architect approves.
2. **Storage**: Baselines stored in versioned artifact store (not git LFS unless project policy).
3. **Comparison**: QA Executor compares current render against baseline using configured tool.
4. **Drift Detection**: Any diff exceeding threshold = visual regression failure.
5. **Rebaselining**:
   - Only QA Architect or Human QA can approve a new baseline.
   - Implementation agents **never** approve baseline changes.
   - Rebaselining requires explicit `golden_baseline_changes` entry in QA Result with approval reference.
6. **History**: All baseline versions retained for audit and rollback comparison.

---

## Process Gates

### Gate Q1: QA Contract Review
- **Trigger**: QA Contract created by QA Architect (parallel with Design Contract).
- **Reviewer**: Engineering Manager + Independent Engineering Reviewer (read-only).
- **Criteria**: Completeness, traceability to Design Contract/requirements, feasible test strategy, clear evidence standards.
- **Output**: `APPROVED` → freeze QA Contract; `CHANGES_REQUIRED` → QA Architect revises.

### Gate Q2: QA Contract Freeze (Pre-Implementation Completion)
- **Trigger**: QA Contract passes Gate Q1.
- **Constraint**: **Required before implementation reports `IMPLEMENTED`**.
- **Action**: Manager freezes QA Contract, records provenance.
- **Output**: `QA_CONTRACT_FROZEN` — implementation can now complete with known QA targets.

### Gate Q3: Automated QA Execution
- **Trigger**: Post-integration deployment to QA environment.
- **Executor**: QA Executor.
- **Criteria**: All required automated tests pass per QA Contract gate criteria.
- **Output**: QA Result with `overall_verdict`.

### Gate Q4: Visual QA Execution
- **Trigger**: Post-integration (can run parallel with Automated QA).
- **Executor**: QA Executor.
- **Criteria**: No visual regressions exceeding thresholds; or all regressions classified and approved for rebaseline.
- **Output**: QA Result with `visual` gate result.

### Gate Q5: Human QA Execution (when required)
- **Trigger**: QA Contract specifies `human: REQUIRED` or automated/visual gaps identified.
- **Authority**: Human QA initiation via structured question UI.
- **Executor**: Human testers coordinated by QA Executor.
- **Output**: QA Result with `human` gate result.

### Gate Q6: QA Verdict & Classification
- **Trigger**: All applicable QA executions complete.
- **Authority**: QA Architect reviews QA Results, classifies failures.
- **Criteria**: All failures classified; regression tests added for `IMPLEMENTATION_DEFECT`/`DESIGN_DEFECT`; remediation lanes assigned.
- **Output**: `READY_FOR_MERGE` | `BLOCKED` (with classified failures) | `HUMAN_DECISION_REQUIRED`.

---

## Invariants

1. **QA Architect ≠ QA Executor** — separate agents, no overlap.
2. **QA Contract required before implementation completion** — no implementation can claim `IMPLEMENTED` without a frozen QA Contract.
3. **Deterministic evidence is authoritative over reviewer opinion** — passing tests cannot be vetoed by subjective review.
4. **Implementation agents cannot approve changed visual golden baselines** — only QA Architect or Human QA.
5. **QA artifacts must be preserved as evidence** — pinned to exact revision, retained per policy.
6. **Regressions require regression tests** — no re-verification without test.
7. **Every failure classified exactly once** — `IMPLEMENTATION_DEFECT`, `DESIGN_DEFECT`, `REQUIREMENT_GAP`, `ENVIRONMENT_DEFECT`.
8. **QA Executor is read-only wrt production code and baselines** — never modifies implementation or approves baselines.
9. **Only Engineering Manager advances lifecycle state** — QA agents produce results; Manager consumes and transitions.

---

## Structured Results

QA Architect and QA Executor must emit machine-readable structured results per
[STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md).

### QA Architect Result Contract (QA Contract Creation)
```json
{
  "result_type": "QA_CONTRACT",
  "status": "CREATED" | "FROZEN",
  "provenance": { "agent_id": "", "contract_id": "", "design_contract_ref": "", "head_sha": "" },
  "payload": { "contract": {}, "artifact_path": "" },
  "evidence": { "traceability_matrix": {} },
  "blockers": [],
  "next_actions": ["QA_CONTRACT_REVIEW", "QA_CONTRACT_FREEZE"]
}
```

### QA Executor Result Contract (QA Execution)
```json
{
  "result_type": "QA_RESULT",
  "status": "PASS" | "FAIL" | "PARTIAL" | "BLOCKED",
  "provenance": { "executor_id": "", "contract_id": "", "target_revision": "", "environment": "" },
  "payload": { "summary": {}, "failures": [], "golden_baseline_changes": [] },
  "evidence": { "test_reports": [], "screenshots": [], "videos": [], "logs": [] },
  "blockers": [],
  "next_actions": ["CLASSIFY_FAILURES", "REGRESSION_TESTS", "REMEDIATION_ROUTING"]
}
```

---

## Cross-References

- [WORKFLOW.md](WORKFLOW.md) — Lifecycle stages 19, 24-29
- [DESIGN_GOVERNANCE.md](DESIGN_GOVERNANCE.md) — Design Contract defines what QA validates; Design Defects route to DCR
- [AGENTS.md](../../AGENTS.md) — Repository-wide invariants
- [HUMAN_DECISIONS.md](HUMAN_DECISIONS.md) — Human QA initiation, Requirement Gap resolution
- [DEPLOYMENT_GOVERNANCE.md](DEPLOYMENT_GOVERNANCE.md) — QA gates must pass before Staging/Production
- [STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md) — Machine-readable result contracts
- [LEARNING_POLICY.md](LEARNING_POLICY.md) — `QA_DISCOVERY` classification

---

## Templates

- [QA Contract Template](../../framework/templates/qa-contract.template.md)
- [QA Result Template](../../framework/templates/qa-result.template.yaml)