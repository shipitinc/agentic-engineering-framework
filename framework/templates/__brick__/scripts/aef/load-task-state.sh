#!/bin/sh
# load-task-state.sh — OPTIONAL host adapter: restore persisted task state.
#
# SessionStart / post-compaction adapter: reads `.devin/task-state.md` and, when
# in-flight work is present, emits a host hook event carrying the saved state so
# the agent can resume it. Without python3 the state is printed verbatim (still
# useful as plain context). Always exits 0 — advisory only.

set -u

PROJECT_DIR="${DEVIN_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
STATE_FILE="$PROJECT_DIR/.devin/task-state.md"

[ -f "$STATE_FILE" ] || exit 0

CONTENT=$(cat "$STATE_FILE")

# Nothing in flight? Stay silent.
if ! printf '%s' "$CONTENT" | grep -qE '\[~\]|\[ \]|WT_MAP_START'; then
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$CONTENT" | python3 -c "
import json, sys
content = sys.stdin.read()
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': '## Task Recovery - In-Flight Work Detected\n\nThe following task state was saved from a previous session (possibly due to a crash or compaction). Review it and resume any in-progress work immediately:\n\n' + content + '\n\n## Recovery rules\n\n1. If any task was marked **in progress**, resume that task first.\n2. If a worktree mapping section is present, check each listed worktree:\n   - Run \`git -C <path> status --short\` for uncommitted changes.\n   - Run \`git -C <path> log --oneline <base>..<branch>\` for commits.\n   - Do NOT re-do work that was already committed.\n3. If a worktree has no commits and no uncommitted changes, the lane did\n   not complete its work — re-dispatch it.\n4. If a worktree has uncommitted changes, review them before continuing.\n5. Before launching ANY new lane, run scripts/aef/launch-preflight-check.sh\n   to verify worktree isolation and required tooling.'
    }
}))
"
else
  printf '%s\n' "$CONTENT"
fi

exit 0
