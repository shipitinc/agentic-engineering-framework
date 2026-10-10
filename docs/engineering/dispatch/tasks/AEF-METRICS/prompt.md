MANAGER: root
TASK_TYPE: implement
BASE_SHA: c1476185dd3c9bcd3ba7113c0bcdd6a78c694cdc
ROUTING_CLASS: STANDARD
READ_ONLY_PATHS: [AGENTS.md, docs/engineering/STRUCTURED_RESULTS.md, .agents/]
Original request: "Let's add those updates and add AEF support to track task duration and other helpful stats you can consume here in the repo."
Read AGENTS.md and implementer profile, verify branch/HEAD before writes. Return structured report using .agents/skills/aef-orchestrator/templates/subtask-report.md with exact full HEAD, actual tests and timestamps. Commit changes. Do not update lifecycle state. Do not spawn extra agents; manager provides independent review. Stop lane processes and keep tracked worktree clean.
TASK_ID: AEF-METRICS
FEATURE: Portable repository task metrics
AREA: task telemetry
WORKTREE: /workspace/scratch/2c5d5034fecb/aef-metrics
BRANCH: feat/task-metrics
OWNED_PATHS: [framework/templates/__brick__/scripts/aef/task-metrics.py, framework/templates/__brick__/scripts/aef/README.md, framework/templates/__brick__/docs/engineering/TASK_METRICS.md, docs/engineering/TASK_METRICS.md, cli/test/task_metrics_test.dart, cli/test/fixtures/task_metrics/]
PROHIBITED_PATHS: [all other production paths, generated adapters, docs/engineering/WORK_STATE.md, docs/engineering/dispatch/]
ACCEPTANCE_CRITERIA:
- Ship lightweight Python3 stdlib CLI (existing scripts already use Python), optional observability not approval gate. Machine-readable immutable timestamped events and reproducible JSON+Markdown summary in consuming repo. Concurrency safe event files and no lost parallel writes. No network or secret/transcript collection.
- Record task/run IDs, parent/run scope, model/harness/framework revision, git provenance, start/stop/paused/wait/resume and outcome; count attempts, review verdicts/corrections, test/build failures, environment blockers, human QA results and escapes where explicitly recorded. Keep unknown fields explicit. No inference of active time from commits; observed intervals only, separate total wall elapsed, active interval union and lane-effort sum, waiting by reason and unknown. Distinguish AI verification from human acceptance. Avoid claiming causal performance improvements from mixed models/scope.
- Document copy/paste commands and event schema for humans/agents including adoption via existing CLI upgrade (no new CLI subcommand needed); dependency python3; bounded overhead. CLI usable by orchestration policy via start/event/summary or your coherent chosen interface. Notify other lane and manager immediately with exact final commands/schema before docs integrate.
- Deterministic adversarial tests for parallel overlap, pauses/unclosed intervals, invalid timestamps/events, duplicates/idempotency, rework/QA counters, fresh bootstrap script availability. Use Dart test wrapper to run Python unittest fixture if appropriate; no external Python packages. Coordinate any test path expansions with manager.
VALIDATION_COMMANDS: [python3 script help and smoke run, python3 unittest if implemented, dart test test/task_metrics_test.dart when SDK available]

Manager ownership amendment: .github/workflows/ci.yml owned solely to include new metrics regression suite in existing CI explicit test list, with Python setup if required.
