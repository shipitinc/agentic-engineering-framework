# Optional task metrics

Task metrics make delivery time and rework inspectable from repository files. They are
observations, **not lifecycle state, approval evidence, a completion gate, or a model leaderboard**.
A missing adapter, unavailable Python, or a failed recording must not block product work. Note the
coverage gap in the lane report; do not manufacture historical events from commit timestamps.

The shipped `scripts/aef/task-metrics.py` needs Python 3.9+ and its standard library, no service,
credentials, hook integration, or additional package. Receive it through the existing AEF CLI
bootstrap/upgrade workflow, reviewing the upgrade diff as usual. Run from the product repository
root. In this framework source repository, the script lives under
`framework/templates/__brick__/scripts/aef/`.

## Capture a run

Use one run ID for a comparable deliverable and unique task IDs for its lanes. The Manager owns run
boundaries; each lane records its own observations. Record only meaningful transitions, not every
tool call. A task's `task_start`/`task_stop` measures elapsed task time; it does **not** imply active
work. Explicit active intervals mean observed engagement (including normal tool waits), not CPU
utilization, billed tokens, or human labor. Stop them when parking, handing off, or ending a session.
A crash leaves an unknown interval, never an indefinitely running timer.

```sh
python3 scripts/aef/task-metrics.py event --run JRN-2 --task manager --type run_start --metadata '{"scope":"follow team to schedule","model":null,"harness":"Devin","framework_revision":"EXACT_AEF_SHA"}'
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type task_start --metadata '{"scope":"journey correction","model":"ACTUAL_MODEL_ID","harness":"Devin","framework_revision":"EXACT_AEF_SHA","parent_task":"manager"}'
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type attempt --event-id JRN-2-UI-attempt-1
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type active_start --interval coding-1
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type active_stop --interval coding-1
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type wait_start --interval blocked-1 --reason environment
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type environment_blocker --ref docs/engineering/dispatch/tasks/UI/report.md
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type wait_stop --interval blocked-1
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type active_start --interval coding-2
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type active_stop --interval coding-2
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI --type task_stop --outcome implemented
python3 scripts/aef/task-metrics.py event --run JRN-2 --task manager --type run_stop --outcome ready_for_human_qa
```

Pause: close the active interval and start a wait with its reason if known. Resume: close that wait
and open a **new** active interval ID. An unexplained gap remains unknown. Choose run scope before
starting: closing at `ready_for_human_qa` measures that milestone, not accepted delivery. To measure
accepted delivery, keep the run open through Human QA or start a separately scoped follow-up run.
Run IDs cannot be reopened; task IDs have one lifecycle per run (use a new ID for another lane).

Record each attempt and correction once, with a stable event ID for retryable integrations:

```sh
python3 scripts/aef/task-metrics.py event --run JRN-2 --task REVIEW --type review --outcome changes_required --ref docs/engineering/dispatch/tasks/REVIEW/report.md
python3 scripts/aef/task-metrics.py event --run JRN-2 --task UI-FIX --type correction --event-id JRN-2-UI-FIX-correction
python3 scripts/aef/task-metrics.py event --run JRN-2 --task QA --type ai_verification --outcome pass
python3 scripts/aef/task-metrics.py event --run JRN-2 --task HUMAN-QA --type human_qa --outcome fail --ref docs/engineering/human-qa-results.md
python3 scripts/aef/task-metrics.py event --run JRN-2 --task HUMAN-QA --type qa_escape --reason IMPLEMENTATION_DEFECT --ref docs/engineering/human-qa-results.md
```

These outcome examples belong **before** the run stop, or in a new follow-up run. `human_qa` must
reference an actual human result, never an AI prediction. Record one `qa_escape` per distinct defect
found after an earlier verification; do not count every failing assertion as a new defect. Review
outcomes and correction events remain separate: a review may have no corrections or several.
Use stable outcome spellings (`pass`, `fail`, `approved`, `changes_required`, `blocked`) consistently.
`--ref` is a repository artifact path or revision identifying supporting evidence. Test/build failure
counts represent explicitly recorded failed invocations, not test-case counts. Suggested wait reasons:
`human`, `environment`, `queue`, `external`, `suspended`; custom reasons are allowed.

## Files and schema

Default store: `docs/engineering/dispatch/metrics/events/`. Override with
`--store PATH` **before** `event` or `summary` (for example when `DISPATCH_STATE_DIR` differs).
Each event is one schema-version-1 JSON file, named by a safe unique `event_id`. Complete files appear
atomically via a same-filesystem hard link; concurrent writers never append to a shared file. The
filesystem must support atomic hard links (normal local Git worktrees do). Commit event files with
related reports; preserve them unchanged. Keep generated summaries separate from the events folder.
No network calls, transcripts, environment variables, remote URLs, credentials, or tool arguments
are collected. Only explicitly supplied metadata and local Git HEAD/branch are recorded. Do not put
secrets in metadata/reasons/references. `recorded_at` is automatic UTC capture time; `at` defaults to
that observation time. `--at` accepts an explicit timezone-aware ISO timestamp only for observations
supported by evidence (including a ref); do not backfill inferred start times.

| Field | Meaning |
|---|---|
| `schema_version` | `1` |
| `event_id` | UUID by default; `--event-id` makes retries idempotent |
| `run_id`, `task_id`, `lane_id` | Safe identifiers `[A-Za-z0-9_.-]+`; lane defaults to task |
| `type` | One event type from the table below |
| `at`, `recorded_at` | Observation and capture timestamps, both timezone-aware |
| `interval_id` | Required pair identifier for active/wait start and stop, scoped to task/lane/kind |
| `reason`, `outcome`, `ref` | Optional strings, otherwise JSON null; requirements below |
| `metadata` | Explicit JSON object; start metadata summarized as scope/model/harness/framework_revision/parent_task (unknown = null) |
| `git` | Automatically observed local `head` and `branch`, null when unavailable; evidence under test belongs in `ref` |

| Types | Requirements / interpretation |
|---|---|
| `run_start`, `run_stop` | One pair per run; stop requires outcome |
| `task_start`, `task_stop` | One pair per task per run; stop requires outcome |
| `active_start`, `active_stop` | Same `--interval` and lane/task for pair |
| `wait_start`, `wait_stop` | Same pair; start also requires `--reason` |
| `attempt`, `correction` | Explicit attempt and rework episode counts |
| `review` | Requires outcome; verdict counts remain distinct from corrections |
| `test_failure`, `build_failure`, `environment_blocker` | Explicit failure/blocker counts; reason/ref encouraged |
| `ai_verification`, `human_qa` | Require outcome; counted separately, never inferred from each other |
| `qa_escape` | Distinct escaped defect; classification in reason, evidence in ref |

Reusing an event ID with the same intent returns the original event (including its original timestamp
and Git observation); automatic timestamps may differ on retry. Changing its intent, or an explicitly
supplied timestamp, fails instead of overwriting. Summary rejects malformed events, conflicting IDs,
duplicate starts/stops, missing starts, reversed intervals, and events outside a closed run. A retry
with a new ID is a new observation and can double-count; use stable IDs where retries are possible.

## Summaries and comparisons

```sh
python3 scripts/aef/task-metrics.py summary --run JRN-2 --format json > docs/engineering/dispatch/metrics/JRN-2.json
python3 scripts/aef/task-metrics.py summary --run JRN-2 --format markdown > docs/engineering/dispatch/metrics/JRN-2.md
```

Summaries are deterministic for the same event set; Markdown embeds the exact JSON summary. They
report run/task completion outcomes (null until stopped), run elapsed seconds (null without a complete run pair), task elapsed seconds, the union of
closed active intervals, summed per-lane active unions (effort), waiting union and waiting by reason,
and elapsed time not covered by any closed active/wait interval (unknown). Simultaneous lanes are
not summed into run elapsed time. Waiting reasons and active/wait unions may overlap across lanes,
so **do not add them** to derive elapsed time. Effort is not critical-path duration. Unclosed intervals
are listed and excluded from totals, not extended to the current clock. Closed totals in an incomplete
run are partial observations. Zero observed active time is not proof of zero work.

Counters count recorded observations only: zero never proves no retries, failures, or escapes.
Missing human results mean **human acceptance unknown**, even if AI verification passed. Group
comparisons by scope, model, harness, AEF revision, and completion milestone; lane metadata exposes
mixed configurations. Commit timestamps, historical narrative estimates, and deployment milestones
may provide elapsed-time proxies, but not active runtime. Compare similar tasks over several runs,
report coverage gaps, and do not attribute a speed change solely to AEF when models or scope changed.
No acceptance rate denominator or causal performance score is invented automatically.
