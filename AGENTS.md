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

### Ownership & concurrency
- Production-writing agents must declare **`OWNED_PATHS`**, **`READ_ONLY_PATHS`**, and
  **`PROHIBITED_PATHS`**.
- **Concurrent writers cannot have overlapping ownership.** If ownership would overlap, work must be
  serialized or re-partitioned before proceeding.

### Validation & evidence
- **Required deterministic validation must pass before success is claimed** (e.g., builds, linters,
  type checks, tests, and any project-declared required gates).
- **Runtime/browser evidence must correspond to the exact code revision being reviewed** (pin to the
  commit/revision; stale evidence is invalid).

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
- [framework/templates/](framework/templates/) — placeholder structure for versioned product artifacts.

> Note: This repository intentionally does **not** contain `.junie/AGENTS.md`.
