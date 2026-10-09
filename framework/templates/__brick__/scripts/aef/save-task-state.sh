#!/bin/sh
# save-task-state.sh — OPTIONAL host adapter: persist the agent's task list.
#
# Reads a `todo_write`-style hook JSON event from stdin and writes
# `$AEF_STATE_DIR/task-state.md` (default `.devin/`) with `# Pending Tasks` / `# Completed Tasks` sections,
# so in-flight work survives a crash or session restart. If
# `$AEF_STATE_DIR/active-worktrees.md` exists its contents are appended so the
# worktree mapping survives alongside the task list.
#
# This is a reference adapter, not framework policy: wiring it to a host hook
# (e.g. `.devin/hooks`) is product-side. It ALWAYS exits 0 — a hook must never
# block the tool call it observes.

set -u

PROJECT_DIR="${AEF_PROJECT_DIR:-${DEVIN_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}}"
STATE_DIR="${AEF_STATE_DIR:-$PROJECT_DIR/.devin}"
STATE_FILE="$STATE_DIR/task-state.md"
WORKTREE_FILE="$STATE_DIR/active-worktrees.md"

INPUT=$(cat)

if ! command -v python3 >/dev/null 2>&1; then
  # No parser available — degrade to a no-op rather than block the tool.
  exit 0
fi

TODO_MD=$(printf '%s' "$INPUT" | python3 -c '
import sys, json, datetime

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

todos = data.get("tool_input", {}).get("todos", [])
if not todos:
    sys.exit(0)

now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

pending = []
completed = []
for t in todos:
    status = t.get("status", "pending")
    content = t.get("content", "")
    if status == "completed":
        completed.append(content)
    else:
        mark = "~" if status == "in_progress" else " "
        suffix = " **(in progress)**" if status == "in_progress" else ""
        pending.append(f"- [{mark}] {content}{suffix}")

lines = [
    "# Task State",
    "",
    f"_Last updated: {now}_",
    "",
    "# Pending Tasks",
    "",
]
lines.extend(pending or ["_(none)_"])
lines.extend(["", "# Completed Tasks", ""])
lines.extend(f"- [x] {c}" for c in completed)
lines.append("")
print("\n".join(lines))
' 2>/dev/null || true)

if [ -n "$TODO_MD" ]; then
  mkdir -p "$(dirname "$STATE_FILE")"
  if [ -f "$WORKTREE_FILE" ]; then
    printf '%s\n\n%s\n' "$TODO_MD" "$(cat "$WORKTREE_FILE")" > "$STATE_FILE"
  else
    printf '%s\n' "$TODO_MD" > "$STATE_FILE"
  fi
fi

exit 0
