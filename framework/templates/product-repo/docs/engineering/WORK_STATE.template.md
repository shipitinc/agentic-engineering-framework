# WORK_STATE.md — Product Repository (instantiated from framework)

<!--
  PLACEHOLDER TEMPLATE.
  Describes the state of the PRODUCT repository. Product-specific architecture, design, and
  infrastructure decisions DO belong here (and in the product's ADRs) — not in the framework repo.
-->

## Current state

- Status: TBD (e.g., REQUIREMENTS, ARCHITECTURE, IMPLEMENTATION, QA, PRODUCTION)
- Active workflow orchestrator: TBD
- Current lifecycle step (see framework WORKFLOW): TBD

## Architecture

- Decision record(s): TBD (link ADRs)

## Design

- Design Contract: TBD

## Infrastructure / CI-CD / Deployment

- Environments: TBD
- Deployment strategy & rollback: TBD

## Framework provenance

- Framework revision (authoritative): TBD
- Framework version (human-readable metadata): TBD
- Recorded in this product repo's `framework-manifest.yaml` (the instantiated copy of the
  framework-side source template `manifest.template.yaml`). The manifest stores **provenance only**
  plus per-artifact baseline hashes; local modifications are **derived** from hash comparison.
  Upgrades are reviewable, isolated 3-way merges with no runtime dependency on the framework repo.
