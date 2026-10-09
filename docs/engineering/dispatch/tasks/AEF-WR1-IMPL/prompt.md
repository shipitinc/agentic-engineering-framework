# Role

You are the Implementer for a **framework-internal workflow change** in
`shipitinc/agentic-engineering-framework` (the canonical AEF repo). You follow
`.agents/skills/aef-implementation-workflow/SKILL.md`. This change makes
dispatch/review/QA admission mechanical and bounded, informed by measured
failures in the TeamHub product repo and working Partnerhub practices. **No new
lifecycle stage, no new human gate, no new mandatory tool dependency.**

`TASK_TYPE: implement` (STANDARD class — bounded cross-cutting policy change).
Read `docs/engineering/STRUCTURED_RESULTS.md` for the mandatory report grammar —
your `report.md` is validated mechanically before the Manager may advance state.

## Worktree

    WORKTREE: /Users/alkebut/air-aef-wt/wr1
    BRANCH:   feat/wr1-result-admission
    BASE_SHA: 4e7869d297f12a9f51a50db6cb648735316acdca   # main @ task start (verify with git rev-parse HEAD of base)
    CANONICAL REPO: /Users/alkebut/air/agentic-engineering-framework  (READ-ONLY to you)

The worktree was created with `git worktree add` against BASE_SHA. Work there.
Commit your changes on `feat/wr1-result-admission` (a normal descriptive commit
is expected; you may commit once at the end).

## Ownership (declare verbatim at the top of your report)

    OWNED_PATHS:
      - framework/templates/**          # brick canonical .agents/, docs/, and NEW scripts/aef/
      - framework/templates/product-repo/**
      - framework/templates/README.md
      - docs/engineering/**             # EXCEPT docs/engineering/dispatch/** (Manager-owned)
      - .agents/**, .claude/**, .junie/**, .opencode/**   # REGENERATED ONLY, via cli/tool/generate_platform_adapters.dart — never hand-edit
      - cli/test/platform_adapter_test.dart
      - cli/test/bootstrap_integration_test.dart          # managed-path counts only, if they change
    READ_ONLY_PATHS:
      - .agents/skills/aef-implementation-workflow/SKILL.md  # canonical source is in __brick__; root is generated
      - cli/lib/**, cli/bin/**, cli/tool/** (read for understanding; only the two test files are owned)
      - docs/engineering/dispatch/**
    PROHIBITED_PATHS:
      - .git/**, any path outside this repository and worktree
      - TeamHub, Partnerhub, or any other product repository

## Canonical/generated mechanics — read this before editing

- `.agents/` **inside the brick** (`framework/templates/__brick__/.agents/`) is the canonical
  source for agent profiles and skills. The repository-root `.agents/` is a **generated mirror**.
- `.claude/`, `.junie/`, `.opencode/` (both under `__brick__/` and at repo root) are **generated
  adapters**. Never hand-edit them. After canonical edits, run
  `dart run tool/generate_platform_adapters.dart` from `cli/` to regenerate; verify with `--check`.
- `docs/engineering/` exists in BOTH the repo root and the brick. The two copies are maintained in
  parallel: `STRUCTURED_RESULTS.md` copies are byte-identical and MUST remain so;
  `WORKFLOW.md` copies differ deliberately (path-qualification / ADR-0004 bootstrap wording).
  Rule: apply the semantic change to BOTH copies; where copies are currently byte-identical they
  must stay byte-identical; where they differ, preserve each copy's deliberate differences.
- New files under `framework/templates/__brick__/` become managed product artifacts and are
  counted by `cli/test/bootstrap_integration_test.dart` (currently 93 managed paths) — update the
  expected count.

## Scope — required changes

### 1. Brick-shipped report validator (the centerpiece)

Create `framework/templates/__brick__/scripts/aef/validate-report.sh`:
- POSIX `sh`, no build dependency; may use `python3` for parsing if present, but MUST fail closed
  (non-zero exit, named violation) if a required capability is absent — never silently pass.
- Usage: `validate-report.sh <report-file> [--expect-task-type <TYPE>]`.
- Validates against a lane report on disk (fail closed, non-zero exit + printed violations):
  (a) file exists and is non-empty; (b) contains a YAML front-matter/header block;
  (c) all mandatory keys present: `RESULT`, `TASK_ID`, `TASK_TYPE`, `FEATURE`, `WORKTREE`,
      `BRANCH`, `BASE_SHA`, `HEAD_SHA`, `COMMITTED`;
  (d) `TASK_TYPE` is a member of the legal enum in
      `framework/templates/__brick__/.agents/skills/aef-orchestrator/templates/subtask-report.md`;
  (e) `RESULT` is a member of the legal vocabulary **for that TASK_TYPE** per the same table —
      encode the TASK_TYPE→tokens map in the script as data;
  (f) if `--expect-task-type` is given, `TASK_TYPE` must match.
- Exit 0 and print a one-line `VALID` summary only when all checks pass.
- Keep the token map in one place at the top of the script so future vocabulary additions are
  one-line edits.

Update `framework/templates/__brick__/.agents/skills/aef-orchestrator/SKILL.md`: in the
report-consumption flow (§5), add a mandatory **admission step** — before the Manager may act on
any lane outcome it must (i) confirm `report.md` exists on disk in `tasks/<TASK_ID>/`, (ii) run
`scripts/aef/validate-report.sh` against it (or perform the equivalent mechanical checks if the
script is absent — fail closed either way), (iii) confirm `RESULT` is legal for the lane's agent.
A missing or malformed report is `UNSCOPED`, not consent. Report this check's result in the lane's
Manager state.

### 2. Bounded waits + cancellation recovery (aef-orchestrator)

In `framework/templates/__brick__/.agents/skills/aef-orchestrator/SKILL.md` §4/§5:
- **Artifact-as-completion**: the durable signal is `report.md` on disk, not the child-session
  notification.
- **Bounded wait**: on dispatch, wait one bounded block (state a concrete budget, e.g. 10 min);
  then inspect `report.md`. If a valid report exists → proceed and terminate the child. If absent
  but the child is still active → allow exactly one additional bounded block. If still no report →
  re-dispatch the lane once (new isolated session); if that also fails to produce a report → mark
  the lane `BLOCKED: NO_REPORT` in LANES.md, park, and surface to the human.
- **Provider cancellation**: a lane cancelled at the provider produces no report; re-dispatch
  up to once, then park `BLOCKED: PROVIDER_CANCELLED`. Never count a cancelled attempt as a verdict.
- **Reaped worktree**: if the lane worktree path vanished (OS temp reaping), recreate it from the
  lane branch (`git worktree add` at the recorded `HEAD`/`base`), verify `HEAD` before resuming.
- Restate explicitly: Manager-run gates/verification are consistency checks, **not** the
  independent-review gate. A cancelled or reportless review lane cannot be replaced by Manager
  verification. (Observed: TeamHub `L1-CORR-1` — five provider cancellations, zero reports.)

### 3. Durable worktree root

In the same skill: add convention `LANE_WORKTREE_ROOT` (env-overridable, default
`<repo-parent>/<repo-name>-wt/`) and amend the isolation bullet to require lane worktrees be
created **under `LANE_WORKTREE_ROOT`, never inside OS temporary space** (`/var/folders`, `$TMPDIR`)
— observed failure: OS reaped lane worktrees mid-lane in TeamHub.

### 4. Terminal-step + fail-fast contract (subtask-prompt)

In `framework/templates/__brick__/.agents/skills/aef-orchestrator/templates/subtask-prompt.md`,
add to "Terminal step" / "Failure mode rules":
- After writing `report.md`, emit **exactly one** `RESULT: <TOKEN>` line and make **no further
  tool calls** (reports returned as messages but never written, or lanes that kept working after
  reporting, were observed failures).
- If a required tool/dependency is unavailable → stop and report `BLOCKED` with the missing
  capability named; do not improvise a substitute.

### 5. Review admissibility — upstream TeamHub D20

In `framework/templates/__brick__/.agents/skills/aef-independent-review/SKILL.md` (Sufficiency +
Steps) and in `framework/templates/__brick__/.agents/agents/engineering-reviewer.md` and
`focused-reviewer.md` (principles/evidence sections): a review verdict is **admissible only where
each claimed check is separable and re-runnable** — run the artifact's own published commands,
quote literal command output verbatim including failures, copy identifiers (finding ids, paths,
SHAs) from the artifact rather than inventing them, and report a git-derived diffstat. A verdict
claiming checks that cannot be reproduced from the artifact is invalid on its face; a missing
verdict is not a verdict. Read-only constraints unchanged.

### 6. Mandatory integrated-journey row + probes preference

- `framework/templates/__brick__/docs/engineering/QA_GOVERNANCE.md` **and**
  `docs/engineering/QA_GOVERNANCE.md` (keep byte-identical): in "Required QA fields"/"Pipeline",
  add a contract-level requirement: **every QA Contract MUST declare at least one `REQUIRED`
  `E_*` row** exercising an integrated end-to-end user journey against the integrated/deployed
  build at the pinned `target_revision`; it must reach `EXECUTED` before Human QA initiation —
  or carry a formal `SKIPPED` determination with `authority_ref`. Human QA may not begin on a
  contract whose journey row is missing, `PLANNED`, or `BLOCKED`.
- Add a **probes-over-review-passes** preference (QA_GOVERNANCE remediation routing): for
  runtime-observable QA failure classes (e.g. wrong HTTP status at a guard site), prefer a
  committed regression probe in the QA suite over another review pass — a probe produces durable
  executable evidence; a review pass does not. Keep the explicit note that review remains the
  right tool for normative/specification defects.
- `framework/templates/__brick__/.agents/skills/aef-qa-contract/SKILL.md` (Required fields +
  validation checklist): the journey-row requirement above; verifier must reject a contract
  lacking it.
- `framework/templates/__brick__/framework/templates/qa-contract.template.md`: add a commented
  example `E_*` row marked `REQUIRED`/`AUTOMATED|COMBINED` for an integrated journey.
- **Resolve the open marker**: `framework/templates/__brick__/docs/engineering/WORKFLOW.md`
  (root copy too, preserving its deliberate differences) `UNRESOLVED_FRAMEWORK_AREA: how runtime
  or browser evidence is captured and pinned` — replace with the rule: runtime/browser evidence
  belongs to the exact pinned `target_revision` of the integrated build it ran against; the
  integrated journey row records the served-revision SHA in `evidence_ref`.

### 7. Iteration vs. integration validation

- `aef-implementation-workflow/SKILL.md`: lanes MAY run a targeted subset during iteration;
  the lane's declared required gate set MUST pass at the reported `HEAD_SHA` before review
  dispatch (a failed subset remains a failed gate).
- `aef-orchestrator/SKILL.md` §9/§10 and `.agents/agents/integrator.md`: after review approval,
  the required gate set runs **again on the integrated tree** before acceptance —
  approval at lane `HEAD_SHA` does not waive integrated-tree gates.

### 8. Explicit per-artifact cap (pre-implementation design review)

- `DESIGN_GOVERNANCE.md` (both copies) + `aef-design-review/SKILL.md` +
  `design-reviewer.md`/`focused-reviewer.md`: each pre-implementation design artifact revision
  gets **at most one full review pass plus one correction pass**. A post-correction verification
  (focused re-review) may report **regressions only** — findings introduced by that correction.
  All other post-cap findings route by blast radius: `EVIDENCE_HYGIENE` → recorded onto the Gate
  D5 open set; `REACHES_IMPLEMENTATION` → Design Contract Revision / new revision (a genuine
  design change, not another correction lane). Stated boundless re-review of the same revision is
  out of scope for reviewers.

### 9. Close open items X1–X3 (check-citations integration)

- `aef-design-review/SKILL.md` + `aef-design-workflow/SKILL.md`: name `framework check-citations`
  in the checklists where citation/prose references are in scope.
- `docs/engineering/LEARNINGS.md` X1–X3 blocks: mark resolved/superseded with this change —
  the derivation rule (the checker detects drift symptoms; the reviewer's position classifies
  `blast_radius`) and the disposition for `indeterminate`/unreadable citations (**record as an
  open EVIDENCE_HYGIENE finding; never a pass**). Move the closed blocks to the
  `## Closed` section format already in use.

### 10. Optional harness adapter templates

Create `framework/templates/__brick__/scripts/aef/` reference adapters generalized from
Partnerhub (`/Users/alkebut/IdeaProjects/partnerhub/.devin/scripts/` — read if accessible,
otherwise implement from the descriptions below; strip all product/host identifiers):
- `save-task-state.sh` — reads a `todo_write`-style hook JSON event from stdin, writes
  `.devin/task-state.md` with `# Pending Tasks` / `# Completed Tasks` sections; preserves
  `.devin/active-worktrees.md` if present; always exits 0 (never blocks the tool).
- `load-task-state.sh` / `check-task-state.sh` — restore/report persisted task state.
- `launch-preflight-check.sh` — parameterizable pre-flight check for a subagent lane
  (required tools present, worktree exists, branch recorded).
- `README.md` — one page: these are OPTIONAL host adapters; canonical AEF policy requires no
  hooks; wiring (e.g. `.devin/hooks`) is product-side.

## Gates (run inside the worktree; report each exact command)

1. `cd cli && dart format --output=none --set-exit-if-changed .`
2. `cd cli && dart analyze`
3. `cd cli && dart test`
4. `cd cli && dart run tool/generate_platform_adapters.dart` then `... --check` (regenerate, then verify no drift)
5. `cd cli && dart compile exe bin/framework.dart -o /tmp/aef-wr1-framework` (keep the tree clean)
6. Exercise `scripts/aef/validate-report.sh` (in the worktree, at its brick path) against:
   a valid fixture report (exit 0) and malformed fixtures (missing file, missing `RESULT`,
   illegal token for TASK_TYPE, missing mandatory key) — each must exit non-zero.
7. `git diff --stat` vs BASE_SHA.

Checks not run → `NOT_RUN` in the report. Never claim a pass you did not run.

## Constraints

- Surgical edits; no refactors, no renames, no unrelated cleanup. Keep "Designed for Devin" stays
  harness-neutral (§14): canonical policy MUST NOT depend on any host's hooks.
- Both `docs/engineering/` copies per the sync rule above; `__brick__` mirrors only `.agents/` —
  docs changes are applied to each copy directly.
- If you find an edit would require changing `cli/lib/**` or `cli/bin/**`, stop and report
  `BLOCKED` (those are out of scope).
- No lifecycle stage, no new human gate, no new mandatory external dependency.

## Terminal step

Write `report.md` to `docs/engineering/dispatch/tasks/AEF-WR1-IMPL/report.md` **in the canonical
repo** (this bookkeeping dir is Manager-owned but is the agreed report drop-point — writing your
report file there is your only permitted write outside `OWNED_PATHS`), then reply with exactly
one `RESULT: <TOKEN>` line and stop.
