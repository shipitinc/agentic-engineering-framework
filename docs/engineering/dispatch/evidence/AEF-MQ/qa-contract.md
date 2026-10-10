# AEF task metrics and journey evidence — QA contract

- `contract_id`: `5f42f832-c170-47cf-bdb7-c1d7237ce503`
- `version`: `1.0.0`
- `status`: `FROZEN`; Manager froze v1.0.0 after independent approval of fdf5e3c on 2026-10-10.
- `design_contract_ref`: not applicable; no application UI or visual design changes.
- Requirements: original user request to add AEF updates and repository-consumable task duration/statistics, scoped by `dispatch/tasks/AEF-METRICS/prompt.md` and `dispatch/tasks/AEF-JOURNEY/prompt.md`.
- Source base: `c1476185dd3c9bcd3ba7113c0bcdd6a78c694cdc`.
- Ownership: QA Architect owns this file only; implementation, generated adapters, lifecycle state, and QA execution evidence are outside this lane.

## Acceptance criteria

1. **Telemetry portability:** a Python 3 standard-library adapter ships through existing bootstrap/upgrade, with copyable documented commands, no network dependency or transcript/secret collection, and immutable machine-readable events plus reproducible JSON/Markdown summaries.
2. **Duration honesty:** deterministic fixtures distinguish wall elapsed, observed active interval union, aggregate lane effort, waiting by reason, and unknown time. Parallel work cannot inflate wall/union duration; unfinished observations, missing data, pauses and inconsistent timestamps cannot silently become precise completed work. Commits do not infer active time.
3. **Event integrity:** concurrent writers retain every distinct event; duplicate/idempotent submissions follow a documented policy without inflating aggregates; malformed events/timestamps fail clearly without corrupting existing history. Task/run/parent scope and model, harness, framework and git provenance remain inspectable, with unavailable fields explicitly unknown.
4. **Outcome honesty:** explicitly recorded attempts, review verdicts, corrections, test/build failures, environment blockers, QA escapes, and human QA outcomes summarize accurately. Agent verification never implies human acceptance. Mixed models/scopes do not support causal performance claims.
5. **Actual journey guidance:** existing contracts/evidence require uninterrupted real UI interaction, applicable fresh signed-out state and auth transitions, actual post-auth route and retained-state assertions, production dependencies/lifecycle, explicit fixture disclosure, reset prerequisites, and exact revision/build/environment/browser provenance. Navigation shortcuts and substituted clients cannot stand in for the claimed journey.
6. **Operational guidance:** preflight covers API and database ports/ownership, isolated fixture teardown, dedicated browser context/tab, bounded timeout/stall recording, and serialization of resource-heavy work when required. It adds no arbitrary retries, lifecycle stage, or approval loop.
7. **Adoption consistency:** canonical skills/templates and root/brick governance agree; generated adapters pass drift checking. Orchestration/report pointers use the implemented telemetry interface; missing telemetry remains an observability limitation rather than a new approval gate.
8. **Integrated usability:** a disposable consuming git repository receives the adapter through the real framework CLI and completes the documented telemetry lifecycle, including concurrent lanes, wait/resume, a failure/correction and separately recorded agent/human QA outcomes; generated summaries match its saved events. Existing upgrade preserves product-owned files and event history.

## Strategy and evidence rows

All rows below are `REQUIRED`, initially `READY_NOT_EXECUTED`; these are contract declarations, not execution claims. Executor pins each result to the exact integrated `target_revision` and records commands, UTC start/end, exit status, environment/tool versions and concrete artifact paths. No row may remain unexecuted in a passing QA result. An unrunnable gate requires a reason plus Manager disposition (formal authorized skip or contract revision).

| Row | Criteria | Artifact reference / parameters | Prerequisites and passing threshold |
| --- | --- | --- | --- |
| `E_UNIT` | 1–4 | `qa-result.md#unit`; from `cli/`: `dart test test/task_metrics_test.dart`, including its Python fixture tests | Python 3 and resolved Dart dependencies. All tests pass, including overlap, pause/unclosed/missing intervals, malformed data, duplicate handling, concurrent writes and QA/correction counters. |
| `E_REGRESSION` | 1, 7–8 | `qa-result.md#regression`; from `cli/`: `dart analyze` and `dart test` | Supported Dart SDK and resolved dependencies; analyzer and complete existing CLI suite pass. No placeholder assertions substitute for observed outcomes. |
| `E_DISTRIBUTION` | 5–7 | `qa-result.md#distribution`; from `cli/`: `dart run tool/generate_platform_adapters.dart --check`; repository `git diff --check`; focused independent document review | Generated artifacts are present at target revision; no drift/whitespace errors. Review confirms criteria 5–7 and root/brick alignment without unrelated governance changes. |
| `E_CLI_JOURNEY` | 1–4, 8 | `qa-result.md#cli-journey` with retained `cli-journey/` transcript, representative event files and JSON/Markdown summaries; execute documented adapter commands from the bootstrapped consuming repo | Disposable git repository; CLI binds to exact target framework checkout. Bootstrap and existing-repo upgrade install script/docs; original product file and saved events survive upgrade. Exercise lifecycle in criterion 8. Record actual generated times as observations; compare summaries to events and repeat summary with identical explicit cutoff where supported. Report wall vs lane effort separately. |

The required integrated end-to-end journey is `E_CLI_JOURNEY`: the framework's user-facing surface is a CLI workflow, not TeamHub's application. Test the shipped adapter, not a directly copied source script. Keep the consuming repository local and disposable; no production deployment/access is required.

- **Unit:** defined in `E_UNIT`, deterministic known-value calculations and integrity adversaries.
- **Integration/contract:** defined in `E_REGRESSION` and `E_DISTRIBUTION`, packaging, CLI compatibility, schema/document consistency.
- **E2E:** defined in `E_CLI_JOURNEY`, real consumer bootstrap → record → summarize → upgrade.
- **Visual:** `NOT_APPLICABLE`; no rendered application UI or golden baseline changes. `golden_baselines: []`.
- **Human:** `NOT_APPLICABLE` for this bounded framework change; no customer application acceptance is claimed. Human outcome events in QA are labeled synthetic fixtures, never actual acceptance.

## Results, retention and regressions

QA Executor remains read-only for implementation and records one determination per row. Preserve concise reproducible logs/fixtures under `docs/engineering/dispatch/evidence/AEF-MQ/` with the repository history; redact credentials and avoid captured private transcripts. Evidence must identify the tested code revision, separate from any later evidence-only commit. Independent review and Manager freeze/integration retain existing authority; telemetry itself creates no gate.

Any discovered implementation regression requires a focused regression test before re-verification. Classify each failure exactly once as `IMPLEMENTATION_DEFECT`, `DESIGN_DEFECT`, `REQUIREMENT_GAP`, or `ENVIRONMENT_DEFECT`; distinguish environment/setup retries from implementation corrections. QA reports elapsed observations without inferring model speed or framework benefit from this single run.
