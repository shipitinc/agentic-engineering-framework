---
name: deployment-execution
description: Procedure for deployment execution and rollback in this framework — validate pre-deployment checks, execute deployment plan, monitor health, trigger automatic rollback to known-good artifact. Use when deploying to staging or production.
---

# Deployment Execution Workflow

Use this skill when executing deployments in the Deployment Authority lane. It encodes the
non-negotiable discipline required by `AGENTS.md`, `docs/engineering/WORKFLOW.md`,
and `docs/engineering/DEPLOYMENT_GOVERNANCE.md`.

## 1. Declare ownership before writing

Before editing anything, declare explicitly:

- `OWNED_PATHS` — the only paths you may create/modify (deployment configs, scripts, manifests, execution logs, rollback artifacts).
- `READ_ONLY_PATHS` — paths you may read but must not change (Production Candidates, Deployment Requests, QA Results, build artifacts).
- `PROHIBITED_PATHS` — paths you must never touch (implementation source, design artifacts, QA test code, golden baselines).

Ownership must not overlap with any concurrent writer.

## 2. Pre-deployment validation (mandatory)

Before executing ANY deployment step, verify all pre-deployment checks in Deployment Request:

- **Migration Classification Review**: All steps classified (SAFE/RISKY/DESTRUCTIVE). DESTRUCTIVE steps have Human Decision approval.
- **Rollback Plan Validated**: Rollback steps defined, target known-good artifact referenced, max rollback time bounded.
- **Mobile API Backward Compatibility**: Documented in Deployment Request. Versioned endpoints, deprecation timeline, min client versions.
- **Infrastructure Destruction Review**: Any DESTRUCTIVE infra steps have Human Decision approval.

**Do not proceed if any check is `FAIL` or `PENDING` without Human Decision.**

## 3. Build once, promote same artifact

- Deploy the **exact same Production Candidate** (immutable artifact) that passed QA.
- Verify artifact digest/hash at each promotion (staging → production).
- No rebuilds between environments.

## 4. Deployment execution

- Execute Deployment Plan steps in declared order (respecting `depends_on`).
- Monitor real-time: health checks, metrics, logs.
- Record each step: `step_id`, `status`, `started_at`, `completed_at`, `output`, `evidence_refs`.
- **Coding agents never execute production deployments** — only Deployment Authority.

## 5. Automatic rollback (prefers known-good artifact)

Rollback triggers on objective criteria (configured in Deployment Request):
- Health check failure
- Error rate threshold exceeded
- Synthetic transaction failure
- Key metric degradation

**Rollback behavior**:
- Automatically deploys last known-good Production Candidate.
- Does **not** ask AI to debug live production.
- Maximum rollback time bounded (configured in Deployment Request).
- Records `rollback_triggered: true`, `rollback_reason`, `rollback_result`.

## 6. Post-deployment validation

After deployment execution reports `SUCCESS`:
- Health checks (liveness, readiness)
- Synthetic transactions (critical user flows)
- Key metrics (latency, throughput, error rate, business metrics)
- Error rates (application, infrastructure)
- Mobile client compatibility (API version negotiation, feature flags)

## 7. Credential boundary

- **Deployment Authority holds production credentials** — separate identity/role.
- Coding agents (implementers, designers, QA) **never receive unrestricted production credentials**.
- Deployment execution is a distinct, auditable step from implementation.

## 8. Report exact provenance

Every result must include `request_id`, `candidate_id`, `target_environment`, `executed_by`,
duration, steps executed, rollback info, validation results. Provenance verifiable by Manager.

## 9. No placeholder completion claims

- `RESULT: DEPLOYMENT_SUCCESSFUL` means all validation checks pass.
- `RESULT: DEPLOYMENT_ROLLED_BACK` means automatic rollback executed and known-good restored.
- `RESULT: DEPLOYMENT_FAILED` / `PARTIAL` with evidence — never a false green.

## 10. Classify durable discoveries

Before finishing, apply the `repository-learning` skill to classify and persist durable findings.
Categories: `DEPLOYMENT_DISCOVERY`, `HUMAN_DECISION_RECORD`.