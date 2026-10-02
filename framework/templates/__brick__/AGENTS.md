# AGENTS.md — Product Repository (instantiated from framework)

<!--
  PLACEHOLDER TEMPLATE.
  This is instantiated into a PRODUCT repository from the canonical framework.
  Fill in product-specific values. Do NOT depend on the framework repo at runtime.
  Record the producing framework version in this product repo's `framework-manifest.yaml`.
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

## Orchestration

The top-level session is the **Engineering Manager / Orchestrator**. It **dispatches** work to
specialist subagents and integrates only independently reviewed results; it does not normally
implement production source itself. This is operationalized by the `aef-orchestrator` skill
which is the executable counterpart of the invariants above. It reuses the
existing lane skills (`aef-design-workflow`, `aef-design-review`, `aef-qa-contract`,
`aef-qa-execution`, `aef-implementation-workflow`, `aef-independent-review`, `aef-correction-loop`,
`aef-deployment-execution`, `aef-human-decision`, `aef-repository-learning`) and adds no lifecycle
stage and no human gate.

Dispatch uses the mandatory header in the `aef-orchestrator` skill § 4, rendered from
`.agents/skills/aef-orchestrator/templates/subtask-prompt.md`; results are returned per
`.agents/skills/aef-orchestrator/templates/subtask-report.md`. The lane skills themselves live under
`.agents/skills/aef-<skill-name>/SKILL.md`. `docs/engineering/WORKFLOW.md` and
`docs/engineering/STRUCTURED_RESULTS.md` remain authoritative
wherever the skill and those documents differ.

`.agents/` is the **canonical source of truth**. The `.claude/`, `.junie/`, and `.opencode/`
directories hold **generated** platform adapters rendered from it; they are never hand-maintained
content and must not be edited — change the canonical artifact under `.agents/` and regenerate. See
`docs/engineering/adr/0003-product-generic-orchestrator-skill.md` § Platform matrix and generated
adapters.

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
- Orchestration conventions (see `aef-orchestrator` skill § 3 — override the defaults for every
  convention your project does not want defaulted): TBD

## Framework provenance
- Framework revision: {{frameworkRevision}} — the **authoritative, immutable** provenance identifier.
- Framework version: TBD — human-readable metadata only (revision controls provenance if they differ).
- Both are recorded in this product repo's `framework-manifest.yaml`, which stores **provenance only** plus
  per-artifact baseline hashes. Framework upgrades arrive as **reviewable, isolated 3-way-merge**
  changes and must **not** create a runtime dependency on the framework repo. See the framework's
  ADR 0001 (`docs/engineering/adr/0001-framework-distribution-and-versioning.md`).
