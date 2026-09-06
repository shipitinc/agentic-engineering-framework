# AGENTS.md — Canonical Agentic Engineering Framework

This repository contains the **canonical, reusable agentic engineering framework**. It is
**not an application**. It defines the orchestration policy, lifecycle, and templates that will
later bootstrap and govern separate **product repositories**.

Product repositories will receive **versioned/instantiated copies** of the appropriate framework
policy. They must **not** depend implicitly on this repository at runtime. This repository is the
source of truth for the framework itself; instantiated copies are the source of truth for each product.

---

## Repository-wide invariants

These invariants are authoritative for any agent operating under this framework.

### Orchestration & roles
- There is exactly **one authoritative Engineering Manager / Orchestrator** per active product workflow.
- **Specialists do not independently advance lifecycle state.** Only the Orchestrator advances the
  workflow between lifecycle states.
- **Implementers never approve their own work.**
- **Independent reviewers are read-only** with respect to production code under review.

#### Design Governance
- **Design Agent ≠ Independent Design Reviewer** — separate agents, no overlap.
- **Design Agent never approves own work** — every Design Revision requires Independent Design Review.
- **Independent Design Reviewer is read-only** — never modifies design artifacts.
- **Substantial UI changes require an approved Design Revision** — implementers must not invent consequential UX.
- **Implementation-discovered UI gaps route back via DCR** — not resolved in implementation lane.

#### QA Governance
- **QA Architect ≠ QA Executor** — separate agents, no overlap.
- **QA Contract required before implementation completion** — no implementation can claim `IMPLEMENTED` without a frozen QA Contract.
- **Deterministic evidence is authoritative over reviewer opinion** — passing tests cannot be vetoed by subjective review.
- **Implementation agents cannot approve changed visual golden baselines** — only QA Architect or Human QA.
- **QA artifacts must be preserved as evidence** — pinned to exact revision, retained per policy.
- **Regressions require regression tests** — no re-verification without test.
- **Every QA failure classified exactly once** — `IMPLEMENTATION_DEFECT`, `DESIGN_DEFECT`, `REQUIREMENT_GAP`, `ENVIRONMENT_DEFECT`.
- **QA Executor is read-only wrt production code and baselines** — never modifies implementation or approves baselines.

#### Human Decision Governance
- **Every consequential human gate = a Human Decision object** — no exceptions.
- **Human Decision objects are durable, versioned, and queryable** — not chat ephemera.
- **Agents park cleanly while waiting** — emit structured `BLOCKED` result, no hanging processes.
- **Workflow is resumable from persisted state** — Manager reads decision, validates, continues.
- **Structured question UI is mandatory** — never free-form prose.
- **Each question/option is atomic** — no bundling.
- **Research first** — Orchestrator discovers facts before asking.
- **Only Engineering Manager creates/resolves Human Decisions** — specialists cannot bypass.
- **Decision audit trail is immutable** — state transitions are commits.
- **Routine transitions remain automatic** — Human Decisions only for consequential gates.

#### Deployment Governance
- **Build once, promote same artifact** — no rebuilds between environments.
- **Production Candidates are immutable** — new candidate = new build.
- **Deployment Authority is separate from implementation/QA/design** — no credential sharing.
- **Coding agents never receive unrestricted production credentials** — hard boundary.
- **Destructive migrations always require Human Decision** — no exceptions.
- **Infrastructure destruction always requires Human Decision** — no exceptions.
- **Automatic rollback prefers known-good artifact** — never AI debugging in production.
- **Mobile API backward compatibility is mandatory consideration** — documented in every Deployment Request.
- **Deployment execution is a distinct, auditable step** — not conflated with implementation.

#### Structured Results
- **Every agent result must be a machine-readable structured result** per `STRUCTURED_RESULTS.md`.
- **Provenance is mandatory** — agent_id, branch, base_sha, head_sha, timestamp.
- **Results are parsed and validated by the Engineering Manager** before advancing workflow state.
- **Invalid/malformed results are rejected** — agent must re-emit.
- **No workflow transition depends on scraping conversational prose**.

#### Junie orchestration binding
- The **main Junie session is the authoritative Engineering Manager / Orchestrator**. It is the only
  Manager; a competing `engineering-manager` subagent must **not** be created.
- The Manager **delegates production implementation** to specialist subagents rather than reviewing
  its own work, and **consumes their structured results** directly.
- **Routine lifecycle transitions are automatic** and the **human is never used as a message relay**
  between agents. `RESULT: IMPLEMENTED` automatically triggers independent review; `RESULT:
  DO_NOT_MERGE` automatically triggers correction (unless the finding itself is
  `HUMAN_DECISION_REQUIRED`); correction is always followed by a fresh **focused re-review**.
- **Integration is allowed only after independent approval.** A failed agent report is **evidence**,
  not grounds to silently skip a gate.
- Every child result must include **exact repository/worktree/HEAD provenance**, and **only the
  Manager updates workflow state** (`docs/engineering/WORK_STATE.md`). Durable discoveries are
  classified and persisted per `docs/engineering/LEARNING_POLICY.md`.
- Orchestration artifacts live under `.junie/` (`agents/`, `skills/`, `commands/run-feature.md`); the
  `/run-feature` command is the single human entry point for the autonomous loop.

### Ownership & concurrency
- Production-writing agents must declare **`OWNED_PATHS`**, **`READ_ONLY_PATHS`**, and
  **`PROHIBITED_PATHS`**.
- **Concurrent writers cannot have overlapping ownership.** If ownership would overlap, work must be
  serialized or re-partitioned before proceeding.
- Design, QA, and Deployment agents must declare ownership per their domain artifacts.
- Design artifacts, QA Contracts/baselines/results, Deployment Plans/Candidates/Requests are distinct ownership domains.

### Validation & evidence
- **Required deterministic validation must pass before success is claimed** (e.g., builds, linters,
  type checks, tests, and any project-declared required gates).
- **Runtime/browser evidence must correspond to the exact code revision being reviewed** (pin to the
  commit/revision; stale evidence is invalid).
- **QA evidence must correspond to the exact revision under test** — pinned via `target_revision` in QA Result.
- **Deployment evidence must correspond to the exact Production Candidate** — immutable artifact reference.

### Automation vs. human authority
- **Routine workflow transitions proceed automatically.**
- **Human intervention is reserved for genuine product, architecture, design, security,
  infrastructure, destructive-operation, deployment-authority, or other consequential decisions.**
- **Major architecture choices are human gates** and must be supported by **current qualitative and
  quantitative research**.
- Architecture research should compare **viable options** such as BaaS vs. application backend,
  cloud/runtime providers, database choices, object storage, authentication, and delivery topology
  when relevant.
- **Architecture bootstrap** includes Git/repository connectivity, CI/CD, infrastructure access, CLI
  availability, authentication, authorization, environments, deployment strategy, rollback, and
  production promotion.
- **QA deployment should normally be deterministic and automated after integration** when project
  policy permits.
- **Production promotion should remain human-authorized** unless a human-approved project policy
  explicitly changes that.
- **Design Brief approval, Level 2/3 DCR, Human QA initiation, destructive migrations, production promotion = Human Decisions.**

### Human questions & clarifications
- **Always surface questions to the human through the structured question UI**, never as free-form
  prose buried in a normal chat answer. Whenever an agent needs a human product / architecture /
  security / destructive-operation / infrastructure-access / production-deployment-authority / other
  consequential decision — or any clarification, missing requirement, scope choice, or priority /
  trade-off — it must be presented as one or more discrete, selectable questions via the question UI
  (in this environment, the `ask_user` / `mcp__Air__ask_user_question` tool).
- **Each question and each option must be a single, atomic proposal.** Do not bundle multiple
  unrelated decisions into one question or option; the human must be able to accept or reject each
  independently.
- **Research first.** Do not ask about facts you can determine yourself from the repository; reserve
  questions for genuine preferences, scope, priorities, trade-offs, or `HUMAN_DECISION_REQUIRED`
  gates. Provide real, non-overlapping next-step options and enough discovered context to decide.
- This rule does **not** relax the automation invariants: routine workflow transitions still proceed
  automatically and are **never** turned into human questions.

### Knowledge & learning
- Agents must **persist verified discoveries** that future agents would otherwise need to rediscover.
- **Prefer executable knowledge** (tests, scripts, configuration, commands) over prose where appropriate.
- **Operational/project facts may be persisted automatically when supported by evidence.**
- See [docs/engineering/LEARNING_POLICY.md](docs/engineering/LEARNING_POLICY.md) for classification
  and authority levels.

### Changing the framework itself
- **Material workflow-framework changes require independent review.**
- **Consequential governance changes require human approval.**
- The framework is **expected to improve based on findings**; the initial framework is **not assumed
  to be perfect**. Unresolved areas are tracked explicitly (see WORKFLOW / WORK_STATE).

---

## Control-plane files

- [docs/engineering/WORKFLOW.md](docs/engineering/WORKFLOW.md) — the reusable lifecycle.
- [docs/engineering/WORK_STATE.md](docs/engineering/WORK_STATE.md) — state of **this** framework repo.
- [docs/engineering/LEARNING_POLICY.md](docs/engineering/LEARNING_POLICY.md) — knowledge classification & authority.
- [docs/engineering/DESIGN_GOVERNANCE.md](docs/engineering/DESIGN_GOVERNANCE.md) — Design Agent, Design Reviewer, Design Brief, Design Revision, DCR, risk levels.
- [docs/engineering/QA_GOVERNANCE.md](docs/engineering/QA_GOVERNANCE.md) — QA Architect, QA Executor, QA Contract, QA Result, failure classifications.
- [docs/engineering/HUMAN_DECISIONS.md](docs/engineering/HUMAN_DECISIONS.md) — Human Decision objects, state persistence, structured question UI.
- [docs/engineering/DEPLOYMENT_GOVERNANCE.md](docs/engineering/DEPLOYMENT_GOVERNANCE.md) — Staging, production candidates, deployment plans, migration classification, rollback.
- [docs/engineering/STRUCTURED_RESULTS.md](docs/engineering/STRUCTURED_RESULTS.md) — Machine-readable result contracts for all roles and workflows.
- [framework/templates/](framework/templates/) — placeholder structure for versioned product artifacts.

> Note: This repository intentionally does **not** contain `.junie/AGENTS.md`.