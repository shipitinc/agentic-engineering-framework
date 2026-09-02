# AGENTS.md — Product Repository (instantiated from framework)

<!--
  PLACEHOLDER TEMPLATE.
  This is instantiated into a PRODUCT repository from the canonical framework.
  Fill in product-specific values. Do NOT depend on the framework repo at runtime.
  Record the producing framework version in this product repo's `framework-manifest.yaml`
  (the instantiated copy of the framework-side source template `manifest.template.yaml`).
-->

This product repository is governed by a **versioned copy** of the agentic engineering framework.

## Inherited invariants (from framework)

- One authoritative Engineering Manager / Orchestrator per active workflow.
- Specialists do not independently advance lifecycle state.
- Implementers never approve their own work; independent reviewers are read-only.
- Production-writing agents declare `OWNED_PATHS`, `READ_ONLY_PATHS`, `PROHIBITED_PATHS`;
  concurrent writers cannot have overlapping ownership.
- Required deterministic validation must pass before success is claimed.
- Runtime/browser evidence must correspond to the exact code revision under review.
- Human intervention is reserved for consequential decisions (product, architecture, design,
  security, infrastructure, destructive operations, deployment authority).
- Production promotion is human-authorized unless a human-approved project policy changes that.

## Product-specific policy (fill in)

- Required validation gates: TBD
- Environments & deployment strategy: TBD
- Path ownership map: TBD

## Framework provenance

- Framework revision: TBD — the **authoritative, immutable** provenance identifier.
- Framework version: TBD — human-readable metadata only (revision controls provenance if they differ).
- Both are recorded in this product repo's `framework-manifest.yaml` (the instantiated copy of the
  framework-side source template `manifest.template.yaml`), which stores **provenance only** plus
  per-artifact baseline hashes. Framework upgrades arrive as **reviewable, isolated 3-way-merge**
  changes and must **not** create a runtime dependency on the framework repo. See the framework's
  ADR 0001 (`docs/engineering/adr/0001-framework-distribution-and-versioning.md`).
