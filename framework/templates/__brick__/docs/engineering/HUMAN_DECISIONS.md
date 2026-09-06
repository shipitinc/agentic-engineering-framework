# HUMAN_DECISIONS.md — Human Decision Governance

This document defines the **Human Decision** object: a durable, machine-readable record that replaces
conversational waiting with structured, auditable, and resumable human-in-the-loop governance.

---

## Motivation

The previous model relied on conversational pauses where agents "waited for human input" in chat.
This created several problems:
- No durable record of the decision context, options, or rationale.
- Workflow could not be resumed if the agent session ended.
- No audit trail for consequential decisions.
- Human decisions were implicit in chat logs, not queryable or enforceable.

The Human Decision object solves this by making every consequential human gate a **first-class,
persisted artifact** with explicit state machine, provenance, and integration with the orchestration
loop.

---

## Human Decision Object Schema

```yaml
# human-decision.yaml
decision_id: UUID                          # Globally unique identifier
type: PRODUCT | ARCHITECTURE | DESIGN | SECURITY | INFRASTRUCTURE | DESTRUCTIVE_OPERATION | DEPLOYMENT_AUTHORITY | OTHER_CONSEQUENTIAL
status: PENDING | IN_PROGRESS | RESOLVED | ESCALATED | DEFERRED | CANCELLED
question: string                           # The exact decision question (atomic, single proposal)
context:                                   # Supporting context for the decision
  summary: string                          # Brief narrative context
  blocking_work_item:                      # The work item blocked by this decision
    item_type: FEATURE | DESIGN_REVISION | DCR | QA_CONTRACT | DEPLOYMENT | MIGRATION | ARCHITECTURE_CHOICE | OTHER
    item_id: UUID
    item_ref: string                       # Human-readable reference (e.g., "Design Revision #3 for Feature X")
  evidence:                                # Evidence package presented to human
    documents:                             # Links to relevant artifacts
      - type: DESIGN_BRIEF | DESIGN_REVISION | DCR | QA_CONTRACT | QA_RESULT | ADR | DEPLOYMENT_PLAN | OTHER
        id: UUID
        url: string
    quantitative_data:                     # Metrics, benchmarks, cost estimates
      - metric: string
        value: string
        source: string
    qualitative_tradeoffs:                 # Non-quantitative considerations
      - dimension: string
        option_a: string
        option_b: string
        assessment: string
  recommendation:                          # Orchestrator/agent recommendation
    recommended_option: string             # Option ID from options[]
    rationale: string
    confidence: HIGH | MEDIUM | LOW
options:                                   # Discrete, atomic, selectable choices (2-4)
  - option_id: string                      # e.g., "OPTION_A"
    label: string                          # Short display label (max ~5 words)
    description: string                    # What happens if this option is chosen
    implications: string                   # Consequences, risks, follow-up work
    estimated_effort: string               # e.g., "2 days", "1 sprint", "ongoing"
    risk_level: LOW | MEDIUM | HIGH | CRITICAL
resolution:                                # Populated when status=RESOLVED
  selected_option: string                  # Option ID chosen
  decided_by: string                       # Human identifier
  decided_at: ISO8601 timestamp
  rationale: string                        # Human's rationale
  follow_up_actions:                       # Actions triggered by decision
    - action: string
      owner: string
      due_date: ISO8601 timestamp (optional)
created_by: string                         # Agent/orchestrator ID that created the decision
created_at: ISO8601 timestamp
updated_at: ISO8601 timestamp
```

---

## Decision Types

| Type | Description | Typical Context |
|------|-------------|-----------------|
| `PRODUCT` | Product scope, priority, feature definition | Requirements clarification, scope change |
| `ARCHITECTURE` | Major technology/platform/structural choice | ADR decision, infrastructure topology |
| `DESIGN` | Design direction, UX/UI, design system | Design Brief approval, Level 2/3 DCR |
| `SECURITY` | Security policy, vulnerability response, compliance | Threat model approval, exception request |
| `INFRASTRUCTURE` | Provisioning, scaling, environment changes | New environment, capacity increase |
| `DESTRUCTIVE_OPERATION` | Data deletion, schema destruction, infra teardown | Production migration, cleanup |
| `DEPLOYMENT_AUTHORITY` | Production promotion, release authorization | Release go/no-go, rollback authorization |
| `OTHER_CONSEQUENTIAL` | Any other decision with material impact | Catch-all for unambiguous consequential gates |

---

## State Machine

```
PENDING → IN_PROGRESS → RESOLVED
                ↓
            ESCALATED → (re-enters as new decision or human intervention)
                ↓
            DEFERRED → (re-enters PENDING when unblocked)
                ↓
            CANCELLED → (work item abandoned or superseded)
```

**Transitions**:
- `PENDING` → `IN_PROGRESS`: Human acknowledges and begins deliberation (auto on first view).
- `IN_PROGRESS` → `RESOLVED`: Human selects option via structured UI; resolution recorded.
- `IN_PROGRESS` → `ESCALATED`: Human escalates to higher authority; creates new decision or direct intervention.
- `IN_PROGRESS` → `DEFERRED`: Human defers; decision re-enters `PENDING` when unblocking condition met.
- `IN_PROGRESS` → `CANCELLED`: Human cancels; blocking work item marked abandoned/superseded.

---

## Orchestration Integration

### Creation
The Engineering Manager (Orchestrator) creates a Human Decision object when:
1. Workflow reaches a `HUMAN_DECISION_REQUIRED` gate (WORKFLOW.md).
2. An agent reports a `HUMAN_DECISION_REQUIRED` blocker in its structured result.
3. A DCR Level 2/3 requires human approval (DESIGN_GOVERNANCE.md).
4. QA classifies a `REQUIREMENT_GAP` (QA_GOVERNANCE.md).
5. Deployment migration is `DESTRUCTIVE` or infrastructure destruction (DEPLOYMENT_GOVERNANCE.md).
6. Production promotion gate (WORKFLOW.md step 36).

### Presentation
**Always** surface through the structured question UI (`ask_user` / `mcp__Air__ask_user_question`).
Never as free-form prose. The UI presents:
- Decision header (type, blocking item)
- Question
- Context summary + evidence links
- Recommendation with rationale
- Options as discrete, atomic, selectable choices

### Agent Behavior While Waiting
When a Human Decision is `PENDING` or `IN_PROGRESS`:
1. **The blocking agent terminates/parks cleanly** — emits a structured result with `status: BLOCKED`, `blockers: [{decision_id, type: HUMAN_DECISION}]`.
2. **The Engineering Manager parks the workflow lane** — updates `WORK_STATE.md` with the decision reference.
3. **Safe parallel work continues** — other non-blocked lanes proceed per `SAFE_PARALLEL_WORK` in reviewer results.
4. **No polling** — the system uses event-driven resumption (webhook, callback, or next orchestration cycle).

### Resumption
When the Human Decision reaches `RESOLVED`:
1. The Engineering Manager reads the decision resolution.
2. Validates the selected option against the original options (tamper-check).
3. Resumes the blocked lane with the resolution as input.
4. Advances the workflow per the decision outcome (e.g., `APPROVED` → next gate; `REJECTED` → correction/DCR).
5. Records the transition in `WORK_STATE.md`.

### Persistence
- Human Decision objects are stored in the product repository under `.decisions/` (or configured location).
- They are **version-controlled** — every state transition is a commit.
- They are **queryable** — agents can list pending decisions for a work item.
- They form an **audit trail** — immutable record of all consequential human decisions.

---

## Structured Question UI Contract

The `ask_user` / `mcp__Air__ask_user_question` tool is the **only** authorized mechanism for
presenting human decisions. The Orchestrator must format the decision as:

```
HUMAN DECISION REQUIRED — <type>: <brief topic>

Decision: <the exact question>
Why blocking: <blocking work item and impact>
Evidence: <links to artifacts, quantitative data, qualitative tradeoffs>
Recommendation: <recommended option with rationale>
Options:
  A. <label> — <description> — <implications> — <effort> — <risk>
  B. <label> — <description> — <implications> — <effort> — <risk>
  ...
Paused lanes: <list of blocked work items>
Safe work continuing: <list of non-blocked lanes>
```

**Rules**:
- Each question = one atomic decision.
- Each option = one atomic proposal.
- No bundling unrelated decisions.
- Human must be able to accept/reject each independently.
- Research first — never ask about facts discoverable from repo.

---

## Invariants

1. **Every consequential human gate = a Human Decision object** — no exceptions.
2. **Human Decision objects are durable, versioned, and queryable** — not chat ephemera.
3. **Agents park cleanly while waiting** — emit structured `BLOCKED` result, no hanging processes.
4. **Workflow is resumable from persisted state** — Manager reads decision, validates, continues.
5. **Structured question UI is mandatory** — never free-form prose.
6. **Each question/option is atomic** — no bundling.
7. **Research first** — Orchestrator discovers facts before asking.
8. **Only Engineering Manager creates/resolves Human Decisions** — specialists cannot bypass.
9. **Decision audit trail is immutable** — state transitions are commits.
10. **Routine transitions remain automatic** — Human Decisions only for consequential gates.

---

## Cross-References

- [WORKFLOW.md](WORKFLOW.md) — Human gates at steps 6, 14, 18, 23, 28, 36
- [DESIGN_GOVERNANCE.md](DESIGN_GOVERNANCE.md) — Level 2/3 DCR approval
- [QA_GOVERNANCE.md](QA_GOVERNANCE.md) — Human QA initiation, Requirement Gap resolution
- [DEPLOYMENT_GOVERNANCE.md](DEPLOYMENT_GOVERNANCE.md) — Destructive migration approval, production promotion
- [STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md) — Human Decision Result contract
- [LEARNING_POLICY.md](LEARNING_POLICY.md) — `HUMAN_DECISION_RECORD` classification
- [AGENTS.md](../../AGENTS.md) — "Human questions & clarifications" invariant

---

## Templates

- [Human Decision Template](../../framework/templates/human-decision.template.yaml)