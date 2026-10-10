MANAGER: root
TASK_ID: AEF-MQ-CONTRACT
TASK_TYPE: qa-contract
FEATURE: Task telemetry and journey evidence improvements
AREA: QA contract
WORKTREE: /workspace/scratch/2c5d5034fecb/aef-qa
BRANCH: feat/metrics-qa
BASE_SHA: c1476185dd3c9bcd3ba7113c0bcdd6a78c694cdc
OWNED_PATHS: [docs/engineering/dispatch/evidence/AEF-MQ/qa-contract.md]
READ_ONLY_PATHS: [entire repository, ../aef/docs/engineering/dispatch/tasks/AEF-METRICS/prompt.md, ../aef/docs/engineering/dispatch/tasks/AEF-JOURNEY/prompt.md]
PROHIBITED_PATHS: [production source, lifecycle state, all other paths]
ROUTING_CLASS: STANDARD
ACCEPTANCE_CRITERIA: Define concise frozen QA contract for authorized metrics and journey changes. Inspect implementation prompts for scope. Required CLI unit/adversarial tests, analyzer, adapter drift, bootstrap/upgrade availability and realistic integrated metrics command journey in disposable consuming repo. No user-facing UI in framework: explicitly determine required integrated journey evidence as CLI lifecycle journey, visual/human checks not applicable with reason. Distinguish elapsed/active/wait/unknown, failure/rework/QA counters, immutable event concurrency, no metrics approval gate. Don't expand scope or add stages. Can commit contract. Do not execute tests. Return structured QA_CONTRACT_FROZEN if supported by existing freeze authority; otherwise CREATED for Manager freeze review. Read qa-architect profile/required skills.
VALIDATION_COMMANDS: [document inspection only; no QA execution]
Original user request: Let's add those updates and add AEF support to track task duration and other helpful stats you can consume here in the repo.
