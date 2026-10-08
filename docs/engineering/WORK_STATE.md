# WORK_STATE.md — State of THIS Framework Repository

This file describes **only the state of this framework repository**. It intentionally contains **no**
product-specific architecture, design, or infrastructure decisions — those belong in the respective
**product repositories**, not here.

---

## Current state

- **Status:** `FRAMEWORK_COMPLETE`
- **Scope of this repo:** canonical, reusable agentic engineering framework (policy, lifecycle,
  learning policy, and templates). This repository is **not** an application.
- **What exists now:**
  - [AGENTS.md](../../AGENTS.md) — repository-wide invariants.
  - [WORKFLOW.md](WORKFLOW.md) — reusable lifecycle (with resolved and unresolved areas).
  - [LEARNING_POLICY.md](LEARNING_POLICY.md) — knowledge classification & authority.
  - [adr/0001-framework-distribution-and-versioning.md](adr/0001-framework-distribution-and-versioning.md)
    — framework distribution/versioning architecture decision.
  - [adr/0002-dart-mason-git-framework-driver.md](adr/0002-dart-mason-git-framework-driver.md)
    — framework driver/tooling selection (Dart + Mason + Git).
  - [adr/0003-product-generic-orchestrator-skill.md](adr/0003-product-generic-orchestrator-skill.md)
    — product-generic orchestrator skill + dispatch/report contracts.
  - [framework/templates/](../../framework/templates/) — Mason bricks and product-repo templates.

## Recorded framework decisions

- **Product-generic orchestrator skill (ADR 0003):** the top-level session now has an invocable
  skill that makes it a **dispatching orchestrator** rather than a doer: decompose → dispatch to
  isolated lanes with declared `OWNED_PATHS`/`READ_ONLY_PATHS`/`PROHIBITED_PATHS` and full
  provenance → monitor → collect structured reports → integrate only independently reviewed results.
  it `reuses` the existing agents/skills (adds no stage, no gate, no fork of
  `independent-review`/`correction-loop`/`qa-execution`), keeps an enumerated escape hatch for small
  mechanical Manager self-edits (which never grants self-approval), and escalates to humans in two
  phases (phase 1 **creates the durable Human Decision object** and emits only a machine-readable
  "pending, no question asked yet" notice while safe work continues — never a prose option list; phase 2
  is the single place the question and its atomic options are presented, through the structured question
  UI, once the decision is the sole remaining blocker — after which unblocked lanes launch immediately
  following the mandatory resolution fields and the selected-option tamper-check). Durable Manager state is
  plain markdown/JSON under a project-declared directory, so it survives crash/compaction **without**
  any host-specific session hook; a different agent host changes only how a lane is *launched*.
  **Provenance:** generalized from a production project-local orchestrator skill and its subtask
  dispatch protocol — the hand-authored `sponsorwell-orchestrator` skill and
  `.devin/templates/subtask-{prompt,report}.md` in the Partnerhub product repository (the product-0
  whose lifecycle discipline inspired AEF). Its product identity, agent-host branding, design-tool
  integration, stack-specific gates, and host-specific lifecycle hooks were generalized or dropped —
  the shipped artifacts contain **no** product/tool identifier. Shipped artifacts:
  `__brick__/.agents/skills/aef-orchestrator/SKILL.md`,
  `__brick__/.agents/skills/aef-orchestrator/templates/subtask-prompt.md`,
  `__brick__/.agents/skills/aef-orchestrator/templates/subtask-report.md`,
  `__brick__/docs/engineering/adr/0003-*.md`, wired
  into `__brick__/AGENTS.md`, `framework/templates/product-repo/AGENTS.template.md`, and the
  generated per-platform `run-feature` command adapters. Registration is structural (ADR 0002): being
  in `__brick__/` is registration; the CLI's `KNOWN DEFECT D` completeness test now asserts **93**
  managed paths. Verified end-to-end **for fresh instantiation only**: a bootstrap into a disposable
  git repo wrote 93 manifest artifacts — that test exercises `bootstrap` alone, so it is
  **not** proof of upgrade re-delivery (see the host-binding defect recorded below). The Manager's
  result type was added to the authoritative contract — `ORCHESTRATION_RESULT` + `agent_role:
  ENGINEERING_MANAGER` in `docs/engineering/STRUCTURED_RESULTS.md` (additive; `schema_version` stays
  `1.0`) — so the skill does not invent a result type it declares subordinate to. **Classified
  `WORKFLOW_IMPROVEMENT`** (a `LEARNING_POLICY.md` category), whose required authority is **independent
  review**, not `HUMAN_DECISION_REQUIRED`: it adds no human gate and no lifecycle stage, so it is a
  material framework change that **requires independent review** before promotion.

- **Platform matrix / adapter generation (ADR 0003 § Platform matrix and generated
  adapters):** `.agents/` is the **canonical source of truth** (10 agent profiles + 12
  `aef-`prefixed skills). `.claude/`, `.junie/`, and `.opencode/` hold **generated** adapters —
  23, 23, and 11 files respectively (57 total) — rendered by
  `cli/tool/generate_platform_adapters.dart` from the single `kPlatforms` constant. **Revised
  invariant:** those three directories **may exist only as generator-produced output, never
  hand-maintained content**, enforced by `cli/test/platform_adapter_test.dart` (which runs
  `--check` and also asserts the adapter count, the cross-platform tool-set identity, and that a
  Junie/Claude skill copy differs from canonical only in the mapped `disable-model-invocation`
  line). The previous rule — "no `junie` anywhere in the shipped tree" — was **wrong by decision**
  and is superseded; what is prohibited is hand-maintained content, not the directory's existence.
  opencode reads `.agents/skills/` natively, so **no** `.opencode/skills/` is generated.
  **Human decision:** keep Junie *and* add Claude Code alongside the canonical and opencode sets.

- **HUMAN DECISION (2026-10-01) — the framework repository dogfoods what it ships: generate all
  four root adapters.** Options presented and decided: *generate all four root adapters*.
  Rejected: *leave the root stale*, *refresh the stale files once by hand*, and *delete the root
  `.junie/` and consume the canonical layout only*. **No `decision_id` UUID was issued for this
  decision** — it was received in-session rather than raised as a persisted Human Decision object,
  so `HUMAN_DECISIONS.md`'s `decision_id: UUID` convention is **unbound** here; a later audit
  should bind one. Decision text: extend the platform-adapter work to the repository root, generated
  from the same canonical source, with the brick's `.agents/` remaining the single source of truth.

  - **Root inventory BEFORE** (all 10 files tracked and clean; `.agents/`, `.claude/`, `.opencode/`
    **absent**): `.junie/agents/` held **5** of 10 agent profiles (`correction-implementer`,
    `engineering-reviewer`, `focused-reviewer`, `implementer`, `integrator`); `.junie/skills/` held
    **4** of 12 skills, all **unprefixed** (`correction-loop`, `implementation-workflow`,
    `independent-review`, `repository-learning`); `.junie/commands/run-feature.md` was a superseded
    hand-written command.
  - **Root inventory AFTER** (generated, committed, drift-covered): `.agents/` **24** (10 agents + 12
    `SKILL.md` + the 2 `aef-orchestrator` dispatch templates) — a **mirror**, not a second source of
    truth; `.claude/` **23**; `.junie/` **23**; `.opencode/` **11**; root total **81**, brick **57**,
    canonical total **138**.
  - **Exactly what moved:** the 4 unprefixed root `.junie/` skills were **deleted** (superseded by
    their `aef-`-prefixed equivalents, which is what makes the root copy collision-safe); the other 6
    tracked root `.junie/` files (5 agents + the command) were overwritten in place by their generated
    equivalents; `.agents/`, `.claude/`, and `.opencode/` were added. **Nothing outside root `.junie/`
    was disturbed** — verified with `git status --short`.
  - **Coverage:** `--check` now verifies **both** roots and reports per-root/per-platform counts; the
    drift test asserts both roots and derives its count expectations from the same `kPlatforms` ×
    `kTargetRoots` declarations the generator iterates, plus a byte-identity assertion that root
    `.agents/` equals the brick canonical tree. `.gitignore` still commits all four root directories.
  - Verified: `--check` exit 0 at 138; root `.claude/`, `.junie/`, `.opencode/` byte-identical to the
    brick's; root `.agents/` byte-identical to brick canonical; brick adapter output byte-unchanged
    (81/81 files identical before and after this step).

- **Distribution/versioning architecture (ADR 0001):** versioned **copy-based** installation with
  **deterministic provenance** (authoritative `framework.revision`, per-artifact install/source
  hashes, no persisted `locally_modified` flag) and **reviewable, isolated 3-way-merge** upgrades
  that preserve product-specific knowledge. Provenance and any template answers are kept separate;
  normal product operation requires **no** runtime access to this framework repo or a registry.
- **Framework driver/tool selection (ADR 0002):** the driver is **Dart + Mason + Git** with
  **`framework-manifest.yaml`** as authoritative provenance. **Dart** owns CLI/orchestration;
  **Mason** owns template rendering only (non-authoritative metadata); **Git** owns native 3-way
  merge/versioning mechanics; a **custom text merge engine is prohibited**. This was validated by an
  empirical proof-of-concept (`DART_MASON_GIT_POC_PASS`, all pass criteria met, **no architecture
  blockers**). ADR 0002 records the mandatory POC-derived mitigations, the exit-code and
  structured-result contracts, and an 8-phase implementation plan.
  - **All phases 3-8 complete.** The framework driver is implemented and production-authorized
    through the autonomous orchestration loop (implement → independent review → correction →
    integrate). All gates green: `dart format`, `dart analyze`, `dart test` (60/60), `dart compile
    exe`. Production promotion authorized via human decision recorded in commit `4ca8094`.
  - **Exit-code contract extension ratified (human-approved):** `NOT_IMPLEMENTED = 50` added to the
    ADR 0002 exit-code contract (`ARCHITECTURE_DISCOVERY` surfaced by the Phase 1 implementer /
    independent reviewer). Gives stub commands an unambiguous, non-zero, non-colliding semantic so a
    stub can never be mistaken for `SUCCESS`.

- **QA evidence rows + unrunnable-gate determinations (issues #1/#2 resolved):** QA Contracts now
  declare **`E_*` evidence rows** binding feature-specific artifacts
  (`artifact_ref` / `params` / `prerequisites`) with contract-time determinations
  (`EXPECTED_TO_EXECUTE | CONTINGENT | SKIPPED_BY_CONTRACT`); QA Results report per-row
  determinations (`EXECUTED | READY_NOT_EXECUTED | SKIPPED`) and gates may be
  `NOT_EXECUTED` / `SKIPPED`. Rules: **nothing is silently asserted**; a `REQUIRED` row that
  cannot run must be formally determined (made runnable, `SKIPPED` with reasons + `authority_ref`,
  or contract revision) — never left `REQUIRED` + `READY_NOT_EXECUTED` forever;
  `OPTIONAL` / `NOT_IN_DEFAULT_PIPELINE` rows are non-blocking. Filed as
  `shipitinc/agentic-engineering-framework#1` and `#2` (QA Contract feature-specific artifact
  binding; ShipIt headless-device/CI E2E lane gap). The framework resolution covers the
  governance/template side; the concrete CI E2E device lane for a product stays a per-product
  platform decision, now expressible as a first-class `prerequisites` declaration on each `E_*`
  row. Resolved 2026-09-13.

- **Plan artifact retention policy (APPROVED WITH REFINEMENT):** agent-generated plan artifacts
  (`.air/plans/`, `.junie/plans/`, or equivalent) are **visible/versionable but not automatically
  committed** by default. See [LEARNING_POLICY.md — Plan artifact retention
  policy](LEARNING_POLICY.md#plan-artifact-retention-policy) for the full classification model
  (`AUTHORITATIVE_PLAN`, `SUPPORTING_PLAN`, `AUDIT_ARTIFACT`, `PROMOTION_REQUIRED`, `TRANSIENT_PLAN`,
  `DUPLICATE_ARTIFACT`) and commit/promote/delete criteria. Policy is tool-neutral (classifies by
  information authority, not artifact origin). **Refinement:** `LEAVE_UNTRACKED` is an interim
  working state only, never a permanent disposition — every untracked plan must eventually be
  intentionally finalized to `COMMIT`, `PROMOTE_THEN_DELETE`, or `DELETE` unless its originating
  work/review cycle is still active.

- **Upgrade merge engine and delivery (ADR 0004):** `framework upgrade` now computes the documented
  three-way merge — **base** = render of the pinned revision A, **local** = the product's own state,
  **incoming** = render of revision B — **without a working-tree copy**, by creating three synthetic
  commits that share the base render as their parent and merging them with `git merge-tree
  --write-tree`. The result is delivered as **one commit on the product repository's real `HEAD`**,
  pushed last to `framework/upgrade-<A>-<B>`, carrying the refreshed `framework-manifest.yaml`
  (`source_hash` = what the framework ships at revision B, `install_hash` = what the product will
  carry, so a local customization stays detectable). Consequences that are now guarantees: the product
  working tree and index are **never** mutated; a conflict is **delivered** with markers and reported
  as `upgradeConflict` + `humanActionRequired` instead of being stranded; a re-run **refuses** to
  overwrite an upgrade awaiting review; all scratch state is **discarded** on every exit path. Requires
  `git >= 2.38`. Classified `WORKFLOW_IMPROVEMENT`; authority is **independent review**, not
  `HUMAN_DECISION_REQUIRED` — it repairs an existing documented command and adds no stage or gate.

- **The first real product upgrade exposed three more defects, all fixed by ADR 0004 § 6-8.** Running the
  engine against `TeamHub` (pinned `7f1368f`, manifest `upgraded_at: null`) produced **15 conflicts, 11
  of them fabricated**. The product had been bootstrapped from the **brick directory** rather than from a
  render: its 21 manifest entries were all brick build inputs, and it held **no rendered framework
  artifact at all** (no `.agents/`, `.claude/`, `.junie/`, `.opencode/`). Three consequences, each now
  handled explicitly and covered by tests:
  1. **Staging artifacts.** Byte-identical copies of brick inputs (`__brick__/**`, `brick.yaml`,
     `manifest.template.yaml`) are removed from the delivered tree and reported; git had been pairing
     them with the base render as renames, inventing `rename/rename` conflicts against unrelated upstream
     moves. Copies that were *edited* (e.g. a customized `__brick__/AGENTS.md`) are deliberately kept and
     reported as stale entries, since that content may carry product knowledge.
  2. **A fictional merge base.** With no render lineage the base is replaced by git's empty tree, so the
     incoming render is **adopted** and product-owned files are kept. Conflicts dropped from 15 to the
     **2 that are real** (`AGENTS.md`, `docs/engineering/WORK_STATE.md` — a product-local file and a
     framework file that both claim the same path).
  3. **Ambiguous pins.** The manifest recorded the revision string that was typed (`e37b2a3`); it now
     records the resolved object id (`e37b2a3fa3449df89686b79dbe08e4eb7b9a3176`).
  Result: `Added: 91`, `Removed: 3`, `Conflicts: 2`, 93 artifacts in the refreshed manifest. The product
  working tree stayed clean throughout. **Still open and human-owned:** resolving those 2 conflicts,
  deciding the fate of the 17 leftover unreachable `__brick__/**` and `product-repo/**` files, and
  reviewing the 91 adopted artifacts. `framework.source` in that manifest is still a local filesystem
  path inherited from the original bootstrap; left as-is (truthful provenance, host-bound) pending an
  explicit decision.

- **Five blocking defects in the previous upgrade implementation (all fixed by ADR 0004; reproduced
  against a real bootstrapped product pinned at `7f1368f` before any fix).** Recorded because
  `upgrade` had **never executed successfully on a real product**, and ADR 0003 could therefore claim
  only fresh instantiation:
  1. **Trusted-source check ran on the wrong repository** — it compared the **product** repo's `origin`
     against the approved framework URL, which can never match for a real product. Now evaluated on
     the framework checkout that owns the resolved brick (`<brick>/../..`); the product repo needs only
     an existing `origin`.
  2. **Base revision was unreachable** — rendering used `git clone --depth 1`, so any upgrade whose
     pinned base was not the branch tip failed. Rendering now uses full history, and prefers the CLI's
     own framework checkout when it contains the revision (no network, hermetic under test).
  3. **Scratch checkout lived inside the repository being copied** — the worktree was created at
     `<productRepo>/.git/worktrees/upgrade-tmp` and the product repo was copied into it, aborting with
     `FileSystemException … '.git/info/refs' … (Is a directory)`. Scratch is now a clone of the product
     repo in the system temp directory, outside the product repository entirely.
  4. **Inverted commit topology dropped product changes** — `upgrade-base` was rewritten *from* the
     local state after local state was committed on top of it, so the merge base no longer matched the
     base render and the product's own changes were silently absent from the merged tree.
  5. **Nothing was delivered** — a conflicted merge returned early, a clean merge left its only output
     in a scratch repo that was then deleted, and the review patch was written **into the product
     working tree** (which itself trips the next run's dirty-tree guard). Delivery is now the branch
     above; the product tree is never written to.

- **Two engineering findings from implementing ADR 0004 (both fixed here).** *(a)* Two `git`
  invocations — the product-repo clone and the framework clone — originally inherited the **ambient
  process working directory**; the CLI test suite caught this only when another suite had moved and
  deleted the current directory (`shell-init: … getcwd: cannot access parent directories` →
  `fatal: this operation must be run in a work tree`). Every git invocation in the engine now passes
  an explicit `workingDirectory`, so the upgrade never depends on where the process is. *(b)* Building
  a tree from a rendered directory must use `git add -A -f`, not `git add -A`: a product `.gitignore`
  can exclude framework-rendered paths (e.g. a generated `.claude/` adapter directory) and `add`
  without `-f` would silently drop them from the merge inputs — resurrecting, in a new disguise, the
  class of bug this ADR exists to remove.

## Plan artifact cleanup completed

The three plan artifacts previously classified under the retention policy have been finalized
per their approved dispositions:

- `.air/plans/independent-review-framework-bootstrap.plan.md` — classification=`SUPPORTING_PLAN`,
  final_disposition=`DELETE_AFTER_POLICY_APPROVAL_AND_REVIEW` — **deleted**.
- `.junie/plans/independent-review-framework-bootstrap.md` — classification=`DUPLICATE_ARTIFACT`,
  final_disposition=`DELETE_AFTER_POLICY_APPROVAL_AND_REVIEW` — **deleted**.
- `.junie/plans/framework-artifact-distribution-architecture.md` — classification=`SUPPORTING_PLAN`,
  final_disposition=`DELETE_AFTER_POLICY_APPROVAL_AND_REVIEW` — **deleted** (durable conclusions
  already fully captured in ADR 0001 and this file's own "Recorded framework decisions" entry above).

## Explicitly out of scope for this repository

- Product-specific **architecture** decisions (belong in product repos + their ADRs).
- Product-specific **design** decisions and Design Contracts.
- Product-specific **infrastructure**, environments, CI/CD, and deployment configuration.

## Verified repository/environment facts (evidence-backed)

- This is a valid Git repository on branch `main` with **no commits yet** at bootstrap time.
- Remote `origin` is configured: `https://github.com/shipitinc/agentic-engineering-framework.git`.
- Remote is **reachable** and Git authentication appears **sufficient** for fetch workflows
  (`git ls-remote` / `git fetch --dry-run` succeeded without credential prompts). The remote had no
  refs at bootstrap time (empty upstream).
- No pushes, remote resources, or destructive Git operations were performed during bootstrap.
- **Canonical revision:** `4ca80945b468d8044e7a0e143a28870a41fb5f7c` — all phases 3-8 implemented
  and production-authorized.
- **Bootstrap is currently only runnable in CLI test mode (pre-existing, verified 2026-09-30).** The
  brick-integrity map `_getExpectedBrickHash()` in `cli/lib/src/commands.dart` records exactly one
  revision (`4c7baa1`), and `_validateBrickIntegrity` rejects unknown revisions. Any bootstrap run
  **without** `FRAMEWORK_CLI_TEST_MODE=true` from an unreleased revision therefore falls through to
  the distributed-CLI branch and fails with `BOOTSTRAP_BLOCKED` /
  `FRAMEWORK_BRICK_PATH environment variable not set`. Reproduced on an unmodified checkout of
  `01e0e84`; it is a **release-process gap, not a regression** — each release must record the new
  revision's brick hash. Classified `WORKFLOW_IMPROVEMENT`.
- **The template-completeness test is host-bound (pre-existing, verified 2026-09-30, NOT fixed by ADR
  0003).** `cli/test/bootstrap_integration_test.dart:19-20` hardcodes
  `frameworkRepoPath = '/Users/alkebut/air/agentic-engineering-framework'`, so the `KNOWN DEFECT D`
  inventory test (and every test in that file that shells out to the CLI) runs only when the checkout
  happens to live at that absolute path; elsewhere it fails before asserting anything. The same test
  exercises **`bootstrap` only**, so it never proves upgrade re-delivery — which is why ADR 0003 and
  `framework/templates/README.md` claim only fresh instantiation + manifest registration. Classified
  `WORKFLOW_IMPROVEMENT`; **unresolved** — parameterizing the path is a `cli/**` change outside the
  ADR 0003 correction scope. **Amended 2026-10-02 (ADR 0004):** the *conclusion* this entry drew
  ("upgrade re-delivery is unproven") is superseded — `cli/test/upgrade_merge_test.dart` now covers
  upgrade merge, delivery, conflict reporting, manifest refresh, re-run refusal, and scratch cleanup
  end-to-end, and it builds its framework and product fixtures in temporary directories with **no
  absolute-path dependency**, so it does not repeat the host-bound mistake this entry records. The
  host-bound defect of `bootstrap_integration_test.dart` itself is **still unresolved**.
- **The two `STRUCTURED_RESULTS.md` copies are byte-identical; no divergence exists.** Verified
  (independent review finding, corrected 2026-10-01): at HEAD `01e0e845` both copies were 585 lines and
  byte-identical with **zero** design markers, and in the current working tree both are 675 lines,
  byte-identical, and both contain `visual_approval_required`, `design_system_asset_refs`,
  `asset_reuse_compliance`, and `ARTIFACT_VERIFICATION`. **This entry supersedes an earlier version of
  itself**, which claimed the copies "intentionally diverge" and that the brick copy lacked the
  design-workstream additions — a claim that described a state that was never implemented. **Best-supported
  account of how the design markers came to be in both copies:** the design-authority workstream's
  `STRUCTURED_RESULTS.md` hunks were applied to **both** copies before this change set was reviewed.
  The design markers are uniformly present and the two files match, which is what a deliberate
  both-copies application produces; the divergence claim appears to have been written from the
  *orchestration* lane's own patch set — this change added only `ORCHESTRATION_RESULT`,
  `agent_role: ENGINEERING_MANAGER`, `payload.conventions.declared_in`, and the product-repo-qualified
  `orchestrator` cross-reference, and those hunks are correctly **path-qualified per copy**
  (`.agents/skills/` in the brick copy, the full repository path in the framework copy). That
  path qualification is the **one intentional difference between the two patch sets**, not between the
  two files. No design-workstream hunk was lost in this correction; `cmp` on both copies is clean.
- **Path ownership for this change (Manager decision, 2026-10-01).** `OWNED_PATHS` for the ADR 0003 /
  orchestrator change is: `framework/templates/__brick__/.agents/skills/aef-orchestrator/SKILL.md`,
  `framework/templates/__brick__/.agents/skills/aef-orchestrator/templates/subtask-report.md`,
  `framework/templates/__brick__/.agents/skills/aef-orchestrator/templates/subtask-prompt.md`,
  `docs/engineering/STRUCTURED_RESULTS.md`,
  `framework/templates/__brick__/docs/engineering/STRUCTURED_RESULTS.md`, and
  `docs/engineering/WORK_STATE.md`. This change additionally owns **the single ADR-0003
  "Resolved framework areas" hunk in the framework copy of `docs/engineering/WORKFLOW.md`** (13 lines,
  "Manager orchestration as an invocable procedure — RESOLVED by [ADR 0003]"), which is an original
  deliverable of this change; the **design-authority workstream concurrently owns the other hunks in that
  same file**. The two ownerships are **disjoint** — different line ranges, no shared lines — so the file
  is **serialized, not concurrently written**, and every hunk other than the ADR-0003 entry is the
  design-authority workstream's and was **not touched** here.
- **Residual pre-existing conflict: per-`result_type` status enums vs the global `Status Values (Enum)`
  table (open, contract owner).** The two `STRUCTURED_RESULTS.md` copies declare **narrower** per-type
  status enums for some types (`QA_CONTRACT` `CREATED | FROZEN`, `QA_RESULT`
  `PASS | FAIL | PARTIAL | BLOCKED`, `DEPLOYMENT_RESULT` `SUCCESS | FAILED | ROLLED_BACK | PARTIAL`,
  `INTEGRATION_READINESS` `READY | NOT_READY | BLOCKED`) that do not match the global table, and
  `QA_CONTRACT` declares **no** blocked member at all, so `RESULT: QA_CONTRACT_BLOCKED` currently has **no
  legal envelope `status`**. `subtask-report.md` now emits the **per-type** member where one is declared
  and records the `QA_CONTRACT_BLOCKED` cell as unsatisfiable rather than substituting a global value.
  **Not reconciled here** — resolving the enum overlap (and the missing `QA_CONTRACT` blocked member) is
  a contract-owner change to `STRUCTURED_RESULTS.md`, not a correction-cycle edit.
- **`cli/**` working-tree changes are declared in scope for this change (Manager decision, 2026-10-01)
  and are left untouched here.** They consist of a mandatory-gate formatting normalization plus one
  unused-parameter removal; the orchestrator workstream neither authored nor edits them. Recorded so the
  dirty path set has an explicit owner and the re-review does not read those diffs as orchestrator
  output.

## Independent review outcome — platform adapter generation / two-root dogfooding

- **Verdict: `CHANGES_REQUIRED`** — independent `engineering-reviewer` (read-only, fresh session)
  reviewed the platform-adapter generation and two-root dogfooding change at working-tree state pinned
  to `01e0e845f046b400b24c5e0a2cd6f028c88ceb85` (uncommitted, `base_sha == head_sha`). **4 blockers**
  (B1 `.opencode/` ownership scoping, B2 a `WORK_STATE` claim about a `STRUCTURED_RESULTS.md` divergence
  that never existed, B3 a self-contradictory `framework/templates/README.md` layout, B4 an invalid
  self-certification) and **8 non-blocking findings**, of which two were **human decisions already
  taken** and are now implemented as specified (N2 narrow the read-only claim; N3 declare the invariant
  advisory in product repos; N4 keep both Claude entry points and document the alias). B1 additionally
  carried an explicit human decision: own only the **generated subtrees** (`.opencode/agents/**`,
  `.opencode/command/**`), never the whole `.opencode/` directory, because opencode writes its own
  runtime files there.
- **Review state now: corrections applied in the working tree; `CHANGES_REQUIRED` is not yet cleared.**
  A fresh **focused re-review** is required against the corrected state, per
  `aef-correction-loop`; this entry does **not** assert approval.
- **Superseded: an earlier `IMPLEMENTED` result for this change declared `independent_review:
  NOT_REQUIRED` and `integration_readiness: READY`.** That was an **invalid self-certification** and is
  superseded: `AGENTS.md § Changing the framework itself` requires independent review for a material
  workflow-framework change, and `AGENTS.md § Orchestration binding` states "Integration is allowed only
  after independent approval". Its provenance `task_id: "gen-two-roots"` was a descriptive label with no
  dispatch record, against `STRUCTURED_RESULTS.md` (`task_id` must identify a dispatched lane;
  `evidence.dispatch_records` must list the report per task). Independent review **has since been
  performed** and returned `CHANGES_REQUIRED`; the malformed result must not be cited as a gate
  outcome, and no agent may self-certify `independent_review` or `integration_readiness` in its own
  result — those stay `PENDING` until a fresh focused re-review reports.
- **B1 evidence for the human decision:** `.opencode/` held **3,659** files on the development host,
  of which **3,645** were `node_modules/` plus `package.json`, `package-lock.json`, and `.gitignore`
  — i.e. **11** generated files against 3,648 runtime files. The whole-directory ownership claim made
  `--check` and `dart test` red (`+80 -2`) and reproduced in every bootstrapped product repo. The
  generator now derives ownership from the generated paths themselves, so the exemption is structural
  rather than an allowlist. **Brick check:** the brick does **not** ship a tool-authored
  `.opencode/.gitignore`; `framework/templates/__brick__/.opencode/` contains only `agents/` and
  `command/` (11 generated files). The `.opencode/.gitignore` that ignores `node_modules`,
  `package.json`, `package-lock.json`, `bun.lock`, and `.gitignore` exists **only at the repository
  root** and was written by opencode at runtime.

## Manager state transition — focused re-review cleared the blockers

- **Verdict: `APPROVE_CORRECTIONS`** — independent `focused-reviewer` (read-only, fresh session
  `ses_f0616be4affeXGkQun11rOuuFo`) re-reviewed **only** the corrected findings and the regression risk
  they introduced, at working-tree state pinned to `01e0e845f046b400b24c5e0a2cd6f028c88ceb85`
  (uncommitted, `base_sha == head_sha`). **B1–B4 all cleared**, **N1–N7 all landed as decided**, no
  regressions, no open blockers, no open non-blocking findings.
- **`CHANGES_REQUIRED` is cleared.** Per `AGENTS.md § Changing the framework itself`, this material
  workflow-framework change has now completed independent review → correction → focused re-review.
- **B1's trap is closed on both halves.** Ownership is derived from generated paths
  (`generate_platform_adapters.dart` `ownedScopes`/`scopeCounts`), so it is structural, not an allowlist.
  The test's disk-level guarantee survives via three **unconditional literal** assertions outside the
  per-scope loop (`.opencode/agents` == 10, `.opencode/command` == 1, generated `.opencode/` == 11), so
  dropping `.opencode` from the owned list cannot silently disable opencode adapter verification.
  Verified by the Manager directly: a stray file under `.opencode/agents/` fails `--check` (exit 1), a
  stray under `.claude/agents/` fails, and a runtime file elsewhere under `.opencode/` does not (exit 0).
- **Deterministic evidence at the re-reviewed state** (Manager-verified unless noted): `dart format`
  exit 0 (29 files, 0 changed); `dart analyze` no issues; `dart test` **+83 / 83 passed**; generator
  `--check` exit 0 with `PLATFORM_ADAPTERS_IN_SYNC: 138` (brick 57, root 81 = 24 canonical mirror + 57
  adapters) across `.claude` 23 / `.junie` 23 / `.opencode` 11 at both roots; both ADR 0003 copies
  byte-identical; both `STRUCTURED_RESULTS.md` copies byte-identical with all four design markers present
  in both; both `WORKFLOW.md` copies byte-identical; root `.agents/` mirror identical to brick canonical;
  the unrelated shared design workstream intact with no orchestration hunk clobbering it.
- **N2's `read_only_exec` runner remains an open tracked follow-up** (owner: framework tooling / CLI) —
  deliberately not built. Until it exists, read-only reviewers hold `exec`/`bash` on all three platforms;
  ADR 0003 now states only the narrower true claim (the **native edit path** is denied on every
  platform) and explicitly disclaims filesystem read-only-ness.
- **Known consequence of the human-approved structural ownership principle, recorded deliberately:** the
  same derivation exempts the top level of `.claude/` and `.junie/`, so a runtime file such as
  `.claude/settings.local.json` would fall outside drift detection. This follows from "derived from
  generated paths, not a maintained allowlist" and is not a defect, but it is consciously accepted here.
- **Not done, and deliberately so: no commit.** Integration is approved but not performed. Committing is
  human-authorized and must not be inferred from this approval. The release revision/hash registration in
  `cli/lib/src/version.dart`, `cli/tool/compute_brick_hash.dart`, and `_getExpectedBrickHash()` in
  `cli/lib/src/commands.dart` stays outstanding because the hash cannot exist before the commit does.

## Earlier independent review outcome — ADR 0003 / orchestrator skill

- **Verdict: `APPROVE_WITH_NON_BLOCKING_FOLLOWUP`** — independent `focused-re-reviewer`
  (fresh session, `agent_role: ENGINEERING_REVIEWER`), pinned to working-tree state at
  `01e0e845f046b400b24c5e0a2cd6f028c88ceb85` (uncommitted, `base_sha == head_sha`).
  `CORRECTION_REQUIRED: false`, `HUMAN_DECISION_REQUIRED: false`, `findings: []`, `blockers: []`.
- **All nine round-3 findings verified fixed**: N1 (§7 table row), N10 (two-way `DO_NOT_MERGE` split),
  N2 (per-`result_type` status binding), N3 (shared-file ownership declaration), N4 (`TASK_TYPE` enum
  extension across all five enumeration sites), N5 (`REVIEWED_HEAD`), N6 (shipped-heading citation),
  N7 (§6 scope line), N8 (symmetric `OVERALL_VERDICT` precondition).
- **History**: three review→correct cycles. Round 1 found 3 blockers, round 2 found 1, round 3 found 5
  (two of them side-effects of that round's broad rewrite — a Markdown formatting accident and an
  ownership-declaration gap). Cycle 3 was therefore constrained to surgical, line-anchored edits.
- **Gates at review time**: `dart format` clean (27 files, 0 changed), `dart analyze` `No issues found!`,
  `dart test` 72/72 passed.
- **One non-blocking follow-up (NF-001)**: the pre-existing per-`result_type` vs global status-enum
  overlap, including the `QA_CONTRACT` blocked-member gap. Already recorded above as an owned open item
  for the contract owner. Not a blocker for this change and not introduced by it.
- **Change is approved for integration.** The only remaining action is a normal human-authorized commit.

## Accepted open items — ADR 0004 upgrade engine (tracked follow-ups)

- The ADR 0004 upgrade-engine change (`b1a028d`, `ce4f015`, `2ffa16a`) completed independent review
  and a focused re-review with **zero blockers**, and is **human-approved for integration**. The human
  has explicitly decided to push the work and leave four items open as documented rather than fix
  them here; they are recorded below so they stay tracked instead of being lost. **None of them is a
  blocker for this change and none was introduced by it**, and each carries a follow-up owner.
  Numbers continue the existing `NF-001` series (§ *Earlier independent review outcome — ADR 0003 /
  orchestrator skill*).

- **NF-002 — the CI workflow is entirely non-functional (severity `HIGH`, pre-existing, out of scope
  for this change).** `.github/workflows/ci.yml` runs `dart pub get`, `dart format`, `dart analyze`,
  `dart test`, and `dart compile exe bin/framework.dart` with no `working-directory`, i.e. at the
  repository root, which has neither a `pubspec.yaml` nor a `bin/`. The first step therefore fails on
  all three OSes of the matrix (`Found no pubspec.yaml file in … or parent directories`) and the
  workflow never reaches a test. **Provenance:** added in `4ca8094`, before the reviewed range, and
  untouched by `e37b2a3..2ffa16a`. **Suggested remedy:** `defaults.run.working-directory: cli`, plus
  Windows path care for `bin/framework.dart`. **Owner: framework tooling / CI.**

- **NF-003 — open `HUMAN_DECISION`: non-checkout framework source vs the ADR-0002 brick-content
  hash.** Already recorded as unresolved in ADR 0004 § 1; re-registered here as a tracked item so it
  is not lost. The rule and its evaluation point are **deliberately unchanged** by ADR 0004.
  **Owner: framework architecture (human decision).**

- **NF-004 — `FRAMEWORK_CLI_TEST_MODE` is reachable in a compiled production binary.** Verified by
  compiling `dart compile exe bin/framework.dart` and driving it against a framework checkout whose
  `origin` is an untrusted URL: with the flag unset the run is correctly blocked
  (`Untrusted framework source: …`, exit 20), while with the flag set the trusted-source check is
  skipped entirely and execution proceeds. The flag deliberately disables **both** the
  trusted-framework-source check **and** the dirty-tree guard — pre-existing behaviour, untouched by
  `2ffa16a`, and honestly documented as a test seam in ADR 0004 § 1. Two sub-points: **(a)** whether
  that trade-off is acceptable for a compiled production binary is a **human call, not a reviewer's**,
  and a candidate remedy is gating the seam behind a compile-time flag; **(b)** ADR 0004 § 1's
  enumeration of what the flag skips is **incomplete** — it omits that the same flag also skips
  `_validateBrickIntegrity`. **Owner: framework security / tooling.**

- **NF-005 — minor accuracy items in the `2ffa16a` correction commit and its tests.** **(a)** The
  commit message claims "every added test was verified to fail when its fix is reverted"; that is not
  true for `a different repository or a non-remote is not that identity`, which also passes against
  the pre-fix algorithm (the old code rejected those inputs too, just via garbage identities) —
  **documentation inaccuracy only**, with no behaviour claim. **(b)** The same commit's wording "every
  cleanup path uses `dispose()`" is loose: the render temp-dir `finally` block in
  `cli/lib/src/upgrade/upgrade.dart` is `existsSync`-guarded inside
  `try`/`catch (FileSystemException)`, so the safety property holds but the wording overstates it.
  **(c)** `_newScratchDirs` assumes no concurrent run creates `aef_upgrade_*` between capture and
  assertion — safe today (only `upgrade_merge_test.dart` uses that prefix, and tests within a file
  are serial) but a latent coupling if a second file ever drives `runUpgradeCore`.
  **Owner: framework tooling / upgrade engine.**

## Upstream-reported upgrade-engine defects, repaired (2026-10-03)

Two defects in the ADR 0004 upgrade engine were reported **from outside this repository**, by a consumer
running `framework upgrade` against a real product (`TeamHub`), as issues #3 and #4. Both reproduced
here and both are now repaired. They were introduced by the ADR 0004 change itself, so the repair is
part of closing that item rather than a new workstream. Neither is a governance change: no human gate,
no lifecycle stage, no policy decision — so the authority is again **independent review**, per
`LEARNING_POLICY.md`'s `WORKFLOW_IMPROVEMENT` category. ADR 0004 is amended in place with the full
record.

- **Delivery went to a local path, not the product's remote.** The delivered commit was pushed from the
  scratch clone, whose `origin` git had configured as the product's **local directory** (the clone source
  was a path). The push exited `0`, created a ref inside the product repository, and reached the hosting
  provider of nothing, so the run reported success while `git ls-remote origin 'refs/heads/framework/*'`
  was empty. This also silently disabled ADR 0004 §4's remote-only re-run refusal, so a re-run would push
  over a review in progress, and it wrote into the product repository that the same ADR promises is never
  mutated. The hermetic suite could not catch it: with a local-path remote, "the branch is on the remote"
  was satisfiable by a local assertion — and the fixtures' "remote" was not a git repository at all.
  **Repair:** the push is now issued by the product repository against the remote in its own config; the
  remote is probed with `ls-remote` for the refusal, an unprobeable remote is refused rather than assumed
  branch-free, and a product with no resolvable remote is refused before any state exists. Fixtures now
  use a **real bare remote** and delivery is asserted by reading the ref out of it.

- **The render carried the typed target while the manifest carried the resolved pin.**
  `{{frameworkRevision}}` was substituted with the revision *string the caller typed*, and
  `template_inputs.frameworkRevision` was carried forward verbatim from the original instantiation. The
  field was therefore stale from the first upgrade onward, and the two spellings made the managed
  provenance line collide with itself on the **second** upgrade: modify/modify on
  `Framework revision:` in `AGENTS.md` and `docs/engineering/WORK_STATE.md`, a field whose only correct
  value was never in dispute. Reproduced on `TeamHub` as 2 conflicts and reproduced hermetically as a
  two-upgrade test. **Repair:** the render substitutes the **resolved object id**, so the rendered line
  and `framework.revision` are the same immutable identifier by construction and the bump is a clean
  one-sided change; `template_inputs` is refreshed from that value rather than carried forward, and the
  renderer never reads it back, so a recorded product input cannot become a later render's input (which
  also closes the concern raised with issue #3 about a non-checkout framework source — see ADR 0004
  §1's open `HUMAN_DECISION` and NF-003).

Three further defects were found while repairing those two, all in the same engine and all now fixed:

- **A pin spelled differently was treated as a competing edit.** Fixing the render alone would still leave
  every product already delivered by the pre-repair engine carrying `Framework revision: e37b2a3` against
  a manifest pinning `e37b2a3fa344…`, so its next upgrade would conflict on that line for no reason.
  **Repair:** a local file is canonicalized to the base render when — and only when — its content is
  byte-for-byte the base render's content with the pin replaced by another spelling of the same object id
  (git's own abbreviations, down to 4 characters). The test is whole-file equality, never a partial
  rewrite, so a genuine customization in the same file still conflicts with the product's text intact, and
  the count is reported (`Provenance pin spellings canonicalized: N`) and recorded in the commit message.
  See ADR 0004 A3.
- **A delivered upgrade could be reported as a no-op.** `UpgradeClassification.modified` is contracted as
  "the framework changed them, a local customization survived on top of them, **or both**", but the
  implementation recorded a path only as `unmodified` when the merged content equalled the incoming
  render. `hasChanges` is derived from `added`/`deleted`/`renamed`/`modified`/`conflicts`, so an upgrade
  whose every change was a one-sided upstream edit returned `upgradeNoop` **after** pushing its branch to
  the product's remote — telling the human there was nothing to review about a branch with real changes.
  Reachable from any second upgrade, since the provenance pin changes by construction. **Repair:** a path
  the framework changed counts as `modified` whether or not a local customization also survived, matching
  the documented contract; a genuinely empty upgrade still reports `upgradeNoop`. See ADR 0004 A4.
- **`dart format` drift in `cli/`.** Two files did not satisfy the gate this repo documents and runs
  locally (`dart format --output=none --set-exit-if-changed .` at Dart >= 3.12.0):
  `cli/lib/src/commands.dart` and `cli/test/upgrade_merge_test.dart`. Both are now formatted, in a
  separate commit that touches no behaviour and is byte-identical to `dart format` output, so it can be
  reviewed as pure formatter output. This did **not** make the CI format step red at `main`: per **NF-002**
  the workflow fails at `dart pub get` (there is no root `pubspec.yaml`) and never reaches the format step.
  Fixing NF-002 would make this gate enforce itself in CI; that is a separate, infrastructure-level change
  and is left open deliberately.

- **Verified:** `dart analyze` clean, `dart format --set-exit-if-changed` clean across the whole `cli`
  package, full hermetic suite green (**113 tests**). The six tests added for #3 and #4 were each confirmed
  to **fail against the pre-repair engine** and pass after it. The three tests added for the findings above
  were each confirmed to fail against the engine **without** the corresponding fix — the abbreviated-pin
  upgrade conflicts on 2 files, the abbreviation-plus-local-edit case reports 0 canonicalized instead of
  1, and the one-sided-edit upgrade returns `upgradeNoop` — by neutering each fix in place and re-running
  exactly those tests. (Recorded explicitly because NF-005(a) flags a prior commit for claiming this
  verification without doing it.)
- **Follow-ups raised by the independent review of this change**, all pre-existing or documentation-level
  and none of them a blocker: the delivered branch name is still derived from the *typed* revisions, so
  `upgrade e37b2a3` and `upgrade e37b2a3fa344…` name different branches and the A1 re-run refusal does not
  fire between them; `_resolveProductRemote` requires a remote literally named `origin`, which A1 should
  state explicitly; the product's `pre-push` hooks now run for the first time, since hooks are not cloned
  into the scratch clone; the `git fetch` that moves the delivered commit into the product repository
  leaves a `FETCH_HEAD` under its `.git`; and a canonicalized pin file reports itself locally modified
  against its stale `install_hash`, which is inert today (ADR 0004 A3 records why).
- **Known, untouched by this change:** `NF-002` — the CI workflow never reaches a test — still stands.

## Issue #5 — design-review finding disposition + citation checker (merged, not pushed)

Resolved from consumer issue `shipitinc/agentic-engineering-framework#5` (teamhub, 2026-10-07). Two
work items, disjoint ownership, each through the full independent-review loop.

- **Lane A — reach-based finding disposition.** `b5c3b3e` → `5a6c60e` on
  `issue5-disposition-correction`. `engineering-reviewer` → **`DO_NOT_MERGE`** (1 BLOCKER, 2 MEDIUM,
  3 LOW) → correction → `focused-reviewer` → **`APPROVE_CORRECTIONS`**, no blockers, no regressions.
  Zero Dart.
- **Lane B — `check-citations` CLI.** `1d56782` → `ee896b0` → `80dd37c` on
  `issue5-checker-correction`. `engineering-reviewer` → **`DO_NOT_MERGE`** (0 blockers, 1 HIGH,
  2 MEDIUM, 5 LOW) → correction → `focused-reviewer` → **`DO_NOT_APPROVE_CORRECTIONS`** (the L4 safety
  guard was *vacuous*) → correction → `focused-reviewer` → **`APPROVE_CORRECTIONS`**.
  This is the bounded loop's second and final cycle; it closed on the second pass.
- **Integrated:** `main` `7c2d979` → `bd93ef0` (fast-forward to Lane A, then `--no-ff` merge for Lane B
  so both sets of reviewed commits survive verbatim). No squash, no force, no amend; both lane chains
  intact and every reviewed commit an ancestor of `main` with its original object id.
- **Gates at `bd93ef0`:** `dart format` clean (36 files, 0 changed), `dart analyze` no issues,
  `dart test` **170/170**, `dart compile exe` succeeds; adapter drift `PLATFORM_ADAPTERS_IN_SYNC: 138`
  (brick 57 / root 81) exit 0; root `.agents/` mirror byte-identical to brick canonical; both
  `STRUCTURED_RESULTS.md` copies byte-identical.
- **Not pushed.** Integration is complete and verified; the push is a separate human-authorized step.

### What changed, and why

- **`DESIGN_REVIEW` gained a non-blocking finding disposition.** It previously had **none at all** —
  `payload.findings[]` + `blockers[]` and a three-member status enum — so a design reviewer had no
  structured way to say "true, but cannot change what the implementation does", and every finding had
  to become `CHANGES_REQUIRED`, forcing a correction lane then a fresh review lane.
  `ENGINEERING_REVIEW` already had `non_blocking_followups[]` + `APPROVE_WITH_NON_BLOCKING_FOLLOWUP`, and
  `QA_GOVERNANCE.md` rule 5 already made `OPTIONAL` / `NOT_IN_DEFAULT_PIPELINE` rows non-blocking by
  construction. **`DESIGN_REVIEW` was the sole outlier**, so this is a symmetry repair, not a new concept.
- **Additive:** `blast_radius: REACHES_IMPLEMENTATION | EVIDENCE_HYGIENE` per finding;
  `payload.non_blocking_findings[]`; status member `APPROVED_WITH_NON_BLOCKING_FINDINGS`; agent token
  `DESIGN_REVIEW_APPROVED_WITH_NON_BLOCKING_FINDINGS` with consumption paths at all four sites
  (`subtask-report.md` role row + normalization table, `aef-orchestrator` phase row, `aef-run-feature`
  routing). `schema_version` stays `1.0`; the global `Status Values (Enum)` table was deliberately
  **not** expanded (see NF-001 below).
- **Classification is by reach, not by symptom** — the discriminator is *"can this finding change what
  the implementation does?"* A "register that disagrees with itself" is hygiene in a **count table** and
  `REACHES_IMPLEMENTATION` in a **traceability row asserting which requirement a normative rule serves**.
  The consumer's original list was symptom-shaped and would have been gameable.
- **Human Decision `313e9aab-2eba-48c8-9e61-a969b0adbc51` (`.decisions/`, type `DESIGN`, RESOLVED as
  `OPTION_A`)** took the gate-relaxation decision. Its load-bearing condition — *non-blocking means
  RECORDED AND STILL REQUIRED before Design Contract freeze, never silently dropped* — is enforced by a
  **Gate D5 precondition** plus a **determination mechanism**: each `non_blocking_findings[]` entry
  carries `finding_id` (stable across emits of the same `revision_id`), `resolution: OPEN | CORRECTED`,
  and `resolution_ref`; **closure requires a fresh `DESIGN_REVIEW` recording that `finding_id` as
  `CORRECTED`, and a carried-forward id the fresh emit omits stays OPEN.** Absence is never closure, so
  "no open findings" can no longer be confused with "none were ever recorded".
  `HUMAN_DECISION_REQUIRED` is untouched throughout: Level 2/3 DCR approval and human visual approval
  are unchanged.
- **`check-citations` is a new read-only CLI command** resolving `file:line` citations and extracting
  fenced commands. It is the machine enforcement of the citation-drift defect class.
  **It never executes anything.** There is no subprocess primitive anywhere in `cli/lib/src/check/`, no
  execution parameter on `runCheckCitations`, and `--execute-commands` is a **total refusal** evaluated
  *before* `--help` so no flag ordering reaches help, a scan, or exit 0. Both reviews attacked this
  adversarially — the reviewer proved the guard real by injecting three genuine process primitives into
  throwaway copies and watching the suite go red, and ran 38 scanner cases against the test's own
  hand-written Dart lexer. A partial scan reports `drift_found: indeterminate` and **never a false `no`**.
  Unreadable / non-UTF-8 / UTF-16 input exits **40**, not 255 (that crash was HIGH 1 and is fixed).

### Follow-ups — none is a blocker; all are content changes needing their own review

- **X1 — the design-review checklist names no tool at all.** `check-citations` has **zero** references
  outside `cli/`; there is no existing slot where a tool belongs. Naming it requires first deciding
  whether that checklist should name tools. Owner: framework design governance.
- **X2 — vocabulary mismatch: the checker detects, it cannot classify.** It emits symptom-typed tokens
  (`CITATION_DRIFT {UNRESOLVED_PATH, OUTSIDE_ROOT, LINE_BEYOND_EOF, INVERTED_RANGE, …}`) and emits **no**
  `blast_radius` — correctly so, since Lane A's class depends on *position in the artifact*, which the
  checker does not model. **Neither lane says so.** The risk is a reviewer mapping every finding to
  `EVIDENCE_HYGIENE` by symptom — the exact reasoning Lane A forbids. Needs a documented derivation rule.
- **X3 — a third outcome with no legal disposition.** `CITATION_UNVERIFIED`, `ARTIFACT_SKIPPED`, and exit
  40 ("indeterminate, not a verdict") have no expression in Lane A's two-member `blast_radius` enum;
  `grep -n indeterminate` across the design-governance docs returns zero. An unreadable artifact cannot
  be expressed in a `DESIGN_REVIEW` emit.
- **X4 — measured coverage on this repo's own prose is near-zero.** Running the binary against the
  integrated tree: `--dir docs` → 12 artifacts, **1** citation, 0 commands; `--dir .` → 32 artifacts,
  **1** citation, 0 commands. The governance corpus cites paths and §-sections, not `path:line`, so 170
  green tests say nothing about coverage of this corpus. **Claiming machine enforcement of citation drift
  is premature until the citation form/corpus is decided.** Owner: framework design governance.
- **X5 — latent policy tension, not active.** `check-citations` exits `20 PREFLIGHT_POLICY_FAILURE` on
  any drift, so wiring it into CI would be *stricter* than Gates D1/D3, which permit `EVIDENCE_HYGIENE`
  findings to be non-blocking. Nothing is wired (`grep -rn "check-citations" .github/` → 0 hits). Revisit
  if CI is ever wired.
- **X6 — spelling drift introduced by Lane A, survived two reviews.** The enum token is declared
  underscored (`STRUCTURED_RESULTS.md:244`) while prose uses the hyphenated form **4** times vs **59**
  underscored — specifically the section heading `DESIGN_GOVERNANCE.md:148` and prose `:176`, in both
  root and brick copies. An agent keying on the literal heading token would mis-read it. This is exactly
  the drift class `check-citations` exists to detect, and the checker cannot see it.
- **NF-006 (new) — FIFO or device node named `*.md` hangs `readAsStringSync` forever.** Round 1 guarded
  *exceptions*; a FIFO does not throw, it blocks. **Correctly declined as out of scope**: git refuses to
  track a FIFO (verified), so it cannot arrive from a fork or PR — it needs a local `mkfifo`. The
  residual is real: there is **no time or size bound** on reading an artifact. Fix is a
  `FileSystemEntity.typeSync(p) == file` pre-check. Owner: framework tooling.
- **NF-007 (new) — `UNLISTABLE` rows are readdir-ordered** while the file list is sorted. Run-to-run
  determinism holds (verified 5/5 byte-identical incl. a 2000-artifact tree); only order-*independence*
  is missing. Owner: framework tooling.
- **NF-008 (new) — `cli/framework_cli` is not gitignored.** The documented build gate
  (`dart compile exe`) leaves an untracked ~7.6 MB binary that `git add -A` would commit. Reported by
  both lanes, deliberately not fixed (`.gitignore` was outside their ownership). Owner: framework tooling.
- **NF-001 (pre-existing, extended).** The per-type-vs-global `Status Values (Enum)` conflict now also
  covers `APPROVED_WITH_NON_BLOCKING_FINDINGS`. **Harmless** — `DESIGN_REVIEW` declares its own enum and
  per `subtask-report.md:63-68` that declaration binds — and the global table was deliberately left
  unexpanded. The conflict set grew by one member. Contract owner.
- **R1 (non-blocking, from Lane A's re-review) — Gate D5's precondition is prose-enforced, not
  code-enforced.** There is no JSON-Schema file and no envelope validator anywhere in this framework, and
  every other gate (Gate D5 itself, QA-contract freeze, risk classification) is expressed the same way.
  What changed materially is that the obligation now names an actor, a carrier, a trigger field, and
  evidence. Not a defect of this change.
- **R2 (non-blocking, from Lane A's re-review) — `focused-reviewer.md`'s design branch is defensive.**
  It describes a dispatch no current routing rule produces, and does not name the carrying artifact or
  actor. Correctly scoped to Gate D5; drops nothing.

### Durable lessons persisted by this work (executable, not prose)

- **A guard that reduces its own coverage degrades to a vacuous pass — which is worse than no guard,
  because it looks like evidence.** The L4 safety guard's comment stripper treated the `/**` inside a
  `///` doc comment as a block-comment opener, blanking the remainder of `commands.dart`; it silently
  missed the three process-bearing entry points, and a mutation adding `runBootstrap` to the checker
  **passed the entire suite**. Fixed by making the scanner a real character lexer *and* asserting the
  known process-bearing symbols are actually found — **"fix the extraction, not the expectation"** — plus
  deriving the module set instead of hand-listing it, so coverage cannot be narrowed without failing.
  Made executable in `cli/test/check_citations_test.dart`.
- **"Assert the output is sorted" is not a test unless the unsorted order is made implausible.** A
  48-entry fixture turns a coincidental match into an effective impossibility.
- **A recursive directory listing is all-or-nothing.** Wrapping `root.listSync(recursive: true)` in a
  `try` converts a crash into `artifacts_scanned: 0` + `drift_found: no` + exit 0 — a **false green**,
  strictly worse than the crash it replaced. It needed replacing with a per-directory walk.
- **`PathAccessException` implements `FileSystemException`**, so `on FileSystemException` catches it.
- **Mutation specifications should be compile-checked before being handed to a lane** — the brief's
  literal mutation used a top-level `assert`, which is a keyword error and does not compile.
- **A new per-type enum member silently inherits a contradiction** with any prose asserting "every
  normalized status is a global-enum member" — already false for `READY`/`SUCCESS`/`CREATED`/`FROZEN`.
  Adding the row creates the contradiction; the precedence sentence must be corrected in the same change.

## Next steps for the framework itself

- **Framework complete** (Phases 3-8). No further phase implementation required.
- **Push `main` `bd93ef0`** — integration is complete and verified, but the push is human-authorized and
  has **not** been performed.
- **Register the new revision** in `cli/lib/src/version.dart`, `cli/tool/compute_brick_hash.dart`, and
  `_getExpectedBrickHash()` in `cli/lib/src/commands.dart`, so non-test bootstrap resolves it again.
  The release hash cannot be computed before the commit exists, which is why it stays outstanding — and
  this change **does** modify brick content, so the hash must be registered at the next release.
- **Decide X4/X1 before claiming machine enforcement of citation drift.** The checker works and is
  reviewed, but it finds ~1 citation in this repository's own governance corpus because that corpus uses
  a citation form it does not match.
- **Commit the ADR 0003 / orchestrator change** (independently approved). After the commit, register the
  new revision in `cli/lib/src/version.dart`, `cli/tool/compute_brick_hash.dart`, and
  `_getExpectedBrickHash()` in `cli/lib/src/commands.dart` so non-test bootstrap resolves it again.
  The release hash cannot be computed before the commit exists, which is why it is deliberately still
  outstanding.
- **Prepare first product bootstrap** using the canonical framework and its neutral governance
  contracts, runtime adapters, and product-repo templates.
- Resolve the remaining `UNRESOLVED_FRAMEWORK_AREA` items in [WORKFLOW.md](WORKFLOW.md) if
  desired for future refinement.
- Flesh out [framework/templates/](../../framework/templates/) as Mason bricks during future
  phased implementation.
- Material workflow-framework changes require independent review; consequential governance changes
  require human approval.