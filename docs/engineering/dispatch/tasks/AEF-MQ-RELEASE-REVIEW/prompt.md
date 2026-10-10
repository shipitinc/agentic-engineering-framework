MANAGER: root
TASK_ID: AEF-MQ-RELEASE-REVIEW
TASK_TYPE: review
FEATURE: Metrics template revision registration
AREA: release metadata
WORKTREE: /workspace/scratch/2c5d5034fecb/aef-journey
BRANCH: feat/metrics-release
BASE_SHA: 68c2d8a70edf21dcbc7093c4dedb649769d3e56f
OWNED_PATHS: [report.md]
READ_ONLY_PATHS: [entire repository]
PROHIBITED_PATHS: [all source, lifecycle state]
ROUTING_CLASS: STANDARD
ACCEPTANCE_CRITERIA: Independent two-file release metadata diff review at07df511c985e3e476a9bfbf59e3ac59a78ccd417; verify embedded68c and hashbe111963ae74fd5fb1e5edc3471852e50c830f6e75b9ae7fdc0b086e426ce60f correct, no weakened integrity policy.
VALIDATION_COMMANDS: [source diff review, brick hash comparison]
Original request: Let's add those updates and add AEF support to track task duration and other helpful stats you can consume here in the repo.
