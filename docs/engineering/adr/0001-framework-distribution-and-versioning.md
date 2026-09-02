# ADR 0001 — Framework Distribution & Versioning Architecture

- **Status:** Accepted (human-approved architectural direction; implementation deferred)
- **Date:** 2026-09-02
- **Decision type:** `ARCHITECTURE_DISCOVERY` — consequential, `HUMAN_DECISION_REQUIRED`
  (see [LEARNING_POLICY.md](../LEARNING_POLICY.md) and
  [WORKFLOW.md](../WORKFLOW.md) step 6).
- **Scope:** How this canonical framework repository distributes and versions its policy/templates
  into separate **product repositories**. This ADR records the framework repository's **own**
  architecture decision; it is not a product-specific ADR.

---

## Context

This repository is the **canonical, reusable agentic engineering framework** — not an application.
Product repositories must receive framework policy in a way that:

- does **not** depend implicitly on this repository (or any package registry) **at runtime**
  (see [AGENTS.md](../../../AGENTS.md));
- records **deterministic provenance** of exactly which framework revision produced a product's
  artifacts;
- lets a product **safely upgrade** to newer framework revisions while **preserving valid
  product-specific changes**;
- keeps every framework change **reviewable** and subject to independent review.

Previously, the concrete mechanism for distributing/versioning framework artifacts to product
repositories was tracked as an `UNRESOLVED_FRAMEWORK_AREA` in [WORKFLOW.md](../WORKFLOW.md).

## Options considered

- **A — Runtime dependency (submodule / live pull):** product repos reference the framework repo
  (Git submodule, subtree pull at runtime, or fetch from a registry) at build/run time.
  Rejected: violates the "no implicit runtime dependency" invariant; couples product operation to
  framework availability.
- **B — Manual copy, no provenance:** copy files by hand with no recorded provenance.
  Rejected: no deterministic provenance; upgrades become guesswork; local modifications are
  indistinguishable from framework baseline.
- **C — Package/registry distribution only:** publish the framework as a package and install it.
  Rejected (for now): still introduces a registry dependency for normal operation and pulls in a
  release/distribution system before the model is validated.
- **E — Versioned copy-based installation with deterministic provenance and reviewable upgrades
  (Chosen):** the framework is **copied** (instantiated) into a product repository at a pinned
  revision; provenance is recorded deterministically; upgrades are performed as reviewable,
  isolated, 3-way-merge changes that preserve product-specific knowledge.

## Decision

Adopt **Option E**: **versioned copy-based framework installation with deterministic provenance and
reviewable 3-way-merge upgrades.**

The following refinements are authoritative:

1. **Authoritative provenance identifier.** `framework.revision` is the **authoritative, immutable
   provenance identifier**. `framework.version` is **human-readable metadata**. If the two ever
   disagree, **`framework.revision` controls provenance.**
2. **Hash-derived local-modification state.** The manifest stores **install/source hashes** for each
   installed artifact. There is **no persisted authoritative `locally_modified` boolean**. Local
   modification state is **derived** by comparing an artifact's current hash against its
   installed/source baseline hash.
3. **Separation of provenance and template answers.** `framework-manifest.yaml` records **framework
   provenance only**. If template answers (instantiation inputs) become necessary, they are stored
   in a **separate, machine-managed answers artifact** — never mixed into the provenance manifest.
4. **Isolated upgrade execution.** Framework upgrades must execute in an **isolated
   branch/worktree or equivalent isolated change context**. Upgrades must **not** directly mutate
   the product's main line.
5. **Reviewable upgrades.** Every upgrade must produce an **ordinary reviewable Git diff** and pass
   **independent review** before integration (consistent with
   [WORKFLOW.md](../WORKFLOW.md) steps 18–20 and the framework-change rules in
   [AGENTS.md](../../../AGENTS.md)).
6. **Product changes survive upgrades.** Merge/conflict resolution must **distinguish framework
   improvements from valid product-specific knowledge** (a 3-way merge against the installed
   baseline) rather than blindly preferring either side.
7. **No runtime coupling.** Normal operation of an instantiated product must require **no runtime
   access** to the framework repository or any package registry.

## Explicitly deferred (NOT decided here)

- **Framework driver / tooling is NOT selected.** **Copier** vs. a **custom/thin driver** (or any
  other tool) remains a **separate, later implementation decision**. This ADR selects the
  *architecture*, not the *tool*.
- No **bootstrap CLI**, **Copier integration**, **release system**, **tags**, or **package
  distribution** are implemented or mandated by this ADR.
- The **concrete hash algorithm**, manifest field layout beyond the principles above, and the
  exact answers-artifact format are implementation details to be decided when the driver is chosen.

## Consequences

- Provenance becomes deterministic and auditable via `framework.revision` + per-artifact hashes.
- Upgrades are safe, isolated, and reviewable; product-specific knowledge is preserved through
  3-way merges rather than overwrites.
- Products remain fully operable offline with respect to the framework (no runtime coupling).
- A driver/tool decision is still required before the distribution mechanism can be implemented; it
  will be recorded in a subsequent ADR.
- The `UNRESOLVED_FRAMEWORK_AREA` for distribution/versioning in [WORKFLOW.md](../WORKFLOW.md) is
  now **resolved at the architecture level**; the **driver selection** remains explicitly open.
