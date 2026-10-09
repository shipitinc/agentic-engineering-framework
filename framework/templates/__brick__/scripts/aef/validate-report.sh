#!/bin/sh
# validate-report.sh — mechanical admission check for a lane report file.
#
# Part of the agentic engineering framework (see README.md in this directory).
# The Engineering Manager runs this against <DISPATCH_STATE_DIR>/tasks/<TASK_ID>/
# report.md BEFORE acting on a lane outcome. A missing or malformed report is
# UNSCOPED input, not consent — this script never silently passes.
#
# Usage:
#   validate-report.sh <report-file> [--expect-task-type <TYPE>]
#
# Exit status:
#   0  — every check passed; prints one `VALID: ...` summary line.
#   1  — one or more violations; each printed as `VIOLATION: <name>`.
#   2  — the check itself could not run (bad invocation, missing capability).
#
# Dependencies: POSIX sh plus awk(1). There is deliberately no build step and
# no host-specific tool requirement; if awk is absent the script fails closed
# with a named violation rather than passing.

set -u

# ---------------------------------------------------------------------------
# Legal vocabulary — data, not logic.
#
# TASK_TYPES lists every legal TASK_TYPE value, in the order
# .agents/skills/aef-orchestrator/templates/subtask-report.md declares them.
# legal_result_tokens() maps each TASK_TYPE to the RESULT: tokens the emitting
# agent may use (the "RESULT: vocabulary per lane" table in the same file).
# Adding vocabulary is a one-line edit in ONE of these two places.
# ---------------------------------------------------------------------------

TASK_TYPES="design-review implement review correct re-review integrate research design-produce qa-contract qa-execute deploy"

legal_result_tokens() {
  case "$1" in
    design-review)  echo "DESIGN_REVIEW_APPROVED DESIGN_REVIEW_APPROVED_WITH_NON_BLOCKING_FINDINGS DESIGN_REVIEW_CHANGES_REQUIRED DESIGN_REVIEW_HUMAN_DECISION_REQUIRED" ;;
    implement)      echo "IMPLEMENTED IMPLEMENTATION_BLOCKED" ;;
    review)         echo "APPROVE_FOR_MERGE APPROVE_WITH_NON_BLOCKING_FOLLOWUP DO_NOT_MERGE" ;;
    correct)        echo "CORRECTION_COMPLETE CORRECTION_BLOCKED" ;;
    re-review)      echo "APPROVE_CORRECTIONS DO_NOT_APPROVE_CORRECTIONS" ;;
    integrate)      echo "MERGE_APPROVED INTEGRATION_BLOCKED" ;;
    # A research lane has no dedicated agent: it emits the tokens of whichever
    # agent the Manager dispatched (subtask-report.md). Admit the union of the
    # read-only agents' vocabularies so an unknown token still fails closed.
    research)       echo "DESIGN_REVIEW_APPROVED DESIGN_REVIEW_APPROVED_WITH_NON_BLOCKING_FINDINGS DESIGN_REVIEW_CHANGES_REQUIRED DESIGN_REVIEW_HUMAN_DECISION_REQUIRED APPROVE_FOR_MERGE APPROVE_WITH_NON_BLOCKING_FOLLOWUP DO_NOT_MERGE APPROVE_CORRECTIONS DO_NOT_APPROVE_CORRECTIONS" ;;
    design-produce) echo "DESIGN_REVISION_COMPLETE DESIGN_REVISION_BLOCKED" ;;
    qa-contract)    echo "QA_CONTRACT_CREATED QA_CONTRACT_FROZEN QA_CONTRACT_BLOCKED" ;;
    qa-execute)     echo "QA_RESULT_PASS QA_RESULT_FAIL QA_RESULT_PARTIAL QA_RESULT_BLOCKED" ;;
    deploy)         echo "DEPLOYMENT_SUCCESSFUL DEPLOYMENT_FAILED DEPLOYMENT_ROLLED_BACK DEPLOYMENT_PARTIAL" ;;
    *)              echo "" ;;
  esac
}

# Mandatory header keys per subtask-report.md "Mandatory header".
MANDATORY_KEYS="RESULT TASK_ID TASK_TYPE FEATURE WORKTREE BRANCH BASE_SHA HEAD_SHA COMMITTED"

usage() {
  echo "usage: $0 <report-file> [--expect-task-type <TYPE>]" >&2
}

# --- capability check (fail closed) ------------------------------------------

if ! command -v awk >/dev/null 2>&1; then
  echo "VIOLATION: MISSING_CAPABILITY awk — report validation cannot run" >&2
  exit 2
fi

# --- argument parsing ---------------------------------------------------------

REPORT=""
EXPECT_TYPE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --expect-task-type)
      if [ $# -lt 2 ]; then
        echo "VIOLATION: BAD_USAGE --expect-task-type requires a value" >&2
        exit 2
      fi
      EXPECT_TYPE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "VIOLATION: BAD_USAGE unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [ -z "$REPORT" ]; then
        REPORT="$1"
      else
        echo "VIOLATION: BAD_USAGE unexpected argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$REPORT" ]; then
  usage
  exit 2
fi

# --- (a) file exists and is non-empty ----------------------------------------

VIOLATIONS=""
add_violation() {
  VIOLATIONS="${VIOLATIONS}
$1"
}

if [ ! -f "$REPORT" ]; then
  echo "VIOLATION: REPORT_MISSING $REPORT" >&2
  exit 1
fi
if [ ! -s "$REPORT" ]; then
  echo "VIOLATION: REPORT_EMPTY $REPORT" >&2
  exit 1
fi

# --- (b)+(c) locate the header block and extract KEY: value pairs ------------
#
# A report's mandatory header may appear as (first match wins):
#   1. a ```yaml / ```yml fenced block,
#   2. a --- YAML front-matter block, or
#   3. a contiguous run of bare `KEY: value` lines (blank lines, `#` comment
#      lines, and markdown headings are skippable while seeking).
# Keys are emitted as `KEY<TAB>value`; the sentinel `@NO_BLOCK@` is emitted
# when no header block is found at all.

PAIRS=$(
  awk '
    function emit(line,   i, k, v) {
      i = index(line, ":")
      k = substr(line, 1, i - 1)
      v = substr(line, i + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      sub(/^[ \t]+/, "", v)
      sub(/[ \t]+#.*$/, "", v)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (length(v) >= 2 && substr(v, 1, 1) == "\"" && substr(v, length(v), 1) == "\"") {
        v = substr(v, 2, length(v) - 2)
      } else if (length(v) >= 2 && substr(v, 1, 1) == "\'"'"'" && substr(v, length(v), 1) == "\'"'"'") {
        v = substr(v, 2, length(v) - 2)
      }
      print k "\t" v
    }
    {
      line = $0
      if (mode == 0) {
        if (line ~ /^[ \t]*$/ || line ~ /^#/) next
        if (line ~ /^```[ \t]*(yaml|yml)?[ \t]*$/) { mode = 1; next }
        if (line ~ /^---[ \t]*$/)                  { mode = 2; next }
        if (line ~ /^[A-Z_][A-Z0-9_]*[ \t]*:/)       mode = 3
        else                                       next
      }
      if (mode == 1) {
        if (line ~ /^```/) { mode = 9; next }
        if (line ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*:/) emit(line)
        next
      }
      if (mode == 2) {
        if (line ~ /^---[ \t]*$/) { mode = 9; next }
        if (line ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*:/) emit(line)
        next
      }
      if (mode == 3) {
        if (line ~ /^[A-Z_][A-Z0-9_]*[ \t]*:/) { emit(line); next }
        if (line ~ /^[ \t]/ || line ~ /^[ \t]*$/ || line ~ /^#/) next
        mode = 9
      }
    }
    END {
      if (mode == 0) print "@NO_BLOCK@\t"
    }
  ' "$REPORT"
)

if [ "$PAIRS" = "@NO_BLOCK@	" ] || printf '%s' "$PAIRS" | grep -q '^@NO_BLOCK@'; then
  add_violation "NO_HEADER_BLOCK — no YAML front-matter or KEY: header block found"
fi

TAB=$(printf '\t')
RESULT="" TASK_ID="" TASK_TYPE="" FEATURE="" WORKTREE=""
BRANCH="" BASE_SHA="" HEAD_SHA="" COMMITTED=""

# shellcheck disable=SC2034  # FEATURE/TASK_ID etc. are collected for completeness
while IFS="$TAB" read -r key value; do
  case "$key" in
    RESULT)    RESULT="$value" ;;
    TASK_ID)   TASK_ID="$value" ;;
    TASK_TYPE) TASK_TYPE="$value" ;;
    FEATURE)   FEATURE="$value" ;;
    WORKTREE)  WORKTREE="$value" ;;
    BRANCH)    BRANCH="$value" ;;
    BASE_SHA)  BASE_SHA="$value" ;;
    HEAD_SHA)  HEAD_SHA="$value" ;;
    COMMITTED) COMMITTED="$value" ;;
  esac
done <<PAIRS_EOF
$PAIRS
PAIRS_EOF

for key in $MANDATORY_KEYS; do
  eval "val=\${$key:-}"
  if [ -z "$val" ]; then
    add_violation "MISSING_MANDATORY_KEY $key"
  fi
done

# --- (d) TASK_TYPE is a member of the legal enum ------------------------------

task_type_known=0
case " $TASK_TYPES " in
  *" $TASK_TYPE "*) task_type_known=1 ;;
esac
if [ -n "$TASK_TYPE" ] && [ "$task_type_known" -eq 0 ]; then
  add_violation "ILLEGAL_TASK_TYPE $TASK_TYPE"
fi

# --- (e) RESULT is legal for that TASK_TYPE -----------------------------------

if [ "$task_type_known" -eq 1 ] && [ -n "$RESULT" ]; then
  tokens=$(legal_result_tokens "$TASK_TYPE")
  case " $tokens " in
    *" $RESULT "*) : ;;
    *) add_violation "ILLEGAL_RESULT_FOR_TASK_TYPE $RESULT (TASK_TYPE=$TASK_TYPE)" ;;
  esac
fi

# --- (f) optional expected task type ------------------------------------------

if [ -n "$EXPECT_TYPE" ] && [ -n "$TASK_TYPE" ] && [ "$TASK_TYPE" != "$EXPECT_TYPE" ]; then
  add_violation "TASK_TYPE_MISMATCH expected=$EXPECT_TYPE actual=$TASK_TYPE"
fi

# --- verdict ------------------------------------------------------------------

if [ -n "$VIOLATIONS" ]; then
  printf '%s\n' "$VIOLATIONS" | while IFS= read -r line; do
    [ -n "$line" ] && echo "VIOLATION: $line" >&2
  done
  exit 1
fi

echo "VALID: $REPORT TASK_TYPE=$TASK_TYPE RESULT=$RESULT"
exit 0
