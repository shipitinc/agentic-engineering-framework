---
name: correction-loop
description: Procedure for the correction and focused re-review cycle in this framework — consume concrete reviewer findings, make focused corrections that preserve reviewed provenance, and trigger a fresh focused re-review with no self-approval. Use when addressing DO_NOT_MERGE findings or re-reviewing corrections.
---

# Correction loop

Use this skill when a change failed independent review (`DO_NOT_MERGE`) and must be corrected, and
when re-reviewing those corrections. It keeps the loop honest and bounded.

## Consume findings

- Take the concrete blockers/high/medium findings exactly as reported by the reviewer.
- Do not reinterpret away a blocker; if you disagree, surface it explicitly rather than ignoring it.
- Do not expand scope: address the findings, not unrelated code.

## Focused correction

- Correct from the exact reviewed HEAD; record `CORRECTED_FROM_HEAD` and the produced `NEW_HEAD`.
- Create a new corrected state — never pretend the prior review did not happen or rewrite it away.
- Re-run all applicable required gates; they must genuinely pass (never weaken/skip tests).

## Fresh re-review

- A correction is **never** self-approved. After `CORRECTION_COMPLETE`, a fresh **focused** review
  must run against the corrected HEAD.
- The focused re-review covers the corrected findings plus regression risk from the corrections.

## Bounded loop (anti-thrash)

- Do not loop indefinitely. After **two** failed correction/re-review cycles on the same substantive
  issue:
  - classify the repeated failure (workflow / tooling / architecture blocker?);
  - escalate only if it is genuinely `HUMAN_DECISION_REQUIRED` or an unrecoverable blocker;
  - otherwise report the impasse with evidence rather than silently retrying.
