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
  - [framework/templates/](../../framework/templates/) — minimal placeholder structure.

## Recorded framework decisions

- **Distribution/versioning architecture (ADR 0001):** versioned **copy-based** installation with
  **deterministic provenance** (authoritative `framework.revision`, per-artifact install/source
  hashes, no persisted `locally_modified` flag) and **reviewable, isolated 3-way-merge** upgrades
  that preserve product-specific knowledge. Provenance and any template answers are kept separate;
  normal product operation requires **no** runtime access to this framework repo or a registry.
  - **Deferred (not decided):** the concrete framework **driver/tool** (e.g., Copier vs. a
    custom/thin driver), and any bootstrap CLI, release system, tags, or package distribution.

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

- Select the framework **driver/tool** for the copy-based distribution model (deferred by ADR 0001),
  then implement bootstrap/upgrade tooling.
- Resolve the remaining `UNRESOLVED_FRAMEWORK_AREA` items in [WORKFLOW.md](WORKFLOW.md).
- Flesh out [framework/templates/](../../framework/templates/) once the driver/tool is chosen.
- Material workflow-framework changes require independent review; consequential governance changes
  require human approval.
