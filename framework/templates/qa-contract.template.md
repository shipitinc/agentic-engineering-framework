# QA Contract — {{contract_id}}

<!--
  TEMPLATE: QA Contract
  Created by QA Architect per QA_GOVERNANCE.md
  Required BEFORE implementation completion (parallel with Design Contract).
  Status lifecycle: DRAFT → UNDER_REVIEW → APPROVED → FROZEN → SUPERSEDED
-->

## Metadata

| Field | Value |
|-------|-------|
| `contract_id` | {{contract_id}} |
| `design_contract_ref` | {{design_contract_ref}} |
| `version` | {{version}} (semver) |
| `status` | {{status}} |
| `created_by` | {{agent_id}} (QA Architect) |
| `created_at` | {{created_at}} (ISO8601) |
| `reviewed_by` | {{reviewed_by}} |
| `reviewed_at` | {{reviewed_at}} (ISO8601) |
| `approved_by` | {{approved_by}} |
| `approved_at` | {{approved_at}} (ISO8601) |

## Acceptance Criteria

{{#each acceptance_criteria}}
### AC-{{id}}: {{title}}
- **Description**: {{description}}
- **Traceability**: Requirements: {{requirements_refs}}, Design: {{design_refs}}
- **Test Method**: {{test_method}} (AUTOMATED \| VISUAL \| HUMAN \| COMBINED)
- **Pass Criteria**: {{pass_criteria}}
{{/each}}

## Test Strategy

### Unit Tests
- **Scope**: {{unit_scope}}
- **Coverage Target**: {{unit_coverage}}%
- **Tools**: {{unit_tools}}
- **Required**: {{unit_required}}

### Integration Tests
- **Scope**: {{integration_scope}}
- **Service Boundaries**: {{service_boundaries}}
- **Tools**: {{integration_tools}}
- **Required**: {{integration_required}}

### Contract Tests
- **Scope**: {{contract_scope}}
- **Consumer-Driven Contracts**: {{consumer_contracts}}
- **Schema Validation**: {{schema_validation}}
- **Tools**: {{contract_tools}}
- **Required**: {{contract_required}}

### End-to-End Tests
- **Critical User Flows**: {{e2e_flows}}
- **Environments**: {{e2e_environments}}
- **Tools**: {{e2e_tools}}
- **Required**: {{e2e_required}}
- **Evidence Rows**: Each journey is declared as an `E_*` evidence row below with
  `artifact_ref`, `params`, and `prerequisites`. A row whose lane does not exist
  (no CI device job, no headless device) is either made runnable or formally
  determined per its contract determination — never silently asserted.

### Visual Tests
- **Pages/Components**: {{visual_components}}
- **Baseline References**: {{baseline_refs}}
- **Tolerance Thresholds**: {{visual_thresholds}}
- **Tools**: {{visual_tools}}
- **Required**: {{visual_required}}

### Human QA
- **Exploratory Charters**: {{exploratory_charters}}
- **Usability Tasks**: {{usability_tasks}}
- **Accessibility Standards**: {{accessibility_standards}} (WCAG {{wcag_level}})
- **Required**: {{human_required}} (REQUIRED \| OPTIONAL \| NOT_APPLICABLE)

## Evidence Standards

- **Deterministic Evidence Required**: {{deterministic_evidence_required}}
- **Revision Pinning Required**: {{revision_pinning_required}} (evidence must correspond to exact code revision)
- **Artifact Retention Policy**: {{artifact_retention_policy}} (duration, storage location)

## Evidence Rows

Each `E_*` row binds a contract-mandated evidence requirement to the
**feature-specific artifact(s)** and run prerequisites that will satisfy it —
declared by the QA Architect at contract time, never improvised after freeze.
The QA Result reports each row's determination against these declarations.

{{#each evidence_rows}}
### E-{{id}}: {{title}}
- **Required**: {{required}} (REQUIRED \| OPTIONAL \| NOT_APPLICABLE)
- **Test Method**: {{test_method}} (AUTOMATED \| VISUAL \| HUMAN \| COMBINED)
- **Artifact Ref**: {{artifact_ref}} (feature-specific file/URL satisfying this row)
- **Run Params**: {{params}} (e.g. `--dart-define=E2E_VERIFICATION_CODE`, target device, env vars)
- **Prerequisites**: {{prerequisites}} (lane/services/devices required to run; e.g. a CI device job or headless device)
- **Traceability**: {{traceability_refs}} (requirements/design refs evidenced)
- **Contract Determination**: {{determination}} (EXPECTED_TO_EXECUTE \| CONTINGENT \| SKIPPED_BY_CONTRACT)
- **Determination Reasons**: {{determination_reasons}} (mandatory unless EXPECTED_TO_EXECUTE)
{{/each}}

> A `REQUIRED` row must reach `EXECUTED` or a formal `SKIPPED`. An `OPTIONAL` /
> `NOT_IN_DEFAULT_PIPELINE` row may rest at `READY_NOT_EXECUTED` without a
> decision. Nothing here is silently asserted — see QA_GOVERNANCE.md
> "Evidence Rows & Determinations".

## Golden Baselines

{{#each golden_baselines}}
- **Baseline ID**: {{baseline_id}}
- **Source Revision**: {{source_revision}}
- **Component/Page**: {{component}}
- **Approval Status**: {{approval_status}} (PENDING \| APPROVED_QA_ARCHITECT \| APPROVED_HUMAN_QA)
- **Approved By**: {{approved_by}}
- **Approved At**: {{approved_at}}
{{/each}}

## Regression Test Requirements

- **New Regressions Must Add Regression Tests**: {{regression_tests_required}}
- **Regression Test Traceability**: Each regression test must reference original `failure_id`

## Gate Criteria

| Gate | Pass Threshold |
|------|----------------|
| Unit | {{unit_gate}} |
| Integration | {{integration_gate}} |
| Contract | {{contract_gate}} |
| E2E | {{e2e_gate}} |
| Visual | {{visual_gate}} |
| Human | {{human_gate}} |

**Gate determination semantics**: each `E_*` evidence row resolves to
`EXECUTED` (evidence at the pinned revision) or a formal `SKIPPED`
(`reasons` + `authority_ref`); `READY_NOT_EXECUTED` is interim only and never a
resting state for a `REQUIRED` row. Gates report `PASS | FAIL | N/A |
NOT_EXECUTED | SKIPPED` in the QA Result.

---

## Review & Freeze

**Gate Q1**: QA Contract Review (completeness, traceability, feasible strategy, clear evidence standards)
**Gate Q2**: QA Contract Freeze — Required before implementation reports `IMPLEMENTED`

**Next Gate**: Implementation (with frozen QA Contract as target)