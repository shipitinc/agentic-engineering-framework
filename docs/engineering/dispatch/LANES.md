# LANES — dispatch ledger

One row per lane. `DISPATCH_STATE_DIR` = `docs/engineering/dispatch/` (framework default; this
repository does not override it). Prompt is persisted at `tasks/<TASK_ID>/prompt.md` **before**
launch; the returned report is stored verbatim at `tasks/<TASK_ID>/report.md`; Manager lane record
at `tasks/<TASK_ID>/state.json`.

`WORKFLOW_STATE` = `docs/engineering/WORK_STATE.md` (default; this repo does not declare the
TeamHub-style override). `DECISION_DIR` = `.decisions/`.

## Open

| TASK_ID | Type | State | Worktree | Branch | base_sha | head_sha | Next action |
|---------|------|-------|----------|--------|----------|----------|-------------|
| `AEF-WR1-IMPL` | implement | REPORTED | `/Users/alkebut/air-aef-wt/wr1` | `feat/wr1-result-admission` | `4e7869d` | `8f353c1` | IMPLEMENTATION_BLOCKED — KNOWN DEFECT D host-binding; fix lane dispatched |
| `AEF-WR1-FIX1` | implement (correction) | REPORTED | `/Users/alkebut/air-aef-wt/wr1` | `feat/wr1-result-admission` | `8f353c1` | `fe7c28f` | IMPLEMENTED — `dart test` 170/170 verified by Manager at HEAD |
| `AEF-WR1-REV` | review | REPORTED | (read-only) | — | `4e7869d` | `fe7c28f` | `APPROVE_WITH_NON_BLOCKING_FOLLOWUP` → integrator |
| `AEF-WR1-INT` | integrate | REPORTED | canonical repo | `feat/wr1-result-admission` → `main` | `4e7869d` | `fe7c28f` | `MERGE_APPROVED` — awaiting human merge authorization |

## History

| TASK_ID | Type | Result token | base_sha → head_sha | Routing | Note |
|---------|------|--------------|---------------------|---------|------|
| `AEF-WR1-IMPL` | implement | `IMPLEMENTATION_BLOCKED` | `4e7869d` → `8f353c1` | fix-lane `AEF-WR1-FIX1` | All scope delivered + committed; single gate failure is the recorded `bootstrap_integration_test` host-binding defect (verified by Manager reproduction) |
| `AEF-WR1-FIX1` | implement (correction) | `IMPLEMENTED` | `8f353c1` → `fe7c28f` | → `AEF-WR1-REV` | `frameworkRepoPath` derived via package-config resolution; KNOWN DEFECT D defect resolved; `dart test` green at HEAD |
| `AEF-WR1-REV` | review | `APPROVE_WITH_NON_BLOCKING_FOLLOWUP` | `4e7869d` → `fe7c28f` | → `AEF-WR1-INT` | All gates independently re-run green; 3 non-blocking followups recorded (stale comment, WORK_STATE resolved-note, trivial preflight edge) |
| `AEF-WR1-INT` | integrate | `MERGE_APPROVED` | `4e7869d` → `fe7c28f` | → HUMAN | Clean FF verified; gates green on integrated scratch tree; first report malformed → re-emitted valid |
| `AEF-WR1-AUDIT` | review (post-merge audit) | `APPROVE_WITH_NON_BLOCKING_FOLLOWUP` | `4e7869d` → `7770b12` | closed | Fresh independent audit of the full adoptable delta; all gates re-run green at `7770b12`; 3 LOW non-blocking findings (LOW-1 stale brick WORKFLOW.md text and LOW-2 `.devin`-flavored adapter framing fixed at `8b06a5d`; LOW-3 was the validator correctly rejecting a bad token — no action); report self-validates `VALID` |
| `AEF-WR1-FIXTURE` | verification (Manager-run) | PASS | fixture `f43636b` → `7770b12` | closed | Disposable product + bare remote under `/Users/alkebut/air-aef-wt/upgrade-fixture/`; real `bootstrap`+`upgrade`; 1 honest conflict (`WORK_STATE.md`), customizations survived, manifest pinned full SHA, rerun refused (`UPGRADE_BLOCKED` exit 20) |

## Resolved inputs for this work item

Decided in-session via the structured question UI on 2026-10-08 (recorded verbatim in
`decisions-2026-10-08.yaml`; the questions were presented and answered directly rather than raised
as parked Human Decision objects — no PENDING period existed):

1. Report validation ships as a **brick-instantiated portable script** (reaches product repos,
   where the observed failure happened). CLI-only and prose-only were rejected.
2. **Adopt the explicit per-artifact cap** (one review + one correction pass per pre-implementation
   artifact) on top of the Gate D5 deferral mechanism.
3. The integrated-user-journey `E_*` row is **mandatory (`REQUIRED`)** in every QA Contract, not a
   project-narrowable default.
4. Partnerhub-style harness adapters **ship as optional templates** in the brick.

## Ownership map (concurrent writers)

`MAX_CONCURRENT_WRITERS` = 3.

| Lane | `OWNED_PATHS` | Running | Intersects |
|------|---------------|---------|------------|
| `AEF-WR1-IMPL` | `framework/templates/**`, `docs/engineering/**` (except `dispatch/` — Manager), `.agents/`, `.claude/`, `.junie/`, `.opencode/` (regeneration only, via `cli/tool/generate_platform_adapters.dart`), `cli/test/platform_adapter_test.dart`, `cli/test/bootstrap_integration_test.dart`, `docs/engineering/WORK_STATE.md` § this work item's block — **no**; WORK_STATE is Manager-owned | yes | — |

Correction: `docs/engineering/**` other than `dispatch/` belongs to the lane; `dispatch/` stays
Manager-owned bookkeeping.

## AEF metrics and journey work — 2026-10-10T02:35:16.133946+00:00

Manager self-edit: persisted dispatch prompts and ownership before launch. Existing defaults apply; LANE_WORKTREE_ROOT is /workspace/scratch/2c5d5034fecb (not OS temporary storage). Two isolated writers; ownership explicitly disjoint. AEF-METRICS owns new metrics script/docs/tests and script README; AEF-JOURNEY owns canonical policy/QA templates; generated outputs reserved for serialized generation. Independent review required before integration.

AEF-MQ-CONTRACT dispatched to distinct QA Architect in isolated aef-qa worktree; sole owned path docs/engineering/dispatch/evidence/AEF-MQ/qa-contract.md. Journey lane owns generated outputs via generator only; metrics lane owns CI inclusion for new tests. No overlaps.

Manager froze QA contract v1.0.0 following read-only independent APPROVE_FOR_MERGE at fdf5e3c; no implementation approval implied. Child interruption was host usage limit; resumed on user request. Dart SDK permission repaired; no framework source workaround.

Integrated source candidate68c2d8a independently approved. Full suite found new metrics wrapper cwd coupling; correction scoped solely cli/test/task_metrics_test.dart, fresh focused review dispatched. GitHub create-tree denied403 Resource not accessible by integration; no publication performed.

Final source target:2a0720eb8f99ec47a0b2e55f6a65fb1a47396cc9. All172 tests pass at exact target;
normal integrity-enabled install and both upgrades pass. Independent review approved source,
CWD/packaging corrections and release registration. QA architect and executor were distinct.
Publication blocked only by GitHub integration write access (403); user permission update needed.
No new mandatory approval, no remote changes, no TeamHub upgrade performed.

Publication retry: GitHub access restored; source snapshota1e082c published to feat/aef-task-metrics-journey,
matching local4a9d0ed tree exactly. AEF-MQ-PUBLISH-PIN implemented two SHA replacements;
AEF-MQ-PUBLISH-REVIEW approved exact3a08956. Normal bootstrap verifies reachable source pin without
test mode. Prior GitHub403 blocker resolved. Main and TeamHub unchanged; draft review submission follows.
