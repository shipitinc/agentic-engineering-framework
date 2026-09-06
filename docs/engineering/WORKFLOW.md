# WORKFLOW.md — Reusable Engineering Lifecycle

This document describes the **high-level, reusable lifecycle** governed by this framework. It is
intentionally kept at the level of *stages and gates*. It **does not** over-specify implementation
details that have not yet been tested. Unresolved areas are marked explicitly with
`UNRESOLVED_FRAMEWORK_AREA`.

Legend:
- `AUTO` — routine transition. The Orchestrator/Manager advances it without asking for
  permission **only after all prerequisites and required gates for that transition are satisfied**.
- `HUMAN_DECISION_REQUIRED` — a human gate for a consequential decision.
- `GATE` — a validation/approval checkpoint that must pass before proceeding.

### Automatic transitions vs. human gates (general rule)

These rules are authoritative wherever `AUTO`, `GATE`, and `HUMAN_DECISION_REQUIRED` appear:

- `AUTO` means the Manager advances the workflow without asking for routine permission **only after
  all prerequisites and required gates for that transition are satisfied**. An unsatisfied gate
  blocks the automatic transition.
- A state that explicitly requires `HUMAN_DECISION_REQUIRED` (or any other human authorization) can
  **never** be bypassed, skipped, or auto-resolved by an automatic transition.
- An agent **may automatically enter** a human-decision-required state when conditions require it
  (e.g., reaching a consequential architecture choice), but it **may not automatically resolve** that
  state; resolution requires the human decision. After the human decision is recorded, subsequent
  routine transitions may again proceed automatically.

---

## Lifecycle

### Phase 0: Foundation

1. **Product Requirements** `AUTO`
   Capture what the product must do. Produce a structured requirements artifact.

2. **Architecture Requirements Extraction** `AUTO`
   Derive architecture-relevant constraints and requirements from product requirements.

3. **Current Candidate Research** `AUTO`
   Research viable, current candidate technologies/approaches (BaaS vs. application backend,
   cloud/runtime providers, database, object storage, authentication, delivery topology, etc.).
   Research must reflect **current** information, not stale assumptions.

4. **Qualitative / Quantitative Analysis** `AUTO`
   Compare candidates on qualitative and quantitative criteria relevant to the product.

5. **Architecture Recommendation** `AUTO`
   Produce a recommendation with rationale and trade-offs.

6. **`HUMAN_DECISION_REQUIRED`** (where consequential) `GATE`
   Major architecture choices are human gates. Must be supported by current qualitative and
   quantitative research (steps 3–5).

7. **ADR (Architecture Decision Record)** `AUTO`
   Record the decision, context, options considered, and consequences.

8. **Git / Tooling / Cloud / Access Preflight** `GATE`
   Verify repository connectivity, CI/CD availability, infrastructure access, CLI availability,
   authentication and authorization **before** attempting bootstrap.

9. **Infrastructure Bootstrap** `AUTO` (may require `HUMAN_DECISION_REQUIRED` for provisioning)
   Stand up environments and infrastructure per the ADR.

10. **CI/CD and Deployment Bootstrap** `AUTO` (deployment authority may be a human gate)
    Establish pipelines, environments, deployment strategy, and rollback.

11. **Architecture Verification** `GATE`
    Confirm the bootstrapped architecture behaves as designed.

### Phase 1: Design Governance

12. **Design Brief Creation** `AUTO`
    Design Agent produces a **Design Brief** from requirements and architecture constraints.
    The Design Brief captures: problem statement, user flows, success criteria, constraints,
    acceptance criteria, and risk assessment.

13. **Design Brief Review** `GATE`
    Independent Design Reviewer evaluates the Design Brief for completeness, consistency,
    feasibility, and alignment with requirements/architecture.

14. **`HUMAN_DECISION_REQUIRED`** (Design Brief Approval) `GATE`
    Human approves the Design Brief for design exploration. Consequential design direction
    decisions are human gates.

15. **Design Exploration & Revision** `AUTO` (loop)
    Design Agent produces **Design Revisions** (candidate designs) iteratively.
    Each revision is versioned with metadata: revision number, author, timestamp, changelog,
    risk level assessment, and traceability to Design Brief requirements.

16. **Independent Design Review** `GATE`
    Independent Design Reviewer evaluates each Design Revision for:
    - Design system consistency (Level 1 risk)
    - UX coherence and accessibility (Level 2 risk)
    - Information architecture / workflow integrity (Level 3 risk)
    - Implementation feasibility

17. **Design Change Request (DCR) Process** `AUTO` / `HUMAN_DECISION_REQUIRED`
    - Level 0 (Implementation Correction): `AUTO` — routed to implementation lane
    - Level 1 (Design-System Correction): `AUTO` with design-system owner notification
    - Level 2 (Feature UX Change): `HUMAN_DECISION_REQUIRED` for product/design approval
    - Level 3 (Major Workflow/Navigation/IA Change): `HUMAN_DECISION_REQUIRED` with architecture review

18. **Approved Design Revision / Design Contract Freeze** `AUTO` (after gate passage)
    The approved Design Revision becomes the **Design Contract** — a frozen, versioned artifact
    that implementation must satisfy. Substantial UI changes require an approved Design Revision.
    Implementers must not invent consequential UX to fill design gaps.

19. **QA Contract Definition** `AUTO` (parallel with Design Contract)
    QA Architect defines the **QA Contract**: acceptance criteria, test strategy, automated/visual/
    human QA scope, golden baseline requirements, and evidence standards. Required before
    implementation completion.

### Phase 2: Implementation & Code Review

20. **Implementation** `AUTO`
    Implementers build against the Design Contract and QA Contract, declaring `OWNED_PATHS`,
    `READ_ONLY_PATHS`, and `PROHIBITED_PATHS`. Implementers never approve their own work.
    Implementation-discovered UI gaps route back into the design lifecycle via DCR.

21. **Deterministic Tests / Runtime / Browser Validation** `GATE`
    Required deterministic validation must pass. Runtime/browser evidence must correspond to the
    exact code revision under review.

22. **Independent Engineering Review** `GATE`
    An independent, read-only reviewer evaluates the implementation against:
    - Design Contract compliance
    - QA Contract test coverage
    - Architecture boundaries
    - Code quality and maintainability

23. **Correction / Re-review** `AUTO` (loop)
    Address findings and re-review until the gate passes. Bounded: after two failed cycles on
    the same substantive issue, classify and escalate if `HUMAN_DECISION_REQUIRED`.

### Phase 3: QA Governance

24. **Integration** `AUTO`
    Integrate approved work into the integration branch.

25. **Automated QA Deployment** `AUTO` (when project policy permits)
    Deploy to QA environment deterministically after integration.

26. **Automated QA Execution** `GATE`
    QA Executor runs: unit, integration, contract, e2e tests per QA Contract.
    Deterministic evidence is authoritative over reviewer opinion.

27. **Visual QA Execution** `GATE`
    QA Executor runs visual regression against golden baselines.
    Implementation agents **cannot approve changed visual golden baselines** — only QA Architect
    or Human QA can rebaseline.

28. **Human QA Execution** (when required) `HUMAN_DECISION_REQUIRED` / `GATE`
    Exploratory, usability, accessibility testing per QA Contract.
    QA artifacts must be preserved as evidence.

29. **QA Verdict & Failure Classification** `GATE`
    QA classifies any failure as exactly one of:
    - `IMPLEMENTATION_DEFECT` → route to correction lane
    - `DESIGN_DEFECT` → route to DCR (Design Change Request)
    - `REQUIREMENT_GAP` → route to requirements clarification (human gate)
    - `ENVIRONMENT_DEFECT` → route to infrastructure/environment remediation
    Regressions require regression tests before re-verification.

### Phase 4: Deployment Governance

30. **Merge** `AUTO`
    Merge to main/trunk branch after all QA gates pass.

31. **Staging Deployment** `AUTO` (when project policy permits)
    Deploy the **same immutable artifact** to staging. Build once, promote same artifact.

32. **Staging Validation** `GATE`
    Smoke tests, health checks, and staging-specific validation.

33. **Production Candidate Creation** `AUTO`
    Tag the validated artifact as a **Production Candidate** with full provenance:
    git SHA, build ID, test results, QA evidence, Design Contract version, migration plan.

34. **Pre-Deployment Validation** `GATE`
    Verify deployment plan, migration classification, rollback plan, and mobile API
    backward compatibility (old Android/iOS clients may remain installed).

35. **Migration Classification Review** `GATE`
    Classify each migration step:
    - `SAFE` — additive, backward-compatible
    - `RISKY` — schema changes, config changes requiring coordination
    - `DESTRUCTIVE` — data deletion, column drops, infrastructure destruction
    **Destructive production migrations always require human approval.**
    **Infrastructure destruction always requires human approval.**

36. **`HUMAN_DECISION_REQUIRED`** (Production Promotion) `GATE`
    Production promotion remains human-authorized unless a human-approved project policy
    explicitly changes that. Deployment Authority executes; coding agents never receive
    unrestricted production credentials.

37. **Deployment Execution** `AUTO` (by Deployment Authority)
    Deployment Authority/Controller executes the deployment plan.
    Automatic rollback prefers a known-good artifact rather than asking an AI to debug live production.

38. **Production Validation** `GATE`
    Verify the promoted release in production: health checks, synthetic transactions,
    key metrics, error rates, mobile client compatibility.

### Phase 5: Learning & Improvement

39. **Repository Learning** `AUTO`
    Persist verified discoveries per [LEARNING_POLICY.md](LEARNING_POLICY.md).

40. **Framework Improvement Candidates** (where generally reusable) `AUTO` → review
    Promote generally reusable lessons as framework improvement candidates. Material
    workflow-framework changes require independent review; consequential governance changes
    require human approval.

---

## Resolved framework areas

- **Distribution/versioning of framework artifacts to product repositories** — RESOLVED at the
  architecture level by [ADR 0001](adr/0001-framework-distribution-and-versioning.md):
  **versioned copy-based installation** with **deterministic provenance** (authoritative
  `framework.revision`, per-artifact install/source hashes) and **reviewable, isolated 3-way-merge
  upgrades** that preserve product-specific knowledge. Normal product operation requires **no**
  runtime access to the framework repository or any package registry.

- **Framework driver / tooling selection** — RESOLVED by
  [ADR 0002](adr/0002-dart-mason-git-framework-driver.md): the driver is
  **Dart + Mason + Git** with **`framework-manifest.yaml`** as authoritative provenance. Dart owns
  CLI/orchestration; Mason owns template rendering only; Git owns native 3-way merge/versioning
  mechanics; a **custom text merge engine is prohibited**. This selection was validated by an
  empirical proof-of-concept (`DART_MASON_GIT_POC_PASS`, no architecture blockers). ADR 0002 records
  the mandatory POC-derived mitigations, exit-code and structured-result contracts, and a phased
  implementation plan. The **production CLI is not yet implemented** — implementation is explicitly
  deferred to the phased plan (next state: Phase 1 CLI skeleton/domain model); the driver is **not**
  production-ready merely because the POC passed. See [framework/templates/](../../framework/templates/).

---

## Cross-References

This workflow is governed by and must be read in conjunction with:

- [AGENTS.md](../../AGENTS.md) — Repository-wide invariants and role authorities
- [DESIGN_GOVERNANCE.md](DESIGN_GOVERNANCE.md) — Design Agent, Design Reviewer, Design Brief, Design Revision, DCR, risk levels
- [QA_GOVERNANCE.md](QA_GOVERNANCE.md) — QA Architect, QA Executor, QA Contract, QA Result, failure classifications
- [HUMAN_DECISIONS.md](HUMAN_DECISIONS.md) — Human Decision objects, state persistence, structured question UI
- [DEPLOYMENT_GOVERNANCE.md](DEPLOYMENT_GOVERNANCE.md) — Staging, production candidates, deployment plans, migration classification, rollback
- [STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md) — Machine-readable result contracts for all roles and workflows
- [LEARNING_POLICY.md](LEARNING_POLICY.md) — Knowledge classification & authority

---

## Unresolved framework areas

These are explicitly **not** finalized and must not be treated as tested policy:

- `UNRESOLVED_FRAMEWORK_AREA`: Exact required deterministic validation gate set per project type.
- `UNRESOLVED_FRAMEWORK_AREA`: Ownership-conflict detection/enforcement mechanics for concurrent writers.
- `UNRESOLVED_FRAMEWORK_AREA`: Standard format and storage location for ADRs in product repos.
- `UNRESOLVED_FRAMEWORK_AREA`: Rollback and production-verification automation contracts.
- `UNRESOLVED_FRAMEWORK_AREA`: How runtime/browser evidence is pinned to and verified against a revision.
- `UNRESOLVED_FRAMEWORK_AREA`: Exact visual QA tooling and golden baseline storage strategy per project.
- `UNRESOLVED_FRAMEWORK_AREA`: Mobile API backward compatibility verification automation level.
- `UNRESOLVED_FRAMEWORK_AREA`: Deployment Authority identity and credential management mechanics.