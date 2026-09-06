# DESIGN_GOVERNANCE.md — Design Governance Policy

This document defines the governance framework for design activities within the agentic engineering
lifecycle. It establishes roles, artifacts, processes, and gates that ensure design quality,
traceability, and proper separation of concerns between design and implementation.

---

## Roles

### Design Agent
- **Authority**: Produces Design Briefs, Design Revisions, and Design Contracts.
- **Responsibilities**:
  - Translate requirements and architecture constraints into design artifacts.
  - Produce Design Revisions iteratively with explicit versioning and metadata.
  - Assess design-change risk levels for each revision.
  - Respond to Design Reviewer findings and DCR feedback.
  - Maintain traceability from requirements → Design Brief → Design Revisions → Design Contract.
- **Constraints**:
  - Does not implement production code.
  - Does not approve own work — requires Independent Design Review.
  - Must declare `OWNED_PATHS` (design artifacts), `READ_ONLY_PATHS` (requirements, architecture, design system), `PROHIBITED_PATHS` (implementation code, QA artifacts, deployment configs).

### Independent Design Reviewer
- **Authority**: Read-only evaluation of Design Briefs and Design Revisions.
- **Responsibilities**:
  - Verify completeness, consistency, feasibility, and alignment with requirements/architecture.
  - Assess design system consistency, UX coherence, accessibility, information architecture integrity.
  - Classify design-change risk levels independently.
  - Challenge Design Agent claims with evidence.
- **Constraints**:
  - **Read-only with respect to design artifacts** — never edits, commits, or pushes design files.
  - Does not produce designs — only reviews.
  - Must declare `READ_ONLY_PATHS` (all design artifacts, requirements, architecture), `PROHIBITED_PATHS` (implementation, QA, deployment).

---

## Artifacts

### Design Brief
**Purpose**: Captures the problem statement, user flows, success criteria, constraints, acceptance
criteria, and risk assessment before design exploration begins.

**Lifecycle**: Created → Reviewed → Human-Approved → Frozen (triggers Design Exploration).

**Required Fields**:
- `brief_id`: UUID
- `version`: semver (major.minor.patch)
- `status`: `DRAFT` | `UNDER_REVIEW` | `APPROVED` | `SUPERSEDED`
- `requirements_refs`: array of requirement IDs
- `architecture_refs`: array of ADR IDs
- `problem_statement`: string
- `user_flows`: array of flow descriptions with entry/exit criteria
- `success_criteria`: measurable outcomes
- `constraints`: technical, brand, regulatory, accessibility
- `acceptance_criteria`: testable conditions for design completion
- `risk_assessment`: initial risk level (0-3) and rationale
- `created_by`: agent ID
- `created_at`: ISO8601 timestamp
- `approved_by`: human ID (when approved)
- `approved_at`: ISO8601 timestamp

### Design Revision
**Purpose**: A versioned candidate design produced during exploration. Each revision is a complete,
reviewable design artifact with explicit metadata.

**Lifecycle**: Created → Independent Review → DCR Process (if needed) → Approved → Becomes Design Contract.

**Required Metadata** (`design-revision-metadata.yaml`):
```yaml
revision_id: UUID
brief_id: UUID (references Design Brief)
revision_number: integer (1, 2, 3...)
status: DRAFT | UNDER_REVIEW | APPROVED | REJECTED | SUPERSEDED
risk_level: 0 | 1 | 2 | 3
risk_rationale: string
changelog: array of changes from previous revision
traceability:
  requirements_covered: array of requirement IDs
  requirements_gaps: array of requirement IDs not yet addressed
design_system_compliance: PASS | PARTIAL | FAIL
ux_accessibility_score: PASS | PARTIAL | FAIL
implementation_feasibility: HIGH | MEDIUM | LOW | UNKNOWN
created_by: agent ID
created_at: ISO8601 timestamp
reviewed_by: reviewer ID (when reviewed)
reviewed_at: ISO8601 timestamp
approved_by: human ID (when approved, for Level 2+)
approved_at: ISO8601 timestamp
```

**Design-Change Risk Levels**:

| Level | Name | Description | Approval Path |
|-------|------|-------------|---------------|
| 0 | Implementation Correction | Minor visual/code detail that does not affect user flow, design system, or IA. Can be resolved in implementation without design revision. | `AUTO` — routed to implementation lane as implementation detail |
| 1 | Design-System Correction | Inconsistency with established design system (tokens, components, patterns). Requires design system owner notification. | `AUTO` with design-system owner notification; no human gate unless design system owner objects |
| 2 | Feature UX Change | Change to user flow, interaction pattern, or feature-level UX that affects user behavior. | `HUMAN_DECISION_REQUIRED` — product/design approval required |
| 3 | Major Workflow/Navigation/IA Change | Change to core workflow, navigation structure, or information architecture affecting multiple features or user mental models. | `HUMAN_DECISION_REQUIRED` — product/design/architecture approval required |

### Design Change Request (DCR)
**Purpose**: Formal process for proposing, evaluating, and approving changes to an approved Design
Revision or Design Contract.

**Lifecycle**: Created → Classified (Risk Level) → Reviewed → Approved/Rejected → Applied.

**Required Fields**:
- `dcr_id`: UUID
- `target_revision_id`: UUID (the Design Revision or Contract being changed)
- `initiator`: agent ID or human ID
- `initiated_at`: ISO8601 timestamp
- `change_description`: string
- `change_rationale`: string
- `risk_level`: 0 | 1 | 2 | 3 (assessed by initiator, verified by reviewer)
- `affected_artifacts`: array of artifact paths/IDs
- `implementation_impact`: NONE | LOW | MEDIUM | HIGH | UNKNOWN
- `status`: `OPEN` | `UNDER_REVIEW` | `APPROVED` | `REJECTED` | `APPLIED` | `SUPERSEDED`
- `reviewed_by`: reviewer ID
- `reviewed_at`: ISO8601 timestamp
- `approved_by`: human ID (for Level 2+)
- `approved_at`: ISO8601 timestamp
- `resolution_notes`: string

### Approved Design Revision / Design Contract
**Purpose**: The frozen, versioned design artifact that implementation must satisfy. Created when a
Design Revision passes all gates (Independent Design Review + Human Approval for Level 2+).

**Properties**:
- Immutable once frozen.
- Versioned with `contract_id`, `source_revision_id`, `frozen_at`, `frozen_by`.
- Serves as the acceptance baseline for implementation and QA.
- Substantial UI changes **require** an approved Design Revision — implementers must not invent
  consequential UX to fill design gaps.
- Implementation-discovered UI gaps route back into the design lifecycle via DCR.

---

## Process Gates

### Gate D1: Design Brief Review
- **Trigger**: Design Brief created by Design Agent.
- **Reviewer**: Independent Design Reviewer.
- **Criteria**: Completeness, traceability to requirements/architecture, feasible scope, clear acceptance criteria.
- **Output**: `APPROVED` → proceed to Design Exploration; `CHANGES_REQUIRED` → Design Agent revises.

### Gate D2: Human Design Brief Approval
- **Trigger**: Design Brief passes Gate D1.
- **Authority**: Human (product/design lead).
- **Criteria**: Strategic alignment, resource commitment, risk acceptance.
- **Output**: `APPROVED` → freeze Design Brief, begin Design Exploration.

### Gate D3: Independent Design Review (per Revision)
- **Trigger**: Design Revision submitted by Design Agent.
- **Reviewer**: Independent Design Reviewer.
- **Criteria**: Design system compliance, UX/accessibility, IA integrity, implementation feasibility, traceability.
- **Risk Assessment**: Reviewer independently assesses and records risk level.
- **Output**: `APPROVED` → proceed to DCR/Human Approval; `CHANGES_REQUIRED` → Design Agent revises.

### Gate D4: DCR / Human Approval (per Risk Level)
- **Level 0**: `AUTO` — no gate, routed to implementation.
- **Level 1**: `AUTO` with notification — design system owner informed; proceeds unless objection within 24h.
- **Level 2**: `HUMAN_DECISION_REQUIRED` — human product/design approval via structured question UI.
- **Level 3**: `HUMAN_DECISION_REQUIRED` — human product/design/architecture approval via structured question UI.

### Gate D5: Design Contract Freeze
- **Trigger**: Design Revision passes all applicable gates.
- **Action**: Manager freezes the revision as Design Contract, records provenance.
- **Output**: `DESIGN_CONTRACT_FROZEN` — triggers Implementation and QA Contract Definition.

---

## Invariants

1. **Design Agent ≠ Independent Design Reviewer** — separate agents, no overlap.
2. **Design Agent never approves own work** — every Design Revision requires Independent Design Review.
3. **Independent Design Reviewer is read-only** — never modifies design artifacts.
4. **Substantial UI changes require an approved Design Revision** — implementers must not invent consequential UX.
5. **Implementation-discovered UI gaps route back via DCR** — not resolved in implementation lane.
6. **Risk level classification is mandatory** for every Design Revision and DCR.
7. **Design Contract is immutable** once frozen — changes require new Design Revision + DCR.
8. **Traceability is mandatory** — every design element traces to requirements/architecture.
9. **Only the Engineering Manager advances lifecycle state** — Design Agent and Reviewer produce results; Manager consumes and transitions.

---

## Structured Results

Design Agent and Independent Design Reviewer must emit machine-readable structured results per
[STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md).

### Design Agent Result Contract
```json
{
  "result_type": "DESIGN_REVISION",
  "status": "COMPLETE" | "BLOCKED",
  "provenance": { "agent_id": "", "revision_id": "", "brief_id": "", "head_sha": "" },
  "payload": { "revision_metadata": {}, "artifact_paths": [] },
  "evidence": { "review_gates": [], "traceability_matrix": {} },
  "blockers": [],
  "next_actions": ["INDEPENDENT_DESIGN_REVIEW"]
}
```

### Independent Design Reviewer Result Contract
```json
{
  "result_type": "DESIGN_REVIEW",
  "status": "APPROVED" | "CHANGES_REQUIRED" | "HUMAN_DECISION_REQUIRED",
  "provenance": { "reviewer_id": "", "revision_id": "", "head_sha": "" },
  "payload": { "risk_level": 0, "findings": [], "traceability_gaps": [] },
  "evidence": { "gate_results": {} },
  "blockers": [],
  "next_actions": ["DCR_PROCESS" | "HUMAN_APPROVAL" | "DESIGN_CONTRACT_FREEZE"]
}
```

---

## Cross-References

- [WORKFLOW.md](WORKFLOW.md) — Lifecycle stages 12-19
- [AGENTS.md](../../AGENTS.md) — Repository-wide invariants
- [QA_GOVERNANCE.md](QA_GOVERNANCE.md) — QA Contract defined in parallel with Design Contract
- [HUMAN_DECISIONS.md](HUMAN_DECISIONS.md) — Human approval gates for Level 2/3 changes
- [STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md) — Machine-readable result contracts
- [LEARNING_POLICY.md](LEARNING_POLICY.md) — `DESIGN_DISCOVERY` classification

---

## Templates

- [Design Brief Template](../../framework/templates/design-brief.template.md)
- [Design Revision Metadata Template](../../framework/templates/design-revision-metadata.template.yaml)
- [Design Change Request Template](../../framework/templates/design-change-request.template.md)