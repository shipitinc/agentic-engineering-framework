# scripts/aef/ — optional host adapters

These scripts are **optional reference adapters** shipped with the framework
brick. Canonical AEF policy (`AGENTS.md`, `docs/engineering/WORKFLOW.md`,
`.agents/skills/aef-orchestrator`) requires **no** host hooks and persists all
Manager state as plain files under `DISPATCH_STATE_DIR`. Nothing in the
framework depends on these adapters existing or being wired.

| Script | Purpose |
|--------|---------|
| `validate-report.sh` | Mechanical admission check for a lane `report.md` before the Manager acts on it. **The one script here that is part of the shipped policy**: the orchestrator skill calls it (or its equivalent checks) before consuming a lane result. Fails closed: non-zero exit plus a named `VIOLATION:` per defect. |
| `task-metrics.py` | Optional offline task/run events and JSON/Markdown duration, rework, and QA summaries. Python 3.9+ standard library; no lifecycle authority. See [TASK_METRICS.md](../../docs/engineering/TASK_METRICS.md). |
| `save-task-state.sh` | Reads a Devin-shaped `todo_write` hook JSON event from stdin and persists it to `$AEF_STATE_DIR/task-state.md` (`# Pending Tasks` / `# Completed Tasks`), preserving `active-worktrees.md` when present. Always exits 0. |
| `load-task-state.sh` | Session-start adapter: emits the persisted task state back as hook context so in-flight work survives crash/compaction. Always exits 0. |
| `check-task-state.sh` | Stop-style adapter: reports unreconciled in-progress tasks so the task list is accurate before the session ends. Always exits 0. |
| `launch-preflight-check.sh` | Parameterizable pre-flight check for a subagent lane: required tools on PATH, worktree exists and is registered, expected branch checked out, HEAD recorded, and the worktree is **not** inside OS temporary space. |

## Wiring

Hook wiring is **product-side**, and these adapters are written for the
**Devin hook family** in particular: the stdin event shape (`tool_input.todos`,
`hookSpecificOutput`, `decision: block`) and the default state directory
(`.devin/`) are Devin's. They are reference implementations — a different host
needs its event parsing adapted to its own hook payloads; override points
`AEF_PROJECT_DIR` and `AEF_STATE_DIR` cover the paths. A `.devin/hooks`
configuration may register `save-task-state.sh` as a post-tool observer,
`load-task-state.sh` at session start / post-compaction, and
`check-task-state.sh` at stop time. A host with no hook facility loses
nothing: the framework's durability guarantees come from the on-disk dispatch
state, not from these scripts.

Run any script with `sh scripts/aef/<name>.sh` — no executable bit or build
step is required.

Run metrics with `python3 scripts/aef/task-metrics.py --help`; the `sh` invocation above applies only to `.sh` adapters.
