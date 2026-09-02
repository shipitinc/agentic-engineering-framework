# ADR 0002 — Dart + Mason + Git Framework Driver

- **Status:** Accepted (human-approved architecture; production implementation deferred and phased)
- **Date:** 2026-09-02
- **Decision type:** `ARCHITECTURE_DISCOVERY` — consequential, `HUMAN_DECISION_REQUIRED`
  (see [LEARNING_POLICY.md](../LEARNING_POLICY.md) and [WORKFLOW.md](../WORKFLOW.md) step 6).
- **Scope:** Selects the concrete **framework driver / tooling** that implements the copy-based
  distribution/upgrade architecture accepted in
  [ADR 0001](0001-framework-distribution-and-versioning.md). This ADR selects the *tool*; ADR 0001
  selected the *architecture*. ADR 0001 is **not** modified by this ADR.

---

## Context

[ADR 0001](0001-framework-distribution-and-versioning.md) established the framework
distribution/versioning **architecture** — versioned copy-based installation with deterministic
provenance and reviewable, isolated 3-way-merge upgrades — but **intentionally deferred** the
concrete **bootstrap/upgrade driver** (e.g., Copier vs. a custom/thin driver) to a separate later
implementation decision.

An empirical proof-of-concept ("Option C2") has now validated **Dart + Mason + Git** as the
implementation mechanism for exactly the ADR 0001 model. The POC exercised bootstrap rendering,
exact-revision provenance, per-artifact hashing, clean and conflicting upgrades, additions,
deletions, renames, product-only isolation, dirty-tree preflight, isolated-worktree execution,
failure recovery, idempotent re-runs, headless machine-readable execution, and AOT-compiled Dart
execution. The POC returned `DART_MASON_GIT_POC_PASS` against all defined pass criteria, with **no
architecture blockers** and all limitations classified as wrapper-mitigable.

This ADR records that human decision and converts the POC findings into explicit implementation
requirements, contracts, and a phased plan. It **does not** implement the production CLI.

## Decision

Adopt **Dart + Mason + Git** as the framework driver, with `framework-manifest.yaml` as
authoritative provenance:

- **Dart** → framework CLI / orchestration.
- **Mason** → template rendering only.
- **Git** → merge / versioning mechanics (native 3-way merge; **no custom text merge engine**).
- **`framework-manifest.yaml`** → authoritative provenance, independent of Mason.
- **Mason metadata** → non-authoritative implementation detail only.
- **Custom text merge engine** → **PROHIBITED**.

This architecture is approved for framework implementation. It does **not** by itself make the driver
production-ready; production readiness is established only after the phased implementation and
independent review below.

## Responsibility boundary

**The Dart framework CLI owns:**

- repository validation;
- canonical-repository checks;
- dirty-tree checks;
- branch/worktree creation;
- isolated upgrade lifecycle;
- trusted framework-source validation;
- exact framework revision resolution;
- `framework-manifest.yaml` (read/write, authoritative);
- artifact path inventory;
- source/install baseline hashing;
- template input management;
- local modification detection;
- upgrade policy;
- add/delete/rename classification;
- conflict detection;
- modify/delete handling;
- result classification;
- human-gate integration;
- independent-review gating;
- learning-policy integration;
- rollback/abort behavior;
- structured output;
- deterministic exit codes.

**Mason owns only:**

- rendering;
- variable substitution;
- template/brick structure.

**Mason must NOT own:**

- authoritative provenance;
- upgrade-state authority;
- repository policy;
- Git isolation;
- merge policy;
- human gates;
- review gates;
- learning policy.

**Git owns:**

- repository history;
- commit/revision identity;
- worktrees;
- native 3-way merge mechanics;
- conflict representation;
- ordinary reviewable diffs.

**No custom text merge engine may be written.** All 3-way merge mechanics are delegated to Git-native
plumbing.

## Provenance rule

`framework-manifest.yaml` remains **authoritative and independent of Mason**. At minimum it must
eventually represent:

- framework source identity;
- authoritative exact framework revision (`framework.revision`, immutable; authoritative over the
  human-readable `framework.version` per ADR 0001);
- human-readable framework version;
- product instantiation/upgrade timestamps;
- managed artifact paths;
- source/install baseline hashes (local-modification state is **derived** from current-vs-baseline
  hash comparison, not a persisted flag);
- template input provenance where required (kept separate from provenance per ADR 0001).

**Mason-specific metadata (brick caches, lockfiles, tool state) must never become required** to
understand framework provenance. Existing product repositories must remain understandable even if
Mason is later replaced (see mitigation 11).

## POC findings recorded

The architecture POC (`DART_MASON_GIT_POC_PASS`) empirically established:

- Mason renders nested directories correctly.
- Mason renders `.air/` and `.junie/` (dot-directory) paths correctly.
- Exact framework revision provenance can be guaranteed independently of Mason.
- Per-artifact hashes are deterministic and stable for unchanged content.
- Clean A → B upgrades work.
- Non-overlapping product-local modifications survive framework updates.
- Overlapping changes produce **visible conflicts** rather than silent overwrite.
- Framework file additions are manageable and appear in the reviewable diff.
- Framework file deletion is safe **only** when wrapper policy accounts for local-modification state.
- Rename behavior is workable but requires **explicit** wrapper handling.
- Product-only files remain untouched.
- Dirty destination repositories require preflight rejection.
- Isolated Git worktree upgrades contain all partial/failing state.
- Failed worktrees can be abandoned without modifying product `main`.
- Re-running an already-applied upgrade can safely no-op.
- Non-interactive/headless execution is viable.
- AOT-compiled Dart execution is viable.
- Machine-readable structured output and deterministic exit codes are viable.
- Git-native merge mechanics are sufficient.
- No custom textual merge engine is required.
- No architecture blockers were found.

## Mandatory mitigations (implementation requirements)

These are derived from POC findings and are **required** for the production driver:

1. **Dirty repository guard.** Refuse an upgrade before mutation if the intended change context is
   not clean/isolated.
2. **Worktree isolation.** All upgrades occur in a dedicated branch/worktree or equivalent isolated
   Git context. Never mutate `main` directly.
3. **Product-only path isolation.** Upgrade mechanics operate only on framework-managed artifact
   paths. Product-only files must remain untouched (hard requirement).
4. **Delete policy.** If framework B deletes a previously managed file: a clean/unmodified product
   copy may be deleted automatically; a locally modified product copy must **not** be silently
   deleted; classify as conflict/correction/human decision per policy.
5. **Rename policy.** Rename-like framework changes require explicit detection/handling. Do not
   assume every add+delete pair is automatically safe to classify as a rename.
6. **Modify/delete conflict policy.** Explicitly detect product-modified/framework-deleted and
   equivalent conflict classes.
7. **Conflict guard.** Any unresolved Git conflict blocks success/integration.
8. **No silent overwrite.** Local product changes cannot be overwritten without a visible conflict or
   an explicitly authorized policy.
9. **No Mason hook execution.** Framework templates must not rely on Mason hooks/executable template
   logic for critical behavior. Orchestration belongs in the Dart CLI.
10. **Trusted source.** Bootstrap/upgrade source must be restricted to the approved framework source
    and exact revision.
11. **Manifest independence.** Existing product repos must remain understandable even if Mason is
    later replaced.
12. **Re-run safety.** Already-at-target upgrades must no-op cleanly.
13. **Machine-readable results.** CLI operations must expose stable structured results and
    deterministic exit codes.
14. **Failure containment.** Partial failures remain inside the isolated worktree context and can be
    abandoned safely.
15. **Hashing.** Local-modification detection derives from current content hash vs stored baseline
    hash.
16. **Path safety.** Validate all managed paths and prevent path traversal / out-of-repo writes.

## Exit-code contract (initial, semantic)

Stable **semantic result categories** are defined now; exact numeric values may be refined during
implementation if evidence suggests a better design, but the categories are stable:

| Code | Semantic category            | Meaning                                              |
|------|------------------------------|------------------------------------------------------|
| `0`  | `SUCCESS`                    | success / no blocking issue                          |
| `10` | `MERGE_ACTION_REQUIRED`      | merge / conflict / correction required               |
| `20` | `PREFLIGHT_POLICY_FAILURE`   | preflight / policy failure (e.g., dirty tree)        |
| `30` | `HUMAN_DECISION_REQUIRED`    | human decision required                              |
| `40` | `INTERNAL_TOOL_FAILURE`      | internal / tool failure                              |

The POC validated deterministic propagation of `0` (clean), `10` (conflict), and `20` (dirty
preflight) through both the shell driver and the AOT-compiled Dart CLI.

## Structured result contract (conceptual)

The future CLI must emit stable, machine-readable result families (JSON or equivalent). These are
defined conceptually now and **not implemented** here:

- `BOOTSTRAP_COMPLETE`
- `BOOTSTRAP_BLOCKED`
- `UPGRADE_READY_FOR_REVIEW`
- `UPGRADE_NOOP`
- `UPGRADE_CONFLICT`
- `UPGRADE_BLOCKED`
- `HUMAN_DECISION_REQUIRED`
- `VALIDATION_FAILED`
- `INTERNAL_ERROR`

## Git merge mechanism

The POC evaluated two Git-native approaches; both avoid any custom text merge:

- **Recommended (primary):** an isolated worktree with synthetic base/local/incoming commits and a
  native `git merge`, producing ordinary conflict markers, unmerged index state (`UU`/`UD`), and an
  ordinary reviewable diff. This contained all partial/failing state and could be abandoned cleanly.
- **Alternate (evaluated):** `git merge-tree --write-tree` for a worktree-free, index-free 3-way
  merge that reports conflicts via non-zero exit and written trees. Useful for read-only conflict
  preview.

The production driver must be able to: identify base/local/incoming; invoke Git deterministically;
detect conflicts; avoid touching unmanaged files; preserve product-specific changes; and produce
ordinary reviewable diffs.

## Implementation phases (deferred)

The production CLI is **not** implemented in this decision. Implementation proceeds in discrete,
independently reviewable phases; they must **not** be combined into a single task:

- **PHASE 1 — CLI skeleton + domain model.** Dart package/executable, command structure, structured
  output, exit-code semantics. No real bootstrap/update yet.
- **PHASE 2 — manifest + hashing.** Authoritative manifest parser/writer, hash calculation, managed
  artifact inventory, modification detection.
- **PHASE 3 — bootstrap.** Git/repo preflight, exact framework revision resolution, Mason rendering,
  manifest generation, initial hashes, structured result.
- **PHASE 4 — upgrade core.** Isolated worktree creation, render base, render incoming, Git-native
  3-way application, add/delete/rename classification, conflict detection, reviewable diff.
- **PHASE 5 — safety hardening.** Dirty-tree guards, modify/delete policy, path validation,
  re-run/no-op logic, failure recovery, trusted-source restrictions.
- **PHASE 6 — agent/workflow integration.** Independent-review handoff, `HUMAN_DECISION_REQUIRED`
  integration, learning classification, framework `WORK_STATE` updates.
- **PHASE 7 — cross-platform/headless.** macOS, Linux, Windows, GitHub Actions, Air, Junie CLI, and
  AOT executable distribution evaluation.
- **PHASE 8 — release/adoption.** Independent review, production-readiness assessment, version/tag/
  release mechanism, and bootstrapping a real throwaway product from the canonical framework. Only
  then is the driver considered production-ready.

## Security

- **Mason hooks/executable template logic are avoided** (mitigation 9); the POC required no hooks.
  Any future need for a hook is a recorded risk and must be reviewed.
- **Git command injection** and **path traversal** are risks the Dart CLI must defend against
  (mitigations 10, 16): validate managed paths, restrict to the trusted framework source and exact
  revision, and invoke Git with argument lists rather than shell interpolation.

## Consequences

- The ADR 0001 driver selection — previously an explicitly open item — is now **resolved**:
  Dart + Mason + Git with an authoritative `framework-manifest.yaml`.
- Mason is subordinate and replaceable; Git owns merge mechanics; no custom text merge exists.
- Provenance remains deterministic, Mason-independent, and auditable.
- The driver is **not** production-ready merely because the POC passed; readiness follows the phased
  plan and independent review (Phase 8).
- Subsequent phase work and material framework changes require independent review; consequential
  governance changes require human approval.
