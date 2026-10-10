MANAGER: root
TASK_ID: AEF-MQ-QA
TASK_TYPE: qa-execute
FEATURE: Task metrics and journey evidence
AREA: Real CLI consumer journey
WORKTREE: /workspace/scratch/2c5d5034fecb/aef
BRANCH: feat/aef-task-metrics-journey
BASE_SHA: c1476185dd3c9bcd3ba7113c0bcdd6a78c694cdc
OWNED_PATHS: [docs/engineering/dispatch/evidence/AEF-MQ/qa-result.md, docs/engineering/dispatch/evidence/AEF-MQ/cli-journey/, docs/engineering/dispatch/tasks/AEF-MQ-QA/report.md]
READ_ONLY_PATHS: [all implementation, frozen qa-contract.md]
PROHIBITED_PATHS: [production source, baselines, lifecycle state]
ROUTING_CLASS: STANDARD
ACCEPTANCE_CRITERIA: Execute frozen contract CLI journey against integrated candidate 68c2d8a (resolve full SHA). Repo-specific instructions require QA architect distinct; you are executor. Manager is running full dart test session52460 and will supply result, do NOT duplicate. Run analyzer and drift AFTER full suite ends (coordinate); focus real consumer fixture now. Use scratch only for fixture script/repositories. Validate bootstrap installs script/docs, record events through shipped script in consuming repo, concurrent lanes+wait/resume+failure/correction+AI/Human QA distinct synthetic outcomes, deterministic summaries compared to events, then actual upgrade preserves product-owned file/events. Prior source a7e1aa3 has same brick with metrics and can bootstrap at that revision; target68c2d8a upgrades to newer revision. Also old c147618 bootstrap+upgrade shows new script/doc installed in existing product. Local bare delivery remote only, no external changes; Framework CLI upgrade expects --target revision from product cwd with FRAMEWORK_REPO_PATH set source repo. Existing aef-baseline at c147618 and Dart dependencies available offline. Exact tools commands/report evidence, event files synthetic clearly labeled. No fixture sleeps needed. No approval or production deployment. Stop owned processes; report all evidence rows with target revision. Follow qa-executor profile. No subdelegation. Avoid busy progress checks.
VALIDATION_COMMANDS: [actual bootstrap event summary upgrade lifecycle, dart analyze after Manager full test completes, generator --check, git diff --check]
Dart SDK: /workspace/scratch/2c5d5034fecb/tools/dart-sdk/bin prepend PATH; dart pub get --offline works.
Original user request: Let's add those updates and add AEF support to track task duration and other helpful stats you can consume here in the repo.
