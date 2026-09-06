# WORK_STATE.md — Product Repository (instantiated from framework)

<!--
  PLACEHOLDER TEMPLATE.
  Describes the state of the PRODUCT repository. Product-specific architecture, design, and
  infrastructure decisions DO belong here (and in the product's ADRs) — not in the framework repo.
-->

## Current state

- Status: TBD (e.g., REQUIREMENTS, ARCHITECTURE, DESIGN, DESIGN_REVIEW, IMPLEMENTATION, CODE_REVIEW, QA, STAGING, PRODUCTION_APPROVAL, DEPLOYMENT, PRODUCTION_VALIDATION)
- Active workflow orchestrator: TBD
- Current lifecycle step (see framework WORKFLOW): TBD

## Architecture

- Decision record(s): TBD (link ADRs)

## Design

- Design Brief: TBD (link Design Brief artifact)
- Design Revisions: TBD (list revision IDs and statuses)
- Design Contract: TBD (link frozen Design Contract)
- Active DCRs: TBD (list DCR IDs and statuses)

## QA

- QA Contract: TBD (link frozen QA Contract)
- QA Results: TBD (list QA Result IDs, types, and verdicts)
- Golden Baselines: TBD (list baseline IDs and approval status)
- Human QA Required: TBD (YES/NO, with charter reference if YES)

## Human Decisions

- Pending Decisions: TBD (list Human Decision IDs, types, blocking items)
- Resolved Decisions: TBD (list Human Decision IDs with resolutions)
- Decision Archive: TBD (location of persisted Human Decision objects)

## Deployment

- Production Candidates: TBD (list candidate IDs, statuses, source revisions)
- Active Deployment Request: TBD (Deployment Request ID, target environment, status)
- Deployment History: TBD (list completed deployments with results)
- Rollback Plan: TBD (reference to current rollback plan)

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