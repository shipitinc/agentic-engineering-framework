---
description: "Run one feature end-to-end through the complete autonomous engineering lifecycle — REQUIREMENT → DESIGN → DESIGN REVIEW → IMPLEMENTATION → CODE REVIEW → AUTOMATED QA → HUMAN QA → MERGE → STAGING → PRODUCTION APPROVAL → DEPLOYMENT → PRODUCTION VALIDATION — acting as the Engineering Manager / Orchestrator that dispatches every specialist lane. Use when the human explicitly asks to run, start, or drive a feature through the full lifecycle; this is the human entry point, so it is never auto-invoked."
argument-hint: "[feature description]"
disable-model-invocation: true
---

Load the `aef-run-feature` skill from `.agents/skills/aef-run-feature/SKILL.md` and execute it end to end
as the Engineering Manager / Orchestrator for this repository. Follow the skill exactly
as written: it defines the phase list, the routing rules, the structured `RESULT:`
tokens, and the terminal Manager report vocabulary. Do not summarise, reorder, or skip
any part of it, and do not ask the human for routine workflow transitions.

This command and `.claude/skills/aef-run-feature/SKILL.md` are an intentional
**alias of the same workflow**, not two copies of it: Claude Code treats `commands/` and
`skills/` as one feature, so the workflow is exposed as both `/run-feature` and
`/aef-run-feature`. Both are generated from the one canonical
`.agents/skills/aef-run-feature/SKILL.md` and both resolve to the same skill body, so
there is no name collision and no startup conflict. Invoke whichever you prefer.

FEATURE (verbatim from $ARGUMENTS):

$ARGUMENTS
