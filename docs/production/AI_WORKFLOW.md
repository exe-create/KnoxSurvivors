<!-- modforge-doc
authority: canonical
load: always
purpose: canonical AI/tool routing workflow
-->

# Knox Survivors — AI development workflow

Updated: 2026-09-30

## Goal

Make one developer operate like a coherent small studio without turning Knox into disconnected AI-generated patches.

The production loop is:

**capture → establish current truth → scope → assign one owner → implement → independent review → validate → record evidence → sync state → choose next work**

## Non-negotiable coherence rules

1. **One active implementation owner per task/bug ID.** Subagents may research, plan, inspect, or review, but dependent edits should not be split across competing agents.
2. **One durable source for each fact.** Active work lives in `WORK_QUEUE.md`; confirmed defects in `BUGS.md`; settled decisions in `DECISIONS.md`. `.modforge/PROJECT_STATE.md` is generated.
3. **Update existing records before creating anything new.** Progress, support evidence, scope changes, and completion evidence belong in the existing canonical task/bug/decision/current-state sections. Do not create duplicate plans, status snapshots, bug ledgers, or release documents to avoid updating the owner record.
4. **No opportunistic scope creep.** If an agent finds adjacent work that is not required to complete the current item, record/triage it instead of silently fixing it.
5. **Escalate by boundary, not by frustration.** Narrow reproducible bugs stay in the budget lane. Persistence/identity/lifecycle/architecture/cross-system work moves to Codex.
6. **Evidence changes status.** Code existing is not the same as offline verified, live verified, or release ready.
7. **Deferred live tests are tracked dependencies, not universal blockers.** Continue independent mechanics when the offline evidence and architecture boundary are strong enough, while keeping the live scenario open and clearly unverified. Do not advance the affected release gate or claim native behavior until the live test passes.
8. **Use the real game boundary.** Prefer Project Zomboid's real APIs, native systems, assets, items, actions, resources, and runtime state. When behavior is unknown, investigate from exact source/runtime evidence and careful reverse engineering rather than fabricating success or building an unsupported parallel simulation.
9. **No agent creates work merely to stay busy.** When there is no approved actionable item, consult the roadmap/milestones and relevant design references before proposing the next item; return unresolved product choices to the Boss/owner.

## Shared documentation and context routing

Codex, OpenCode, and ModForge use the same repository records. They must expose
the same production/design/testing map to their agents, but they should load
documents lazily to control context size and usage.

Always establish current truth from:

`AGENTS.md` → `docs/production/PROJECT.md` → `CURRENT_STATE.md` →
`WORK_QUEUE.md` → `BUGS.md` → `DECISIONS.md`.

Load `QA_RELEASE.md` and `DEVELOPMENT_TESTING.md` when validation or release
confidence is involved. Load `FEATURE_SPEC.md` and `ARCHITECTURE.md` when the
implementation boundary requires them. Load `ROADMAP.md`, `MILESTONES.md`,
`docs/design/README.md`, the relevant design intake/inspiration notes, and
research history when deciding what to start next or resolving an unknown—not
as routine context. Load `SUPPORT_AND_TRIAGE.md` for pasted player/tester
reports and `COLLABORATION.md` for translator/external-author conversations.

The active owner may read the exact source, tests, runtime evidence, or design
reference needed for the task. No tool should preload the entire repository,
all historical documents, or all logs.

## Keeping production records synchronized

After meaningful work, update the existing owner record in the same cycle:

- implementation/evidence → `WORK_QUEUE.md` or `BUGS.md`;
- current position or blocked dependency → `CURRENT_STATE.md`;
- settled product/architecture choice → `DECISIONS.md`;
- phase/order change → `ROADMAP.md` and, when relevant, `MILESTONES.md`;
- acceptance/release evidence change → `QA_RELEASE.md`;
- tester/player report → `SUPPORT_AND_TRIAGE.md`, then the linked bug/task;
- collaborator conversation or delivered work → `COLLABORATION.md` and linked bug/task;
- design/reference decision → relevant `docs/design/` record plus `DECISIONS.md` or `ROADMAP.md`.

Update only when the new evidence or decision supports it. Do not create a new
status, roadmap, bug, tester, or collaboration document just to avoid updating
the canonical record. `.modforge/PROJECT_STATE.md` remains generated.

## ModForge — optional production desk

ModForge is an optional local coordination and indexing layer. When it is open,
it may automatically sync the repository on project open, watched canonical-file
changes, and the configured fallback interval without spending model tokens just
to detect changes. When it is not installed, open, or available, the repository
workflow below remains complete using `AGENTS.md`, Git, and `docs/production/`.

ModForge owns:

- project overview/current state;
- roadmap and milestones;
- task/bug board synchronized with canonical repository sections;
- decision log and documentation authority index;
- collaboration/credits/support intake;
- evidence/completion state;
- cheap planning/research/review agents;
- workflow construction and tool routing;
- focused handoff packets for Codex, OpenCode, and ChatGPT Consultant use;
- Design Inbox/reference provenance before ideas become roadmap work;
- Model Center role profiles and explicit Free / Subscription Allowance / Paid usage lanes;
- source-write protection and Change Ledger notes when ModForge itself is deliberately allowed to edit repository files.

For imported production tasks/bugs, ModForge is a **view/editor of repository truth**, not an independent second task database. Safe UI changes may write through to the canonical section when there is no external-edit conflict. Codex/OpenCode may update the same section directly without waiting for ModForge; repository truth wins on the next sync.

## Implementation authority hierarchy

For an approved work item, authority is deliberately separated:

1. **Human owner:** final product, reputation, release, public claims, permissions, and save-breaking decisions.
2. **Codex / assigned Boss:** technical implementation authority for engineering assigned to Codex; normally GPT-6 Luna, with Sol/Astra only through the explicit escalation rules below.
3. **OpenCode:** technical implementation authority for bounded budget/scoped engineering assigned to OpenCode.
4. **ModForge / Boss / Planner:** production coordination, scope, priority, constraints, evidence, and routing. They do not rewrite the active implementer's approach just to express a different preference.
5. **Cheap subagents:** research, scoping, cleanup, independent review, and evidence support only unless explicitly promoted.

## Cost-controlled boss and worker lanes

Use one boss lane for a workstream. GPT-6 Luna is the default cost-controlled
Boss for normal development and coordination. GPT-5.6 Terra is the normal
support/Grunt and independent-review lane. GPT-5.6 Luna is the Planner lane.
Sol 5.6 low is an exceptional support/Boss escalation, and Astra medium is the
final high-tier lane for last resort, whole-project review, or major new
mechanic/system expansion. Sol and Astra must never be routine workers.

### Escalation ladder

Escalation is evidence-gated and must not happen merely because a task is
interesting or difficult:

1. Luna/Terra/OpenCode owns the bounded task and makes at least two documented
   focused attempts, unless the first investigation proves the boundary is
   immediately architecture-sensitive.
2. If the same confirmed issue remains unresolved, the Boss may invoke the
   `.codex/agents/sol-escalation.toml` lane (`gpt-5.6-sol`, low reasoning) for
   one focused escalation attempt. It must read the previous attempts and may
   not restart or broaden the work.
3. If Sol also fails after one or two focused approaches, the Boss may invoke
   `.codex/agents/astra-final.toml` (`gpt-6-astra`, medium reasoning) exactly
   once as the final model escalation.
4. If Astra cannot resolve it, stop and return the issue to the human owner or
   leave it blocked with evidence. Do not loop, silently spend more premium
   usage, or claim success.

Each escalation record must include the task/bug ID, attempts already made,
why they failed, exact remaining uncertainty, model lane requested, and a
bounded acceptance condition. Routine planning, documentation, testing,
cleanup, and lookup work never qualifies for this ladder.

Use Luna first for planning, file scoping, documentation maintenance, test reporting, and narrow lookups. Use Terra for independent review, compatibility checks, bounded implementation, or support work that needs more judgment than routine Luna work. Grunt and Planner remain the cheap support roles. Use one support worker at a time by default. For any task classified as planning, lookup, cleanup, test collection, evidence gathering, documentation maintenance, or independent review, assign the appropriate cheap worker first; the boss should only integrate/review the result rather than doing repetitive work itself.

The free OpenCode catalog remains the default for ModForge/OpenCode roles. A free catalog entry is not permission to select a premium Codex model as a subagent, and quota failure must never trigger a paid or subscription-backed fallback.

If an implementation conflicts with recorded project vision, architecture ownership, task scope, or evidence requirements, ModForge/Boss can stop/escalate it. Otherwise the assigned coding tool gets room to work coherently like the project's engineering department.

## Codex — implementation and escalation

Use the normal Luna Boss for:

- broad but bounded implementation;
- integration and stabilization across existing systems;
- focused debugging and research-backed fixes;
- coordinating cheap planning, evidence, review, and cleanup support.

Use Sol only for:

- a confirmed difficult issue that the Luna Boss/Terra support path has failed
  to resolve after repeated attempts;
- an explicit owner request for a higher-tier focused pass.

The following boundaries can justify an Astra escalation or explicit owner
assignment; they do not automatically select Astra or bypass the ladder:

- architecture-sensitive changes;
- persistence, identity, lifecycle, ownership, reconstruction;
- cross-system expansion;
- difficult engine/debugging work;
- broad required refactors;
- large release-hardening/reconciliation passes;
- difficult regressions whose first failing boundary spans multiple systems.

Normal Codex startup:

`AGENTS.md` → current production docs → generated project state → smallest relevant technical authority → Git status/diff.

The 2026-09-30 whole-project coherence pass is an explicitly owner-authorized
Astra exception. One Astra owner integrates the existing OpenCode diff and
cheap read-only planning/review; this does not change normal model routing.

The main Codex session normally runs on GPT-6 Luna for cost-controlled
development. GPT-5.6 Luna handles planning; GPT-5.6 Terra handles Grunt,
bounded support, evidence, and independent review. Sol and Astra are separate,
deliberate exceptions and are never routine subagents. The Boss should keep a
coherent workstream moving and delegate repetitive support instead of reducing
the session to many tiny passes.

## OpenCode — budget implementation/support department

Use OpenCode for:

- confirmed narrow bug fixes;
- small/medium scoped implementation;
- support/triage follow-up;
- compatibility investigation;
- cleanup and mechanical maintenance;
- translation/collaboration support;
- narrow review/research using local/free/cheap models.

OpenCode must stop and escalate instead of stretching a cheap patch when the work crosses persistence, survivor identity, lifecycle ownership, save migration, core architecture, or several coupled systems. OpenCode remains the implementation owner for its assigned bounded task; ModForge supplies the contract and records the result.

Project subagents live under `.opencode/agents/`. The repository default is now a project-local free-only OpenCode profile in `opencode.json`; role-specific free primary/fallback assignments live in `.modforge/free-models.json`. The owner may deliberately choose another provider outside that profile, but ModForge must never silently change the project to a subscription-backed or paid route.

OpenCode has two explicit local profiles: the default free lane in `opencode.free.json` and the opt-in OpenCode Go subscription lane in `opencode.go.json`. Start them with `scripts/start-opencode.ps1` or `scripts/start-opencode.ps1 -Profile go`. The Go lane uses the `opencode-go` provider only. OpenCode Go is separate from ChatGPT Go/Codex usage; the project must not represent one as the other.

## ModForge team roles

### Boss
Owns priorities, dependencies, blockers, project health, assignment, and handoffs. Protects the project vision; does not become the default coder.

### Planner
Turns an approved goal/bug into a bounded plan with dependencies, acceptance, validation, and stop/escalation conditions. Does not code or make final product/architecture decisions.

### Grunt
Cheap operations worker for lookups, file/task/doc maintenance, evidence gathering, cleanup, and mechanical support. No architecture decisions and no coding by default.

### Researcher
Answers one narrow technical/compatibility question, records evidence/uncertainty, and returns it to the active owner.

### QA Reviewer
Independently checks the requested scope, diff, regressions, evidence level, and release claims. Does not approve engine behavior without the required live evidence.

## Routing matrix

| Situation | Default route |
|---|---|
| unclear request / missing acceptance | Planner |
| narrow technical unknown | Researcher |
| narrow reproduced bug | OpenCode |
| small/medium isolated implementation | OpenCode |
| persistence/identity/lifecycle/ownership | Codex |
| cross-system feature/major expansion | Codex |
| difficult release reconciliation/hardening | Codex |
| product/public/collaboration permission decision | Boss prepares; human decides |
| release claim | QA Reviewer + evidence + human approval |
| community report | `SUPPORT_AND_TRIAGE.md` before coding |

## Handoff contract

Every implementation handoff should carry:

- stable task/bug ID;
- why the work matters now;
- exact allowed scope and explicit out-of-scope items;
- relevant decisions/architecture boundaries;
- acceptance criteria;
- validation plan/evidence level required;
- likely files/systems when known;
- stop/escalation conditions;
- current Git/repository state warning;
- instruction to return exact changed files/checks/unverified risks.

A handoff is not permission to clean unrelated code.

## Completion loop

1. Implementation owner returns result/evidence.
2. QA Reviewer checks task contract and scope drift.
3. Required focused/full/live checks run.
4. Only then does task/bug status advance.
5. Existing canonical repository section is updated in place (directly or by ModForge write-through).
6. If ModForge is active, it re-indexes and regenerates `.modforge/PROJECT_STATE.md`.
7. Boss/owner chooses the next approved item from the refreshed canonical state.

## Standalone Codex/OpenCode path

ModForge is not a prerequisite. A normal session can use this compact loop:

1. Read `AGENTS.md`, then `PROJECT.md`, `CURRENT_STATE.md`, `WORK_QUEUE.md`,
   `BUGS.md` and `DECISIONS.md`.
2. Check `git status`/`git diff` and identify the active task, bug, or explicit
   owner request.
3. Load only the technical authority relevant to the subsystem.
4. Implement with Codex or OpenCode according to the routing rules above.
5. Run focused validation, record exact evidence in the existing canonical
   record, and leave any live-only boundary open.

No ModForge task card, generated state file, Inbox item, or handoff UI is needed
to perform this path. Those are optional conveniences, not project authority.

## Context rule

Do not dump the entire repository or `FEATURE_AUDIT.md` into routine model calls. Start with the short production path, then lazy-load only the technical/history material required for the current boundary.


## Usage exhaustion / model failure

AI usage limits must never change project truth by themselves. If Codex/OpenCode/a cloud model runs out of quota or becomes unavailable:

1. stop at the current recorded boundary;
2. do not mark the task done or advance release status;
3. preserve completed diffs/tests/evidence;
4. switch only to a deliberately configured free/local fallback when it is capable of the remaining work; otherwise leave the item open/paused;
5. never silently enable paid API usage or broaden permissions just to keep an agent running;
6. when the stronger implementation lane becomes available again, resume from the canonical task, Git diff, and recorded evidence rather than restarting from memory.

For heavy architecture work, a weak fallback should support research/scoping/review rather than taking over an implementation it cannot safely own.

## Debug / console evidence

Do **not** ingest logs during normal planning or every coding session. Logs are a diagnostic tool, not project memory.

Use them only when the active bug/test/runtime boundary calls for them or the owner says a log contains the symptom. Start with the smallest recent slice around the reproduction, extract the useful evidence into `BUGS.md` / the active task, then return to source/tests. Old bulk logs and `dev-runs` stay excluded from routine ModForge context.

## Model/usage lanes

ModForge separates model usage into three user-visible lanes:

1. **Free/local** — default and preferred for routine Boss/Planner/Grunt/Research/QA work.
2. **Subscription allowance** — optional; use spare included usage from Codex/ChatGPT-plan-backed routes or OpenCode models the owner explicitly marks as subscription-backed. This is for times when stronger planning/research is worth spending weekly/session allowance.
3. **Paid/metered API** — separate explicit opt-in. Never enabled automatically by quota failure.

Quota exhaustion stops cleanly or uses an explicitly configured safe free fallback. It never promotes a paid route or a weak model into risky architecture work without approval.

## Design Inbox → production work

Game inspiration, owner notes, community suggestions, PDFs/transcripts/screenshots, and mechanic comparisons start as **design/reference intake**, not implementation. Boss/Planner/Researcher may organize and analyze them, but only the owner can approve the resulting direction. Promoted material is written under `docs/design/` with provenance, then reconciled into decisions/roadmap before implementation work exists.

## ModForge file writes

Routine ModForge behavior should not edit Knox source. Managed production/design records may be updated; all other repository writes require explicit per-project owner approval. Every ModForge file write produces a local `.modforge/changes/CHANGE_LEDGER.md` entry so Codex/OpenCode can inspect the same rationale/task context before continuing. Git diff is the exact authority for what changed.
