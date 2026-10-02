# framework/templates/

Minimal structure showing how product repositories receive **versioned / instantiated
copies** of appropriate framework policy.

> The distribution/versioning **architecture** is decided — see
> [ADR 0001](../../docs/engineering/adr/0001-framework-distribution-and-versioning.md):
> **versioned copy-based installation** with **deterministic provenance** and **reviewable,
> isolated 3-way-merge upgrades**. The **driver/tool is built and chosen** — see
> [ADR 0002](../../docs/engineering/adr/0002-dart-mason-git-framework-driver.md): **Dart + Mason +
> Git**, with the CLI in `cli/`. Two concrete pieces of that tooling exist here:
> `cli/tool/generate_platform_adapters.dart` renders every `.claude/`, `.junie/`, and `.opencode/`
> adapter from the canonical `.agents/` tree, and `cli/test/platform_adapter_test.dart` is its
> `--check` drift test. The CLI's `bootstrap` and `upgrade` commands render the `__brick__/` Mason
> brick. Release tagging and package distribution remain **deferred** (see also
> [../../docs/engineering/WORKFLOW.md](../../docs/engineering/WORKFLOW.md)).

## Intent

- Product repositories should receive **versioned** copies of framework artifacts, not depend
  implicitly on this repository at runtime (see [AGENTS.md](../../AGENTS.md)).
- Templates here are the **source** for those instantiated copies.

## Layout

- `product-repo/` — skeleton of what a product repository receives from the framework.
  - `AGENTS.template.md` — starting point for a product repository's agent policy.
  - `docs/engineering/WORK_STATE.template.md` — starting point for a product repo's work state.
- `__brick__/` — the Mason brick: everything rendered into a product repository on `bootstrap` and
  diffed back into it on `upgrade`. Everything below is inside it.
  - `AGENTS.md`, `docs/engineering/**` — governance policy instantiated into the product repo.
  - `.agents/agents/**` — canonical Devin agent profiles.
  - `.agents/skills/**` — portable Agent Skills, including **`aef-orchestrator`** (the
    Manager-lane orchestration procedure: decompose → dispatch with declared ownership and full
    provenance → collect structured results → integrate only independently reviewed results) and
    **`aef-run-feature`** (the human-triggered entry point).
  - `.claude/`, `.junie/`, `.opencode/` — **generated** platform adapters (never hand-edited, never
    hand-maintained). Rendered from the canonical `.agents/` artifacts by
    `cli/tool/generate_platform_adapters.dart`; run
    `dart run cli/tool/generate_platform_adapters.dart` after changing `.agents/`, and verify with
    `--check` (the drift test runs it). The platform matrix is the single constant `kPlatforms` in
    that tool. opencode resolves `.agents/skills/` natively, so **no** `.opencode/skills/` is
    generated. Ownership covers the **generated subtrees only** — `.opencode/agents/` and
    `.opencode/command/`; the rest of `.opencode/` (`node_modules/`, `package.json`,
    `package-lock.json`, `.gitignore`) is opencode's own runtime output, not generated content.
    In a product repository this no-hand-editing rule is **advisory** — the generator and its drift
    test are framework tooling and are not instantiated there.
  - `.agents/skills/aef-orchestrator/templates/**` — dispatch contracts referenced by the
    `aef-orchestrator` skill: `subtask-prompt.md` (mandatory prompt header) and `subtask-report.md`
    (structured result).
  - `/run-feature` is surfaced per platform by a generated command adapter —
    `.claude/commands/run-feature.md`, `.junie/commands/run-feature.md`,
    `.opencode/command/run-feature.md` — each of which loads the canonical `aef-run-feature` skill.
    That skill is the canonical human entry point. Claude Code also gets
    `.claude/skills/aef-run-feature/SKILL.md`, so the workflow is deliberately exposed there as both
    `/run-feature` and `/aef-run-feature`; that is an **intentional alias of the same workflow**, not
    a second copy (see ADR 0003).
  - See [ADR 0003 § Platform matrix and generated adapters](../../docs/engineering/adr/0003-product-generic-orchestrator-skill.md)
    for the matrix, the tool mapping, and why adapters are generated rather than shared.

### Registration is structural, not a registry file

There is **no** skill registry. Per [ADR 0002](../../docs/engineering/adr/0002-dart-mason-git-framework-driver.md),
`framework-manifest.yaml` is the single authoritative provenance artifact and is generated from the
files Mason actually renders. Therefore:

- to **add** a framework artifact, add the file under `__brick__/` — it is instantiated on
  `bootstrap` and tracked (path + baseline hashes) in `framework-manifest.yaml`, and re-delivered by
  `upgrade` through the isolated 3-way merge;
- to **register it in the expectations**, add its instantiated path to the CLI's template-completeness
  test (`cli/test/bootstrap_integration_test.dart`, `KNOWN DEFECT D`), which asserts the exact managed
  artifact inventory and that each path exists on disk and in the manifest. That test exercises
  **`bootstrap` only**, so it is proof of **fresh instantiation and manifest registration — not of
  upgrade re-delivery**; it also binds a hardcoded absolute `frameworkRepoPath`, so it runs only on that
  host path (a pre-existing framework defect recorded in
  [../../docs/engineering/WORK_STATE.md](../../docs/engineering/WORK_STATE.md)).

Adding a second registry would create a second source of truth and is rejected
([ADR 0003](../../docs/engineering/adr/0003-product-generic-orchestrator-skill.md)).

## Template naming model (source vs. instantiated)

Framework-side **source templates** carry a `.template` marker in their filename. When a product
repository is instantiated, each source template is copied and **renamed** to its product-side name
(the `.template` marker is dropped). Do not confuse the two names:

| Framework-side source template (this repo) | Instantiated product-side file (product repo) |
| ------------------------------------------ | --------------------------------------------- |
| `manifest.template.yaml`                   | `framework-manifest.yaml`                      |

References to `framework-manifest.yaml` inside the product-side templates intentionally name the
**instantiated** file, not this source template.

## Provenance & versioning

Instantiated artifacts record deterministic **provenance** of which framework revision produced
them, per [ADR 0001](../../docs/engineering/adr/0001-framework-distribution-and-versioning.md):

- `framework.revision` is the **authoritative, immutable** provenance identifier; `framework.version`
  is human-readable metadata. If they disagree, `framework.revision` controls provenance.
- Per-artifact **install/source hashes** are recorded; local-modification state is **derived** by
  comparing current vs. baseline hashes (no persisted `locally_modified` flag).
- The manifest records **provenance only**. Template answers, if ever needed, live in a **separate,
  machine-managed answers artifact**.
- Upgrades run in an **isolated** branch/worktree, produce an ordinary **reviewable Git diff**, go
  through **independent review**, and use a **3-way merge** so product-specific changes survive.
- Normal product operation requires **no runtime access** to this framework repo or any registry.

See the source template [manifest.template.yaml](manifest.template.yaml) (instantiated into a product
repository as `framework-manifest.yaml`). The concrete driver/tool and hashing algorithm are
deferred (see ADR 0001).
