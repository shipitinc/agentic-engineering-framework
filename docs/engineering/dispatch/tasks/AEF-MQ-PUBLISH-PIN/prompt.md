MANAGER: root
TASK_ID: AEF-MQ-PUBLISH-PIN
TASK_TYPE: implement
FEATURE: Bind distributed CLI to published source
AREA: release metadata
WORKTREE: /workspace/scratch/2c5d5034fecb/aef-publish
BRANCH: feat/published-metrics-release
BASE_SHA: 4a9d0ed
OWNED_PATHS: [cli/lib/src/version.dart, cli/lib/src/commands.dart, ../aef/docs/engineering/dispatch/tasks/AEF-MQ-PUBLISH-PIN/report.md]
READ_ONLY_PATHS: [all other source]
PROHIBITED_PATHS: [other production paths, lifecycle state]
ROUTING_CLASS: STANDARD
ACCEPTANCE_CRITERIA: Replace newly added local source68c2d8a70edf21dcbc7093c4dedb649769d3e56f with published sourcea1e082c96f337a31053bc73696c417298aa34bef in embedded revision and knownHashes entry. Identical content hashbe111963ae74fd5fb1e5edc3471852e50c830f6e75b9ae7fdc0b086e426ce60f. No other production change. Published source tree57f484a79ecb9c873fb2b11fa6a5b29abc6b8369 exactly matches local4a9d0ed. Original full172 tests remain evidence for unchanged implementation; targeted release check and independent review for this metadata correction. Commit and report mandatory header with exact full SHAs. Normal integrity-enabled bootstrap from clean consumer cwd with FRAMEWORK_BRICK_PATH and no test mode must succeed and manifest pin published SHA; use local bare remote only, preserve transcript under report path or sibling evidence. Stop owned processes.
VALIDATION_COMMANDS: [dart format bounded2files, compute_brick_hash, normal bootstrap exact published manifest pin, git diff --check]
Original request: Retry git access on AEF (continuing authorized implementation and publication).
