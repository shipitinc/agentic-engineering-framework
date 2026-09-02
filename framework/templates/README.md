# framework/templates/

**Minimal placeholder** structure showing how product repositories will eventually receive
**versioned / instantiated copies** of appropriate framework policy.

> This is a placeholder only. The complete bootstrap/distribution system is **not** built yet.
> The concrete distribution and versioning mechanism is an
> `UNRESOLVED_FRAMEWORK_AREA` (see [../../docs/engineering/WORKFLOW.md](../../docs/engineering/WORKFLOW.md)).

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

## Versioning (placeholder)

Instantiated artifacts should record which framework version produced them. The exact scheme is
unresolved; see the source template [manifest.template.yaml](manifest.template.yaml) (instantiated
into a product repository as `framework-manifest.yaml`).
