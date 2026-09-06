---
name: human-decision
description: Procedure for Human Decision object management in this framework — create durable decision objects, present via structured question UI, park agents cleanly, resume workflow from persisted state. Use when a consequential human gate is reached.
---

# Human Decision Management

Use this skill when the Engineering Manager creates, presents, and resolves Human Decision objects
per `AGENTS.md`, `docs/engineering/WORKFLOW.md`, and `docs/engineering/HUMAN_DECISIONS.md`.

## 1. When to create a Human Decision

Create a Human Decision object (not a chat question) when workflow reaches any `HUMAN_DECISION_REQUIRED` gate:

- Architecture choice (WORKFLOW.md step 6)
- Design Brief approval (WORKFLOW.md step 14)
- Level 2/3 DCR approval (DESIGN_GOVERNANCE.md)
- Human QA initiation (QA_GOVERNANCE.md Gate Q5)
- Requirement Gap resolution (QA_GOVERNANCE.md)
- Destructive migration approval (DEPLOYMENT_GOVERNANCE.md)
- Infrastructure destruction approval (DEPLOYMENT_GOVERNANCE.md)
- Production promotion (WORKFLOW.md step 36)

## 2. Decision object creation

- Use the `human-decision.template.yaml` template.
- Populate all fields: `decision_id`, `type`, `question`, `context`, `recommendation`, `options`.
- **Each question and option must be atomic** — no bundling.
- **Research first** — discover facts from repo before asking; only ask for preferences/trade-offs.
- Store in product repo under `.decisions/` (or configured location), version-controlled.

## 3. Structured question UI presentation

**Always** present via `ask_user` / `mcp__Air__ask_user_question` tool. Format:

```
HUMAN DECISION REQUIRED — <type>: <brief topic>

Decision: <exact question>
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

## 4. Agent parking (clean termination)

When a Human Decision is created:

1. **Blocking agent terminates cleanly** — emits structured result with `status: BLOCKED`, `blockers: [{decision_id, type: HUMAN_DECISION}]`.
2. **Engineering Manager parks the lane** — updates `WORK_STATE.md` with decision reference.
3. **Safe parallel work continues** — other non-blocked lanes proceed per `SAFE_PARALLEL_WORK`.
4. **No polling** — event-driven resumption (webhook, callback, or next orchestration cycle).

## 5. Resumption from persisted state

When Human Decision reaches `RESOLVED`:

1. Manager reads decision resolution from persisted object.
2. Validates selected option against original options (tamper-check).
3. Resumes blocked lane with resolution as input.
4. Advances workflow per decision outcome.
5. Records transition in `WORK_STATE.md`.

## 6. Audit trail

- Every state transition (`PENDING` → `IN_PROGRESS` → `RESOLVED`/`ESCALATED`/`DEFERRED`/`CANCELLED`) is a commit.
- Decision objects are immutable once resolved — amendments create new decision objects.
- Queryable for precedent and pattern analysis.

## 7. Invariants

- Only Engineering Manager creates/resolves Human Decisions — specialists cannot bypass.
- Routine transitions remain automatic — Human Decisions only for consequential gates.
- Decision audit trail is immutable — state transitions are commits.