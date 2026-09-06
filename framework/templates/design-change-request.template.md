# Design Change Request (DCR) — {{dcr_id}}

<!--
  TEMPLATE: Design Change Request
  Used for proposing changes to an approved Design Revision or Design Contract.
  Per DESIGN_GOVERNANCE.md risk levels:
  - Level 0: AUTO (implementation detail)
  - Level 1: AUTO with notification
  - Level 2: HUMAN_DECISION_REQUIRED
  - Level 3: HUMAN_DECISION_REQUIRED (with architecture review)
-->

## Metadata

| Field | Value |
|-------|-------|
| `dcr_id` | {{dcr_id}} |
| `target_revision_id` | {{target_revision_id}} |
| `initiator` | {{initiator}} (agent ID or human ID) |
| `initiated_at` | {{initiated_at}} (ISO8601) |
| `risk_level` | {{risk_level}} (0-3) |
| `status` | {{status}} (OPEN \| UNDER_REVIEW \| APPROVED \| REJECTED \| APPLIED \| SUPERSEDED) |
| `reviewed_by` | {{reviewed_by}} |
| `reviewed_at` | {{reviewed_at}} (ISO8601) |
| `approved_by` | {{approved_by}} (human ID, required for Level 2+) |
| `approved_at` | {{approved_at}} (ISO8601) |

## Change Description

{{change_description}}

## Change Rationale

{{change_rationale}}

## Risk Assessment

| Aspect | Assessment |
|--------|------------|
| **Risk Level** | {{risk_level}} ({{risk_level_name}}) |
| **Affected Artifacts** | {{affected_artifacts}} |
| **Implementation Impact** | {{implementation_impact}} (NONE \| LOW \| MEDIUM \| HIGH \| UNKNOWN) |
| **Design System Impact** | {{design_system_impact}} |
| **UX/Accessibility Impact** | {{ux_accessibility_impact}} |
| **Information Architecture Impact** | {{ia_impact}} |

## Approval Path

{{#if_eq risk_level 0}}
**Level 0 — Implementation Correction**: `AUTO` — Routed to implementation lane as implementation detail. No design gate required.
{{/if_eq}}
{{#if_eq risk_level 1}}
**Level 1 — Design-System Correction**: `AUTO` with design-system owner notification. Proceeds unless objection within 24h.
{{/if_eq}}
{{#if_eq risk_level 2}}
**Level 2 — Feature UX Change**: `HUMAN_DECISION_REQUIRED` — Product/design approval required via structured question UI.
{{/if_eq}}
{{#if_eq risk_level 3}}
**Level 3 — Major Workflow/Navigation/IA Change**: `HUMAN_DECISION_REQUIRED` — Product/design/architecture approval required via structured question UI.
{{/if_eq}}

## Review Findings

{{#if review_findings}}
### Independent Design Reviewer Findings
{{#each review_findings}}
- **{{severity}}** [{{category}}]: {{description}} (Artifact: {{artifact_ref}})
{{/each}}
{{/if}}

## Resolution

{{#if resolution_notes}}
**Resolution Notes**: {{resolution_notes}}
{{/if}}

## Next Steps

{{#if_eq status "APPROVED"}}
- Apply changes → New Design Revision → Design Contract Freeze
{{/if_eq}}
{{#if_eq status "REJECTED"}}
- Document rationale → Close DCR → Design Agent may propose alternative
{{/if_eq}}
{{#if_eq status "OPEN"}}
- Await Independent Design Review → Risk Level Verification → Approval Path
{{/if_eq}}