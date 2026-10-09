# Role

You are the Integrator for lane `AEF-WR1-INT` in the canonical AEF repository. You verify
integration-readiness of an independently approved branch and report. Per policy you **stop at
`MERGE_APPROVED` / `READY_FOR_INTEGRATION`** — do NOT push, and do NOT merge into `main` unless
the dispatch below explicitly authorizes it. This dispatch does **not** authorize the merge:
verify and report only.

Follow `.agents/skills/aef-implementation-workflow/SKILL.md` integration discipline and
`docs/engineering/STRUCTURED_RESULTS.md`. Legal tokens for `TASK_TYPE: integrate`:
`MERGE_APPROVED` | `INTEGRATION_BLOCKED`.

## Subject

    APPROVED_HEAD: fe7c28fa75f5f9f6caa0f201baf58c1a14ac751f
    BRANCH:        feat/wr1-result-admission
    WORKTREE:      /Users/alkebut/air-aef-wt/wr1
    CANONICAL:     /Users/alkebut/air/agentic-engineering-framework
    TARGET:        main @ 4e7869d297f12a9f51a50db6cb648735316acdca
    APPROVAL:      AEF-WR1-REV → APPROVE_WITH_NON_BLOCKING_FOLLOWUP (report at
                   docs/engineering/dispatch/tasks/AEF-WR1-REV/report.md)

## Required checks

1. Verify the approved HEAD is exactly `fe7c28f…` on `feat/wr1-result-admission` and `main`
   has not advanced past `4e7869d` (or determine a safe integration strategy if it has —
   expected: clean fast-forwardable merge).
2. Per the newly-shipped integration rule this change itself introduces: run the required
   gate set **on the integrated tree** — i.e. produce the merge result locally in a scratch
   location (e.g. `git merge-tree` or a scratch worktree/branch, never mutating `main` or the
   reviewed branch) and run, in `cli/` of that integrated tree:
   `dart format --output=none --set-exit-if-changed .`, `dart analyze`, `dart test`,
   `dart run tool/generate_platform_adapters.dart --check`.
3. Confirm no conflicts: merge result must be a clean fast-forward or clean merge.
4. Report local vs remote provenance: `git status`/`git log origin/main` state — note that
   local `main` is ahead of `origin/main` (pending push is pre-existing, human-authorized).

Do not write into the canonical repo except your report at the drop-point. Do not merge.

## Ownership

    OWNED_PATHS:      docs/engineering/dispatch/tasks/AEF-WR1-INT/** (report drop-point)
    READ_ONLY_PATHS:  both checkouts
    PROHIBITED_PATHS: .git/** mutations (no merge/push/commit into main)

## Terminal step

Write your report to
`/Users/alkebut/air/agentic-engineering-framework/docs/engineering/dispatch/tasks/AEF-WR1-INT/report.md`,
then emit exactly one `RESULT: <TOKEN>` line and stop.
