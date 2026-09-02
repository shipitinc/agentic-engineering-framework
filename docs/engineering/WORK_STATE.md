# WORK_STATE.md — State of THIS Framework Repository

This file describes **only the state of this framework repository**. It intentionally contains **no**
product-specific architecture, design, or infrastructure decisions — those belong in the respective
**product repositories**, not here.

---

## Current state

- **Status:** `FRAMEWORK_BOOTSTRAP_IN_PROGRESS`
- **Scope of this repo:** canonical, reusable agentic engineering framework (policy, lifecycle,
  learning policy, and templates). This repository is **not** an application.
- **What exists now:**
  - [AGENTS.md](../../AGENTS.md) — repository-wide invariants.
  - [WORKFLOW.md](WORKFLOW.md) — reusable lifecycle (with resolved and still-unresolved areas).
  - [LEARNING_POLICY.md](LEARNING_POLICY.md) — knowledge classification & authority.
  - [adr/0001-framework-distribution-and-versioning.md](adr/0001-framework-distribution-and-versioning.md)
    — framework distribution/versioning architecture decision.
  - [adr/0002-dart-mason-git-framework-driver.md](adr/0002-dart-mason-git-framework-driver.md)
    — framework driver/tooling selection (Dart + Mason + Git).
  - [framework/templates/](../../framework/templates/) — minimal placeholder structure.

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
  - **POC passed.** The driver is **not** production-ready merely because the POC passed. No
    packages, releases, tags, CI, Mason bricks, or product repos were created.
  - **Phase 1 (CLI skeleton + domain model) IMPLEMENTED and independently APPROVED.** Delivered
    through the autonomous orchestration loop (implement → independent review → merge-readiness) in an
    isolated worktree (`feature/phase1-cli`, base `572b3d14`); `cli/**` package with structured
    result families, `--json` output, and centralized semantic exit categories. Gates green:
    `dart format`, `dart analyze`, `dart test` (25/25), `dart compile exe`. State:
    `MERGE_APPROVED` / `READY_FOR_INTEGRATION` — **held, unpushed**, pending explicit integration
    authorization. **Next state:** Phase 2 (manifest + hashing).
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

## Pending plan artifact cleanup (approved, not yet executed)

The following **final dispositions** were human-approved for the three plan artifacts already
classified under the retention policy above. **Not yet executed** — the files remain untracked and
unmodified pending an explicit follow-up task to carry out the deletion.

- `.air/plans/independent-review-framework-bootstrap.plan.md` — classification=`SUPPORTING_PLAN`,
  final_disposition=`DELETE_AFTER_POLICY_APPROVAL_AND_REVIEW`.
- `.junie/plans/independent-review-framework-bootstrap.md` — classification=`DUPLICATE_ARTIFACT`,
  final_disposition=`DELETE_AFTER_POLICY_APPROVAL_AND_REVIEW`.
- `.junie/plans/framework-artifact-distribution-architecture.md` — classification=`SUPPORTING_PLAN`,
  final_disposition=`DELETE_AFTER_POLICY_APPROVAL_AND_REVIEW` (durable conclusions already fully
  captured in ADR 0001 and this file's own "Recorded framework decisions" entry above).

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

## Next steps for the framework itself

- **Phase 1 is done** (CLI skeleton + domain model, structured output, exit-code semantics; stubs
  only, no real bootstrap/update). It is `MERGE_APPROVED` and held unpushed in `feature/phase1-cli`
  pending explicit integration authorization.
- **Begin Phase 2** of the ADR 0002 implementation plan (manifest + hashing) on new files, with no
  ownership overlap with the held Phase 1 `cli/lib/src` paths.
- Resolve the remaining `UNRESOLVED_FRAMEWORK_AREA` items in [WORKFLOW.md](WORKFLOW.md).
- Flesh out [framework/templates/](../../framework/templates/) as Mason bricks during the phased
  implementation (ADR 0002).
- Material workflow-framework changes require independent review; consequential governance changes
  require human approval.
