---
name: aef-orchestrator
description: Manager-session orchestration procedure — decompose work, dispatch to isolated specialist sessions with declared path ownership and full provenance, collect structured results, gate integration on independent review, escalate only genuine human decisions. Use when running a work item end-to-end or resuming persisted state after a crash.
---

# Orchestrator

Use this skill in the **Manager** lane — the single authoritative top-level session (per
`AGENTS.md` § Inherited invariants and § Orchestration). It is the **operational
counterpart** of
those prose invariants and of `docs/engineering/WORKFLOW.md`: it states *how* the Manager dispatches
and gates work. It **adds no lifecycle stage and no human gate**; where this skill and
`WORKFLOW.md`/`AGENTS.md` disagree, those documents win.

Objective: **maximum safe throughput with deterministic provenance.** Prefer serial prerequisites
followed by parallel independent work over speculative parallel coding.

The Manager is an **orchestrator, not a production implementer**.

## 1. Coordinator responsibilities

The Manager MUST:

- own workflow state (`docs/engineering/WORK_STATE.md` is the Manager's file; no other agent
  writes it);
- decompose a request into bounded subtasks of type
  `design-review | implement | review | correct | re-review | integrate | research | design-produce |
  qa-contract | qa-execute | deploy`;
- declare path ownership and verify non-overlap **before** launching writers;
- dispatch to isolated specialist subagent sessions using the dispatch contract (§4);
- monitor children, send corrections/clarifications, and terminate or park off-scope children;
- parse and validate each child's structured result before advancing any state;
- enforce runtime/test/design/QA/deployment gates;
- integrate **only** independently approved work;
- escalate genuine human decisions per §13.

The Manager MUST NOT: use the human as a message relay between lanes, advance state on invalid or
unparsed results, or treat a child's optimistic report as permission to skip a gate.

## 2. Authorized self-edits (the orchestrator-not-implementer escape hatch)

The Manager may perform these small mechanical edits itself, without dispatching a lane:

- **Repository metadata:** `README*`, `LICENSE*`, `.gitignore`, `.gitattributes`, `.editorconfig`.
- **Workflow bookkeeping:** files under the declared state directory (§3),
  `docs/engineering/WORK_STATE.md`, Human Decision objects under the declared decision directory,
  and lane task-state files.
- **Mechanical config fixes to an already-declared gate:** a change that makes an existing declared
  validation command pass with **no behavior change** (e.g. a formatting-only fix reported by a
  declared gate).
- **Documentation that only restates an already-recorded decision** (no new claims).

Everything else — any production source, test, schema, or dependency change — MUST be
dispatched. Record every self-edit in the ledger (§15) with the reason it was in the list above.

**The escape hatch never grants self-approval.** A Manager self-edit to production source is not
exempt from independent review; if the Manager makes one anyway, it must still pass §9 before
integration.

## 3. Project-declared conventions (placeholders)

Every mechanism below is a convention. A consuming project sets the values in **its own `AGENTS.md`
§ Orchestration**. If the project declares a value, **it wins** over the default. If the project
declares none, the Manager MUST use the default **and record the defaults it used in the ledger
before the first dispatch**. If a required convention is absent and has no safe default, raise
`HUMAN_DECISION_REQUIRED` (type `OTHER_CONSEQUENTIAL`).

| Convention | Default | Purpose |
|------------|---------|---------|
| `SUBTASK_PROMPT_TEMPLATE` | `.agents/skills/aef-orchestrator/templates/subtask-prompt.md` | Dispatch prompt contract |
| `SUBTASK_REPORT_TEMPLATE` | `.agents/skills/aef-orchestrator/templates/subtask-report.md` | Structured result contract |
| `DISPATCH_STATE_DIR` | `docs/engineering/dispatch/` | Plain-file lane state (§14) |
| `DECISION_DIR` | `.decisions/` | Human Decision objects |
| `WORKFLOW_STATE` | `docs/engineering/WORK_STATE.md` | Manager-owned lifecycle ledger |
| `ISOLATION_CONVENTION` | `git worktree add -b <branch> <abs-path> <base>` | Lane isolation |
| `LANE_WORKTREE_ROOT` | `<repo-parent>/<repo-name>-wt/` (env-overridable) | Durable root under which every lane worktree is created — never OS temporary space (§4) |
| `LANE_WAIT_BUDGET` | `10 min` per bounded block | Bounded wait per dispatch block (§5) |
| `MAX_CONCURRENT_WRITERS` | `3` | Concurrent production-writing lanes |
| `ROUTING_POLICY` | **none shipped by the brick** — the brick instantiates no routing-policy file into a product repository, so a project declares its own routing policy file; where it declares none, the §12 dispatch-cost-class table applies directly | Cost-aware dispatch (§12) |

No convention above names a file that the brick does not instantiate into a product repository.

## 4. Dispatch contract

The Manager MUST NOT dispatch a production-writing lane until **all** preconditions hold:

1. A **dedicated isolated worktree** exists for the lane, created per `ISOLATION_CONVENTION` at a
   path **outside** the canonical checkout **and under `LANE_WORKTREE_ROOT`** — never inside OS
   temporary space (`/var/folders`, `$TMPDIR`, `/tmp`), where the OS can reap the worktree
   mid-lane (observed: lane worktrees deleted under a temp root while their lanes were in flight).
   The canonical checkout is the Manager's lane only.
2. The child is instructed to `cd` into the worktree and verify
   `git branch --show-current` and `git rev-parse HEAD` match `BRANCH` / `BASE_SHA` **before
   writing**.
3. Two writers never share a worktree.
4. `OWNED_PATHS` sets of all concurrent writers **do not intersect** (compare explicitly; if they
   overlap, serialize or re-partition first).
5. Running production-writing lanes ≤ `MAX_CONCURRENT_WRITERS`.
6. Every dependency listed in the prompt is already merged.

If any precondition cannot be met, the Manager MUST **stop and fix the infrastructure first**.
Running two writers in one worktree is a critical violation that causes branch collisions and lost
work.

Every dispatch prompt MUST contain the mandatory YAML header below, filled in, with **no key
omitted** (rendered from `SUBTASK_PROMPT_TEMPLATE`):

```yaml
MANAGER: <Manager session identifier>
TASK_ID: <work-item id>
TASK_TYPE: design-review | implement | review | correct | re-review | integrate | research | design-produce | qa-contract | qa-execute | deploy
FEATURE: <one-line work-item name>
AREA: <bounded area label>
WORKTREE: <absolute worktree path>
BRANCH: <branch name>
BASE_SHA: <short SHA the worktree started from>
OWNED_PATHS:
  - <files/dirs the child may edit>
READ_ONLY_PATHS:
  - <context files the child may read but not modify>
PROHIBITED_PATHS:
  - <generated code, other lanes' source, secrets>
ACCEPTANCE_CRITERIA: <inline list or path to a durable list>
VALIDATION_COMMANDS:
  - <exact commands the child must run and report>
ROUTING_CLASS: CHEAP_READ | STANDARD | PRECISION
```

Plus: the original request verbatim, references to the authoritative sources the child needs, and
the cleanup checklist. The child MUST return a report conforming to `SUBTASK_REPORT_TEMPLATE`; the
child's only outcome token is the `RESULT:` token its own agent file defines, and the Manager — not the
child — normalizes it into an envelope `status` (§7).

Every dispatch is persisted as a file before launch (see §14).

## 5. Lane naming, admission, and bounded waits

Name lanes predictably: `<TASK_TYPE> — <FEATURE>` (e.g. `implement — checkout retry`). The
`TASK_ID` plus `WORKTREE`/`BRANCH`/`BASE_SHA` make any lane auditable after the fact. Provenance is
mandatory: a child result without exact repository/worktree/HEAD provenance is **invalid** and must
be re-emitted.

### Report admission (mandatory, fail closed)

Before the Manager may act on **any** lane outcome it MUST:

1. confirm `report.md` exists on disk at `<DISPATCH_STATE_DIR>/tasks/<TASK_ID>/report.md` — the
   durable signal is the artifact on disk, never the child-session notification;
2. run `scripts/aef/validate-report.sh tasks/<TASK_ID>/report.md --expect-task-type <TASK_TYPE>`
   when the script is present in the repository, or perform the equivalent mechanical checks
   itself when it is absent — file exists and is non-empty, a YAML front-matter/header block
   exists, every mandatory key is present, `TASK_TYPE` is a legal enum member, and `RESULT` is
   legal for that `TASK_TYPE` — **fail closed either way**;
3. confirm the `RESULT` token is legal for the lane's agent per `subtask-report.md`
   § `RESULT:` vocabulary per lane.

A missing or malformed report is **`UNSCOPED`**, not consent: the Manager must not advance the
lane on it, and a session notification is not a report. Record the admission check's outcome in
the lane's Manager state (`state.json`, `LANES.md`).

### Bounded waits and cancellation recovery

Dispatch is asynchronous; the Manager waits on the **artifact**, not the child process:

- **Artifact-as-completion**: the durable completion signal is `report.md` on disk — never the
  provider's child-session notification, which can arrive early, late, or never.
- **Bounded wait**: on dispatch, wait one bounded block (default budget `LANE_WAIT_BUDGET`,
  10 minutes), then inspect `report.md`:
  - a **valid** report exists → proceed per the admission step and terminate the child session;
  - no report but the child is still active → allow **exactly one** additional bounded block;
  - still no report → re-dispatch the lane **once** in a new isolated session; if that also
    produces no report → mark the lane `BLOCKED: NO_REPORT` in `LANES.md`, park it, and surface
    it to the human.
- **Provider cancellation**: a lane cancelled at the provider produces no report; re-dispatch
  **up to once**, then park `BLOCKED: PROVIDER_CANCELLED`. A cancelled attempt is **never**
  counted as a verdict, and no Manager-side check substitutes for one.
- **Reaped worktree**: if the lane worktree path vanished (OS temp reaping), recreate it from the
  lane branch — `git worktree add` under `LANE_WORKTREE_ROOT` at the recorded `base_sha`/`head_sha`
  — and verify `HEAD` before resuming.
- **Manager-run gates are not the review gate**: any gate or check the Manager runs itself is a
  consistency check only — it is never the independent-review gate, and a cancelled or reportless
  review lane cannot be replaced by Manager verification. (Observed upstream: a correction lane
  cancelled at the provider five times, produced zero reports, and could not be advanced on
  Manager verification alone.)

## 6. Manager ledger states (bookkeeping, not lifecycle steps)

The Manager tracks each active work item explicitly and is the only writer of that ledger:

`REQUIREMENT → FOUNDATION → DESIGN_PENDING → DESIGN_REVIEWING → DESIGN_BLOCKED → DESIGN_READY →
ARCHITECTURE_BLOCKED → IMPLEMENTATION_PENDING → IMPLEMENTING → IMPLEMENTATION_BLOCKED → IMPLEMENTED →
REVIEWING → CORRECTION_REQUIRED → CORRECTING → RE_REVIEWING → QA_CONTRACT_PENDING → QA_EXECUTING →
QA_BLOCKED → READY_FOR_INTEGRATION → MERGE_APPROVED → INTEGRATING → STAGING → STAGING_VALIDATED →
DEPLOYMENT_PENDING → DEPLOYING → PRODUCTION_VALIDATED → LEARNING → MERGED` plus
`HUMAN_DECISION_REQUIRED` (reachable from any state).

**These names are Manager ledger bookkeeping states — not lifecycle steps, not gates, and not workflow
authority.** `docs/engineering/WORKFLOW.md`'s numbered steps are authoritative for every gate and for
ordering, exactly as §13's `G1`–`G5` ids are project-local shorthand. A ledger state authorizes nothing:
a work item advances only when a `WORKFLOW.md` step's gate has passed on a **parsed** structured result
per `docs/engineering/STRUCTURED_RESULTS.md` — never by conversational prose.

Mapping to the authoritative vocabulary (no name below adds authority; each points at the contract that
already governs it):

| Ledger state(s) | Authoritative counterpart |
|-----------------|---------------------------|
| `DESIGN_PENDING`, `DESIGN_REVIEWING`, `DESIGN_BLOCKED`, `DESIGN_READY` | `DESIGN_REVISION` / `DESIGN_REVIEW` results; gates D1–D5 in `DESIGN_GOVERNANCE.md` |
| `IMPLEMENTATION_PENDING`, `IMPLEMENTING`, `IMPLEMENTATION_BLOCKED`, `IMPLEMENTED` | `IMPLEMENTATION_RESULT`; lane `RESULT:` tokens `IMPLEMENTED` / `IMPLEMENTATION_BLOCKED` (`.agents/agents/implementer.md`) → envelope `status: COMPLETE` / `BLOCKED` |
| `REVIEWING`, `CORRECTION_REQUIRED`, `CORRECTING`, `RE_REVIEWING` | `ENGINEERING_REVIEW` results and the `aef-correction-loop` skill; lane `RESULT: DO_NOT_MERGE` (`.agents/agents/engineering-reviewer.md`) → envelope `status: CHANGES_REQUIRED`, and `RESULT: DO_NOT_APPROVE_CORRECTIONS` (`.agents/agents/focused-reviewer.md`) → `CHANGES_REQUIRED` |
| `READY_FOR_INTEGRATION`, `MERGE_APPROVED`, `INTEGRATING` | `INTEGRATION_READINESS`; lane `RESULT: MERGE_APPROVED \| INTEGRATION_BLOCKED` (`.agents/agents/integrator.md`) |
| `QA_CONTRACT_PENDING`, `QA_EXECUTING`, `QA_BLOCKED` | `QA_CONTRACT` / `QA_RESULT` results and `QA_GOVERNANCE.md` gates |
| `STAGING`, `STAGING_VALIDATED`, `DEPLOYMENT_PENDING`, `DEPLOYING`, `PRODUCTION_VALIDATED` | `DEPLOYMENT_REQUEST` / `DEPLOYMENT_RESULT` / `PRODUCTION_VALIDATION` results and `DEPLOYMENT_GOVERNANCE.md` |
| `REQUIREMENT`, `FOUNDATION`, `ARCHITECTURE_BLOCKED`, `LEARNING`, `MERGED` | no result type of their own — Manager bookkeeping only; `FOUNDATION` closes with an ADR, `LEARNING` persists per `LEARNING_POLICY.md` |
| `HUMAN_DECISION_REQUIRED` | `HUMAN_DECISION` result type and the `HUMAN_DECISIONS.md` state machine |

Selected report and ledger **fields** that are not envelope statuses and are **not** `next_actions`
(the ones with a non-obvious mapping; also defined in `.agents/skills/aef-orchestrator/templates/subtask-report.md`; they are
fields, never new lifecycle states or enum members):

| Field | Where it is canonical | Mapping to the authoritative vocabulary |
|-------|-----------------------|----------------------------------------|
| `CHEAP_READ` / `STANDARD` / `PRECISION` | §12 dispatch-cost-class table; reported as `routing_class` (`ORCHESTRATION_RESULT.lanes_dispatched[].routing_class`) and `ROUTING_CLASS_REQUESTED` | Manager-declared, non-gating execution policy — changes no gate or approval |
| `READY_FOR_FOCUSED_REVIEW` | `.agents/agents/correction-implementer.md` report field — an **agent field**, not a `RESULT:` token and not an envelope member | "the corrected HEAD needs a fresh `focused-reviewer` dispatch" → the lane's recommended next action `FOCUSED_RE_REVIEW` → envelope `next_actions: FOCUSED_RE_REVIEW` |
| clarification requests | a child reports the ambiguity under **Unresolved issues** using **its own blocked `RESULT:` token** (e.g. `IMPLEMENTATION_BLOCKED`, `CORRECTION_BLOCKED`) — there is no clarification token of its own | envelope `status: BLOCKED`, plus `blockers[].type: HUMAN_DECISION_REQUIRED` only when the clarification is a consequential human decision |

**Recommended next action (report field) → envelope `next_actions`.** Every value a lane may report is
already a real `next_actions` member of that `result_type` in `docs/engineering/STRUCTURED_RESULTS.md`,
and the Manager copies it **verbatim** — a lane never names a value the contract does not declare, and
the Manager never invents one. The authoritative per-lane list is `subtask-report.md`
§ Recommended next action. Two values earlier drafts of the report template offered are **not** report
values and are dropped: `RETRY_WITH_PRECISION` (raising the routing class is a **Manager dispatch
decision**, recorded in the ledger per §12/§ 15, not a lane recommendation) and `NO_ACTION` (no such
member exists; a terminal Manager lane reports `PARK`).

## 7. Phase delegation map (reuse the existing lanes and skills)

| Workflow phase | Manager action | Lane | Skill | Consumes | Gate before advancing |
|----------------|----------------|------|-------|----------|-----------------------|
| Foundation | research → recommendation → ADR | Manager (self) + `research` lanes | `aef-repository-learning` | requirements artifact | major architecture choice is a human gate |
| Design governance | brief → review → revisions → review → freeze | `design-agent`, `design-reviewer` | `aef-design-workflow`, `aef-design-review` | `DESIGN_REVISION`, `DESIGN_REVIEW` | `RESULT: DESIGN_REVISION_COMPLETE` + `READY_FOR_INDEPENDENT_DESIGN_REVIEW: YES` → dispatch review; `RESULT: DESIGN_REVIEW_APPROVED` \| `RESULT: DESIGN_REVIEW_APPROVED_WITH_NON_BLOCKING_FINDINGS` → freeze path, the latter **carrying its recorded `non_blocking_findings[]` as the Gate D5 open set** (the freeze is refused while any is still open); Human Design Brief approval; Human Visual Approval before promotion **only where the project's `WORKFLOW.md` declares that gate** (see below) |
| QA strategy | define contract in parallel with design | `qa-architect` | `aef-qa-contract` | `QA_CONTRACT` | `RESULT: QA_CONTRACT_FROZEN` before implementation completion (`RESULT: QA_CONTRACT_CREATED` is not enough) |
| Implementation | dispatch against Design + QA Contract | `implementer` | `aef-implementation-workflow` | `IMPLEMENTATION_RESULT` | `RESULT: IMPLEMENTED` only when required deterministic validation passes; otherwise `RESULT: IMPLEMENTATION_BLOCKED` |
| Engineering review | auto-dispatch a **different** session | `engineering-reviewer` | `aef-independent-review` | `ENGINEERING_REVIEW` | `RESULT: APPROVE_FOR_MERGE \| APPROVE_WITH_NON_BLOCKING_FOLLOWUP`; `RESULT: DO_NOT_MERGE` enters §8 instead |
| Correction / re-review | bounded loop | `correction-implementer`, `focused-reviewer` | `aef-correction-loop`, `aef-independent-review` | `IMPLEMENTATION_RESULT`, `ENGINEERING_REVIEW` | `RESULT: CORRECTION_COMPLETE` → dispatch a **fresh** `focused-reviewer`; `RESULT: APPROVE_CORRECTIONS` closes the loop, `RESULT: DO_NOT_APPROVE_CORRECTIONS` hands the still-open findings back to `correction-implementer`; no self-approval; ≤ 2 cycles per issue |
| Integration | verify merge-readiness | `integrator` | — | `INTEGRATION_READINESS` | stops at `RESULT: MERGE_APPROVED` unless authorized |
| QA execution | deploy to QA, run automated + visual (+ human) QA | `qa-executor` | `aef-qa-execution` | `QA_RESULT` | `RESULT: QA_RESULT_PASS` requires `OVERALL_VERDICT: READY_FOR_MERGE`; every failure classified exactly once; regressions need regression tests |
| Deployment | staging → validate → Production Candidate → promote | `deployment-authority` | `aef-deployment-execution` | `DEPLOYMENT_REQUEST`, `DEPLOYMENT_RESULT` | `RESULT: DEPLOYMENT_SUCCESSFUL` only after post-deployment validation passes; production promotion human-authorized |
| Learning | classify + persist discoveries | every lane, orchestrated by Manager | `aef-repository-learning` | persisted knowledge | `docs/engineering/LEARNING_POLICY.md` |

**Each lane reports its own `RESULT:` token — there is no single cross-lane vocabulary.** The tokens are
defined by each agent file under `.agents/agents/` and listed per lane in `subtask-report.md`
§ `RESULT:` vocabulary per lane. The child's token is **authoritative**; the child never emits an
envelope `status`; the **Manager** normalizes the token into the envelope `status` using the table in
`subtask-report.md` § Result normalization, whose values are only real members of the owning
`result_type`'s own per-type `status` enum in `docs/engineering/STRUCTURED_RESULTS.md`, or of the
global `Status Values (Enum)` table where that type declares none. A token that is unknown,
misspelled, or replaced by an envelope `status` makes the result **malformed**: the Manager rejects
it and the child re-emits (see §16).

**Never fork these skills.** The Manager adds no validation, review, or correction rules of its own;
it delegates to the existing skills and enforces their gates.

### Ordering constraints (non-obvious, and mandatory)

- Design artifacts exist and the Design Contract is **frozen** before implementation starts.
- The producing lane's own check of its design artifact is **advisory self-QA only**. It can never
  grant approval — Independent Design Review is the gate, plus a human **visual** approval step only
  where the project's own governance declares one.
- **Human Visual Approval is a project-declared gate, not a framework-shipped one.** The framework's
  `docs/engineering/WORKFLOW.md` declares it as an explicit step, but the shipped brick copy does
  **not**, so every instantiated product repo must decide for itself whether to declare it in its own
  `WORKFLOW.md`/design governance. Where it is undeclared, Independent Design Review plus Design
  Contract Freeze govern promotion, and the Manager must not invent the gate.
- The implementing lane's local runtime/browser/visual check is a **precondition** for independent
  engineering review, never a substitute for it. No work item skips independent review because
  implementation gates passed.
- Runtime and browser evidence MUST be pinned to the exact reviewed HEAD; stale evidence is invalid.
- Deploy verification (staging validation) runs **after** merge, on the same immutable artifact —
  never on a rebuild.
- Integration is allowed **only** after independent approval.

## 8. Correction and re-review loop

On `RESULT: DO_NOT_MERGE` (with `HUMAN_DECISION_REQUIRED: NO`) the Manager MUST, following the
`aef-correction-loop` skill:

1. return the concrete findings to the implementation lane (prefer the original implementer);
2. require a **new** correction commit — never amend/rebase commits the review provenance
   depends on;
3. require all applicable validation commands re-run and genuinely passing;
4. require refreshed revision-pinned evidence for any UI/runtime change;
5. auto-dispatch a **fresh focused** re-review (`focused-reviewer`) against the corrected HEAD.

The focused re-review outcome is not optional bookkeeping: on `RESULT: APPROVE_CORRECTIONS` the loop
closes and the work item returns to the §7 phase the review was gating; on
`RESULT: DO_NOT_APPROVE_CORRECTIONS` the Manager hands the still-open findings back to the correction
lane exactly as in step 1.

The implementer may **not** self-approve. After two failed cycles on the same substantive issue,
classify the impasse and escalate rather than looping (see the `aef-correction-loop` skill).

## 9. Independent review requirements

- The reviewer MUST be a **different session** from the implementer, with no write access to
  production code.
- The reviewer verifies the **entire** diff at the exact reviewed HEAD, re-runs/validates the gates,
  and challenges the implementer's claims rather than trusting them.
- Deterministic evidence (passing gates/tests) is authoritative; reviewer opinion cannot veto it and
  cannot substitute for it.
- `RESULT: DO_NOT_MERGE` findings must be concrete and actionable enough for a correction lane to act on
  without re-deriving the analysis.
- Approval binds the reviewed `HEAD_SHA` and gates *eligibility* for integration — it does not waive
  the required gate set on the integrated tree (§10).

## 10. Integration

Dispatch `integrator` only after independent approval. The Manager's integration rules:

- after independent approval, the lane's declared **required gate set runs again on the integrated
  tree** before acceptance — approval at the lane `HEAD_SHA` covers the lane diff, not the merged
  result, and does not waive integrated-tree gates;
- never integrate unapproved work, and never bypass a failed agent report as "just noise";
- never force-push; never rewrite reviewed history unnecessarily;
- no squash unless repository policy explicitly requires it;
- after push, verify the remote is 0/0 ahead/behind;
- delete the lane worktree/branch **only** after the push is verified;
- stop at `RESULT: MERGE_APPROVED` / `READY_FOR_INTEGRATION` unless repository policy explicitly authorizes
  integration. If authorization is ambiguous, stop there rather than asking a routine question.

## 11. Parallelism

Parallelize only when ownership and contracts permit it. Safe: read-only research/audit lanes;
frontend and backend lanes after their interface/state contract is fixed and paths do not overlap;
one work item's independent review in parallel with the next work item's design review.

Unsafe (do NOT launch concurrent writers): overlapping `OWNED_PATHS`; shared unresolved state
ownership; shared unresolved backend contract; one lane depends on another lane's unmerged
primitives; the design system is changing underneath both; no integration contract exists.

Every dispatch MUST tell the child which other lanes are running. Every returned report MUST carry
`SAFE_PARALLEL_WORK` and `PROHIBITED_PARALLEL_WORK` (see the report template), so the Manager can
schedule the next lanes without re-deriving what is blocked.

## 12. Cost-aware delegation policy

- Delegation is **authorized explicitly by the Manager** and must be **bounded, independent work**
  with declared paths, acceptance criteria, and validation commands. An unbounded "do the feature"
  dispatch is a contract violation.
- The Manager picks the **cheapest routing class that is sufficient** for the subtask and may
  escalate upward only with a recorded reason in the ledger:

  | Class | Use for |
  |-------|---------|
  | `CHEAP_READ` | read-only research, archaeology, search, summarization, review support that produces findings only |
  | `STANDARD` | bounded implementation, bounded correction, QA execution, design exploration |
  | `PRECISION` | hard defects, cross-cutting changes, accessibility/security-sensitive work, failed lower-class attempts |

- **Routing is replaceable execution policy, not workflow authority.** This rule is **self-contained**:
  changing the model, provider, or dispatch class used for a subtask never changes which gates, reviews,
  or human approvals apply, and never adds, removes, or reorders a workflow step. A project may replace
  the class taxonomy with its own routing policy (§3 `ROUTING_POLICY`); the workflow semantics above are
  unchanged by that replacement. This rule is stated here on its own authority — it does not depend on
  any other document's wording.
- **The three classes above are dispatch *cost* classes, not a design-workstream routing policy.** They
  rank what a *subtask* costs to run. A design workstream may separately classify design *capability*
  (first-pass exploration vs. precision corrections vs. specialized work), and that taxonomy is a
  different, independent axis that happens to reuse some of the same class words; the two are never
  interchangeable, neither one sets the other, and re-labelling either never changes a gate, review, or
  approval.
- Each child reports the model/reasoning effort it actually used (`subtask-report.md`); a child that
  had to escalate internally reports the reason.
- The Manager **retains** repository context, sequencing, integration, and final acceptance. It
  delegates execution, never authority.

## 13. Human escalation (two-phase)

The Manager MUST NOT ask routine questions — "should I proceed?", "review is done, what's next?",
"should I start the reviewer?", "should I merge after approval?". Those transitions are defined by
this skill and by `WORKFLOW.md`.

**Phase 1 — durable early notice (machine-readable, non-blocking).** As soon as a consequential
decision is identified (typically during design review or reconnaissance), the Manager MUST:

1. **Create the Human Decision object** per `docs/engineering/HUMAN_DECISIONS.md` § Human Decision
   Object Schema and the `aef-human-decision` skill: `status: PENDING`, `decision_id`, `type`,
   `question` (atomic), `context` (blocking work item + evidence), `recommendation`, and 2–4 atomic
   `options`. Persist it under `DECISION_DIR` (§3) and **commit** the creation — the object is durable,
   versioned, and queryable, so the decision exists independently of any conversation. Record the id in
   `DECISIONS.md`, `LANES.md`, and `WORK_STATE.md` (§14, §15).
2. **Emit one machine-readable notice and nothing else conversational:**

   ```
   HUMAN_DECISION_PENDING: <decision_id>
   BLOCKED_WORK_ITEM: <item_type> <item_ref>
   PAUSED_LANES: [<task_id> ...]           # may not proceed past the blocked point
   CONTINUING_SAFE_LANES: [<task_id> ...]  # per SAFE_PARALLEL_WORK in their reports
   QUESTION_PRESENTED: NO                  # no question is being asked yet
   NEXT_ACTION: DISPATCH_NEXT_LANE
   ```

3. **Do not** present the options, a recommendation, or a request for a decision in prose. Prose option
   lists violate `HUMAN_DECISIONS.md` (structured question UI is mandatory, never free-form prose) and
   would pre-empt the atomic per-option judgement the human is entitled to make. Phase 2 is the single
   place a question and its options are presented.

The workflow does **not** stop here while safe work remains: `NEXT_ACTION: DISPATCH_NEXT_LANE` keeps the
non-blocked lanes moving. Phase 1 exists so the human learns of the decision early and the durable record
exists early — not so the human answers early.

**Phase 2 — interactive blocking (structured questions).** Only when the decision is the **sole**
remaining blocker and all safe work is exhausted: re-read the object, update it if the evidence or
options changed (`updated_at`), move it `PENDING → IN_PROGRESS`, and present it through the structured
question UI (`ask_user` / `mcp__Air__ask_user_question`) per the `aef-human-decision` skill and the
`HUMAN_DECISIONS.md` § Structured Question UI Contract — one atomic question, atomic options each, with
the recommendation. Never in prose.

**After the answer:** the human's answer **is** the approval. Per `docs/engineering/HUMAN_DECISIONS.md`
§ Resumption, before resuming anything the Manager MUST:

1. set `status: RESOLVED` and populate **every** mandatory `resolution` field: `selected_option`,
   `decided_by`, `decided_at` (ISO8601), `rationale`, and `follow_up_actions[]` (each with `action` and
   `owner`; `due_date` optional) — a resolution missing any of these is invalid and must be re-emitted;
2. **tamper-check**: verify `selected_option` is one of the `option_id`s **as originally presented in
   Phase 2**, and that `question`/`options` were not changed after presentation. If either fails, the
   result is invalid — re-present the decision instead of resuming from it;
3. commit the transition (the audit trail is immutable; amendments create a new decision object) and
   record it in `WORK_STATE.md`;
4. then **immediately launch** the newly unblocked lanes, passing the resolution as input — do not wait
   for a second confirmation.

Escalation triggers (authoritative list lives in `docs/engineering/HUMAN_DECISIONS.md` and
`WORKFLOW.md`; the `G*` IDs below are project-local shorthand for referencing them, not a new gate
list):

| ID | Gate |
|----|------|
| `G1` | Major architecture choice |
| `G2` | Human Design Brief approval; Level 2/3 DCR approval; Human Visual Approval before design promotion **only where the project declares that gate** (§7) |
| `G3` | Human QA initiation |
| `G4` | Destructive migration; infrastructure destruction; security/billing policy |
| `G5` | Production promotion (human-authorized unless project policy says otherwise) |

Also escalate (not loop): product scope/priority change, material external credential or permission
requirement, unreconcilable conflict between authoritative sources, and repeated failure of the same
substantive issue (two cycles — see the `aef-correction-loop` skill).

## 14. Persistence and crash/compaction resumption

Harness-specific lifecycle hooks are **not** required by this framework. Optional reference
adapters for hosts that support them ship under `scripts/aef/` (see `scripts/aef/README.md`);
they are conveniences only — the contract is the plain-file state below, which works on any host.
**All** Manager state that must survive a crash or context compaction is written as
**plain markdown/JSON files** under `DISPATCH_STATE_DIR` (default `docs/engineering/dispatch/`):

```
<DISPATCH_STATE_DIR>/
  LANES.md                              # one row per lane: task id, type, state, worktree, branch, SHAs, next action
  tasks/<TASK_ID>/prompt.md             # the exact prompt dispatched (persisted BEFORE launch)
  tasks/<TASK_ID>/report.md             # the child's returned report, verbatim
  tasks/<TASK_ID>/state.json            # {task_id, task_type, state, worktree, branch, base_sha, head_sha, result, decision_ids[]}
  DECISIONS.md                          # index of open/resolved decision ids (objects live in DECISION_DIR)
```

Write rules:

- persist `prompt.md` **before** launching a lane (so the dispatch stays auditable if the
  session dies);
- update `LANES.md` and `state.json` on every result, state change, and escalation;
- **never** rely on in-memory-only state, and never rely on a tool-specific hook to save it.

**Relationship to `STRUCTURED_RESULTS.md` rule 6.** That rule persists the **envelope JSON** in the
product repository under `.results/` (or a configured location) for audit. This layout is a
**different artifact**: `report.md` is the lane's returned report **verbatim**, which is what the Manager
parses, and `state.json` is the Manager's own lane record. The two do not conflict and neither
overrides the other. When a project declares `DISPATCH_STATE_DIR` as its configured result location,
the two trees are the same tree; otherwise a project may keep both, with the envelope JSON mirrored
under `.results/`. This section is authoritative for **Manager state**; `STRUCTURED_RESULTS.md` rule 6
remains authoritative for the **envelope audit record**.

Recovery procedure for a new session or a post-compaction session:

1. read `docs/engineering/WORK_STATE.md` and `LANES.md`; rebuild the in-memory picture from disk;
2. read each `state.json` and every persisted `report.md`;
3. verify against Git: `git worktree list`, `git branch -v`, `git status` per lane worktree;
4. treat lanes reported in-flight whose worktree/branch no longer exist as `IMPLEMENTATION_BLOCKED`
   with evidence, not as still-running;
5. if the persisted state disagrees with Git, **Git wins** for code state; correct the ledger, then
   continue. Never restart completed work.
6. never re-dispatch a lane whose `report.md` already exists; resume from the recorded next action.

## 15. Manager ledger

Maintain a compact per-work-item block in `docs/engineering/WORK_STATE.md` (workflow state,
**not** a substitute for Git):

```
WORK_ITEM:
STATE:
OWNERSHIP:            # owned / read-only / prohibited
LANE:                 # task id, type, worktree, branch, base_sha, head_sha, routing class
REVIEW_RESULT:
QA_RESULT:
DEPLOYMENT_RESULT:
BLOCKERS:
DECISIONS:            # open decision ids
DEPENDENCIES:
SAFE_PARALLEL:
NEXT_AUTOMATIC_ACTION:
SELF_EDITS:           # only the §2 mechanical edits, with reason
CONVENTIONS_USED:     # declared or defaulted values from §3
```

## 16. Stop conditions

The Manager MUST stop rather than guess when: required validation cannot pass for a reason that
would require weakening tests; two authoritative sources conflict irreconcilably; a requirement is
unresolved; an architecture decision would introduce a new framework/pattern; a security boundary is
unclear; an operation would be destructive; ownership would overlap; a dispatch precondition cannot
be satisfied; a child result is malformed, unparsable, or lacks provenance; or a gate would have to
be skipped to proceed.

Emit a structured result and park cleanly (`status: BLOCKED`, blockers with `type` and
`escalation_path`) — no hanging processes, no silent retries.

## 17. Manager's own structured result

The Manager emits a machine-readable result (envelope per `docs/engineering/STRUCTURED_RESULTS.md`,
`result_type: ORCHESTRATION_RESULT`, `agent_role: ENGINEERING_MANAGER`, envelope `status` one of
`COMPLETE | PARTIAL | BLOCKED | HUMAN_DECISION_REQUIRED`) and finishes with exactly one terminal
`RESULT:` line, using **exactly** the vocabulary defined in `.agents/skills/aef-run-feature/SKILL.md` § Final
Manager Report:

```
RESULT: AUTONOMOUS_WORKFLOW_PASS
RESULT: AUTONOMOUS_WORKFLOW_PARTIAL
RESULT: AUTONOMOUS_WORKFLOW_BLOCKED
RESULT: HUMAN_DECISION_REQUIRED
```

**.agents/skills/aef-run-feature/SKILL.md is the single source of the terminal `RESULT:` vocabulary.** Do not
restate, extend, or rename these tokens anywhere — a second spelling is the defect this rule exists to
prevent. The envelope `status` and the terminal `RESULT:` token are **different things**: `status` is
the machine-parsed envelope field validated against the `Status Values` enum in
`docs/engineering/STRUCTURED_RESULTS.md`; the terminal `RESULT:` line is the human-facing loop
outcome, and no other role emits it.
