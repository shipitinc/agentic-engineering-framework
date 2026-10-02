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
  ADR 0003 correction scope.
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

## Next steps for the framework itself

- **Framework complete** (Phases 3-8). No further phase implementation required.
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