# Design Brief — {{brief_id}}

<!--
  TEMPLATE: Design Brief
  Instantiated by Design Agent per DESIGN_GOVERNANCE.md
  Required before Design Exploration begins.
  Status lifecycle: DRAFT → UNDER_REVIEW → APPROVED → SUPERSEDED
-->

## Metadata

| Field | Value |
|-------|-------|
| `brief_id` | {{brief_id}} |
| `version` | {{version}} (semver) |
| `status` | {{status}} |
| `created_by` | {{agent_id}} |
| `created_at` | {{created_at}} (ISO8601) |
| `approved_by` | {{approved_by}} |
| `approved_at` | {{approved_at}} (ISO8601) |

## Traceability

- **Requirements Refs**: {{requirements_refs}}
- **Architecture Refs (ADRs)**: {{architecture_refs}}

## Problem Statement

{{problem_statement}}

## User Flows

{{#each user_flows}}
### Flow: {{name}}
- **Entry Criteria**: {{entry_criteria}}
- **Steps**:
  {{#each steps}}
  - {{description}}
  {{/each}}
- **Exit Criteria**: {{exit_criteria}}
- **Success Metrics**: {{success_metrics}}
{{/each}}

## Success Criteria

{{#each success_criteria}}
- {{description}} (Measurable: {{metric}})
{{/each}}

## Constraints

| Category | Constraints |
|----------|-------------|
| Technical | {{technical_constraints}} |
| Brand | {{brand_constraints}} |
| Regulatory | {{regulatory_constraints}} |
| Accessibility | {{accessibility_constraints}} (WCAG {{wcag_level}}) |
| Performance | {{performance_constraints}} |
| Other | {{other_constraints}} |

## Acceptance Criteria

{{#each acceptance_criteria}}
- **AC-{{id}}**: {{description}} — *Testable via*: {{test_method}}
{{/each}}

## Risk Assessment

| Risk Level | Rationale |
|------------|-----------|
| {{initial_risk_level}} (0-3) | {{risk_rationale}} |

---

## Design Exploration Guidance

This Design Brief authorizes the Design Agent to explore candidate designs via Design Revisions.
Each revision will be evaluated against these criteria and the risk level framework in
DESIGN_GOVERNANCE.md.

**Next Gate**: Independent Design Review (Gate D1) → Human Approval (Gate D2) → Design Exploration