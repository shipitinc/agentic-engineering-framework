MANAGER: root
TASK_ID: AEF-MQ-CWD-FIX
TASK_TYPE: correct
FEATURE: Metrics regression wrapper path stability
AREA: CLI test harness
WORKTREE: /workspace/scratch/2c5d5034fecb/aef-metrics
BRANCH: feat/task-metrics
BASE_SHA: 71acb19164350a3b3db714da52716d0fc05269f0
OWNED_PATHS: [cli/test/task_metrics_test.dart]
READ_ONLY_PATHS: [all other source]
PROHIBITED_PATHS: [other production source, workflow state]
ACCEPTANCE_CRITERIA: Correct/review new test wrapper cwd race with existing bootstrap integration process-global cwd mutation. Resolve absolute paths via package URI and explicit subprocess working directory. No brick changes. Fresh focused independent review before integration.
VALIDATION_COMMANDS: [paired dart test test/bootstrap_integration_test.dart test/task_metrics_test.dart]
ROUTING_CLASS: STANDARD
Original request: Let's add those updates and add AEF support to track task duration and other helpful stats you can consume here in the repo.

Ownership amendment: cli/test/bootstrap_integration_test.dart solely completeness expected path list/count, adding shipped script/docs (99 becomes101). Existing exact-count packaging gate retained.
