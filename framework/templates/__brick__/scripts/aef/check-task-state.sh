#!/bin/sh
# check-task-state.sh — OPTIONAL host adapter: report persisted task state.
#
# Stop-style adapter: inspects `$AEF_STATE_DIR/task-state.md` (default `.devin/`) and, when tasks are still
# marked in progress, emits a hook event that asks the agent to reconcile the
# task list before stopping, so a crash cannot silently lose in-flight work.
# Always exits 0 — advisory only.

set -u

PROJECT_DIR="${AEF_PROJECT_DIR:-${DEVIN_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}}"
STATE_DIR="${AEF_STATE_DIR:-$PROJECT_DIR/.devin}"
STATE_FILE="$STATE_DIR/task-state.md"

[ -f "$STATE_FILE" ] || exit 0

if grep -qE '\[~\].*in progress' "$STATE_FILE"; then
  IN_PROGRESS=$(grep -E '\[~\].*in progress' "$STATE_FILE" | sed 's/\*\*(in progress)\*\*//' | sed 's/^- \[~\] //')
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$IN_PROGRESS" | python3 -c "
import json, sys
tasks = sys.stdin.read().strip()
print(json.dumps({
    'decision': 'block',
    'reason': 'You have in-progress tasks that have not been completed:\n' + tasks + '\n\nBefore stopping, either:\n1. Complete the task and update the task list, or\n2. Update the task list to reflect the current state so it can be resumed after a crash.\n\nThis ensures no work is lost if the session crashes.'
}))
"
  else
    echo "IN-PROGRESS TASKS NOT RECONCILED:" >&2
    printf '%s\n' "$IN_PROGRESS" >&2
  fi
fi

exit 0
