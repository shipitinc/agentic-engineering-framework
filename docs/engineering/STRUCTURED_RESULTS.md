# STRUCTURED_RESULTS.md — Machine-Readable Result Contracts

This document defines the **standard envelope** and **role-specific payloads** for all structured results
emitted by agents in the agentic engineering framework. These contracts enable deterministic
workflow orchestration without scraping conversational prose.

---

## Standard Envelope

Every structured result **must** conform to this top-level envelope:

```json
{
  "result_type": "STRING",                    // Enum: see Result Types below
  "status": "STRING",                         // Enum: see Status Values below
  "schema_version": "1.0",                    // Contract version for forward compatibility
  "provenance": {                             // Mandatory provenance block
    "agent_id": "STRING",                     // Unique agent identifier
    "agent_role": "STRING",                   // Role: IMPLEMENTER, ENGINEERING_REVIEWER, DESIGN_AGENT, DESIGN_REVIEWER, QA_ARCHITECT, QA_EXECUTOR, RELEASE_ENGINEER, DEPLOYMENT_AUTHORITY, CORRECTION_IMPLEMENTER, FOCUSED_REVIEWER, INTEGRATOR, ENGINEERING_MANAGER
    "work_item_id": "STRING",                 // Feature/change ID this result pertains to
    "work_item_type": "STRING",               // FEATURE, DESIGN_REVISION, DCR, QA_CONTRACT, DEPLOYMENT, etc.
    "branch": "STRING",                       // Git branch name
    "base_sha": "STRING",                     // Base commit SHA (parent of changes)
    "head_sha": "STRING",                     // Head commit SHA (result of this work)
    "timestamp": "ISO8601"                    // Result emission timestamp
  },
  "payload": {                                // Role-specific payload (defined per result_type)
    // ... varies by result_type
  },
  "evidence": {                               // Evidence package (paths, URLs, references)
    // ... varies by result_type
  },
  "blockers": [                               // Array of blocking issues
    {
      "blocker_id": "STRING",
      "type": "HUMAN_DECISION_REQUIRED | VALIDATION_FAILURE | OWNERSHIP_CONFLICT | ARCHITECTURE_BLOCKER | DEPENDENCY_BLOCKER | OTHER",
      "description": "STRING",
      "related_artifact_ids": ["STRING"],
      "escalation_path": "STRING"
    }
  ],
  "next_actions": ["STRING"],                 // Suggested next workflow actions (enum per result_type)
  "metadata": {                               // Optional extensible metadata
    "duration_seconds": "INTEGER",
    "tool_versions": {},
    "custom": {}
  }
}
```

### Optional task telemetry

Task timing and performance observations live in the append-only event store described in
[TASK_METRICS.md](TASK_METRICS.md). An envelope may link them through
`metadata.custom.task_metrics` with `run_id`, `task_id`, and `events_ref`; these are optional
metadata, not new result/status tokens or admission requirements. Missing telemetry stays unknown
and never blocks a gate. Keep total elapsed, explicitly observed active intervals, waiting, and
unknown time distinct. Do not infer agent work time from commit timestamps or add parallel lane
hours and call the sum delivery time. Record actual model, harness, framework revision, attempts,
review/correction outcomes, and agent verification separately from Human QA outcomes.

### Result Types (Enum)

| Result Type | Emitted By | Description |
|-------------|------------|-------------|
| `IMPLEMENTATION_RESULT` | Implementer / Correction Implementer | Implementation or correction completion |
| `ENGINEERING_REVIEW` | Engineering Reviewer / Focused Reviewer | Independent code review verdict |
| `DESIGN_REVISION` | Design Agent | Design Revision produced |
| `DESIGN_REVIEW` | Design Reviewer | Independent design review verdict |
| `QA_CONTRACT` | QA Architect | QA Contract created/frozen |
| `QA_RESULT` | QA Executor | QA execution outcome |
| `HUMAN_DECISION` | Engineering Manager | Human Decision object created/resolved |
| `DEPLOYMENT_REQUEST` | Release Engineer | Deployment Request created/validated |
| `DEPLOYMENT_RESULT` | Deployment Authority | Deployment execution outcome |
| `PRODUCTION_VALIDATION` | Deployment Authority / Manager | Post-deployment production validation |
| `INTEGRATION_READINESS` | Integrator | Merge-readiness verification |
| `ORCHESTRATION_RESULT` | Engineering Manager | Work-item orchestration outcome (lanes, gates, blockers) |

### Status Values (Enum)

| Status | Meaning |
|--------|---------|
| `COMPLETE` | Work finished successfully, all gates pass |
| `BLOCKED` | Work cannot proceed; blockers listed |
| `PARTIAL` | Work partially complete; some gates pass, some deferred |
| `FAILED` | Work attempted but failed validation |
| `PENDING` | Result submitted but awaiting dependent gate (e.g., review) |
| `APPROVED` | Review/approval gate passed |
| `CHANGES_REQUIRED` | Review gate requires changes |
| `HUMAN_DECISION_REQUIRED` | Consequential human gate required |
| `READY_FOR_MERGE` | All gates pass, ready for integration |
| `DEPLOYMENT_SUCCESSFUL` | Deployment completed and validated |
| `ROLLED_BACK` | Deployment rolled back |
| `RESOLVED` | Human Decision resolved |

---

## Role-Specific Payloads

### 1. IMPLEMENTATION_RESULT (Implementer / Correction Implementer)

```json
{
  "result_type": "IMPLEMENTATION_RESULT",
  "status": "COMPLETE | BLOCKED | PARTIAL",
  "payload": {
    "feature_id": "STRING",
    "owned_paths": ["STRING"],
    "read_only_paths": ["STRING"],
    "prohibited_paths": ["STRING"],
    "files_changed": ["STRING"],
    "gates": {
      "format": "PASS | FAIL | N/A",
      "analyze": "PASS | FAIL | N/A",
      "tests": "PASS | FAIL | N/A",
      "build": "PASS | FAIL | N/A",
      "runtime": "PASS | FAIL | N/A",
      "gate_commands": {
        "format": "STRING",
        "analyze": "STRING",
        "tests": "STRING",
        "build": "STRING",
        "runtime": "STRING"
      }
    },
    "design_contract_ref": "STRING",
    "qa_contract_ref": "STRING",
    "discoveries": [
      {
        "category": "PROJECT_FACT | RUNTIME_DISCOVERY | ARCHITECTURE_DISCOVERY | DESIGN_DISCOVERY | WORKFLOW_IMPROVEMENT | AUTOMATION_OPPORTUNITY | CONTRADICTION",
        "description": "STRING",
        "evidence_ref": "STRING"
      }
    ],
    "knowledge_persisted": ["STRING"],
    "ready_for_independent_review": true
  },
  "evidence": {
    "test_reports": ["STRING"],
    "build_logs": ["STRING"],
    "runtime_evidence": ["STRING"]
  },
  "next_actions": ["INDEPENDENT_ENGINEERING_REVIEW", "CORRECTION_LOOP", "HUMAN_DECISION_REQUIRED"]
}
```

### 2. ENGINEERING_REVIEW (Engineering Reviewer / Focused Reviewer)

```json
{
  "result_type": "ENGINEERING_REVIEW",
  "status": "APPROVED | CHANGES_REQUIRED | HUMAN_DECISION_REQUIRED",
  "payload": {
    "reviewed_head_sha": "STRING",
    "review_scope": "FULL | FOCUSED",
    "focused_on_findings": ["STRING"],  // Only for FOCUSED
    "blockers": [
      {
        "severity": "HIGH | MEDIUM | LOW",
        "description": "STRING",
        "file_path": "STRING",
        "line_range": "STRING",
        "suggested_fix": "STRING"
      }
    ],
    "non_blocking_followups": [
      {
        "description": "STRING",
        "file_path": "STRING",
        "line_range": "STRING"
      }
    ],
    "correction_required": true,
    "human_decision_required": false,
    "human_decision_type": "STRING",  // If human_decision_required=true
    "safe_parallel_work": ["STRING"]
  },
  "evidence": {
    "gate_verification": {
      "format": "PASS | FAIL",
      "analyze": "PASS | FAIL",
      "tests": "PASS | FAIL",
      "commands_run": ["STRING"]
    },
    "diff_inspection": "COMPLETE | PARTIAL",
    "provenance_verified": true
  },
  "next_actions": ["CORRECTION_LOOP", "FOCUSED_RE_REVIEW", "INTEGRATION", "HUMAN_DECISION_REQUIRED"]
}
```

### 3. DESIGN_REVISION (Design Agent)

```json
{
  "result_type": "DESIGN_REVISION",
  "status": "COMPLETE | BLOCKED",
  "payload": {
    "brief_id": "STRING",
    "revision_id": "STRING",
    "revision_number": "INTEGER",
    "revision_metadata_path": "STRING",
    "artifact_paths": ["STRING"],
    "risk_level": 0 | 1 | 2 | 3,
    "risk_rationale": "STRING",
    "changelog": ["STRING"],
    "traceability": {
      "requirements_covered": ["STRING"],
      "requirements_gaps": ["STRING"]
    },
    "design_system_compliance": "PASS | PARTIAL | FAIL",
    "ux_accessibility_score": "PASS | PARTIAL | FAIL",
    "implementation_feasibility": "HIGH | MEDIUM | LOW | UNKNOWN",
    "design_artifact_ref": "STRING",
    "source_design_artifact_ref": "STRING",
    "candidate_design_artifact_ref": "STRING",
    "verification": {
      "write_verified": true,
      "deterministic_checks_passed": "INTEGER",
      "deterministic_checks_total": "INTEGER",
      "evidence_ref": "STRING",
      "verification_status": "UNVERIFIED | VERIFIED | FAILED | INCOMPLETE"
    },
    "design_system_asset_refs": ["STRING"],
    "routing_policy": {
      "model_used": "STRING",
      "routing_class": "STRING"
    }
  },
  "evidence": {
    "design_files": ["STRING"],
    "prototype_urls": ["STRING"],
    "review_gates": {}
  },
  "next_actions": ["INDEPENDENT_DESIGN_REVIEW", "DCR_PROCESS", "HUMAN_APPROVAL", "DESIGN_CONTRACT_FREEZE"]
}
```

### 4. DESIGN_REVIEW (Independent Design Reviewer)

```json
{
  "result_type": "DESIGN_REVIEW",
  "status": "APPROVED | APPROVED_WITH_NON_BLOCKING_FINDINGS | CHANGES_REQUIRED | HUMAN_DECISION_REQUIRED",
  "payload": {
    "revision_id": "STRING",
    "reviewed_head_sha": "STRING",
    "independent_risk_level": 0 | 1 | 2 | 3,
    "risk_level_agreement": true,
    "findings": [
      {
        "severity": "HIGH | MEDIUM | LOW",
        "category": "DESIGN_SYSTEM | UX_ACCESSIBILITY | INFORMATION_ARCHITECTURE | IMPLEMENTATION_FEASIBILITY | TRACEABILITY | ARTIFACT_VERIFICATION | ASSET_REUSE",
        "blast_radius": "REACHES_IMPLEMENTATION | EVIDENCE_HYGIENE",
        "description": "STRING",
        "artifact_ref": "STRING"
      }
    ],
    "non_blocking_findings": [
      {
        "finding_id": "STRING",
        "severity": "HIGH | MEDIUM | LOW",
        "category": "DESIGN_SYSTEM | UX_ACCESSIBILITY | INFORMATION_ARCHITECTURE | IMPLEMENTATION_FEASIBILITY | TRACEABILITY | ARTIFACT_VERIFICATION | ASSET_REUSE",
        "blast_radius": "EVIDENCE_HYGIENE",
        "description": "STRING",
        "artifact_ref": "STRING",
        "file_path": "STRING",
        "line_range": "STRING",
        "resolution": "OPEN | CORRECTED",
        "resolution_ref": "STRING"  // Required when resolution=CORRECTED; names the corrected location
      }
    ],
    "traceability_gaps": ["STRING"],
    "human_decision_required": false,
    "human_decision_type": "DESIGN",
    "dcr_required": false,
    "visual_approval_required": true,
    "candidate_design_artifact_ref": "STRING",
    "canonical_design_artifact_ref": "STRING",
    "human_decision_ref": "STRING"
  },
  "evidence": {
    "gate_results": {
      "design_system_compliance": "PASS | FAIL",
      "ux_accessibility": "PASS | FAIL",
      "ia_integrity": "PASS | FAIL",
      "feasibility": "PASS | FAIL",
      "artifact_verification": "PASS | FAIL",
      "asset_reuse_compliance": "PASS | FAIL"
    }
  },
  "next_actions": ["DCR_PROCESS", "HUMAN_APPROVAL", "DESIGN_CONTRACT_FREEZE", "DESIGN_REVISION"]
}
```

#### Finding disposition by blast radius

Every entry in `findings[]` carries a mandatory `blast_radius`. The classification taxonomy and its
discriminator — *can this finding change what the implementation does?* — are defined in
[DESIGN_GOVERNANCE.md](DESIGN_GOVERNANCE.md) § Finding Classification by Blast Radius. Classification
is by **reach, not by symptom**.

- `REACHES_IMPLEMENTATION` — always blocking. The finding is emitted in `findings[]` and forces
  `CHANGES_REQUIRED` (or `HUMAN_DECISION_REQUIRED` when it is a genuine Level 2/3 gate).
- `EVIDENCE_HYGIENE` — **non-blocking by default in a pre-implementation artifact**. Emitted in
  `non_blocking_findings[]` — the field name and its `description` / `file_path` / `line_range`
  members mirror § 2 `non_blocking_followups[]` so the two review paths read identically, plus the
  design-specific `severity` / `category` / `blast_radius` / `artifact_ref` — and the verdict becomes
  `APPROVED_WITH_NON_BLOCKING_FINDINGS`.

`non_blocking_findings[]` is **recorded, not waived**: every entry is still required before
Gate D5 (Design Contract Freeze), and the freeze is refused while any is open. `non_blocking`
governs only the gate between the revision and the freeze, never the freeze itself.

**Open is determined, never inferred from absence.** Each entry carries a `finding_id` that is
**stable across emits of the same `revision_id`**: a later `DESIGN_REVIEW` reuses the prior
`finding_id` verbatim, so the Manager can match carries across emits. An entry closes **only** when a
later `DESIGN_REVIEW` records that same `finding_id` with `resolution: CORRECTED` and a
`resolution_ref` naming the corrected location. A carried-forward `finding_id` the fresh emit does
not mention is **still open** — silence is never closure, and `resolution` is what makes "still
open" determinable rather than inferred. The Manager carries the open set forward from the most
recent emit for that `revision_id` and refuses Gate D5 while it is non-empty. Correcting a finding
produces a new Design Revision, and invariant 2 of DESIGN_GOVERNANCE.md already requires an
Independent Design Review of every revision, so the fresh emit that closes it exists in the
lifecycle — no new lane is required.

This is a **symmetry repair with `ENGINEERING_REVIEW`**, not a new concept — see § 2
(`non_blocking_followups[]` + `APPROVE_WITH_NON_BLOCKING_FOLLOWUP`) and
[QA_GOVERNANCE.md](QA_GOVERNANCE.md) rule 5 (`OPTIONAL` / `NOT_IN_DEFAULT_PIPELINE` rows are
non-blocking by construction). `APPROVED_WITH_NON_BLOCKING_FINDINGS` normalizes to envelope `status:
APPROVED_WITH_NON_BLOCKING_FINDINGS`; `HUMAN_DECISION_REQUIRED` is unchanged by this addition.

### 5. QA_CONTRACT (QA Architect)

```json
{
  "result_type": "QA_CONTRACT",
  "status": "CREATED | FROZEN",
  "payload": {
    "contract_id": "STRING",
    "design_contract_ref": "STRING",
    "contract_path": "STRING",
    "acceptance_criteria_count": "INTEGER",
    "test_strategy": {
      "unit": "DEFINED | NOT_APPLICABLE",
      "integration": "DEFINED | NOT_APPLICABLE",
      "contract": "DEFINED | NOT_APPLICABLE",
      "e2e": "DEFINED | NOT_APPLICABLE",
      "visual": "DEFINED | NOT_APPLICABLE",
      "human": "REQUIRED | OPTIONAL | NOT_APPLICABLE"
    },
    "evidence_standards_defined": true,
    "golden_baselines_defined": true,
    "regression_requirements_defined": true,
    "evidence_rows": [
      {
        "evidence_id": "STRING",  // E-01, E-02, … (E_* rows)
        "required": "REQUIRED | OPTIONAL | NOT_APPLICABLE",
        "test_method": "AUTOMATED | VISUAL | HUMAN | COMBINED",
        "artifact_ref": "STRING",  // feature-specific artifact/URL satisfying the row
        "params": "STRING",        // run parameters, e.g. --dart-define=E2E_VERIFICATION_CODE
        "prerequisites": "STRING", // lane/services/device required to run
        "contract_determination": "EXPECTED_TO_EXECUTE | CONTINGENT | SKIPPED_BY_CONTRACT",
        "determination_reasons": "STRING"
      }
    ]
  },
  "evidence": {
    "traceability_matrix": "STRING"
  },
  "next_actions": ["QA_CONTRACT_REVIEW", "QA_CONTRACT_FREEZE", "IMPLEMENTATION"]
}
```

### 6. QA_RESULT (QA Executor)

```json
{
  "result_type": "QA_RESULT",
  "status": "PASS | FAIL | PARTIAL | BLOCKED",
  "payload": {
    "contract_id": "STRING",
    "execution_type": "AUTOMATED | VISUAL | HUMAN | COMBINED",
    "target_revision": "STRING",
    "target_environment": "STRING",
    "summary": {
      "total_tests": "INTEGER",
      "passed": "INTEGER",
      "failed": "INTEGER",
      "skipped": "INTEGER",
      "flaky": "INTEGER"
    },
    "gate_results": {
      "unit": "PASS | FAIL | N/A | NOT_EXECUTED | SKIPPED",
      "integration": "PASS | FAIL | N/A | NOT_EXECUTED | SKIPPED",
      "contract": "PASS | FAIL | N/A | NOT_EXECUTED | SKIPPED",
      "e2e": "PASS | FAIL | N/A | NOT_EXECUTED | SKIPPED",
      "visual": "PASS | FAIL | N/A | NOT_EXECUTED | SKIPPED",
      "human": "PASS | FAIL | N/A | NOT_EXECUTED | SKIPPED"
    },
    "evidence_determinations": [
      {
        "evidence_id": "STRING",  // E_* row reference from the QA Contract
        "determination": "EXECUTED | READY_NOT_EXECUTED | SKIPPED",
        "artifact_ref": "STRING",
        "params": "STRING",
        "prerequisites": "STRING",
        "reasons": "STRING",      // mandatory unless EXECUTED
        "authority_ref": "STRING",// required for SKIPPED
        "evidence_refs": ["STRING"]
      }
    ],
    "failures": [
      {
        "failure_id": "STRING",
        "classification": "IMPLEMENTATION_DEFECT | DESIGN_DEFECT | REQUIREMENT_GAP | ENVIRONMENT_DEFECT",
        "severity": "CRITICAL | HIGH | MEDIUM | LOW",
        "description": "STRING",
        "evidence_refs": ["STRING"],
        "suggested_remediation_lane": "CORRECTION | DCR | REQUIREMENTS_CLARIFICATION | INFRA_REMEDIATION",
        "regression_test_added": true,
        "regression_test_ref": "STRING"
      }
    ],
    "golden_baseline_changes": [
      {
        "baseline_id": "STRING",
        "change_type": "NEW | UPDATED | REMOVED",
        "approved_by": "QA_ARCHITECT | HUMAN_QA",
        "approval_ref": "STRING"
      }
    ],
    "overall_verdict": "READY_FOR_MERGE | BLOCKED | HUMAN_DECISION_REQUIRED"
  },
  "evidence": {
    "test_reports": ["STRING"],
    "screenshots": ["STRING"],
    "videos": ["STRING"],
    "logs": ["STRING"],
    "traces": ["STRING"]
  },
  "next_actions": ["CLASSIFY_FAILURES", "REGRESSION_TESTS", "REMEDIATION_ROUTING", "MERGE", "HUMAN_DECISION_REQUIRED"]
}
```

### 7. HUMAN_DECISION (Engineering Manager)

```json
{
  "result_type": "HUMAN_DECISION",
  "status": "CREATED | RESOLVED | ESCALATED | DEFERRED | CANCELLED",
  "payload": {
    "decision_id": "STRING",
    "decision_type": "PRODUCT | ARCHITECTURE | DESIGN | SECURITY | INFRASTRUCTURE | DESTRUCTIVE_OPERATION | DEPLOYMENT_AUTHORITY | OTHER_CONSEQUENTIAL",
    "question": "STRING",
    "blocking_work_item": {
      "item_type": "STRING",
      "item_id": "STRING",
      "item_ref": "STRING"
    },
    "options": [
      {
        "option_id": "STRING",
        "label": "STRING",
        "description": "STRING",
        "implications": "STRING",
        "estimated_effort": "STRING",
        "risk_level": "LOW | MEDIUM | HIGH | CRITICAL"
      }
    ],
    "recommendation": {
      "recommended_option": "STRING",
      "rationale": "STRING",
      "confidence": "HIGH | MEDIUM | LOW"
    },
    "resolution": {
      "selected_option": "STRING",
      "decided_by": "STRING",
      "decided_at": "ISO8601",
      "rationale": "STRING",
      "follow_up_actions": [
        {
          "action": "STRING",
          "owner": "STRING",
          "due_date": "ISO8601"
        }
      ]
    }
  },
  "evidence": {
    "context_documents": ["STRING"],
    "quantitative_data": ["STRING"],
    "qualitative_tradeoffs": ["STRING"]
  },
  "next_actions": ["RESUME_BLOCKED_LANE", "ESCALATE", "DEFER", "CANCEL_WORK_ITEM"]
}
```

### 8. DEPLOYMENT_REQUEST (Release Engineer)

```json
{
  "result_type": "DEPLOYMENT_REQUEST",
  "status": "CREATED | VALIDATED | APPROVED",
  "payload": {
    "request_id": "STRING",
    "candidate_id": "STRING",
    "target_environment": "STAGING | PRODUCTION",
    "deployment_strategy": "STRING",
    "deployment_plan_summary": {
      "total_steps": "INTEGER",
      "migration_counts": {
        "SAFE": "INTEGER",
        "RISKY": "INTEGER",
        "DESTRUCTIVE": "INTEGER"
      },
      "estimated_duration_seconds": "INTEGER"
    },
    "pre_deployment_checks": {
      "migration_classification_review": "PASS | PENDING | FAIL",
      "rollback_plan_validated": "PASS | PENDING | FAIL",
      "mobile_api_backward_compatibility": "PASS | PENDING | FAIL | NOT_APPLICABLE",
      "infrastructure_destruction_review": "PASS | PENDING | FAIL | NOT_APPLICABLE"
    },
    "human_approval_required": true,
    "human_approval_ref": "STRING"
  },
  "evidence": {
    "qa_results": ["STRING"],
    "build_provenance": "STRING",
    "candidate_provenance": "STRING"
  },
  "next_actions": ["PRE_DEPLOYMENT_VALIDATION", "HUMAN_APPROVAL", "DEPLOYMENT_EXECUTION"]
}
```

### 9. DEPLOYMENT_RESULT (Deployment Authority)

```json
{
  "result_type": "DEPLOYMENT_RESULT",
  "status": "SUCCESS | FAILED | ROLLED_BACK | PARTIAL",
  "payload": {
    "request_id": "STRING",
    "candidate_id": "STRING",
    "target_environment": "STAGING | PRODUCTION",
    "executed_by": "STRING",
    "duration_seconds": "INTEGER",
    "steps_executed": [
      {
        "step_id": "STRING",
        "status": "SUCCESS | FAILED | SKIPPED",
        "started_at": "ISO8601",
        "completed_at": "ISO8601",
        "output": "STRING"
      }
    ],
    "rollback_triggered": false,
    "rollback_reason": "STRING",
    "rollback_result": "SUCCESS | FAILED | PARTIAL",
    "post_deployment_validation": {
      "health_checks": "PASS | FAIL",
      "synthetic_transactions": "PASS | FAIL",
      "key_metrics": "PASS | FAIL",
      "error_rates": "PASS | FAIL",
      "mobile_compatibility": "PASS | FAIL | NOT_APPLICABLE"
    },
    "overall_verdict": "DEPLOYMENT_SUCCESSFUL | ROLLED_BACK | REQUIRES_INTERVENTION"
  },
  "evidence": {
    "logs": ["STRING"],
    "metrics": ["STRING"],
    "health_checks": ["STRING"]
  },
  "next_actions": ["PRODUCTION_VALIDATION", "ROLLBACK", "MARK_DEPLOYED", "HUMAN_DECISION_REQUIRED"]
}
```

### 10. PRODUCTION_VALIDATION (Deployment Authority / Manager)

```json
{
  "result_type": "PRODUCTION_VALIDATION",
  "status": "PASS | FAIL | PARTIAL",
  "payload": {
    "candidate_id": "STRING",
    "deployment_result_ref": "STRING",
    "validation_checks": {
      "health_checks": "PASS | FAIL",
      "synthetic_transactions": "PASS | FAIL",
      "key_metrics": "PASS | FAIL",
      "error_rates": "PASS | FAIL",
      "mobile_compatibility": "PASS | FAIL | NOT_APPLICABLE",
      "monitoring_alerts": "NONE | ACTIVE"
    },
    "verdict": "VALIDATED | ROLLBACK_REQUIRED | INVESTIGATION_REQUIRED"
  },
  "evidence": {
    "monitoring_dashboards": ["STRING"],
    "synthetic_results": ["STRING"],
    "metric_snapshots": ["STRING"]
  },
  "next_actions": ["MARK_RELEASE_COMPLETE", "ROLLBACK", "INCIDENT_RESPONSE"]
}
```

### 11. INTEGRATION_READINESS (Integrator)

```json
{
  "result_type": "INTEGRATION_READINESS",
  "status": "READY | NOT_READY | BLOCKED",
  "payload": {
    "feature_id": "STRING",
    "source_branch": "STRING",
    "target_branch": "STRING",
    "merge_strategy": "MERGE | REBASE | SQUASH",
    "checks": {
      "review_approved": true,
      "all_gates_pass": true,
      "no_conflicts": true,
      "ci_green": true,
      "qa_gates_pass": true,
      "deployment_request_ready": true
    },
    "blocking_issues": ["STRING"]
  },
  "evidence": {
    "review_result_ref": "STRING",
    "qa_result_refs": ["STRING"],
    "ci_run_url": "STRING"
  },
  "next_actions": ["MERGE", "WAIT_FOR_GATES", "RESOLVE_CONFLICTS"]
}
```

---

### 12. ORCHESTRATION_RESULT (Engineering Manager)

Emitted by the Manager lane for a work item when it parks, completes, or blocks. One result per work
item, never one per subtask; the per-lane results it references are the specialist results above.

The envelope `status` below is **not** the terminal `RESULT:` line the Manager prints when the loop
ends. That terminal vocabulary is defined solely in the canonical
`.agents/skills/aef-run-feature/SKILL.md` (or the platform-equivalent adapter that loads that skill) §
Final Manager Report and is not an envelope field; no other role emits it.

```json
{
  "result_type": "ORCHESTRATION_RESULT",
  "status": "COMPLETE | PARTIAL | BLOCKED | HUMAN_DECISION_REQUIRED",
  "payload": {
    "work_item_id": "STRING",
    "final_state": "STRING",
    "lanes_dispatched": [
      {
        "task_id": "STRING",
        "task_type": "design-review | implement | review | correct | re-review | integrate | research | design-produce | qa-contract | qa-execute | deploy",
        "routing_class": "CHEAP_READ | STANDARD | PRECISION",
        "worktree": "STRING",
        "branch": "STRING",
        "base_sha": "STRING",
        "head_sha": "STRING",
        "result_ref": "STRING",
        "verdict": "COMPLETE | PARTIAL | BLOCKED | FAILED | PENDING"
      }
    ],
    "gates": {
      "independent_review": "NOT_REQUIRED | APPROVED | CHANGES_REQUIRED | BLOCKED",
      "integration_readiness": "NOT_REQUIRED | READY | NOT_READY | BLOCKED",
      "qa_contract": "NOT_REQUIRED | FROZEN | BLOCKED",
      "qa_execution": "NOT_REQUIRED | PASS | FAIL | BLOCKED",
      "deployment": "NOT_REQUIRED | SUCCESSFUL | ROLLED_BACK | BLOCKED"
    },
    "manager_self_edits": ["STRING"],
    "blockers": [
      { "type": "STRING", "escalation_path": "AUTO | HUMAN_DECISION | STOP" }
    ],
    "open_decision_ids": ["STRING"],
    "conventions": {
      "declared_in": "STRING",  // project-declared path + heading of the section that declares the
                                 // orchestration conventions (e.g. the instantiated AGENTS.md's
                                 // conventions section). Never hardcoded: heading names differ per repo.
      "defaulted": ["STRING"]   // convention names taken from defaults, per the orchestrator skill
    }
  },
  "evidence": {
    "dispatch_records": ["<DISPATCH_STATE_DIR>/tasks/<TASK_ID>/report.md"],
    "lanes_ledger": "<DISPATCH_STATE_DIR>/LANES.md"
  },
  "next_actions": ["ADVANCE_STATE", "DISPATCH_NEXT_LANE", "AWAIT_HUMAN_DECISION", "PARK"]
}
```

## Orchestration Rules for Structured Results

1. **Every agent result must be a valid JSON object** conforming to the standard envelope.
2. **Provenance is mandatory** — `agent_id`, `branch`, `base_sha`, `head_sha`, `timestamp`.
3. **Results are emitted to stdout** (or configured output) as a single JSON object.
4. **The Engineering Manager parses and validates** each result before advancing workflow state.
5. **Invalid/malformed results are rejected** — agent must re-emit.
6. **Results are persisted** in the product repository under `.results/` (or configured location) for audit.
7. **Next actions are advisory** — the Manager decides actual next step based on workflow policy.
8. **Blockers must be actionable** — each blocker must have a type, description, and escalation path.

---

## Cross-References

- [WORKFLOW.md](WORKFLOW.md) — Lifecycle gates that require structured results
- [AGENTS.md](../../AGENTS.md) — "Structured results" invariant, orchestration binding
- [DESIGN_GOVERNANCE.md](DESIGN_GOVERNANCE.md) — DESIGN_REVISION, DESIGN_REVIEW contracts
- [QA_GOVERNANCE.md](QA_GOVERNANCE.md) — QA_CONTRACT, QA_RESULT contracts
- [HUMAN_DECISIONS.md](HUMAN_DECISIONS.md) — HUMAN_DECISION contract
- [DEPLOYMENT_GOVERNANCE.md](DEPLOYMENT_GOVERNANCE.md) — DEPLOYMENT_REQUEST, DEPLOYMENT_RESULT, PRODUCTION_VALIDATION contracts
- [LEARNING_POLICY.md](LEARNING_POLICY.md) — Discovery classification in results
- `aef-orchestrator` skill (`.agents/skills/aef-orchestrator/SKILL.md`) —
  Manager lane that emits ORCHESTRATION_RESULT. Its canonical source in this framework repository lives
  under `framework/templates/__brick__/.agents/skills/`. The framework root now also carries a
  **generated mirror** at `.agents/skills/`, so this path resolves at the root as well — but the mirror
  is generated output, never a source of truth: fix the brick, never the copy.
- `aef-run-feature` skill (`.agents/skills/aef-run-feature/SKILL.md`) — single source of the Manager's
  terminal `RESULT:` vocabulary. On each non-canonical platform it is surfaced through a **generated**
  command adapter: `.claude/commands/run-feature.md`, `.junie/commands/run-feature.md`, and
  `.opencode/command/run-feature.md`. Those directories (and `.claude/agents/`, `.junie/agents/`,
  `.opencode/agents/`) are generated output from the canonical `.agents/` artifacts and are never
  hand-maintained — see ADR 0003 § Platform matrix and generated adapters.

---

## Versioning

- `schema_version: "1.0"` — This version.
- Breaking changes require new major version and migration plan.
- Minor versions add optional fields only.
- Agents must declare the schema version they emit.
- Manager must handle declared version or reject with clear error.