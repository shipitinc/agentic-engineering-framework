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

### Design Governance
- Design Agent ≠ Independent Design Reviewer — separate agents, no overlap.
- Design Agent never approves own work — every Design Revision requires Independent Design Review.
- Independent Design Reviewer is read-only — never modifies design artifacts.
- Substantial UI changes require an approved Design Revision — implementers must not invent consequential UX.
- Implementation-discovered UI gaps route back via DCR — not resolved in implementation lane.

### QA Governance
- QA Architect ≠ QA Executor — separate agents, no overlap.
- QA Contract required before implementation completion — no implementation can claim `IMPLEMENTED` without a frozen QA Contract.
- Deterministic evidence is authoritative over reviewer opinion — passing tests cannot be vetoed by subjective review.
- Implementation agents cannot approve changed visual golden baselines — only QA Architect or Human QA.
- QA artifacts must be preserved as evidence — pinned to exact revision, retained per policy.
- Regressions require regression tests — no re-verification without test.
- Every QA failure classified exactly once — `IMPLEMENTATION_DEFECT`, `DESIGN_DEFECT`, `REQUIREMENT_GAP`, `ENVIRONMENT_DEFECT`.
- QA Executor is read-only wrt production code and baselines — never modifies implementation or approves baselines.

### Human Decision Governance
- Every consequential human gate = a Human Decision object — no exceptions.
- Human Decision objects are durable, versioned, and queryable — not chat ephemera.
- Agents park cleanly while waiting — emit structured `BLOCKED` result, no hanging processes.
- Workflow is resumable from persisted state — Manager reads decision, validates, continues.
- Structured question UI is mandatory — never free-form prose.
- Each question/option is atomic — no bundling.
- Research first — Orchestrator discovers facts before asking.
- Only Engineering Manager creates/resolves Human Decisions — specialists cannot bypass.
- Decision audit trail is immutable — state transitions are commits.
- Routine transitions remain automatic — Human Decisions only for consequential gates.

### Deployment Governance
- Build once, promote same artifact — no rebuilds between environments.
- Production Candidates are immutable — new candidate = new build.
- Deployment Authority is separate from implementation/QA/design — no credential sharing.
- Coding agents never receive unrestricted production credentials — hard boundary.
- Destructive migrations always require Human Decision — no exceptions.
- Infrastructure destruction always requires Human Decision — no exceptions.
- Automatic rollback prefers known-good artifact — never AI debugging in production.
- Mobile API backward compatibility is mandatory consideration — documented in every Deployment Request.
- Deployment execution is a distinct, auditable step — not conflated with implementation.

### Structured Results
- Every agent result must be a machine-readable structured result per `STRUCTURED_RESULTS.md`.
- Provenance is mandatory — agent_id, branch, base_sha, head_sha, timestamp.
- Results are parsed and validated by the Engineering Manager before advancing workflow state.
- Invalid/malformed results are rejected — agent must re-emit.
- No workflow transition depends on scraping conversational prose.

## Orchestration

- The top-level session is the single Engineering Manager / Orchestrator — see the `aef-orchestrator`
  skill (the executable counterpart of these prose invariants; it adds no lifecycle stage and no human
  gate).
- The Manager **decomposes and dispatches**; it does not normally implement production source itself.
  It **retains** repository context, sequencing, integration, and final acceptance.
- Every dispatch names a bounded `TASK_TYPE`
  (`design-review | implement | review | correct | re-review | integrate | research`) and carries
  the mandatory prompt header from the `aef-orchestrator` skill § 4 (`MANAGER`, `TASK_ID`,
  `TASK_TYPE`, `FEATURE`, `AREA`, `WORKTREE`, `BRANCH`, `BASE_SHA`, `OWNED_PATHS`,
  `READ_ONLY_PATHS`, `PROHIBITED_PATHS`, `ACCEPTANCE_CRITERIA`, `VALIDATION_COMMANDS`,
  `ROUTING_CLASS`), rendered from
  `.agents/skills/aef-orchestrator/templates/subtask-prompt.md`.
- Every lane returns the structured report in
  `.agents/skills/aef-orchestrator/templates/subtask-report.md`; results are
  parsed per `STRUCTURED_RESULTS.md` and never read out of conversational prose.
- Production-writing lanes run in isolated worktrees with verified `BRANCH`/`BASE_SHA`; two writers
  never share a worktree, and overlapping `OWNED_PATHS` are serialized or re-partitioned first.
- Delegation is explicit and bounded, and uses the cheapest sufficient routing class — model routing
  is replaceable execution policy, never workflow authority.
- Manager state that must survive a crash or compaction is persisted as **plain markdown/JSON**
  under the declared state directory (`aef-orchestrator` skill § 3/§ 14). Tool-specific session hooks are not
  required and are not assumed to exist.
- `.agents/` is the **canonical source of truth** for the orchestration artifacts. `.claude/`,
  `.junie/`, and `.opencode/` hold **generated** platform adapters: never hand-edit them, edit the
  canonical artifact under `.agents/` instead. See `docs/engineering/adr/0003-product-generic-orchestrator-skill.md`
  § Platform matrix and generated adapters.

  **That no-hand-editing rule is advisory in this repository.** The generator
  (`cli/tool/generate_platform_adapters.dart`) and its `--check` drift test
  (`cli/test/platform_adapter_test.dart`) are framework-repository tooling and are **not** instantiated
  here, so nothing mechanically fails if a generated adapter is hand-edited — upholding the rule is the
  human's job in a product repository. The rule is mechanically enforced **only** in the framework
  repository itself, which owns the generator and the drift test. The ownership scope is the generated
  subtrees only: `.opencode/agents/` and `.opencode/command/` are generated, while the rest of
  `.opencode/` (`node_modules/`, `package.json`, `package-lock.json`, `.gitignore`) belongs to opencode
  at runtime and is not generated content.

## Product-specific policy (fill in)

- Required validation gates: TBD
- Environments & deployment strategy: TBD
- Path ownership map: TBD
- Orchestration conventions (override the `orchestrator` skill § 3 defaults; list the values this
  project declares, or `DEFAULTS` to accept them): TBD

## Framework provenance

- Framework revision: TBD — the **authoritative, immutable** provenance identifier.
- Framework version: TBD — human-readable metadata only (revision controls provenance if they differ).
- Both are recorded in this product repo's `framework-manifest.yaml` (the instantiated copy of the
  framework-side source template `manifest.template.yaml`), which stores **provenance only** plus
  per-artifact baseline hashes. Framework upgrades arrive as **reviewable, isolated 3-way-merge**
  changes and must **not** create a runtime dependency on the framework repo. See the framework's
  ADR 0001 (`docs/engineering/adr/0001-framework-distribution-and-versioning.md`).