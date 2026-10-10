MANAGER: root
TASK_ID: AEF-MQ-IMPL-REVIEW
TASK_TYPE: review
FEATURE: Metrics and journey implementation
AREA: Independent production review
WORKTREE: /workspace/scratch/2c5d5034fecb/aef-journey
BRANCH: feat/journey-evidence
BASE_SHA: c1476185dd3c9bcd3ba7113c0bcdd6a78c694cdc
OWNED_PATHS: [../aef/docs/engineering/dispatch/tasks/AEF-MQ-IMPL-REVIEW/report.md]
READ_ONLY_PATHS: [aef-journey, aef-metrics, frozen aef-qa contract]
PROHIBITED_PATHS: [all production source, lifecycle state]
ROUTING_CLASS: STANDARD
ACCEPTANCE_CRITERIA: Independent review of journey HEAD 2f3612e68f19ca449e40af95d896cf30d21077ec and metrics HEAD supplied when committed. Check metrics correctness, doc/interface agreement and frozen contract criteria. Focus material defects; no extra scope/review gates. Exact reviewed SHAs in report; combined QA happens after approval and integration.
VALIDATION_COMMANDS: [focused Python metrics tests, git diff --check, document review]
Original user request: Let's add those updates and add AEF support to track task duration and other helpful stats you can consume here in the repo.
