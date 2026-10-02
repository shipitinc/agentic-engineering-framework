# ADR 0004 — Upgrade by Synthetic Three-Way Merge, Delivered as a Review Branch

- **Status:** Accepted (material framework change; **independent review required** before promotion.
  It adds **no** lifecycle stage and **no** human gate — it repairs an existing documented command, so
  it is not a `HUMAN_DECISION_REQUIRED` governance change.)
- **Date:** 2026-10-02
- **Decision type:** `WORKFLOW_IMPROVEMENT` (a `LEARNING_POLICY.md` category); authority is
  **independent review**.
- **Scope:** The `framework upgrade` execution path in `cli/**` — how the three-way merge documented in
  [ADR 0001](0001-framework-distribution-and-versioning.md) is actually computed, where it runs, and
  how the result is delivered to the product repository. It does **not** change the manifest schema, the
  managed-artifact contract, the human-gate list, or the trusted-source rule itself; it only fixes
  **where** that rule is evaluated (see § Decision 1).

---

## Context

`framework upgrade` is specified as a three-way merge: **base** = the render of the pinned revision A,
**local** = the product repository's own state, **incoming** = the render of the target revision B. That
merge must reconcile product-local customizations of framework-managed files with upstream changes
between the two revisions.

The shipped implementation could not perform that merge. Five defects were found and reproduced against
a real product repository (a Flutter/melos workspace bootstrapped from this framework, pinned at
revision `7f1368f`):

1. **Preflight compared the wrong repository.** The trusted-framework-source check compared the
   **product** repository's `origin` against the approved framework URL. A product repository is a
   *different* repository, so the check could never pass for any real product; it only "worked" for
   checkouts whose origin happened to be the framework itself.
2. **The base revision was unreachable.** Rendering cloned the framework with `--depth 1`, so only the
   branch tip existed. Any upgrade whose *pinned base* was not the tip failed with "Revision not found",
   which is the normal case for a pinned-but-outdated product.
3. **The scratch checkout lived inside the repository being copied.** The worktree was created at
   `<productRepo>/.git/worktrees/upgrade-tmp`, then the product repository was copied into that
   directory — a directory **inside itself**. This aborted the upgrade with
   `FileSystemException ... '.git/info/refs' ... (Is a directory)`.
4. **The commit topology was inverted.** `upgrade-base` was *rewritten* from local product state after
   the local state had already been committed on top of it, so the merge base no longer corresponded to
   the base render, and the "merge" silently dropped the product's own changes from its result tree.
5. **The result was never delivered.** A conflicted merge returned early and left state in a temporary
   scratch repository; a clean merge left its only output in a scratch repository that was then deleted,
   plus a patch file written **into the product working tree** — which itself makes the next preflight
   fail (dirty-tree guard).

Net effect: `upgrade` had **never been executed successfully on a real product**. The only end-to-end CLI
test covered `bootstrap`, which is why ADR 0003 could only claim fresh instantiation and explicitly
recorded that "this test exercises `bootstrap` alone, so it is **not** proof of upgrade re-delivery".

## Decision

The merge is computed **without a working-tree copy at all**, using three synthetic commits whose
topology encodes the three inputs, and delivered as a **single review commit on top of the product's real
`HEAD`**.

### 1. Trusted-source validation is evaluated on the framework checkout

The approved-source rule is unchanged in substance: what gets rendered must come from the approved
canonical framework. It is evaluated against the **framework checkout that owns the resolved brick**
(`<brick>/../..`), not the product repository. A product repository needs only an existing `origin`.
Under `FRAMEWORK_CLI_TEST_MODE=true` this check is skipped, like the existing dirty-tree guard, so tests
can render from a sandbox framework.

### 2. Rendering prefers a local framework checkout, and uses full history

Rendering clones the framework **with full history** (no `--depth`), then checks out the requested
revision. When the CLI's own framework checkout already contains the requested revision, that checkout is
used as the clone source instead of the network URL. This removes the network round-trip for local
upgrades and makes the operation hermetic under test.

### 3. The merge is computed by `git merge-tree` over synthetic refs

A scratch clone of the **product** repository is created in the system temp directory — outside the
product repository, so no self-copy and no worktree bookkeeping inside the product's `.git`. In that
clone, three commits are created from **trees built directly from rendered directories**:

| ref | parent | tree |
|---|---|---|
| `refs/aef-upgrade/base` | *(root)* | render of revision A |
| `refs/aef-upgrade/local` | `base` | the product's `HEAD` tree |
| `refs/aef-upgrade/incoming` | `base` | render of revision B |

Because `local` and `incoming` share `base` as parent, `git merge-tree --write-tree --name-only local
incoming` performs exactly the specified merge, with `base` as the merge base, **in memory** — no
working tree is cleared, copied, or re-committed, so no input can be lost. Trees are built with
`git add -A -f` against a temporary index so that a product `.gitignore` cannot silently exclude
rendered framework paths (e.g. `.claude/`).

`merge-tree` returns the merged tree on its first stdout line and the conflicted paths after it, with
exit status `0` (clean) or `1` (conflicts). Conflicted files carry inline conflict markers in the merged
tree, which is what makes them reviewable and fixable by ordinary editing.

### 4. Delivery is one commit on the product's real history

The merged tree is delivered as a single commit whose **first parent is the product's real `HEAD`**,
pushed to the product repository as `framework/upgrade-<revisionA>-<revisionB>`. Consequences:

- the branch is reviewable with ordinary commands (`git diff HEAD..framework/upgrade-…`), and it merges
  into `main` by ordinary fast-forward/merge because it shares real history;
- conflicted artifacts are fixed by editing the files on that branch — no rebase, no unrelated-histories
  flag, no `allow-unrelated-histories` workaround;
- **the product working tree and index are never mutated.** The review patch is therefore *not* written
  into the product repository (writing it there would trip the dirty-tree guard on the next run); the
  message reports the `git` command that reproduces the diff.

The upgrade branch is pushed **last**, after the merge and the manifest update have succeeded, so a
failed upgrade leaves no ref behind. An upgrade branch that already exists is refused rather than
overwritten, so a re-run cannot silently discard a review in progress.

### 5. The delivered commit refreshes the manifest

`framework-manifest.yaml` is regenerated **inside the merged tree** and therefore shipped with the
branch, so a reviewed upgrade leaves the product pinned to the revision it just adopted instead of a
stale one. Per artifact, `source_hash` is the hash of the incoming render (what the framework ships at
revision B) and `install_hash` is the hash of the merged file (what the product will actually carry), so
a locally customized artifact stays visible as `source_hash != install_hash`. Artifacts that upstream
deleted are dropped from the manifest; product files that are not framework-managed are never listed.

### 6. The manifest pins the exact revision, not the string that was typed

The requested target may be an abbreviation (`e37b2a3`). The refreshed manifest records the full object
id the render actually resolved to (`e37b2a3fa344…`), because a pin must be unambiguous for a later
upgrade to verify and for a reviewer to audit. Branch names keep the short form for readability.

### 7. Brick staging artifacts are removed from the delivered tree and reported

Mason renders only `__brick__/**`. Everything else the brick ships — `brick.yaml`,
`manifest.template.yaml`, `product-repo/**`, `README.md` — plus the brick's own `__brick__/` directory
are build inputs that no render can produce. A product holding a **byte-identical copy** of a file the
brick ships at that exact relative path was bootstrapped from the brick *directory* instead of from a
render; those copies are excluded from the merge, deleted in the delivered commit, and listed in the
result so that accepting the branch is an explicit human decision.

Byte identity is required on purpose. A product that merely shares a name with a brick input (`README.md`
is the common case) is product content and is preserved untouched.

Leaving such copies in place is not a neutral option: git pairs a byte-identical copy with the base
render file as a **rename**, so an untouched product copy is reported as `rename/rename` against an
unrelated upstream move. On the first real product upgrade this manufactured 11 of 15 conflicts out of
nothing.

### 8. A product with no render lineage adopts the incoming render

If the product's manifest claims no path that the pinned revision actually renders, the product was never
rendered and the merge base is fiction. Merging against fiction reports every framework path as a local
deletion, so the base is replaced by git's empty tree: the incoming render is **adopted**, product-owned
files are kept as-is, and the result states `Adopted the incoming render: yes` plus a blocker requiring a
human to review every added artifact.

A product that owns a path the framework also renders (`AGENTS.md`, `docs/engineering/WORK_STATE.md`)
then conflicts on exactly that path — the true, resolvable disagreement — instead of colliding with
dozens of fabricated modify/delete conflicts.

### 9. Scratch state is always cleaned up

The temporary scratch clone and both render directories are deleted on every exit path, success or
failure. Because the deliverable is a ref in the product repository, keeping scratch state is never
necessary for a human to continue the work.

## Consequences

- `upgrade` becomes executable and testable end-to-end; a new hermetic test covers a clean merge, a
  conflicting merge, product-state preservation, manifest refresh, re-run refusal, and scratch cleanup.
- The upgrade cannot silently lose product changes: product-local edits participate in the merge as the
  `local` side, and the delivered commit's parent is the product's real `HEAD`.
- A conflict is no longer a dead end — the branch exists and is reviewable, and the result family stays
  `upgradeConflict` with `humanActionRequired`, so automation still stops.
- Requires `git >= 2.38` for `git merge-tree --write-tree` (macOS git 2.54 and ubuntu-latest both
  satisfy this); the CLI fails with a clear blocker otherwise.
- `merge-tree` reports only content/path conflicts. A file deleted upstream while modified locally
  surfaces as a modify/delete conflict, and a locally modified artifact that upstream deletes is
  additionally reported by the change classifier, so deletion is never applied silently.
- The manifest is now rewritten on upgrade; a product that keeps its manifest untouched after accepting
  the branch will still be detected as pinned to the old revision.
- A product bootstrapped from the brick directory is repaired by the upgrade rather than reported as
  broken: it receives the render it never had, its unverifiable staging copies are removed, and its own
  files are untouched. This was found by running the engine against the first real product
  (`TeamHub`), whose manifest claimed 21 brick build inputs and no rendered artifact at all.
- Staging copies that are *not* byte-identical (someone edited `__brick__/AGENTS.md`) are deliberately
  **kept** and reported as stale manifest entries, because that content may carry product knowledge the
  human wants to port. They survive as unreachable files that no future render will ever claim.

## Alternatives considered

- **`git merge` in a checked-out worktree (the previous design).** Rejected: it requires mutating and
  re-committing a working tree to construct history, which is what produced the self-copy and the
  inverted topology, and it cannot deliver a result to the product repository without leaving state
  behind.
- **`git apply --3way` of the upstream delta onto the product tree.** Rejected: it produces `.rej` files
  rather than conflict markers, does not model add/delete conflicts as precisely, and is not the merge
  ADR 0001 documents.
- **Applying upstream changes directly to the product working tree.** Rejected: it destroys the
  preflight dirty-tree guarantee for any subsequent command and leaves no reviewable artifact.
- **Hand-merging the framework artifacts manually in the product.** Rejected: not reproducible, not
  verifiable, and it silently depends on a human noticing that a generated artifact changed.