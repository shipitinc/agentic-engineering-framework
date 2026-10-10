MANAGER: root
TASK_ID: AEF-MQ-PUBLISH-REVIEW
TASK_TYPE: review
FEATURE: Published source pin
AREA: independent release metadata review
WORKTREE: /workspace/scratch/2c5d5034fecb/aef-publish
BRANCH: feat/published-metrics-release
BASE_SHA: 4a9d0ed
OWNED_PATHS: [../aef/docs/engineering/dispatch/tasks/AEF-MQ-PUBLISH-REVIEW/report.md]
READ_ONLY_PATHS: [all source and published-pin implementation report]
PROHIBITED_PATHS: [all production writes, lifecycle state]
ROUTING_CLASS: STANDARD
ACCEPTANCE_CRITERIA: Review only replacement of local68c embedded source/hash key with publisheda1e082c96f337a31053bc73696c417298aa34bef. Brick hash unchangedbe111963ae74fd5fb1e5edc3471852e50c830f6e75b9ae7fdc0b086e426ce60f. Source snapshot tree57f484a79ecb9c873fb2b11fa6a5b29abc6b8369 equals local4a9d0ed. Exact subsequent commit supplied by implementer. Normal no-test-mode bootstrap must pin published source; no integrity policy weakening. No full suite duplication, prior172 tests preserve unchanged-source evidence. Report exact SHA and all mandatory header fields.
VALIDATION_COMMANDS: [diff inspection, hash equality, targeted bootstrap evidence inspection]
Original request: Retry git access on AEF (continuing authorized publication).
