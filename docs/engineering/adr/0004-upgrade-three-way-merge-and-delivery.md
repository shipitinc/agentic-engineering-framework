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
The remote is compared as a **repository identity** (`host/owner/repo`), not as a string: the URL and
scp-like forms are normalized first — host lowercased, `user[:password]@` and `:port` dropped,
trailing `/` and `.git` removed, redundant separators collapsed — so every spelling of the approved
repository
(`https://github.com/shipitinc/agentic-engineering-framework.git`,
`https://token@github.com/…`, `ssh://git@github.com/…`, `git@github.com:…`,
`github.com:shipitinc/…`) is accepted, while a different repository or a local path is not.

**`FRAMEWORK_CLI_TEST_MODE` is a deliberate test-only seam.** When it is set to `true`, a production
build of this CLI skips **both** the trusted-framework-source check **and** the dirty-tree guard.
That is the price of hermetic sandbox tests, and it is a seam, not a policy: the flag exists so tests
can render from a sandbox framework and run in intentionally dirty or non-repository sandboxes.
Neither check is weakened for any caller that does not set it.

**Open question, deliberately unresolved here.** Whether a framework source that is *not* a checkout
of this repository may be accepted — and therefore how the ADR-0002 brick-content hash applies to it
— remains an open `HUMAN_DECISION`. This ADR changes neither the rule nor its evaluation point.

### 2. Rendering prefers a local framework checkout, and uses full history

Rendering clones the framework **with full history** (no `--depth`), then checks out the requested
revision. When the CLI's own framework checkout already contains the requested revision, that checkout is
used as the clone source instead of the network URL. This removes the network round-trip for local
upgrades and makes the operation hermetic under test.

An explicitly selected framework root (`frameworkRootOverride`) is **authoritative**: it is used
verbatim and never falls back to the network, so a caller that pinned a framework checkout cannot
silently end up rendering the canonical source instead. A revision that checkout does not contain fails
loudly here, which is what keeps the test suite off the network.

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

Content classification on top of the merged tree follows git: a base path the incoming revision no longer
renders is a candidate rename source, and a rename is recorded **only** when the candidate is absent from
the incoming render (and absent from the merged tree). Otherwise upstream merely *copied* a path's old
content elsewhere, and reporting that as a rename would erase the original path's own change from the
report and suppress its deletion.

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
overwritten, so a re-run cannot silently discard a review in progress. The check probes
`refs/heads/<branch>` and `refs/remotes/origin/<branch>` locally, and the **remote** with
`git ls-remote --exit-code --heads` — the remote is where a previous run actually left the branch, and
a branch that exists only there is refused with the same clear message instead of being pushed over. A
remote that cannot be probed at all is refused as well: "could not ask" is not evidence that the
branch is absent.

The push is issued **by the product repository**, against the remote configured in the product's own
git config. The scratch clone's `origin` is the product's *local path* — git configures the clone
source as the clone's remote whenever the source is a path — so a push from the scratch clone is a
local-to-local write: it exits `0`, creates a ref inside the product repository, and reaches nothing
else. A product with no resolvable remote is refused before any state is created. The delivered commit
is created in the scratch clone, so its objects are moved into the product repository under
`refs/aef-upgrade/delivered` before the push and that ref is dropped again on both paths; a failed
upgrade therefore leaves no ref behind. After the push, the local review branch is created in the
product repository so the review command below resolves by its bare name — a ref and objects under
`.git`, never a working-tree or index change.

### 5. The delivered commit refreshes the manifest

`framework-manifest.yaml` is regenerated **inside the merged tree** and therefore shipped with the
branch, so a reviewed upgrade leaves the product pinned to the revision it just adopted instead of a
stale one. Per artifact, `source_hash` is the hash of the incoming render (what the framework ships at
revision B) and `install_hash` is the hash of the merged file (what the product will actually carry), so
a locally customized artifact stays visible as `source_hash != install_hash`. Artifacts that upstream
deleted are dropped from the manifest; product files that are not framework-managed are never listed.

`template_inputs` is refreshed, not carried forward. `frameworkRevision` is framework-controlled — it is
the value the render substituted into the managed provenance lines — so a value left at the original
instantiation pin is a false record of what the product's artifacts were rendered from. Any other key
is preserved. Because the renderer never reads `template_inputs` back, recording a product input there
can never become an input to a later render.

### 6. The manifest pins the exact revision, not the string that was typed

The requested target may be an abbreviation (`e37b2a3`). The refreshed manifest records the full object
id the render actually resolved to (`e37b2a3fa344…`), because a pin must be unambiguous for a later
upgrade to verify and for a reviewer to audit. Branch names keep the short form for readability.

**The render substitutes that same resolved object id.** `{{frameworkRevision}}` is filled with the
commit id the checkout resolved to, never with the string the caller typed. A managed provenance line
therefore always carries exactly the identifier `framework.revision` pins, so the next upgrade's base
render of revision A reproduces the file the product already has, and the pin bump is the clean
one-sided change it should be. Substituting the typed string instead makes the *first* upgrade of an
abbreviated target deliver a product whose provenance line disagrees with its own manifest, and the
*next* upgrade then sees a local edit against that line as well as an upstream change to it — a
modify/modify conflict on a field whose only correct value was never in dispute.

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

The `git >= 2.38` gate is evaluated **before** the scratch clone is created, so an unsupported git
leaves nothing behind at all and no cleanup can fail; every later cleanup path goes through the same
best-effort disposal that swallows `FileSystemException` instead of letting it escape as an
`internalError`.

## Consequences

- `upgrade` becomes executable and testable end-to-end; the hermetic suite covers a clean merge, a
  conflicting merge, product-state preservation, manifest refresh, re-run refusal (local, remote-only
  *and* real-remote-only branch, plus an unreadable remote), the git version gate, the `git add -A -f`
  defense against a product `.gitignore`, rename-vs-copy classification, stale manifest entries, and
  scratch cleanup.
- Delivery is asserted against a **real bare remote**, not against the product's local refs. Asserting
  locally cannot distinguish "delivered" from "written into the product repository", which is what let
  a local-path push pass as delivery.
- The upgrade tests perform **no network access**: an explicitly selected framework root is
  authoritative, so an absent revision fails from the sandbox framework instead of cloning the canonical
  source. The failure-path test asserts that the reported source is the sandbox, not the canonical URL.
- The upgrade cannot silently lose product changes: product-local edits participate in the merge as the
  `local` side, and the delivered commit's parent is the product's real `HEAD`.
- A conflict is no longer a dead end — the branch exists and is reviewable, and the result family stays
  `upgradeConflict` with `humanActionRequired`, so automation still stops.
- Requires `git >= 2.38` for `git merge-tree --write-tree` (macOS git 2.54 and ubuntu-latest both
  satisfy this); the CLI fails with a clear blocker otherwise, before creating any state.
- `merge-tree` reports only content/path conflicts. A file deleted upstream while modified locally
  surfaces as a modify/delete conflict, and a locally modified artifact that upstream deletes is
  additionally reported by the change classifier, so deletion is never applied silently.
- The `modified` and `product-customizations-preserved` buckets deliberately **overlap**: a path the
  framework changed that the product had also changed is both an upstream modification and a preserved
  customization. Making them exclusive would drop such a path out of "did anything change?", and a
  delivered upgrade would be reported as a no-op.
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

## Amendment (2026-10-03) — delivery reaches the remote, and the render carries the resolved pin

Two defects in the delivered engine were reported from outside by a consumer of this framework
(`shipitinc/agentic-engineering-framework` issues #3 and #4), both reproduced here and both repaired.
Neither changes a decision in this ADR: §4 already specifies delivery *to the product repository* and a
remote-only re-run refusal, and §6 already specifies an unambiguous pin. Both repairs make the
implementation do what those sections say.

### A1 — delivery went to a local path, not to the remote (§4)

The delivered commit was pushed from the scratch clone with `git push origin <sha>:refs/heads/<branch>`.
Git configures the clone source as the clone's remote whenever the source is a **path**, and the scratch
clone is created from the product's local path — so `origin` there was the product directory itself. The
push was a local-to-local write: exit `0`, a new ref inside the product repository, and no ref anywhere on
the hosting provider. The reported run therefore looked successful while `git ls-remote origin
'refs/heads/framework/*'` returned nothing.

Three things followed from that single cause:

1. The re-run refusal of §4 — which only works against the **remote** — never saw a branch that a previous
   run had delivered, so a re-run would push over a review in progress. (Its `refs/remotes/origin/<branch>`
   probe cannot compensate: it describes what a fetch brought in, not what a push left behind.)
2. A run that promises the product repository is never mutated wrote a ref into it.
3. The hermetic suite could not catch it: with a local-path remote, the assertion "the branch is on the
   remote" was satisfiable by a local-path assertion. The fixtures' remote was not even a git repository.

**Repair.** The push is issued by the **product repository** against the remote in its own config
(§4 as amended above); the scratch clone's `origin` is now documented as unusable for delivery. The remote
is probed with `ls-remote` for the re-run refusal, an unprobeable remote is refused rather than assumed
branch-free, and a product with no resolvable remote is refused before any state exists. The fixtures'
remote is a **real bare repository**, and delivery is asserted by reading the ref out of it, so a local
ref cannot satisfy the assertion.

### A2 — the render carried the typed target, not the resolved pin (§6)

`{{frameworkRevision}}` was substituted with the revision **string the caller passed**, while
`framework.revision` and the refreshed `template_inputs.frameworkRevision` were left at, or computed
independently of, the resolved object id. Two consequences:

- `template_inputs.frameworkRevision` was carried forward verbatim and stayed frozen at the value the
  product was instantiated with — a false record of what its artifacts were rendered from.
- The two spellings made the managed provenance line (`AGENTS.md`,
  `docs/engineering/WORK_STATE.md`) collide with itself on the **second** upgrade. Upgrade 1 with an
  abbreviated target delivered `Framework revision: e37b2a3` while the manifest pinned
  `e37b2a3fa344…`. On upgrade 2 the base render of the pinned revision produced the full id, the product
  still carried the abbreviation, and the incoming render changed the line again: modify/modify, on a
  field whose only correct value was never in dispute. Reproduced on the first real product
  (`TeamHub`) as 2 conflicts confined to the provenance line, and reproduced hermetically as a
  two-upgrade test.

**Repair.** The render substitutes the **resolved object id** of the checked-out revision (§6 as amended
above), so the rendered line and the manifest pin are the same immutable identifier by construction, and
the bump is a clean one-sided change. `template_inputs` is refreshed from that same resolved value rather
than carried forward. The renderer still derives its inputs from the revision alone and never reads
`template_inputs`, so the recorded product input cannot become an input to a later render — which also
closes the concern raised alongside issue #3 about a non-checkout framework source.

A product delivered by the *pre-repair* engine still carries the abbreviated pin. A3 removes the one-time
conflict that state would otherwise cause.

### A3 — a pin spelled differently is the same pin, not a competing edit

**Context.** A2 fixes the engine going forward, but every product already delivered by the pre-repair
engine still carries `Framework revision: e37b2a3` against a manifest pinning `e37b2a3fa344…`. On its next
upgrade the base render produces the full id, the product still carries the abbreviation, and incoming
changes the same line: modify/modify on a field whose only correct value was never in dispute. Repairing
the engine therefore leaves every existing product with a conflict it has no reason to adjudicate.

**Decision.** A pin that names the same commit is the same pin. Before the merge, a local file is
canonicalized to the base render **only** when its content is byte-for-byte equal to the base render's
content with the pin replaced by another spelling of the same object id — git's own abbreviations, down to
its 4-character minimum.

The test is whole-file equality, never a partial or fuzzy rewrite, so:

- a file differing from base in any other way is left untouched and merges, or conflicts, exactly as
  before — including a product that edited the very line the pin is on;
- no product text is rewritten to make a conflict disappear.

Canonicalized paths are counted and named in the report (`Provenance pin spellings
canonicalized: N (path, …)`) and in the delivered commit message, so the repair is never silent. The rule
can only ever be *more* conservative: a file not proven to differ solely by pin spelling cannot be
canonicalized.

The comparison is made on **bytes**, not decoded text, because a rendered artifact need not be valid
UTF-8 and decoding one would turn a byte-level rule into a failure for the entire upgrade.

Two consequences worth stating because they are not obvious:

- **Canonicalization cannot change delivered content.** A canonicalizable path's base text carries the
  pin, and the pin differs between revision A and revision B by construction, so `base != incoming` holds
  for such a path. It is therefore classified `modified`, and for that classification the merged content
  is the incoming render whether or not the local side was canonicalized. Canonicalization can only turn a
  conflict into a clean merge; it cannot alter what the product ends up carrying.
- **A canonicalized file then reports itself as locally modified.** Its content no longer matches the
  `install_hash` the pre-repair engine recorded for the abbreviated file, so `ModificationDetector`
  reports it `locallyModified`. This is inert today — the only consumer of that signal is the
  deleted-upstream branch, which reports a conflict either way — but it must be revisited if that branch
  is ever changed.

**Consequence.** A product delivered by the pre-repair engine upgrades with zero conflicts on its
provenance lines, and its second upgrade is clean with nothing left to canonicalize. A product with a real
customization in the same file still gets a conflict, with its own text intact, and a product whose
provenance line names a *different* commit — or an abbreviation shorter than git's 4-character minimum —
is never canonicalized either.

### A4 — a delivered upgrade whose every change was one-sided upstream was reported as a no-op

**Context.** `UpgradeClassification.modified` is contracted as "paths whose merged content differs from the
base render — the framework changed them, a local customization survived on top of them, **or both**". The
implementation contradicted that contract: when the merged content equalled the incoming render, the path
was recorded only as `unmodified` and never in `modified`. `hasChanges` is derived from `added`, `deleted`,
`renamed`, `modified` and `conflicts`, so an upgrade whose every change was a one-sided upstream edit —
nothing of the product's involved — came back as `upgradeNoop` **after** its branch had already been
pushed to the product's remote. The human was told there was nothing to review about a branch that
contained real changes. Every upgrade also changes the provenance pin by construction, so the case was
reachable from any second upgrade.

**Decision.** A path the framework changed counts as `modified` whether or not a local customization also
survived on it, matching the documented contract. `unmodified` keeps its own meaning — the merged content
is exactly the incoming render, so nothing of the product's was lost — and the two buckets overlap by
design, as the class already documents.

**Consequence.** `hasChanges` is true whenever the delivered tree differs from the base render, so a
delivered branch is never reported as a no-op. A genuinely empty upgrade — every path identical in base
and incoming — still reports `upgradeNoop`, which remains the correct answer there.

### Verified

`dart analyze` clean; `dart format` clean across the whole `cli` package; the full hermetic suite green
(113 tests).

Each of the six tests added for issues #3 and #4 was confirmed to **fail** against the pre-repair engine
and pass after it — the delivery assertion against the bare remote, the no-remote refusal, the
real-remote-only branch refusal, the unprobeable-remote refusal, the resolved-provenance-pin assertion,
and the two-upgrade no-conflict regression.

For A3 and A4, each added test was confirmed to fail against the engine without the corresponding change:

- the abbreviated-pin upgrade conflicted on both pin files without A3, and the negative case proves a real
  local edit in the same file still conflicts with the product's text intact;
- without A4 a second upgrade whose only edit was one-sided upstream returned `upgradeNoop`.

One A3 test does **not** discriminate, and is claimed only as a characterization: "a pin that is not
another spelling of the base id is never canonicalized" asserts behaviour that is correct both with and
without A3. It exists to pin the boundary of the rule, not to prove the fix.

`ls-remote --exit-code` was additionally checked against this environment's git: exit `2` for an absent
branch in both an empty bare repository and a populated one, which is the contract A1 depends on.

An independent read-only review of the whole change (`APPROVE_WITH_NON_BLOCKING_FOLLOWUP`, no blockers)
reproduced each of the above, confirmed `89e3474` byte-identical to `dart format` output, and raised the
corrections folded in here: the byte-level comparison (MEDIUM 2), the boundary test above (MEDIUM 3), the
removal of an unsupported claim that this drift had made the CI format step red — NF-002 means CI never
reaches it — the misplaced doc comment (LOW 5), the paths named in the commit message (LOW 7), and the two
non-obvious A3 consequences recorded above (LOW 4). Its remaining low findings are tracked as follow-ups
in `WORK_STATE.md`.
