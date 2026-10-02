# ADR 0003 — Product-Generic Orchestrator Skill

- **Status:** Accepted (material framework change; **independent review required** before promotion.
  It adds **no** lifecycle stage and **no** human gate, so it is not a `HUMAN_DECISION_REQUIRED`
  governance change.)
- **Date:** 2026-09-30
- **Amended:** 2026-10-01 — the framework repository's **own root** added as a second generated target
  root, so this repository consumes what it ships; `--check` now covers both roots and the root
  `.agents/` is a generated mirror of the brick's canonical tree. Decision-only: the platform matrix,
  the `aef-` prefix rationale, the empirical findings below, and the "generated output, never
  hand-maintained" invariant are unchanged — the invariant is simply now stated per root. See
  [§ Roots](#roots-the-shipped-brick-and-this-repositorys-own-root) and the corresponding
  [Consequences](#consequences) bullet.
- **Decision type:** `WORKFLOW_IMPROVEMENT` (a `LEARNING_POLICY.md` category). Its required authority
  is **independent review**, which is why this change is not a `HUMAN_DECISION_REQUIRED` governance
  decision: it adds no human gate and no lifecycle stage.
- **Scope:** Ships an invocable **orchestrator skill** (plus its dispatch/report templates) as a
  framework artifact, so every product repository instantiated or upgraded from this framework
  inherits a top-level session that **dispatches** work instead of doing production work itself.
  This ADR does **not** modify [ADR 0001](0001-framework-distribution-and-versioning.md) or
  [ADR 0002](0002-dart-mason-git-framework-driver.md). It does **not** modify the **lifecycle steps or
  the human-gate list** in `WORKFLOW.md`, and it does not modify any existing skill/agent; its only
  `WORKFLOW.md` touch is the *Resolved framework areas* entry recording this decision. (`WORKFLOW.md` is
  otherwise edited in the same change set by the separate design-authority workstream — a new step 18
  *Human Visual Approval* plus renumbering, cited from `DESIGN_GOVERNANCE.md` — which is **not** part of
  this decision.)

---

## Context

`AGENTS.md` states the Manager/orchestrator invariants in prose: one authoritative Manager, specialists
do not advance state, implementers never self-approve, writers declare `OWNED_PATHS` /
`READ_ONLY_PATHS` / `PROHIBITED_PATHS`, delegation is bounded and explicitly authorized, and the
human is used only for consequential decisions. The `/run-feature` command lists the phases and the
routing rules.

What was missing was the **operational layer**: nothing forced a top-level session to decompose,
dispatch to isolated lanes with a full provenance header, refuse to integrate unreviewed work, or
escalate in a bounded two-phase way. In practice, a project had to hand-author that skill itself. A
production project did exactly that — a project-specific orchestrator skill plus a subtask
prompt/report contract and a worktree-isolation discipline — and it worked, but it lived only in that
project and was not reusable by the next instantiation.

Meanwhile the concrete distribution machinery (ADR 0001/0002) only ships whatever is physically
present in the Mason brick's `__brick__/` tree; `framework-manifest.yaml` is generated from the files
Mason actually rendered. So a new artifact is "registered" simply by being in `__brick__/` — and
verified by the CLI's `KNOWN DEFECT D` template-completeness test, which asserts the exact managed
artifact inventory.

## Decision

Ship a **product-generic** orchestrator skill and its two dispatch contracts as framework artifacts.

| Artifact (in the brick) | Instantiated into a product repo as | Role |
|---|---|---|
| `.agents/skills/aef-orchestrator/SKILL.md` | same path | Manager-lane procedure |
| `.agents/skills/aef-orchestrator/templates/subtask-prompt.md` | same path | dispatch contract (mandatory YAML header) |
| `.agents/skills/aef-orchestrator/templates/subtask-report.md` | same path | structured result contract |
| `docs/engineering/adr/0003-product-generic-orchestrator-skill.md` | same path | this decision record |

Plus minimal wiring: an `## Orchestration` section in the instantiated `AGENTS.md` and in
`framework/templates/product-repo/AGENTS.template.md` (both referencing the skill), the
`aef-run-feature` skill and its generated platform command adapters, and the new
managed paths added to the CLI's template-completeness test so the managed inventory tracks them (see
Verification for exactly what that test does and does not prove).

One authoritative-contract addition was unavoidable: the skill's Manager result
(`ORCHESTRATION_RESULT`, `agent_role: ENGINEERING_MANAGER`) did not exist in
`docs/engineering/STRUCTURED_RESULTS.md`. Rather than let the skill invent a result type it
declared subordinate to that document, the enum table, the `agent_role` enum, and a new payload
section were added there (and in the brick copy). It is additive and precedented by
`HUMAN_DECISION`/`PRODUCTION_VALIDATION`, which the Manager already emits. `schema_version` stays
`1.0` because the change adds a value, not a field.

The skill encodes:

1. **Orchestrator-not-implementer by default**, with an explicit, enumerated escape hatch for
   small mechanical edits (repository metadata, workflow/decision bookkeeping, behavior-free config
   fixes to an already-declared gate, documentation that only restates a recorded decision). The
   escape hatch explicitly does **not** grant self-approval.
2. **A full dispatch contract**: worktree isolation preconditions that must hold *before* a writer is
   launched, a mandatory non-omittable YAML header, bounded acceptance criteria, and exact validation
   commands.
3. **A phase delegation map** onto the **existing** agents and skills (`design-agent`,
   `design-reviewer`, `implementer`, `engineering-reviewer`, `correction-implementer`,
   `focused-reviewer`, `integrator`, `qa-architect`, `qa-executor`, `deployment-authority`), which
   *reuses* rather than forks them.
4. **Two-phase human escalation**, compliant with the mandatory structured-question rule: phase 1
   **creates the durable Human Decision object** (persisted, committed, with its id) and emits only a
   machine-readable "pending, no question asked yet" notice while safe work continues — no prose
   option list, no recommendation, no request for a decision; phase 2 is the **single** place the
   question and its atomic options are presented, and only through the structured question UI
   (`ask_user`), once the decision is the sole remaining blocker. After the answer the Manager must
   populate every mandatory resolution field, tamper-check the selected option against the options as
   presented, commit the transition, and then immediately continue unblocked lanes.
5. **Crash/compaction survival without tool hooks**: all durable Manager state is plain
   markdown/JSON under a project-declared state directory, with a written recovery procedure.

### Platform matrix and generated adapters

`.agents/` is the **canonical source of truth** and is never generated. Every other platform
directory is **generated output**, rendered from it by
`cli/tool/generate_platform_adapters.dart`.

**Enforcement is mechanical in the framework repository only.** The generator and its drift test live
in this repository and are not shipped in the brick, so an instantiated product repository receives the
57 generated adapters with **no** generator and **no** `--check`. In a product repo the
"never hand-edit, fix the canonical artifact under `.agents/`" rule is therefore **advisory** — it is
stated in the shipped `AGENTS.md` and in this ADR, and it is the human's rule to uphold, but nothing
mechanically fails if it is broken. Only in this framework repository is it enforced by drift test.

| Platform | Skills | Agents | Command | Role |
|---|---|---|---|---|
| `.agents/` | native | native | native (skill + `argument-hint`) | **canonical source of truth** (Devin CLI) |
| `.claude/` | generated | generated | generated | Claude Code |
| `.opencode/` | **no adapter — reads `.agents/skills/` natively** | generated | generated | opencode |
| `.junie/` | generated | generated | generated | JetBrains Junie |

`.opencode/skills/` is deliberately **not** created: opencode discovers `.agents/skills/` directly, so
a copy there would be a duplicate with no benefit. The matrix lives in **one declarative constant**
(`kPlatforms`) in the generator, and the drift test asserts against that same constant, so a platform
cannot be added to the generator and forgotten in the test, nor added to the test without a generator
entry. Adding a platform is a single edit.

#### Roots: the shipped brick and this repository's own root

The generator emits into **two roots**, declared as a second declarative constant (`kTargetRoots`)
alongside the platform matrix, so *which platforms × which roots* is a single edit point and the emit
logic is written once for both:

| Root | Generated content | Count | Role |
|---|---|---|---|
| `framework/templates/__brick__/` | `.claude/` 23 + `.junie/` 23 + `.opencode/` 11 | **57** | shipped to product repositories |
| `.` — this repository's own root | `.agents/` **mirror** 24 + `.claude/` 23 + `.junie/` 23 + `.opencode/` 11 | **81** | **dogfooding**: this repository consumes exactly what it ships |

The canonical total across both roots is **138** generated files. `--check` verifies **every adapter at
every root** and exits non-zero listing each mismatch prefixed with the root it belongs to
(`brick: …` / `root: …`); a clean run prints the canonical path, the per-root totals, and the
per-platform breakdown.

The root `.agents/` is a **generated mirror** of the brick's canonical tree and **not a second source of
truth**. It exists so this repository resolves skills the way opencode does — natively from
`.agents/skills/` — instead of shipping a layout it does not itself consume. The rule is
unambiguous: **fix the brick**. An edit to the root mirror is not a framework change; it is an edit to a
copy, and it is overwritten by the next generator run and reported as drift by `--check` in the
meantime. The root `.claude/`, `.junie/`, and `.opencode/` are generated on exactly the same terms.

The per-platform frontmatter shapes are not interchangeable, so the adapters are rendered per schema:

| Artifact | `.agents/` (canonical) | `.claude/` | `.junie/` | `.opencode/` |
|---|---|---|---|---|
| agent | `name`, `description`, `allowed-tools: [tokens]` | `name`, `description`, `tools: A, B, C` | `name`, `description`, `tools: ["A", "B"]`, `allowPromptArgument: true`, `skills` | `description`, `mode: subagent`, `permission:` block |
| skill | `name`, `description`, (+ `argument-hint`, `triggers`) | verbatim + mapped `disable-model-invocation` | verbatim | n/a (native) |
| command | n/a (it *is* a skill) | `description`, `argument-hint`, `disable-model-invocation`, `$ARGUMENTS` | `name`, `description`, `argument-hint`, `allowPromptArgument: true` | `description`, `$ARGUMENTS` |

The complete tool mapping, applied mechanically from the canonical `allowed-tools` token list and
never from prose:

| canonical | opencode `permission` | Claude `tools` | Junie `tools` |
|---|---|---|---|
| `read` | `read: allow` | `Read` | `Read` |
| `grep` | `grep: allow` | `Grep` | `Grep` |
| `glob` | `glob: allow` | `Glob` | `Glob` |
| `edit` | `edit: allow` / `edit: deny` | `Write`, `Edit` | `Write`, `Edit` |
| `exec` | `bash: allow` / `bash: deny` | `Bash` | `Bash` |

`edit` is a single canonical token that expands to **two** platform tool names. For opencode, `edit:
deny` is **mandatory** whenever the canonical list lacks `edit`, because opencode allows editing by
default: omitting the deny would silently grant write access to a read-only reviewer. The **native
edit path** is therefore denied identically on every platform, and a writer is granted it identically
on every platform; a mismatch would be a governance bug and the drift test asserts the granted tool
set is identical across platforms.

**Precisely what that does and does not guarantee.** It guarantees the *native edit path* — `Write`,
`Edit`, `write`/`edit`/`apply_patch` — is unavailable to a read-only profile. It does **not** make a
read-only profile read-only with respect to the filesystem: a profile without `edit` still holds
`exec`, which maps to `Bash` on Claude Code and Junie and to `bash: allow` on opencode, so the shell
reaches the filesystem on **all three** platforms. The read-only invariant is therefore enforced as
**two** properties, not one: the mechanical denial of the native edit path (asserted by the drift test)
plus the behavioural rule in `AGENTS.md` that an independent reviewer never modifies production code.
Denying filesystem writes through the shell is **not** claimed by this ADR. Tracked follow-up (**owner:
framework tooling / CLI**): build an argv-only, **deny-by-default** `read_only_exec` allowlist runner
that permits exactly the project's declared required gates (`dart format`, `dart analyze`, `dart test`,
read-only `git` reads) and rejects everything else, so a read-only reviewer's shell is bounded by the
same list the gates are declared in. No tool grant changes with this ADR.

Skill copies are the canonical file **verbatim** with at most one mechanical difference: the canonical
`triggers: ["user"]` is mapped to Claude Code's `disable-model-invocation: true`, so the human entry
point is never auto-invoked by the model. The mapping is derived from the `triggers` key, not
hand-listed per skill, and the drift test asserts that a Junie or Claude skill copy differs from
canonical in *only* that mapped field. Junie has no documented counterpart to `triggers`, so its copy
is byte-identical rather than carrying an invented key. `triggers: ["user"]` is the **only** value the
canonical vocabulary defines, and `parseSkill` throws on any other value rather than mapping an
unrecognised contract as though it meant "human-invoked only".

The mapping is a **trigger-key mapping, not an asset copy**: platform skill adapters are
single-file (`<platform>/skills/<name>/SKILL.md`) and their relative references point at the canonical
`.agents/` tree, which the mirror provides. Referenced assets (e.g.
`.agents/skills/aef-orchestrator/templates/`) are mirrored verbatim into `.agents/` but are **not**
duplicated into every platform's `skills/` tree; today no canonical skill references a path inside a
platform directory, so no reference is broken. A canonical skill that ships a referenced asset and
needs it adjacent to a platform copy would need an asset-emitting step added to that platform.

##### Claude Code exposes the entry point twice, by design

Claude Code treats `commands/` and `skills/` as one invocation feature, so this repository ships the
human entry point **both** ways: `.claude/commands/run-feature.md` (the `/run-feature` command adapter)
and `.claude/skills/aef-run-feature/SKILL.md` (the `aef-run-feature` skill adapter). The workflow is
therefore exposed as both `/run-feature` and `/aef-run-feature`. This is an **intentional alias of the
same workflow, not two copies of it**: both files are generated from the one canonical
`.agents/skills/aef-run-feature/SKILL.md`, both are `disable-model-invocation: true`, and both resolve
to the same skill body. There is **no name collision and no startup conflict** — the two names differ,
and Claude Code's resolution between them is order-independent for the same body. Both files are kept
because which one a given user has wired up or muscle-memorized is a human preference, not a
framework decision. The canonical skill's H1 is `# aef-run-feature`, matching its `name:` field and its
directory, so the naming is self-consistent across the canonical file and both Claude adapters.

#### Empirical evidence: generated adapters, not shared files

The alternative — one file shared across platforms by symlink, or a single format every platform
tolerates — was tested and **fails on all three counts**:

1. **opencode hard-fails on a foreign frontmatter shape.** A Junie-style `tools: [...]` array placed
   in `.opencode/agents/` aborts startup with
   `Error: Configuration is invalid ... Expected object | undefined`. opencode cannot even start, so
   "share the Junie file" is not a degraded experience — it is a broken tool.
2. **opencode silently ignores unrecognized tool fields and falls back to allow-everything.** A
   Devin-format file symlinked into `.opencode/agents/` resolved to `permission: * allow`,
   `edit: true`, `write: true`, with the `allowed-tools` value swallowed into `options`. This is the
   dangerous case: a read-only reviewer would be granted **write access with no error and no
   warning**. Silent permission escalation is strictly worse than a hard failure, which is why the
   renderer emits only the keys opencode's schema defines.
3. **Mason dereferences symlinks.** A symlinked file is rendered as a regular file and a symlinked
   directory as a real directory, so symlink-based sharing yields the same copies in the output plus
   redundant manifest entries — it buys nothing.

The resulting property, stated plainly: **one canonical edit point**, adapters **machine-verified by
the drift test**, and the **correct per-platform schema** on each host. Editing a canonical agent
profile or skill and re-running the generator updates every platform; `--check` fails the build if any
committed adapter drifts, and the generator is deterministic (no timestamps, no environment input,
stable ordering), so `--check` is reproducible in CI.

#### Invariant: generated directories are never hand-maintained

**Revised invariant.** `.junie/`, `.claude/`, and `.opencode/` **may exist only as generator-produced
output, never as hand-maintained content**, and this is enforced mechanically by the drift test
(`cli/test/platform_adapter_test.dart`): `--check` fails on a missing adapter, a differing adapter, or
an **unexpected** file in a generator-owned directory.

The invariant is stated **per root**, and it now covers **both** roots: the brick's `.claude/`,
`.junie/`, and `.opencode/`, **and** this repository's own root `.claude/`, `.junie/`, `.opencode/`,
**and `.agents/`**. The root `.agents/` is the sharpest case, because it is the one generated directory
that carries the canonical *names*: it is a mirror, so editing one is not editing the framework, it is
editing a copy — precisely the mistake the drift test exists to catch, and one the old, un-mirrored,
partially hand-written root layout had already made.

##### Ownership is scoped to the generated subtrees, not the whole platform directory

Ownership is **derived structurally from the generated paths**, never from a hand-maintained list: the
generator groups every generated path under its `<root>/<subdirectory>` prefix, and those prefixes are
exactly what it owns. So it owns `.opencode/agents/**` and `.opencode/command/**` and **not** the rest
of `.opencode/`. This matters because `.opencode/` is not exclusively ours: opencode writes its own
runtime files there at session time — `node_modules/` (3,645 files on the development host) plus
`package.json`, `package-lock.json`, and `.gitignore`. Claiming the whole directory made `--check` and
`dart test` permanently red in **every** bootstrapped product repository, which is a false positive in
the direction that gets the invariant ignored.

The scoping is applied **uniformly to all three platforms** rather than special-casing `.opencode`, so
ownership cannot rot when a platform gains or renames a subdirectory. The disk-side guarantee is
deliberately kept: the drift test asserts the **raw recursive disk count** for each owned scope equals
the generator's count, and asserts `.opencode/agents/` = 10 and `.opencode/command/` = 1 (11 opencode
adapters) explicitly. Dropping `.opencode` from the disk check entirely would have left the 11-count
guarantee silently unverified while the suite went green — a gate that reports success falsely, which
is the failure mode this scoping is meant to avoid.

> **Superseded:** an earlier revision of this ADR recorded the rule as "no `junie` anywhere in the
> shipped tree". That is **wrong by decision** and is replaced by the invariant above. The `junie`
> platform is retained by explicit human decision, and what is prohibited is *hand-maintained* content
> in a generated directory — not the directory's existence. The same framing applies to `.claude/` and
> `.opencode/`.

#### Why the `aef-` skill-name prefix

opencode resolves **same-ID skills by precedence, last source wins**. Canonical skills therefore carry
an `aef-` prefix so that a consuming product's own skill — say `implementation-workflow` — can never be
**silently overridden** by, or silently override, a framework skill. With a shared, unprefixed
namespace the collision would be invisible: no error, just a different skill body being loaded. The
prefix makes the framework's namespace explicit and collision-free, and it is carried mechanically into
the Junie `skills:` bindings (which must reference the `aef-`-prefixed names, since that is what the
skill directories are actually called).

The same precedence rule is why the prefix is what makes the **root copy** safe. With a generated
mirror at the repository root, an unprefixed copy would place four generic names —
`correction-loop`, `implementation-workflow`, `independent-review`, `repository-learning` — directly in
this repository's own skill namespace, where a project-local or future framework skill of the same name
would collide invisibly and the loser would be silently ignored. With the prefix, the mirror occupies
its own namespace at **both** roots. This is load-bearing rather than cosmetic, and the root tree shows
it concretely: those four unprefixed root `.junie/` skills pre-dated the mirror, were superseded by
their `aef-`-prefixed generated equivalents, and were **deleted** — the only files the migration
removed, and none of them were canonical.

### Product-generic by construction

Every project-specific element is a **placeholder convention** that a consuming project sets in its
own `AGENTS.md § Orchestration`, with a framework default listed in the skill (state directory,
prompt/report template locations, decision directory, workflow-state file, isolation command,
concurrency limit, routing policy). No product name, tool brand, design-tool name, tenant rule, or
vendor-specific layout appears in the artifacts; the provenance skill's tool-specific pieces
(subagent-session platform, lifecycle hooks, design-tool specifics, a specific frontend stack's
commands, one product's routes and gates) were **generalized or dropped**, not copied.

Routing stays a **configurable execution policy, not workflow authority**: changing the model, provider,
or dispatch class used for a subtask never changes which gates, reviews, or human approvals apply, and
never adds, removes, or reorders a workflow step. This rule is stated **standalone** in the skill and
deliberately attributed to no other document's invariant — the rule must remain true and self-contained
regardless of what any `AGENTS.md` copy happens to contain, so no product repo can inherit an
unresolvable or contradicted citation. The skill adds three routing
*classes* (`CHEAP_READ` / `STANDARD` / `PRECISION`) for the cost-aware delegation policy and makes
the child's actual model/reasoning effort a reported, non-gating observability field. Those are
**dispatch cost classes** (what a subtask costs to run), a separate axis from any design-workstream
routing policy (what design capability a revision needs); the skill instantiates no routing-policy file
into product repositories and never reads one, so the two taxonomies cannot collide at runtime.

## Rejected alternatives

- **Port the product skill verbatim.** Rejected: it carried product identity, a specific design
  tool, a specific frontend stack's gates, a specific cloud host, one product's route inventory, and
  a tool's lifecycle hooks. Not shippable to other products.
- **Ship tool-specific lifecycle hooks** (auto-save work state on a tool event, inject it on session
  start). Rejected: not portable, and unnecessary — plain-file state plus a documented recovery
  procedure achieves the same durability on any agent host. The *requirement* is documented; the
  mechanism is the product's choice.
- **Let the Manager implement small tasks directly, unbounded.** Rejected: it collapses the
  independent-review guarantee for exactly the changes least likely to be reviewed carefully. The
  enumerated escape hatch keeps the pragmatism without the hole.
- **Fork or restate the review/correction/QA rules inside the new skill.** Rejected: duplicate
  authority invites divergence. The skill delegates to `independent-review`, `correction-loop`,
  `qa-execution`, `human-decision`, and the rest, and states that `WORKFLOW.md` wins on conflict.
- **Introduce new human gates** (for example a per-feature "dispatch approval"). Rejected: it would
  redesign the human-gate list, which is out of scope. The `G1`–`G5` identifiers in the skill are
  explicitly documented as *project-local shorthand* for the already-authoritative gates.
- **Register the skill in a new manifest/registry file.** Rejected: ADR 0002 makes
  `framework-manifest.yaml` the single authoritative provenance artifact, and it is generated from
  what Mason renders. A second registry would be a second source of truth. The established
  mechanism — brick content + the completeness test — is used instead.
- **Share one agent/skill file across platforms by symlink, or pick one format all platforms
  tolerate.** Rejected on measured evidence, recorded above: opencode hard-fails on the Junie
  frontmatter shape, silently escalates permissions to allow-everything on the Devin shape, and Mason
  dereferences symlinks into plain copies anyway. A silent permission escalation on a read-only
  reviewer is an unacceptable failure mode for generated governance artifacts.
- **Ship only opencode, dropping the Junie platform.** Rejected by human decision: Junie is retained
  alongside Claude Code, with the same generated-adapter property.
- **Generate a `.opencode/skills/` copy for uniformity with the other platforms.** Rejected:
  opencode reads `.agents/skills/` natively, so the copy would be a duplicate that can only drift.
- **Leave the framework repository's root stale, or refresh it once by hand.** Rejected by human
  decision (2026-10-01) in favour of making the root a generated target root. A one-off hand refresh
  would have produced the same 81 files while leaving them un-owned and unchecked — which is the exact
  condition that made the previous root layout wrong. Deleting the root `.junie/` and consuming the
  canonical layout only was also rejected: the framework would then run on a different layout from the
  one it ships to every product repository.

## Product adoption

Nothing is required of existing product repositories beyond taking the framework upgrade:

- **New instantiation:** `bootstrap` renders the skill and both templates, and
  `framework-manifest.yaml` records them as managed artifacts with baseline hashes, so later
  local modification is derived and upgrades classify them as added/modified/conflicting like any
  other framework artifact.
- **Upgrade:** the artifacts arrive through the normal reviewable, isolated 3-way merge; a project
  that has locally adapted the templates sees the usual modify-conflict handling.
- **Effective use:** the project's `AGENTS.md § Orchestration` declares its convention values, or
  records `DEFAULTS` to accept the framework defaults. Until then the Manager must record the
  defaults it used in its ledger — conventions are never left implicit.
- **Adopting a different agent host** (a different subagent dispatch mechanism) changes how a lane
  is *launched*; it does not change the dispatch header, the report contract, the gates, or the
  escalation policy.

## Verification

- `dart format --output=none --set-exit-if-changed .`, `dart analyze`, `dart test` green in `cli/`.
- The CLI's `KNOWN DEFECT D` template-completeness test asserts the new managed paths exist on disk
  **and** appear in `framework-manifest.yaml`, with the total artifact count matching exactly. That
  proves **fresh instantiation and manifest registration** of those paths — it is the *only* proof
  claimed here.
- The platform-adapter drift test (`cli/test/platform_adapter_test.dart`) runs the generator in
  `--check` mode — which covers **both** roots, the brick and this repository's root — and additionally
  asserts: every canonical agent has exactly one adapter per platform **at every root**; the adapter
  **count** at every root is derived from the same `kPlatforms` × `kTargetRoots` declarations the
  generator iterates, so a missing adapter fails rather than passing silently; the root `.agents/`
  mirror is **byte-identical** to the brick's canonical tree; the granted tool set is identical across
  platforms; read-only profiles deny `edit` everywhere and write-capable profiles are granted it
  everywhere; no adapter emits a foreign frontmatter key; and a Junie or Claude skill copy differs from
  canonical in only the mapped field.
- **Upgrade re-delivery is not proven by that test**, which exercises `bootstrap` only. The test also
  binds a hardcoded absolute `frameworkRepoPath`, so it runs only on that host path; parameterizing it
  is a pre-existing framework defect recorded in the framework repository's `WORK_STATE.md`, outside
  this decision's scope.
- No product-specific identifier appears in any new artifact.

## Consequences

- The prose Manager invariants in `AGENTS.md` now have an executable counterpart, and the prose and
  the skill can no longer drift silently: the skill defers to `WORKFLOW.md` on conflict.
- Projects that were hand-authoring an orchestrator skill can delete it and inherit this one.
- **Superseded location note:** this ADR originally recorded the skill at
  `.junie/skills/orchestrator/`. The brick's artifacts were relocated to the portable Agent Skills
  layout (`.agents/skills/aef-orchestrator/`), the canonical agent profiles to `.agents/agents/`, and
  the human entry point to the `aef-run-feature` skill. The decision and the canonical artifacts are
  unchanged; only their paths and the `aef-` skill-name prefix changed. `.junie/` was later
  **retained by explicit human decision** as a *generated* adapter platform alongside `.claude/`, and
  `.opencode/` is generated as well; see the platform matrix and the revised invariant above.
- **The framework repository now dogfoods what it ships (human decision, 2026-10-01).** The root
  `.junie/` mirror was previously stale — 10 tracked files, **5** of the 10 agent profiles, 4 of the 12
  skills, **unprefixed** skill names, and a superseded `run-feature` command — and sat outside
  `--check`, which was scoped to the brick. The root is now a **generated target root** alongside the
  brick, so this repository carries `.agents/` (mirror, 24 files), `.claude/` (23), `.junie/` (23), and
  `.opencode/` (11) — **81** files, 138 across both roots — rendered from the same canonical source and
  covered by the same `--check`. The four unprefixed root `.junie/` skills were superseded by their
  `aef-`-prefixed equivalents and deleted; the other six tracked root `.junie/` files were overwritten
  in place by their generated equivalents. The framework's single source of truth remains the brick's
  `.agents/`; the root copy is generated output.
- The skill's convention defaults are a **framework proposal, not validated policy**; the exact gate
  set and ownership-conflict enforcement mechanics remain `UNRESOLVED_FRAMEWORK_AREA` items in
  `WORKFLOW.md`.

## Provenance

This skill is **generalized from a production project-local orchestrator skill and its subtask
dispatch protocol** — a hand-authored, working, but non-reusable artifact that lived in a single
product repository. The mechanisms (orchestrator-not-implementer default, isolated-lane dispatch with
declared ownership, mandatory provenance header, correction/re-review loop, two-phase human
escalation, plain-file state) were kept; the product identity, agent-host branding, design-tool
integration, stack-specific gates, and host-specific lifecycle hooks were generalized or dropped.

The named source artifact and repository are recorded in the **framework repository's own**
`docs/engineering/WORK_STATE.md` (framework-internal, not shipped) and in the git history of this
ADR — deliberately **not** by a relative link, which would resolve to the product repository's own
`WORK_STATE.md` and inherit nothing. This ADR and the shipped skill are **product-neutral**, so a
reader of a product repository never inherits another product's name.

## Known deviations from the source material

- **Frontmatter:** the source skill declared a tool-specific `triggers:` list. The `aef-orchestrator`
  skill itself does not declare one and uses the established convention exactly — `name` +
  `description` ending in "Use when ..." — to stay consistent with the other skills. The human entry
  point `aef-run-feature` **does** declare `triggers: ["user"]`, because it must not be auto-invoked;
  that key is the documented source for the generated Claude Code `disable-model-invocation: true`
  mapping and is never hand-copied.
- **Agent-host-specific terminology** (named managed subagent sessions, coordinator session titles,
  per-session token limits, a session dashboard) was replaced with the framework's own vocabulary:
  "specialist subagent sessions", routing classes, and the Manager.
- **Design-tool specifics and the source product's visual-evidence checklist** were generalized to
  "the project's canonical visual authority" plus a categorized mismatch list, with an explicit
  instruction not to claim pixel-diff automation the project does not have.
