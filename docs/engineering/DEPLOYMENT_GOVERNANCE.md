# DEPLOYMENT_GOVERNANCE.md — Deployment Governance Policy

This document defines the governance framework for deployment activities within the agentic
engineering lifecycle. It establishes roles, artifacts, processes, and gates that ensure safe,
auditable, and reversible deployments with clear separation between deployment authority and
implementation agents.

---

## Roles

### Deployment Authority / Controller
- **Authority**: Sole executor of production deployments. Holds production credentials.
- **Responsibilities**:
  - Execute Deployment Plans against staging and production.
  - Validate pre-deployment checks (migration classification, rollback plan, mobile API compatibility).
  - Trigger automatic rollback on production validation failure.
  - Maintain deployment audit trail.
  - Hold and rotate production credentials (coding agents **never** receive unrestricted production credentials).
- **Constraints**:
  - Does not write implementation code.
  - Does not define QA strategy or design.
  - Read-only access to implementation artifacts (builds, manifests).
  - Must declare `OWNED_PATHS` (deployment configs, scripts, manifests), `READ_ONLY_PATHS` (build artifacts, QA results, Design/QA Contracts), `PROHIBITED_PATHS` (implementation source, design artifacts).

### Release Engineer (Optional Specialist)
- **Authority**: Prepares Deployment Requests and validates Production Candidates.
- **Responsibilities**:
  - Assemble Production Candidates from successful QA runs.
  - Create Deployment Requests with full provenance.
  - Validate migration classifications and rollback plans.
  - Coordinate with Deployment Authority for execution.
- **Constraints**:
  - Does not execute production deployments.
  - Does not hold production credentials.
  - Must declare `OWNED_PATHS` (deployment requests, release notes), `READ_ONLY_PATHS` (build artifacts, QA results), `PROHIBITED_PATHS` (production credentials, implementation source).

---

## Artifacts

### Production Candidate
**Purpose**: An immutable, versioned artifact that has passed all QA gates and is eligible for
promotion to staging/production. **Build once, promote the same artifact.**

**Properties**:
- `candidate_id`: UUID
- `source_revision`: git SHA (exact commit)
- `build_id`: CI/CD build identifier
- `build_artifact_location`: immutable storage reference (e.g., container image digest, binary hash)
- `design_contract_version`: Design Contract ID + version
- `qa_contract_version`: QA Contract ID + version
- `qa_result_refs`: array of QA Result IDs (automated, visual, human)
- `gate_results`: summary of all passed gates
- `migration_plan_ref`: Deployment Request ID
- `created_at`: ISO8601 timestamp
- `created_by`: Release Engineer or Engineering Manager
- `status`: `CANDIDATE` | `STAGING_VALIDATED` | `PRODUCTION_APPROVED` | `DEPLOYED` | `ROLLED_BACK` | `REJECTED`

**Immutability**: Once created, a Production Candidate never changes. A new candidate requires a new build.

### Deployment Request
**Purpose**: Formal request to deploy a Production Candidate to a target environment, containing the
complete deployment plan, migration classification, and rollback strategy.

**Lifecycle**: Created → Reviewed → Human-Approved (if required) → Executed.

**Required Fields** (`deployment-request.yaml`):
```yaml
request_id: UUID
candidate_id: UUID (references Production Candidate)
target_environment: STAGING | PRODUCTION
deployment_strategy: BLUE_GREEN | ROLLING | CANARY | RECREATE | HELM | TERRAFORM | CUSTOM
deployment_plan:
  steps:
    - step_id: string
      description: string
      type: MIGRATION | CONFIG_CHANGE | SERVICE_DEPLOY | HEALTH_CHECK | SMOKE_TEST | VALIDATION
      migration_classification: SAFE | RISKY | DESTRUCTIVE
      migration_details: string
      rollback_step: string (reference to rollback plan step)
      estimated_duration_seconds: integer
      depends_on: array of step_ids
  rollback_plan:
    trigger_conditions: array of conditions (e.g., "error_rate > 5%", "health_check_failed")
    steps:
      - step_id: string
        description: string
        type: REVERT_DEPLOYMENT | REVERT_MIGRATION | REVERT_CONFIG | TRAFFIC_SWITCH
        target_artifact: string (known-good artifact reference)
        estimated_duration_seconds: integer
    max_rollback_time_seconds: integer
    prefers_known_good_artifact: true  # Automatic rollback prefers known-good artifact over AI debugging
pre_deployment_checks:
  - check: MIGRATION_CLASSIFICATION_REVIEW
    status: PASS | PENDING | FAIL
  - check: ROLBACK_PLAN_VALIDATED
    status: PASS | PENDING | FAIL
  - check: MOBILE_API_BACKWARD_COMPATIBILITY
    status: PASS | PENDING | FAIL | NOT_APPLICABLE
    details: string (e.g., "Android min version 2.1.0, iOS min version 2.1.0 supported")
  - check: INFRASTRUCTURE_DESTRUCTION_REVIEW
    status: PASS | PENDING | FAIL | NOT_APPLICABLE
    details: string
human_approval_required: boolean
human_approval_ref: string (Human Decision ID if required)
created_by: string (Release Engineer / Manager)
created_at: ISO8601 timestamp
reviewed_by: string
reviewed_at: ISO8601 timestamp
approved_by: string (Human Decision maker if required)
approved_at: ISO8601 timestamp
status: DRAFT | UNDER_REVIEW | APPROVED | EXECUTING | COMPLETED | FAILED | ROLLED_BACK
```

### Deployment Result
**Purpose**: Machine-readable record of deployment execution outcome.

**Required Fields** (`deployment-result.yaml`):
```yaml
result_id: UUID
request_id: UUID (references Deployment Request)
candidate_id: UUID
target_environment: STAGING | PRODUCTION
executed_by: string (Deployment Authority ID)
executed_at: ISO8601 timestamp
duration_seconds: integer
status: SUCCESS | FAILED | ROLLED_BACK | PARTIAL
steps_executed:
  - step_id: string
    status: SUCCESS | FAILED | SKIPPED
    started_at: ISO8601 timestamp
    completed_at: ISO8601 timestamp
    output: string
    evidence_refs: array of log/metric URLs
rollback_triggered: boolean
rollback_reason: string (if triggered)
rollback_result: SUCCESS | FAILED | PARTIAL
post_deployment_validation:
  health_checks: PASS | FAIL
  synthetic_transactions: PASS | FAIL
  key_metrics: PASS | FAIL
  error_rates: PASS | FAIL
  mobile_compatibility: PASS | FAIL | NOT_APPLICABLE
overall_verdict: DEPLOYMENT_SUCCESSFUL | ROLLED_BACK | REQUIRES_INTERVENTION
```

---

## Migration Classification

Every deployment migration step **must** be classified as exactly one of:

| Classification | Definition | Examples | Approval Required |
|----------------|------------|----------|-------------------|
| `SAFE` | Additive, backward-compatible, no data risk | New column (nullable), new table, new service, feature flag addition, config addition | `AUTO` (reviewed in pre-deployment checks) |
| `RISKY` | Schema changes requiring coordination, config changes with blast radius | Column type change, index creation on large table, config change affecting multiple services, API version bump | `AUTO` with enhanced validation; human notification |
| `DESTRUCTIVE` | Data deletion, irreversible schema changes, infrastructure destruction | Column drop, table drop, data deletion, service decommission, cluster teardown, DNS record removal | **`HUMAN_DECISION_REQUIRED` — always** |

**Rules**:
- Classification is proposed by Release Engineer, validated by Deployment Authority.
- `DESTRUCTIVE` migrations **always** require a Human Decision (HUMAN_DECISIONS.md).
- Infrastructure destruction (cluster teardown, database deletion, etc.) **always** requires Human Decision.
- Migration classification is recorded in Deployment Request and immutable after approval.

---

## Deployment Principles

### Build Once, Promote Same Artifact
- The exact same build artifact (container image, binary, bundle) that passed QA is deployed to
  staging and production.
- No rebuilds between environments.
- Artifact integrity verified via digest/hash at each promotion.

### Immutable Artifacts
- Production Candidates are immutable once created.
- Configuration is injected at deploy time via environment-specific configs (not baked into artifact).
- Secrets are injected at runtime from secret manager (never in artifact).

### Separation of Deployment Authority
- **Coding agents (implementers, designers, QA) never receive unrestricted production credentials**.
- Deployment Authority is a separate role/identity with its own credential scope.
- Deployment execution is a distinct step from implementation/QA.

### Automatic Rollback Prefers Known-Good Artifact
- On production validation failure, rollback **automatically** deploys the last known-good
  Production Candidate.
- The system **does not** ask an AI to debug live production.
- Rollback is triggered by objective criteria (health checks, error rates, synthetic transactions).
- Maximum rollback time is bounded (configured in Deployment Request).

### Mobile API Backward Compatibility
- **Old Android and iOS clients may remain installed after backend deployment.**
- Every Deployment Request must include a `MOBILE_API_BACKWARD_COMPATIBILITY` check.
- Breaking API changes require:
  - Versioned API endpoints (e.g., `/v2/...` alongside `/v1/...`)
  - Deprecation timeline communicated to mobile teams
  - Minimum supported client version documented
  - Rollback plan that restores old API version

---

## Process Gates

### Gate P1: Production Candidate Creation
- **Trigger**: All QA gates pass (WORKFLOW.md step 29).
- **Authority**: Engineering Manager / Release Engineer.
- **Criteria**: QA Results all `PASS`; Design Contract + QA Contract traceability complete; build artifact immutable.
- **Output**: `PRODUCTION_CANDIDATE_CREATED` with full provenance.

### Gate P2: Staging Deployment
- **Trigger**: Production Candidate created.
- **Authority**: Deployment Authority (automated when project policy permits).
- **Action**: Deploy candidate to staging using Deployment Request (staging variant).
- **Validation**: Smoke tests, health checks, staging-specific validation.
- **Output**: `STAGING_VALIDATED` candidate status.

### Gate P3: Pre-Deployment Validation (Production)
- **Trigger**: Staging validation passes; production promotion requested.
- **Authority**: Engineering Manager + Deployment Authority review.
- **Checks**:
  - Migration Classification Review (all steps classified, `DESTRUCTIVE` flagged)
  - Rollback Plan Validated (tested in staging or verified against known-good)
  - Mobile API Backward Compatibility (documented, versioned, deprecation plan)
  - Infrastructure Destruction Review (if any `DESTRUCTIVE` infra steps)
- **Output**: `PRE_DEPLOYMENT_VALIDATED` or `BLOCKED` with specific failures.

### Gate P4: Human Production Approval
- **Trigger**: Pre-deployment validation passes.
- **Authority**: Human (via Human Decision object, HUMAN_DECISIONS.md).
- **Type**: `DEPLOYMENT_AUTHORITY` decision.
- **Context**: Deployment Request, Production Candidate, QA evidence, migration plan, rollback plan.
- **Output**: `APPROVED` → proceed to execution; `REJECTED` → candidate rejected, feedback to team.

### Gate P5: Deployment Execution
- **Trigger**: Human approval (or auto if project policy permits and no `DESTRUCTIVE` migrations).
- **Authority**: Deployment Authority **only**.
- **Action**: Execute Deployment Plan steps in order.
- **Monitoring**: Real-time health checks, metrics, logs.
- **Rollback Trigger**: Automatic on validation failure; manual override by Deployment Authority.

### Gate P6: Production Validation
- **Trigger**: Deployment execution reports `SUCCESS`.
- **Authority**: Deployment Authority + Engineering Manager (automated checks).
- **Checks**:
  - Health checks (liveness, readiness)
  - Synthetic transactions (critical user flows)
  - Key metrics (latency, throughput, error rate, business metrics)
  - Error rates (application, infrastructure)
  - Mobile client compatibility (API version negotiation, feature flags)
- **Output**: `DEPLOYMENT_SUCCESSFUL` | `ROLLED_BACK` | `REQUIRES_INTERVENTION`

---

## Invariants

1. **Build once, promote same artifact** — no rebuilds between environments.
2. **Production Candidates are immutable** — new candidate = new build.
3. **Deployment Authority is separate from implementation/QA/design** — no credential sharing.
4. **Coding agents never receive unrestricted production credentials** — hard boundary.
5. **Destructive migrations always require Human Decision** — no exceptions.
6. **Infrastructure destruction always requires Human Decision** — no exceptions.
7. **Automatic rollback prefers known-good artifact** — never AI debugging in production.
8. **Mobile API backward compatibility is mandatory consideration** — documented in every Deployment Request.
4. **Deployment execution is a distinct, auditable step** — not conflated with implementation.
10. **Only Engineering Manager advances lifecycle state** — Deployment Authority executes; Manager consumes results and transitions.

---

## Structured Results

Release Engineer and Deployment Authority must emit machine-readable structured results per
[STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md).

### Release Engineer Result Contract (Production Candidate / Deployment Request)
```json
{
  "result_type": "DEPLOYMENT_REQUEST",
  "status": "CREATED" | "VALIDATED" | "APPROVED",
  "provenance": { "agent_id": "", "request_id": "", "candidate_id": "", "head_sha": "" },
  "payload": { "deployment_request": {}, "pre_deployment_checks": {} },
  "evidence": { "qa_results": [], "build_provenance": {} },
  "blockers": [],
  "next_actions": ["PRE_DEPLOYMENT_VALIDATION", "HUMAN_APPROVAL", "DEPLOYMENT_EXECUTION"]
}
```

### Deployment Authority Result Contract (Deployment Execution)
```json
{
  "result_type": "DEPLOYMENT_RESULT",
  "status": "SUCCESS" | "FAILED" | "ROLLED_BACK" | "PARTIAL",
  "provenance": { "authority_id": "", "request_id": "", "candidate_id": "", "environment": "" },
  "payload": { "steps_executed": [], "rollback_triggered": false, "post_deployment_validation": {} },
  "evidence": { "logs": [], "metrics": [], "health_checks": [] },
  "blockers": [],
  "next_actions": ["PRODUCTION_VALIDATION", "ROLLBACK" | "MARK_DEPLOYED"]
}
```

---

## Cross-References

- [WORKFLOW.md](WORKFLOW.md) — Lifecycle steps 30-38
- [QA_GOVERNANCE.md](QA_GOVERNANCE.md) — QA gates must pass before Production Candidate creation
- [HUMAN_DECISIONS.md](HUMAN_DECISIONS.md) — Human approval for destructive migrations and production promotion
- [STRUCTURED_RESULTS.md](STRUCTURED_RESULTS.md) — Machine-readable result contracts
- [LEARNING_POLICY.md](LEARNING_POLICY.md) — `DEPLOYMENT_DISCOVERY` classification
- [AGENTS.md](../../AGENTS.md) — Repository-wide invariants (ownership, validation, human authority)

---

## Templates

- [Deployment Request Template](../../framework/templates/deployment-request.template.yaml)
- [Deployment Result Template](../../framework/templates/deployment-result.template.yaml)