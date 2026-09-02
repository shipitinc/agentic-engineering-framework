# framework/templates/

**Minimal placeholder** structure showing how product repositories will eventually receive
**versioned / instantiated copies** of appropriate framework policy.

> This is a placeholder only. The bootstrap/distribution **tooling** is **not** built yet.
> The distribution/versioning **architecture** is now decided — see
> [ADR 0001](../../docs/engineering/adr/0001-framework-distribution-and-versioning.md):
> **versioned copy-based installation** with **deterministic provenance** and **reviewable,
> isolated 3-way-merge upgrades**. The concrete **driver/tool** (e.g., Copier vs. a custom/thin
> driver), any bootstrap CLI, release system, tags, or package distribution remain **deferred**
> implementation decisions (see also [../../docs/engineering/WORKFLOW.md](../../docs/engineering/WORKFLOW.md)).

## Intent

- Product repositories should receive **versioned** copies of framework artifacts, not depend
  implicitly on this repository at runtime (see [AGENTS.md](../../AGENTS.md)).
- Templates here are the **source** for those instantiated copies.

## Layout (initial, minimal)

- `product-repo/` — skeleton of what a product repository receives from the framework.
  - `AGENTS.template.md` — starting point for a product repository's agent policy.
  - `docs/engineering/WORK_STATE.template.md` — starting point for a product repo's work state.

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
