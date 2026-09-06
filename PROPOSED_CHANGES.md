# Proposed File/Change Plan — AEF Governance Extension

This document outlines the complete plan to extend the Agentic Engineering Framework (AEF) to govern a full software engineering lifecycle with first-class support for Design Governance, QA Governance, Human Decisions, Deployment Governance, and Structured Results.

---

## 1. Core Lifecycle Document Updates

### `docs/engineering/WORKFLOW.md` — Extended Lifecycle
**Action:** Replace/extend the existing lifecycle with the complete 13-stage workflow:
1. REQUIREMENT
2. DESIGN
3. DESIGN REVIEW
4. IMPLEMENTATION
5. CODE REVIEW
6. AUTOMATED QA
7. HUMAN QA (when required)
8. MERGE
9. STAGING
10. PRODUCTION APPROVAL (when required)
11. DEPLOYMENT
12. PRODUCTION VALIDATION
13. REPOSITORY LEARNING

**Key additions:**
- Design governance gates (Design Brief approval, Design Review, Design Contract freeze)
- QA governance (QA Contract required before implementation completion, Automated QA, Visual QA, Human QA)
- Deployment governance (Staging, Production Candidates, Deployment Plans, Migration Classification)
- Human Decision gates at consequential points
- Structured result contracts at each gate

---

## 2. New Governance Documents

### `docs/engineering/DESIGN_GOVERNANCE.md`
**Content:**
- Design Agent role and responsibilities
- Independent Design Reviewer role (read-only)
- Design Brief template and lifecycle
- Design Revision metadata and versioning
- Design Change Request (DCR) process
- Approved Design Revision as contract for implementation
- Design Defect vs Implementation Defect classification
- Design-change risk levels:
  - Level 0: Implementation Correction
  - Level 1: Design-System Correction
  - Level 2: Feature UX Change
  - Level 3: Major Workflow/Navigation/IA Change
- Substantial UI changes require approved design revision
- Implementers must not invent consequential UX
- Implementation-discovered UI gaps route back to design lifecycle

### `docs/engineering/QA_GOVERNANCE.md`
**Content:**
- QA Architect role (defines QA strategy, contracts, golden baselines)
- QA Executor role (runs automated/visual/human QA)
- Automated QA (unit, integration, contract, e2e)
- Visual QA (golden baselines, pixel/perceptual diff)
- Human QA (exploratory, usability, accessibility)
- Acceptance/QA Contract required before implementation completion
- Deterministic evidence authoritative over reviewer opinion
- Implementation agents cannot approve changed visual golden baselines
- QA artifacts preserved as evidence
- Regressions require regression tests
- QA Failure Classifications:
  - IMPLEMENTATION_DEFECT
  - DESIGN_DEFECT
  - REQUIREMENT_GAP
  - ENVIRONMENT_DEFECT

### `docs/engineering/HUMAN_DECISIONS.md`
**Content:**
- Human Decision object schema (id, type, question, context, recommendation, options, blocking_work_item, status, resolution)
- Decision types: PRODUCT, ARCHITECTURE, DESIGN, SECURITY, INFRASTRUCTURE, DESTRUCTIVE_OPERATION, DEPLOYMENT_AUTHORITY, OTHER_CONSEQUENTIAL
- State machine: PENDING → IN_PROGRESS → RESOLVED / ESCALATED / DEFERRED
- Agents terminate/park cleanly while waiting
- Workflow resumable from persisted state
- Structured question UI integration (ask_user / mcp__Air__ask_user_question)
- Decision audit trail and provenance

### `docs/engineering/DEPLOYMENT_GOVERNANCE.md`
**Content:**
- Staging environment governance
- Production Candidates (immutable artifacts, build once / promote same)
- Deployment Plans (pre-deployment validation, migration steps, rollback plan)
- Migration Classification:
  - SAFE (additive, backward-compatible)
  - RISKY (schema changes, config changes requiring coordination)
  - DESTRUCTIVE (data deletion, column drops, infra destruction)
- Destructive production migrations always require human approval
- Infrastructure destruction requires human approval
- Coding agents never receive unrestricted production credentials
- Deployment execution belongs to separate Deployment Authority/Controller
- Automatic rollback prefers known-good artifact over AI debugging
- Mobile API backward compatibility consideration (old Android/iOS clients)

### `docs/engineering/STRUCTURED_RESULTS.md`
**Content:**
- Machine-readable result contracts for:
  - Design Agent Result
  - Design Reviewer Result
  - Implementation Result (existing, extended)
  - Code Review Result (existing, extended)
  - QA Contract Result
  - QA Execution Result (Automated, Visual, Human)
  - Human Decision Result
  - Deployment Request Result
  - Deployment Execution Result
  - Production Validation Result
- Standard envelope: RESULT_TYPE, STATUS, PROVENANCE, PAYLOAD, EVIDENCE, BLOCKERS, NEXT_ACTIONS
- No dependency on scraping conversational prose

---

## 3. Updated Existing Documents

### `AGENTS.md` — Extended Invariants
**Additions:**
- Design Governance invariants (Design Agent, independent Design Reviewer, DCR process)
- QA Governance invariants (QA Architect/Executor separation, evidence authority, golden baseline protection)
- Human Decision invariants (durable objects, clean park/resume, structured UI)
- Deployment Governance invariants (separate deployment authority, immutable artifacts, migration classification, credential isolation)
- Structured Results requirement (machine-readable contracts mandatory)

### `docs/engineering/LEARNING_POLICY.md` — Extended Classifications
**New categories:**
- `DESIGN_DISCOVERY` (already exists, clarify usage)
- `QA_DISCOVERY` — finding affecting QA strategy, contracts, or evidence
- `DEPLOYMENT_DISCOVERY` — finding affecting deployment, migration, rollback
- `HUMAN_DECISION_RECORD` — persisted human decision with rationale

---

## 4. Template Files (in `framework/templates/`)

### Design Governance Templates
- `framework/templates/design-brief.template.md`
- `framework/templates/design-revision-metadata.template.yaml`
- `framework/templates/design-change-request.template.md`

### QA Governance Templates
- `framework/templates/qa-contract.template.md`
- `framework/templates/qa-result.template.yaml`

### Human Decision Template
- `framework/templates/human-decision.template.yaml`

### Deployment Governance Templates
- `framework/templates/deployment-request.template.yaml`
- `framework/templates/deployment-result.template.yaml`

---

## 5. Product Repository Template Updates

### `framework/templates/product-repo/AGENTS.template.md`
- Add Design/QA/Deployment governance invariants
- Add path ownership for design/QA/deployment artifacts

### `framework/templates/product-repo/docs/engineering/WORK_STATE.template.md`
- Add Design Contract, QA Contract, Deployment Plan, Human Decisions sections

---

## 6. Junie/OpenCode Artifacts Updates

### New Agents (in `framework/templates/__brick__/.junie/agents/`)
- `design-agent.md` — Design Agent specialist
- `design-reviewer.md` — Independent Design Reviewer (read-only)
- `qa-architect.md` — QA Architect (defines strategy, contracts, baselines)
- `qa-executor.md` — QA Executor (runs QA, produces evidence)
- `deployment-authority.md` — Deployment Authority/Controller (executes deployments)

### New Skills (in `framework/templates/__brick__/.junie/skills/`)
- `design-workflow/SKILL.md` — Design lifecycle procedure
- `design-review/SKILL.md` — Independent design review checklist
- `qa-contract/SKILL.md` — QA Contract creation and validation
- `qa-execution/SKILL.md` — Automated/visual/human QA execution
- `human-decision/SKILL.md` — Human Decision object management
- `deployment-execution/SKILL.md` — Deployment plan execution and rollback

### Updated Command
- `framework/templates/__brick__/.junie/commands/run-feature.md` — Extended to orchestrate full lifecycle

---

## 7. Cross-Reference Updates

All documents must cross-reference each other correctly:
- WORKFLOW.md → DESIGN_GOVERNANCE.md, QA_GOVERNANCE.md, HUMAN_DECISIONS.md, DEPLOYMENT_GOVERNANCE.md, STRUCTURED_RESULTS.md
- AGENTS.md → all governance documents
- LEARNING_POLICY.md → new classification categories
- Templates → governing documents
- Junie agents/skills → governing documents and STRUCTURED_RESULTS.md

---

## 8. Verification Checklist (Post-Implementation)

After implementation, verify:
1. ✅ No contradictory lifecycle rules
2. ✅ No duplicate authorities (single Engineering Manager remains authoritative)
3. ✅ No specialist can bypass Engineering Manager
4. ✅ Design/QA/Deployment loops have explicit termination and escalation conditions
5. ✅ Unresolved architectural questions reported (not silently invented)
6. ✅ No application/platform runtime code created
7. ✅ Core governance remains technology-neutral
8. ✅ All cross-references resolve correctly
9. ✅ Templates are complete and usable
10. ✅ Structured result contracts are machine-readable and consistent