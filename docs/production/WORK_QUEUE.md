<!-- modforge-doc
authority: canonical
load: always
purpose: canonical active work queue
-->

# Knox Survivors — active production work queue

Updated: 2026-10-01

The sections below are deliberately machine-friendly so ModForge can populate its task board automatically. Keep confirmed bugs in `BUGS.md` instead of hiding them here.

## KS-PROD-001 — Reconcile the current worktree with repository baseline
Status: done
Priority: critical
Owner: Codex
Type: release

### Goal
Identify the GitHub baseline and make the post-main worktree understandable to downstream verification.

### Result
- Commit `163b789a2564ee626bc9d5acdad46674623c25b8` verified as the current GitHub `main` and local checkout HEAD, directly based on prior baseline `7f56dcb846f107a4c226770b3ca72fe21232235b`.
- The implementation baseline was verified at the current HEAD; later coordination/documentation changes remain visible as a separate uncommitted layer and do not change the implementation claim.
- Current source/test changes grouped by subsystem in `CURRENT_STATE.md`.
- Old overlapping plan/release documents consolidated so they no longer compete with current production truth.

### Validation
Repository status/diff, connected GitHub baseline, current source/test inventory and retained historical evidence.

### Definition of Done
Downstream QA can verify the exact current implementation without relying on a stale release snapshot.

## KS-PROD-002 — Run focused verification for all release-bound changed subsystems
Status: done
Priority: critical
Owner: Codex / OpenCode
Type: qa

### Goal
Prove each changed subsystem passes its cheapest meaningful focused checks before the full gate.

### Scope
Use the tests/verifiers already associated with the changed files. OpenCode may handle narrow failures; Codex owns cross-system or architecture-sensitive failures.

### Acceptance
- Focused checks pass for every release-bound subsystem, or a confirmed failure is converted to a tracked bug.
- No failure is hidden by retries, fake fixtures, or wording changes.

### Validation
Candidate: `163b789a2564ee626bc9d5acdad46674623c25b8`; focused evidence applies to that candidate implementation baseline. Current documentation/configuration edits are separate and remain subject to Git review.

Focused command for each listed Lua test:

```powershell
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tools/<test>.lua (Get-Location).Path
```

| Changed subsystem | Focused tests | Result | Remaining live-only boundary |
|---|---|---:|---|
| Base/storage/organize | `test-base-storage.lua`, `test-base-organize-wiring.lua`, `test-base-storage-menu.lua`, `test-base-setup-ui.lua`, `test-base-ambient-life.lua`, `test-base-supply-planner.lua`, `test-duty-schedule.lua`, `test-multi-base.lua` | 8/8 passed | Native jobs, real storage/item transfer, pathing and resource consumption |
| Companion orders/UI | `test-order-routing.lua`, `test-radial-orders.lua`, `test-notebook-away-ownership.lua`, `test-notebook-refresh.lua`, `test-speech-indicators.lua`, `test-survivor-card-ui.lua`, `test-survivor-view-model.lua` | 7/7 passed | Native order execution, interruption recovery and rendered UI at target scales |
| Persistence/autonomy | `test-survivor-lifecycle-policy.lua`, `test-unloaded-survival.lua` | 2/2 passed | Real save/reload, hibernation/rematerialization and engine lifecycle |
| Events/world continuity | `test-event-runtime.lua`, `test-knox-events.lua`, `test-world-traces.lua` | 3/3 passed | Live loaded/unloaded event behavior and native world effects |
| Threat awareness | `test-zombie-awareness.lua` | 1/1 passed | Native detection, combat and damage behavior |

Total changed-test batch: **21/21 passed, 0 failed**. The same 2026-09-27
read-only audit also passed **112/112** Lua 5.1 syntax checks, **174/174**
repository Lua regression scripts, and `gradlew.bat :java:check` (16 successful
tasks). These are offline checks using test fixtures/doubles; they do not prove
the live-only boundaries above. Static review separately established
`BUG-KS-001`, `BUG-KS-002`, and `BUG-KS-003`; green fixtures do not override
those source/architecture failures.

### Definition of Done
The complete changed-test set for the exact candidate is confirmed and the
source-confirmed audit failures are represented by explicit bug records. The
full offline/package gate and live Build 42 acceptance remain separate queue
items and are not implied by this completion.

## KS-PROD-003 — Run the full offline candidate gate
Status: done
Priority: high
Owner: Codex
Type: release

### Goal
Run the complete syntax/regression/Java/build/package verification on the same candidate revision.

### Acceptance
- Full offline suite completes without unexplained failure.
- Exact check counts, revision/worktree state, and packaging result are recorded.

### Validation
On 2026-09-29 the exact Survivors source candidate `e93ed2655470212a6e78305171ccff63f7893c58` passed `tools/verify.ps1`: 112 Lua sources, 178 Lua regression scripts, 291 checks, 0 failures, including the Java check/build. `gradlew.bat prepareWorkshopUpload` staged the existing item `3749727604`; the PZ native payload validator passed the staged Contents layout, metadata, preview, Bridge descriptor, single agent JAR, checksum and premain checks (126 staged files). At that time, the then-current release-document changes did not touch gameplay source. The current worktree has since accumulated uncommitted gameplay packages and is no longer this exact candidate. A fresh dirty-tree Lua-only gate on 2026-09-30 passed 112 sources, 182 scripts, 294 checks, 0 failed; Java and payload gates remain scoped to `e93ed26` until rerun on the later candidate. Steam upload/download and live gameplay acceptance remain separate gates.

On 2026-09-28, `tools/verify.ps1` (full, Java included) checked 112 Lua sources and ran 177
Lua scripts (290 checks, 0 failed, including `java-check-build`) on worktree `decbda5`
plus 5 uncommitted files (`KS_CompanionVehicles.lua`, `KS_SurvivorAutonomyController.lua`,
`BUGS.md`, `CURRENT_STATE.md`, `WORK_QUEUE.md`). Test scripts are intentionally local-only
(`.gitignore`, owner commit `1d10f42`), so the harness itself is not part of the published
candidate. `verify.ps1` covers syntax, regression, and Java check/build only — Workshop
staging/package verification is not part of that tool and remains outstanding, as does a
clean-tree rerun. Prior partial record below is superseded by this run for Lua/Java scope.

On 2026-09-27, `tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 174
Lua scripts (286 checks, 0 failed) against the current working tree. This is
partial offline evidence only; Java, staging/package verification, and the full
candidate gate remain outstanding. BUG-KS-001's six focused event/trace tests
also passed, but native raid behavior remains live-unverified. Follow
`docs/DEVELOPMENT_TESTING.md` and the supported build/release tooling.

### Definition of Done
A fresh offline evidence record exists for the exact candidate.

## KS-PROD-008 — Complete and connect the implemented survivor systems
Status: in_progress
Priority: high
Owner: Codex / OpenCode
Type: development

### Goal
Turn the substantial existing implementation into one coherent, reliable,
believable and playable survivor loop without creating overlapping owners or
parallel replacement systems.

### Scope
Work in dependency order: identity/persistence/lifecycle and off-screen truth;
survivor brains/autonomy/claims; movement/pathing/native action interruption;
combat/threat awareness; storage/base/jobs/supplies; companions/orders/UI;
purposeful implemented events/factions/world life; vehicle readiness/driving per
D-019 and Slice J; launcher/runtime compatibility
where required; then performance, balanced defaults and player customization.

### Acceptance
- Existing systems connect through their documented authoritative owners.
- Confirmed failures are fixed at the first failing boundary or tracked in
  `BUGS.md` with evidence.
- No fabricated items, world effects, bodies, completion or test evidence.
- Off-screen continuity is real-time and cheaper, never faked: same needs/travel/rest progression, real supply consumption, deterministic history, and idempotent loaded reconcile per D-016.
- Implemented experimental systems with a real purpose are completed safely;
  unstarted feature families remain deferred.
- Focused and required live evidence is recorded separately and honestly.

### Validation
Use the focused tests listed in KS-PROD-002, the subsystem authorities in
`docs/ARCHITECTURE.md` and `docs/DEVELOPMENT_TESTING.md`, fresh-save Build 42
acceptance, and launcher/runtime checks when the boundary crosses repositories.

The confirmed detached-companion stale-shell defect is tracked as
`BUG-KS-008`. Its bounded lifecycle correction has focused and full offline Lua
evidence recorded in `BUGS.md`; the broader KS-PROD-008 loop remains open. Live
Build 42 replay must cover recognized vault/climb states, cell-edge/streaming
gaps, vehicle occupancy, prolonged unexplained detachment, dismissal,
save/reload, and rematerialization before this boundary is considered live
verified.

### Completion slices (one owner, one acceptance each — no parallel systems)

Work slices in dependency order. A slice is done only when its offline tests
pass on the exact candidate AND its live replay passes (or its failure becomes
a tracked bug). Slices map to `ROADMAP.md` Phase 2 and the dossiers in
`docs/design/NPC_SYSTEM_INSPIRATION.md`; they create no new task IDs.

2026-09-28 traversal integration: claimed base jobs now route entry-related
failure on assigned-storage pickup through the existing window/door recovery
owner. Quiet entry and permitted forced entry retain the exact task supply
lease and resume the same approach; unavailable entry fails through existing
task cleanup. Focused `test-base-task-supply-entry.lua` plus entry, action
lifecycle, task validation, arrival, claim and inventory cleanup checks pass.
The full offline gate passed 112 Lua sources, 178 regression scripts, 290
checks and 0 failures. The focused script is local under ignored `tools/`
policy. BUG-KS-033 records the offline boundary. Build 42 still needs native
door/window traversal, actual container receipt, interruption and save/reload.
Public corpse/fence and general locked-door reports remain unconfirmed live
cases.

- **Slice A — Identity/lifecycle/off-screen truth.** Owners: `KS_Persistence.lua`, lifecycle policy, runtime, unloaded ledger, storylets, traces. Offline: lifecycle-policy, persistence-recovery, unloaded-survival/group/base-return, event-runtime, world-trace tests. Live: save/reload identity/inventory/orders, hibernation/rematerialization with no duplicates, loaded→unloaded→loaded travel with real consumption and retryable traces. Bugs: `BUG-KS-001`, `BUG-KS-002`, `BUG-KS-008`, `BUG-KS-024`. Rule: D-016 continuous-real, never faked.
- **Slice B — Brains/autonomy/claims.** Owners: autonomy controller, needs/loot/medical probes, task board, duty simulation. Offline: autonomy, needs, work-priority, anti-flap, group support/scavenge, behavior-integration tests; the dynamic organizer-duty regression confirms leaving base duty, disabling hauling, or reassignment cancels its action/route once and releases item/container claims. The focused base-life set passed 8/8 and the full offline gate passed 112 Lua sources, 176 scripts, 288 checks, 0 failures. Live: full-day base observation — needs, interruption, resumption, no controller fights, idle residents choose base-life. Bugs: `BUG-KS-013`, `BUG-KS-025`.
- **Slice C — Movement/pathing/native actions.** Owners: Java traversal runtime, cohesion, formation follow, companion service, action adapters. Offline: formation, traversal, command, order, door-discipline tests. Live: leader-plus-two-followers through travel, door/fence, interruption, recovery; one native work action and one danger-interrupted action with real world change. Bugs: `BUG-KS-011`, `BUG-KS-019`, `BUG-KS-028`.
- **Slice D — Combat/threat/retreat/firearms.** Owners: awareness, threat classifier, combat/firearm support. Offline: zombie-awareness, combat-intelligence, formation, threat-classifier tests. Live: one-zombie hold, small-group hold, overwhelming-group retreat through a viable lane and recovery; hostile duel plus bystander check with real ammo/health evidence. Bugs: `BUG-KS-009`, `BUG-KS-012`, `BUG-KS-029`. Diagnostic update 2026-09-28 (`dev-runs/20260928-021135`): no `LightingJNI` visibility-write failure appears in the console extract; other encounter logs show native zombie damage, but `combat_group_horde` remained `PARTIAL` (15 survivor hits, zero zombie damage/kills). Do not repeat the base-danger source audit absent new evidence; offline arbitration is covered. Keep the one-zombie/small-group native combat replay in live acceptance.
- `test-combat-intelligence.lua` drives a base resident through the scheduled danger scan with an active organizer action: the combat bridge starts once, the action is cleared, and the claimed task is retained with `combat_interrupt`. Offline arbitration is covered; native damage, retreat and recovery remain live-only.
- 2026-09-29 retreat continuity extension: base residents now use the existing threat-weighted flee admission and shared movement route when pressure/condition warrants escape. Direct player companions remain excluded. A threatened resident suspends its current task without releasing the task-board claim, releases temporary task transfer reservations, and returns through the existing two-safe-scan completion and base arbitration. The active supply-run marker/order/carried real item is preserved while temporary search reservations are released. `test-combat-intelligence.lua` covers base-task retention, controller continuation despite base assignment, safe-scan completion, non-overwhelming one-zombie restraint, and supply-run continuity. Focused combat, formation, claim-suspension, base-duty, task-validation, auto-scavenge, supply-planner, and group-scavenge checks passed. Live Build 42 still must verify one zombie/small group remain a fight/hold when appropriate, an overwhelming threat produces one viable retreat and safe return, a base job resumes afterward, and an interrupted supply carrier deposits/reassesses after saving/reloading. No native combat, pathing, or persistence result is claimed.
- Broad verification after the retreat extension: `tools/verify.ps1 -SkipJava` checked **112 Lua sources**, ran **178 regression scripts**, and reported **290 checks, 0 failures**. `git diff --check` passed. Focused test edits remain local under ignored `tools/` policy.
- **Slice E — Storage/organizer/supplies.** Owners: base storage, organize, supply planner, context menu, manager categories. Offline: base-storage/menu/organize/supply-routing/planner/cleanup/inventory tests. Live: typed deposit, General fallback,
logs/firewood routing, loot→storage→need loop with identity/counts across save/reload. Native vehicle parts
(`VehicleMaintenance`: tires, batteries, brakes, gas tanks per installed Build 42 item scripts) now resolve to the
Materials role through the existing building matcher — no new role, registry, or stockpile owner; mechanic hand tools
were already Tools. A confirmed supply-claim gap is tracked as `BUG-KS-031`: collection used to terminate the
durable run before storage receipt. The existing autonomy owner now holds the run and return intent through
the typed native transfer, and releases it only when destination receipt is confirmed. Focused
`test-base-auto-scavenge.lua`, `test-base-needs.lua`, and `test-inventory-cleanup.lua` plus the full offline gate
passed (112 Lua sources, 177 scripts, 289 checks, 0 failed). Native transfer, container capacity/weight, and
save/reload identity remain live-only. Bugs: `BUG-KS-015`, `BUG-KS-016`, `BUG-KS-031`.
- **Slice F — Bases/jobs/duties.** Owners: base manager/jobs/task board/needs, zone executors, duty scheduling. Offline: existing base-job/ambient/needs/duty/task-board tests plus dynamic watchdog coverage. `test-base-leisure-routing.lua` now drives `tick` through stalled `BASE_PATROL`, `BASE_RETURN`, and `MOVING_TO_REST`: the first two cancel through `handleBaseMovementFailure` and release their ambient claim with backoff; rest uses the existing ground-rest action and releases its furniture claim. The ordinary base-task loop now also yields to actionable urgent self-care on a 90-tick check while preserving the task claim and routing cancellation/transfer release through existing owners. `test-claim-suspend.lua` covers active work, task action, supply movement/transfer, below-threshold continuation, specialized guard/cook ownership, verified eating, and resumption. The focused connected suite passed; `tools/verify.ps1 -SkipJava` passed 112 Lua files, 177 scripts, 289 checks, 0 failures. Test changes are local under ignored `tools/` policy and are not tracked Git changes. Live: full-day two-resident base observation; stalled chair/patrol/return recovery; hungry residents during ordinary work and supply transfer with real assigned food, native eating, same-task resumption and honest unavailable-food behavior; one supplied job end-to-end; active-organizer duty removal/hauling disable/base reassignment; two-window barricade sequence; territory-corner save/reload. Bugs: `BUG-KS-013`, `BUG-KS-017`, `BUG-KS-018`, `BUG-KS-020`.

2026-09-28 completion-authority correction (`BUG-KS-034`): native base-job
executors already verify the world result, but a stale/revoked claim could make
the task board reject the final finish after the controller had emitted success
and completion speech. The existing board response now gates task success
diagnostics, automatic-work pacing, and completion speech. Rejection records a
distinct bounded failure and releases the stale controller's transient task
and supply leases; it does not mutate another owner's claim or undo a real
world result. Focused `test-base-task-validation.lua`,
`test-base-action-lifecycle.lua`, `test-base-task-board.lua`,
`test-companion-base-domain.lua`, `test-base-repairs.lua`,
`test-base-farming.lua`, `test-base-woodcutting.lua`, and
`test-base-corpse-handling.lua` all passed. The full
`tools/verify.ps1 -SkipJava` run checked **112 Lua sources**, **178 regression
scripts**, **290 checks**, **0 failures**; the updated test remains local under
ignored `tools/` policy. `git diff --check` passed. Build 42 must still replay
ordinary native job completion and a claim revoked during/after the action,
including feedback, next activity and save/reload. No native action or
save/reload result is claimed from these offline fixtures.
- **Slice G — Companions/orders/UI.** Owners: companion service, party commands, order catalog/signals, radial, HUD, card, notebook, map overlay, speech indicators. Offline: order-routing, radial, notebook, speech, card, view-model, map tests. The existing survivor snapshot already supplied persisted life-purpose, relationship meeting count, and bounded newest-first memory to the Card, but those fields were dropped from the player-facing detail. The Card now shows purpose, meeting count, and up to three sanitized history summaries/details without reading raw persistence; list views remain compact and the shared view-model stays authoritative. Focused view-model, Card UI, Notebook refresh/mission ownership, offscreen-story, relationship-coherence, and survivor-needs checks passed; full offline gate on 2026-09-28: 112 Lua sources, 177 regression scripts, 289 checks, 0 failures. The new/updated focused script remains local under ignored `tools/` per repository policy. This cycle corrected trust-only gifts by connecting `Give Item` to explicit one-way mode in the existing trade UI/action: real item eligibility, recipient reserve checks, capacity, transfer receipt, rollback, capture, then the existing gift contribution reward. `Give Money` stays absent as an abstract account action; tangible supported currency objects use the real-item path. `BUG-KS-032` and D-020 record the consequence rule. Focused social-act, valuation, action, and UI regressions plus the full gate passed at 112 Lua sources, 177 scripts, 289 checks, 0 failures. Focused test edits remain local under ignored `tools/` policy. Live: order/interruption/recovery, speech readability plus right-click menus, UI at small/large scales; inspect Card history text clipping/scrolling at both scales and replay real gift/barter receipt, capacity, cancellation, and save/reload. Bugs: `BUG-KS-008`, `BUG-KS-010`, `BUG-KS-021`, `BUG-KS-032`.
- **Slice H — Events/factions/world life.** Owners: event runtime, Knox events, factions/camps/scouting, group scavenge, away-team executor, storylets. Offline: population, origin, faction-development, event-entry, group tests. Live: solo→group→faction→settlement observable; shortage→mission→return→deposit→memory closes; raids only with loaded outcomes. Bugs: `BUG-KS-001`, `BUG-KS-024`, `BUG-KS-026`. Deferred per D-017: full politics, creator, broad raids.

2026-09-29 KS-PROD-008 integration: faction-owned bases now elect an available
resident with matching persisted faction identity for an actual storage
shortage, using the existing durable supply-run and receipt-gated deposit path.
Generic group-sortie members are excluded through the existing read-only lease
owner; specialized residents retain their duty. Player-base opt-in is unchanged.
Focused `test-base-auto-scavenge.lua`, `test-group-scavenge.lua`,
`test-base-supply-planner.lua`, `test-base-needs.lua`,
`test-inventory-cleanup.lua`, and `test-base-supply-routing.lua` passed. The
full offline gate passed at 112 Lua sources, 178 scripts, 290 checks, 0
failures; `git diff --check` is recorded at final validation. Focused tests
remain local under ignored `tools/` policy. Live: faction-owned base with a
real shortage, matching resident versus specialized/wrong-faction residents,
existing group sortie, real pickup/return/native deposit, shortage
reassessment, and save/reload. D-022 records the owner rule; BUG-KS-025 remains
reported for broader native decision quality.

2026-09-29 loaded/offscreen social continuity: `KS_OffscreenStories` already
persists pair-specific pending meeting intent, but the loaded relationship
coordinator consumed it when merely selecting an encounter. It now carries the
matching intent token through request, approach, and greeting, consumes only
after a loaded outcome is accepted, and expires matching stale intent after the
existing 72-hour freshness window. Aborted attempts preserve the offscreen
intent; failed hostile handoff uses the existing short encounter cooldown so
the same attempt is not re-elected every tick. Pair-scoped cleanup cannot erase
a newer intent for another partner. Focused encounter, offscreen-story,
recount, and relationship-coherence checks passed; broad offline verification
checked 112 Lua sources, 178 scripts, 290 checks, 0 failures. The focused
regression remains local under ignored `tools/` policy. Build 42 still needs an
offscreen encounter followed by loaded approach interruption, later recontact,
finalized greeting/decline/join/hostile handoff, and save/reload continuity;
offline tests do not prove native approach or robbery/combat outcomes.

2026-09-29 encounter-to-faction admission: review confirmed the successful
encounter → canonical group membership → faction resident duty → runtime
formation path is already connected. It exposed one failure handoff:
`addTravelGroupMember()` mutated group membership and allied relationships
before checking whether `addFactionMember()` accepted the survivor. Faction
admission now succeeds first or returns a rejection without partial group,
roster, affiliation, or relationship changes. Successful home-base admission
still uses the existing resident lifecycle and formation owners. Focused
faction-persistence, encounter, formation, unloaded-group, relationship, and
faction-development tests passed; the offline gate checked 112 Lua sources,
178 regression scripts, 290 checks, 0 failures. Build 42 accepted recruitment,
formation/base duty, and save/reload remain live acceptance.
- **Slice I — Performance/defaults/customization.** Owners: settings, schedulers,
population budgets. Offline: full gate counts on exact candidate. Live: frame-time at configured population plus
crowded job/combat; rarity modes direction (Lonely/Balanced/Lively) scoped as future work item. Rule: D-015/D-017 —
conservative defaults, no ownership bypasses.
- **Slice J — Vehicle readiness/driving (D-019).** Owners: `KS_NpcVehicleTravel.lua` (shared admission verdict),
`KS_CompanionVehicles.lua` (drive admission), `KS_VehicleNavigation.lua` (geometry/routing, unchanged),
`KS_BaseStorage.lua` Materials routing for parts. Offline: shared ready/low-fuel/locked/unknown matrix on both the
travel path and the module-absent fallback; no boarding or `driveTo` on rejection; no movement, routing, formation,
leader-order, away-team, lifecycle, or persistence owner changes. Boarding yields to retreat-worthy danger and
critical needs through the existing lease owner (rearming next-tick arbitration); refused abort-time exits retry
boundedly once stopped; arrival exits each passenger exactly once with the driver explicitly staying seated and one
truthful feed line; unrecoverable exits report once. Full gate 112/177/289, 0 failed. Group boarding
commits an explicit per-member roster attached to the driver run; every abort/arrival rolls it back at once (pending
leases release immediately, seated passengers get native exit, overflow stays unclaimed); `stopDriver` only clears a
present run key. Duty/order changes arbitrate vehicle leases through the existing interruption owner (lease-free
survivors untouched); every `cancel` settles the attached roster except player takeover, which preserves riders.
Live: real parked
vehicles across engine/fuel/damage/lock/seat/occupancy/towing states plus one valid fueled vehicle; multi-car driving
runs, convoy spacing, control release, and native part consumption are separate future gates. Deferred: hotwiring/keys, forced entry,
player-assigned vehicle work orders with HP thresholds, specialist workstations, vehicle-work UI. Bugs: `BUG-KS-030`.

Routing per slice: narrow selector/matcher/schedule/retry fixes → OpenCode; persistence/identity/lifecycle/cross-system → Codex; vision/scope/release → Boss/owner.

### Whole-project coherence disposition — 2026-09-30

This explicitly owner-authorized Astra pass reviews the existing dirty worktree
at HEAD `624caac`, including OpenCode's BUG-KS-039 correction. It does not turn
historical package evidence into current acceptance. The Lua-only gate passed
112 source syntax checks plus 182 regression scripts (294 checks, zero failures).
Local regression scripts remain ignored. No game launch, Java, external runtime,
Workshop staging or live acceptance occurred.

| Connected boundary | Existing owners and reviewed contract | Disposition / next evidence |
|---|---|---|
| Social → memory → membership | `KS_SurvivorRelationships` finalizes loaded outcomes; `KS_OffscreenStories.recordLoadedEncounter` writes canonical personal history; persistence admits membership before a joined outcome. Pending meets survive until loaded acceptance. | Reviewed connected offline; relationship/coherence, offscreen-meets/stories tests pass. Real meeting/join/decline and reload remain live. BUG-KS-032/036/037/038. |
| Membership → directives → formation → succession | Persistence owns affiliation/leader repair; relationship refresh and companion service project the roster; the autonomy controller owns movement. Player-party destination remains session-only under D-025. | Reviewed connected offline; relationship-coherence, group-runtime-refresh, unloaded-groups and party/formation checks pass. Leader loss, native following and interruption remain live. BUG-KS-028. |
| UI → duty/schedule → task → claims/actions → reassessment | Notebook passes the selected owned base to companion service; persistence validates/writes; runtime notifies the same controller. `KS_BaseJobs` selects; task board/persistence own claims; controller and native actions own physical work and verified completion. | Reviewed connected offline, **BUG-KS-013 remains a valid high-priority live failure**. UI corrections do not prove visible work. First reproduce selected resident/base save, then one supplied job and one blocked case; use the first failing transition. |
| Shortage → supply run → return → receipt | Base needs/supply planner elect through existing claims; controller holds the persisted run and exact native transfer until storage receipt, then releases/reassesses. | Reviewed connected offline; base-auto-scavenge, supply routing/planner, task-board and inventory tests pass. Native loot/deposit/resource identity remains live. BUG-KS-015/031/035. |
| Threat → retreat → recovery → resume | Existing perception/controller arbitrate retreat; base tasks suspend through the existing claim owner, transient reservations retire, and safe scans return to ordinary arbitration. | Reviewed connected offline; autonomy/group support and claim-suspend tests pass. Horde behavior, real route safety and useful task resumption remain live. BUG-KS-012. |
| Equipment → firearms → vehicles | Existing inventory actions equip owned items; FirearmSupport selects/prepares while native combat owns ammunition/damage. CompanionVehicles owns vehicle leases and native control release, with controller interruption. | Existing ownership retained; equipment/firearm/vehicle regression sets pass. No new vehicle/firearm implementation in this pass. Aiming, damage, seating/driving/control release remain live. BUG-KS-029/030. |
| Map coordinates/presentation | `KS_MapOrders` derives canonical loaded/logical/last-known locations, groups same-floor markers, and uses native world/UI projection. It does not persist a second position owner. | Reviewed source/fixture path; map-order checks pass. Zoom/pan, click coordinates and rendered markers remain live. BUG-KS-021; faction markers deferred under BUG-KS-022. |
| Offscreen → load/save → same identity | Runtime/persistence retain the person; unloaded survival consumes/reconciles its real ledger, rejects missing snapshots and preserves monotonic reconciliation time. Native bodies/actions remain separate from logical intent. | Reviewed existing lifecycle contracts plus unloaded/lifecycle/offscreen tests. Native materialization, save/reload and away-team restoration remain live. BUG-KS-008/024; never manufacture absent bodies or outcomes. |
| Assigned storage → removal | Base policy remains canonical; ToolCupboard owns only capacity rollback metadata. Removal now resolves without a capacity write, restores known originals with readback, retains failed rollback evidence and leaves unknown originals unchanged. | Confirmed source fix under BUG-KS-039. New silent-rejection/rejected-removal tests fail on the pre-Astra snapshot and pass after correction. Real capacity/content persistence remains live. |

Do not repeat these broad offline audits without a changed boundary, failing
regression or new concrete runtime evidence. This disposition covers ownership
and exercised source paths, not every game interaction or native correctness.
The 2026-09-30 review's then-current 53-option registration/consumer/
disposition inventory is in `../SANDBOX_SETTINGS.md`; the 2026-10-01
organization below supersedes that page/count snapshot. Developer supply
generation is explicitly excluded from ordinary resource-loop evidence.

Next safe order: (1) BUG-KS-013 short Notebook/one-job replay, (2) BUG-KS-039
real capacity/content removal and reload replay, (3) the existing connected
resource/interruption/lifecycle acceptance set. With live work deferred,
resume only a newly confirmed bounded defect; keep release status unchanged.

### Current QA slice

`QA-START-001` through `QA-CLEANUP-001` are the first manifest-driven
in-game QA vertical slice. They cover readiness metadata, one QA-owned native
survivor fixture, read-only recruitment eligibility, checkpoints, and verified
fixture cleanup. The slice uses a unique run ID and separates `BLOCKED` native
prerequisites from `HARNESS_ERROR` coordinator/cleanup failures. A disposable
Build 42.20.4 run exposed BUG-KS-009: the fixture's combat path repeatedly
attempted an unsafe off-slot lighting visibility write. Its narrow source
correction has passed offline regression but still needs a live one-zombie
replay. The slice does not establish natural encounter frequency, recruitment
progression, persistence, combat, movement, storage, jobs, factions, raids,
vehicles, or whole-world safety.

The same existing Diagnostics > **Write Survivor Status to Log** command now
adds a bounded session history from the autonomy controller's centralized
failure path. Up to twelve scalar-only `recent_failure` rows preserve tick,
reason, controller state, decision, retry deadline, and position when
available; this is transient evidence, not persisted state or a second QA
owner. It gives future acceptance scenarios and reports a concise recent
failure trail without per-tick logging. Exact-worktree offline verification on
2026-09-28 passed: 112 Lua sources, 177 regression scripts, 289 checks, 0
failures. Focused autonomy/formation, developer-menu, debug-log, and combat
scenario-reporting regressions passed. Focused scripts remain local under the
ignored `tools/` policy. Live diagnostic acceptance: produce a recoverable
native movement failure, invoke the status command, match its row to the
controller state/retry, then unload/reload and verify only the transient ring
clears. This does not verify the underlying movement outcome. Other Build 42
scenarios remain required for native behavior.

The same live observation established BUG-KS-010 (dark speech overlay),
BUG-KS-011 (post-fence formation cadence), and BUG-KS-012 (retreat policy
retired despite overwhelming-fight inputs). BUG-KS-010 and BUG-KS-011 now have
bounded offline corrections and focused regression evidence; both still need
Build 42 visual/native replay. BUG-KS-012 now has a bounded offline retreat-
admission correction using existing native movement and route-safety ownership;
it still needs the one-zombie/small-group versus overwhelming-group Build 42
comparison before combat acceptance. The former run-stop-return loop was not
restored.

## KS-PROD-011 — Offline regression harness and QA runtime retirement
Status: complete for offline tooling; in-game runner retired by owner direction
Priority: high
Owner: Codex / Luna; Human for live confirmation
Type: qa

### Goal
Keep maintainable offline regression coverage and separate it from ordinary
Build 42 gameplay. The in-game coordinator and save-arming path were retired
when the owner found them confusing and unhelpful to playtesting.

### Implemented offline slice
- Added `KS_QAManifest.lua` with validation, dependencies, seven result statuses,
  timeout normalization, exception isolation, run IDs, and exact ownership checks.
- Extended the active opt-in coordinator with persisted run ID/owner-token tags,
  current/stale fixture reconciliation through the existing persistence and
  autonomy owners, checkpoints/evidence references, and continued scenario
  reporting after a dependency failure.
- Quarantined the old `FULL_STEPS` coordinator; its ordinary-zombie clearing
  helper is inert. The old job matrix remains unavailable because it may mutate
  pre-existing base zones without a full rollback contract.
- Added base, melee, firearm, group/faction, vehicle, save/reload, UI/input, and
  natural-feel manifest entries as `SKIPPED` / `human_required`. They are not
  native passes.
- Added a read-only `QA-BASE-ADAPTER-001` preflight. It reports `BLOCKED`
  until persistence, storage, and autonomy expose the complete run-owned base,
  native target/material, task/reservation, and rollback contract. It never
  calls the legacy `beginBase` or job matrix. `QA-BASE-001` remains human-required.
- Extended the existing log-to-JSON parser, including legacy `SKIP` mapping
  and the explicit base-adapter `BLOCKED` result.

### Validation and remaining acceptance
Focused local tests cover manifest shape, the base-adapter fail-closed gate,
task creation/eligibility/claims/action cleanup, storage/material supply,
dependencies, exception isolation, timeouts/statuses, duplicate and partial
fixture IDs, exact/stale ownership, ordinary-world cleanup safety, persistence
tags, and parser output.
`tools/` tests are ignored by Git policy and local-only. Current
exact-worktree results: focused QA/base-task/persistence/parser checks passed;
`tools/verify.ps1 -SkipJava` passed 115 Lua sources, 192 regression scripts,
307 checks, 0 failures;
`git diff --check` passed. No game was launched; disposable Build 42 validation
is still required for fixture materialization, stale-run reconciliation after
reload, native removal, and report collection. Expand automation only after
each scenario module has a per-run fixture and complete rollback contract; do
not enable the legacy coordinator. The base-task preflight remains blocked:
the existing setup may target the player's real base, and there is no exact
rollback for its base record, zones, tasks, storage policy/native items,
resident duty, runtime reservations, or the native target after a partial or
successful action. Planner and Terra confirmed this
boundary. Next: implement an owner-tagged disposable base-fixture transaction
before enabling base-task automation.

### KS-PROD-011 save-isolation gate follow-up — 2026-09-30

Status: offline_fixed_live_pending; save creation/discard contract remains external

`QA.start` no longer asserts `save_is_disposable=true`. It records the strict
`getCore():getGameSaveWorld()` identity and source, and the new
`QA-SAVE-ISOLATION-001` reports one of `APPROVED_QA_SAVE`, `ORDINARY_SAVE`,
`UNKNOWN_SAVE`, `SAVE_IDENTITY_UNAVAILABLE`, or
`STALE_OR_MISMATCHED_QA_RUN`. Mutating and human world scenarios require this
gate; read-only readiness, checkpoint, and base rollback preflight remain
independent. The gate is a run-scoped human declaration, not proof that the
engine created a clone or can safely discard it. No QA approval persists across
menu/reload, and a save identity change during a run invalidates destructive
scenario dependencies and refuses menu-exit cleanup.

Build 42 exposes only the current save/world label used by this mod; Knox has no
safe Lua API for cloning or deleting saves. The owner must create/backup a
separate `KSQA-...` save outside Knox, arm its exact current identity with the
developer acknowledgement, run QA, then restore/discard it outside Knox. Until
that live path is proven, base-task automation stays `BLOCKED` by both the
save gate and `QA-BASE-ADAPTER-001` rollback preflight. The previous base
preflight remains complete and must not be repeated.

Focused local tests cover all isolation classifications, exact save and next-run
binding, ordinary/unavailable/mismatched identity rejection, identity change,
reload/menu re-arming, mutating dependency blocking, read-only continuation,
and parser refusal of mixed-save report events. `tools/` tests remain ignored
and local-only. Exact current `tools/verify.ps1 -SkipJava` result: 116 Lua
sources, 194 regression scripts, 310 checks, 0 failures; `git diff --check`
passed. Java, Build 42, staging, and Workshop upload were not run.

### KS-PROD-011 manual arm and safe read-only coverage — 2026-09-30

Status: offline_fixed_live_pending

The Developer Tools context submenu now displays the exact save identity,
classification, pending approval, next run sequence, current run status, and
manifest dispositions. Arming is an explicit Developer Mode action followed
by a confirmation dialog showing the identity; QA start remains a separate
action. The in-memory approval is bound to that identity and next run and is
cleared on refused/normal start, finish, menu/reload boundary, identity change,
or coordinator error. Missing/unexpected identity refuses arming. The report
records arm/consume/expire events; the parser correlates arming metadata and
does not treat an arm-only log as a run.

Read-only scenarios now capture canonical survivor/body state,
base/task/duty state, and group/faction membership. They continue on ordinary
saves. Map projection is excluded because the current path can initialize
player persistence. Recruitment remains behind the run-owned encounter
fixture. `QA-BASE-ADAPTER-001` remains a read-only `BLOCKED` result and
`QA-BASE-001` remains blocked by the independent native task/work-target
rollback gap. Combat, firearms, vehicles, faction conflict, world population
mutation, and save/reload mutation remain blocked or human-required.

Focused Developer Tools, read-only snapshot, isolation, coordinator, manifest,
automated-QA, and PowerShell 7 parser tests passed. `tools/verify.ps1 -SkipJava`
passed 116 Lua sources, 196 regression scripts, 312 checks, 0 failures;
`git diff --check` passed. New and existing `tools/` tests are ignored by Git
and are local-only evidence. No Build 42, Java, staging, or Workshop upload was
run. One owner replay in an externally prepared disposable save must confirm
the visible identity, arm confirmation, separate start action, and report arm
metadata before this workflow is live-accepted. Do not repeat the save-gate
design or fixture-ownership reviews; continue with the next QA adapter only
after live arming is observed and native rollback ownership is safe.

The latest available debug log (`2026-09-30_21-40_DebugLog.txt`, events through
22:07) is classified as a stale-stage test, not acceptance: its legacy START
record contains `save_is_disposable=true` and lacks current save identity and
manifest metadata. The local and Workshop QA files did not match current source.
The run hit a Kahlua local-index error, then `KnoxAutonomyController.new` was
unavailable; encounter reported `HARNESS_ERROR`, recruitment skipped, and
registration errors repeated. Current source and located staged Lua copies
compile with Build 42's Kahlua compiler outside the game's debug loader; debug
loader behavior remains unresolved. Refresh local staging before another debug
launch. Do not repeat the save-gate or base rollback audits; current-payload
live replay is required.

### Definition of Done
The core survivor loop is fun and playable in a fresh save, the known connected
systems have no unexplained ownership gaps, performance/default settings are
documented, and remaining live-only or experimental work is explicitly tracked.

## KS-PROD-004 — Complete live UI acceptance on Build 42.20.4
Status: todo
Priority: high
Owner: Human + QA Reviewer
Type: live-test

### Goal
Verify the current Survivor Card and related character UI in the real engine.

### Acceptance
Inspect Skills, health, inventory, and medical views at small and large UI scales without repeated errors, unusable clipping, or stale unloaded-survivor assumptions.

### Validation
Disposable save, target Build 42.20.4, fresh logs.

### Definition of Done
Live UI evidence is recorded with any failure converted into `BUGS.md`.

## KS-PROD-005 — Complete core live gameplay acceptance
Status: todo
Priority: critical
Owner: Human + QA Reviewer
Type: live-test

### Goal
Validate engine-bound behavior that offline doubles cannot prove.

### Acceptance
Cover companion orders/interruption recovery, representative native base jobs, firearms/native damage/reload, save/reload, hibernation/rematerialization, real resource consumption, faction lifecycle/event behavior where enabled, and vehicle behavior where enabled.

### Validation
Use `docs/production/QA_RELEASE.md` and `docs/DEVELOPMENT_TESTING.md`.

### Definition of Done
Required live scenarios pass or produce reproducible tracked bugs.

## KS-PROD-006 — Verify supported Steam/runtime startup paths
Status: todo
Priority: high
Owner: OpenCode + Human
Type: compatibility

### Goal
Confirm the release candidate starts through the supported runtime path(s) from a real subscribed/published-style install.

### Acceptance
- selected runtime path produces fresh `runtime start PASS` and the later
  `Knox patch readiness PASS` evidence when used; the earlier line alone
  is only bridge startup and does not prove that hooks applied.
- The selected path also produces `Lua bridge exposed global=KnoxJavaBridge`
  and Lua-side `[KnoxSurvivors][Bridge] PASS` evidence.
- The deprecated Knox Survivors Launcher is not an acceptance path. Do not
  launch it or compose it with KnoxBridge or external Java runtime. Its separate repository
  has been requested to become private; that visibility change remains pending
  owner-side settings confirmation.
- Do not advertise or test the retired standalone launcher or direct legacy Knox agent as supported setup paths. Test KnoxBridge via normal Steam startup only.
- No test intentionally loads duplicate runtime paths.
- One representative live zombie detection/attack/damage sequence succeeds on
  the selected path so startup text is not treated as gameplay proof.

### Validation
Follow `README.md`, `docs/production/RUNTIME_AND_MIGRATION.md`, and
`docs/production/QA_RELEASE.md`. The old standalone launcher is deprecated and
not part of the supported runtime matrix. On 2026-09-27, its source passed
offline launch-option security/native-argument, updater metadata/version/
checksum, runtime-isolation, and Windows-bootstrap checks; this historical
evidence does not make it a supported path. The main repository retirement
check and verifier also passed at that time. Before live acceptance, isolate
the local `<Zomboid-mods>\KnoxSurvivors` shadow copy and use KnoxBridge as the
only Knox Java runtime. Alternate runtime testing must be performed separately,
never stacked with KnoxBridge.

### Definition of Done
Runtime support claims match live evidence.

## KS-PROD-009 — Triage and stabilize the community-reported gameplay backlog
Status: todo
Priority: high
Owner: Codex / OpenCode
Type: stabilization

### Goal
Reproduce, deduplicate, and resolve the reported gameplay issues recorded as
BUG-KS-013 through BUG-KS-027 after the active confirmed defects and core
integration boundaries are addressed.

### Scope
Start with the highest-impact existing-system failures: storage/resupply,
base-boundary correctness, idle/autonomy behavior, independent survivor/group
decision quality, doors/traversal, and bounded off-screen continuity. Treat map
markers, work-priority expansion, faction markers, and the custom creator as
later feature candidates unless a current implementation defect is proven.

### Rules
- Every report remains `reported` until reproduced against the current Build 42
  and Knox revision or confirmed from a source-owned failure.
- Check whether it is already fixed before changing code.
- Fix one shared failing boundary at a time and update the linked bug evidence.
- Preserve real Project Zomboid state, identity, persistence, and performance
  limits; do not add population/faction systems to hide a measurement gap.
- Use the design references for principles only: Project Zomboid remains the
  foundation, while RimWorld, Rebuild, Dead State, Crusader Kings, and Dwarf
  Fortress inform bounded design comparisons.

### Acceptance
Each promoted bug has a reproduction or source boundary, focused regression
coverage where practical, live verification requirements, and an updated
canonical record. No reported item is silently closed because it is old or
because a different setup produced no failure.

### Next selection
After BUG-KS-012 and current live gates are scheduled, choose the highest-value
reported item whose existing-system boundary is clear. Prefer one that improves
the normal survivor/base/storage loop and can be fixed without introducing a
new parallel system.

The first source-confirmed KS-PROD-009 storage boundary is tracked in
BUG-KS-016: the exposed Logs & Lumber assignment was rejected by the manager's
category registry, and the existing General Storage matcher/fallback could not
be assigned through the menu/persistence allowlist. Both bounded wiring gaps
are corrected with focused coverage; native transfers and the broader resupply
reports remain separate live/current-reproducer work. The 2026-09-27 storage regression pass
also confirms offline coverage for typed categories, same-role containers,
overflow/fallback, real-instance supply/deposit behavior, organizer transfers,
claims and job requirements. No second storage defect was confirmed. The
optional ground-item pickup/placement candidate and its bounds are recorded in
the existing roadmap; implementation remains deferred pending a concrete
cleanup need and verified native action path.

The 2026-09-27 follow-up audit of BUG-KS-015 found no additional offline
transfer/resupply defect after BUG-KS-016's category wiring correction. Focused
storage/organizer/supply/needs/cleanup/job/inventory/persistence tests passed;
native movement, reachability, container mutation, and save/reload remain live
acceptance. BUG-KS-025's current individual/group decision chain likewise has
no deterministic offline priority failure in the reviewed boundary and focused
tests; live decision quality remains unverified. BUG-KS-014 is a distinct
missing general loose-ground-item hauling feature, not a failure in carried
cleanup or corpse hauling, and remains deferred to the existing roadmap
candidate.

BUG-KS-023 was audited on 2026-09-27 and is now classified in `BUGS.md` as a
feature request rather than a confirmed scheduler defect: explicit role,
profession-derived Auto hint, persisted work-group priorities, schedules, and
guarded concrete task assignment already affect selection. Broader multi-role
profiles and additional task groups remain future design choices, not a reason
to replace the current one-job-at-a-time selector.

2026-09-29 BUG-KS-023 base-work preference completion: the existing sparse
player-base `duty.workPriorities` map now exposes High/Normal/Low/Disabled for
the eight groups already recognized by `KS_BaseJobs.selectEligibleTask`.
Missing values mean Normal; legacy values migrate at save normalization. The
selector applies the states only after ordinary task scoring and eligibility,
and Disabled only filters new automatic selections. Active companions remain
outside the work selector; their stored values are preserved across companion /
base-duty transitions and are consumed only in base duty. No task, claim,
reservation, supply-run, or native action owner changed. Focused work-preference,
task-board, base-job, companion/base, organizer, needs, Notebook, and persistence
checks passed. `tools/verify.ps1 -SkipJava` passed: 112 Lua sources, 181 scripts,
293 checks, 0 failures; `git diff --check` passed. `tools/` regressions are
ignored/local-only. Build 42 UI and native work/save-reload acceptance remain
open. See BUG-KS-023 and `DEVELOPMENT_TESTING.md` for exact replay cases.

The follow-up fallback review found no new offline regression in BUG-KS-019's
door helper or BUG-KS-012's bounded retreat admission; their focused tests pass,
but native door/combat behavior remains live-only. BUG-KS-026's source/test
review found one canonical persistence-owned population allocator for survivor
identity/origin, with group/faction/event records referring to those identities;
the report stays open for real Build 42 allocation, materialization, streaming,
and performance evidence.

The 2026-09-27 backlog pass also found a narrow offline door-close fallback
defect in BUG-KS-019: wrappers exposing `setOpen` without a toggle method were
always sent the open state during cleanup. The requested state is now passed
explicitly and covered offline; `lua tools/test-door-discipline.lua` passes in
the current worktree. The offline correction is complete, but native Build 42
door traversal remains unverified. BUG-KS-020 remains reported after focused barricade/task lifecycle
tests: target discovery and claim coverage pass, but the native action-to-next-
window sequence is not proven offline. BUG-KS-013 remains reported after its
existing decision-flow coverage; visible native base-life behavior still needs
the recorded live replay.

The 2026-09-27 BUG-KS-021/022 map audit found that owned-survivor locations
already render through the Knox map overlay, including loaded, logical,
last-known, and durable deceased coordinates. The focused map test passed; no
stale-marker failure was reproduced. Nearby grouping remains a feature
candidate, and native projection/streaming/save-reload behavior remains live-
unverified. Faction-base records already relocate and remove through the
canonical base/faction lifecycle, but no map-marker consumer exists; BUG-KS-022
is therefore a missing feature candidate, not a current stale-marker defect.
Focused map-owned-location, faction-persistence, and multi-base tests passed.
Do not add an independent marker ledger; continue with the next
offline-confirmable existing-system boundary.

The 2026-09-27 BUG-KS-024 stabilization pass removed a source-confirmed
unloaded-combat boundary violation: daily abstract traveler scuffles could
persist damage/death and create fight traces before a native body existed.
Unloaded continuity now remains limited to persisted needs, real carried
supplies, rest, and logical travel. Focused unloaded-survival/group,
world-trace, and event-runtime tests passed, followed by `tools/verify.ps1
-SkipJava` (112 Lua files, 175 scripts, 287 checks, 0 failures). Retain native
materialization/save-reload and loaded/unloaded replay as live acceptance.

The following BUG-KS-024 transition fix commits the hibernated ledger before
native body removal. If the commit fails, the runtime/controller remains active;
if removal does not actually clear the bridge shell, the loaded snapshot is
re-captured before retry. Focused lifecycle, virtual-base-return,
unloaded-survival/base-return, and away-team tests passed, followed by the
offline gate (112 Lua files, 175 scripts, 287 checks, 0 failures). The required
live replay now includes a deliberate hibernation store failure/retry where
diagnostics permit, plus normal restoration with identity, inventory, orders,
affiliation, and duplicate-body checks.

The multi-member away-team handoff now uses the same ownership rule. Its full
roster is validated and stored before removal; pre-removal aborts roll live
members back to loaded ledger ownership, while already-removed members remain
recoverable hibernated identities beneath a blocked, non-outbound dispatch
record. The focused transaction fixture covers valid/invalid roster, duplicate
and dead members, store/team failure, first/middle/final teardown failure and
retry. Focused lifecycle, away-team/executor, unloaded, group, base-return,
world-presence and persistence recovery checks passed before the full offline
gate (112 Lua files, 176 scripts, 288 checks, 0 failures). Live acceptance must still prove native body acknowledgement,
save/reload, restoration and no duplicates.

Blocked dispatch recovery now preserves this distinction through persistence:
only a member whose removal was acknowledged stays `away` beneath the blocked
ledger, while a still-live member restores its prior duty. After canonical
record restoration registers the removed member's body, the lifecycle path
releases that member's saved duty without creating a new identity or body.
Focused coverage includes persistence reload, finalization failure, recovery,
and retry; the same 112-source/176-script/288-check offline gate passed. Native
removal acknowledgement, reconstruction, inventory/equipment/order and
affiliation continuity, and duplicate-body prevention remain for the later
Build 42 disposable-save replay.

## KS-PROD-007 — Refresh candidate evidence and public-facing documentation
Status: in_progress
Priority: high
Owner: ModForge + Codex
Type: documentation

### Goal
Bring release documentation forward to the exact candidate after verification.

### Acceptance
- `CURRENT_STATE.md`, `QA_RELEASE.md`, `WORK_QUEUE.md` and `BUGS.md` reflect the exact candidate evidence.
- `RELEASE_NOTES.md` contains only supported player-facing claims.
- Generated ModForge state agrees with the canonical repository docs.

### Validation
Cross-check the exact candidate revision, test results, live acceptance, and open bugs. On 2026-09-29 the Survivors player docs and Workshop description were reconciled with the alpha8 Bridge review flow. The Bridge UI still needs live Build 42 replay. Read-only release checks found GitHub still on Bridge alpha5 and the public Survivors Workshop page removed with stale Setup.cmd/option-2 instructions; the new Steam uploads are pending owner-side Workshop access. Generated ModForge state has not been checked.

### Definition of Done
One coherent release story exists across ModForge, production docs, and player-facing docs.

### Newly recorded priorities

- `BUG-KS-028` — group/faction follower cohesion and leader-order arbitration;
  prioritize after the current live combat/UI checks because it affects the
  basic NPC group experience.
- `BUG-KS-029` — firearm stabilization; schedule as a dedicated combat pass,
  not incidental work during group movement.
- `BUG-KS-030` — vehicle/driving stabilization; schedule after lifecycle, group
  cohesion, and core combat boundaries are reliable.

BUG-KS-028 now has one bounded offline correction: native group-follow route
success no longer forces a full formation refresh wait before the follower can
reconsider a moving leader. The success handler issues no new route; normal
next-tick arbitration retains existing route commits, cadence, traversal,
threat/need/combat interruption, and retry ownership. Focused formation,
relationship, unloaded-group, order, and behavior checks passed, followed by
`tools/verify.ps1 -SkipJava` (112 Lua files, 176 scripts, 288 checks, 0
failures). The bounded leader-order slice below is now implemented; require the
specified Build 42 leader-plus-multiple-followers replay before treating either
cohesion or leader-order timing as live verified.

The first inspiration-driven group-order slice is now implemented within
KS-PROD-008: canonical NPC group/faction leaders can issue one persisted
`follow` or bounded `hold` directive to their current travel group. The record
is leader-authorized, stored-issuer/group/faction validated, default-bounded to
15 game minutes, and delivered by existing relationship/formation arbitration;
it never creates a second movement or combat scheduler. Successful ordinary
roam/regroup routes issue follow; explicit hold has no autonomous policy, UI,
destination command, or mission behavior. Pending delivery preserves native
traversal/actions and existing need/job/combat ownership; cancellation requires
native `MOVE_CANCELLED` and a failed cancellation waits 60 ticks. Extended
relationship-coherence, autonomy-formation, and roaming-autonomy tests plus the
112-source/176-script/288-check offline gate passed. Defer the disposable Build
42 replay, destination orders, group missions, order UI, firearms live
acceptance, and vehicle work until their dedicated evidence-backed passes.

2026-09-28 supply-ownership correction (`BUG-KS-035`): the 1.5-hour shared
loaded-world shortage lease could expire while the persisted `activeSupplyRun`
still owned an unfinished search/return, allowing another resident to be
elected for the same shortage. The existing autonomy owner now rebuilds the
transient claim from valid same-base active runs before shortage election,
including unloaded residents; only existing terminal run cleanup releases
that durable ownership. Focused `test-base-auto-scavenge.lua`,
`test-base-supply-planner.lua`, `test-inventory-cleanup.lua`, and
`test-base-needs.lua` passed. `tools/verify.ps1 -SkipJava` checked **112 Lua
sources**, **178 regression scripts**, **290 checks**, **0 failures**; `git
diff --check` passed. The focused fixture is local under ignored `tools/`
policy. Build 42 still needs a trip lasting beyond the lease window, including
unload/reload, real pickup, native storage receipt and reassessment. This is
offline ownership evidence only, not proof of native transfer or persistence.

2026-09-28 social-memory connection (`BUG-KS-036`): finalized loaded survivor
encounters previously changed relationship/group state without entering the
persistent history consumed by later recount dialogue and Survivor Cards. The
relationship owner now submits only resolved outcomes to `KS_OffscreenStories`,
which appends to each existing canonical ledger with per-participant
deduplication and the existing 12-entry cap; no ledger is synthesized. Greet,
decline, persisted hostility, successful join, and rejected join have truthful
separate outcomes. Incomplete/interrupted encounters and unverified robbery or
combat success are not recorded. Dialogue and Survivor Card history labels now
reflect friendly, joined, parted, and hostile outcomes. Focused story/history,
recount, encounter, view-model, and relationship-coherence tests passed.
`tools/verify.ps1 -SkipJava` checked 112
Lua sources and ran 178 regression scripts (290 checks, 0 failures). Focused
test edits remain local under ignored `tools/` policy. Build 42 still needs
native loaded encounter outcome, save/reload, and later dialogue/Card replay;
this offline path does not prove engine encounter or native robbery behavior.

## KS-PROD-010 — Test Knox Survivors on Build 42.21
Status: todo
Priority: high
Owner: Codex + Human
Type: compatibility / live-test

### Goal
Use the existing Knox Survivors mod ID and files, with one metadata range
covering Build 42.20 through 42.21. Test the same mod on both builds and do not
claim verified 42.21 gameplay support until its live gates pass. The owner
retargeted compatibility testing after Project Zomboid 42.21.0 Stable was
announced on 2026-09-28.

### Acceptance
- Verify the independent KnoxBridge test module in a real 42.21 game context,
  including enabled-mod discovery, trust, entrypoint, and its harmless patch.
- Keep the existing mod ID (`KnoxSurvivors`) and current mod files; do not make
  a duplicate package or Workshop item for 42.21.
- Set the metadata range to 42.20–42.21 and label 42.21 as under test until
  live acceptance passes. The owner reports the candidate Workshop items have
  been uploaded/updated; this does not close the live acceptance or release
  gate.
- Knox module metadata and entrypoint must use KnoxBridge; remove external Java runtime
  metadata and compile dependencies from the Workshop payload while retaining
  the direct Knox legacy agent only as a source rollback path.
- Audit every required Knox Java hook against the installed 42.21 JAR and test
  the migrated bridge/transformers without changing survivor Lua simulation or
  save schema.
- On a disposable 42.21 world, verify Knox module approval/load, bridge exposure,
  one survivor creation, movement/order, zombie awareness/combat, and save/reload.
- Verify uninstall/restore removes only KnoxBridge startup ownership, ordinary
  Steam starts without it, then reinstall and verify again.
- Keep the package marked experimental until its test evidence is reviewed;
  public upload/release remains subject to owner approval.

### Current evidence and dependency
Normal Steam Play on 2026-09-28 reported PZ `42.21.0`, Java `25.0.1`, and
successful `ZomboidFileSystem.loadMods(List)` transformation. PZ supplied the
enabled roots `KnoxBridgeIndependentTest` and `KnoxSurvivors`; their unknown
hashes were blocked on the first run. After exact-hash approval and restart,
both modules loaded, the independent entrypoint initialized/registered its
probe, and Knox reported required combat/visibility patches ready plus
`KnoxJavaBridge` exposure. This closes the generic bootstrap/discovery/trust/
module-entrypoint gate and the Knox module bootstrap gate. In the same live
session Knox logged native probe `ks-dev-1` spawned, door/fence movement
transitions, baseball-bat attacks, and zombie health reaching zero. One route
reported `FailedStuck`; this is narrow runtime/combat evidence, not pathing
acceptance. Save/reload, deny or changed-hash policy, and 42.20 live
compatibility remain open. The actual uninstall restored the exact original JSON hash;
normal Steam launched without a new KnoxBridge log entry, then reinstall and a
second Steam launch rediscovered and loaded both approved modules. No saves or
mod-list files were targeted.

The local Workshop `Contents` payload was replaced from source after a verified
backup of its previous 125 files. It declares `42.20–42.21`; its KnoxBridge
module JAR now stages at the descriptor path and has a verified SHA-256 match
to the built JAR. Both Knox metadata trees declare `require=KnoxBridgeRuntime`.
KnoxBridge Workshop staging contains the dependency marker, compile-time API
JAR, and player/mod-author guides; it excludes the runtime agent, native
bootstrap, installer, and setup scripts. The player package is separate:
Windows standalone installer; Linux/macOS ZIP plus Python helper (implemented,
not live verified). The owner reports uploading/updating both Workshop items
after this staging. The current public Knox listing still needs owner review for
Bridge access, Required Item linkage, and setup instructions matching the actual
downloadable package. The old installed Steam Workshop subscription and source
trees were preserved. Publication does not prove module startup, gameplay,
save/reload, or cross-platform acceptance.

2026-09-29 group succession normalization: the missing-leader repair path
already cleared leader-owned objectives but retained an old persisted
follow/hold record. Stale-order reads rejected it, so it was inert but remained
orphaned canonical state. Persistence normalization now clears the directive
and advances its revision at the same successor transition, matching direct
member removal. Focused relationship-coherence, unloaded-group,
autonomy-formation, and faction-persistence tests passed; full offline
verification passed 112 Lua sources, 178 regression scripts, 290 checks, 0
failures. The focused regression is local under ignored `tools/` policy. Keep
loaded movement refresh and save/reload during native travel in Build 42
acceptance; the bounded 60-tick coordinator interval is unchanged.

2026-09-29 KS-PROD-008 player control: added World Sandbox option
`AllowAutonomousRetreat` (default `true`) to expose the existing bounded retreat
policy. An absent key in an existing save falls back to true. The existing
controller admission owner rejects only new autonomous retreats when disabled;
active retreat route recovery remains available. Direct player companions,
combat, threat scans, formation, traversal, orders, claims, supply runs and task
resumption retain their existing owners. Focused `test-sandbox-settings.lua`,
`test-combat-intelligence.lua`, `test-autonomy-formation.lua`,
`test-survivor-needs.lua`, `test-base-duty-controller.lua`,
`test-claim-suspend.lua`, `test-relationship-coherence.lua`,
`test-persistence-recovery.lua`, and `test-unloaded-groups.lua` passed.
`tools/verify.ps1 -SkipJava` passed with 112 Lua sources, 178 regression
scripts, 290 checks, and 0 failures. Focused test changes are local under the
ignored `tools/` policy. Do not claim native retreat behavior: the enabled /
disabled Build 42 comparison matrix is in `DEVELOPMENT_TESTING.md`.

2026-09-29 KS-PROD-008 equipment control: automatic owned-gear upgrades were
reconsidered unconditionally in idle autonomy and after loot. The existing
survivor policy record now owns nullable `autoEquipment` (missing means enabled
for old saves); player-owned individual and party menus expose the preference,
including the individual menu for a player-owned base resident. Existing
companion-controller synchronization applies it to loaded autonomy, and both
automatic reevaluation sites share one controller gate. Manual inventory
equipment and combat weapon selection are unchanged. Focused
`test-weapon-preferences.lua`, `test-companion-sync-cache.lua`,
`test-equipment-intelligence.lua`, `test-companion-commands.lua`, and
`test-combat-intelligence.lua`, and `test-order-menu-callbacks.lua` passed.
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and 178 regression
scripts (290 checks, 0 failures); `git diff --check` passed. Test edits are
local under ignored `tools/` policy. Build 42 still needs enabled/disabled real
weapon/clothing/bag upgrade, post-loot, explicit manual equip, combat
requirement and save/reload replay; see `DEVELOPMENT_TESTING.md`.

2026-09-29 KS-PROD-008 group continuity: direct group-member removal and leader
succession updated canonical persistence immediately, while loaded controller
formation projections waited for the existing 60-tick relationship cadence.
Persistence now requests a transient refresh from the existing relationship
coordinator. Its next pass reprojects canonical membership/succession without
writing objectives, clearing runtime life intent, speaking, or issuing/canceling
native movement. The regular cadence remains unchanged absent a membership
change. Focused `test-group-runtime-refresh.lua`,
`test-relationship-coherence.lua`, `test-unloaded-groups.lua`,
`test-autonomy-formation.lua`, and `test-faction-persistence.lua` passed.
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and 179 regression scripts
(291 checks, 0 failures); `git diff --check` passed. The focused script remains
local under ignored `tools/` policy. Build 42 must replay leader removal during
travel, native movement response, group cohesion, priority arbitration, and
save/reload; see the loaded group membership-removal scenario in
`DEVELOPMENT_TESTING.md`.

2026-09-29 KS-PROD-008 base-life review disposition: the offline chain is
reviewed and considered connected through needs, shortage arbitration, task
selection, real-material checks, claims/reservations, native-action result
verification, task-board acceptance, cleanup, and reassessment. No additional
offline defect or implementation package was justified by the current source
and focused evidence. Do not repeat this base-life audit or patch it
speculatively; its remaining evidence is the queued Build 42 full-day and
real-resource/storage replay. The focused base-life set passed 10/10 and the
exact worktree's `tools/verify.ps1 -SkipJava` passed 112 Lua sources, 179
regression scripts, 291 checks, and 0 failures; `git diff --check` passed.
Regression files under `tools/` remain ignored/local and are not Git-tracked
evidence.

The approved player-owned BUG-KS-028 shared destination remains governed by D-025:
one session-only snapshot, Follow-eligible participants only, individual orders
take precedence, one-hour expiry, physical 1.5-tile arrival, and no save/reload
preservation. The player remains the party authority and anchor; NPC/faction
leader objectives and formation remain separate and unchanged.

The separately approved player-party cohesion package is implemented as a
runtime projection under D-026. `KS_CompanionService` derives the current
recruited Follow/no-individual-directive roster, assigns runtime-stable slots,
and updates party heading only after sustained player movement. The existing
`KS_SurvivorAutonomyController` still decides and issues every movement request.
Player-only target leases use the shared autonomy reservation table; blocked
slots compress into distinct standable targets. The player remains anchor, with
a bounded last-position spatial fallback and waits through player traversal or
a moving vehicle. The NPC GROUP formation/leader path is unchanged. During an
active shared destination, eligible members stage on distinct tiles within the
same final tolerance, arrived members wait for the roster, and the service
validates live position before acknowledging completion.

Focused `test-player-party-cohesion.lua`, `test-party-destination.lua`,
`test-autonomy-formation.lua`, `test-directive-handoff.lua`,
`test-companion-sync-cache.lua`, `test-death-evidence.lua`,
`test-survivor-lifecycle-policy.lua`, `test-combat-intelligence.lua`,
`test-survivor-needs.lua`, `test-order-routing.lua`,
`test-order-menu-callbacks.lua`, `test-radial-orders.lua`,
`test-group-scavenge.lua`, `test-relationship-coherence.lua`, and
`test-unloaded-groups.lua` passed. `tools/verify.ps1 -SkipJava` checked 112 Lua
sources, ran 181 regression scripts, and passed 293 checks with 0 failures;
`git diff --check` passed. The focused scripts are local under ignored `tools/`
policy. This is offline evidence only. Build 42 pathfinding, traversal timing,
collision/crowding, rendered status, real interruption/resumption, and the
intentional session-state reset remain open live acceptance. BUG-KS-028's
original NPC follower pause/cohesion issue also remains live-unverified. The
`BUG-KS-030` remains open for its live vehicle acceptance matrix. Nearby-marker
grouping (`BUG-KS-021`) has since been implemented offline; faction-base markers
(`BUG-KS-022`) remain deferred pending lifecycle/live validation. BUG-KS-023's
approved base-only four-state preference slice is now implemented offline;
Build 42 UI, selection, interruption, and save/reload acceptance remains open.

2026-09-29 `BUG-KS-029` firearm stabilization (owner-approved offline package):
the controller's bounded reload-preparation budget is keyed to the exact prepared
weapon identity and target, so a completed encounter cannot force a false
`reload_stalled` on a later fresh reload. Consecutive native ranged
approach/pursuit `COMBAT_FAILED` results are bounded and then released through the
existing melee-fallback owner while the still-valid target stays eligible. Melee
fallback is idempotent when melee is already held and prefers the exact carried
item id. A committed ranged encounter retains its weapon class across the
survivor-choice threshold, and one `clearFirearmCombatState()` owner resets
firearm transients at every terminal boundary (drop, retarget, kill, failure,
close/ranged fallback, preference change, directive abandon, controller error,
detach recovery, flee, shutdown). Native Build 42 still owns reload/rack, the
attack hook, ballistics, damage, condition, chamber/magazine/ammo, and gunshot
sound; no ammo ledger, simulated hit, health mutation, second scheduler, or Java
change was added. Focused `test-firearm-support.lua` and
`test-combat-reload-yield.lua` were extended for readiness, exact weapon identity,
hysteresis, fallback idempotence, budget keying, bounded ranged failure, no
duplicate fire request while a native action owns the weapon, teardown clearing,
lifecycle/shutdown clearing, and directive preservation. Existing firearm,
empty-hand, weapon-preference, equipment-intelligence, combat-intelligence,
autonomy-formation, threat-classifier, human-encounter, and
combat-scenario-reporting regressions passed. `tools/verify.ps1 -SkipJava`
checked 112 Lua sources, ran 181 regression scripts, and passed 293 checks with 0
failures; `git diff --check` passed. This is offline evidence only; live Build 42
acceptance (real reload, shot, ammo reduction, native damage, sound/animation,
friendly protection, interruption/resumption, preference save/reload, party
resume) remains open and is enumerated in `DEVELOPMENT_TESTING.md`. Java was not
changed, so `-SkipJava` is the correct scope. `BUG-KS-030` remains open for its
Build 42 acceptance matrix; do not add offline vehicle changes without new
evidence.

2026-09-29 `BUG-KS-030` vehicle roster rollback correction: `rollbackRoster()`
previously treated a roster member who was aboard a different vehicle as
unseated and called `cancel(member)`, which could clear that member's newer
driver run/control ownership. Cleanup now only cancels an unseated member or
requests native exit from a member still in the exact original run vehicle;
other/unknown vehicle ownership is untouched. Focused
`test-vehicle-driver.lua` reproduces the stale roster and proves the second
driver run, controls, and occupancy persist. The connected vehicle set of eight
scripts passed (driver, NPC travel, companion vehicles, ownership, navigation,
journeys, boarding urgency, lifecycle policy). Current
`tools/verify.ps1 -SkipJava` passed 112 Lua sources, 181 regression scripts,
293 checks, 0 failures; `git diff --check` passed. Java was not changed. The
focused regression edit remains local under the ignored `tools/` policy and is
not Git-tracked evidence. Passenger seats remain native and transient;
save/reload while occupied and unloaded/rematerialized continuity remain live
probes, not supported restore claims. See `BUGS.md` and
`DEVELOPMENT_TESTING.md` for the exact acceptance matrix. `BUG-KS-030` remains
in progress only for native vehicle acceptance; the offline roster rollback
defect is fixed. On 2026-09-29 the approved D-025/D-026 player-owned shared
destination and cohesion slice was rechecked rather than reimplemented:
focused destination, cohesion, order, formation, relationship and unloaded-
group regressions passed (11 scripts), and the current full offline gate passed
with 112 Lua sources, 181 regression scripts, 293 checks and 0 failures. Tests
under `tools/` are ignored/local, not Git-tracked evidence. D-025/D-026 remain
offline-complete with Build 42 acceptance open; no further implementation
package was justified without a new scoped feature or source-confirmed defect.

## 2026-09-29 BUG-KS-021 nearby owned-survivor map grouping

`KS_MapOrders.ownedLocations` remains the authoritative read-only projection;
the existing 250 ms map overlay refresh now derives deterministic same-floor
clusters within 20 world tiles. Member identity and location confidence remain
in the transient group summary, with loaded coordinates preferred for marker
placement and last-known coordinates visibly identified. Deceased markers stay
individual; missing/invalid coordinates are reported without inventing a
position. No new map owner, marker ledger, persistence, group/faction mutation,
or destination-order behavior was introduced. Focused map, map-driving,
persistence, unloaded-survival/groups, faction-persistence, and group-refresh
regressions passed (9 scripts); `tools/verify.ps1 -SkipJava` passed with 112 Lua
sources, 181 regression scripts, 293 checks, and 0 failures. The updated
`tools/test-map-owned-locations.lua` is ignored/local, not Git-tracked evidence.
Build 42 map projection, visual legibility, interaction, streaming and
save/reload remain acceptance requirements. Faction-base markers remain a
separate deferred feature because no existing marker consumer owns them and
base relocation/removal still needs live lifecycle validation.

## 2026-09-29 KS-PROD-008 next-package selection

Planner and Terra reviewed the current queue after BUG-KS-023. No independent,
substantial offline implementation package with an approved scope and existing
owner was identified. BUG-KS-021 marker grouping and BUG-KS-023 base-resident
preferences are offline-complete with Build 42 acceptance open; BUG-KS-022
faction-base markers remain lifecycle-gated; BUG-KS-025 and BUG-KS-026 require
native observation; BUG-KS-027 creator work is deferred by D-017; and the
group, firearm, vehicle, retreat, and base-life packages have no new offline
evidence that justifies reopening them.

Do not add active-companion autonomous work election as an extension of
BUG-KS-023. It needs a separate owner-approved design covering eligible work,
player-order precedence, interaction with formation/danger/needs/travel/combat/
supply runs, player enablement, and how companion work differs from base duty.
The next safe action is the queued Build 42 acceptance or an explicit product
decision that scopes a new feature. This is a reviewed selection result, not a
new gameplay implementation or a change to live/release status.

## 2026-09-29 KS-PROD-008 active-companion work design

Status: implemented_offline; Build 42 acceptance pending.

Owner direction establishes the product rules: companion work is low-risk and
nearby; explicit orders, combat/threats, urgent needs, traversal, formation,
destination travel, supply runs, and recovery outrank it; one player/Sandbox
control gates admission; existing world items, actions, reservations, and
result owners remain authoritative; no global scheduler or base-selector reuse.

Planner/Terra source review found that the base task board and persisted task
claims intentionally accept base residents only. The existing ambient organizer
uses real item/container reservations and native transfers, but its admission
requires an assigned base; companion sync clears that assignment. Therefore no
current active-companion path can safely run a base task by changing only a
preference or toggle. A narrowly scoped companion admission point is required
for any autonomous work, while the controller remains the sole action arbiter.

Owner clarification distinguishes field support from base work: traveling
companions should help the party with essentials, while base jobs remain the
base-resident system's responsibility. The first approved slice is bounded
loaded-area food scavenging by a player-owned companion in settled Follow,
controlled by that companion's existing in-game Auto-Loot permission.
Only safe food is eligible, within 12 tiles on the same floor of both companion
and player; one real item is reserved/transferred and retained in the
companion's inventory. A player move beyond a 3-tile leash, unavailable anchor,
urgent need, threat, explicit order, or disabled Auto-Loot permission cancels an unfinished
route through normal cleanup. An already queued native transfer may finish
unless a higher-priority combat or explicit directive interrupts through its
existing owner; changing Auto-Loot does not clear an already queued native
transfer. It must prove exact inventory receipt. No persistent job/claim is
created; a controller reload resumes ordinary arbitration. The former Sandbox
option `AllowCompanionPartyScavenging` is retired and ignored; it no longer
duplicates the per-companion in-game permission. Missing Auto-Loot values
retain their existing enabled default for old saves.

The implementation uses `KS_SurvivorAutonomyController` as the only arbiter,
`KS_SurvivorLooting.plan` for safe-food filtering, existing transient item and
container reservations, native route/transfer owners, and exact inventory
receipt. It does not use base task selection or create a new scheduler, task
board, storage owner, or persistence record. Water gathering, woodcutting,
organizing, broader scavenging, player inventory delivery, NPC factions,
offscreen activity, and base work remain excluded. Focused offline coverage
was added to existing local regressions; `tools/` is ignored, so those edits are
not Git-tracked evidence. See `DEVELOPMENT_TESTING.md` for the pending native
acceptance. This package supersedes the earlier nearby-base-organizing
candidate; BUG-KS-023 remains complete only for its base-resident scope.

Focused local regressions passed: `test-autonomy-formation.lua`,
`test-survivor-looting.lua`, `test-sandbox-settings.lua`,
`test-companion-sync-cache.lua`, `test-companion-commands.lua`,
`test-survivor-needs.lua`, `test-combat-intelligence.lua`,
`test-base-task-board.lua`, and `test-persistence-recovery.lua`. They cover the
Auto-Loot gate and precedence, distance/floor leash, safe-food filtering and
one-item cap, receipt truth, route cancellation, reservation cleanup, old
Sandbox-key inertness, base/NPC scope, and transient restore behavior. Current
`tools/verify.ps1 -SkipJava` passed: 112 Lua sources, 181 regression scripts,
293 checks, 0 failures. `git diff --check` passed. The three focused test files
under `tools/` are ignored/local, not tracked Git evidence. Build 42 pickup,
movement, capacity, interruption, following, and save/reload remain required;
this offline status is not native acceptance.

## 2026-09-29 BUG-KS-013 staged base-life / Notebook stabilization

Active: the owner observed residents mostly idle or relocating without useful
work in the staged Build 42 mod, and Work/Schedule controls did not produce an
obvious result. Source confirmed and fixed two Notebook integration defects:
selected secondary-base residents now save job preferences, work preferences,
and schedules through the existing service/persistence owners; the Crew view
now preserves the selected person and repaints details after refresh. Tab names
and save feedback are clearer. No base scheduler or native work behavior was
changed. Focused UI, service-boundary, schedule, preference, duty, task, needs,
and ambient-life tests passed; `tools/verify.ps1 -SkipJava` passed 112 Lua
sources, 182 regression scripts, 294 checks, 0 failures; `git diff --check`
passed. `tools/` regression edits are ignored/local and not tracked Git
evidence.

The owner-reported inactivity is not yet explained or resolved end-to-end.
Keep BUG-KS-013 live-open. Next: perform the short Notebook context/save replay,
then a full-day two-resident replay with one supplied real-resource task and one
missing-resource case; capture the first divergence from schedule to native
action/result. Native movement, actions, useful work, and full-day behavior are
still unverified. See `DEVELOPMENT_TESTING.md` for the shortest reproduction.

## 2026-09-30 BUG-KS-039 typed-storage capacity rollback

Source review confirmed `BaseManager.setStoragePolicy()` and
`KS_BaseStorage.resolvePolicy()` raise an assigned native container to the
engine capacity ceiling and mark its object ModData. `BaseContextMenu.removeStorage()`
previously deleted the base policy/name without restoring the prior capacity or
removing that assignment marker. `KS_ToolCupboard` now captures the original
capacity once per native container index, retains it while another active base
policy owns the same compartment, and restores the exact observed original
with readback when the last assignment is successfully removed. Compartment
identity is independent for multi-container furniture; failed policy removal
does not trigger capacity cleanup. No inventory items are moved or deleted.
`ToolCupboardCapacity` is labeled legacy-only for old cupboard records; current
typed storage retains native capacity semantics and the code no longer claims an
unimplemented infinite-weight bypass.

Focused `test-tool-cupboard.lua`, `test-base-storage-menu.lua`,
`test-base-storage.lua`, `test-base-supply-routing.lua`, and
`test-sandbox-settings.lua` passed, including same-object compartment isolation
and removal restoration. The current dirty-tree Lua-only verifier passed 112
sources, 182 scripts, 294 checks, 0 failures; `git diff --check` passed. The
regressions are local under ignored `tools/`. Build 42 must verify real native
capacity, actual item preservation, multi-compartment/overlapping policy
behavior, and save/reload. Old typed assignments that predate an original-capacity
snapshot reuse a known legacy original when available, otherwise leave the
current capacity unchanged and report unconfirmed restoration. Their overwritten
prior capacity cannot be reconstructed. A read-only lookup prevents writes on
rejected removal; silent native rejection retains rollback metadata instead of
claiming success. Both failures were reproduced against the pre-Astra snapshot
and corrected through the existing owners. See BUG-KS-039; this is not live
acceptance or a candidate/package pass.

## 2026-09-30 coherence pass — looting receipt and report disposition

`BUG-KS-015` has a source-confirmed offline correction: generic container loot
no longer reports completion from an empty native action queue alone. The
autonomy controller checks exact selected item identities in the native
inventory, records zero/partial receipt failure, cools the same container,
releases existing leases, and returns to ordinary arbitration. Need,
party-support, base-resupply, and away-team paths remain with their current
result owners. Focused local `test-generic-loot-receipt.lua`,
`test-survivor-looting.lua`, and `test-companion-loot-orders.lua` passed. The
focused test is ignored under existing `tools/` policy. The current dirty-tree
`tools/verify.ps1 -SkipJava` passed 112 Lua sources, 183 regression scripts,
295 checks, 0 failures; `git diff --check` passed. Build 42 native
success/refusal/partial transfer and save/reload remain open. Do not repeat this
source review without new evidence.

### Report triage from 2026-09-30 owner pass

| Observation/report | Existing record / classification | Next evidence or action |
|---|---|---|
| Residents idle; Work/Schedule unclear; base selection/context | `BUG-KS-013`, high-priority live observation; selected-base save/refresh source defects already corrected offline, visible native activity is unresolved | Short secondary-base UI/save replay, then full-day two-resident supplied-task and missing-resource replay; capture the first transition that fails |
| Work-preference button throws | Confirmed `BUG-KS-041`, offline-fixed/live-pending; 2026-09-30 log shows `next(map)` failure at `onCrewPriorityCell` during `ISButton.onMouseUp` | Retest staged fix by cycling High/Low/Disabled/Normal for one selected base resident, then close/reopen Notebook |
| Companion food support unavailable | Reviewed offline 2026-09-30: settled Follow, safe loaded same-floor food within 12 tiles of both actors, exact item/container reservations, native route/transfer, exact inventory receipt, and cancellation cleanup are connected. The old Sandbox gate has since been retired; existing per-companion Auto-Loot is the sole permission. Newer `C:\Users\Gary\Zomboid\Logs\2026-09-30_05-59_DebugLog.txt` evidence remains inconclusive: one `party_support_food_unavailable`, followed later by unidentified useful-item pickup; it does not prove eligible food was present/reachable during the first scan. | Live replay with Auto-Loot enabled for one companion and one safe item in a loaded same-floor container within 12 tiles of both actors; record item identity/count/coordinates, then repeat inaccessible/full inventory, player movement >3 tiles, threat, urgent need, direct order, turning Auto-Loot off during approach and transfer, and save/reload |
| `Wooden_Windows` SpriteConfig warning | Four engine warnings in the 2026-09-30 log; no `Wooden_Windows` reference exists in Knox `mod/` or `workshop/` source, so ownership is unconfirmed and may be map/other-mod content | Identify the placed object and enabled map/mod source before attributing or changing anything |
| `FailedObstacle` movement report | Latest log contains one action failure with `retryAt=1866`, followed by idle/re-election; repeated status snapshots are not repeated failure events | Keep existing recovery; only investigate if live replay shows repeated same-target attempts or no useful continuation |
| Fence pause after traversal | `BUG-KS-011` / `BUG-KS-028`, offline cadence/recovery coverage exists; live/native timing remains unverified | Replay leader/follower through climb/vault/fence and inspect first post-landing continuation |
| Stand from couch into table/furniture | `BUG-KS-013` adjacent report; reviewed 2026-09-30. Controller uses vanilla sit/rest actions and native get-up state; no Knox exit-position owner or source-confirmed defect was found. Unconfirmed, native/live-only geometry. | Run focused couch/table Build 42 replay in `DEVELOPMENT_TESTING.md`; capture stand position and short runtime trace before considering a recovery change |
| Home/outpost naming and dropdown reverting to home | Dropdown is confirmed offline-fixed under `BUG-KS-042`: duplicate `BaseView:prerender` definition suppressed picker commit; area actions now use selected-base resolver. Naming remains a feature gap; visible switching/save behavior remains live-pending | Switch Home → Outpost 2 in Build 42, verify tab contents and area editing/removal stay on that base, close/reopen and save/reload |
| Schedule color/hour clarity and work/storage lists overflowing | `BUG-KS-044` viewport overflow is fixed offline. A follow-up corrected duplicate wheel forwarding from the parent to a child list after the owner reported no improvement; native dispatch and clipping remain live-pending. Schedule colors also remain live presentation acceptance. | Build 42: scroll each list independently and confirm adjacent sections stay within their boxes; test page whitespace, narrow/split-screen, larger fonts, joypad, and schedule-hour feedback |
| Requirements-off jobs appear more productive | Base task/resource owners are connected offline; remaining question is native reachability/action/result; no permission to waive real resources | Run one supplied job and one missing-tool/material case under enabled requirements; preserve honest blocked state |
| Storage zones with ground filters; richer PZ-native work-area assignments/skill gates | `BUG-KS-014` reclassified as a deferred feature request, not a confirmed storage bug. Existing Base & Work UI clearly labels Work Areas separately from assigned real containers; it has no ground-storage control yet. | Design gate updated 2026-09-30: existing `queueDrop` passes a floor container for the actor's current square. The local Build 42 `ISInventoryTransferAction` may place on that square or one of its neighbors, and Knox cleanup verifies only source removal plus a non-nil world item. No exact zone target, square receipt, or inverse rollback owner exists. Proposed first slice: player-owned base only, one same-floor rectangle (max 256 squares), one category via `KS_BaseStorage.classifyItem`, and one already-carried real item per cycle; do not discover/collect loose ground items in this slice. Keep the current assigned-container ranking/overflow/General behavior first; use a ground zone only if no assigned container accepts. Ground zones use exact category before General; General is last-resort catchall. Resolve category overlap with the single classifier (Tools precedes Weapons); reject overlapping ground zones and bind each zone to its canonical base ID/territory. Notebook shows separate **Assigned Containers** and **Ground Storage Zones** sections with category, priority, bounds, and saved/blocked state. Native floor transfer must prove exact item at exact square and safe failure/rollback before code. Loose-world-item collection is a later separate slice; the roadmap's 32 candidates/10-minute scan cap applies there, not to this first carried-item placement slice. No abstract stockpile or placement code. |
| Retreat confidence factors proposal | Future design request; current `BUG-KS-012` bounded policy stays stable | Record as design candidate pending a dedicated combat-policy decision; no retuning from this pass |
| Aimless conversations | Existing social/memory records provide context; this pass found no reproducer proving a dialogue defect | Capture speakers, relationship/memory/faction, location, selected line and event context; prioritize behavioral connection over new chatter |
| Events panel visibility, survivor interaction key/panel/actions | Future UI feature candidate; current interaction/context-menu owners not redesigned | Define one bounded first slice after current owner review; no broad interaction UI added |
| Forage/speech arrow blocks right-click | Arrow source is configured pass-through (`setWantMouseEvents(false)`) and has no input handlers or vanilla foraging hooks; no offline defect found. Native UI-manager propagation and Activity Feed overlap remain live-only | Test right-click/aim outside and over Activity Feed with arrow visible, multiple indicators, expiry, and Feed hidden/visible |
| Base territory corner selection / connected areas | `BUG-KS-017` re-reviewed 2026-09-30: corner normalization and inclusive rectangle ownership agree offline; no current source defect. Disjoint/irregular areas exceed the existing single-rectangle model. No newer runtime logs were available | On a disposable save, select an asymmetric boundary in both corner orders; compare clicked squares, draft highlight, saved bounds, all four edges/adjacent tiles, reopen, and save/reload. Record connected-area inclusion as a model limit, not a bug |

### Continued user-facing triage — 2026-09-30

The game log `C:\Users\Gary\Zomboid\Logs\2026-09-30_05-59_DebugLog.txt`
is newer than the September 28 dev-run. It records one companion-food search
failure followed by a completed two-item general loot route; exact food
availability, item identities, scan coordinates, and capacity are absent, so
this does not establish a defect. Planner/Terra continued through documented
candidates after BUG-KS-017:

- `BUG-KS-022` faction-base markers remain explicitly deferred until faction
  base relocation/removal lifecycle is live-validated; do not add a consumer or
  marker ledger before that gate.
- Schedule controls already show 00–23 labels, current assignment, saved versus
  unsaved feedback, selected tool, and per-category counts. Color/scale clarity
  remains a Build 42 presentation check, not a source-confirmed omission.
- Storage policies and task rows already show category/container/location,
  availability, stock/missing counts, waiting/active/blocked states, reason,
  and retry time. Native display/contents remain live acceptance.
- Dialogue selection already consumes event type, cooldown, personality, and
  bounded social-history context including relationship, group/faction, and
  meetings. “Random/aimless” remains unconfirmed without a captured line and
  matching state; see `BUG-KS-025`.
- Search/loot source has no confirmed contradictory success path after the
  generic receipt correction. Native refusal/partial-transfer wording remains
  part of `BUG-KS-015` live replay.
- Base naming is a feature gap: `base.name` persists and is displayed, but no
  rename flow exists. Hold implementation pending product rules for rename
  scope, maximum/blank-name validation, duplicate-name policy, and whether
  outpost naming occurs at creation or later.

No source defect or approved offline feature boundary was found in these
candidates. No gameplay code or tests changed; continue from the first new live
evidence or a settled base-naming decision rather than repeating these reviews.

## 2026-09-30 Notebook responsive layout — BUG-KS-044

Status: fixed_offline_live_pending. Planner and Terra confirmed Base & Work's
fixed child stack can exceed its short/split-screen viewport; its three data
lists themselves have bounded list boxes. The measured final content bottom is
now supplied to the existing `KS_SurvivorUILayout.bindView` scroll owner.
`tools/test-notebook-layout.lua` checks measured extent, bounded lists, scroll
reachability/stencil, and refit from a short to taller viewport. Focused layout,
Notebook context/refresh, Base UI, and Card UI tests pass. `tools/test-notebook-
evidence: `tools/verify.ps1 -SkipJava` passed 112 Lua sources, 184 regression
scripts, 296 checks, 0 failures; `git diff --check` passed. `deployDev` then
succeeded and SHA-256 matched all 122 source payload files against local and
Workshop `Contents` (0 missing, 0 different); no upload or live test. Build 42
still needs short/split-screen and large-font wheel/joypad navigation and
schedule clarity acceptance.

Arrow review found no offline source defect: the existing overlay explicitly
requests no mouse events, has no input handlers/foraging hooks, draws multiple
speaker IDs per player, expires marks in prerender, hides on empty, and resets
on game start. Existing `test-speech-indicators.lua` covers pass-through config,
expiry, and hiding. Native event propagation and interaction with the separate
lower-left Activity Feed remain live-only; do not add forwarding or alter the
input flags without that evidence.
| Survivors hard to find / independent groups and factions activity | Population/continuity gaps already tracked under `BUG-KS-026`/`BUG-KS-027` and KS-PROD-008; rarer/persistent faction and richer encounter ideas remain deferred | Return after base/loot live gates; do not spawn broader populations or fabricate offscreen outcomes |
| Same spouse traits / duplicate spouse after household succession | `BUG-KS-055`: confirmed offline; fresh saves reused `ks-spouse-<playerId>`, so deterministic personality seeded identically. Fresh spouse IDs now use a one-time saved random suffix; succession marks the successor as inheriting the household so no second spouse is generated. | Build 42: compare two fresh saves; verify stable identity after reload; test player death with household continuation both enabled and disabled. |
| Broccoli repeatedly queued after power loss | `BUG-KS-043` confirms and corrects the offline false-positive: cold/unpowered non-microwave appliances were accepted; live report remains unconfirmed and fuel semantics are unknown | Replay powered stove, power loss before action, residual heat, fuel-backed appliance, failure cleanup, and save/reload |
| Zombie reacts strangely during recruitment | Community report, likely live/native interaction among zombie targeting, encounter and recruitment; unconfirmed | Replay recruitment with nearby zombie and record threat target, encounter phase, and native reaction |
| Search reports an error while finding clothing/medicine/weapons | Reviewed 2026-09-30: no new runtime log/reproducer; generic exploration verifies exact selected-item identity in survivor inventory. Zero/partial receipt produces bounded failure, source cooldown and lease cleanup, not success. No source-confirmed error remains; symptom unconfirmed/native-pending under `BUG-KS-015`. | Build 42 test valid, refused, and partial transfers with exact before/after inventory counts and a short action-result log; do not patch expected native rejection or call report reproduced |
| Medal clip `nBy0GyJDVjJoiD2MQ` | Attempted to open the supplied link this pass, but it was inaccessible to the browser tool; content remains unconfirmed | Provide a local capture or another accessible view; make no claims from the URL alone |

The only source change selected was generic loot receipt truth because it was
confirmed in the current owner path and could be covered offline. BUG-KS-013,
storage capacity (`BUG-KS-039`), and vehicle/other live gates remain separate;
no settings were removed or renamed in this pass. Next priority is the
short/full-day BUG-KS-013 Build 42 replay, followed by BUG-KS-015 real loot
receipt/storage loop; offline work should resume from the first captured
failing handoff, not from another broad audit.

Runtime evidence reviewed from `dev-runs/20260928-021135` (small summary and
matching event slices only): 5,326 Knox event lines, 59 possible issue lines,
and 3 automated results (2 pass, 0 fail, 1 partial). The combat horde probe was
`PARTIAL` (`survivorHits=15`, `zombieDamage=0`, attack action seen, no confirmed
damage); this remains native combat evidence, not an offline code conclusion.
Movement probes include `FailedStuck`, locked-door, static-blockage, and
locked/unusable-window failures. The console slice had no Knox-attributed Lua
exception or render-corruption line; engine/vanilla errors were present and
remain outside this package. See BUG-KS-013 for the precise bounded base
failure/retry sequence. Do not reopen those systems from aggregate counts
without a matching reproduction.

After the source fix, the previously authorized `./gradlew.bat deployDev`
completed successfully. Source-to-local and source-to-Workshop `Contents` SHA-256
comparisons each matched all 122 mod payload files (0 missing, 0 different);
the Workshop stage additionally has the expected Java agent and checksum.
This is development-copy parity, not an upload or Build 42 acceptance result.

## 2026-09-30 urgent startup error correction — BUG-KS-040

The owner reported two immediate autonomy errors after loading the staged
payload. The newest DebugLog locates both at the same `next()` call used to
build threat context for settled companion scavenging. The controller now uses
guarded `pairs`-based `Controller.hasEntries` for that decision and its
reservation cleanup. Focused formation, generic loot receipt, looting,
companion loot, base supply, group support, and away-team checks passed.
`tools/verify.ps1 -SkipJava` passed 112 Lua sources, 183 regression scripts,
295 checks, and 0 failures. `deployDev` completed, then SHA-256 comparison
matched all 122 source mod files in both the local game copy and Workshop
`Contents` (0 missing, 0 different). BUG-KS-040 remains live-pending until Build
42 confirms no errors and the threat gate still suppresses party scavenging.
This is a corrected source/local/staged candidate, not a public Workshop upload
or live-verified fix.

## 2026-09-30 legally safe Workshop inspiration review

Reviewed public player-facing description for Workshop item 1905148104 against
current Knox authorities. It offers no reason to replace Knox ownership or
architecture: basic survivor needs, recruitment/orders, base roles, hostility,
groups and persistence already have Knox owners; visible live outcomes remain
the acceptance question. No code, asset, text, data structure, or layout was
used or reproduced. The item's own page identifies it as Build 41, single-
player, WIP and currently removed/incompatible; the removal notice gives no
reason and is not treated as a legal finding. See `NPC_SYSTEM_INSPIRATION.md`
for the bounded design conclusion.

No code change was justified by the reference comparison. The completed
2026-09-30 test log later confirmed BUG-KS-041, a work-preference click
exception; it contains no task/native-work sequence that closes BUG-KS-013.
Retest the corrected click, then diagnose the first failing duty/task/native-
result handoff. Next separate live priorities remain BUG-KS-015 loot receipt/resupply,
BUG-KS-039 capacity, BUG-KS-021 marker presentation/input, BUG-KS-028 group
movement, BUG-KS-029 firearm acceptance, BUG-KS-030 vehicle acceptance, and
BUG-KS-040 startup/threat replay. Do not repeat this comparison or claim a live
result from prior offline evidence.

## 2026-09-30 Notebook work-preference callback correction — BUG-KS-041

Status: fixed_offline_live_pending. The 02:48 DebugLog shows `next(map)` failing
inside `onCrewPriorityCell` after vanilla `ISButton.onMouseUp` at frame 1875.
The callback now checks the normalized preference map with `pairs`, preserving
the existing CompanionService/persistence owner and selected-base forwarding.
Focused `test-notebook-refresh.lua`, `test-notebook-base-context.lua`, and
`test-work-priorities.lua` pass, including the callback with global `next`
unavailable and the return-to-Normal reset. Full `tools/verify.ps1 -SkipJava`
passes 112 Lua sources, 183 regression scripts, 295 checks, 0 failures;
`git diff --check` passes. The focused regression is ignored by Git under the
existing `tools/` policy. Retest on Build 42 by cycling one selected base
resident High → Low → Disabled → Normal, then close/reopen Notebook and inspect
the selected base/resident and stored value. BUG-KS-013 remains open: this
button exception alone does not explain base inactivity or prove native work.
`deployDev` completed after verification; all 122 source payload hashes match
the local mod and Workshop `Contents`, with no Workshop upload.

## 2026-09-30 selected-base Notebook routing correction — BUG-KS-042

Status: fixed_offline_live_pending. Terra confirmed that two definitions of
`BaseView:prerender` caused the later remove-button method to override the
outpost picker commit. One method now handles both picker refresh and button
state. Edit Boundary, Add Area, and Remove Selected now resolve the selected
owned base instead of the primary base fallback. Executable assertions in the
local ignored `tools/test-notebook-base-context.lua` select a secondary base,
verify ID commit and one shared-view refresh, and exercise all three actions
against that selected base. Focused Notebook refresh and Base UI tests pass.
The final `tools/verify.ps1 -SkipJava` run passed 112 Lua sources, 183
regression scripts, 295 checks, and 0 failures; `git diff --check` passed.
`deployDev` succeeded after verification; SHA-256 matched all 122 mod payload
files against both local and Workshop `Contents` copies (0 missing, 0
different). This is staging only. The test is ignored by the existing
`tools/` policy and is not tracked Git
evidence. Live: visibly switch among multiple bases, edit/remove outpost work
areas, reopen the Notebook, and save/reload. Naming remains a separate feature
gap; BUG-KS-017/018 boundary geometry remains unchanged.

## 2026-09-30 cooking availability gate — BUG-KS-043

Status: fixed_offline_live_pending. Planner selected the supported base-cooking
eligibility boundary; Terra confirmed the final unconditional `true` admitted
cold, unpowered non-microwave appliances despite no supported power/heat
evidence. `KS_BaseCooking.usable` now fails closed there, preserving the
existing powered and positive-temperature cases. Focused cooking, base-job,
task-board, and base-duty checks pass. The final `tools/verify.ps1 -SkipJava`
run passed 112 Lua sources, 183 regression scripts, 295 checks, and 0 failures;
`git diff --check` passed. The expanded `tools/test-base-cooking.lua` is ignored
by Git policy. `deployDev` succeeded and all 122 source payload hashes match
local and Workshop `Contents` (0 missing, 0 different); no upload occurred.
Native fuel-backed behavior, actual heating, and the
reported broccoli-after-power-loss scenario remain live-unverified; see the
BUG-KS-043 replay in `DEVELOPMENT_TESTING.md`.

## 2026-09-30 radial order coverage review — KS-PROD-008 Slice G (superseded)

**Status:** The inventory below was the pre-implementation review. The bounded
command-surface implementation was completed offline on 2026-10-01 and is
recorded in the continuation entry below. Do not repeat this coverage audit.
Build 42 radial rendering/input and native order execution remain live-pending.

Owner request: make the survivor radial the dependable home for expected Knox
orders before reducing duplicate right-click order menus. This is a source/UI
inventory and organization plan. The following is historical pre-implementation
coverage; the reported gaps were addressed within the implementation where the
radial has sufficient target context.

### Current coverage and gaps

`KS_RadialOrders` adds an optional `Knox Orders` entry to the vanilla emote
radial. The existing hierarchy separates Party Orders, individual Followers,
Residents, and Nearby Survivors. It uses the current CompanionService/order
owners, filters to living loaded same-floor people within seven tiles, and
rechecks membership when a submenu is opened. Its current implementation covers
the common follow/hold/relax, return/check-needs, selected search orders,
combat stances, traversal/door permissions, party regroup/guard/patrol, resident
recall, unstick, and nearby talk/recruit paths. The vanilla radial remains
available when no Knox person is nearby or its integration is unavailable.

Existing menu actions not represented or represented only partially in the
radial:

| Cohort | Missing or incomplete radial coverage | Existing owner/scope |
|---|---|---|
| Party | Cancel the session-scoped shared destination; clear individual directives; formation shape/spacing; party vehicle enter/exit; automatic-equipment policy; full nearby search choices | `KS_CompanionService`, `KS_Persistence`, `KS_CompanionVehicles` |
| Individual companion | Formation shape/spacing; weapon preference; automatic-equipment policy; clear directive; direct move/guard/patrol; vehicle actions; full survival/search vocabulary (including clothing, ammunition, clean inventory and corpse/area search) | Existing companion service and controller; selected-square/building targets still need a world target source |
| Base resident | Full nine supply requests and clear-supply action; the existing base-work preference set; automatic-equipment policy; resident loot-run permission | Existing base duty, supply, policy and persistence owners; do not route resident work through companion-only behavior |
| Nearby independent survivor | Implemented radial entry opens the shared F interaction window; its existing eligibility checks govern social, trade, gift, and recruitment actions. | Existing relationship, trade UI/action, recruitment, and interaction-window owners |
| Spatial/world-target orders | Move Party Here, guard/patrol a clicked location, search a selected building/location, map driving | Need the clicked world square/map target; the emote radial callback currently has only the player and radial state |

The Residents tab currently queries the primary owned base returned by
`getForOwner("player", playerId)`, not every owned base. A multi-base radial
needs an explicit base-selection level (base name → resident) or another
unambiguous selected-base source; it must not silently show only Home while the
player is managing an Outpost.

### Recommended radial organization

Keep one top-level Knox entry and four population tabs: **Party**, **Followers**,
**Residents**, and **Nearby Survivors**. For a selected person or population,
use short category pages rather than adding every choice to one ring:

- **Party:** Orders; Movement; Survival/Search; Tactics; Vehicles; Cancel or
  Resume. Order the most-used Follow/Hold/Relax/Return/Check Needs choices first.
- **Follower:** Orders; Movement; Survival/Search; Tactics; Vehicle; Unstick.
  Tactics contains separate Combat Stance, Formation, Weapon Preference,
  Equipment Policy, Traversal, and Door Policy pages.
- **Resident:** Needs/Recall; Supply Orders; Work Focus; Resident Policies;
  Unstick. Work Focus retains the current Automatic/Guard/Patrol/Farming/
  Cooking/Woodwork/Barricade/Hauling/Repair/Rest choices. Resident Policies
  holds automatic equipment and loot-run permission. For multiple owned bases,
  select the base before listing its residents.
- **Nearby Survivor:** one **Interact** action opens the shared social window
  used by the proximity prompt. The window groups Talk/Needs, Social,
  Trade/Give Item, and Recruit; keep risky actions explicitly labeled and route
  all consequences through existing relationship, transfer-receipt, and
  recruitment owners. Do not maintain a second radial-only social action list.

Use a maximum of six action/category slices plus Back per submenu as a usability
target, not as an engine limit. Build 42's `ISRadialMenu` and Java `RadialMenu`
derive angular size from the current slice count and accept more slices, but
large rings make long labels and directional selection harder. Every choice
must reuse current service/persistence/controller APIs. Do not create another
order registry, task selector, formation owner, or destination persistence
record. Party regroup/destination must preserve D-025 session semantics; an
individual directive remains individual and takes precedence.

### Context-menu retirement boundary and acceptance

After parity is implemented and verified, remove only redundant Knox
**command/order** duplicates. Keep vanilla context menus intact. Do not suppress
the separately useful target-specific flows merely because an order radial
exists: base establishment/relocation, clicked-square scouting/barricading,
door locks, container/storage assignment, bed assignment, map/vehicle targeting,
inventory-item actions, and developer diagnostics still need their exact world,
object, item, or coordinate target. Move a flow only after its replacement is
available from the Notebook/Card or another target-aware UI. Keep View Survivor,
inventory/medical management, and other window-opening actions in a deliberate
management surface rather than overloading the order wheel.

Before hiding any command entries, extend the radial regression to assert every
new category, payload, player/survivor/base scope, failure-safe callback, and
back-navigation path. Then use the focused order/radial tests and full offline
Lua gate. Build 42 acceptance must separately verify mouse and joypad selection,
labels at small/large UI scales, order acknowledgement, interruption/resumption,
multi-base resident targeting, and absence of lost access to retained
target-specific flows. Offline radial fixtures do not prove native UI rendering
or actual order execution.

### Custom radial artwork contract

The current code already attempts to load `media/ui/knoxOrders.png` for the
Knox root and falls back to the vanilla group icon. That custom file is not
present in `mod/42/media/ui`; action slices currently use vanilla emote icons
and survivor body-outline textures. In the installed Build 42.21 UI source,
`ISEmoteRadialMenu` supplies the radial, `ISRadialMenu:addSlice` accepts a
Project Zomboid `Texture`, and Java `zombie.ui.RadialMenu` draws textures at
their native dimensions up to 64px; textures wider than 64px are aspect-scaled
into 64×64. The installed vanilla `moveout.png` icon is 64×64. Therefore create
original transparent RGBA PNGs at **64×64 px** under the mod's `media/ui`
folder, load with `getTexture("media/ui/...")`, and retain a vanilla fallback
for every asset. Use one clear, high-contrast human/action silhouette per
slice; no text, fine detail, or opaque square background. Generate source art
at a larger square resolution if needed, remove the background, crop with safe
transparent margin, and downsample to 64×64 before adding it to the mod.

Suggested asset key families follow the radial categories and action meanings
(party/group, follow, hold, rest, home, needs, movement, patrol/guard, food,
water, medical, tools/materials, combat stances, paired/single-file formation,
weapon choice, traversal/doors, vehicle, resident/work, talk/social, trade and
recruit). Artwork comes after the final command vocabulary and radial hierarchy
are settled so assets are generated only for retained entries.

Initial image-generation prompt template (generate one image per final action
key, replacing the bracketed action and gesture; do not request an icon sheet):

> Create an original, human-centered survival-game UI illustration for the
> Knox Survivors radial command **[ACTION]**. Show one ordinary adult survivor
> in worn, practical everyday clothing, with a natural expressive face and a
> readable body gesture that clearly means **[GESTURE / EMOTION]**. Make the
> person feel tired, alert, resourceful, and recognizably human—not a generic
> soldier, superhero, mascot, or faceless strategy-game pawn. Use a restrained
> hand-painted look, strong simple silhouette, warm natural skin tones, muted
> charcoal/olive/earth/rust colors, and a small consistent highlight color.
> Center one clear focal subject; include at most one simple supporting object
> when essential to the command. Compose for legibility when reduced to a
> 64×64 Project Zomboid radial slice. Square canvas, transparent alpha
> background, generous clear margin. Output a clean PNG source at 512×512 so it
> can be cropped and downsampled to 64×64. No text, letters, numbers, labels,
> watermark, frame, radial wedge, opaque background, checkerboard pattern,
> tiny props, complex scene, gore, or imitation of existing game/mod artwork.

Example substitutions: **Follow** — “looking back while giving a small
come-along hand gesture; quietly reassuring”; **Hold** — “one hand raised in a
calm stop signal; focused, not aggressive”; **Return to Base** — “walking toward
a modest house silhouette with a pack; relieved but cautious”; **Check Needs** —
“survivor indicating a water bottle and a bandaged arm; asking for help without
panic”; **Defensive Stance** — “standing close beside an ally with shoulders
turned outward, watchful and protective”; **Recruit/Talk** — “two wary survivors
facing each other at respectful distance, one offering an open hand.”

### Social interaction surface — owner request 2026-09-30

Implemented offline in `KS_SurvivorInteractionUI.lua` as a restrained proximity
prompt near the lower-center of each player's viewport: **[Knox interaction
key, F by default] Speak with [survivor name]**. Its own keybinding is
configurable in Project Zomboid's Controls menu; the vanilla Interact/context
path remains available as a compatibility/controller route and is not globally
rebound. Only show it for a living, loaded, visible, same-floor survivor within the
existing conversation distance; keep it hidden while the player is in a vehicle
or another UI owns focus. Pressing Interact opens one small, player-scoped
window with the survivor's existing live 3D character preview, name, and four
clear attitude tabs: Friendly, Neutral, Mean, Hostile. Tab actions are buttons,
not a free-text or branching dialogue simulator.

Route current actions through their existing owners: Talk/Needs/social acts
through `KS_CompanionService`; Trade/Give Item through `KS_TradeUI`; Recruit
through the existing eligibility/recruitment path. Group current acts as
Friendly (Talk, Joke, Compliment, Funny Face), Neutral (Talk, Ask Needs, Trade,
Give Item, Recruit), Mean (Insult), and Hostile (Slap). Hostility remains the
result of existing trust/relationship rules; do not add an attack, forced
recruitment, or invented conversation outcome. Keep the panel open after
ordinary social actions so a player can continue talking; close it if the
survivor leaves interaction range, unloads/dies, is no longer visible, or an
external high-priority interaction takes over.

`BUG-KS-045` records the source-confirmed conversation progression issue:
`PLAYER_CONVERSATION` rejected repeat attention requests from the same player,
and saved `warm_up` remained the Talk dialogue event after the existing contact
threshold. The correction extends only the current same-player attention lease
and moves warm-up Talk to ordinary personality-aware lines after familiar
contact; it does not alter the persistent social disposition or recruitment
eligibility. The Knox F shortcut uses the registered custom keybinding; the
native Interact event remains available for compatibility/controller behavior.
Prompt scanning suppresses it while a modal dialog or another hovered UI element owns attention (own
prompt/panel excluded via their java objects), and closes the small window when
the target becomes hostile, unavailable, invisible, or leaves range.

Acceptance uses a compact lower-center prompt that does not darken the world,
panel bounds that fit small/split-screen viewports, mouse and joypad
selection, a real loaded 3D portrait, safe action eligibility, repeated Talk,
meaningful personality dialogue progression, and immediate danger/need/directive
interruption. These UI additions provide the Nearby Survivor social interaction
surface proposed in the radial review; they do not replace target-specific base,
storage, inventory, or map menus. Build 42 presentation/input and native
character-model rendering remain live-only acceptance.

The latest 2026-09-30 17:05 runtime log exposed BUG-KS-047: portrait `setState`
ran before `addChild` had instantiated the native model. The child ordering is
corrected, and a configurable F-default shortcut is registered without changing
vanilla Interact. Focused `test-social-interaction-ui.lua` also exercises the
native-child readiness boundary and input gates. Build 42 still must confirm
that the window opens and key/remap, controller, mouse, and world input paths
work without the exception.

Focused `test-social-interaction-ui.lua`, `test-player-conversation.lua`,
`test-player-reputation.lua`, `test-player-social.lua`, `test-social-acts.lua`,
`test-survivor-dialogue.lua`, and `test-order-menu-callbacks.lua` passed. The
current `tools/verify.ps1 -SkipJava` run checked 113 Lua sources and 188
regression scripts (301 checks, 0 failures). An earlier run's one
`test-base-naming.lua` failure is not reproduced: the focused naming check and
current full gate both pass. Focused scripts under `tools/` are ignored/local
and are not tracked Git evidence. `git diff --check` passed for the changed
source and canonical records. Build 42 visual,
input, UI-scale, and native model acceptance remains open.

### KS-PROD-008 Slice H — player-owned base/outpost naming
Status: offline_complete_live_pending
Owner: Codex / Luna

The Base & Work view now offers Rename for the selected player-owned home or
outpost. `KS_Persistence.renamePlayerBase` remains the sole naming/persistence
owner and changes only the existing `base.name`; it verifies the selected base
belongs to the current player, trims surrounding whitespace, rejects blank,
control-containing, malformed UTF-8, or over-32-codepoint names, and rejects
same-owner duplicate names using ASCII case-insensitive comparison (non-ASCII
bytes compare exactly). Successful saves refresh Notebook views while retaining
the selected base ID. The UI reports success and validation/ownership failures.
Faction bases and base identity, territory, zones, tasks, storage, residents,
and schedules are unchanged. Existing save names are not migrated or rewritten.

Focused `test-base-naming.lua`, `test-notebook-base-context.lua`,
`test-multi-base.lua`, `test-persistence-recovery.lua`,
`test-notebook-refresh.lua`, and `test-base-setup-ui.lua` passed. The focused
naming regression is under ignored `tools/` policy and is local-only. The exact
worktree Lua gate passed 113 Lua source syntax checks and 186 regression scripts
(299 checks, 0 failures); Java was skipped. `git diff --check` passed. No Build
42 session was run. Live acceptance must verify input/cancel behavior, home and
outpost selection, immediate label refresh, duplicate feedback, Notebook reopen,
and save/reload. Do not repeat offline naming review absent new evidence.

### KS-PROD-008 Slice I — water-safety classification
Status: offline_fixed_live_pending
Owner: Codex / Luna

Whole-project ranking placed the full-day base-life/loot-resupply observations
first by player impact, but their next acceptance is native-only and already
well-scoped in BUG-KS-013/015. The highest-confidence offline fix was in the
shared clean-water classifier: a failed taint-tag read previously defaulted to
clean. BUG-KS-046 now records the source defect. `KS_SurvivorNeeds` rejects
unknown fluid state while preserving known-clean water and the existing
known-tainted critical-thirst fallback. Consumers remain Needs, autonomy,
`KS_BaseStorage`, looting, group support, and offscreen snapshot validation;
no duplicate water owner was added.

Planner ranked the open base-life/resupply and capacity replays above offline
work by impact, then this directly actionable water-safety defect, then the
filtered ground-storage feature (which still needs a native placement/receipt
path), followed by the future retreat-policy design. Terra confirmed the
`ISDrinkFromBottle` native consequence and fail-open source boundary. Focused
needs, base-needs, base-storage, supply-routing, loot, group-support, and
unloaded-survival checks passed. The current full verifier passed 113 Lua
sources and 186 regression scripts (299 checks, 0 failures); Java was skipped.
The `tools/` test extension is ignored/local-only. `git diff --check` passed.
Build 42 has not verified fluids, native consumption, sickness, or persistence.

#### Whole-project coherence disposition

| Area | Current owner/evidence | Coherence state and remaining gate |
|---|---|---|
| Identity, origin, lifecycle, offscreen | Persistence/Java runtime, population, unloaded ledger/story owners; source and fixture coverage recorded in architecture | Connected offline; spawn density, materialization and same-person save/reload remain native/live gates. |
| Encounters, recruitment, relationships, memories, dialogue | Relationship/group/persistence owners; loaded encounter outcomes feed bounded persistent memory; interaction UI uses existing trade/recruit/social owners | Connected offline; encounter pacing, rendered interaction and real consequences remain live. |
| Groups/factions and leader/follower | Persistence/group leadership, relationship refresh and existing formation/controller path | Membership and succession boundaries exercised offline; native travel, cohesion, danger and reload remain open. |
| Bases, outposts, duties, schedules, work preferences | Persistence owns selected base/duty; Notebook presents; task board owns claims; controller/native action verifies results | Owner's 2026-09-30 replay provisionally observed base work functioning; full-day/supplied/missing-resource acceptance remains incomplete. Schedule clarity is offline-updated and live-pending. |
| Storage, shortages, real items | `KS_BaseStorage`, real containers, capacity rollback owner, task/supply claims and receipt verification | Typed-container behavior is connected offline; BUG-KS-015/039 real pickup, capacity, deposit and reload remain live. Filtered ground placement is a future feature requiring a real native move/receipt boundary. |
| Food, water, needs, self-care | Shared Needs classifier; native eat/drink actions while loaded; inventory snapshot consumption while unloaded; shared base/group supply/search paths | BUG-KS-046 classifier fail-open fixed offline; direct loaded-object drinking is implemented through the existing controller and vanilla `ISTakeWaterAction`, limited to owned base/camp boundaries. Clean/tainted/unknown native-water consequences, real depletion, and reload remain live-pending. |
| Jobs, skills, crafting, household tasks | Existing task/job selectors and specialized native executors; claims and real-material checks | Supported jobs are offline-connected; broad skill-gated coverage, resource failure presentation and full-day visible productivity remain acceptance/design work. |
| Melee, firearms, fleeing, vehicles | Existing controller/FirearmSupport/CompanionVehicles and vanilla native action/state | Bounded ownership/fallback logic has offline coverage; native damage/ammo/reload, escape choices, vehicles and recovery remain unverified. |
| Map, Notebook, radial, speech, lists, input | Existing map projection and UI owners; selected-base context, naming, scroll measurement and social panel in source | Source paths reviewed/tested; native rendering, mouse/joypad propagation, scale, map click/zoom and Arrow overlap remain live. |
| Sandbox settings/prototypes | `sandbox-options.txt`, `KS_Settings`, controller and `SANDBOX_SETTINGS.md` | 2026-10-01 owner-directed cleanup reorganized the 52 visible options into General, Population, World & Factions, Bases & Work, Companions & Orders, Interface, and Developer Tools. Retired the redundant `AllowCompanionPartyScavenging` gate; existing in-game per-companion Auto-Loot now owns nearby pickup and party-food admission. Old key is ignored, not migrated. `ToolCupboardCapacity` and `ShowLegacyContextCommands` remain because source confirms compatibility/presentation consumers. Offline-fixed/live-pending; do not repeat without new evidence. |

No new gameplay defect was promoted to confirmed by the owner's latest test.
BUG-KS-013 is provisionally observed working but not fully replayed; BUG-KS-015
and native clean/tainted/unknown water remain unconfirmed/live-pending. Do not
re-audit those offline boundaries absent new evidence. Direct native water
source selection is offline-implemented below; its Build 42 result remains
open. The next offline-safe package is deferred: filtered ground storage lacks
an approved placement/receipt contract, furniture exit needs the reported
geometry replay, base/outpost naming and conversation continuation are already
implemented offline, and the search-order symptom remains live-unconfirmed
after the generic receipt correction. Proceed with the short water replay or
new evidence before selecting another source change.

### KS-PROD-008 Slice J — Schedule UI clarity
Status: offline_complete_live_pending
Owner: Codex / Luna

The owner reported that schedule editing was difficult to understand despite
provisional base-work success. The existing 24-hour draft, tool-paint callbacks,
`hoursToDutyWindows`, selected-base service write, and persistence are retained.
The Crew & Schedule view now removes the instructional paragraph and verbose
task/job/count text; it shows the resident, current hour/assignment, selected
paint tool, and a short saved/unsaved/default status. Hour cells retain their
assignment colors and 24-hour labels, with a yellow border and `*` on the
current hour. Tool/preset/action rows wrap at narrow widths, the hour strip
reflows into more rows as needed, and the existing vertical scroll adapter
keeps the full page reachable. Schedule meaning, resident eligibility, write
ownership, and joypad handlers remain unchanged. The 2026-09-30 follow-up adds
a bounded mouse stroke to the existing hour buttons: press on an hour, drag
over cells to paint, and release to stop. The stroke captures the selected
resident/tool, does not capture pointer input, and ends on release outside or
scroll; single-click and joypad activation still paint one hour. Persistence
and the existing save path remain the sole owners. BUG-KS-048 tracks this
offline correction separately from the still unverified visual color concern.

Focused `test-notebook-schedule-clarity.lua`, `test-duty-schedule.lua`,
`test-notebook-refresh.lua`, `test-notebook-base-context.lua`, and
`test-notebook-layout.lua` passed. The new `tools/` regression is ignored by
Git policy and remains local-only evidence. Full offline verification and
`git diff --check` results are recorded in the current-state entry for this
slice. Build 42 color contrast, clipping, actual pointer/joypad painting,
hour-transition highlighting, save feedback, and reopen behavior remain open.

### KS-PROD-008 Slice K — Direct drinking from loaded native water sources
Status: offline_complete_live_pending
Owner: Codex / Luna

The loaded self-care search still prefers carried fluid items, assigned storage,
and real water items in searchable containers. It now also considers loaded
object-backed sources through the same 12-tile XY/same-floor search, only for
player-owned base residents inside their owned boundary and faction/base
residents inside their base or camp boundary. Empty sources and unreadable
taint are rejected; known tainted sources are eligible only at critical thirst.
Candidates use the existing adjacent-tile route, need/order/threat arbitration,
and a transient water-source lease. Arrival rechecks need, source, boundary,
approach, order, and threat before queueing vanilla `ISTakeWaterAction` for
direct drinking. Full inventory is honored as the native refusal. Completion
requires both a real thirst decrease and a real source amount decrease (a
source depleted to zero is valid evidence); failed/partial actions do not
report success. Existing release/backoff and truthful failure paths remain the
owners. No persistence, offscreen map-water, bottle filling, new scheduler, or
new resource ledger was added.

Focused `test-survivor-needs.lua`, `test-autonomy-water-source.lua`,
`test-base-needs.lua`, `test-roaming-autonomy.lua`, and
`test-autonomy-formation.lua` passed. `tools/verify.ps1 -SkipJava` passed 113
Lua sources and 188 regression scripts (301 checks, 0 failures); Java was
skipped. The new water-source regression is ignored under `tools/` policy and
is local-only evidence. Native water, sickness, source depletion, full-inventory
refusal, item amounts, movement, and save/reload remain live-pending. The owner
has not completed BUG-KS-046's clean/tainted/unknown native-water matrix; do not
claim it passed.

Next: replay one player-owned base resident and one faction/base resident with
a real nearby clean source, then known-tainted source at ordinary and critical
thirst, an unknown source, no source, full inventory, danger/order interruption,
and save/reload. Keep bottle filling and ground storage as separate later
packages.

## 2026-09-30 latest Build 42 observation follow-up

| Observation | Current classification/evidence | Status and next action |
|---|---|---|
| Interaction prompt says E and does not open | `BUG-KS-047` confirmed by 21 logged `ISUI3DModel:setState` failures before portrait child instantiation; fixed offline. A registered Knox key uses F by default, while vanilla Interact/controller input remains available. | `offline_fixed_live_pending`; test F, remapping, native Interact/controller, world input, modal/vehicle/aiming gates, and absence of the exception. |
| Schedule click color/continuous paint | `BUG-KS-048`: click updates the existing colored draft cell offline; source lacked a held-drag stroke. Stroke now paints only hovered hour cells, captured to resident/tool, ending on release outside or scroll. Native color rendering remains unproven. | `offline_fixed_live_pending`; replay click/drag/repaint/save/reopen at narrow and normal scale, with joypad and scroll. |
| Natural behavior away from base seems aimless | Keep the owner observation as an important unresolved player-facing problem. Source has purposeful roam/exploration, need, threat, formation, companion-relax, recreation, and social arbitration; this review found no deterministic offline scheduling defect. Existing choices do not prove they look useful in Build 42. | `live_observation_needs_context`; replay an independent/group survivor and a companion away from base with identity, orders, needs, threat, route/state, active task and recent activity. Separate native movement stalls from low-purpose choices; do not dismiss the report or add random busywork. |
| Base resident work/farming failures in latest test | `BUG-KS-013`: `ks-spouse-player-1` (`KnoxIsoPlayerShell`) reached farm actions; plow/seed/water checks saw no crop state change. A tree action timed out; `FailedStuck` entered bounded movement retry. Follow-up source audit found no Knox registration/call of `receiveGlobalObjects`; Knox waits for queued actions, verifies crop state, and routes no-change through task-board failure cleanup. The warning is correlated/native-live uncertainty, not a confirmed Knox defect. | `live_replay_required`; compare player and survivor-shell plow/seed/water on one isolated assigned tile, capture actual action queue and `CFarmingSystem` before/after, and run one supplied plus one missing-resource non-farming job. BUG-KS-013 stays open/high; player-visible inactivity is not considered solved. Callback audit reviewed 2026-09-30; do not repeat absent new reproduction/source divergence. |
| Barricade/cover all valid windows | `BUG-KS-020` confirmed an offline continuation gap: the explicit order queued each window but only the first was manually assigned; remaining tasks stopped when `automaticJobs=false`. Persisted `manualOrder` task markers now enter the existing task board before the autonomous-jobs gate. | `offline_fixed_live_pending`; verify a two-window ordered job with automatic jobs disabled, material delivery, native result, next-target selection, cancellation, retry, and save/reload. |
| Metal-sheet installation | Bounded readiness audit: the installed Build 42 `ISBarricadeAction` exposes metal mode (`new(character, object, true, false)`), validates an unbarricaded `BarricadeAble` plus equipped BlowTorch/SheetMetal, then consumes SheetMetal and adds/transmits a metal barricade. Knox's shim preserves that validation branch, but Knox job discovery, material sourcing/reservation, queueing (`false, false` wood mode), and plank-count receipt are wood-only. No metal task/result/cleanup path exists. | `feature_gap_deferred`; not implementation-ready as a Knox vertical slice until product scope chooses metal barricade vs. metal-door covering and requirements are defined. Then implement through existing task board, real materials/tools, native action, verified metal barricade result, and interruption/claim cleanup. Native animation, resource consumption, and sync still require Build 42 acceptance. Review complete 2026-09-30; do not repeat without new API/source evidence or approved scope. |

For this review, `test-base-farming.lua`, `test-base-jobs.lua`,
`test-base-task-board.lua`, `test-base-action-lifecycle.lua`, and
`test-base-task-validation.lua` passed. `tools/verify.ps1 -SkipJava` passed
113 Lua sources, 189 regression scripts, 302 checks, 0 failures. No source was
changed and no live acceptance was performed.

The focused manual-order, barricade, task-board, task-validation, base-job,
action-lifecycle, duty-controller/simulation, and schedule regressions passed.
`tools/verify.ps1 -SkipJava` passed 113 Lua sources, 189 regression scripts,
302 checks, and 0 failures; Java was skipped. `git diff --check` passed. The
new `tools/test-manual-barricade-order.lua` is ignored/local-only evidence.

The relevant current log was `C:\Users\Gary\Zomboid\Logs\2026-09-30_17-05_DebugLog.txt`. The 17:09 portrait exception predates its already-completed offline correction and was not reopened. The 17:12–17:15 slice identifies farming tasks on the non-local survivor shell with no verified crop change, a tree-action timeout, movement failures, and nearby `receiveGlobalObjects: player is null` messages. None proves the native cause; task failure and bounded cleanup are truthful in source. No live test or source change was made in this review.

Focused farming, job, task-board, task-validation, action-lifecycle, base-duty,
ambient-life, and needs checks passed. `tools/verify.ps1 -SkipJava` passed 113
Lua sources, 189 regression scripts, 302 checks, and 0 failures; Java was
skipped. `git diff --check` passed. The review updates evidence only; no native
farming or base-life acceptance is claimed.

## 2026-09-30 interaction and UI stabilization follow-up

This pass used the current dirty tree and source/tests; no newer runtime log
slice was supplied, so no new engine failure is claimed.

| Item | Result | Disposition |
|---|---|---|
| Nearby interaction prompt | Existing `BUG-KS-047` registers F by default; the minimal translucent prompt now explicitly says Press [key] to talk to [survivor], uses a stronger readable font, and keeps `setWantMouseEvents(false)`. Focused regression covers wording, gates, and pass-through. | `offline_fixed_live_pending`; confirm rendered placement/contrast, input, native Interact/controller, and no overlap in Build 42. |
| Conversation/trade wandering | Terra traced the conversation's bounded attention lease and trade begin/release lifecycle. A real cleanup gap remained: closing the interaction window did not release a conversation lease started by that window. `BUG-KS-051` now routes cleanup to the runtime lease owner. Trade remains owned by its existing trade lifecycle. | `offline_fixed_live_pending`; verify stay-near while open, close/cancel cleanup, danger/need interruption, and native movement. Range remains unchanged. |
| Duplicate storage assignment menu | Terra found the existing Knox menu de-duplicates clicked objects, addresses compartments separately, and replaces/removes the exact stable base/object/container reference. Existing `test-base-storage-menu.lua` covers these paths. No duplicate Knox assignment writer was found. | `reviewed_source_path_correct`; if the player's duplicate entry report persists, capture the exact right-click target/menu labels to distinguish vanilla from Knox. No setting, key, or saved data was removed. |
| Activity Feed show/hide | `BUG-KS-049`: hide previously forced the window visible, toggle always showed, close was disabled, and the display setting also discarded incoming feed records. The existing feed owner now hides/reopens without clearing its bounded seven-line history; Sandbox visibility no longer suppresses recording. | `offline_fixed_live_pending`; verify close button, context-menu toggle, event retention, and world input with display on/off. |
| Notebook side access | The existing Base menu and Party management context menu already open `KnoxSurvivorNotebook.show`. No safe vanilla always-visible sidebar registration was confirmed in this path. | `existing_fallback; side_button_feature_deferred`; evaluate only with a supported Build 42 button API and scale/joypad acceptance. |
| Radial clutter/visibility | `BUG-KS-050`: `ShowRadialOrders` defaults on; `ShowLegacyContextCommands` is the default-off alternate right-click order surface. The settings are independent; disabling context menus never triggers an automatic fallback. When both are off, Knox orders are absent from both surfaces while vanilla radial actions remain. | `offline_fixed_live_pending`; verify enabled/disabled wheel behavior with mouse/joypad and right-click visibility. |
| Speech/direction arrow input | New owner retest says the full-screen arrow still blocks world interaction. It now explicitly returns false from all mouse handlers, reapplies `setWantMouseEvents(false)` after UI registration, and releases pointer capture. Focused fixture checks the registered state and callbacks. | `offline_fixed_live_pending`; verify right-click, aiming, movement, and other world interaction with arrows visible and Activity Feed independently visible/hidden. |
| Base & Work scroll report | New screenshot displayed legacy `Storage: 1 assigned`; current source displays `filtered | usable containers`. Source files have now been copied into the subscribed Workshop folder, but 11 obsolete QA/probe Lua files remain because cleanup was blocked. | `current_source_staged_extra_legacy_files`; use the clean local mod with Workshop entry disabled for next test. Fully restart and confirm `filtered | usable containers`, then test each list/page scroll. If current build still leaks, investigate nested page scrolling; do not repeat the already-correct culling audit. |

The arrow input change passed `test-speech-indicators.lua`; focused Notebook layout
and base-context checks passed. `tools/verify.ps1 -SkipJava` passed 103 Lua
sources, 200 regression scripts, 303 checks, and 0 failures. `deployDev`
completed; source matched all 114 payload files in the local mod, local Workshop
staging directory, and subscribed Workshop folder (0 missing/different tracked
source files). The subscribed folder still has 11 obsolete QA/probe Lua files
and the generated agent JAR; choose the clean local mod and disable the Workshop
entry for the next test. Keep Build 42 confirmation open until restarted.

No storage Sandbox options, compatibility keys, or persisted assignments were
removed or renamed. `ShowLegacyContextCommands` remains actively read by its
context-menu owner; `OrderGestures` remains an active gesture setting, not a
radial visibility gate. `ShowActivityFeed` remains the feed display gate and
now does not discard the in-session bounded feed records.

Focused regressions passed for Activity Feed, radial orders/settings, player
conversation lease, social interaction UI, speech indicators, storage context
menu, and order-menu callbacks. `tools/verify.ps1 -SkipJava` passed 113 Lua sources and 190 scripts
(303 checks, 0 failures); Java was skipped. `git diff --check` passed. Tests
under ignored `tools/` remain local-only Git evidence. No Build 42 retest was
performed.

### KS-PROD-011 / BUG-KS-053 — Debug loader local-variable overflow

The newest Build 42.21 log (2026-09-30_22-39_DebugLog.txt) shows the actual
active mod root was `C:\Users\Gary\Zomboid\Workshop\KnoxSurvivors\Contents\mods\KnoxSurvivors\42`,
not only `Zomboid\mods\KnoxSurvivors`. The active payload emitted the legacy
QA START shape (`save_is_disposable=true`) and lacked the current identity and
manifest metadata. During Lua startup, Kahlua reported local index 200 outside
a 200-slot array; subsequent `KnoxAutonomyController.new` nil errors blocked
controller registration, and encounter QA reported `HARNESS_ERROR`.

The only current client Lua source at 200 top-level locals was
`KS_SurvivorAutonomyController.lua`; one unused helper was removed, leaving
199, and an ignored local regression locks that budget. Focused autonomy and
QA checks plus `tools/verify.ps1 -SkipJava` passed 116 Lua files, 197
regressions, 313 checks, 0 failures. Both the local mod folder and the actual
Workshop development path from the log now match the 127 source payload files
by SHA-256; the two intentional runtime JAR/checksum files in the Workshop
folder remain untouched. No public upload or live retest occurred. Next owner
action: restart Build 42 and verify the current QA START metadata and absence
of both the compiler and controller-registration errors before any gameplay QA.

### KS-PROD-011 / BUG-KS-053 — second Debug Mode attempt

The 2026-09-30_23-18 log confirms the game loaded the Workshop development
root and the current QA manifest v2, but Kahlua still overflowed after the
first source reduction to 199 locals. Therefore that first attempt did not fix
the loader failure. `saveIdentity=unavailable` made the current harness block
`QA-ENCOUNTER-001`, as intended; it does not explain the earlier Kahlua
compile error. Ten tuning constants now use the existing
`KnoxAutonomyController.TUNING` table, reducing the controller to 189
module-scope locals. A regression caps it at 190. Focused tests and full
offline verification passed (116 Lua, 197 regression scripts, 313 checks, 0
failures). The corrected payload has been recopied to both game paths and
hash-checked. Next: restart and confirm Kahlua loads the controller; separately
investigate why the save identity API reports unavailable if that persists.

### KS-PROD-011 / BUG-KS-053 — 23:49 Debug Mode retest and next action

The 23:49 log confirms the Kahlua error persisted in the Workshop copy staged
at 23:42 (189 controller locals). The repository was changed later, at 23:58,
to reduce the controller to 153 locals by moving 36 constants into its existing
`Controller.TUNING` table. The regression cap is 160. Focused checks and the
full verifier passed (116 Lua, 197 scripts, 313 checks, 0 failures). The latest
127-file payload has now been copied to both local and Workshop development
roots and SHA-256 checked; the Workshop agent JAR/checksum were preserved. Next
owner action: launch Build 42 again and confirm the fresh log has neither the
Kahlua overflow nor `KnoxAutonomyController.new` registration errors before
testing gameplay. Save identity remains separately unavailable in the prior
log; destructive QA stays blocked until its gate is satisfied.


### BUG-KS-053 — fresh Debug Mode failure and corrected function boundary

**Status:** source-corrected; fresh Build 42 confirmation pending. The 2026-10-01
00:25 run loaded a Workshop controller hash identical to current source but still
failed in Kahlua `LexState.new_localvar` at index 200, followed by nil controller
registration at `KS_SurvivorAutonomy.lua:309`. The prior source reduction only
changed module scope and did not address the actual 231-local `Controller:tick`.
The existing base-task action/result branch now belongs to
`Controller:updateBaseTaskAction`; `tick` delegates and returns when handled. This
keeps native actions, claims, receipts, and arbitration under the same owners.
Focused lifecycle/autonomy tests and full offline verification pass (116 Lua, 197
scripts, 313 checks). **Next:** stage the corrected controller to both local and
Workshop development roots, confirm hashes, then ask the owner for one fresh
Debug Mode launch. Accept only when neither the Kahlua exception nor nil
constructor registration error appears. QA save identity remains a separate
blocked prerequisite. Do not repeat the module-scope-only local reduction audit.


### BUG-KS-053 — startup loader replay result

**Status:** startup error live-confirmed resolved for the owner's fresh restart.
The staged controller split removed the Kahlua index-200 error and resulting nil
constructor report, per owner confirmation. Do not repeat the loader fix/audit
without new error evidence. QA save identity/arming remains a separate open gate;
continue only with the owner's normal gameplay test after confirming the intended
mod is loaded.


### KS-PROD-011 — runtime QA retired; offline tests retained (2026-10-01)

The owner asked to remove the in-game QA because it was confusing and was not
helping gameplay progress. `KS_AutomatedQA` and its manifest, save-isolation,
base-adapter, probe, developer-config, and job-matrix modules have been moved
out of `mod/42/media/lua`, so the game cannot auto-load the harness from its
client Lua directory. The Developer Tools submenu/actions and Sandbox option
were removed. Ordinary developer spawn/combat/job/diagnostic tools remain.

Offline QA contract/parser regressions remain in place and load their harness
fixtures from `dev/qa-harness`; `tools/verify.ps1` remains the developer test
path. The old `AutomatedQAMode` value in existing saves is inert and ignored;
there is no migration or data rewrite. Do not restore an in-game runner without
a new explicit product decision. Next work returns to gameplay stabilization,
not QA infrastructure.


**Verification and deployment:** focused QA retirement/menu/Sandbox regressions
passed; QA archive syntax checked (14 files). Full verifier: 102 packaged Lua
sources, 197 regression scripts, 299 checks, 0 failures. `git diff --check`
passed. All 109 `mod/42` files match the local and Workshop development copies
by SHA-256; no QA-only `.lua` module remains active in either runtime folder.
The old files are retained under `dev/qa-harness` for offline regression use.
No public upload or live test was performed.

### 2026-10-01 — Sandbox organization and single Auto-Loot permission

The 53-option registration was reorganized into seven player-oriented pages;
the redundant `AllowCompanionPartyScavenging` option and both runtime gates
were removed. Per-companion Auto-Loot is now the only permission for nearby
pickup and the bounded safe-food detour. Old saves' retired key is ignored;
the existing missing Auto-Loot value remains enabled. `ToolCupboardCapacity`
and `ShowLegacyContextCommands` were retained because their compatibility and
UI consumers are active. No defaults or persisted option identities besides
the retired gate were changed.

Focused `test-sandbox-settings.lua`, `test-autonomy-formation.lua`,
`test-companion-loot-orders.lua`, `test-survivor-looting.lua`,
`test-companion-commands.lua`, `test-order-routing.lua`, `test-radial-orders.lua`,
`test-base-storage-menu.lua`, and `test-tool-cupboard.lua` passed. Full
`tools/verify.ps1 -SkipJava` passed: 102 Lua files, 197 regression scripts,
299 checks, 0 failures. Sandbox translation JSON parsed, and source census
confirmed 52 registered options across the seven documented pages.
`git diff --check` passed. Test files under ignored `tools/` are local-only.
Live Build 42 still needs Sandbox-page display/default review; per-companion
Auto-Loot on/off with nearby food, interruption and save/reload; old-save
behavior; and legacy Tool Cupboard compatibility confirmation. No native or
save-reload acceptance is claimed.

### BUG-KS-054 — Sandbox options missing because parser rejected comments

**Status:** fixed offline, restaged, live-menu retest pending. The owner reported that no Knox Survivors Sandbox options appeared after deployment. The newest `console.txt` confirms the game loaded the Workshop development root and then `CustomSandboxOptions.parse` failed on `unknown block type "--"`. Seven Lua-style section comments added during page organization were invalid for the Build 42 Sandbox parser. Removed those comments without changing option declarations or translated page identifiers; added a focused regression that prevents comment lines from returning. No unrelated setting was removed or renamed by this fix.

**Verification:** focused Sandbox settings test, `tools/verify.ps1 -SkipJava`, `git diff --check`; then `deployDev` and SHA-256 parity for source, local mod, and Workshop payload. Exact results are reported in the session completion. Tests under ignored `tools/` are local-only evidence.

**Next:** restart Build 42, open Sandbox > Knox Survivors, confirm the seven pages/options appear and no `CustomSandboxOptions` exception is logged. Then continue the already-queued Auto-Loot live checks. Do not repeat the source audit absent new evidence.


### BUG-KS-030 — player vehicle-follow handoff and direct driver order (2026-10-01)

Status: offline_implemented_live_pending
Owner: Codex / Luna; Human for Build 42 acceptance

Added player-enter/exit synchronization for nearby same-floor Follow companions
through `KS_CompanionVehicles`, a per-companion nearest loaded vehicle driver
order, and failure feedback for individual vehicle context commands. Passenger
entry uses vanilla path/enter actions; driver admission still uses the existing
Experimental NPC Driving gate and native readiness/route checks; player exit
uses vanilla exit and only targets companions in the exact vehicle. Held,
directed, base-duty, distant, and non-party survivors remain outside automatic
sync. Eight focused scripts (`test-companion-vehicles.lua`,
`test-vehicle-driver.lua`, `test-vehicle-ownership.lua`,
`test-vehicle-navigation.lua`, `test-vehicle-journeys.lua`,
`test-vehicle-boarding-urgency.lua`, `test-companion-commands.lua`, and
`test-order-routing.lua`) passed. `tools/verify.ps1 -SkipJava` passed 102 Lua
sources, 197 regression scripts, 299 checks, 0 failures; `git diff --check`
passed. Tests under `tools/` are ignored/local-only. The source payload was
staged with `deployDev`; source and local mod roots match across all 113 files,
and the Workshop mod root contains the same 113 plus the two generated Knox
Bridge agent files. This is not live acceptance or Steam upload. Next: owner tests a one-player/one-Follow-companion
car, with Experimental NPC Driving both disabled and enabled, then checks manual
nearest driver order and native interruption/exit behavior. Retain BUG-KS-030
for the existing full vehicle matrix.

### BUG-KS-030 — locked passenger door was misclassified as no seat (2026-10-01)

Status: offline_fixed_live_pending

Compared `KS_CompanionVehicles.usablePassengerSeat` with the installed Build 42
`ISVehicleMenu.onEnterAux` path. Knox rejected an installed, unoccupied passenger
seat whenever its door was locked, then reported `no_free_passenger_seat`; vanilla
instead queues the native unlock/open/enter/close actions and lets native key and
lock state decide the outcome. Boarding now mirrors that sequence, including
vanilla's real key-on-door transfer path. The focused vehicle fixtures verify
that a locked-door seat queues the native action order. This does not claim a
real survivor has the key/permission or that Build 42 completes the sequence.

Focused tests: `test-companion-vehicles.lua`, `test-vehicle-driver.lua`, and
`test-vehicle-ownership.lua`. Full verifier and staging results are recorded in
the session report; local `tools/` tests remain ignored by Git. Next live test:
with a companion Follow roster, enter a car whose passenger doors are locked,
confirm the companion uses the native unlock/open/enter sequence when permitted,
and confirm a refused unlock does not create entry or a false seat receipt.

### 2026-10-01 owner retest follow-up — BUG-KS-030 / BUG-KS-041 / BUG-KS-048

**Status:** source corrections implemented offline; restage and Build 42 retest required. The newest `2026-10-01_03-53_DebugLog.txt` proves work-preference clicks still failed in `normalizeWorkPreferences` at `KS_Persistence.lua:49`; the function called Kahlua-unavailable global `next`. It now uses the existing `pairs` iteration to detect retained values. Separately, installed vanilla `ISButton` requires its `background` flag for assigned fills to render; Notebook schedule-hour and work-preference cells now enable that flag and preserve fill on hover. The current-hour gold border/star is a separate, intentional indicator. Vehicle boarding now requests native jog during the existing path action and restores the prior running flag on success or teardown.

**Verification:** `test-work-priorities.lua`, `test-notebook-schedule-clarity.lua`, `test-notebook-refresh.lua`, `test-notebook-base-context.lua`, `test-vehicle-driver.lua`, and `test-companion-vehicles.lua` pass. `tools/verify.ps1 -SkipJava` passed 102 Lua files, 197 regression scripts, 299 checks, 0 failures; `git diff --check` passed. `deployDev` passed and all 113 repository mod files match both local and Workshop development payloads by SHA-256; two generated Knox Bridge agent files remain Workshop-only. Tests under ignored `tools/` are local-only. Human replay: select a player-owned base resident, change preference without Lua error, select a paint tool and paint several hours, save/reopen and confirm cell fills differ while the current-hour outline remains; then have a Follow companion board the player's vehicle and observe jog pace plus restoration after entry/cancellation. Native UI and animation are live-pending.

**BUG-KS-048 follow-up — current-hour source corrected offline; live-pending.** The owner observed the highlight stuck on hour 12 at 17:00. The existing duty window serializer round-trips all 24 assignments; the UI clock helper was the confirmed divergence, using a helper with a noon fallback. It now reads the native game clock and has a singleton fallback, without fabricating a marker when unavailable. Focused and full verification passed; retest painted colors, Save Hours, reopen persistence, and 17:00 highlight in Build 42. Do not repeat the serializer audit absent new evidence.

**BUG-KS-048 follow-up — painted colors reverted on refresh.** Confirmed source cause: Build 42 `ISButton:setEnable()` restores `backgroundColorEnabled`, but Notebook only changed visible/hover colors. A shared color setter now updates the native restore cache as well for schedule cells, tools, and preference cells. Focused regression reproduces the stale-cache restore and verifies the chosen color survives. Full offline verification passed; restage and confirm visible color persistence and schedule save/reopen in Build 42.

**BUG-KS-047 follow-up — intermittent F prompt and invalid actions.** Confirmed source mismatch: prompt update admitted aiming players although the key handler rejected them, and range visibility used NPC-to-player sight rather than player-to-NPC sight. Prompt and F admission now agree on aiming and the prompt uses player sight. Removed all prompt panel fills/borders so only the resolved key/talk text is drawn. Trade, Give Item, and Recruit are filtered from the F panel for player-owned companions, factions, and grouped survivors; independent ungrouped survivors retain valid options. Focused social UI tests pass. Restage and confirm prompt visibility/key behavior and action lists in Build 42; native visibility and input remain live-pending.
## 2026-10-01 command-surface continuation — KS-PROD-008 Slice G

**Offline slice complete; Build 42 radial/input acceptance pending.** The
player chooses between two independent Sandbox options: `ShowRadialOrders`
(default on) and the compatibility key `ShowLegacyContextCommands` (default
off). Right-click order menus no longer appear as an automatic fallback when
the radial is unavailable. With the context option off, survivor, party,
resident, clicked-location, and map-driving order menus are suppressed. F talk,
survivor view/care, base management, storage assignment, and native target
interactions remain separate. The duplicate `Interact (F)` right-click item
was removed; Nearby Survivors radial still opens the shared F interaction
panel, whose existing eligibility checks own Trade/Give/Recruit availability.

Radial pages were reorganized into compact movement, survival, tactic,
vehicle, gear, formation, resident-work, and resident-policy categories. They
reuse CompanionService, base supply/work setters, formation/permission
policies, base picker, and the shared interaction UI. A loaded resident listing
now aggregates the player's owned base IDs with duplicate identity filtering.
No new order executor, movement owner, or autonomy policy was added.

Focused radial, order-menu, social UI, and map-driving tests pass; local-only
tests under ignored `tools/` are not tracked in Git. Next: live Build 42 check
that radial category selection/back navigation works with mouse and joypad,
each order reaches the existing service, context orders remain entirely hidden
when disabled, and enabling context orders restores the alternate path. Map
point destinations require the context option; arbitrary clicked coordinates
cannot be selected on the emote radial. Do not claim native menu/input
acceptance from offline tests. Separately scope the player-owned companion
"Use Judgment / Orders Only" policy before changing autonomy admissions; never
gate needs, danger, combat, explicit orders, formation, traversal, vehicles, or
recovery.

## 2026-10-01 owner follow-up — spouse, item search, power, and scroll behavior

| Request | Evidence / status | Next acceptance or owner |
|---|---|---|
| Starting spouse variety and player-death continuity | `BUG-KS-055` confirmed/fixed offline. Identity randomness is saved once per fresh save; reload/retry retain it. Household succession explicitly skips a second spouse and keeps the current spouse as a resident. | Build 42: compare fresh saves, reload one spouse, then test both player-death continuation settings. |
| Find needed medical/tools/weapons/clothing | Confirmed offline gap in `find_medical`: the order excluded medicine already listed by the shared loot classifier. Fixed by reusing `KnoxSurvivorLooting.isMedicalSupply`. Tools, meaningful weapon upgrades, clothing, and ammunition already have separate selectors; transfers remain native/live-pending. | Build 42: issue each search order with one valid real item in a nearby searchable container; verify exact item receipt, no fabricated result, interruption, and retry. |
| Sprinters target survivors as they target players | Native/live question; no current log/replay proves whether Build 42 zombie target selection admits Knox survivor bodies. Do not assign targets or simulate zombie AI in Lua. | Live: same sprinting zombie, same distance/LOS, compare player and survivor target acquisition and pursuit, with no other target in range. |
| Generators, lights, gas pumps, appliance power | Partial existing behavior: loaded autonomy can use supported native light/TV power APIs; cooking requires a supported appliance power/heat signal. No general generator service/refueling or gas-pump power workflow is present. Feature gap, not a confirmed bug. | Define one PZ-native use case and verify generator/device/pump APIs, resources, result receipts, and interruption before implementation. |
| Scrollable tabs appear to move together | Source review finds per-tab Notebook view objects and independent list state; Base & Work uses an outer page scroller with three bounded data-list scrollers. No shared global scroll state confirmed; wheel dispatch/render behavior needs the game. | Build 42: use each tab at distinct scroll offsets; wheel over Base/Storage lists versus page whitespace; switch tabs, return, resize, and repeat in other Knox views. Identify which component actually moves before patching. |

Do not repeat the spouse identity or medical-goal source fixes without new
evidence. The other reports remain native/live-only or scoped feature work.

### 2026-10-01 owner follow-up — sleep/bed continuity, zombie sprinting, storage filters

| Request | Offline result | Next action |
|---|---|---|
| Owned and independent survivors sleep when tired; use best/assigned bed | Confirmed controller arbitration gap for player companions: any direct order converted both ordinary rest and actual sleep into roaming. Fixed only the sleep case; durable order is preserved and resumes after native recovery. Existing shared Needs path already selects validated assigned beds before fallback beds. Faction base upkeep now assigns distinct reachable native beds to loaded residents leader-first when automatic faction work-area/storage generation is enabled. Persistence tags auto beds by faction/base and protects manual player bed records. | Offline-fixed; focused sleep/bed/persistence tests pass. Full gate: 102 Lua source syntax checks, 199 regression scripts, 301 checks, 0 failures; `git diff --check` passed. Local `tools/` tests are ignored. Build 42: test follower at sleep threshold, assigned-bed selection, faction leader/member beds, upstairs route, threat interruption/wake, preserved order/duty, save/reload, and rematerialization. |
| Sprinter zombies do not appear to pursue survivors like the player | Source has no Knox sprint/pursuit override; perception may pass exposed native survivor targets through the bridge, while native zombie AI owns target admission, speed, and attack. No supplied live log proves a divergence. | Native/live-only, unchanged. Compare one sprinting zombie vs player and stationary survivor at equal distance/LOS without alternate targets; record target and pursuit speed. Do not add forced targeting or simulated sprint. |
| Container filters and automatic container use | Offline implementation extended: any loaded eligible container inside an owned home/outpost is discoverable without creating a saved policy; saved vanilla `DisplayCategory` filters and Knox convenience filters direct preferred storage; matching filtered containers rank ahead of unfiltered fallback. Single-container objects now open `Set Filters…` directly from the first right-click menu; multi-compartment objects retain an explicit compartment submenu. Existing retrieval, deposit, organizer, job-material, and needs paths remain owners. See the 2026-10-01 storage clarification continuation. | Build 42: inspect right-click **Set Filters…** window, vanilla category checkboxes, save/reopen, filtered-first and nearest-match behavior, unfiltered fallback, all residents’ deposits/withdrawals, chest-to-chest organizing, real capacity/full/reachability, and save/reload in Home and Outpost 2. No ground placement until exact-square native receipt/rollback is proven. |
| Resident cleaning order and useful free-time cleaning | Feature gap, not a confirmed defect. Existing carried-inventory cleanup and hygiene are separate; neither cleans house items/surfaces. | Design a bounded first native-action slice: explicit resident/follower cleaning request and low-priority base-duty free time only when safe, bored/idle, reachable, and no work/urgent need/order competes. Identify what world state is cleanable and which native actions prove completion before implementation. Do not add ambient animation or fabricate floor cleanup. |
| Filtered `Storage Zone` with four items per square arranged at corners | Confirmed feature gap, not a safe offline defect. Current native floor transfer can select current/adjacent squares and does not prove an exact zone square, exact item receipt, or rollback after ambiguous partial transfer. | Deferred until native exact-square placement and inverse-transfer contract are proven. Keep real items only; no abstract stock or fabricated four-corner placement. |

Do not repeat the direct-order sleep arbitration review or the existing ground
transfer audit without new evidence. Full-game sprinter pursuit, sleep, and bed
movement remain native Build 42 acceptance items.

### KS-PROD-008 Slice L — isolated Base & Work scrolling and container filters

Status: offline_complete_live_pending
Owner: Codex / Luna; Human for Build 42 acceptance

The Base & Work page consumes a wheel event that bubbles from a hovered list
without forwarding it to the child a second time. The owner's screenshot then
exposed the actual visual defect: Knox's custom Notebook row renderers omitted
the native `ISScrollingListBox` offscreen-row guard. All six custom list
renderers now skip rows outside their viewport while preserving row-height
accounting. The existing container policy now supports a versioned multi-category
filter list configured through a large, scrollable right-click **Set Filters…**
window. The window reads vanilla `DisplayCategory` values from the game's script
item registry and also offers Knox convenience groups plus General Storage. Any
eligible loaded real container inside an owned base/outpost can be used without
assignment; this fallback is a transient reference only and does not write a
policy, name, or capacity. Configured matching filters are preferred before
unfiltered real-container fallback. Filters gate deposits, organizer
destinations, base task-material retrieval, food/water supply retrieval, and
storage-based log processing through existing owners. Editing an old role
creates the filter version; untouched old saves keep their prior role and
priority. Existing mismatching contents remain physically untouched. Ground
zones, item ledgers, and second storage owners were not added.

Focused `test-notebook-layout.lua`, `test-base-storage-menu.lua`,
`test-base-storage.lua`, `test-companion-base-domain.lua`,
`test-autonomy-water-source.lua`, `test-base-woodcutting.lua`,
`test-base-needs.lua`, `test-base-organize-wiring.lua`,
`test-base-supply-routing.lua`, `test-base-task-supply-entry.lua`, and
`test-base-setup-ui.lua` passed. The first full run found one obsolete
`test-base-setup-ui.lua` assertion for the old one-role menu text; it was
updated to require the new filter instruction. The rerun passed 102 Lua source
syntax checks, 199 regression scripts, 301 checks, 0 failures with Java
skipped; `git diff --check` passed. Tests under ignored `tools/` are local-only.
Build 42 must confirm visible
scroll containment, right-click and joypad usability, real native item movement,
category matching, old-save behavior, container capacity/contents, and
save/reload. Keep `BUG-KS-014` ground placement deferred until exact target
square, native receipt, and rollback are proven. Do not repeat this offline
boundary absent new evidence.

### 2026-10-01 storage clarification continuation

The owner clarified that all eligible base-radius containers participate
without right-click assignment, while explicit filters guide organization.
Implemented an offline vertical slice: the right-click action opens a dedicated
large scrolling filter window populated from vanilla `DisplayCategory` script
items plus Knox groups; validated native-category keys persist in the existing
per-container record. Loaded unconfigured real containers are transiently
discovered for deposits, source lookups, needs/job supply, and the existing
organizer. Filtered matches are preferred, with unconfigured containers as
real-item fallback. Organizer can move a misplaced item from an unconfigured
chest to a matching explicit filter through its existing one-item transfer
path; it does not bounce items between unconfigured chests. No policy/capacity/
name mutation occurs during discovery.

Focused storage-filter UI, menu, storage, organizer, supply, needs, water,
woodcutting, base setup, task supply, and ownership tests passed. Verifier:
103 Lua sources, 200 regression scripts, 303 checks, 0 failures; Java skipped.
`git diff --check` passed. `tools/` test files are ignored/local-only. Build 42
visual, joypad, transfer, reachability, capacity, native task, and save/reload
acceptance remains open. `deployDev` passed its Build 42 jar/API/Java tasks;
SHA-256 matched all 110 source mod files in both local and Workshop `Contents`
payloads, with only the two expected generated agent files extra in Workshop.
No upload or live run occurred. House cleaning and ground `Storage Zone` are
separate feature gaps; no whole-house cleaning action or exact-square ground
placement was added.

### BUG-KS-056 — Kahlua-safe storage filters and capacity cleanup
The 2026-10-01 09:02 log confirmed `clearInfinite` called unavailable global
`next`, throwing on a storage removal click. The same source hazard affected
filter save/toggle/clear. All storage-owner checks now use `pairs` iteration.
Focused tests run these paths with `next=nil`; full verification passed 103 Lua
sources, 200 regressions, 303 checks, 0 failures. `git diff --check` passed.
Workshop development copy is updated for the changed Lua files and must be
reloaded by restarting Build 42. Live filter UI and capacity restoration remain
pending. The accompanying missing-squad/resident report is not explained by
this error: the log retains the 48-survivor population ledger but lacks owned
roster IDs; request the smallest DebugLog slice from the next reproduction
before changing persistent identity/materialization.

### BUG-KS-057 — faction scheduled sleep reaches native recovery
Status: offline_fixed_live_pending
Priority: high
Owner: Codex / Luna; Human for Build 42 acceptance

Shared loaded needs arbitration already covers independents, groups, faction
and player residents, and companion controllers. Unloaded records advance
hunger, thirst, fatigue, sleep/rest, and real persisted supplies. Night shelter
uses native movement and a persisted group objective for traveling groups.
The confirmed gap was narrower: faction-owned base residents assigned the
`sleep` schedule entered ambient sitting/rest instead of native sleep.

The faction-only scheduled path now enters `beginRecovery("sleep")`, reusing
assigned-bed selection and native sleep. Player-owned base schedule behavior is
unchanged; no universal night scheduler or offscreen world-sleep effect was
added. Focused sleep/needs/bed/camp/group/unloaded checks and full verifier
results are in the current implementation record below. Tests under ignored
`tools/` are local-only evidence.

Next: Build 42 compare an NPC faction base resident on a scheduled sleep window
with assigned bed, then no-bed fallback, interruption by danger, and save/reload.
Also replay an independent survivor, traveling group leader/follower, camp member,
and player base resident to confirm their existing paths remain intact.

Offline verification for BUG-KS-057: focused faction scheduled sleep,
shared needs, assigned-bed recovery, faction-bed ownership, camp, group,
night-shelter, and unloaded-survival checks passed. `tools/verify.ps1
-SkipJava` passed 103 Lua sources, 201 regression scripts, 304 checks, 0
failures. `git diff --check` passed with repository line-ending warnings only.
The changed controller was SHA-256 synchronized to the local mod, Workshop
Contents staging, and subscribed Workshop cache. No live test or upload.

### BUG-KS-058 — hibernation removal refusal recovery

Status: offline_fixed_live_pending
Priority: high
Owner: Codex / Luna; Human for Build 42

Source confirmed that a body left alive by a failed native hibernation removal
was left in a `STOPPED` controller while still registered and excluded from
unloaded simulation. The path now rolls the same identity's stored ledger back
to `loaded`, then resumes that existing shell through normal controller
arbitration. Failed persistence rollback stays explicitly pending and retries
only ledger reconciliation; it does not repeat teardown or create a body.
Healthy `hibernated`/`Away` logical survivors remain offscreen and continue
through their existing ledger owners.

Focused lifecycle, persistence, unloaded survival, world presence, away team,
group, base return, and same-shell recovery tests passed. Full verifier and
`git diff --check` results are recorded in CURRENT_STATE. Tests in ignored
`tools/` are local-only.

Next: Build 42 verify a controlled native remove refusal if safely reproducible,
then confirm the same survivor resumes; separately test normal hibernate and
same-ID rematerialization, save/menu boundary behavior, inventory/equipment,
orders, group/faction membership, and no duplicate body. Do not test by
corrupting a player's only save.

### 2026-10-01 owner follow-up — roster body, filter clicks, radial availability

Planner/Terra source map selected the exact lifecycle/UI boundaries from the
owner's visible report; quiet or incomplete logs were not used to dismiss it.

| Item | Result | Status / next action |
|---|---|---|
| Owned survivor absent after load/Resident→Party | 11:32 Build 42 log repeatedly deferred Stacy (`ks-world-4`); 11:47 save still retains player-1 Follow, hibernated/sleeping, canonical native record x=1468,y=7310,z=1. Sleep is accepted; no safe loaded square was found near the saved upstairs position. Offline fix: after saved-square failure, explicit player-owned Follow may restore the same ID within four tiles of the owning player on a safe loaded tile on the player's current floor. Hold, base residents, and independent survivors remain unchanged. | `BUG-KS-059 offline follow fallback; Build 42 pending`. Stage and load `playtest01`; with Stacy still on Follow, verify one same-ID body appears near the owner, inventory/identity/order remain, no duplicate occurs, and the log records `activation-fallback` followed by population activation. If it fails, capture the new per-ID log. Safe assigned-base fallback for player base residents is a separate candidate. |
| Container filter UI discoverability and checkmarks | Owner reported the filter UI/checkmarks still were not apparent. The action was nested under the Knox world-object submenu; single-container **Set Filters…** now appears directly on the world-object menu, while multi-compartment filters have a direct **Set Container Filters** submenu. Native `ISScrollingListBox` callback payload is handled; selected rows now have a filled green indicator and plain `X`. | `BUG-KS-060 offline-corrected_live-pending`; confirm in Build 42 that the direct action opens, checks visibly update, multi-select works, save/reopen preserves them, and Home/Outpost target the right base. |
| Radial options unavailable with offscreen party | Radial root and party-wide tab were incorrectly gated on a nearby loaded follower although party-wide commands target the durable roster. Fixed visibility; individual follower actions remain nearby-body-gated. | `BUG-KS-061 offline_fixed_live_pending`; confirm vanilla emote radial shows Knox Orders and party-wide commands in Build 42. |
| Repeated Kahlua errors on startup/autonomy tick | Latest DebugLog contains 334 `Object tried to call nil in emptyList` failures. `KS_KnoxEvents` called unavailable global `next()` during validation and corruption recovery; both paths now iterate with `pairs`. The `Sleeping` activity label is independently derived from an offscreen sleep phase; party order remains `Following`, with exact survivor sleep state uncorrelated in the log. | `BUG-KS-062 offline_fixed_staged_live-pending`; restart staged Build 42 and confirm errors stop, then verify same-ID survivor appears and inspect order/activity when moved into Party. |

Focused tests: storage-filter UI/menu, radial orders, stale active-body recovery,
world-population candidates (including same-ID Follow fallback), unloaded
survival, lifecycle policy, persistence recovery, detached companion lifecycle,
and companion sync all pass. Full verification: `tools/verify.ps1 -SkipJava`
passed 103 Lua sources, 203 regression scripts, 306 checks, 0 failures. The
focused test under ignored `tools/` is local-only evidence. No Java source
changed and no live test occurred. `git diff --check` passed. `deployDev`
succeeded; all 114 repository `mod/` files match both
`Zomboid\mods\KnoxSurvivors` and Workshop `Contents/mods/KnoxSurvivors` by
SHA-256 with 0 differences. This does not publish the Workshop item. Preserve
the unrelated dirty tree; do not repeat these offline traces absent new
evidence.
