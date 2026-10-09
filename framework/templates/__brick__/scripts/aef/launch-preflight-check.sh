#!/bin/sh
# launch-preflight-check.sh — OPTIONAL host adapter: pre-flight check for a
# subagent lane before dispatch.
#
# Verifies, for each requested lane:
#   1. every required tool is on PATH (--require-tool, repeatable);
#   2. the lane worktree exists, is a registered git worktree, and sits on the
#      expected branch (--worktree + --branch, paired and repeatable);
#   3. the worktree is NOT inside OS temporary space (TMPDIR / /var/folders /
#      /tmp) — ephemeral roots get reaped mid-lane;
#   4. the worktree HEAD is recorded (printed as BASE_SHA for the dispatch
#      prompt).
#
# Usage:
#   launch-preflight-check.sh --worktree <path> --branch <name> \
#       [--require-tool <tool>]... [--worktree <path> --branch <name>]...
#
# Exits non-zero and prints the failing check when any lane is not launchable.
# This script never creates or mutates anything — it is a check, not a setup
# tool.

set -u

PROG=$(basename "$0")
REPO="${DEVIN_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"

WT_PATHS=""
WT_BRANCHES=""
TOOLS=""
NL='
'

usage() {
  echo "usage: $PROG --worktree <path> --branch <name> [--require-tool <tool>]... [--worktree ... --branch ...]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --worktree)
      [ $# -ge 2 ] || { usage; exit 2; }
      WT_PATHS="${WT_PATHS}${2}${NL}"
      shift 2
      ;;
    --branch)
      [ $# -ge 2 ] || { usage; exit 2; }
      WT_BRANCHES="${WT_BRANCHES}${2}${NL}"
      shift 2
      ;;
    --require-tool)
      [ $# -ge 2 ] || { usage; exit 2; }
      TOOLS="${TOOLS}${2}${NL}"
      shift 2
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

N_WT=$(printf '%s' "$WT_PATHS" | grep -c . || true)
N_BR=$(printf '%s' "$WT_BRANCHES" | grep -c . || true)

if [ "$N_WT" -eq 0 ]; then
  echo "ERROR: no lanes specified — pass at least one --worktree/--branch pair" >&2
  exit 2
fi
if [ "$N_WT" -ne "$N_BR" ]; then
  echo "ERROR: every --worktree needs a matching --branch ($N_WT worktrees vs $N_BR branches)" >&2
  exit 2
fi

FAILED=0

# --- required tools ----------------------------------------------------------

if printf '%s' "$TOOLS" | grep -q .; then
  echo "--- Required tools ---"
  # shellcheck disable=SC2086 # intentional word splitting on the newline list
  for tool in $TOOLS; do
    if command -v "$tool" >/dev/null 2>&1; then
      echo "OK: $tool"
    else
      echo "MISSING: $tool" >&2
      FAILED=1
    fi
  done
fi

# --- per-lane worktree checks -------------------------------------------------

echo "--- Lane worktrees ---"

i=1
while [ "$i" -le "$N_WT" ]; do
  wt=$(printf '%s' "$WT_PATHS" | sed -n "${i}p")
  br=$(printf '%s' "$WT_BRANCHES" | sed -n "${i}p")
  i=$((i + 1))

  echo "lane: $wt (branch $br)"

  # (a) worktree directory exists
  if [ ! -d "$wt" ]; then
    echo "ERROR: worktree path does not exist: $wt" >&2
    FAILED=1
    continue
  fi

  # (b) not inside OS temporary space. Match $TMPDIR (when set) plus the
  # well-known temp roots literally — a temp-rooted worktree can be reaped
  # mid-lane, which is exactly the failure this check exists to refuse.
  in_temp=0
  if [ -n "${TMPDIR:-}" ]; then
    case "$wt" in "${TMPDIR%/}"/*) in_temp=1 ;; esac
  fi
  case "$wt" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*|/var/tmp/*|/private/var/tmp/*)
      in_temp=1 ;;
  esac
  if [ "$in_temp" -eq 1 ]; then
    echo "ERROR: worktree is inside OS temporary space ($wt) — temp roots are" >&2
    echo "       reaped mid-lane; create lane worktrees under the durable" >&2
    echo "       LANE_WORKTREE_ROOT instead" >&2
    FAILED=1
  fi

  # (c) registered git worktree
  if ! git -C "$REPO" worktree list --porcelain 2>/dev/null | grep -q "^worktree $wt\$"; then
    echo "ERROR: $wt is not a registered git worktree of $REPO" >&2
    FAILED=1
    continue
  fi

  # (d) on the expected branch
  actual=$(git -C "$wt" branch --show-current 2>/dev/null || echo "")
  if [ "$actual" != "$br" ]; then
    echo "ERROR: $wt is on branch '${actual:-DETACHED}', expected '$br'" >&2
    FAILED=1
    continue
  fi

  # (e) record the HEAD the dispatch must pin as BASE_SHA
  head_sha=$(git -C "$wt" rev-parse HEAD 2>/dev/null || echo "UNKNOWN")
  echo "OK: $wt on $br — BASE_SHA $head_sha"
done

if [ "$FAILED" -ne 0 ]; then
  echo "PRE-FLIGHT FAILED — do not dispatch the lane(s) above" >&2
  exit 1
fi

echo "PRE-FLIGHT PASSED"
exit 0
