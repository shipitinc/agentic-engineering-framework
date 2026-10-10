MANAGER: root
TASK_TYPE: implement
BASE_SHA: c1476185dd3c9bcd3ba7113c0bcdd6a78c694cdc
ROUTING_CLASS: STANDARD
READ_ONLY_PATHS: [AGENTS.md, docs/engineering/STRUCTURED_RESULTS.md, .agents/]
Original request: "Let's add those updates and add AEF support to track task duration and other helpful stats you can consume here in the repo."
Read AGENTS.md and implementer profile, verify branch/HEAD before writes. Return structured report using .agents/skills/aef-orchestrator/templates/subtask-report.md with exact full HEAD, actual tests and timestamps. Commit changes. Do not update lifecycle state. Do not spawn extra agents; manager provides independent review. Stop lane processes and keep tracked worktree clean.
TASK_ID: AEF-JOURNEY
FEATURE: Real journey evidence and resource discipline
AREA: QA and orchestration guidance
WORKTREE: /workspace/scratch/2c5d5034fecb/aef-journey
BRANCH: feat/journey-evidence
OWNED_PATHS: [framework/templates/__brick__/.agents/, framework/templates/__brick__/docs/engineering/QA_GOVERNANCE.md, docs/engineering/QA_GOVERNANCE.md, framework/templates/__brick__/docs/engineering/WORKFLOW.md, docs/engineering/WORKFLOW.md, framework/templates/__brick__/docs/engineering/STRUCTURED_RESULTS.md, docs/engineering/STRUCTURED_RESULTS.md]
PROHIBITED_PATHS: [scripts/, framework/templates/__brick__/scripts/, TASK_METRICS.md, generated adapters including root .agents/, cli/, docs/engineering/WORK_STATE.md, docs/engineering/dispatch/]
ACCEPTANCE_CRITERIA:
- Tighten existing required integrated journey evidence, no new lifecycle stage/approval: uninterrupted actual UI clicks including nav, auth transition, assert postauth actual route and retained intended state, fresh logged-out start where applicable, production dependency injection/lifecycle exercised. No page.goto jumps/injected client substitutes as journey evidence; setup fixtures okay explicitly disclosed. Revision/build/environment/browser session provenance, steps/results and reset prerequisites in contract/evidence; automation pass != human acceptance.
- Operational preflight includes all API+DB ports and ownership, isolated DB fixture teardown, dedicated browser context/tab, bounded timeout and recorded stall reason, serialize heavy analyzers/builds when resource limited. Do not mandate arbitrary retries/new review loops. Keep concise and targeted existing sections/templates rather than multiplying prose.
- Integrate task telemetry pointers into canonical orchestrator and report/prompt templates; metrics are observability only, missing fields unknown/no blocking gate. Include start/end/wait/attempt/model/harness revision and QA metrics pointer, use exact interface from AEF-METRICS lane once provided. Add no invented status tokens.
- Main/brick documentation aligned; do NOT hand-edit generated outputs. Manager arranges Dart generation after source complete.
VALIDATION_COMMANDS: [git diff --check, relevant text consistency checks; generator deferred to integration lane]

Manager ownership amendment: generated root .agents/.claude/.junie/.opencode and brick .claude/.junie/.opencode are owned solely for generator execution. Dart SDK /workspace/scratch/2c5d5034fecb/tools/dart-sdk/bin; run dart pub get, generator, --check and platform_adapter_test.dart.
