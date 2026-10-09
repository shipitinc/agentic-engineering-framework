# Role

You are the Implementer for correction lane `AEF-WR1-FIX1` in the canonical AEF repository.
Follow `.agents/skills/aef-implementation-workflow/SKILL.md`. `TASK_TYPE: implement`.
Read `docs/engineering/STRUCTURED_RESULTS.md` — your report is mechanically validated.

## Worktree

    WORKTREE: /Users/alkebut/air-aef-wt/wr1
    BRANCH:   feat/wr1-result-admission   (existing — commit ON TOP of it, do not rebase)
    BASE_SHA: 8f353c1ceea1d753b08f1c6f09383c48a6c171b0   (current branch HEAD)

## Problem — recorded known defect, now blocking a required gate

`cli/test/bootstrap_integration_test.dart:19-20` hardcodes:

    final String frameworkRepoPath = '/Users/alkebut/air/agentic-engineering-framework';

The spawned `dart run cli/bin/framework.dart` uses that path as `workingDirectory`, so the
bootstrap-under-test always exercises the **canonical checkout's brick**, regardless of which
checkout the test file itself lives in. In this lane's worktree the brick gained `scripts/aef/*`
(managed count 93→99); the canonical brick still renders 93, so `KNOWN DEFECT D` fails with
`Expected managed artifact: scripts/aef/README.md`. The defect is already recorded unresolved in
`docs/engineering/WORK_STATE.md` (~line 268, "host-binding defect").

## Required change

In `cli/test/bootstrap_integration_test.dart` only:

- Replace the hardcoded `frameworkRepoPath` with a derivation from the test's own location —
  i.e. resolve the repository root that contains this test file (e.g. from `Platform.script`:
  `cli/test/bootstrap_integration_test.dart` → up three levels), so the spawned bootstrap binds
  to the checkout under test (canonical repo when run there, worktree when run in a lane).
- Keep a `FRAMEWORK_REPO_PATH` environment-variable override if you judge it useful for CI;
  the default must be the derived path, not a host path.
- No other semantic changes. Do not touch `cli/lib/**`, `cli/bin/**`, or `cli/tool/**`.

## Ownership

    OWNED_PATHS:
      - cli/test/bootstrap_integration_test.dart
    READ_ONLY_PATHS: everything else in the repo/worktree
    PROHIBITED_PATHS: .git/**, outside this repository and worktree

## Gates (inside the worktree)

1. `cd cli && dart format --output=none --set-exit-if-changed .`
2. `cd cli && dart analyze`
3. `cd cli && dart test` — **must be fully green** (170/170). The DEFECT D test must pass by
   binding to the worktree brick (which has 99 artifacts).
4. Sanity: the same derivation must also be correct when run from the canonical checkout —
   verify by reasoning about the path math, do NOT run the suite in the canonical repo.
5. `git diff --stat 8f353c1ceea1d753b08f1c6f09383c48a6c171b0`

Anything not run → `NOT_RUN`. A required-tool absence → `BLOCKED`, not improvisation.

## Terminal step

Commit on `feat/wr1-result-admission`. Write `report.md` to
`docs/engineering/dispatch/tasks/AEF-WR1-FIX1/report.md` in the canonical repo
(`/Users/alkebut/air/agentic-engineering-framework` — that drop-point is your only write outside
the worktree). Then emit exactly one `RESULT: <TOKEN>` line and stop.
