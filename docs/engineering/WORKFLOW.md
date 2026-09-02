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

1. **Product requirements** `AUTO`
   Capture what the product must do.

2. **Architecture requirements extraction** `AUTO`
   Derive architecture-relevant constraints and requirements from product requirements.

3. **Current candidate research** `AUTO`
   Research viable, current candidate technologies/approaches (BaaS vs. application backend,
   cloud/runtime providers, database, object storage, authentication, delivery topology, etc.).
   Research must reflect **current** information, not stale assumptions.

4. **Qualitative / quantitative analysis** `AUTO`
   Compare candidates on qualitative and quantitative criteria relevant to the product.

5. **Architecture recommendation** `AUTO`
   Produce a recommendation with rationale and trade-offs.

6. **`HUMAN_DECISION_REQUIRED`** (where consequential) `GATE`
   Major architecture choices are human gates. Must be supported by current qualitative and
   quantitative research (steps 3–5).

7. **ADR (Architecture Decision Record)** `AUTO`
   Record the decision, context, options considered, and consequences.

8. **Git / tooling / cloud / access preflight** `GATE`
   Verify repository connectivity, CI/CD availability, infrastructure access, CLI availability,
   authentication and authorization **before** attempting bootstrap.

9. **Infrastructure bootstrap** `AUTO` (may require `HUMAN_DECISION_REQUIRED` for provisioning)
   Stand up environments and infrastructure per the ADR.

10. **CI/CD and deployment bootstrap** `AUTO` (deployment authority may be a human gate)
    Establish pipelines, environments, deployment strategy, and rollback.

11. **Architecture verification** `GATE`
    Confirm the bootstrapped architecture behaves as designed.

12. **UI / design generation** `AUTO`
    Generate candidate UI/design.

13. **Human design inspection** `HUMAN_DECISION_REQUIRED`
    A human reviews the generated design.

14. **Independent design review** `GATE`
    An independent (read-only) reviewer evaluates the design.

15. **Design Contract** `AUTO`
    Freeze the agreed design as a contract that implementation must satisfy.

16. **Implementation** `AUTO`
    Implementers build against the Design Contract, declaring `OWNED_PATHS`, `READ_ONLY_PATHS`,
    and `PROHIBITED_PATHS`. Implementers never approve their own work.

17. **Deterministic tests / runtime / browser validation** `GATE`
    Required deterministic validation must pass. Runtime/browser evidence must correspond to the
    exact code revision under review.

18. **Independent engineering review** `GATE`
    An independent, read-only reviewer evaluates the implementation.

19. **Correction / re-review** `AUTO` (loop)
    Address findings and re-review until the gate passes.

20. **Integration** `AUTO`
    Integrate approved work.

21. **Automatic QA deployment** `AUTO` (when project policy permits)
    QA deployment is normally deterministic and automated after integration.

22. **QA acceptance** `GATE`
    Validate against acceptance criteria in QA.

23. **Human production promotion** `HUMAN_DECISION_REQUIRED`
    Production promotion remains human-authorized unless a human-approved project policy explicitly
    changes that.

24. **Production verification** `GATE`
    Verify the promoted release in production.

25. **Repository learning** `AUTO`
    Persist verified discoveries per [LEARNING_POLICY.md](LEARNING_POLICY.md).

26. **Framework improvement candidates** (where generally reusable) `AUTO` → review
    Promote generally reusable lessons as framework improvement candidates. Material
    workflow-framework changes require independent review; consequential governance changes require
    human approval.

---

## Unresolved framework areas

These are explicitly **not** finalized and must not be treated as tested policy:

- `UNRESOLVED_FRAMEWORK_AREA`: Concrete mechanism for distributing/versioning framework artifacts to
  product repositories (pull vs. push, pinning strategy). See [framework/templates/](../../framework/templates/).
- `UNRESOLVED_FRAMEWORK_AREA`: Exact required deterministic validation gate set per project type.
- `UNRESOLVED_FRAMEWORK_AREA`: Ownership-conflict detection/enforcement mechanics for concurrent writers.
- `UNRESOLVED_FRAMEWORK_AREA`: Standard format and storage location for ADRs in product repos.
- `UNRESOLVED_FRAMEWORK_AREA`: Rollback and production-verification automation contracts.
- `UNRESOLVED_FRAMEWORK_AREA`: How runtime/browser evidence is pinned to and verified against a revision.
