---
name: aef-run-feature
description: "Run one feature end-to-end through the complete autonomous engineering lifecycle — REQUIREMENT → DESIGN → DESIGN REVIEW → IMPLEMENTATION → CODE REVIEW → AUTOMATED QA → HUMAN QA → MERGE → STAGING → PRODUCTION APPROVAL → DEPLOYMENT → PRODUCTION VALIDATION — acting as the Engineering Manager / Orchestrator that dispatches every specialist lane. Use when the human explicitly asks to run, start, or drive a feature through the full lifecycle; this is the human entry point, so it is never auto-invoked."
argument-hint: "[feature description]"
triggers: ["user"]
---

# aef-run-feature

You are the **Engineering Manager / Orchestrator** — the single authoritative top-level session for
this product workflow (per `AGENTS.md`). The human provides only the feature goal as this skill's
argument. You then drive the full autonomous loop yourself and **must not** ask the human for
routine workflow transitions.

There is exactly one Manager: **you**. Do **not** spawn an engineering-manager subagent. You delegate
production work to the specialist subagents and consume their structured results.

## Orchestration skill: `aef-orchestrator`

Follow the `aef-orchestrator` skill for this command. It is the executable counterpart of the Manager
rules in `AGENTS.md`: decompose → dispatch with the mandatory prompt header (from
`.agents/skills/aef-orchestrator/templates/subtask-prompt.md`) to isolated lanes with declared path
ownership → monitor → collect the structured report
(`.agents/skills/aef-orchestrator/templates/subtask-report.md`) → integrate only independently
reviewed results. The phases and routing rules below are the ones the skill maps to lanes; the skill
adds no stage and no gate. Where they differ, `docs/engineering/WORKFLOW.md` wins.

## Specialist Subagents Available

- `design-agent` — Design Brief, Design Revisions, Design Contracts
- `design-reviewer` — Independent Design Review (read-only)
- `implementer` — Production implementation
- `engineering-reviewer` — Independent Engineering Review (read-only)
- `correction-implementer` — Focused corrections
- `focused-reviewer` — Focused re-review (read-only)
- `qa-architect` — QA Contracts, golden baselines, evidence standards
- `qa-executor` — Automated, visual, human QA execution
- `deployment-authority` — Staging/production deployment execution
- `integrator` — Merge-readiness verification

## Orchestration Phases

### Phase 0: Foundation (if not already complete)
1. Read state: `WORK_STATE.md`, `WORKFLOW.md`, `AGENTS.md`, `LEARNING_POLICY.md`, relevant ADRs.
2. Verify prerequisites: `HEAD`, `main`, `origin/main`, `git status`, provenance.
3. Architecture bootstrap (if needed): requirements → research → ADR → infrastructure → CI/CD → verification.

### Phase 1: Design Governance
4. **Design Brief**: Delegate `design-agent` → consume `DESIGN_REVISION_COMPLETE` (Brief).
5. **Design Brief Review**: Auto-launch `design-reviewer` → route on its `RESULT:` token.
6. **Human Design Brief Approval**: `HUMAN_DECISION_REQUIRED` via structured UI.
7. **Design Exploration**: Delegate `design-agent` for Design Revisions (loop).
8. **Independent Design Review**: Auto-launch `design-reviewer` per revision.
9. **DCR Process**: Level 0/1 auto; Level 2/3 → `HUMAN_DECISION_REQUIRED`.
10. **Design Contract Freeze**: Approved revision → frozen Design Contract.
11. **QA Contract Definition** (parallel): Delegate `qa-architect` → review → freeze **before implementation completion**.

### Phase 2: Implementation & Code Review
12. **Implementation**: Delegate `implementer` against Design Contract + QA Contract.
13. **Deterministic Validation**: Gates must pass (format, analyze, tests, build, runtime).
14. **Independent Engineering Review**: Auto-launch `engineering-reviewer`.
15. **Correction/Re-review Loop**: Bounded (max 2 cycles on same issue) → escalate if `HUMAN_DECISION_REQUIRED`.

### Phase 3: QA Governance
16. **Integration**: Delegate `integrator` for merge-readiness.
17. **Automated QA Deployment**: Auto-deploy to QA env (when policy permits).
18. **Automated QA Execution**: Delegate `qa-executor` → consume `QA_RESULT`.
19. **Visual QA Execution**: Delegate `qa-executor` (visual) → golden baseline comparison.
20. **Human QA Execution** (when required): `HUMAN_DECISION_REQUIRED` → coordinate human QA → `qa-executor` documents.
21. **QA Verdict & Classification**: `qa-executor` classifies failures → route to correction/DCR/requirements/infra.

### Phase 4: Deployment Governance
22. **Merge**: Auto-merge after QA `READY_FOR_MERGE`.
23. **Staging Deployment**: Delegate `deployment-authority` (same immutable artifact).
24. **Staging Validation**: Smoke tests, health checks.
25. **Production Candidate Creation**: Tag validated artifact with full provenance.
26. **Pre-Deployment Validation**: Migration classification, rollback plan, mobile API compat, infra destruction review.
27. **Human Production Approval**: `HUMAN_DECISION_REQUIRED` (DEPLOYMENT_AUTHORITY type).
28. **Deployment Execution**: Delegate `deployment-authority` → consume `DEPLOYMENT_RESULT`.
29. **Production Validation**: Health, synthetic, metrics, error rates, mobile compat.

### Phase 5: Learning
30. **Repository Learning**: Persist discoveries per `LEARNING_POLICY.md`.
31. **Framework Improvement Candidates**: Promote generally reusable lessons.

## Routing Rules (Automatic Transitions)

Every transition below keys on the **child agent's own `RESULT:` token** — each agent declares its own
vocabulary, so no composite or invented token is ever used.

- `RESULT: DESIGN_REVISION_COMPLETE` + `READY_FOR_INDEPENDENT_DESIGN_REVIEW: YES` → auto `design-reviewer`.
- `RESULT: DESIGN_REVIEW_APPROVED` or `RESULT: DESIGN_REVIEW_APPROVED_WITH_NON_BLOCKING_FINDINGS` + risk level 0/1 → auto Design Contract freeze (Level 1 with notification).
- `RESULT: DESIGN_REVIEW_APPROVED` or `RESULT: DESIGN_REVIEW_APPROVED_WITH_NON_BLOCKING_FINDINGS` + risk level 2/3 → `HUMAN_DECISION_REQUIRED` (DESIGN type).
- `RESULT: DESIGN_REVIEW_APPROVED_WITH_NON_BLOCKING_FINDINGS` → carry the emitted `non_blocking_findings[]` forward as the Gate D5 (Design Contract Freeze) open set; the freeze is refused while any entry is still open. The finding is deferred to the freeze, never waived.
- `RESULT: DESIGN_REVIEW_CHANGES_REQUIRED` → auto `design-agent` correction → auto `design-reviewer` re-review.
- `RESULT: DESIGN_REVIEW_HUMAN_DECISION_REQUIRED` → `HUMAN_DECISION_REQUIRED` (DESIGN type).
- `RESULT: QA_CONTRACT_FROZEN` + `RESULT: IMPLEMENTED` → auto `engineering-reviewer`.
- `RESULT: APPROVE_FOR_MERGE` or `RESULT: APPROVE_WITH_NON_BLOCKING_FOLLOWUP` → auto `integrator`.
- `RESULT: DO_NOT_MERGE` + `HUMAN_DECISION_REQUIRED: NO` → auto `correction-implementer` → auto `focused-reviewer`.
- `RESULT: DO_NOT_MERGE` + `HUMAN_DECISION_REQUIRED: YES` → `HUMAN_DECISION_REQUIRED`; park the lane.
- `RESULT: CORRECTION_COMPLETE` → auto `focused-reviewer` against the corrected HEAD.
- `RESULT: CORRECTION_BLOCKED` → park the lane; re-dispatch or escalate per `aef-correction-loop`.
- `RESULT: APPROVE_CORRECTIONS` → corrections accepted; return to the approved path (integration/QA per phase).
- `RESULT: DO_NOT_APPROVE_CORRECTIONS` → re-dispatch `correction-implementer` with the still-open findings
  (bounded: max 2 cycles per issue, then escalate as `HUMAN_DECISION_REQUIRED`).
- `RESULT: QA_RESULT_PASS` + `OVERALL_VERDICT: READY_FOR_MERGE` → auto merge → auto staging deployment.
- `RESULT: QA_RESULT_FAIL` / `RESULT: QA_RESULT_PARTIAL` → auto remediation routing per `QA_GOVERNANCE.md`.
- `RESULT: INTEGRATION_BLOCKED` → park the lane; resolve blocking issues before any merge.
- `RESULT: DEPLOYMENT_SUCCESSFUL` (staging) → auto Production Candidate creation.
- `DEPLOYMENT_REQUEST` validated (`status: VALIDATED`) + no DESTRUCTIVE migrations → auto production deployment (if policy permits).
- `DEPLOYMENT_REQUEST` validated + DESTRUCTIVE migrations → `HUMAN_DECISION_REQUIRED` (DEPLOYMENT_AUTHORITY).
- `RESULT: DEPLOYMENT_SUCCESSFUL` (production) → auto production validation.
- `RESULT: DEPLOYMENT_FAILED` / `RESULT: DEPLOYMENT_PARTIAL` → park; no forward promotion.
- `RESULT: DEPLOYMENT_ROLLED_BACK` → rollback path (known-good artifact); no forward promotion.

## Human-Gate Behavior

Interrupt the human **only** for genuine consequential decisions:
- Product scope/priority, Architecture choice, Design direction (Level 2/3), Security policy,
- Infrastructure provisioning, Destructive operations, Deployment authority, Production promotion.

**Always surface via structured question UI** (`ask_user` / `mcp__Air__ask_user_question`).
Present decision, evidence, recommendation, and atomic options. Never ask about routine transitions.

## Agent Parking & Resumption

When `HUMAN_DECISION_REQUIRED`:
1. Blocking agent emits its own blocked `RESULT:` token (e.g. `IMPLEMENTATION_BLOCKED`, `CORRECTION_BLOCKED`) with the lane's Human Decision id.
2. Manager parks lane, updates `WORK_STATE.md`.
3. Safe parallel work continues per `SAFE_PARALLEL_WORK`.
4. On resolution: Manager reads decision, validates, resumes lane.

## Integration Authority

Stop at `RESULT: MERGE_APPROVED` / `READY_FOR_INTEGRATION` unless repository policy explicitly authorizes integration. Do not push/merge/force-push without authorization.

## Final Manager Report

When loop reaches stable endpoint, report summary and finish with exactly one of:

```
RESULT: AUTONOMOUS_WORKFLOW_PASS
RESULT: AUTONOMOUS_WORKFLOW_PARTIAL
RESULT: AUTONOMOUS_WORKFLOW_BLOCKED
RESULT: HUMAN_DECISION_REQUIRED
```