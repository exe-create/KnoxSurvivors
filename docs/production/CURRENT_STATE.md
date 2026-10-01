<!-- modforge-doc
authority: canonical
load: always
purpose: current production position and immediate goal
-->

# Knox Survivors — current production state

Updated: 2026-10-01

## Repository baseline

The connected GitHub repository is `exe-create/KnoxSurvivors`. The last recorded
release/package candidate is commit `e93ed2655470212a6e78305171ccff63f7893c58`
on `main`, whose remote head matched when verified on 2026-09-29. Its full
offline/package evidence below applies to that candidate only; it is not an
exact-worktree or current release-readiness claim.

## Current worktree

The current checkout is on `main` at `624caacd283bcd442964b11b58dffc42a6e67a57`
and is **dirty relative to that HEAD**. `e93ed26` is retained package history.
It contains multiple
uncommitted gameplay, test-harness, and documentation work layers, including
companions/party cohesion and destinations, combat/firearms, storage/base work,
vehicles, social/group behavior, persistence, and player-facing commands. The
source-specific additions are described in the canonical package entries below;
older package results are not implicitly promoted to the current tree. The
current dirty worktree most recently passed the Lua-only offline verifier (103
Lua sources, 200 regression scripts, 303 checks, 0 failures). The later
`deployDev` staging also passed its Build 42 jar/API checks and Java task; the
local payload and Workshop `Contents` match the 110-file source mod payload,
with only the two expected generated agent files extra in Workshop. This is
local staging, not a Workshop upload or live acceptance. Local `tools/` regressions are ignored by
Git policy. The unrelated untracked artwork is not part of this development
scope and was left untouched. The last recorded release candidate remains
`e93ed26`; rerun the appropriate exact-tree gates after further gameplay edits.

The owner completed a Build 42 life test on 2026-09-30. The newest available
debug log (`2026-09-30_02-48_DebugLog.txt`) records a confirmed Crew & Schedule
work-preference click exception at 02:52:29, frame 1875: `next(map)` was nil in
`onCrewPriorityCell`, called by vanilla `ISButton.onMouseUp`. The existing
callback now uses `pairs`, with a focused regression under a Kahlua-shaped
fixture; BUG-KS-041 tracks the live retest. The log does not identify the
selected resident/base or show a base task/native-work sequence, so it does not
resolve the broader visible-idle report in BUG-KS-013. Other older movement and
sprite warnings in this log do not establish a new Knox defect. No post-fix
Build 42 replay has been performed. The corrected source passed the latest
recorded offline gate and `deployDev`; SHA-256 comparison matched all 122 mod
payload files to both the local mod and Workshop `Contents` (the stage also has
its expected agent jar/checksum). This is staging parity, not publication.

Offline review then confirmed a separate multi-base Notebook defect
(`BUG-KS-042`): a second `BaseView:prerender` definition overrode the method
that committed the selected outpost ID, and area-edit actions resolved the
primary base directly. The picker responsibilities now share one method, and
boundary/area add/remove use the validated selected-base resolver. The focused
two-base callback regression and connected Notebook/Base UI checks pass. No
Build 42 retest was performed; visible switching, area actions, reopen, and
save/reload remain open. This does not resolve base naming or territory
geometry reports.

The same offline pass confirmed `BUG-KS-043` in the existing cooking owner:
`KS_BaseCooking.usable` accepted cold, unpowered non-microwave stoves after
checking for power and current heat. The fallback now rejects that unsupported
state; focused cooking/base-work checks pass. This is not proof of the reported
broccoli scenario or of fuel-backed stove behavior. Build 42 power-loss,
residual-heat, fuel, action, and save/reload acceptance remains open.
After both fixes, `deployDev` completed and SHA-256 comparison matched all 122
source mod payload files against both the local development copy and Workshop
`Contents` (0 missing, 0 different). No upload or gameplay test occurred.

The speech/forage Arrow source is already configured as pass-through
(`setWantMouseEvents(false)`) and registers no mouse, keyboard, or vanilla
foraging handlers. Existing coverage checks input preference and expiry; native
UI-manager propagation and Activity Feed overlap remain live-only. Following
the requested fallback, Base & Work was checked for viewport geometry and a
source-confirmed gap was fixed as `BUG-KS-044`: its fixed content extended to
520px at 14px font, but short/split-screen viewports could clamp the tab below
that with no outer scrolling. The view now reports measured content to the
existing `KS_SurvivorUILayout` adapter. Its zone/task/storage lists remain
bounded individual scrollers. Focused geometry and connected UI checks pass;
short-viewport visual, wheel/joypad navigation, and schedule clarity remain
live acceptance.
`tools/verify.ps1 -SkipJava` passed 112 Lua sources, 184 regression scripts,
296 checks, and 0 failures; `git diff --check` passed. The added geometry test
is local under ignored `tools/` policy. `deployDev` succeeded and all 122
source payload hashes match both local and Workshop `Contents` copies (0
missing, 0 different). No Workshop upload or Build 42 test was performed.

The 2026-10-01 owner retest reports that the speech arrow still blocks world
interaction and Base & Work scrolling still appears to leak. The arrow now
explicitly disables capture after UI registration and returns false from all
mouse callbacks; focused input-boundary coverage was added. The scroll
screenshot displays the legacy `Storage: 1 assigned` label, but the current
source/local staged Notebook displays `filtered | usable containers`. The
subscribed Workshop payload is a distinct, older copy (Notebook SHA-256
`14D3A08A...` versus source/local `14DC6B85...`) and lacks the latest row
culling code. The 114 current source files have now been copied into the Steam
subscribed mod folder and match there with 0 missing/different files; 11
obsolete QA/probe Lua files and the generated agent JAR remain as extras because
the environment blocked their cleanup. Use the clean local mod copy and disable
the Workshop entry for the next test, then fully restart the game. The new
arrow and scroll behavior remain unverified in Build 42.

After the pass-through correction, `deployDev` succeeded. All 114 repository
mod payload files match both `C:\Users\Gary\Zomboid\mods\KnoxSurvivors` and
the local Workshop staging `Contents` payload (0 missing, 0 different in each).
The Steam subscribed cache's source files now also match, though 11 obsolete
QA/probe Lua files remain there. The next test must explicitly load the clean
local mod and disable the subscribed duplicate; no Steam upload was made.
Focused speech-indicator and Notebook
layout/base-context tests passed. The latest `tools/verify.ps1 -SkipJava`
passed 103 Lua sources, 200 regression scripts, 303 checks, 0 failures; Java
was skipped. `git diff --check` passed with only the repository's existing
line-ending warnings. Native pass-through and scrolling still need the owner
replay.

The next offline triage found no runtime logs newer than the already-recorded
2026-09-30 session evidence. Planner/Terra reviewed `BUG-KS-017` as the next
bounded candidate: `TerritorySelector` passes clicked squares to the existing
manager; persistence normalizes corners and `containsSquare` uses matching
inclusive bounds. Existing selector, base-domain, and multi-base tests cover
their offline contracts; native click projection and draft highlighting remain
unproven. Connected/disjoint-area support is a feature-model limit, not a
source defect. No code change was made; the exact boundary replay remains in
`DEVELOPMENT_TESTING.md`.

Follow-up user-facing triage found no newer runtime logs than the recorded
September 28 dev-run. Planner/Terra reviewed faction-base markers, schedule
feedback, storage/task visibility, dialogue context, and search/loot result
wording. The markers remain lifecycle-gated; schedule/storage already expose
their saved and task states offline, with visual/native behavior still live;
dialogue consumes existing event and relationship/history context; search has
no offline contradictory success path after the receipt fix. Base naming is an
unscoped feature needing decisions on owner scope and duplicate/length
validation. No source or test change was justified. The dispositions are
recorded in `WORK_QUEUE.md` to prevent repeat audits.

The changed implementation is concentrated in these connected areas:

### Base / settlement / storage

- base setup/context/manager behavior;
- multi-base selection;
- storage routing and organizer behavior;
- supply planning;
- task/duty scheduling;
- associated storage/base regression coverage.

### Companion orders / presentation

- companion service/HUD;
- radial order routing;
- Survivor Card and Notebook;
- inventory/view-model presentation;
- activity/speech indicators;
- associated order/UI/notebook tests.

### Persistence / lifecycle / autonomy

- persistence;
- survivor runtime;
- autonomy and autonomy-controller ownership;
- unloaded survival;
- lifecycle-policy coverage.

### Events / off-screen world continuity

- Knox Events and event runtime;
- world traces;
- unloaded/off-screen behavior;
- related event/world-trace tests.

### Threat awareness

- zombie awareness and focused regression coverage.

These groups define the current candidate reconciliation boundary. They are **not automatically release-verified** merely because earlier checkpoints passed.

## Recent repository history anchors

The 2026-09-30 controlled coherence pass retained the existing system owners and
reviewed the connected social, group, work, supply, threat, equipment, map and
offscreen boundaries. Its compact source/offline/live disposition is under
KS-PROD-008 in `WORK_QUEUE.md`; use that before repeating an audit. BUG-KS-039
received bounded capacity-restoration follow-through. At that review snapshot,
53 Sandbox options were classified across four pages. The later 2026-10-01
organization changed the current inventory to 52 visible options across seven
pages, as recorded below and in `../SANDBOX_SETTINGS.md`. Normal model routing remains Luna
Boss / Luna Planner / Terra support; this Astra pass is an owner-authorized
exception. BUG-KS-013's observed base-life failure remains the first live
priority. The latest recorded full Lua-only gate is 112 sources / 183 scripts /
295 checks / zero failures; native behavior and current package/release readiness remain
unverified.

These are concise anchors only; detailed implementation history remains in `../FEATURE_AUDIT.md` and Git history.

- **2026-09-21:** release-readiness work had reached a 245-check / 0-failure offline snapshot, but live engine acceptance was still required.
- **2026-09-23:** persistent survivor memory/off-screen story stabilization and the alternate runtime Patch API runtime path landed around this period; live acceptance remained pending.
- **2026-09-24:** commit `2f3aeec` (`Stabilize survivor state, UI, and release tooling`) and the retained 272-check integrated stabilization checkpoint.
- **2026-09-25:** GitHub `main` was at the prior baseline `7f56dcb`.
- **2026-09-26:** commit `163b789` consolidated production documentation and coordination contracts, and committed the associated base/storage/UI/autonomy/event/off-screen implementation and regression tests.
- **2026-09-28:** local `main` advanced through bounded vehicle admission/boarding interruption changes to `8c78129`. The latest saved Build 42 diagnostic run is `dev-runs/20260928-021135`; it shows both successful native zombie damage and a mixed-group horde scenario that remained `PARTIAL`.
- **2026-09-29:** release guidance was reconciled with KnoxBridge alpha8; the full Survivors offline gate and native Workshop payload validation passed on the unchanged gameplay candidate `e93ed26`.

## Historical offline evidence

`docs/FEATURE_AUDIT.md` records an integrated stabilization checkpoint dated 2026-09-24 with:

- 107 Lua syntax checks;
- 164 Lua regression scripts;
- Java build/check passing;
- 272 checks total;
- 0 failed.

That evidence predates `163b789`. It remains useful historical evidence, but it is not proof that the current worktree is release-ready.

The retained full gate ran with Java on `decbda5` plus five uncommitted files:
112 Lua sources, 177 Lua scripts, 290 checks, 0 failed. It is not exact-candidate
evidence for `8c78129`. Fresh offline gate on 2026-09-28 after the base-supply
delivery fix: `tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 177
scripts (289 checks, 0 failed). Focused `test-base-auto-scavenge.lua`,
`test-base-needs.lua`, and `test-inventory-cleanup.lua` passed. `git diff --check`
passed. Java checks were intentionally skipped under the offline-first cycle;
workshop staging/package verification remains outstanding.

## 2026-09-29 completion-cycle disposition

The requested base-life offline review is closed for its offline scope: needs,
shortage arbitration, task selection, real-material checks,
claims/reservations, native-action result verification, task-board acceptance,
cleanup, and reassessment form a connected source/test path. No speculative
base-life patch is justified. Keep the full-day base and real loot/storage
reassessment scenarios in Build 42 acceptance; do not repeat the offline audit
without new evidence.

The owner approved a **player-owned companion shared destination** under
`BUG-KS-028`; autonomous NPC/faction leader destination policy remains out of
scope. The existing “Move Party Here” surface now writes one runtime-only
player-scoped command, which each currently eligible companion independently
executes through its existing controller/movement owner. The player remains the
party authority and normal Follow anchor. Player-party cohesion now adds stable
runtime slots, a movement-smoothed heading, compressed leased targets and
distinct destination-area staging while the same controller remains the sole
native movement owner. It does not appoint a companion route leader or alter
NPC/faction formation.
Individual directives take precedence; danger, combat, urgent needs, traversal,
native actions and recovery interrupt and resume through ordinary arbitration.
The shared intent expires after one in-game hour, clears on explicit party-order
cancellation, invalid destination/empty eligible roster, or when every current
participant reaches the same-floor 1.5-tile tolerance. Save/reload continuity is
not implemented because the existing player-scoped persistence record cannot
own this lifecycle safely without a broader order-ownership change. Focused
party-destination, directive-handoff, command-menu, order-routing, companion,
radial, autonomy-formation, relationship-coherence, group-refresh and unloaded-
group regressions passed. The exact-worktree `tools/verify.ps1 -SkipJava` gate
passed with 112 Lua sources, 180 regression scripts, 292 checks and 0 failures.
Build 42 UI, native routing/arrival/interruption/resumption and movement behavior
remain unverified; save/reload is intentionally not supported by this runtime-
only slice. BUG-KS-028 and D-025 contain the semantics. Nearby owned-survivor
marker grouping (BUG-KS-021) is now implemented as a derived projection in the
existing map overlay; Build 42 rendering and streaming acceptance remain open.
Faction-base markers (BUG-KS-022) remain deferred pending lifecycle/live
validation. The scoped base-resident four-state BUG-KS-023 slice is now
implemented offline; broader profiles and new work categories still need scope.

Exact worktree evidence for this disposition: focused base-life suite 10/10;
`tools/verify.ps1 -SkipJava` passed with 112 Lua sources, 179 regression
scripts, 291 checks, 0 failures; `git diff --check` passed. Tests under ignored
`tools/` remain local-only. No gameplay source changed in this pass and no
Build 42 behavior is claimed verified.

## BUG-KS-021 nearby owned-survivor map grouping — 2026-09-29

`KS_MapOrders.ownedLocations` remains the read-only source. Its existing
250 ms overlay refresh now derives same-floor groups within a 20-tile XY radius
using deterministic non-transitive anchor clustering. Group labels retain
member names and loaded/persisted/last-known counts; the best-confidence member
supplies the displayed position. Dead evidence stays separate, invalid or
missing coordinates are never fabricated, and the overlay reports survivors
without a usable location. No marker ledger, identity/membership state, or new
map owner was added. Focused map, ownership, persistence, unloaded-survival,
faction-persistence and group regressions passed; the current full offline gate
passed with 112 Lua sources, 181 regression scripts, 293 checks and 0 failures.
The focused `tools/` regression remains ignored/local. Live Build 42 map
projection, appearance, interaction, streaming/recomputation and save/reload
remain pending.

## 2026-09-29 release candidate verification

The full `tools/verify.ps1` gate passed on source candidate `e93ed26`: 112 Lua
sources, 178 regression scripts, 291 checks, 0 failures, including the Java
check/build. `gradlew.bat prepareWorkshopUpload` staged the existing Workshop
item `3749727604` from that source. The installed Build 42 native payload
validator passed the staged `Contents`, metadata, preview, KnoxBridge module
descriptor, single module JAR, SHA-256 sidecar, and premain check. The stage has
126 files. Steam publication/download and gameplay remain unverified.

The matching KnoxBridge `0.1.0-alpha8` candidate now stages the main-menu
review gate and remember/one-launch choice handoff. Its offline Java/UI/package
and Windows bootstrap checks pass, but its live Build 42 gate/restart flow still
needs replay. Read-only release checks on 2026-09-29 found GitHub's latest
KnoxBridge release is still alpha5, whose instructions use installer option 2.
The public Survivors Workshop page for item `3749727604` reports that Steam
removed the item from the community and still shows the obsolete Setup.cmd /
option-2 instructions. The local alpha8 Bridge and Survivors stages have not
been uploaded; GitHub and Steam are not in parity. Steam upload and public-page
recovery need owner-side Steam Workshop access. Windows Defender flagged prior
setup artifacts; any flagged binary remains withdrawn.

Fresh exact-worktree evidence on 2026-09-28 after the base-life recovery and
Survivor Card semantic integration updates: `tools/verify.ps1 -SkipJava`
checked 112 Lua sources and ran 177 regression scripts (289 checks, 0 failed).
Focused view-model, Card UI, Notebook refresh/mission ownership, offscreen-story,
relationship-coherence, and survivor-needs checks passed. The Card now surfaces
persisted life-purpose, relationship meeting count, and up to three bounded
memory details through the existing view-model; the focused script remains local
under ignored `tools/` policy. `git diff --check` passed after documentation
updates. Live Build 42 Card readability/scroll behavior at small
and large UI scales remains pending; native gameplay queues remain unchanged.

The next source-confirmed social defect was that `Offer Gift` and `Give Money`
awarded trust and thank-you responses without transferring an item. The
trust-only acts are removed; `Give Item` now opens the existing exchange UI in
one-way mode and uses its real transfer/capacity/receipt/rollback/capture
owner. Relationship credit comes only after verified receipt. Abstract `Give
Money` remains absent, while real supported currency items are selectable.
Focused social-act and Trade valuation/action/UI regressions and the exact-
worktree full offline gate passed on 2026-09-28: 112 Lua sources, 177 scripts,
289 checks, 0 failures. `BUG-KS-032` and D-020 record the boundary. The four
focused test edits are local under ignored `tools/` policy and are not tracked
Git evidence. Native item gift/barter receipt, capacity, cancellation, and
save/reload remain Build 42 acceptance items.

The current QA improvement extends the existing survivor status command with
up to twelve recent failures from the autonomy controller's shared failure
owner. The session-only records contain bounded scalar context (tick, cause,
state, decision, retry deadline, and position when available); they do not
persist and do not record every tick. Focused autonomy/formation,
developer-menu, debug-log, and combat-scenario-reporting checks passed. The
exact-worktree offline gate passed on 2026-09-28: 112 Lua sources, 177
regression scripts, 289 checks, 0 failures; Java was skipped. This remains
diagnostic evidence only and does not verify Build 42 behavior.

The next gameplay review found the existing needs/food implementation sound
through real-item selection, native eat action, and verified hunger reduction,
but ordinary active base-task states did not revisit that needs owner. The
autonomy controller now gives eligible ordinary task states a bounded urgent-
need yield, using the existing suspension path to retain the base task claim
and release movement/action/transfer state through its current owners. Focused
tests cover work/action/supply-task interruption, no interruption below the
need threshold, verified self-care, and task resumption; connected needs,
cooking, security, task, and arrival regressions pass. Exact-worktree
`tools/verify.ps1 -SkipJava` checked 112 Lua sources, ran 177 regression
scripts, and passed 289 checks with 0 failures. The regression edits remain
local under ignored `tools/` policy. The September 23 public hunger report is
not reproduced or confirmed by this offline evidence. Build 42 must verify
native food access/eating, cancellation and same-task resumption, including
urgent hunger during a supply transfer and unavailable-food recovery.

## Current release state

- Public release line: `0.3.0-rc1`.
- Existing public candidate target: Project Zomboid `42.20.4`.
- Current compatibility-test target: Project Zomboid `42.21.0` Stable. The
  existing mod files now declare support metadata through 42.21, but Knox
  gameplay compatibility is not verified yet; see `KS-PROD-010`.
- The configured local Workshop `Contents` folder was replaced from current
  source and now declares `42.20–42.21`. The prior 125 files are backed up in
  ignored `build/pre-knoxbridge-full-stage-backup`. The staged payload scan
  found no external Java runtime references. This records staging before the owner
  reported uploading/updating both Knox Survivors and KnoxBridge Workshop items.
  Publication/access and Required Item linkage still need owner-side
  confirmation; upload is not gameplay or release-gate evidence.
- Current Knox Workshop staging now mirrors the Knox source mod and includes
  the built KnoxBridge module JAR at the descriptor's exact path
  (`42/media/java/knox-agent.jar`). Its `mod.info` declares
  `require=KnoxBridgeRuntime`. The prior staged copy and safety backup are
  outside the upload `Contents` folder. Current upload staging is limited to
  Knox's mod folder plus the existing Workshop preview/metadata.
- KnoxBridge's Workshop item is a required dependency marker and author
  reference: its staging script includes the compile-time API JAR and setup/
  module-author guides, but not the player runtime installer. Players get setup
  from GitHub Releases. The revised staging change has not yet been uploaded or
  verified on Steam. Windows uses a standalone installer; Linux/macOS use a ZIP
  plus Python setup helper and remain unverified live. The owner previously
  reported both Workshop items public; verify Required Item linkage after the
  next Bridge Workshop upload. This is publication status, not gameplay evidence.
- Single-player is the supported focus.
- KnoxBridge is the active Workshop runtime target. The direct Knox legacy
  agent remains only as a source rollback path during migration.
- Focused candidate checks and the complete Lua regression suite are current;
  the full build/staging/package gate in `KS-PROD-003` remains open.
- Engine-bound behavior still requires live Build 42.20.4 acceptance.
- On 2026-09-28 KnoxBridge was updated in the installed PZ directory and
  launched through normal Steam Play in PZ 42.21.0 / Java 25.0.1. PZ's actual
  enabled list resolved KnoxBridgeIndependentTest and KnoxSurvivors to their
  selected roots. Both unknown JARs were blocked on the first run, then exact
  hashes were allowed for this requested local test. On restart, both modules
  loaded; the independent module initialized and registered its harmless
  probe, and Knox initialized with its required combat/visibility patches
  ready. `KnoxJavaBridge` was exposed. This proves startup, discovery, trust,
  module entrypoints, patch readiness, and bridge exposure, not in-world NPC
  behavior or persistence.
- Knox now has a `knoxbridge.properties` module descriptor and Java entrypoint;
  its source no longer requires the alternate runtime API. Module migration,
  Build 42.21 transformer checks, and the live runtime/module boundary are
  verified. NPC creation, movement, combat, save/reload, changed-hash/deny
  policy, and 42.20 live compatibility remain open beyond the limited probe
  below. See `KS-PROD-010`.
- During the 42.21 KnoxBridge session, the Knox log recorded native probe
  `ks-dev-1` spawned, door/fence movement transitions, live combat start with a
  baseball bat, attack requests, and zombie health reaching zero. A movement
  route also recorded `FailedStuck`; treat this as narrow bridge/patch/runtime
  evidence, not reliable pathing acceptance. Save/reload was not observed.
- The current KnoxBridge uninstaller restored `ProjectZomboid64.json` to the
  exact backed-up SHA-256. Ordinary Steam startup then succeeded with no new
  KnoxBridge log entry. Reinstall/health check and a second normal Steam launch
  rediscovered and loaded both approved modules. No saves or mod list files
  were targeted by the installer or Workshop staging task.
- The loaded base-supply loop now retains its shortage claim and durable return
  intent until typed storage confirms receipt; see `BUG-KS-031` and KS-PROD-008
  Slice E. Native transfer, capacity, save/reload, and shortage reevaluation
  still need Build 42 acceptance.
- Base-danger arbitration is covered offline. Do not repeat its source audit
  absent new evidence; the one-zombie/small-group combat replay remains live
  acceptance. No release-ready claim was produced by this offline change.

## NPC-system design direction

The owner-approved research direction is now captured in:

`docs/design/NPC_SYSTEM_INSPIRATION.md`

The central rule is that a Knox survivor remains an AI-controlled Project Zomboid survivor, not a colony pawn. Existing autonomy, base jobs, relationships, groups, off-screen simulation and persistence should be connected through clearer shared operating rules rather than replaced by unrelated parallel systems.

Settled 2026-09-28 additions: off-screen life is continuous-real and cheaper, never faked (D-016); population is rare-but-findable with future named modes, hostility is relations-driven, and full politics/creator/MP are deferred future tracks (D-017); danger is Walking-Dead unpredictable with universal living-world first moments, all roadmap systems kept, and join-as-member recorded as future work (D-018). The per-slice completion track for the core loop lives in `WORK_QUEUE.md` `KS-PROD-008`; this cycle's base-life watchdog update is recorded under Slice F.

## Immediate production goal

Complete and connect the existing survivor systems into one reliable playable
loop while preserving their current ownership boundaries:

1. Reconcile identity, persistence, lifecycle and off-screen truth.
2. Make survivor brains, goals, needs, claims and autonomy produce believable
   decisions without controller conflicts.
3. Finish movement, pathing, traversal, native actions and interruption recovery.
4. Finish combat, threat awareness, retreat and resource consequences.
5. Finish storage, bases, jobs, supplies and workforce loops using real items and
   native world actions.
6. Finish companion orders, UI, notebook and player-facing feedback.
7. Complete purposeful implemented events, factions, missions and world activity.
8. Keep the launcher/runtime path compatible with the mod when a boundary needs
   both repositories.
9. Validate performance, balanced defaults and player customization.
10. Run focused, full offline and live Build 42 gates before making release claims.

Do not start unrelated feature families merely because an AI worker is idle.

## System status inventory

Status describes repository/offline evidence only unless the live-evidence
column explicitly records a Build 42 acceptance. “Offline verified” does not
mean engine behavior is verified. The recorded candidate gate is
`163b789a2564ee626bc9d5acdad46674623c25b8`; focused tests were 21/21 and the
full Lua regression set was 174/174 on 2026-09-27. The focused trace fix also
passed `test-world-traces.lua`, `test-event-runtime.lua`, and
`test-knox-events.lua`. No live Build 42 evidence is recorded for these systems.

| System | Implementation state | Status | Known issues | Offline evidence | Live evidence | Owner | Next action |
|---|---|---|---|---|---|---|---|
| Survivor identity and lifecycle | Stable identity separated from temporary engine body; lifecycle/materialization implemented | Offline verified | No confirmed defect; real identity continuity through death, hibernation and reconstruction remains unproven | Lifecycle-policy regression; full Lua suite 174/174 | None recorded | Codex | Replay identity through save/load and hibernation/rematerialization in a disposable save |
| Persistence and save/load | Java survivor records and Lua domain persistence/migrations implemented | Offline verified | Native inventory/body restoration and real save compatibility remain unverified | Persistence-related regressions; full Lua suite 174/174; Java checks recorded in KS-PROD-002 | None recorded | Codex | Save/reload one survivor and compare stable ID, body state, inventory, equipment and orders |
| Off-screen continuity | Bounded unloaded survival, stored-group movement and story state implemented; abstract scuffle outcomes removed; hibernation and away-team dispatch commit ledger ownership before native teardown; blocked dispatches retain only confirmed-removed members until canonical restoration registers them | Offline verified | BUG-KS-001 and BUG-KS-024 remain open for native replay; live parity between loaded and unloaded states is unverified | Focused away-dispatch, lifecycle, virtual-base-return, unloaded-survival/group/base-return, persistence recovery and rematerialization tests pass, including blocked-ledger reload/recovery and finalization failure; `tools/verify.ps1 -SkipJava`: 112 Lua files, 176 scripts, 288 checks, 0 failures | None recorded | Codex | Replay unloaded travel and multi-member dispatch through pre-removal failure, partial teardown, save/reload and rematerialization; verify no duplicate or lost survivor |
| Brains and autonomy | Priority controller, needs, duties, player-party runtime formation and interruption ownership implemented; successful NPC leader roam/regroup routes issue bounded follow through existing follower arbitration; explicit bounded NPC hold remains API-only | Offline verified | Player-party cohesion, shared destination, NPC leader-order timing, native movement/action behavior, cancellation/retry, interruption/resumption, and the destination's intentional save/reload reset require Build 42 observation; no autonomous NPC hold policy or NPC leader-order UI exists | Player-party cohesion/destination, relationship-coherence, autonomy-formation and roaming-autonomy coverage; current exact-worktree gate is recorded below in the 2026-09-29 player-party cohesion section | None recorded | Codex | Disposable player with three companions and destination: ordinary follow, heading/roster changes, doors/fences, combat/needs interruption, catch-up/regroup and world reload reset; retain separate NPC leader-plus-two-followers replay |
| Movement and pathing | Shared movement requests, traversal and retries implemented; formation follow latches native traversal, reevaluates on the first landed update, and reopens group-follow arbitration on the next tick after native route success | Offline verified | BUG-KS-011 and BUG-KS-028 remain open for live fence and multi-follower timing; general doors/windows/path recovery remain unverified | Focused formation, combat/traversal, command, order and conversation regressions pass; full offline gate: 112 Lua files, 176 scripts, 288 checks, 0 failures | Owner observed a several-second post-fence pause and follower stop/think/resume cadence before the corrections; neither is replayed live | Codex | Repeat a leader-plus-two-followers route through ordinary travel, a door/fence, need/combat interruption and recovery; verify no route spam or prolonged post-arrival pause |
| Native actions | Native action adapters and action ownership implemented | Implemented | Native animation, completion, real item transfer and interruption have no live acceptance evidence | Related offline action regressions are included in the 174/174 suite | None recorded | Codex / OpenCode | Verify one native work action and one danger-interrupted action in game |
| Combat and threat awareness | Native combat integration and threat selection implemented; unsafe off-slot lighting-bit assist disabled; bounded retreat admission restored through the existing native movement path | In progress | BUG-KS-009 and BUG-KS-012 need live replay; native damage and route completion remain unverified | Focused zombie-awareness, combat-intelligence, formation, companion/order, and conversation regressions pass; full Lua suite 175/175 (287 checks) | Build 42.20.4 QA observation recorded the LightingJNI error and owner observed risky multi-zombie commitment; neither corrected combat nor retreat behavior is live-verified | Codex | Run one controlled combat replay: healthy one-zombie/small-group hold, then overwhelming-group retreat through a viable lane and recovery without a loop |
| Inventory and storage | Native item snapshots, routing, organizer and transfer logic implemented; Logs & Lumber and General Storage roles are assignable through the persisted container policy | Offline verified | Real item transfer, nested-item persistence, resource consumption, and loose ground-item pickup remain unverified; broader reported misrouting needs a live/current reproducer | Focused base/storage/job/resupply tests, including typed roles, general fallback, logs/firewood matching; full Lua suite 175/175 (287 checks). Native `VehicleMaintenance` parts (tires, batteries, brakes, gas tanks) now route to Materials via the existing building matcher with focused + full offline evidence in Slice E (112/176/288, 0 failed); native transfer, capacity/weight, save/reload, and vehicle acquisition behavior remain live-only. | None recorded | Codex / OpenCode | Live-test real item deposit, General fallback, log/firewood routing, and save/reload identity/count |
| Bases and jobs | Base ownership, task claims, supply planning and job scheduling implemented; organizer and base-life watchdog cleanup use existing interruption/recovery owners | Offline verified | BUG-KS-013 remains in progress; native timed action, transfer, base-duty/UI behavior, visible base-life and task completion remain unverified | Dynamic organizer duty-change regression; seven focused base-life/recovery checks including `test-base-leisure-routing.lua` patrol/return/rest watchdog dispatch; full offline gate: 112 Lua sources, 177 scripts, 289 checks, 0 failures | None recorded | Codex / OpenCode | Observe a full day at a two-resident base; force stalled rest and patrol/return routes, verify fallback/released claims, then complete one real-resource job |
| Companions, orders and UI | Companion directives, order routing, card/notebook and HUD implemented; stale-shell detachment has bounded hibernation/recovery handling; speech overlay is transparent and input-pass-through configured | Offline verified | BUG-KS-008 lifecycle and BUG-KS-010 rendered indicator/right-click behavior remain open for live validation | Focused lifecycle/order/persistence tests plus speech style/input/expiry/stale-coordinate regression pass | Owner observed a black/ugly arrow and apparent right-click loss before the correction; corrected rendering and input behavior have not been replayed live | Codex | Replay the speech indicator in Build 42, visually confirm projection/colour, and open world context menus outside and over the Activity Feed |
| Events, factions, raids and world activity | Persistent event/faction systems; unloaded raids retain stored travel/arrival and pause at the native active/objective boundary | Blocked | BUG-KS-001 remains open until live loaded → unloaded → loaded replay; BUG-KS-002 native trace replay remains required | Six focused event/trace tests passed; full Lua verification: 112 sources, 174 scripts, 286 checks, 0 failed | None recorded | Codex | Run the disposable-save raid replay and inspect loaded combat, history, trace, and roster ownership |
| Launcher/runtime compatibility | KnoxBridge is the sole supported public Knox runtime; separate Knox Survivors Launcher is deprecated/unsupported and its requested privacy change is pending; direct legacy agent is rollback-only | In progress | KS-PROD-010: current approval dialog, Linux/macOS startup, save/reload, and full gameplay acceptance remain open | KnoxBridge runtime and setup checks; existing Windows Steam evidence is for an earlier packaged installer | Current alpha6 approval UI and package need fresh Windows replay; no Linux/macOS live startup or Knox save/reload evidence | Codex / Human | Keep the user path on KnoxBridge; publish the current Bridge Workshop author-reference payload and validate startup/gameplay on disposable saves |
| external runtime interoperability | Not a supported Knox startup path; old notes are historical, and KnoxBridge is the active runtime target | Not started | Existing modules that use other Java runtimes are not compatible unless ported; competing instrumentation must not be stacked | Source-level competing-bootstrap block; no live compatibility/stacking test; published external Java runtime page describes an older B42 range | None recorded | Codex / Human | Keep compatibility claims limited to KnoxBridge modules; do not use external Java runtime as the technical baseline |
| Performance, defaults and customization | Conservative defaults and configurable limits/settings exist in implemented systems | Implemented | No end-to-end live performance measurement or unified customization acceptance recorded | Regression suite passes; no dedicated performance acceptance recorded | None recorded | Codex / OpenCode | Measure population/action loop cost and verify meaningful settings in a fresh save |
| Vehicles and driving | Shared admission verdict (driver/engine/driveability/speed/towing/fuel/locks with reason codes); group boarding roster attaches to its driver run; offline rollback respects exact vehicle ownership and cannot cancel a stale roster member's newer other-vehicle run | Offline defect fixed; live acceptance pending | BUG-KS-030 remains open for native fuel/condition/lock semantics, real boarding/driving, occupied save/reload, unloaded/rematerialized continuity, multi-car runs, convoy spacing, control release, and part consumption | Connected vehicle set and current full gate passed: 112 Lua sources, 181 regression scripts, 293 checks, 0 failures | None recorded | Codex / OpenCode | Run the full vehicle acceptance matrix in `DEVELOPMENT_TESTING.md`, including occupied save/reload and identity/inventory/order/group continuity; seat restoration is not implemented |

## Main active risk

The main risks are **evidence drift** and **system overlap**: implementation is
substantial, but several connected boundaries still need focused/live proof and
must be completed through their existing owners rather than parallel replacements.

The documentation structure has been simplified so ModForge, Codex, OpenCode
and normal human work share one current operational truth instead of competing
old plans and release snapshots. ModForge is optional; its generated state is a
convenience snapshot and never replaces the repository records.

## Assigned-storage traversal recovery — 2026-09-28

The current autonomy controller already recovered entry failures during the
work-site leg, but failed a claimed base job immediately when its assigned
storage pickup route encountered an entry-related native failure. The pickup
uses one real item and a transient item/container reservation. It now feeds the
assigned container's room and exact approach into the existing bounded window
detour; permitted door breaking retains that exact lease and resumes the same
pickup route. If entry is unavailable, the existing task-failure path releases
the task and reservations. Transfer remains owned by the native inventory
action and is not considered complete until the existing receipt check.

Planner and Terra compared this gap with the public locked-door and
corpse/fence reports. Corpse handling already has bounded retries/drop
cooldown and fail-closed task release in offline coverage, so its physical
fence outcome stays a live-only question. The generic locked-entry machinery
was already used by other routes; this cycle closed the assigned base-storage
leg that bypassed it. BUG-KS-033 records the source-confirmed correction.
Focused supply-entry, shared entry, base-action, task-validation, supply
arrival, claim-suspension and inventory-cleanup checks passed. Exact-worktree
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 178 regression
scripts (290 checks, 0 failures). Java was skipped; the new regression script
is local under ignored `tools/` policy. Native Build 42 traversal, actual
container receipt, interruption and save/reload remain unverified.

## Base-job completion authority — 2026-09-28

Current executors verify physical results before task completion, and the
existing persistent task board rejects finishes from stale/revoked claim
owners. The autonomy controller now waits for that authoritative response
before recording job success, advancing automatic-work pacing, or announcing
completion. Rejected completion is recorded as a bounded failure and clears
only the local task's transient state/reservations; it does not undo a real
world change or mutate another survivor's claim. `BUG-KS-034` records this
handoff correction. Focused task-validation and connected base-job regressions,
the broad offline gate, and exact counts are recorded in `WORK_QUEUE.md`. A
native Build 42 job completion with claim reassignment/interruption, feedback,
next-activity arbitration and save/reload remains unverified.

## Durable base-supply ownership — 2026-09-28

The loaded-world shortage claim was time-limited, but an elected resident's
persisted `activeSupplyRun` could continue searching or returning past its
1.5-hour lease. The controller now reconstructs the transient claim from valid
same-base active runs before electing another worker, including unloaded
residents. The durable duty remains the sole run owner; native transfer and
save/reload remain live acceptance. `BUG-KS-035` records the confirmed defect
and offline correction. The full `tools/verify.ps1 -SkipJava` gate checked 112
Lua sources, 178 regression scripts, 290 checks and 0 failures; focused supply
planner, auto-scavenge, inventory-cleanup and base-needs tests passed. Focused
test updates are local under ignored `tools/` policy, not tracked evidence.

## Loaded social memory connection — 2026-09-28

The loaded encounter coordinator now writes finalized greet, decline, hostile,
join, and rejected-join outcomes through the existing `KS_OffscreenStories`
owner into both participants' existing persistent ledgers. Entries use
canonical survivor IDs, are idempotent for the same outcome/time, and retain
the established 12-entry cap. Missing ledgers fail closed. Dialogue recounts
and Survivor Card labels describe joining, parting, and hostility without
implying combat or theft that was not verified. Focused story/history, recount,
human-encounter, view-model, and relationship-coherence checks passed.
`tools/verify.ps1 -SkipJava` checked 112
Lua sources, 178 regression scripts, 290 checks, 0 failures. Focused test
changes are local under ignored `tools/` policy. Build 42 still needs encounter
completion, save/reload persistence, and later dialogue/Card replay; hostility
does not imply native combat/robbery acceptance.

## Faction settlement supply eligibility — 2026-09-29

Faction residents can now be elected by their own base's existing real-storage
shortage planner when their persisted faction affiliation matches the base
owner and they remain available for ordinary autonomous work. Specialized
residents retain their role; an active generic group-sortie lease prevents
double assignment. Player-owned residents still require their existing explicit
loot-run preference. Both routes share the existing durable, receipt-gated
supply run and deposit owner (D-022); no generic faction mission was added.
Focused auto-scavenge, group-sortie, supply-planner, base-needs,
inventory-cleanup, and supply-routing checks passed. `tools/verify.ps1 -SkipJava`
checked 112 Lua sources and ran 178 regression scripts (290 checks, 0
failures). Initial broad verification found the workshop-description contract
needed the literal word `approval` for its existing Review Java Mods gate; the
copy was clarified and the rerun passed. Build 42 faction shortage pickup,
native deposit, reassessment, sortie arbitration, and save/reload remain live.

## Base-resident retreat continuity — 2026-09-29

Base residents now use the existing threat-weighted retreat admission when
danger warrants escape and a checked route exists. Ordinary low-pressure
encounters remain governed by the existing hold/fight thresholds; direct player
companions are still excluded. Retreat suspends the same base task while
retaining its authoritative claim and releasing temporary action/item/container
reservations. An active shortage run, explicit supply order, and real carried
delivery survive the interruption; two safe scans return the survivor to
normal base arbitration. Focused combat, formation, claim-suspension, base-duty,
task-validation, auto-scavenge, supply-planner, and group-scavenge regressions
passed. Broad offline counts and live Build 42 requirements are recorded in
`WORK_QUEUE.md`; native escape, return/resumption, and save/reload remain open.

## Offscreen-to-loaded encounter continuity — 2026-09-29

Offscreen pair intents were being consumed as soon as the loaded relationship
coordinator selected an outcome, before meeting interruption/approach or final
relationship/group mutation succeeded. The loaded encounter now retains its
pair-scoped intent token through REQUESTED, APPROACHING, and GREETING; matching
records are consumed only after an accepted loaded outcome. Failed approach,
danger/activity interruption, and membership-change aborts preserve the intent
for later contact. When that pair is evaluated, intents older than the existing
72-hour freshness bound are discarded symmetrically when their pair token still
matches. The existing short cooldown bounds repeated failed hostile handoff
attempts. No new history, relationship, identity, or persistence owner was
added.

Focused `test-human-encounters.lua`, `test-offscreen-stories.lua`,
`test-offscreen-recount.lua`, and `test-relationship-coherence.lua` passed.
The full `tools/verify.ps1 -SkipJava` gate checked 112 Lua sources, ran 178
regression scripts, and passed 290 checks with 0 failures. The added focused
test changes are local under the ignored `tools/` policy. Build 42 still needs
an offscreen-intent → loaded interruption → later finalized encounter replay,
including save/reload; native movement, combat, and robbery are not verified.

## Faction group admission result — 2026-09-29

The faction group-member transaction previously mutated the travel-group roster
and allied relationships before checking the canonical faction-membership
owner's result. A lifecycle rejection from `addFactionMember()` could therefore
be returned as a successful group join with partial authoritative state. The
faction owner now admits first; if it rejects, the group join returns
`faction_admission_rejected` before group, faction, affiliation, or relationship
mutation. The existing successful path still performs home-base resident duty
handoff and runtime notification, then leader/follower state is derived by the
existing bounded relationship coordinator.

Focused faction persistence, human encounter, autonomy formation, unloaded
groups, relationship coherence, and faction development regressions passed.
`tools/verify.ps1 -SkipJava` checked 112 Lua sources, 178 regression scripts,
and 290 checks with 0 failures; `git diff --check` passed. Focused test edits
remain local under ignored `tools/` policy. Build 42 accepted recruitment,
native encounter/formation, base duty, and save/reload remain unverified.

## Group succession directive repair — 2026-09-29

The direct member-removal path already elected a successor and cleared both
leader-owned objective and follow/hold directive. Load normalization repaired a
missing group leader and cleared the objective, but left the old persisted
directive record in the group. Its read validator rejected the stale issuer,
so it could not command followers, but the orphan remained in canonical data.
Normalization now retires that directive and increments its revision whenever
it replaces a leader, matching direct removal. The focused relationship
coherence, unloaded-group, autonomy-formation, and faction-persistence tests
passed. `tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 178
regression scripts (290 checks, 0 failures); `git diff --check` passed. The
updated regression remains local under ignored `tools/` policy. Live movement
after leader loss, formation refresh, and active-travel save/reload remain
unverified; the bounded 60-tick loaded formation refresh was not changed.

2026-09-29 autonomous retreat Sandbox option: `AllowAutonomousRetreat` is a
World-page boolean, default on to preserve existing behavior. `KS_Settings`
returns true for an absent option so existing saves retain current retreat
policy. Only fresh autonomous retreat admission is gated in the existing
`beginFlee` owner; a retreat already in progress can still reacquire a failed
route and complete safe-scan recovery. Direct player companions remain excluded,
and danger assessment, combat, formation, traversal, explicit orders, task
claims, supply runs, and duty resumption are unchanged. Focused sandbox,
combat-intelligence, autonomy-formation, survivor-needs, base-duty,
claim-suspension, relationship, persistence-recovery, and unloaded-group tests
passed. `tools/verify.ps1 -SkipJava` checked 112 Lua sources and 178 regression
scripts (290 checks, 0 failures). Focused test edits remain local under ignored
`tools/` policy. The Build 42 comparison is listed in `DEVELOPMENT_TESTING.md`;
combat, native movement, escape routes, and save/reload remain unverified.

## Automatic equipment preference — 2026-09-29

Automatic weapon, clothing, and bag improvements are now controlled by the
existing per-survivor policy record. Missing/legacy values remain enabled.
Player-owned companions and base residents can change the policy from their
existing context menus; party controls apply to the current companion roster.
The autonomy controller synchronizes the persisted value and gates both idle
and post-loot automatic reevaluation. Explicit inventory equipment and combat
weapon selection are untouched. Focused preference, sync-cache, equipment,
companion-command, and combat regressions passed. The exact-current-tree broad
verification evidence and ignored-test status are recorded in `WORK_QUEUE.md`;
native transfer/equip outcomes and save/reload remain live-only.

## Loaded group projection refresh — 2026-09-29

The current worktree has one new offline group-continuity correction layered
over the previously documented local changes. `removeTravelGroupMember()` still
owns canonical roster/succession mutation; it now signals the existing
relationship coordinator to refresh loaded projections on the next autonomy
coordinator pass instead of waiting up to 60 ticks. The forced projection reads
canonical state, does not rewrite leader objectives or clear runtime life
intent, suppresses objective announcements, and leaves native route ownership
untouched. Focused runtime-refresh, relationship-coherence, unloaded-group,
formation, and faction-persistence regressions passed. The current broad
offline verifier passed 112 Lua sources, 179 regression scripts, 291 checks,
and 0 failures; `git diff --check` passed. The added regression is local under
the ignored `tools/` policy. Build 42 membership-removal movement and
save/reload acceptance remain open; see `DEVELOPMENT_TESTING.md`.

## Player-party cohesion — 2026-09-29

The player is the normal party anchor. `KS_CompanionService` now derives the
runtime Follow-eligible roster and keeps member slots stable across roster
reordering. It smooths orientation from meaningful player movement rather than
turning-in-place direction changes. Player-only slot selection uses the existing
controller and native movement path, leasing a distinct compressed target when
the normal slot is blocked/claimed. A brief missing player square can use only
the player's last finite standable loaded square; traversal or a moving vehicle
causes bounded wait, never a temporary companion leader.

The same player-only target leases give eligible BUG-KS-028 participants
distinct staging squares inside the shared destination's existing 1.5-tile
arrival area. Arrival still checks live same-floor coordinates against the
canonical selected point. Arrived participants wait until the rest of that
snapshot arrives or the shared order clears. Hold/Relax, base duty, individual
directives, and invalid/dead/dismissed members remain excluded. NPC group and
faction formation paths are unchanged. Runtime slot and target state is not
persisted; destination remains runtime-only per D-025.

Focused player-party cohesion, destination, stable sync-slot, lifecycle/death,
movement priority, command routing, NPC group, and unloaded-group regressions
passed. Exact-worktree `tools/verify.ps1 -SkipJava` passed with 112 Lua sources,
181 regression scripts, 293 checks, and 0 failures; `git diff --check` passed.
These prove offline target projection, arbitration, and cleanup only. Native pathing,
crowding, player traversal, rendered activity, interruption/resumption, and the
intentional save/reload reset remain Build 42 acceptance, not live-verified.

## Firearm stabilization — 2026-09-29

`BUG-KS-029` received its owner-approved offline stabilization pass. Native Build
42 still owns reload/rack timed actions, the attack hook, projectile/ballistics,
damage, weapon condition, chamber/magazine/ammo state, and gunshot sound. No
second combat scheduler, ammo ledger, simulated hit, health mutation, parallel
weapon inventory, or Java change was introduced.

The controller's bounded reload-preparation budget is now keyed to the exact
prepared weapon and target instead of one global clock, so a finished encounter
cannot force an immediate false `reload_stalled` on the next fresh reload.
Consecutive native ranged approach/pursuit failures are bounded; at the threshold
the encounter releases firearm ownership through the existing melee-fallback owner
while keeping a still-valid target eligible. Melee fallback is a no-op when melee
is already held and prefers the exact carried item id. A committed ranged
encounter retains its weapon class across the survivor-choice threshold, and
every terminal boundary clears firearm transients through one
`clearFirearmCombatState()` owner.

Focused `test-firearm-support.lua` and `test-combat-reload-yield.lua` were
extended for readiness, exact weapon identity, hysteresis, fallback idempotence,
budget keying, bounded ranged failure, no duplicate fire request while a native
action owns the weapon, teardown clearing, and directive preservation across
lifecycle/shutdown. Existing firearm, empty-hand, weapon-preference,
equipment-intelligence, combat-intelligence, autonomy-formation, threat
classifier, human-encounter, and combat-scenario-reporting regressions passed.
Exact-worktree `tools/verify.ps1 -SkipJava` passed with 112 Lua sources, 181
regression scripts, 293 checks, and 0 failures; `git diff --check` passed.

This is offline evidence only; no native reload, shot, ammo reduction, damage,
animation, sound, reposition, friendly-fire, or save/reload result is claimed.
Live Build 42 acceptance remains open per `BUGS.md` and
`DEVELOPMENT_TESTING.md`. BUG-KS-030's offline roster rollback defect is fixed;
the full Build 42 vehicle matrix remains open. Do not stack offline vehicle
changes without new evidence.

2026-09-29 completion-track disposition: the approved D-025/D-026 player-owned
shared destination and cohesion slice was verified in the current worktree, not
reimplemented. Eleven focused destination, cohesion, directive, order, radial,
formation, relationship, group-refresh, and unloaded-group regressions passed.
The full `tools/verify.ps1 -SkipJava` gate passed: 112 Lua sources, 181
regression scripts, 293 checks, 0 failures. The regression scripts under
`tools/` are ignored/local. Player-party native routing, traversal, crowding,
interruption/resumption, and intentional session reset remain live acceptance;
the full vehicle matrix also remains pending. No next offline implementation
package with an existing bounded owner and acceptance was established by this
pass; avoid inventing scope from the deferred BUG-KS-021/022/023 candidates.

2026-09-29 BUG-KS-023 base-work preference slice: the existing player-owned
base task selector now reads sparse High/Normal/Low/Disabled preferences for
its eight current work groups. Missing values default to Normal, legacy
1–4/false maps normalize at schema 19, and preferences only break otherwise
equal selector choices; Disabled affects new autonomous selection only.
Active companion behavior, faction autonomy, explicit assignments, claims,
reservations, supply runs, and active native work retain their existing owners.
Companion/base duty transitions preserve the saved map so the selector can use
it after assignment to base. Focused regressions passed and
`tools/verify.ps1 -SkipJava` passed: 112 Lua sources, 181 scripts, 293 checks,
0 failures. Local `tools/` tests remain ignored/untracked. The Notebook UI,
native task behavior, interruption, and save/reload remain Build 42 acceptance.

## 2026-09-29 KS-PROD-008 next-package selection

Planner and Terra found no separately approved, substantial offline package
with an existing owner after BUG-KS-023. Do not repeat the preference or map
implementation, or reopen other offline-complete systems without new evidence.
The next safe work is the existing Build 42 acceptance queue or a new
owner-approved feature scope. Active-companion autonomous job election remains
unapproved and requires a separate design decision before implementation.

## 2026-09-29 active-companion work package

The owner clarified that active companions should help with field supplies,
while base jobs remain the base-resident system's responsibility. The first
approved slice is opt-in, loaded-area scavenging for one safe food item while a
player-owned companion is settled in Follow. Search stays on the same floor,
within 12 tiles of both companion and player. The exact item remains carried by
the companion and native transfer receipt is required before success. A
3-tile player leash, need/threat/order arbitration, and route cleanup prevent
the excursion from replacing normal following. The existing autonomy
controller, loot planner, reservations, movement, and inventory-action owners
remain authoritative; no new scheduler or persistence path was added. Nine
focused companion/loot/settings/needs/combat/base/persistence scripts passed,
and `tools/verify.ps1 -SkipJava` passed with 112 Lua sources, 181 regression
scripts, 293 checks, and 0 failures; `git diff --check` passed. Focused scripts
are in ignored `tools/` and remain local-only. Build 42 movement, transfer,
interruptions, capacity, following, and save/reload remain open. D-030 records
the settled boundary; the earlier nearby-base-organizing candidate was
superseded before implementation.

## 2026-09-29 staged base-life observation and Notebook correction

The owner reports that the current staged Build 42 residents mostly stood or
relocated without useful work, and Work/Schedule controls did not produce an
obvious result. This validates BUG-KS-013 as a current player-visible concern;
it does not yet identify the first runtime failure in the native work loop.

Offline source review found a separate confirmed UI integration gap: Notebook
controls used the selected base for resident eligibility but the write service
targeted only the primary player base. Schedule, job-preference, and work-
preference writes now pass the selected owned base through the existing
CompanionService and persistence validation. Notebook refresh/populate also
preserves the selected party/resident and repaints controls after selection
restoration; labels and successful-save feedback now expose the work/schedule
location and result. No task selection, native action, scheduler, duty, or
persistence owner was added or changed.

Focused Notebook/base-context, refresh, schedule, work-preference, order,
companion-command, duty-controller/simulation, base-job/task-board,
ambient-life, and needs regressions passed. The current full offline gate
passed 112 Lua sources, 182 regression scripts, 294 checks, 0 failures;
`git diff --check` passed. Regression edits are local under ignored `tools/`
and are not tracked Git evidence. Native controls, schedules reaching loaded
residents, useful task execution, blocked-state feedback, and full-day activity
remain live-unverified. BUG-KS-013 stays open pending the replay in
`DEVELOPMENT_TESTING.md`.

## Typed storage capacity lifecycle — 2026-09-30

The current source confirmed a storage-removal ownership gap: assigning typed
storage raised the real native `ItemContainer` capacity to the engine's limit
and added an object-ModData assignment marker, but removing the last policy only
deleted the canonical base policy/name. Capacity and marker could remain after
unassignment. The existing `KS_ToolCupboard` owner now snapshots capacity per
native container index, retains the snapshot across repeated resolution and
other active policies on that compartment, and restores the prior capacity
with verified native readback when the last assignment is
successfully removed. The removal menu commits cleanup only after persistence
accepts removal; contents are not deleted. Multiple compartments on one object
retain independent capacity snapshots. `ToolCupboardCapacity` is clearly marked
as a legacy setting for old Tool Cupboard records; new typed storage uses native
capacity and does not claim infinite weight. Removal uses a read-only identity
lookup, so rejected policy removal does not reapply capacity. A failed native
restore retains rollback metadata; an unknown old original is left unchanged
and reported honestly instead of being guessed. Recorded originals are restored
exactly, including values from another mod.

Focused `test-tool-cupboard.lua`, `test-base-storage-menu.lua`,
`test-base-storage.lua`, `test-base-supply-routing.lua`, and
`test-sandbox-settings.lua` passed. The exact dirty-tree Lua-only gate passed
112 sources, 182 regression scripts, 294 checks, and 0 failures;
`git diff --check` passed. Native capacity/weight behavior, real contents
preservation, multiple compartment/overlapping-policy behavior, and save/reload
restoration remain Build 42 acceptance.

## 2026-09-30 generic looting receipt correction

The current dirty worktree now gates generic exploration completion on exact
selected-item presence in the survivor inventory. Missing/partial native
receipts produce a bounded source-container cooldown, failure evidence, and
existing lease cleanup; no item or native result is synthesized. Base resupply,
away-team, party-support, and need-food/water owners retain their separate
receipt rules. Focused local generic-loot, looting-planner, and companion-loot
checks passed. The ignored `tools/` regression is local-only. The current
dirty-tree `tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 183
regression scripts (295 checks, 0 failures); `git diff --check` passed.
Build 42 generic loot refusal, partial transfer, real inventory receipt, and
save/reload remain unverified.
The September 28 runtime showed generic completion messages without inventory
receipt traces, which is insufficient to confirm or disprove the reported
item-search error.

The authorized `deployDev` staging pass completed successfully after this
source fix. SHA-256 comparison found the same 122 mod-payload files in source,
the local `C:\Users\Gary\Zomboid\mods\KnoxSurvivors` copy, and the Workshop
`Contents/mods/KnoxSurvivors` payload, with zero missing or differing files;
the Workshop folder also contains the two expected Java-agent/checksum files.
This establishes source/local/staged payload parity only, not Workshop upload,
subscription, native runtime, or release acceptance.

## 2026-09-30 immediate Build 42 startup error follow-up

After the owner loaded the staged mod, two autonomy exceptions appeared at
frames 166 and 196. The newest debug log points to
`next(self.perceivedThreats)` while constructing the party-support eligibility
context. `Controller.hasEntries`, implemented with guarded `pairs` iteration,
now owns threat-map and reservation-owner emptiness checks. Focused formation,
loot, supply, group-support, and away-team regressions pass after this fix;
`tools/verify.ps1 -SkipJava` passed 112 Lua sources, 183 regression scripts,
295 checks, and 0 failures. `deployDev` then succeeded; source/local/Workshop
mod payload comparison matched all 122 files with zero missing or differing
files. Build 42 must replay settled companion follow with threats present and
confirm both errors are gone.

## 2026-09-30 social interaction prompt and repeat-Talk correction

`KS_SurvivorInteractionUI` now shows a small lower-center prompt for the nearest
visible same-floor survivor within the normal four-tile conversation radius;
the prompt displays the current vanilla Interact binding (E by default). Interact
opens a compact player-scoped panel with the survivor's live 3D model, name, and
Friendly/Neutral/Mean/Hostile action categories. Existing service, dialogue,
trade/gift, and recruitment owners handle actions. The current same-player
conversation lease can be refreshed safely; an established conversation panel
closes when the lease is interrupted or its target becomes unavailable. Warm-up
dialogue progresses to ordinary personality-aware Talk lines at the current
familiarity threshold without changing recruitment/disposition rules.

Focused social-interaction UI, conversation, player-reputation, player-social,
social-act, survivor-dialogue, and order-menu callback regressions passed. An
earlier dirty-tree full gate found one `test-base-naming.lua` fixture failure
during a changing worktree. The focused naming regression now passes, and the
fresh exact-worktree gate passes 113 Lua sources, 188 regression scripts, 301
checks, and 0 failures; that earlier failure is not currently reproducible.
Build 42 prompt/input interaction, UI-scale readability, native model rendering,
repeated conversation, and interruption/resumption remain live acceptance; no
in-game replay was run.

## 2026-09-30 player-owned base/outpost naming — KS-PROD-008 Slice H

The existing Base & Work view now exposes Rename for the selected player-owned
base or outpost. Persistence validates player ownership and updates only the
existing `base.name` field. Input is trimmed; blank/control-containing,
malformed UTF-8, and names over 32 Unicode code points are rejected. Same-owner
duplicate detection ignores ASCII letter case and compares non-ASCII bytes
exactly. Success and failure feedback use the existing activity feed, and a
successful rename refreshes Notebook views while retaining the selected base
ID. Faction bases and all other base state remain unchanged. Existing names in
old saves remain intact unless the player explicitly renames that base.

Focused naming, selected-base, multi-base, persistence-recovery, Notebook-refresh,
and base-management checks passed. The exact dirty-worktree verifier passed
113 Lua sources and 186 regression scripts (299 checks, 0 failures); Java was
skipped. The regression script is ignored under repository test policy and is
local-only. Build 42 keyboard/mouse/joypad behavior, visible feedback, base
switching, view refresh, Notebook reopen, and save/reload are still unverified.
The base-life, loot/resupply, storage, map, group, firearm, vehicle, retreat,
and companion-food acceptance gates remain open.

## 2026-09-30 offline continuation after storage design review

The reported base-naming regression did not reproduce: `lua
tools/test-base-naming.lua` passes. The independent offline door helper check
also passes (`lua tools/test-door-discipline.lua`); BUG-KS-019's source-level
fallback correction is marked offline-resolved, while native Build 42 door
traversal remains live-pending. No source defect was justified in these
candidates. A fresh `tools/verify.ps1 -SkipJava` run passed 113 Lua sources,
188 regression scripts, 301 checks, 0 failures; `git diff --check` passed.
The local regression scripts are ignored by Git policy. The next unresolved
barricade multi-window observation requires a native timed-action cycle; do not
change it without a reproducible offline divergence or live trace.

## 2026-09-30 water safety and coherence pass

Fresh review of current production records, subsystem authorities, source, and
focused fixtures selected the water classification boundary after ranking the
highest-impact base-life/resupply issues as live-only for this session. `BUG-KS-046`
was source-confirmed: `waterState` treated taint inspection failure as clean.
The installed vanilla `ISDrinkFromBottle` reads the same taint marker and may
apply sickness/poison. Knox now fails closed for absent marker/accessor failure
or non-boolean output. Known-tainted water remains an emergency-only option at
critical thirst; clean water and native eat/drink ownership are unchanged.

Focused survivor-needs, base-needs, base-storage, supply-routing, looting,
group-support, and unloaded-survival checks passed. The exact dirty-tree verifier
passed 113 Lua sources, 186 regression scripts, 299 checks, 0 failures; Java was
skipped. `git diff --check` passed. The local test addition is under ignored
`tools/` policy. No new runtime logs were available/relevant and no Build 42
session was performed. Known native fluid types, sickness consequences, real
consumption, and partially consumed bottle save/reload remain open.

The review found strong existing offline ownership in identity/lifecycle, social
memory, groups, task claims, real-item checks, typed storage, and map/UI
projection. The largest observable risks remain BUG-KS-013/015 (base activity
and real loot/resupply), followed by storage capacity and native group/combat/
firearm/vehicle/map/UI acceptance. The existing settings inventory classifies
53 options; no broad key removal is supported. Filtered ground placement remains
a feature candidate pending a native placement/receipt path. No release-ready or
live-verified claim is made.

## 2026-09-30 schedule clarity and water-source planning — KS-PROD-008 Slice J

Owner follow-up to the Build 42 life test: base work appeared to function
provisionally, but the complete supplied-task/missing-resource/full-day replay
was not performed. Keep BUG-KS-013 open and provisionally observed working.
The schedule was still text-heavy and hour feedback unclear. The Crew & Schedule
view now emphasizes the selected resident, `NOW` hour/assignment, selected
paint tool, colored 24-hour cells, a marked current hour, and short saved/dirty/
default status; controls wrap and the existing scroll adapter exposes the full
view at smaller heights. Schedule persistence and meaning are unchanged. This
offline UI update still needs Build 42 visual, pointer/joypad, save/reopen, and
small-resolution acceptance.

The owner did not fully test loot/storage or native clean/tainted/unknown-water
behavior: BUG-KS-015 remains provisional/unconfirmed/live-pending, and BUG-KS-046
remains an offline source fix with water compatibility/consequences
provisional/unconfirmed/live-pending. No native result is marked passed.

Focused Notebook schedule painting, schedule conversion, refresh/selected-base,
and layout regressions passed. `tools/verify.ps1 -SkipJava` passed 113 Lua
sources, 187 regression scripts, 300 checks, and 0 failures; Java was skipped.
The added `tools/test-notebook-schedule-clarity.lua` is ignored by Git policy
and local-only. `git diff --check` passed. No Build 42 session was performed.
`deployDev` succeeded. SHA-256 comparison found 123/123 source files identical
in the local target and all 123 source files identical in Workshop
`Contents/mods/KnoxSurvivors`; Workshop has the two expected generated agent
JAR/checksum files. This is staging parity only: the game was not launched and
the Workshop item was not uploaded.

KS-PROD-008 Slice K now connects urgent loaded thirst to direct drinking from
real native water objects. The existing search checks assigned/carried real
water items first, then loaded source objects within 12 tiles on the same floor.
Object sources are limited to player-owned base residents inside their base and
faction/base residents inside their base/camp; no implied water supply trip is
created. Existing need, threat, order, movement, reservation, retry, and cleanup
owners remain authoritative. Vanilla `ISTakeWaterAction` owns the sip; Knox
requires both native thirst reduction and source-fluid reduction (including a
depleted-to-zero source) before counting success. Full inventory, unknown taint,
normal-thirst tainted water, unavailable sources, and interrupted/failed actions
remain truthful failures. No new persistence or offscreen water simulation was
added.

Focused needs, water-source autonomy, base-needs, roaming, and formation checks
passed. The exact dirty-worktree verifier passed 113 Lua sources, 188 regression
scripts, 301 checks, and 0 failures; Java was skipped. `git diff --check` is
recorded after documentation updates. The added `tools/test-autonomy-water-source.lua`
is ignored by Git policy and local-only. No Build 42 test was performed. Native
taint/sickness effects, direct consumption, fluid depletion, full-inventory
refusal, pathing, base/camp eligibility, and save/reload remain live-pending.
The owner did not complete the prior clean/tainted/unknown water matrix; BUG-KS-046
is not marked live-passed.

No source defect was confirmed in the couch/table exit review. Vanilla actions
own sit/rest/get-up and Knox has no stand-position correction path; the report
remains unconfirmed and native/live-only pending an exact geometry replay.
The generic exploration path verifies exact selected-item identity in survivor
inventory; zero/partial receipts record failure, cool down the container, and
release existing leases. No new logs or reproducer were available, so the
search-order symptom remains unconfirmed. The 53-option Sandbox inventory had
already been reviewed at that point; the later owner-directed cleanup is
recorded below. Ground storage remains design-only: the existing wrapper targets the
actor's floor container, while the local Build 42 action can choose the current
or a neighboring square; Knox confirms only world-item existence, not a
designated square or rollback. The bounded design gate and missing native proof are in
WORK_QUEUE.md and DEVELOPMENT_TESTING.md. Player base/outpost naming and
conversation continuation are already implemented offline and await live
acceptance.

Storage/loot/settings focused checks passed:
`test-base-organize-wiring.lua`, `test-base-storage-menu.lua`,
`test-base-storage.lua`, `test-base-supply-planner.lua`,
`test-base-supply-routing.lua`, `test-companion-loot-orders.lua`,
`test-generic-loot-receipt.lua`, `test-inventory-cleanup.lua`,
`test-multi-base.lua`, `test-sandbox-settings.lua`, and
`test-survivor-looting.lua`. The current offline verifier passed 113 Lua
sources, 188 regression scripts, 301 checks, and 0 failures; Java was skipped.
No source or test changes were made in this audit. Native transfer/rollback and
the user's search-order symptom remain live-pending/unconfirmed.

## 2026-09-30 companion food-support review

Planner selected the still-open companion food-support report; Terra traced the
existing controller path from opt-in eligibility through 12-tile loaded-
container search, exact item/container reservations, native transfer, exact
inventory receipt, and cancellation cleanup. Focused formation, looting,
companion-order, and settings tests pass. The newer
`C:\Users\Gary\Zomboid\Logs\2026-09-30_05-59_DebugLog.txt` records one
`party_support_food_unavailable` event at 06:04:46. At 06:05:17 the companion
starts a `loot_useful_items_2` route and logs completion at 06:05:23. That
proves a later general loot route completed, but does not identify either item
as food or show whether an eligible food source was present/reachable during
the earlier party-support scan. No offline defect is confirmed. Do not repeat
this source review without setup-linked evidence; retain the exact Build 42
replay in WORK_QUEUE. The same log also contains repeated detached-state
telemetry for `ks-dev-1`; it is not attributed to the selected food path and
needs separate reproduction/source review before classification. Search-order
error reporting remains unconfirmed after the receipt correction. Other native
and deferred candidates have no new offline divergence in this pass. The fresh
offline verifier passed 113 Lua sources, 188 regression scripts, 301 checks,
and 0 failures; Java was skipped.

## 2026-09-30 latest Build 42 observation follow-up

The newest relevant log was `C:\Users\Gary\Zomboid\Logs\2026-09-30_17-05_DebugLog.txt`
(199,577 bytes). Only its interaction-window exception slice was read. At
17:09:02, the first of 21 matching stack entries reports
`attempted index: setState of non-table: null`; vanilla `ISUI3DModel:setState`
calls to `KS_SurvivorInteractionUI.lua:292` while `InteractionUI.open` is
creating the panel from `OnContextKey`. The root order was portrait initialise,
native-backed setters, then `addChild`; Build 42 `ISUIElement:addChild`
instantiates the child. `KS_SurvivorInteractionUI` now adds the portrait before
those setters. It also registers the Knox `Talk to Nearby Survivor` keybinding
with F default and uses the same binding for its prompt/keyboard shortcut; the
native Interact/context path remains for compatibility and controller input,
without globally changing PZ's binding. The focused test proves child readiness
ordering, key-label/default registration, shortcut gating and mouse
pass-through, not Build 42 key dispatch or model rendering. BUG-KS-047 is
offline-fixed/live-pending.

Schedule hour cells now start a stroke on mouse-down, paint hovered cells using
the initially selected resident/tool, and stop on release outside or scroll.
There is no pointer capture; single-click and joypad paths keep painting one
cell through the existing draft/persistence owner. The
`test-notebook-schedule-clarity.lua` test proves click, drag, repaint, resident
targeting, scroll/release cancellation, schedule serialization, default state
and narrow wrapping.
Button color properties are set offline; actual Build 42 appearance, pointer
dispatch, UI scale, joypad and save/reopen remain pending as BUG-KS-048.

The same pass reviewed away-from-base arbitration without finding a source
failure tied to the observation: independent `ROAMING`/loaded exploration,
needs, group formation, companion relax, and native recreation/social owners
already exist. No fresh log result identified the actor/state/order context, so
this remains a live observation needing a setup-linked replay, not a reason to
add another idle scheduler. For BUG-KS-020, explicit building orders already
queue each discovered opening (up to 24); automatic work intentionally
discovers one target per recurring pass and excludes claims. No metal-sheet
installation task/executor exists. The barricade shim has a metal validation
branch, but target discovery, material requirements, queued action and result
receipt remain wooden-only; track metal-sheet installation as a separate
deferred feature gap. Native multi-window completion/rediscovery was not
tested.

Focused checks passed for social interaction UI, schedule clarity, duty schedule,
Notebook base context, barricades, base jobs, base ambient life and party
cohesion. `tools/verify.ps1 -SkipJava` passed 113 Lua source checks, 188
regression scripts, 301 checks and 0 failures; Java was skipped. The final
`git diff --check` passed. No Build 42 testing occurred in this pass.

## 2026-09-30 barricade continuation and ambient-behavior follow-up

The explicit building barricade order had a confirmed offline handoff gap:
`orderBarricadeHere` queued every discovered window, but only the first became
an explicit claim. Remaining windows relied on autonomous work election and
were stranded when `automaticJobs` was disabled. Each queued explicit target
now carries a `manualOrder` marker on its existing task record. The controller
asks the existing task board for one eligible marked task before schedule-rest
and the autonomous-jobs gate; the board checks capability and claims atomically.
Successful completion clears the marker, while bounded blocked-task retry keeps
it until resolved. No task, storage, movement, or persistence owner was added.

The away-from-base behavior review found no deterministic source defect that
justifies another ambient scheduler. Existing roam, exploration, need, threat,
formation, companion-relax, recreation, and social owners remain; the owner's
report that base life feels stale remains important and unresolved. The latest
log identifies `ks-spouse-player-1` as a non-local survivor shell. Farming
plow/seed/water actions returned without the expected crop-state change, so Knox
reported failure; a tree action hit the bounded action timeout and
`FailedStuck` movement followed the existing backoff/cleanup path. Nearby
`receiveGlobalObjects: player is null` messages are a native-integration lead,
not proven cause. The source trace did not establish a false success or leaked
claim. Metal-sheet support is partial at the action-adapter validation level,
but no metal job, target discovery, material transfer, completion receipt, or
rollback executor exists. See the updated BUG-KS-013 replay and deferred metal
feature acceptance in `DEVELOPMENT_TESTING.md` and `WORK_QUEUE.md`. No source
change or live test occurred in this pass. Focused farming, jobs, task-board,
task-validation, action-lifecycle, base-duty, ambient-life, and needs checks
passed. `tools/verify.ps1 -SkipJava` passed 113 Lua sources, 189 regression
scripts, 302 checks, and 0 failures; Java was skipped. `git diff --check` passed.

The `receiveGlobalObjects: player is null` lead has now been audited against
current source: Knox registers or calls no such receiver. Farming only reads
the native farming singleton and queues vanilla farming actions. Action
completion still requires observed crop-state change; refusal or no effect
finishes as failure through the task board. Keep the warning classified as
native/live integration uncertainty correlated with the shell farming run,
not as a Knox source defect. Metal-sheet installation remains a feature gap:
the installed Build 42 `ISBarricadeAction` supports metal mode, but Knox's
current job and result path is wood-only. This follow-up reran five focused
farming/job/task/action regressions and `tools/verify.ps1 -SkipJava` (113 Lua
sources, 189 scripts, 302 checks, 0 failures); Java was skipped. No source
change or live test was performed.

The current interaction/UI stabilization pass made three bounded offline
corrections: Activity Feed visibility now hides/reopens without discarding its
bounded in-session events (`BUG-KS-049`); the new default-on `ShowRadialOrders`
option gates only Knox radial slices and stale callbacks while leaving vanilla
radial and independently configured classic context commands intact
(`BUG-KS-050`); and closing the interaction panel releases the conversation
lease started by that panel through the existing runtime owner (`BUG-KS-051`).
Focused feed, radial/settings, interaction, speech, storage-menu, and order-menu
checks passed. The exact current-tree verifier passed 113 Lua sources, 190
regression scripts, 303 checks, 0 failures; Java was skipped and
`git diff --check` passed. Tests under ignored `tools/` are local-only Git
evidence. The prompt and arrows remain live-pending for visual/native input;
storage had no confirmed duplicate Knox writer and no settings/data were
removed; Notebook access continues through the existing Base and Party menus.
No live test, stage, or Workshop upload was performed.

## 2026-09-30 — QA architecture and fixture safety (KS-PROD-011 / BUG-KS-052)

The opt-in unattended QA path now uses one validated scenario catalog
(`KS_QAManifest.lua`) and the existing `KS_AutomatedQA.lua` coordinator.
Automated survivor fixtures receive a persistent owner token on their existing
canonical identity record. Cleanup checks the exact run/token pair, checks the
native body removal result, keeps ownership when uncertain, and can reconcile
only matching stale QA identities after a later load. The old area helper is
inert, the legacy `FULL_STEPS` runner is hard-quarantined, and the menu-exit
path no longer invokes its global probe/job/combat cleanup routines.

The manifest reports `PASS`, `FAIL`, `BLOCKED`, `SKIPPED`, `HARNESS_ERROR`,
`TIMEOUT`, and `CLEANUP_ERROR`, with prerequisites, category, setup/action
sequence, timeout, expected evidence, area/mutation scope, cleanup, evidence
type, and human-confirmation metadata. Encounter smoke remains the only native
fixture path currently automated. Base work, melee, firearm, group/faction, and
save/reload are catalogued as explicitly `human_required`; no combat, job,
movement, transfer, UI, or reload behavior was promoted from offline evidence.

Focused QA architecture, automated-QA, persistence recovery/first-capture, and
PowerShell parser contract checks passed. Current exact-tree
`tools/verify.ps1 -SkipJava` passed 114 Lua sources, 191 regression scripts,
305 checks, 0 failures. `git diff --check` passed. Tests in ignored `tools/`
are local-only Git evidence. Java, staging, Build 42 fixture materialization,
stale-run cleanup after reload, and native removal were not run. Existing
gameplay acceptance gates remain unchanged.

### KS-PROD-011 base-task adapter follow-up — 2026-09-30

A read-only `QA-BASE-ADAPTER-001` preflight now reports `BLOCKED` because the
existing base creation path can target the player's real base. No current owner
can exactly roll back the base record, zones, tasks, storage policy/native
material items, resident duty, runtime reservations, or the native target after
a partial/successful action. The legacy base job matrix remains unreachable.
No base task was automated or live-tested; native base-task behavior remains
human-required.

Focused `test-qa-architecture.lua`, `test-qa-base-task-adapter.lua`,
`test-automated-qa.lua`, base task board/requirements/action lifecycle/task
validation/supply-entry/job/storage/supply-planner tests, and parser contract
passed. The current
exact-worktree `tools/verify.ps1 -SkipJava` result is 115 Lua sources, 192
regression scripts, 307 checks, 0 failures; `git diff --check` passed. Java
and Build 42 were not run. The `tools/` regressions are ignored by Git policy
and remain local-only evidence.

### KS-PROD-011 disposable-save isolation follow-up — 2026-09-30

QA start now records `getCore():getGameSaveWorld()` identity/source and no
longer labels every run disposable. A one-run, in-memory declaration accepts
only the exact current `KSQA-...` identity plus the explicit owner phrase; the
declaration is consumed by the next run and cleared at the menu boundary.
Ordinary, unclassified, unavailable, and mismatched/stale save states block
mutating scenarios. The QA coordinator rechecks identity before each scenario
and refuses abort cleanup if the identity changed. Read-only scenarios,
including `QA-BASE-ADAPTER-001`, still run when mutation is blocked. Reports and
the parser retain save identity, identity source, and isolation classification;
mixed-save events within one run are rejected.

This gate is an explicit human declaration bound to the engine's current save
label, not native proof of a cloned save. Knox has no save create/discard API.
The owner must create/backup a fresh QA save and restore/discard it externally.
Reload starts unarmed and requires a new declaration. Base task execution
remains blocked by the separate rollback preflight. Focused isolation,
coordinator, parser, and manifest regressions pass locally. Exact current
`tools/verify.ps1 -SkipJava`: 116 Lua sources, 194 regression scripts, 310
checks, 0 failures; `git diff --check` passed. Java, Build 42, staging, and
Workshop upload were not run. `tools/` tests are ignored by Git policy and
local-only. No live test or save mutation was performed.

### KS-PROD-011 Developer Tools arming and read-only snapshots — 2026-09-30

The Developer Tools context menu now shows current save identity and
classification, pending-arm state, next run sequence, coordinator state, and
scenario dispositions. A Developer Mode confirmation modal displays the exact
identity before invoking the existing one-run arm owner; starting the run is a
separate explicit action. The approval expires on refused/normal start,
completion, menu/reload, identity change, or coordinator error. The report logs
arm, consume, and expiry decisions, and the PowerShell parser correlates them
without treating an arm-only log as a completed run.

The ordinary-save read-only set now includes survivor/body identity,
base/task/duty, and group/faction snapshots. Map projection remains excluded
because its current entry point may initialize player persistence. Recruitment
and all destructive scenarios remain gated. `QA-BASE-001` remains blocked by
the unproven native task/work-target rollback contract; `QA-BASE-ADAPTER-001`
is read-only and reports `BLOCKED`.

Focused QA Developer Tools, snapshot, isolation, coordinator, manifest,
automated-QA, and PowerShell 7 parser tests passed. Exact current-tree
`tools/verify.ps1 -SkipJava`: 116 Lua sources, 196 regression scripts, 312
checks, 0 failures. `git diff --check` passed. Tests under `tools/` are ignored
and local-only. No live Build 42, Java, staging, or Workshop upload was run.
The manual arming screen and its output still need owner confirmation in an
externally prepared disposable save; save creation/restoration remains external.

### KS-PROD-011 stale Debug Mode QA payload — 2026-09-30

The latest available Build 42.21 debug run is not evidence against the current
manual arming workflow. Its QA START record used the legacy
`save_is_disposable=true` shape without save-identity or manifest metadata, and
the loaded local/Workshop QA coordinator differed from repository source. The
log reports a Kahlua `Index 200 out of bounds for length 200` while loading
`KS_SurvivorAutonomy.lua`; the subsequent `KnoxAutonomyController.new` nil
error caused `QA-ENCOUNTER-001` to end as `HARNESS_ERROR` and recruitment to be
skipped. This classifies as stale staged payload plus unresolved debug-loader
compatibility, not a newly confirmed current-source gameplay defect. Refresh
staging from the current source before another launch. Keep manual arming,
read-only report output, and current-source behavior live-pending until the
owner verifies them in an externally prepared disposable save. Do not run the
legacy destructive QA entry point on an ordinary save.

### 2026-09-30 — Build 42 Debug Mode loader correction (`BUG-KS-053`)

The newest run confirms the game used the Workshop development copy, not just
the local-mod folder. That payload logged legacy `save_is_disposable=true`,
then a Kahlua 200-local overflow; autonomy could not construct
`KnoxAutonomyController`, and the encounter QA ended `HARNESS_ERROR`. The
current controller source had exactly 200 top-level locals; removing its
unused `approachSector` helper brings it to 199. A local budget regression was
added. Focused controller/autonomy/QA tests and the latest full verifier passed
116 Lua files, 197 regression scripts, 313 checks, 0 failures. Current source
was copied to the active Workshop development root and local mod root with
SHA-256 parity for all 127 source payload files; the two existing runtime JAR
and checksum files were retained. This is offline-fixed/live-pending: perform a
fresh Build 42 Debug Mode startup and confirm current QA metadata and successful
autonomy controller registration before proceeding. No Workshop upload or
live retest was performed.

### BUG-KS-053 — second Debug Mode evidence (2026-09-30)

The newest log shows current QA manifest v2 loaded from the Workshop
 development root, but Kahlua still overflowed after the controller was only
reduced to 199 top-level locals. The follow-up moves ten module tuning values
onto the existing controller table; its local count is now 189 (guarded at
190). Offline checks passed; the staged source is hash-equal in both the local
Mods and Workshop development folders. The same log reports save identity as
unavailable, so the QA gate blocks the encounter fixture. This is a separate
identity-availability issue; it does not cause the compiler overflow. Both
native outcomes remain pending the next fresh log.

### BUG-KS-053 — newest Debug Mode log and staged-source correction

`2026-09-30_23-49_DebugLog.txt` is a real failure: Kahlua overflowed at
23:49:22, then autonomy registration failed because
`KnoxAutonomyController.new` was unavailable. The log's Workshop controller
was staged at 23:42 with 189 locals. The current repository fix was written at
23:58, after that launch, so this log does not test the current payload. The
current source moves 36 tuning values onto the existing controller table and
has 153 top-level local declarations (regression cap 160). It has now been
copied and hash-checked across all 127 source payload files in both the local
mod and active Workshop development paths; the two intentional Workshop agent
files remain. Focused checks and the full offline verifier pass (116 Lua, 197
scripts, 313 checks, 0 failures). Next evidence must come from a new launch.
The same old log says `saveIdentity=unavailable`; that is an independent QA
arming limitation, not the cause of the Kahlua error. No native pass is claimed.


### 2026-10-01 — BUG-KS-053 fresh log disproved prior fix; tick split staged next

The newest owner-provided debug evidence is current: the loaded Workshop
controller hash equals the repository source, yet Kahlua still throws twice at
`LexState.new_localvar` (local index 200), then autonomy registration hits a nil
constructor at `KS_SurvivorAutonomy.lua:309`. Save identity is independently
unavailable and is not causal. The concrete source boundary was the 231-local
`Controller:tick`; its existing base-task native-action/result branch has been
extracted into `Controller:updateBaseTaskAction` without changing task, action,
or arbitration owners. Lua 5.1 compilation succeeds and reports 163 locals for
`tick`; focused base-action lifecycle and related autonomy tests pass. Full
verification: 116 Lua sources, 197 regression scripts, 313 checks, 0 failures.
Fresh Build 42 confirmation is still required.


### 2026-10-01 — BUG-KS-053 startup error confirmed gone

After staging the autonomy tick split to both local and Workshop mod roots, the
owner restarted Build 42 and reported the startup errors were gone. Mark the
Kahlua index-200 and consequent nil-constructor startup failure as live-confirmed
resolved for this replay. This does not confirm QA save identity, destructive QA
arming, encounter behavior, or broader gameplay.


### 2026-10-01 — in-game QA removed by owner request

The in-game Automated QA runner, save arming, Sandbox switch, and Developer
Tools submenu are retired. QA-only coordinator/manifest/isolation/adapter/probe
modules now live under `dev/qa-harness`, outside the packaged `mod/42/media/lua`
tree, so they are not loaded with gameplay. Normal Developer Tools remain.
Offline regression scripts still exercise the archived harness modules directly;
this is not in-game QA or proof of native behavior. Existing saves may retain an
unknown `AutomatedQAMode` key, which Knox no longer registers or reads. Owner
confirmation that the Kahlua startup errors are gone is tracked separately as
BUG-KS-053; continue gameplay testing through short manual replays.


### KS-PROD-011 removal verification — 2026-10-01

Focused QA-runtime-retirement, ordinary Developer Tools menu, automated-harness
offline, pacification, and Sandbox-settings regressions passed. All 14 QA-only
Lua modules compile from `dev/qa-harness`; no QA coordinator/probe `.lua` file
remains in the packaged client Lua tree. `tools/verify.ps1 -SkipJava` passed
102 packaged Lua sources, 197 regression scripts, 299 checks, 0 failures;
`git diff --check` passed. The 109-file `mod/42` payload is SHA-256 matched
against both local and Workshop development roots. No Workshop upload or live
acceptance was performed.


### 2026-10-01 — Sandbox pages reorganized; Auto-Loot permission simplified

The Sandbox page now groups its 52 visible settings into General, Population,
World & Factions, Bases & Work, Companions & Orders, Interface, and Developer
Tools. Option keys, types, defaults, and existing setting ownership were
preserved. The redundant `AllowCompanionPartyScavenging` Sandbox gate was
removed from registration and runtime checks: the existing persisted
per-companion Auto-Loot permission now controls both nearby pickup and the
bounded party-food detour. Old values of the retired key are ignored. This
means companions whose Auto-Loot preference is enabled (including the existing
missing-value enabled default) may make the existing safe nearby food detour;
players can turn it off per companion in game. No other companion or NPC
faction work policy changed.

`ToolCupboardCapacity` remains visible under Bases & Work because old marked
cups still read it; `ShowLegacyContextCommands` remains because it is an active
UI fallback preference. The Sandbox settings inventory and D-030 were updated
to record these boundaries. Focused settings, companion-food admission, order,
and storage compatibility regressions passed; `tools/verify.ps1 -SkipJava`
passed 102 Lua sources, 197 regression scripts, 299 checks, and 0 failures.
`git diff --check` passed. These are offline checks; page rendering and
old-save behavior need Build 42 confirmation, and no native setting or
gameplay behavior is claimed live.

### 2026-10-01 — Sandbox parser failure fixed offline (BUG-KS-054)

After staging the reorganized Sandbox, the owner reported that no Knox Survivors Sandbox options appeared. The newest `console.txt` confirms Build 42 loaded the active Workshop source and rejected `sandbox-options.txt` at the first `--` section comment (`unknown block type "--"`). Removed the seven unsupported comment lines and added a regression to keep the file compatible with `CustomSandboxOptions`. Offline checks passed and the corrected files were restaged to the local and Workshop development copies with exact source/hash parity. The options are not counted as live-restored until the owner restarts and opens the Sandbox menu successfully.


### 2026-10-01 — player vehicle-follow handoff (BUG-KS-030)

The existing native vehicle owner now receives local player enter/exit events:
nearby same-floor Follow companions attempt to board the exact stopped vehicle,
and those seated in that exact vehicle attempt native exit when the player exits.
An opted-in follower may take an unoccupied driver seat when the player enters
as passenger; otherwise followers seek passenger seats. The owned-survivor
context menu also offers a nearest loaded vehicle driver order on foot, still
behind Experimental NPC Driving and existing fuel/lock/route gates. Rejected
manual vehicle orders now produce a short Activity Feed reason. Focused offline
vehicle tests and the full verifier pass; native event timing, seat actions,
actual driving, exit behavior, safety interruptions, and save/reload remain
Build 42 live-pending. The newest available DebugLog contains no vehicle-order
trace. The separate low-damage unarmed stomp observation is unresolved because
the log shows combat starts/target changes but no attack/hit receipts.

### 2026-10-01 — BUG-KS-030 locked passenger-door handoff

The latest owner report said boarding returned “no free passenger seat” despite
visually empty, zero-weight seats. Source comparison found Knox filtered every
locked passenger door before queuing entry, unlike Build 42's own
`ISVehicleMenu.onEnterAux`, which queues native unlock/open/enter/close actions.
The companion entry sequence now uses those native actions and key-on-door
handling; the native key/lock result remains live-pending. Focused vehicle tests
cover the sequence; no item, seat, or unlock success is fabricated.

### 2026-10-01 — Notebook priority save and schedule color follow-up (BUG-KS-041 / BUG-KS-048)

The newest Build 42 log (`2026-10-01_03-53_DebugLog.txt`) records the work-preference cell callback throwing from `normalizeWorkPreferences` at `KS_Persistence.lua:49`; the source called global `next`, which is unavailable in this Kahlua path. Replaced that check with a `pairs`-based flag, preserving the same supported preference values and persistence owner. This is a second distinct source boundary after the earlier `onCrewPriorityCell` local `next(map)` fix.

The owner also reported that schedule paints remained visually yellow around the current hour. Installed Build 42 `ISButton` source confirms the Notebook assigned fill colors without enabling its base background. Hour and preference cells now enable the existing button background and keep their state color while hovered. The yellow outline/star remains the intentional current-hour indicator; it is not the assigned schedule state.

Companion passenger boarding now temporarily sets the native running flag for the vehicle-seat path and restores the previous flag at seat entry or lease teardown. It requests a jog, not sprint, and does not alter the vehicle, action, or movement owner.

Focused `test-work-priorities.lua`, `test-notebook-schedule-clarity.lua`, `test-notebook-refresh.lua`, `test-notebook-base-context.lua`, `test-vehicle-driver.lua`, and `test-companion-vehicles.lua` pass. `tools/verify.ps1 -SkipJava` passed 102 Lua files, 197 regression scripts, 299 checks, 0 failures. `git diff --check` passed with only existing LF/CRLF conversion warnings. `deployDev` succeeded; all 113 repository mod files match the local game copy and Workshop development copy by SHA-256, with only the two generated Workshop Knox Bridge agent files as extras. This is staging, not upload or live verification. Build 42 must still confirm preference saves without errors, cell fill rendering/painting, and actual companion approach pace. Active companions still do not receive base-work preferences unless assigned base duty, matching BUG-KS-023's approved scope.

Owner follow-up: Schedule cells appeared not to retain paint colors and the current-hour yellow marker stayed at 12 while game time was 17:00. The existing save writer/24-hour conversion path remains covered offline; a separate source bug was confirmed in the display clock, which fell back to a noon-returning NightShelter helper instead of using Build 42 `getGameTime()`. The Notebook now uses the game clock first, supports `GameTime.getInstance()` as fallback, and omits the marker if time is unavailable. Focused tests cover 17:45, the singleton API, and unavailable time. Native fill appearance and save/reopen remain pending owner replay.

Owner retest identified a second schedule-color defect: colors reverted after paint/refresh. Build 42 `ISButton:setEnable()` restores its cached `backgroundColorEnabled`; Notebook had updated visible and hover colors but not that cache. Schedule cells, palette controls, and preference cells now keep all three color values synchronized. The focused regression simulates native enable/disable restoration and confirms the new paint persists through refresh. Live rendering and saved schedule reopen are still unverified.

2026-10-01 interaction retest follow-up: F prompt visibility and input had mismatched gates. The prompt checked the survivor's view of the player and remained visible while aiming, while the key path requires the player to see the survivor and rejects aiming. Prompt admission now uses player line of sight and shares the aiming restriction. Prompt presentation is text-only with no panel/keycap background. Neutral actions Trade, Give Item, and Recruit are now omitted for player companions, faction members, and grouped survivors; only independent ungrouped survivors receive those controls, subject to existing native/service eligibility. Focused UI/social/trade tests pass; Build 42 input, sight, and rendering remain unverified.

2026-10-01 command surface follow-up: radial order pages now expose compact Movement, Survival, Tactics, Vehicle, Gear, Formation, resident Work, and resident Policy paths through existing command owners. `ShowRadialOrders` defaults on. The saved compatibility option `ShowLegacyContextCommands` now controls the entire alternate Knox right-click order surface and defaults off; it no longer silently turns on if the radial API is absent. Disabled context mode hides survivor/party/resident/location/map-driving order menus while preserving F interaction, survivor view/care, base management, storage assignment, and native target interactions. The duplicate `Interact (F)` context item was removed. Focused offline radial/context/map/social tests pass; mouse/joypad rendering, callbacks in Build 42, and live command behavior remain pending.
# 2026-10-01 — survivor command and autonomy direction

Nearby-survivor radial `Interact` opens the same F interaction window. The
duplicate right-click `Interact (F)` entry is removed; right-click opens the
interaction panel only if a separately selected menu action explicitly does
so. The interaction window remains the eligibility owner for Talk, Trade,
Give, and Recruit. The radial is the default order path; right-click order menus
are an optional, default-off alternate. Spatial destination orders still need
the context/map path because the emote radial has no clicked-coordinate input.
Existing companion door/window and vaulting/climbing permissions continue to
use persisted policy owners.

The owner also requested a clear "free will on/off" control and continuous
survivor life. No global toggle was added: loaded autonomous survivors already
use the existing controller for roaming, needs, social/rest/loot decisions;
persisted unloaded survivors use the truthful travel/needs/rest/history ledger.
Offscreen native combat, looting, movement, and world effects are not
simulated. A companion "Use Judgment / Orders Only" control remains a separate
design/implementation package and must only gate elective behavior, never
survival, danger, combat, explicit orders, formation, traversal, vehicles, or
recovery. See the KS-PROD-008 command-surface continuation in WORK_QUEUE.md.

Focused `test-order-menu-callbacks.lua`, `test-radial-orders.lua`, and
`test-social-interaction-ui.lua` pass. These tests establish dispatch and
eligibility wiring only; Build 42 radial rendering, mouse/joypad selection,
interaction panel behavior, and native autonomy remain unverified.

### 2026-10-01 owner follow-up — spouse identity and item search

`BUG-KS-055` is source-confirmed and offline-fixed: a fresh starting spouse
previously reused a deterministic ID/personality seed for the same player slot,
and a successor inheriting the household could enter the fresh-spouse path.
New spouse identity seeds vary per save and persist across retries; household
succession keeps the existing spouse as a resident and suppresses a duplicate.
The direct Find Medical Supplies goal now reuses the shared looting classifier,
so its candidate set includes supported medicines (for example pills,
disinfectant, sutures, and tweezers), not only bandages/sheets/cotton. Tools,
weapon upgrades, clothing, and ammunition already have distinct selectors.
Native search reach, transfer, equipment use, and save/reload remain live gates.

The scroll state is owned by separate Notebook tab view objects, while Base &
Work intentionally has an outer page scroller plus bounded zone/task/storage
lists. Terra confirmed the first divergence was wheel routing at the BaseView
boundary; each child list now receives wheel input only when hovered, and the
page scrolls only outside those sections. The layout test proves independent
list offsets and outside-page scrolling; Build 42 event routing and clipping
remain pending.
Power behavior is partial: loaded controllers can operate supported powered
lights/televisions, and cooking checks appliance power/heat. Knox has no general
generator refuel/repair or gas-pump power-management loop. Those are feature
gaps requiring native source/result and interaction scope; no power state was
fabricated. Zombie targeting of survivors likewise remains a native/live
acceptance question; no forced target or sprint behavior was added.

### 2026-10-01 owner follow-up — sleep, faction beds, sprinters, and storage

Offline source evidence found one gap in the existing autonomy arbiter:
player-owned companions under direct movement orders were diverted to roaming
for both ordinary rest and actual sleep. The controller now permits the
existing survival sleep action to temporarily preempt movement intent without
clearing the persisted order; ordinary rest retains its previous priority
rules. Faction base upkeep now assigns available native beds to loaded faction
residents leader-first, preferring higher-quality beds and checking occupancy
and approach reachability. Assignments use the existing bed policy with
faction/base provenance; manual/player-owned bed choices are protected.
Focused sleep, bed-selection, persistence, and unloaded-survival tests pass.
`tools/verify.ps1 -SkipJava` passed 102 Lua source syntax checks, 199 Lua
regression scripts, 301 checks, 0 failures; `git diff --check` passed. The
new/updated scripts in `tools/` are ignored by repository policy and remain
local-only evidence. Native sleep, bed traversal/animation, wake/interruption,
save/reload, and unloaded-to-loaded behavior still need Build 42 acceptance.

Sprinter targeting remains native/live-only: Knox does not set zombie targets
or movement speed. Compare the same sprinting zombie's target acquisition and
pursuit of a survivor and player under equal range and line of sight. Existing
container storage now supports versioned multi-category filters on its existing
real-container policies. The right-click filter menu targets any eligible
container in a player-owned base/outpost; old role assignments keep their
legacy behavior until edited. Deposit, organizer, material, food/water, and log
processing routes honor filter policy. No disallowed contents are ejected.
Ground `Storage Zone` and four-corner placement remain deferred until
exact-square native transfer, receipt, and rollback are proven; see BUG-KS-014
and WORK_QUEUE.md. No item movement or stock was fabricated.

### 2026-10-01 Base UI scroll and storage filter slice

`KS-PROD-008 Slice L` is offline-complete/live-pending. After the owner
reported that the staged UI still scrolled incorrectly, the parent wheel path
was corrected to consume a bubbled event over a child list without forwarding
it to the native list a second time. The native Work Areas, Task Queue, or
Storage list owns its scroll; the outer page owns whitespace. Storage setup uses multi-select
per-container filters rather than a single new role. The persistence, context
menu, storage routing, task-material, resident food/water, organizer, and
woodcutting paths reuse existing owners; legacy storage records are not
rewritten. Focused layout, persistence, menu, storage, autonomy-water,
woodcutting, base-needs, organize, supply, and task-supply tests passed. The
first full run exposed one stale `test-base-setup-ui.lua` expectation for the
retired one-role wording; that assertion now checks the filter instructions.
The rerun passed 102 Lua source syntax checks, 199 regression scripts, 301
checks, and 0 failures with Java skipped; `git diff --check` passed. Native item
movement, UI rendering/input, save/reload, and capacity/content behavior remain
Build 42 acceptance items. `tools/` tests are ignored by Git and local-only.
The screenshot establishes that the first staging did not fix the observed UI;
this follow-up is source/test-verified only and must be restaged and replayed.
Reviewing the new screenshot against the installed Build 42 list implementation
found the rendering cause: custom Notebook row callbacks bypassed the vanilla
offscreen-row guard. All six callbacks now skip rows outside their own viewport
and still return the expected row extent. This should prevent Work Areas rows
from drawing over task controls and likewise protect Task, Storage, Crew,
Missions, and World lists. It remains offline-verified only until the owner
retests the staged UI.

### 2026-10-01 storage clarification continuation

The owner clarified that base-radius containers should be usable without
individual assignment, with explicit vanilla item categories guiding preferred
placement and unfiltered containers serving as fallback. Implemented the first
bounded connection in the existing storage owner: loaded real containers inside
the selected base bounds are discovered as transient references; configured
matching filters win ahead of unfiltered fallback; item lookup, needs/job
retrieval, real deposits, and the existing one-item organizer can use these
containers. No transient discovery writes container ModData, title, capacity,
or saved policy. The organizer moves a real item from an unconfigured chest to
a matching configured filter using its existing native transfer/result path;
it does not reshuffle between unfiltered chests.

Right-click **Set Filters…** now opens a large scrollable, joypad-aware window
with vanilla `DisplayCategory` checkbox rows, Knox convenience categories, and
General Storage. The same existing container policy persists selected values,
including validated `display:<category>` keys. Old saves keep their existing
storage records until a player edits them. Focused storage/filter/menu,
organizer, task-supply, needs, water, woodcutting, base-setup, and ownership
tests passed. Latest verifier: 103 Lua syntax checks, 200 regression scripts,
303 checks, 0 failures; Java skipped; `git diff --check` passed. The tests are
under ignored `tools/` policy, so they are local-only evidence. No live Build 42
visual, joypad, category-label, native-transfer, capacity, or save/reload test
was run. `deployDev` then succeeded; SHA-256 comparison matched all 110
repository `mod/42` files to the local development mod and Workshop `Contents`
payload. Workshop contains only the two expected generated `knox-agent.jar`
and `.sha256` files in addition. No Workshop upload or gameplay test occurred.

Still not implemented: ground-placement Storage Zones and house cleaning as a
resident order/free-time job. Ground placement remains deferred until exact
native square receipt and safe rollback are proven. House cleaning needs a
bounded definition of cleanable world objects and safe native actions; carried
item organization is not represented as whole-house cleaning. Keep these as
separate feature slices rather than claiming them covered by container filters.

### 2026-10-01 — storage Kahlua exception and missing survivor report
The newest available DebugLog is `2026-10-01_09-02_DebugLog.txt`. It confirms a
Kahlua `next` exception on storage-capacity cleanup, and current source had the
same unavailable call in container-filter persistence and editor/menu paths.
BUG-KS-056 replaces those calls with `pairs` checks. The log's population
summary reports 48/48 living world survivors, one restore, 46 outside the
activation band, and one virtual location waiting for a loaded square. It does
not include owned squad/base-resident IDs or prove that their records were
lost. No survivor or save data was altered. The reported squad/resident absence
remains unconfirmed; capture the next relevant log around Notebook roster and
population activation before changing lifecycle behavior.

### BUG-KS-057 — faction scheduled sleep correction (2026-10-01)

Source review confirmed faction residents on a `sleep` duty schedule entered
ambient sitting/rest rather than native sleep. Only faction-owned base scheduled
sleep now enters the shared recovery path, which selects assigned/reachable
beds and retains the existing movement, interruption, and recovery owners.
Player-owned base schedules are unchanged. Focused needs, bed, camp, group,
night-shelter, and unloaded-survival tests pass; Build 42 native sleep and
save/reload acceptance remains open. Other survivor scopes already use shared
loaded needs and unloaded survival paths in source and focused tests.

## 2026-10-01 — BUG-KS-058 hibernation teardown recovery

Confirmed source defect fixed offline: when native body removal failed after a
stored-ledger commit, the still-registered controller was set to `STOPPED`.
That prevented ordinary controller ticks while `activeIds` also excluded the
same identity from unloaded advancement. The code now rolls the ledger to
`loaded` before resuming the existing controller and native shell at `IDLE`.
If rollback fails, a runtime recovery-pending entry retries only that ledger
transaction. No spawn, replacement identity, teleport, or simulated success is
used. A confirmed absent body allows the committed hibernation to finish.

Healthy `hibernated`, `Away`, or `Settled` records are not considered stuck just
because they lack a native body; their canonical record and unloaded ledger
remain the owners of needs, supplies, route, and identity. Temporary traversal
and vehicle transitions remain under their grace/vehicle owners. The planner's
review of the newest available log did not reproduce this failure; the defect
was proven by the source transition and STOPPED tick gate.

Focused tests passed: same-shell recovery, lifecycle policy, unloaded survival,
world presence, away teams, unloaded groups, unloaded base return, virtual base
return transaction, persistence recovery, and controller priority stability.
The new and extended `tools/` tests are ignored by Git and are local-only
verification evidence. `tools/verify.ps1 -SkipJava` and `git diff --check`
results are recorded after the implementation gate. Build 42 refusal,
rematerialization, save/reload, and duplicate-body behavior remain pending.

BUG-KS-058 verification: 10 focused lifecycle/persistence/offscreen/controller
regression scripts passed. `tools/verify.ps1 -SkipJava` passed 103 Lua sources,
202 regression scripts, 305 checks, 0 failures. `git diff --check` passed;
Git emitted only its existing LF-to-CRLF working-copy notices. No Java or live
Build 42 testing was performed. The new test file is under ignored `tools/`
policy and is local-only evidence.

## 2026-10-01 — resident rematerialization, filters, and radial follow-up

Owner-observed failures are treated as real player-facing evidence. Source
confirmed three offline defects and fixed them without replacing existing
owners:

- `BUG-KS-059`: an active ID with a bridge-confirmed missing body could remain
  in autonomy's exclusion list indefinitely. The pre-activation reconciliation
  now removes only stale ordinary runtime projection, preserves the canonical
  survivor record/duty, respects transition/hibernate leases, and lets normal
  same-ID restoration retry.
- `BUG-KS-060`: after the owner reported the filter editor/checkmarks still
  were not apparent, the access path was traced again. `Set Filters…` had been
  nested under the Knox submenu; it now appears directly on the world-object
  context menu. The handler accepts the actual native list callback payload,
  and selected rows use a filled green checkbox plus a plain `X` glyph. Offline
  tests cover menu placement and draw state; Build 42 opening, rendering, and
  save/reopen are still pending.
- `BUG-KS-061`: radial root/Party Orders visibility required a nearby loaded
  follower even though party-wide orders use the persisted roster. The root
  now remains available for an owned party with stored/offscreen members;
  individual follower actions remain proximity-gated.

Focused tests passed for stale-body recovery, filters, storage context menu,
radial orders, world-population candidates, and detached companion lifecycle.
`tools/verify.ps1 -SkipJava` passed 103 Lua files, 203 regression scripts,
306 checks, 0 failures. `git diff --check` passed; only existing LF-to-CRLF
working-copy notices were emitted.
All three fixes need Build 42 acceptance; same-ID native body restoration,
visible checkboxes/save-reopen, radial display/input, and no duplicate body
remain unverified. `deployDev` succeeded and the 114 source files under `mod/`
match both the local mod and Workshop `Contents` by SHA-256 (0 differences).
This is staging only; no Workshop upload occurred.

2026-10-01 same-save survivor follow-up: the latest loaded save is
`Sandbox/playtest01`. Its `global_mod_data.bin` retains Stacy Byrd as canonical
`ks-world-4`, player-owned with Follow duty, a native survivor record, and a
hibernated/sleeping logical location. The latest DebugLog contains no restore
for her ID; it restores only `ks-dev-1` and reports one virtual survivor
waiting without an ID. Source confirmed that virtual rematerialization
required an unseen safe square even for owned companions. `KS_WorldPopulation`
now allows a validated player-owned companion to use its real safe logical
square when visible, while independent world population retains hidden
placement. Focused `test-world-population.lua` passes. This is offline-fixed;
same-ID native appearance, visual rendering, item/order continuity, and no
duplicate body remain Build 42 acceptance. The expanded Follow fallback and
focused lifecycle tests passed. `tools/verify.ps1 -SkipJava` passed 103 Lua
sources, 203 regression scripts, and 306 checks with zero failures. `git diff
--check` passed. `deployDev` succeeded and all 114 source mod files now match
both local and Workshop development copies by SHA-256. This is staged, not
live-verified or uploaded.

The 11:32 Build 42 retest names Stacy (`ks-world-4`) and repeatedly defers her
with `virtual_square_not_loaded_or_visible` from startup through frame 2401.
The latest save retains her player-1 ownership, Follow order, canonical record,
and hibernated/sleeping state at 1468,7310,z=1. Sleep is not an activation
blocker: it is an allowed virtual activity. z=0 is ground level; z=1 is one
level above. The actual failure is no safe loaded tile around the saved
same-floor location. An offline recovery now lets an explicitly following
owned companion use a real safe loaded square within four tiles of its owner
when that saved square cannot be used. It relocates the same native record and
ledger through existing owners. Offline regression passes; Build 42 must still
confirm Stacy appears once with state intact. Hold, base residents, and
independent survivors are excluded; base-resident safe-base fallback remains
unimplemented.

2026-10-01 follow-up: the newest Build 42 DebugLog reported 334 repeated
`emptyList` Kahlua exceptions in `KS_KnoxEvents`, called from event maintenance
inside the autonomy update. Both uses of unavailable global `next()` are now
replaced with `pairs` checks. Focused event, runtime, and view-model regressions
pass; full verification passed 103 Lua sources, 203 regressions, and 306 checks
with zero failures. `deployDev` succeeded and all 114 source files match both
local and Workshop `Contents` copies by SHA-256; no Java source changed.
The Notebook's `Sleeping` activity can be the survivor's persisted offscreen
sleep state while the order remains `Following`; the log did not identify the
selected survivor's sleep ledger, so that presentation remains to confirm.
