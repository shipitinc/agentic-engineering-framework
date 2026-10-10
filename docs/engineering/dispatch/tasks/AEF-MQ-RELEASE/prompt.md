MANAGER: root
TASK_ID: AEF-MQ-RELEASE
TASK_TYPE: implement
FEATURE: Register metrics brick for distributed CLI adoption
AREA: release metadata
WORKTREE: /workspace/scratch/2c5d5034fecb/aef-journey
BRANCH: feat/metrics-release
BASE_SHA: 68c2d8a70edf21dcbc7093c4dedb649769d3e56f
OWNED_PATHS: [cli/lib/src/version.dart, cli/lib/src/commands.dart, ../aef/docs/engineering/dispatch/tasks/AEF-MQ-RELEASE/report.md]
READ_ONLY_PATHS: [all other source]
PROHIBITED_PATHS: [all other production files, lifecycle state]
ROUTING_CLASS: STANDARD
ACCEPTANCE_CRITERIA: Normal existing release procedure only: set embedded revision68c2d8a70edf21dcbc7093c4dedb649769d3e56f and add knownHashes entry for brick hashbe111963ae74fd5fb1e5edc3471852e50c830f6e75b9ae7fdc0b086e426ce60f. Verify via compute_brick_hash tool. No source resolver redesign, no integrity bypass. Commit bounded2-file metadata change, exact report. Scope needed for normal non-test-mode distributed bootstrap. Final QA executor will verify no-test-mode compiled/FRAMEWORK_BRICK_PATH workflow. No duplicate full suite. Reviewer independent approval before integration.
VALIDATION_COMMANDS: [compute_brick_hash, dart format --output=none --set-exit-if-changed lib/src/version.dart lib/src/commands.dart, git diff --check]
Original request: Let's add those updates and add AEF support to track task duration and other helpful stats you can consume here in the repo.
