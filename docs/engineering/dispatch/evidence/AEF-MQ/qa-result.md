# Task metrics and journey evidence — QA execution

Status: QA_RESULT_PASS. Frozen contract `5f42f832-c170-47cf-bdb7-c1d7237ce503`, v1.0.0.
Executor: `/root/qa_execute`. Source is read-only; owned evidence and lane report only.

## Unit

Final suite at `2a0720eb8f99ec47a0b2e55f6a65fb1a47396cc9` passed 172/172 Dart tests, including the metrics wrapper's seven Python fixture tests, exit0. Evidence: `full-suite-final.log` and `full-suite-final.json`; UTC 02:59:04.231996–03:01:48.185397 on 2026-10-10. Initial integrated suite found two CWD-sensitive test-wrapper failures and one existing template-count expectation; corrections and regression checks are complete and passing. These are implementation/test defects, not telemetry duration observations.

## Regression

At source `68c2d8a70edf21dcbc7093c4dedb649769d3e56f`, `dart analyze` passed with no issues. Final `dart analyze` at2a0720e passed; complete final suite passed172/172, exit0. Initial failed suite is retained only as correction history.

## Distribution

At source `68c2d8a70edf21dcbc7093c4dedb649769d3e56f`, generated adapter drift check and `git diff --check` passed. Independent implementation review is recorded in `../../tasks/AEF-MQ-IMPL-REVIEW/report.md`.

## CLI journey

Evidence: `cli-journey/transcript.txt`, `summary.json`, `summary.md`, `events/*.json`, `calculation-check.json`.

A real disposable consumer received AEF from the CLI at predecessor `a7e1aa31d3e6da4d4ee5d3045ba6f45e1dfa99eb`, whose brick is unchanged at source `68c2d8a70edf21dcbc7093c4dedb649769d3e56f`. The installed adapter recorded two overlapping lanes, pause/wait/resume, one failed test invocation and correction, independent AI verification and synthetic human failure, and a closed run. All outcomes are **synthetic fixture data**; no human acceptance occurred.

The 22 immutable event files produce byte-identical repeated summaries. An independent event-time calculation matches every duration: elapsed 5.911104 seconds, active union 0.891276 seconds, lane effort 1.422863 seconds, waiting union 0.228983 seconds, and unknown 4.930344 seconds. One stable-ID attempt submitted twice remains one event. Parallel lane effort exceeds active union, while neither is substituted for elapsed time. Human fail and AI pass remain separate counters.

Initial normal bootstrap of unregistered baseline `c1476185dd3c9bcd3ba7113c0bcdd6a78c694cdc` failed closed with exit20. Classified `ENVIRONMENT_DEFECT`: development checkout revision was not registered for release integrity. The development bootstrap fixtures explicitly set `FRAMEWORK_CLI_TEST_MODE=true`, matching existing integration-test setup. This bypass is disclosed and is not release-path validation. Both actual upgrades now pass against final CLI/source target `2a0720eb8f99ec47a0b2e55f6a65fb1a47396cc9`: the baseline consumer added the two new artifacts and modified 17 guidance artifacts without conflicts; the metrics predecessor preserved its product-owned file and all 22 event files byte-for-byte, and the upgraded adapter reproduced the identical summary. Upgrade intentionally exits10 (`UPGRADE_READY_FOR_REVIEW`), delivers a review branch, and does not apply it automatically; the disposable fixture explicitly checked out the delivered remote branch for verification. The QA driver was corrected to expect10 after its first successful delivery. This was a fixture assertion issue, not an application defect.

Normal integrity-enabled bootstrap initially rejected the dirty framework checkout as its invoking cwd (uncommitted QA evidence). Classified `ENVIRONMENT_DEFECT`, corrected by invoking the same absolute CLI from the clean consumer repository with explicit `FRAMEWORK_BRICK_PATH`, without test mode. Normal bootstrap PASS at 02:58:47 UTC, with 101 artifacts and manifest pin `68c2d8a70edf21dcbc7093c4dedb649769d3e56f` (registered embedded source). CLI code executed was final `2a0720eb8f99ec47a0b2e55f6a65fb1a47396cc9`; the template tree is byte-identical across predecessor, registered source, and final CLI target. Retained manifest: `cli-journey/normal-manifest.yaml`. This validates the normal integrity-enforced path separately from development-mode setup. Final analyzer and whitespace checks passed at 02:58:54 UTC.

Environment: local Linux x64 git worktrees; Python3.12.14 standard library; Git2.51.1; Dart3.13.5 SDK under scratch tools. Exact version outputs, commands, UTC boundaries, outputs and exits are in transcript. No browser, API, database, visual UI or production deployment applies to this CLI fixture. Delivery remotes are local bare repositories only. Every subprocess has a 180-second bound; no fixture sleeps or service processes were used.

## Provenance and interpretation

- Integrated CLI `target_revision`: `2a0720eb8f99ec47a0b2e55f6a65fb1a47396cc9`. Branch `feat/aef-task-metrics-journey`; base `c1476185dd3c9bcd3ba7113c0bcdd6a78c694cdc`.
- Shipped template/source revision: registered `68c2d8a70edf21dcbc7093c4dedb649769d3e56f`; `git diff a7e1aa31d3e6da4d4ee5d3045ba6f45e1dfa99eb 2a0720eb8f99ec47a0b2e55f6a65fb1a47396cc9 -- framework/templates/__brick__` is empty.
- Complete executor observation window: 2026-10-10T02:52:12Z–02:58:54Z. It includes environment setup and waiting, not measured active engineering effort. Synthetic run durations above measure only fixture operations.
- Reproduce independent saved-event check: `python3 docs/engineering/dispatch/evidence/AEF-MQ/cli-journey/verify_saved_events.py`.
- No human product acceptance, TeamHub deployment, model performance ranking, or causal AEF speed improvement is claimed.

## Failure dispositions

| Failure | Classification | Disposition |
| --- | --- | --- |
| Initial full-suite metrics wrapper used process-wide CWD | IMPLEMENTATION_DEFECT | Corrected in test wrapper with package-resolved paths; unrelated-CWD regression included. Final full suite PASS. |
| Existing bootstrap inventory expected99, new distribution has101 | IMPLEMENTATION_DEFECT | Corrected expectation and explicit new-artifact assertions. Final full suite PASS. |
| Unregistered development source normal bootstrap rejected | ENVIRONMENT_DEFECT | Disclosed development test mode for predecessor setup; normal final registered distribution separately passed. |
| Normal bootstrap invoked from dirty source checkout | ENVIRONMENT_DEFECT | Reinvoked absolute CLI from clean consumer cwd; passed without policy bypass. |
| Fixture driver assumed upgrade exit0 instead of review-required10 | ENVIRONMENT_DEFECT | Corrected driver assertion; already-delivered branch inspected, no duplicate upgrade or source change. |

Durable discovery (`RUNTIME_DISCOVERY`): upgrade success means a delivered review branch and exit10; inspect that branch explicitly to verify installed artifacts. The fixture records this in transcript and this report. No extra framework governance change is needed.

## Required rows

| Row | Result | Exact target / evidence |
| --- | --- | --- |
| E_UNIT | PASS | Final full suite PASS172/172 includes `test/task_metrics_test.dart`, which executes Python adversarial fixtures. |
| E_REGRESSION | PASS | Final `dart analyze` PASS at2a0720e; complete suite PASS172/172. |
| E_DISTRIBUTION | PASS | Drift checked at68c2d8a; canonical/generated trees unchanged through2a0720e. Final whitespace check PASS; independent review confirms guidance. |
| E_CLI_JOURNEY | PASS | Both upgrades and integrity-enabled normal bootstrap use CLI2a0720e. Transcript, preserved22-event fixture, deterministic summaries and independent calculations retained. |

Visual and actual Human QA: NOT_APPLICABLE under this contract. No baseline changes.
