# LEARNING_POLICY.md — Knowledge Classification & Authority

This policy defines how agents classify discoveries, what authority is required to persist them, and
how to distinguish **product-specific** findings from **generally reusable framework** findings.

Guiding principles (see [AGENTS.md](../../AGENTS.md)):
- Persist verified discoveries that future agents would otherwise rediscover.
- Prefer **executable knowledge** (tests, scripts, configuration, commands) over prose where appropriate.
- Never invent facts. Persist only what is supported by evidence.

---

## Classification categories

Each discovery must be tagged with exactly one category:

- **`EPHEMERAL`**
  Transient context with no lasting value (e.g., a one-off log line, a temporary state during a run).
  Do **not** persist.

- **`PROJECT_FACT`**
  A stable, verified fact about a specific product/repository (e.g., "service X listens on port 8080",
  "package manager is pnpm"). Persist in that product repository's knowledge.

- **`RUNTIME_DISCOVERY`**
  A verified fact about runtime behavior/environment (e.g., "web app is served under `/app`, not `/`").
  Persist in the relevant product repository's runtime knowledge.

- **`ARCHITECTURE_DISCOVERY`**
  A finding affecting architecture decisions (e.g., a provider limitation, a scaling boundary).
  May require an ADR and, if consequential, a human decision.

- **`DESIGN_DISCOVERY`**
  A finding affecting UI/design or the Design Contract.

- **`WORKFLOW_IMPROVEMENT`**
  A finding that would improve the reusable workflow/framework itself.

- **`AUTOMATION_OPPORTUNITY`**
  A manual step that could and should be automated (candidate for a script/CI job).

- **`CONTRADICTION`**
  A discovery that conflicts with existing documented knowledge or policy. Must be surfaced and
  reconciled; never silently overwrite conflicting knowledge.

---

## Authority levels

Persisting knowledge requires the appropriate authority:

1. **Automatic (verified operational knowledge)**
   `PROJECT_FACT`, `RUNTIME_DISCOVERY`, and other verified operational knowledge **may be persisted
   automatically** when supported by evidence.

2. **Independent review (reusable workflow changes)**
   `WORKFLOW_IMPROVEMENT`, `AUTOMATION_OPPORTUNITY`, and other **reusable workflow changes require
   independent review** before being adopted into the framework.

3. **Human decision (consequential architecture/governance)**
   `ARCHITECTURE_DISCOVERY` and other **consequential architecture/governance changes require a human
   decision**. `CONTRADICTION` involving governance/architecture escalates to this level.

---

## Product-specific vs. reusable framework findings

Always classify **where** a finding belongs:

- **Product-specific** findings update the **product repository's** knowledge.
- **Generally reusable** findings become **framework improvement candidates** and follow the
  independent-review / human-decision authority levels above.

### Worked example

- A product agent discovers its web app runs at `/app` rather than `/`.
  → This is a `RUNTIME_DISCOVERY` and a `PROJECT_FACT` for **that product repository**; persist it
  in that repo's runtime knowledge automatically (evidence-backed).

- The **larger lesson** — that browser agents must **discover the configured base path** instead of
  assuming `/` — is a `WORKFLOW_IMPROVEMENT`. It becomes a **framework improvement candidate** and
  requires independent review before adoption here.

### Worked example — do not ignore whole agent-configuration namespaces

Observed agent behavior: during source-control integration an agent added a `.gitignore` rule that
excluded the entire `.air/` and `.junie/` directories, simply to keep its current commit clean.

This is a `WORKFLOW_IMPROVEMENT` derived from observed behavior. The reusable lesson:

- Agents must **not introduce unrequested repository-policy changes** merely to simplify their
  current task.
- `.air/` and `.junie/` are **namespaces that may include both durable project configuration and
  transient session state**. JetBrains Air stores shareable configuration under `.air/` (e.g.
  worktree setup, Docker environment setup, MCP configuration, review prompts); Junie stores
  project-scoped configuration under `.junie/` (e.g. Skills). Some of these are intended to be
  committed.
- Ignore rules must therefore be **path-specific and evidence-based**, never exclude entire agent
  configuration namespaces. If the exact transient paths cannot be confidently identified, prefer
  **removing the broad ignore rule** rather than guessing.
- When uncertain whether a tool-owned file should be versioned, **classify the finding and leave it
  visible** (do not hide it via ignore rules) until the framework determines the correct policy.

This finding follows the **independent-review** authority level for `WORKFLOW_IMPROVEMENT`.

---

## Persistence checklist

Before persisting any discovery:

1. Confirm it is **evidence-backed** (not assumed).
2. Assign exactly one **category**.
3. Determine **product-specific vs. reusable**.
4. Apply the correct **authority level**.
5. Prefer **executable** persistence (test/script/config) over prose when feasible.
6. If it is a `CONTRADICTION`, surface and reconcile — do not silently overwrite.
