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
  - Classify every finding by blast radius (`REACHES_IMPLEMENTATION` | `EVIDENCE_HYGIENE`) per
    [Finding Classification by Blast Radius](#finding-classification-by-blast-radius) — by reach,
    never by symptom — and record hygiene findings rather than blocking on them.
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

## Finding Classification by Blast Radius

Every Design Review finding must be classified on exactly one dimension before a verdict is
emitted: **what the finding can reach**. Classification is by **reach, not by symptom**.

**The discriminator, stated plainly: _can this finding change what the implementation does?_**

### `REACHES-IMPLEMENTATION` — always blocking

The finding is true **and** it is a defect in something the implementation will satisfy, obey, or
be constrained by. It is **always blocking**: it forces `CHANGES_REQUIRED`, or
`HUMAN_DECISION_REQUIRED` when it is a genuine Level 2/3 product/design decision. Examples:

- A normative rule the code contradicts.
- A `MUST`-add snippet that does not compile on the pinned SDK.
- A §ownership file list that omits files the revision's own rules require — this breaks
  path-ownership serialisation (the `AGENTS.md` concurrency invariant).
- A privacy or disclosure boundary.
- A state or ownership transition.

### `EVIDENCE_HYGIENE` — non-blocking at the review gate, required at the freeze

The finding is true **but** it cannot change what the implementation does. In a pre-implementation
artifact it is **non-blocking by default**: it is recorded in `payload.non_blocking_findings[]` and
the revision proceeds. Examples:

- A stale `file:line` range inside a quotation.
- A stale `grep | wc -l` count.
- A table preamble that misdescribes its own table.
- A published command that does not reproduce.
- A register that disagrees with itself **in a non-normative position**.

### Classify by reach, not by symptom

Surface form does not decide the class — **position** does. A "register that disagrees with itself"
is `EVIDENCE_HYGIENE` when it is a **count table**, and `REACHES-IMPLEMENTATION` when it is a
**traceability row asserting which requirement a normative rule serves**. Classifying by symptom
lets the same wrong class be argued both ways; reach is the only sound test, so it is the test that
is applied.

### Symmetry with `ENGINEERING_REVIEW`

This section is a **symmetry repair, not a new concept**. `ENGINEERING_REVIEW` already carries
`payload.non_blocking_followups[]` and the verdict `APPROVE_WITH_NON_BLOCKING_FOLLOWUP` (see
[STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md) § 2), and [QA_GOVERNANCE.md](QA_GOVERNANCE.md)
rule 5 already makes `OPTIONAL` / `NOT_IN_DEFAULT_PIPELINE` evidence rows non-blocking by
construction. `DESIGN_REVIEW` was the sole outlier: it had no non-blocking disposition at all, so a
design reviewer had no structured way to say "wrong, but it cannot reach the implementation", and
every true finding had to become `CHANGES_REQUIRED`.

### Non-blocking is deferred, never waived

A finding classified `EVIDENCE_HYGIENE` is **recorded and still required**. The correction
requirement is **moved onto Gate D5**, not deleted. "Non-blocking" governs the gate **between a
revision and its freeze** — it never governs the freeze itself.

---

## Process Gates

### Gate D1: Design Brief Review
- **Trigger**: Design Brief created by Design Agent.
- **Reviewer**: Independent Design Reviewer.
- **Criteria**: Completeness, traceability to requirements/architecture, feasible scope, clear acceptance criteria.
- **Output**: `APPROVED` → proceed to Design Exploration; `APPROVED_WITH_NON_BLOCKING_FINDINGS` → proceed, with the recorded hygiene findings carried to Gate D5; `CHANGES_REQUIRED` → Design Agent revises.

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
- **Output**: `APPROVED` → proceed to DCR/Human Approval; `APPROVED_WITH_NON_BLOCKING_FINDINGS` → proceed, with the recorded hygiene findings carried to Gate D5; `CHANGES_REQUIRED` → Design Agent revises.

### Gate D4: DCR / Human Approval (per Risk Level)
- **Level 0**: `AUTO` — no gate, routed to implementation.
- **Level 1**: `AUTO` with notification — design system owner informed; proceeds unless objection within 24h.
- **Level 2**: `HUMAN_DECISION_REQUIRED` — human product/design approval via structured question UI.
- **Level 3**: `HUMAN_DECISION_REQUIRED` — human product/design/architecture approval via structured question UI.

### Gate D5: Design Contract Freeze
- **Trigger**: Design Revision passes all applicable gates.
- **Precondition — all recorded non-blocking findings corrected**: every finding classified
  `EVIDENCE_HYGIENE` and recorded in the review's `payload.non_blocking_findings[]` **must be
  corrected before the freeze**. The freeze is **refused** while any recorded non-blocking finding
  is still open. "Non-blocking" governs *the gate between the revision and the freeze* — never the
  freeze itself.
- **Precondition check — open vs closed is determined, never inferred**: every entry in
  `non_blocking_findings[]` carries a `finding_id` that is **stable across emits of the same
  `revision_id`**, so the Manager can match carries forward. The Manager carries the open set
  forward from the most recent `DESIGN_REVIEW` emit for that `revision_id`; an entry closes **only**
  when a fresh `DESIGN_REVIEW` records that same `finding_id` with `resolution: CORRECTED` and a
  `resolution_ref` naming the corrected location. A carried-forward `finding_id` the fresh emit
  omits is **still open** — absence is never closure, so "no recorded open findings" can never be
  confused with "none were ever recorded". The correcting emit already exists in the lifecycle: a
  correction produces a new Design Revision and invariant 2 requires an Independent Design Review of
  every revision, so no new lane is required to close a finding.
- **Action**: Manager verifies the precondition, then freezes the revision as Design Contract,
  records provenance.
- **Output**: `DESIGN_CONTRACT_FROZEN` — triggers Implementation and QA Contract Definition.

---

## Invariants

1. **Design Agent ≠ Independent Design Reviewer** — separate agents, no overlap.
2. **Design Agent never approves own work** — every Design Revision requires Independent Design Review.
3. **Independent Design Reviewer is read-only** — never modifies design artifacts.
4. **Substantial UI changes require an approved Design Revision** — implementers must not invent consequential UX.
5. **Implementation-discovered UI gaps route back via DCR** — not resolved in implementation lane.
6. **Risk level classification is mandatory** for every Design Revision and DCR.
6a. **Finding disposition is mandatory** for every Design Review finding — each finding carries a
`blast_radius` and, when it is `EVIDENCE_HYGIENE`, is recorded in `non_blocking_findings[]` and
still required before Gate D5. A finding is never silently dropped, and it closes only on an
explicit `resolution: CORRECTED` recorded against its carried-forward `finding_id` in a later
`DESIGN_REVIEW` of the same `revision_id` — never by absence from a later emit.
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
  "status": "APPROVED" | "APPROVED_WITH_NON_BLOCKING_FINDINGS" | "CHANGES_REQUIRED" | "HUMAN_DECISION_REQUIRED",
  "provenance": { "reviewer_id": "", "revision_id": "", "head_sha": "" },
  "payload": { "risk_level": 0, "findings": [], "non_blocking_findings": [], "traceability_gaps": [] },
  "evidence": { "gate_results": {} },
  "blockers": [],
  "next_actions": ["DCR_PROCESS" | "HUMAN_APPROVAL" | "DESIGN_CONTRACT_FREEZE"]
}
```

Every entry in `findings[]` and `non_blocking_findings[]` carries a
`blast_radius: REACHES_IMPLEMENTATION | EVIDENCE_HYGIENE`. The authoritative field shapes and the
reach-based disposition rules are in [STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md) § 4; the
classification taxonomy and its discriminator are in
[Finding Classification by Blast Radius](#finding-classification-by-blast-radius) above.

---

## Design Authority & AI-Assisted Design Governance

This section encodes empirical lessons from real design-agent bake-offs. It governs
AI-assisted design workflows where a **project-designated canonical visual tool** is the
authoritative design surface.

### Canonical Visual Authority

- **The project-designated canonical visual tool is the canonical visual authority**.
  Design artifacts (pages, components, design tokens) exist in the canonical visual tool.
  Markdown/YAML artifacts are metadata and traceability only; they do not represent visual truth.
- **Visual correctness is determined by human visual inspection of the canonical design artifacts**,
  not by document checks, layer counts, tool success responses, or model self-assessment.

### Source-Artifact Immutability

- **Known-good / human-approved design artifacts are immutable during AI revision**.
- AI agents must **never write directly to canonical source artifacts** (artifacts referenced by a
  frozen Design Contract or previously human-approved).
- Any AI-driven change targeting a canonical artifact **must create a new revision candidate
  artifact** in the canonical visual tool, leaving the source untouched.

### Revision-Candidate Workflow

- **All AI design work produces disposable revision candidates**, not in-place edits.
- A revision candidate is a complete, self-contained design artifact that can be
  independently reviewed, compared, and either promoted or discarded.
- **Promotion** = human visual approval → candidate becomes the new canonical artifact (via
  recorded operation in the canonical visual tool, recorded in Design Revision metadata).
- **Discard** = candidate is abandoned; canonical source remains unchanged.

### Artifact Write Verification

- **AI must verify artifact state after every write operation to the canonical visual tool**.
- Verification requires **reading back the written artifact** and confirming:
  - Artifact exists and is accessible.
  - Expected components/layers are present with correct properties.
  - Visual content matches intent (via screenshot or deterministic property checks).
- **Artifact names, layer/component counts, and successful tool responses do not prove visual correctness**.
  A tool may report success while the document is blank, corrupted, or visually wrong.
- Failed verification = candidate is marked `FAILED` and discarded; source artifact is
  never repaired in place.

### Deterministic vs. Visual Validation Responsibilities

| Validation Type | Responsible Party | Evidence Standard |
|-----------------|-------------------|-------------------|
| Document/schema compliance (metadata, traceability, risk level) | Independent Design Reviewer | Deterministic — machine-checkable |
| Design system token/component usage | Independent Design Reviewer | Deterministic — token/component reference verification |
| UX/accessibility/IA integrity | Independent Design Reviewer | Qualitative — structured review with evidence |
| **Visual correctness (layout, rendering, interaction fidelity)** | **Human (Visual Approval)** | **Human visual inspection of canonical artifact** |
| **Model self-QA / AI visual assessment** | **Advisory only** | **Non-authoritative — never grants approval** |

- **Model self-review cannot grant design approval**. AI-reported "all checks passing" while
  visible defects remain is a known failure mode.
- Visual approval is a **Human Decision** (type `DESIGN`) per [HUMAN_DECISIONS.md](HUMAN_DECISIONS.md).

### Human Visual Approval Gate

- **Human visual approval is required before canonical promotion** of any revision candidate.
- The approval is a `HUMAN_DECISION_REQUIRED` gate (Level 2 or 3 per risk assessment).
- The Human Decision presents the candidate artifact (via canonical tool link/screenshot) alongside the
  current canonical artifact for direct comparison.
- Options are atomic: `APPROVE_CANDIDATE`, `REJECT_CANDIDATE`, `REQUEST_REVISION`.

### Design-System Asset Reuse

- **Existing design-system assets (logos, icons, navigation, typography, spacing,
  established components) must be reused via component instances or shared libraries** in the
  canonical visual tool, not recreated or approximated.
- Design Revision metadata must declare `design_system_asset_refs` listing reused component
  IDs/library references.
- Independent Design Reviewer verifies reuse compliance deterministically.

### Safe-Abort on Invalid Source Preconditions

- **If a revision candidate's source precondition is invalid (source artifact corrupted,
  missing, or visually degraded), the AI must abort the revision and report a structured
  blocker with reason `SOURCE_PRECONDITION_FAILED`**.
- The AI must **not** attempt to "repair" the canonical source artifact in place.
- The Engineering Manager escalates to a Human Decision (type `DESIGN`) to authorize
  source-artifact recovery from version history or human re-creation.
- This prevents compounding damage (empirically: a surgical correction damaged previously-good
  artifacts; the correct model detected corruption and safely aborted).

### Model Routing as Replaceable Execution Policy

- **Model routing is a configurable execution policy, not workflow authority**.
- Current empirical routing defaults (subject to change without workflow modification):
  - **First-pass design**: Gemini 3.1 Pro (cost-effective exploration) — *ShipIt example*
  - **Precision / high-complexity escalation**: Opus 5 (surgical correction, difficult designs) — *ShipIt example*
- Routing configuration lives in project-level policy (e.g., `.design-routing.yaml`), not in
  DESIGN_GOVERNANCE.md or WORKFLOW.md.
- Workflow semantics (gates, invariants, approval paths) remain unchanged regardless of
  which model executes a given step.

### Escalation After Repeated Revision Failures

- **After two consecutive meaningful revision failures on the same Design Brief** (where
  "meaningful" = distinct approach/changelog, not trivial re-tries), the Engineering Manager
  must escalate via a Human Decision (type `DESIGN`).
- Escalation options:
  - Re-scope the Design Brief (reduce complexity, split into smaller briefs).
  - Engage human designer for the specific challenge.
  - Switch to a different model/routing configuration.
  - Accept current best candidate with documented trade-offs.
- This prevents infinite AI revision loops and ensures human judgment intervenes when
  automated exploration stalls.

### Structured Result Extensions — Penpot Binding Example

This section shows how the tool-agnostic structured result fields (authoritative in
[STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md)) map to Penpot concepts when Penpot is the
canonical visual authority. This is a **project/tool binding example**, not a framework dependency.

| Generic Field (STRUCTURED_RESULTS.md) | Penpot Binding |
|----------------------------------------|----------------|
| `design_artifact_ref` | Penpot file ID (e.g., `figma:abc123` or Penpot file URL) |
| `source_design_artifact_ref` | Source board/page ID (canonical, human-approved) |
| `candidate_design_artifact_ref` | Candidate board/page ID (disposable revision) |
| `canonical_design_artifact_ref` | Canonical board/page ID (frozen Design Contract) |
| `verification.write_verified` | Penpot API write acknowledged + readback confirmed |
| `verification.deterministic_checks_passed` | Layer/component count > 0, expected components present |
| `verification.deterministic_checks_total` | Total deterministic checks configured |
| `verification.evidence_ref` | Penpot screenshot URL or exported image reference |
| `verification.verification_status` | `UNVERIFIED` \| `VERIFIED` \| `FAILED` \| `INCOMPLETE` |
| `design_system_asset_refs` | Penpot component instance IDs / shared library references |
| `routing_policy.routing_class` | `EXPLORATION` \| `PRECISION` \| `SPECIALIZED` |

**Penpot-specific execution guidance** (project-level, not framework):

- **Candidate board naming**: `Feature/Revision-{{revision_number}}/Candidate-{{uuid}}`
- **Source board write prohibition**: Enforced via Penpot permissions / agent policy
- **Asset libraries**: Project-configured (e.g., `design-system-core`, `icons`, `typography`, `navigation`)
- **Verification checks**: Board exists, layer count > 0, expected component instances present, screenshot captured

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