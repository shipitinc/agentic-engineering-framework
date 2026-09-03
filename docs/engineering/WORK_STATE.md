# WORK_STATE.md — State of THIS Framework Repository

This file describes **only the state of this framework repository**. It intentionally contains **no**
product-specific architecture, design, or infrastructure decisions — those belong in the respective
**product repositories**, not here.

---

## Current state

- **Status:** `FRAMEWORK_COMPLETE`
- **Scope of this repo:** canonical, reusable agentic engineering framework (policy, lifecycle,
  learning policy, and templates). This repository is **not** an application.
- **What exists now:**
  - [AGENTS.md](../../AGENTS.md) — repository-wide invariants.
  - [WORKFLOW.md](WORKFLOW.md) — reusable lifecycle (with resolved and unresolved areas).
  - [LEARNING_POLICY.md](LEARNING_POLICY.md) — knowledge classification & authority.
  - [adr/0001-framework-distribution-and-versioning.md](adr/0001-framework-distribution-and-versioning.md)
    — framework distribution/versioning architecture decision.
  - [adr/0002-dart-mason-git-framework-driver.md](adr/0002-dart-mason-git-framework-driver.md)
    — framework driver/tooling selection (Dart + Mason + Git).
  - [framework/templates/](../../framework/templates/) — Mason bricks and product-repo templates.

## Recorded framework decisions

- **Distribution/versioning architecture (ADR 0001):** versioned **copy-based** installation with
  **deterministic provenance** (authoritative `framework.revision`, per-artifact install/source
  hashes, no persisted `locally_modified` flag) and **reviewable, isolated 3-way-merge** upgrades
  that preserve product-specific knowledge. Provenance and any template answers are kept separate;
  normal product operation requires **no** runtime access to this framework repo or a registry.
- **Framework driver/tool selection (ADR 0002):** the driver is **Dart + Mason + Git** with
  **`framework-manifest.yaml`** as authoritative provenance. **Dart** owns CLI/orchestration;
  **Mason** owns template rendering only (non-authoritative metadata); **Git** owns native 3-way
  merge/versioning mechanics; a **custom text merge engine is prohibited**. This was validated by an
  empirical proof-of-concept (`DART_MASON_GIT_POC_PASS`, all pass criteria met, **no architecture
  blockers**). ADR 0002 records the mandatory POC-derived mitigations, the exit-code and
  structured-result contracts, and an 8-phase implementation plan.
  - **All phases 3-8 complete.** The framework driver is implemented and production-authorized
    through the autonomous orchestration loop (implement → independent review → correction →
    integrate). All gates green: `dart format`, `dart analyze`, `dart test` (60/60), `dart compile
    exe`. Production promotion authorized via human decision recorded in commit `4ca8094`.
  - **Exit-code contract extension ratified (human-approved):** `NOT_IMPLEMENTED = 50` added to the
    ADR 0002 exit-code contract (`ARCHITECTURE_DISCOVERY` surfaced by the Phase 1 implementer /
    independent reviewer). Gives stub commands an unambiguous, non-zero, non-colliding semantic so a
    stub can never be mistaken for `SUCCESS`.

- **Plan artifact retention policy (APPROVED WITH REFINEMENT):** agent-generated plan artifacts
  (`.air/plans/`, `.junie/plans/`, or equivalent) are **visible/versionable but not automatically
  committed** by default. See [LEARNING_POLICY.md — Plan artifact retention
  policy](LEARNING_POLICY.md#plan-artifact-retention-policy) for the full classification model
  (`AUTHORITATIVE_PLAN`, `SUPPORTING_PLAN`, `AUDIT_ARTIFACT`, `PROMOTION_REQUIRED`, `TRANSIENT_PLAN`,
  `DUPLICATE_ARTIFACT`) and commit/promote/delete criteria. Policy is tool-neutral (classifies by
  information authority, not artifact origin). **Refinement:** `LEAVE_UNTRACKED` is an interim
  working state only, never a permanent disposition — every untracked plan must eventually be
  intentionally finalized to `COMMIT`, `PROMOTE_THEN_DELETE`, or `DELETE` unless its originating
  work/review cycle is still active.

## Plan artifact cleanup completed

The three plan artifacts previously classified under the retention policy have been finalized
per their approved dispositions:

- `.air/plans/independent-review-framework-bootstrap.plan.md` — classification=`SUPPORTING_PLAN`,
  final_disposition=`DELETE_AFTER_POLICY_APPROVAL_AND_REVIEW` — **deleted**.
- `.junie/plans/independent-review-framework-bootstrap.md` — classification=`DUPLICATE_ARTIFACT`,
  final_disposition=`DELETE_AFTER_POLICY_APPROVAL_AND_REVIEW` — **deleted**.
- `.junie/plans/framework-artifact-distribution-architecture.md` — classification=`SUPPORTING_PLAN`,
  final_disposition=`DELETE_AFTER_POLICY_APPROVAL_AND_REVIEW` — **deleted** (durable conclusions
  already fully captured in ADR 0001 and this file's own "Recorded framework decisions" entry above).

## Explicitly out of scope for this repository

- Product-specific **architecture** decisions (belong in product repos + their ADRs).
- Product-specific **design** decisions and Design Contracts.
- Product-specific **infrastructure**, environments, CI/CD, and deployment configuration.

## Verified repository/environment facts (evidence-backed)

- This is a valid Git repository on branch `main` with **no commits yet** at bootstrap time.
- Remote `origin` is configured: `https://github.com/shipitinc/agentic-engineering-framework.git`.
- Remote is **reachable** and Git authentication appears **sufficient** for fetch workflows
  (`git ls-remote` / `git fetch --dry-run` succeeded without credential prompts). The remote had no
  refs at bootstrap time (empty upstream).
- No pushes, remote resources, or destructive Git operations were performed during bootstrap.
- **Canonical revision:** `4ca80945b468d8044e7a0e143a28870a41fb5f7c` — all phases 3-8 implemented
  and production-authorized.

## Next steps for the framework itself

- **Framework complete** (Phases 3-8). No further phase implementation required.
- **Prepare first product bootstrap** using the canonical framework and its neutral governance
  contracts, runtime adapters, and product-repo templates.
- Resolve the remaining `UNRESOLVED_FRAMEWORK_AREA` items in [WORKFLOW.md](WORKFLOW.md) if
  desired for future refinement.
- Flesh out [framework/templates/](../../framework/templates/) as Mason bricks during future
  phased implementation.
- Material workflow-framework changes require independent review; consequential governance changes
  require human approval.