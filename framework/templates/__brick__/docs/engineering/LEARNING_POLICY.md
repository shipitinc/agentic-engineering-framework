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
excluded the entire `.air/` and `.junie/` directories, simply to keep its current commit clean. A
narrower follow-up then ignored only `.air/plans/` and `.junie/plans/` as "transient" plan artifacts;
new evidence shows even that was too strong — Air plan files may be useful project artifacts, and
Junie plans are explicitly designed to be editable/committable.

This is a `WORKFLOW_IMPROVEMENT` derived from observed behavior. The reusable lesson:

- Agents must **not introduce unrequested repository-policy changes** merely to simplify their
  current task.
- `.air/` and `.junie/` are **namespaces that may include both durable project configuration and
  transient session state**. JetBrains Air stores shareable configuration under `.air/` (e.g.
  worktree setup, Docker environment setup, MCP configuration, review prompts); Junie stores
  project-scoped configuration under `.junie/` (e.g. Skills). Some of these are intended to be
  committed.
- **Generated does not imply transient.** Tool-owned namespaces and generated artifacts must **not**
  be ignored without evidence about their lifecycle and repository value — including plan
  directories such as `.air/plans/` and `.junie/plans/`.
- **Default to visibility/versionability when uncertain.** Ignore rules must be **path-specific and
  evidence-based**, never exclude entire agent configuration namespaces. Ignore only paths
  demonstrated to be local/session-only and **not** useful for collaboration, provenance, replay, or
  review. Do not introduce replacement ignore rules unless supported by concrete evidence. If the
  exact transient paths cannot be confidently identified, prefer **removing the broad ignore rule**
  rather than guessing.
- When uncertain whether a tool-owned file should be versioned, **classify the finding and leave it
  visible** (do not hide it via ignore rules) until the framework determines the correct policy.

This finding follows the **independent-review** authority level for `WORKFLOW_IMPROVEMENT`.

### Worked example — validate framework tooling with a disposable POC before adoption

Before selecting the framework driver/tool, a disposable proof-of-concept validated
Dart + Mason + Git against the ADR 0001 model entirely **outside** the canonical tracked working
tree (throwaway repos in a temp area), leaving the canonical repository unchanged. The reusable
lessons (`WORKFLOW_IMPROVEMENT`, generally reusable):

- **Prove a candidate tool empirically in an isolated, disposable context before adopting it**, and
  keep that experimentation out of the canonical tracked tree so provenance/baseline stays intact.
- **Delegate merge mechanics to Git-native plumbing** (isolated worktree + synthetic
  base/local/incoming commits, or `git merge-tree --write-tree`); do **not** write a custom text
  merge engine.
- **Keep the rendering engine subordinate and replaceable**: authoritative provenance lives in a
  tool-independent manifest, never in rendering-tool metadata.

The concrete decision and full requirements are recorded in
[ADR 0002](adr/0002-dart-mason-git-framework-driver.md); this entry captures only the reusable
method. It follows the **human-decision** authority level (consequential architecture selection).

---

## Plan artifact retention policy

**Status:** `APPROVED WITH REFINEMENT` (human decision). Applies to agent-generated plan artifacts
(e.g. under `.air/plans/`, `.junie/plans/`, or any equivalent agent-platform plan directory),
regardless of which tool produced them. The policy is **tool-neutral**: it classifies artifacts by
**information authority**, never by artifact **origin**.

**Default:** Plan artifacts are **visible/versionable but not automatically committed**. Committing
is an exception that must be justified per-plan, never a default outcome of "an agent produced it."

**`LEAVE_UNTRACKED` is interim, not durable storage.** Untracked is a valid *temporary* working state
while the originating work/review cycle is still active and the local plan is still serving an
immediate working purpose — it is **not** a permanent archival disposition. Every plan that goes
untracked must eventually be **intentionally classified** into exactly one final disposition:
`COMMIT`, `PROMOTE_THEN_DELETE`, or `DELETE`. The framework must not rely on indefinitely untracked
local files for durable knowledge or audit evidence, because the local workspace may be discarded at
any time.

### Classification categories

- **`AUTHORITATIVE_PLAN`**
  The plan itself is the durable source of truth — no ADR/doc/contract/code/test captures its
  conclusion or rationale. **Commit** it.

- **`SUPPORTING_PLAN`**
  Process evidence for a decision whose durable conclusions are **already promoted** elsewhere (ADR,
  `WORKFLOW.md`, `WORK_STATE.md`, code, tests, configuration). **Do not commit**; leave
  visible/untracked **while the review cycle is active**, then finalize to `DELETE` (or
  `PROMOTE_THEN_DELETE` if any residual detail is later found not yet promoted).

- **`AUDIT_ARTIFACT`**
  Retained specifically for exact replay/provenance of a consequential, human-gated decision.
  **Commit only** when that exact replay/provenance has **material future value** (e.g.
  security-sensitive, production-promotion, or governance-change reviews) — not merely because a
  review occurred.

- **`PROMOTION_REQUIRED`**
  Contains durable knowledge (rationale, constraints, decisions) not yet reflected in an authoritative
  artifact (ADR, contract, workflow document, design document, issue, test, script, or
  configuration). **Promote** that knowledge into the correct artifact first; the plan then
  re-classifies as `SUPPORTING_PLAN` (untracked), not committed.

- **`TRANSIENT_PLAN`**
  Scratch/execution planning (task breakdown, step tracking) with no standalone informational value
  once executed.

- **`DUPLICATE_ARTIFACT`**
  Materially overlaps another plan/review covering the same scope and verdict.

  `TRANSIENT_PLAN` and `DUPLICATE_ARTIFACT` **may be deleted**, but only after an **explicit retention
  review** confirms no unique durable value remains — never deleted merely to make `git status` clean,
  and never deleted before any `PROMOTION_REQUIRED` content has been promoted or committed.

### Applying the policy

1. Read the plan's actual content and current repository state; do not classify from the filename or
   originating tool alone.
2. Check whether its durable conclusion/rationale already exists in an ADR, `WORKFLOW.md`,
   `WORK_STATE.md`, code, tests, or configuration. If yes → `SUPPORTING_PLAN` (do not commit).
3. If it holds durable knowledge found nowhere else → `PROMOTION_REQUIRED` (promote), or
   `AUTHORITATIVE_PLAN` (commit) if the plan itself is the intended permanent home.
4. If it is process/execution scaffolding with no standalone value → `TRANSIENT_PLAN`.
5. If it duplicates another plan's scope and verdict → `DUPLICATE_ARTIFACT`.
6. Only delete `TRANSIENT_PLAN`/`DUPLICATE_ARTIFACT` artifacts after an explicit, evidence-based
   retention review; never as a side effect of an unrelated task.
7. `LEAVE_UNTRACKED` is never the final answer. Once the originating work/review cycle is no longer
   active and the plan is no longer serving an immediate working purpose, it must be given a **final
   disposition** of exactly one of: `COMMIT` (it is `AUTHORITATIVE_PLAN` or a required
   `AUDIT_ARTIFACT`), `PROMOTE_THEN_DELETE` (it held durable knowledge that has now been promoted
   elsewhere), or `DELETE` (it is `SUPPORTING_PLAN`/`TRANSIENT_PLAN`/`DUPLICATE_ARTIFACT` with no
   unique durable value remaining). Record the approved final disposition (e.g. in `WORK_STATE.md`)
   before executing it.

This policy follows the **human-decision** authority level (consequential governance change) and is
expected to evolve based on future findings.

---

## Persistence checklist

Before persisting any discovery:

1. Confirm it is **evidence-backed** (not assumed).
2. Assign exactly one **category**.
3. Determine **product-specific vs. reusable**.
4. Apply the correct **authority level**.
5. Prefer **executable** persistence (test/script/config) over prose when feasible.
6. If it is a `CONTRADICTION`, surface and reconcile — do not silently overwrite.
