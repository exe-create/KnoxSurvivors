<!-- modforge-doc
authority: canonical
load: always
purpose: canonical confirmed bug and blocker ledger
-->

# Knox Survivors — confirmed bugs and blockers

Updated: 2026-09-30

## Rule

Only put a bug here when there is a concrete symptom, reproduction/log evidence, or a source-confirmed failure. “Needs live testing” is not itself a bug.

The 2026-09-21 release-readiness audit reported no source-confirmed release blocker at that snapshot. Later worktree changes mean the current candidate must be revalidated, but they do not automatically constitute bugs.

## Current confirmed blockers

## BUG-KS-001 — Unloaded raids manufacture terminal outcomes and world damage
Status: in_progress
Priority: high
Owner: Codex
Type: bug

### Symptom
An entirely unloaded faction raid can be declared repelled or breached without
loaded arrival or native combat. A breach can later create blood and smash real
windows when the player enters the area.

### Reproduction
On candidate `163b789`, schedule an eligible faction raid against an established
base, keep every raider and the target more than 300 tiles from the player, and
allow the event runtime to update. Return to the target after the event reaches a
terminal phase.

### Evidence
The current working diff removes `KS_EventRuntime.resolveUnloadedRaid` and
`KnoxEvents.resolveAbstractRaid`, including the path that released event duties,
recorded terminal outcomes/history, and created fight/breach traces from roster
counts. The runtime now permits stored travel/arrival, then leaves an unloaded
raid at the active/objective boundary until a raider body is loaded for native
combat/looting. While that body is absent, objective review does not time out
into a result; event duties remain owned. Updated event-runtime coverage checks
that this path creates no raid history or traces and that loading a raider
resumes the objective. Six focused event/trace tests passed. The full
`tools/verify.ps1 -SkipJava` run checked 112 Lua sources and ran 174 scripts
(286 checks, 0 failed). These are offline checks and do not verify native combat
or world effects.

### Expected
Unloaded travel may preserve/advance event intent, but only real loaded
arrival/combat/objective evidence may establish a raid outcome or mutate world
geometry.

### Acceptance
No unloaded-only update declares raid victory/defeat, releases a deployed roster
as if combat completed, creates blood, or smashes windows.

### Validation
Offline verification on 2026-09-27: six focused event/trace tests passed; full
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 174 scripts (286
checks, 0 failed). Still required: live Build 42 loaded-to-unloaded-to-loaded
raid replay with native combat evidence. Offline fixtures do not prove native
combat, blood placement, window damage, pathing, or persistence behavior.

## BUG-KS-002 — Failed world-trace materialization is marked complete
Status: in_progress
Priority: high
Owner: Codex
Type: bug

### Symptom
A trace site is permanently marked visited even when blood/window
materialization throws or returns false, so the visible trace is silently lost
instead of retried.

### Reproduction
Present an unvisited nearby trace whose loaded square exists but whose native
materialization call fails or cannot place any effect, then run
`KnoxWorldTraces.update()`.

### Evidence
The bounded fix in `mod/42/media/lua/client/KS_WorldTraces.lua` now calls
`markTraceVisited(site.id)` only when materialization returns success. Breach
materialization reports success only when the blood-placement helper succeeds
or at least one window smash succeeds; this is a code-level success signal, not
live confirmation of the native visual effect. `tools/test-world-traces.lua`
now checks a failed materialization remains unvisited, a later successful retry
is consumed once, and a throwing breach path remains retryable. The same
throwing breach site is now also retried after restoring working cells and
verified consumed exactly once with a bounded real effect
(`breach-retry=true`), with no production-code change.

### Expected
Only successful materialization consumes the persisted trace; transient native
failure remains bounded and retryable.

### Acceptance
Failure/false-result coverage proves the site remains unvisited and can later
materialize exactly once.

### Validation
Offline verification on 2026-09-27: `test-world-traces.lua` passed, including
the same-site throwing-breach retry consumed exactly once;
`test-event-runtime.lua` and `test-knox-events.lua` passed; full Lua regression
suite passed 174/174. This verifies the bounded retry logic under test doubles
only. Still required: live Build 42 trace replay on a temporarily unavailable
or invalid target, confirming the native blood/window effect before the trace
is consumed.

## BUG-KS-003 — Embedded launcher is a conflicting runtime owner
Status: todo
Priority: high
Owner: Codex / OpenCode
Type: bug

### Symptom
The main mod repository contained a second, stale C# launcher that preserved
external Java runtime's `-agentlib:zbNative` while adding Knox's legacy `-javaagent`,
contrary to the exactly-one-runtime-path contract. Its embedded source and
build path were retired. The separate Knox Survivors Launcher is now
deprecated and unsupported by owner direction; KnoxBridge is the sole
supported public Knox runtime path. Its GitHub privacy change was requested but
is still pending, so do not claim the repository is private yet.

### Reproduction
Historical reproduction: in the embedded launcher verifier, inherit
`JAVA_TOOL_OPTIONS=-agentlib:zbNative -Xmx2G` and create a launch plan. The
verifier required both the alternate runtime option and Knox `=pz-game` agent to be
present, and `tools/build-launcher.ps1` packaged that implementation. Those
embedded files are no longer present in the main repository.

### Evidence
The main repository diff retires all 12 tracked embedded launcher project/source
files and `tools/build-launcher.ps1`; `docs/LAUNCHER.md` now names the separate
launcher repository as the sole source, verification, and packaging owner and
rejects active external Java runtime composition. In the sibling
`KnoxSurvivorsLauncher` checkout, `scripts/build.ps1` passed launch-option
security/native-argument verification, updater metadata/version/checksum
verification, launcher verification with Knox and multiple Java runtimes
isolated, and Windows bootstrap verification. The main repository structural
retirement check passed (13 tracked embedded files deleted),
`tools/verify.ps1` passed with 112 Lua sources, 174 Lua regression scripts,
Java checks/build included, 287 checks and 0 failures, and `git diff --check`
passed. These checks establish offline retirement and verifier behavior only;
they do not establish a live game launch.

### Expected
No supported Knox launcher path can package or run a competing instrumentation
runtime. Players use KnoxBridge through normal Steam startup.

### Acceptance
The stale embedded launcher build path is retired, the standalone launcher is
deprecated, and current-facing instructions direct users to KnoxBridge only.
No live acceptance is required for the retired launcher path. KnoxBridge live
startup and gameplay remain tracked separately under `KS-PROD-010` and
`KS-PROD-005`.

### Validation
Offline verification on 2026-09-27: sibling launcher `scripts/build.ps1` passed
the historical launcher/bootstrap checks; the main repository retirement
check and `tools/verify.ps1` passed (287 checks, 0 failed). On 2026-09-29,
current-facing Knox instructions were aligned to KnoxBridge and the separate
launcher was marked deprecated. The requested GitHub visibility change remains
unconfirmed. This does not establish current KnoxBridge live behavior or
release readiness.

## BUG-KS-008 — Detached companions can remain in a stale-shell limbo
Status: in_progress
Priority: high
Owner: Codex
Type: bug
Related: KS-PROD-008

### Symptom
An alive companion with a non-null shell but no current square can remain in
the active survivor registry while being skipped by off-screen simulation.
Without lifecycle classification, it can also accept order writes while it
cannot be normally simulated or re-materialized.

### Evidence
The bounded lifecycle correction classifies vehicle occupancy and recognized
native climb, vault, window, fence, and sheet-rope traversal as legitimate
temporary detached states that remain registered. An unexplained nil-square
companion shell receives ten hibernation checks of grace. During that grace,
new native companion order writes are rejected without changing the persisted
prior order. If detachment persists, the lifecycle uses the existing
transactional capture → native removal → `markStored` → unregister path, keeping
survivor identity and persistence ownership. Dismissal remains allowed as a
persistence ownership change. Recovery restores active order acceptance.

Focused offline coverage passed: `test-survivor-lifecycle-policy.lua`,
`test-detached-companion-lifecycle.lua`, `test-companion-commands.lua`,
`test-order-routing.lua`, `test-unloaded-survival.lua`,
`test-world-presence.lua`, `test-persistence-recovery.lua`,
`test-persistence-hot-path.lua`, `test-unloaded-base-return.lua`, and
`test-virtual-base-return-transaction.lua`. Full
`tools/verify.ps1 -SkipJava` passed: 112 Lua syntax files, 175 regression
scripts, 287 checks, 0 failed. `git diff --check` passed. These are offline
fixtures and do not prove native engine movement, streaming, or save behavior.

### Expected
No companion remains indefinitely registered without either valid simulation
or an intentional, recoverable lifecycle state. Temporary native detachments
remain registered, while a persistent unexplained detach is safely hibernated
with identity, order, inventory, and persistence state preserved.

### Acceptance
Focused tests cover detached classification; order acceptance/rejection;
active registry and off-screen behavior; safe return/rematerialization;
dead/nil-shell cleanup; and identity/persistence preservation. No duplicate
survivor body or lost survivor is introduced.

### Validation
Offline coverage listed above passes. Still required in live Build 42:
vault/climb transitions, cell-edge and streaming gaps, vehicle occupancy,
prolonged unexplained detachment, dismissal, save/reload, and subsequent
rematerialization. BUG-KS-008 and KS-PROD-008 remain open; no native behavior or
release readiness is established by offline tests.

## BUG-KS-009 — Off-slot survivor visibility writes throw Build 42 lighting exceptions
Status: in_progress
Priority: high
Owner: Terra
Type: bug
Related: KS-PROD-008

### Symptom
During a live controlled survivor combat observation, Knox repeatedly called
`IsoGridSquare:setCouldSee` for an off-slot survivor shell. Build 42's lighting
JNI rejected that call with `java.lang.IllegalStateException` from
`LightingJNI$JNILighting.bCouldSee`, producing repeated errors while the
survivor was in combat.

### Evidence
On 2026-09-27, disposable Build 42.20.4 save `KS-QA-Vertical-1` recorded 76
occurrences between 04:58:02 and 05:02:50 in
`<Zomboid-Logs>\2026-09-27_04-42_DebugLog.txt`. The Knox stack
is `KS_ZombieAwareness.setSquareBit` → `ensureVisibilityBit` → `update` →
`KS_SurvivorAutonomy`; the fixture was `ks-dev-1` in `COMBAT`. This confirms an
unsafe Knox lighting-state write, not native combat success or failure.

### Current correction
`KS_ZombieAwareness` no longer writes or clears native `setCouldSee` bits for
off-slot survivor shells. It retains native target selection and reports the
disabled unsafe assist once. The focused zombie-awareness regression verifies
that no lighting bit is written while native targeting remains available.

### Validation
Offline after the correction: `tools/test-zombie-awareness.lua`,
`tools/test-automated-qa.lua`, and `tools/verify.ps1 -SkipJava` passed (112 Lua
syntax checks, 175 scripts, 287 checks, 0 failed); `git diff --check` passed.
Still required: rerun one controlled Build 42 zombie encounter and confirm no
`LightingJNI.bCouldSee` exception while recording the native combat result.
Multi-zombie threat selection, native damage, and retreat behavior remain
unverified.

Additional Build 42.20.4 diagnostic evidence collected 2026-09-28 in
`dev-runs/20260928-021135`: the Knox log contains the one-time
`visibility_bit_disabled` marker and the console extract contains no
`LightingJNI`, `bCouldSee`, or `setCouldSee` failure. This supports that the
unsafe call is no longer being attempted in this run, but is not a standalone
focused replay or proof of all combat outcomes. The same session includes
native zombie attacks that reached `AttackDidDamage=true` and reduced survivor
health (for example, 100 to 96.96 and then 92.40), so the off-slot boundary is
not a blanket failure to damage survivors.

The controlled `combat_group_horde` scenario in that run ended `PARTIAL`:
15 survivor hits, zero zombie damage, and no kills. This mixed encounter does
not change the offline base-danger arbitration coverage or identify a new
source defect. Do not repeat that source audit without new evidence. Keep the
one-zombie and small-group native combat replay in Slice D live acceptance.

## BUG-KS-010 — Speech indicator overlay renders as a dark or malformed layer
Status: in_progress
Priority: medium
Owner: Codex
Type: bug
Related: KS-PROD-008

### Symptom
The owner observed the survivor communication arrow appearing black/ugly and
normal right-click interaction appearing unavailable while it was visible.

### Evidence
`KS_SpeechIndicators` created a full-viewport `ISPanel` without disabling
`ISPanel`'s default half-black background. The shaft also drew a same-width
near-black line at the exact coordinates of its coloured line. The overlay did
call `setWantMouseEvents(false)`, so source inspection does not establish that
it intentionally consumed input; the Activity Feed remains a separate normal
interactive window above world input.

### Current correction
The render-only overlay explicitly disables its background, retains
`setWantMouseEvents(false)`, uses one high-contrast coloured arrow, rejects
missing/stale coordinates, removes expired entries, and resets its owned panels
and marks at game start. It remains Knox-owned and imports no foraging code or
assets.

### Validation
`tools/test-speech-indicators.lua` passes range, compass, transparent style,
mouse-pass-through configuration, expiry, and stale-coordinate checks. Lua
syntax and related UI/order regressions pass. Still required in Build 42:
visually confirm the indicator colour/projection and open an ordinary world
right-click menu both outside and over the Activity Feed while the arrow is
visible.

### 2026-10-01 owner retest follow-up
The owner reports the arrow still blocks ordinary screen interaction. Source
review confirmed the full-viewport panel only disabled mouse consumption
before UI-manager registration and did not explicitly release capture or
return false from mouse callbacks. The overlay now reapplies non-consuming
input after registration, calls `setCapture(false)`, and has explicit
non-consuming mouse handlers. `tools/test-speech-indicators.lua` covers the
registered capture state and each handler. The owner screenshot also displayed
the old `Storage: 1 assigned` label, while current Notebook source displays
`filtered | usable containers`; at report time the subscribed Workshop copy
had a different hash and lacked the current row-culling code. Current source
files have now been copied into that subscribed folder, but 11 obsolete QA/probe
Lua files remain there because cleanup was blocked by the environment. Use the
clean local mod copy with the Workshop entry disabled for the next test. Neither
native arrow input propagation nor current Notebook clipping is yet confirmed
in Build 42.

## BUG-KS-011 — Formation cadence delays follow resumption after fence landing
Status: in_progress
Priority: medium
Owner: Codex
Type: bug
Related: KS-PROD-008

### Symptom
The owner observed a survivor stand for several seconds after completing a
fence traversal before resuming follow behavior.

### Evidence
`refreshFormationFollow` returned on its existing refresh deadline before it
checked native traversal state. A climb that began between refreshes, or a
landing before the deadline, could therefore hide the busy-to-landed transition
behind the old cadence even though native traversal had finished.

### Current correction
Formation follow now observes native traversal before applying its ordinary
refresh cadence, leaves the native climb/vault action untouched, and immediately
reevaluates on the first landed update. With developer diagnostics enabled it
emits bounded `traversal_started` and `traversal_completed` movement entries.

### Validation
`tools/test-autonomy-formation.lua` verifies that active fence traversal keeps
native ownership and that the first landed update clears the traversal latch
without waiting for the old deadline. Related combat, command, order, social,
and QA regressions pass. Live Build 42 fence replay remains required to confirm
animation completion, natural timing, and absence of duplicate route requests.

## BUG-KS-012 — Survivors have no active retreat policy for overwhelming fights
Status: in_progress
Priority: high
Owner: Codex
Type: bug
Related: KS-PROD-008

### Symptom
The owner observed survivors entering multi-zombie fights that appeared
overwhelming instead of reconsidering or withdrawing.

### Evidence
The pre-correction controller gathered nearby zombies, humans, health,
endurance, allies, and escape-lane inputs, but `fleeAssessment`,
`findFleeTarget`, and `beginFlee` were explicitly short-circuited as
`flee_retired`. Loaded survivors could therefore select and retarget threats
but had no active risk-based retreat handoff. This source boundary is
consistent with the visible report; it did not establish balance thresholds or
prove any native escape route.

### Current correction
The dormant native-movement retreat path now has a bounded admission policy. A
retreat needs a real open escape lane plus visible or actively targeting danger;
healthy, equipped survivors hold against a one-on-one or small non-targeting
encounter. Overwhelming immediate pressure, critical health, injury, or severe
exhaustion can admit a retreat. Existing route safety, retry/recovery, two-safe-
scan completion, order preservation, and native movement ownership remain in
place. Direct player companions remain protected from autonomous retreat. Base
residents now use this same bounded admission path; an admitted retreat
suspends, rather than completes or releases, their current base task. Supply
search reservations are released while the durable active run, explicit order,
and carried delivery are retained for normal return/deposit arbitration.

`test-combat-intelligence.lua` and `test-autonomy-formation.lua` now cover
one-on-one/small encounters, crowd pressure, injury, exhaustion, equipment,
nearby allies, escape lanes, blocked lanes, and native-request admission. The
focused companion/order/conversation checks and `tools/verify.ps1 -SkipJava`
passed: 112 Lua syntax checks, 175 scripts, 287 checks, 0 failures; `git diff
--check` passed.

The 2026-09-29 base-resident extension is covered offline in
`test-combat-intelligence.lua`: a work-owning resident enters the existing
retreat, retains the task-board claim, releases temporary task transfer
reservations, survives the controller's base-assignment check, clears only
after the existing two-safe-scan rule, and retains its claim for arbitration.
The same test verifies one non-overwhelming zombie does not trigger retreat and
that an active supply run/order/carried item survive while temporary search
reservations are released. Native escape, formation, combat, return-to-base,
and save/reload remain Build 42 acceptance requirements.

### Remaining live verification
Build 42 must still compare a healthy equipped survivor against one zombie and
a small group, then an overwhelming group with a real viable escape lane. Record
whether native movement begins once, reaches a safer tile, re-evaluates danger,
and resumes without a run-stop-return loop or fabricated combat result.

The retreat admission regression was re-run during the 2026-09-27 fallback
review. `test-combat-intelligence.lua`, `test-autonomy-formation.lua`, and
`test-threat-classifier.lua` passed; no new offline regression was found. Live
Build 42 combat and escape-route verification remains outstanding.

The existing retreat admission is now player-configurable through the World
Sandbox option `Allow Autonomous Survivor Retreat` (default on). The setting
gates only new autonomous retreat admissions in `beginFlee`; an already active
retreat may reacquire a failed route and finish normal safe-scan recovery.
Direct player companions remain excluded, and combat, threat detection,
formation, traversal, explicit orders, claims, and duty resumption keep their
existing owners. Focused settings/combat coverage and the current full offline
gate are recorded in `WORK_QUEUE.md`. Build 42 must compare enabled/disabled
behavior for independent, base, faction, and group survivors, one zombie versus
an overwhelming group with a viable escape lane, direct companions, task
resumption, and save/reload before native behavior is accepted.

## Community-reported backlog — unverified until reproduced

The following reports were copied from the Discord bug tracker on 2026-09-27.
They are intentionally recorded as `reported` rather than confirmed bugs. Some
may already be fixed, may be design requests rather than defects, or may have
come from a different mod/version/setup. The external reference path supplied
by the owner is held in a local owner-only bug inbox; inspect it only
when the related item is actively investigated. Do not treat those files as
authoritative without matching the Build 42 version, Knox revision, save, and
runtime setup.

Priority is provisional and reflects player impact plus dependency order. These
items should be deduplicated against existing systems before implementation.

## BUG-KS-013 — Survivors can idle indefinitely at bases
Status: in_progress
Priority: high
Owner: Codex
Type: behavior
Related: KS-PROD-008

### Report
Survivors sometimes stand around the base doing nothing instead of resting,
using furniture, reading, sleeping, moving naturally, or choosing useful idle
life behavior.

### Verification needed
Offline source review found an existing base-life decision path for needs,
explicit orders, settlement shortages, eligible tasks, hygiene, scheduled rest,
ambient movement, snacks, socializing, television, and storage organizing. The
focused offline checks `test-base-ambient-life.lua`, `test-duty-schedule.lua`,
`test-roaming-autonomy.lua`, `test-base-jobs.lua`, `test-base-needs.lua`,
`test-base-duty-controller.lua`, and `test-base-duty-simulation.lua` pass. They
do not prove native Build 42 actions start or that residents visibly behave
naturally, so this report remains open pending live reproduction.

A narrow offline ownership defect was confirmed and corrected: `onDutyChanged`
interrupted pending recreation but omitted pending organizing. Leaving base
duty, changing bases, or turning hauling off could therefore retain the
organizer action, route, and item/container claims. It now uses the existing
directive-interruption path. `test-companion-commands.lua` dynamically covers
unchanged valid duty, leaving base duty, hauling disabled, and base reassignment,
asserting one action/route cancellation and released item/container claims.
The focused base-life set (`test-companion-commands.lua`,
`test-base-organize-wiring.lua`, `test-base-recreation.lua`,
`test-base-ambient-life.lua`, `test-base-needs.lua`,
`test-base-duty-controller.lua`, `test-base-duty-simulation.lua`, and
`test-base-task-board.lua`) passed 8/8; `tools/verify.ps1 -SkipJava` passed 112
Lua sources, 176 scripts, 288 checks, and 0 failures. This is offline evidence
only: native timed actions, real item transfer, and base-duty/UI behavior still
need Build 42 validation and do not establish that the reported visible idling
is solved.

The latest diagnostic run records the surrounding symptom: in
`dev-runs/20260928-021135/console-since-launch.txt`, line 2441 reports
`base_movement:FailedStuck` before line 2483 shows the resident back at
`BASE_IDLE`; lines 3794 and 3830 record a failed rest route and the resident
in `BASE_AMBIENT_REST`. These are explicit movement failures that reach existing
recovery, not evidence that the watchdog timeout itself occurred.

An additional offline watchdog gap is now corrected at the same controller
owner: `MOVING_TO_REST` that exceeded its movement deadline previously fell
through generic abandonment instead of taking the existing real ground-rest
fallback, and timed-out `BASE_PATROL`/`BASE_RETURN` skipped
`handleBaseMovementFailure`, leaking the selected ambient-square reservation
and bounded failure record. Both timeout paths now use their existing recovery
owners. The extended dynamic `test-base-leisure-routing.lua` exercises actual
`tick` watchdog dispatch for patrol, return and rest, including route
cancellation, reservation release, backoff and the native rest-action fixture.
This script is local under ignored `tools/`; it is not a tracked Git change.
The focused base-life recovery set passed 7/7 and the full offline gate passed
112 Lua files, 177 scripts, 289 checks, 0 failures. Explicit native movement-
failure logs already show rest/patrol falling back correctly; no hung watchdog
route was observed live. Keep the reported visible base-idle behavior open
until a Build 42 full-day replay covers a never-resolving chair approach and a
stalled base patrol/return, verifies another resident can claim the released
square, and confirms the resident can resume an ordinary real-resource job.

The newest relevant Build 42 log (`2026-09-30_17-05_DebugLog.txt`) also records
task execution failures during the 17:12–17:15 test window: repeated
`base_task_move:FailedStuck`, a `state_timeout_BASE_TASK_ACTION` abandonment,
and a `farming_action_not_completed` task result. These show real movement and
native-work failures were observed, but the excerpt does not identify the
underlying route/action refusal or demonstrate stale claims. The farming task
was reported as failed rather than successful. Keep the full-day replay open;
capture the target, native action queue/result, required materials, and task
claim before/after for one such failure. No source fix is justified from this
log alone.

Focused correlation of that run identifies survivor `ks-spouse-player-1`
(`KnoxIsoPlayerShell`, not the local player) and farming tasks at
8038,11564 through 8041,11565. Plow/seed/water actions reached the action state,
then their authoritative snapshots showed no expected crop change; Knox marked
those tasks failed. A `BASE_TASK_ACTION` timeout occurred while chopping at
8033,11566. `FailedStuck` movement entered the existing bounded retry path;
the log later shows the resident idle with no current task and then selecting
other tasks. Nearby `receiveGlobalObjects: player is null` messages make the
native farming/global-object boundary a relevant lead, but do not prove those
messages caused the crop failures. Source confirms failure cleanup/backoff and
Notebook task rows expose blocked reasons. This remains a serious live base-life
failure, not an offline-confirmed Knox false-success or claim-leak defect.

Follow-up audit of `receiveGlobalObjects: player is null` (2026-09-30): the
latest DebugLog repeats the engine `General` warning while
`ks-spouse-player-1` is a `KnoxIsoPlayerShell` and farming actions are being
attempted. A search of Knox Lua found no `receiveGlobalObjects` handler,
registration, or invocation. `KS_BaseFarming` reads
`CFarmingSystem`/`SFarmingSystem` and queues vanilla farming actions; it does
not call the global-object receiver. The controller waits for pending native
actions, verifies crop state, and reports no change as failure; task-board
failure cleanup and bounded retry remain authoritative. Therefore the warning
is a live/native integration lead, not a confirmed Knox-owned offline defect or
proof of causation. Do not add a warning-suppression or player-context guard
without a Build 42 reproduction that identifies a Knox-owned call boundary.

The focused `test-base-farming.lua`, `test-base-jobs.lua`,
`test-base-task-board.lua`, `test-base-task-validation.lua`,
`test-base-action-lifecycle.lua`, `test-base-duty-controller.lua`,
`test-base-duty-simulation.lua`, `test-base-ambient-life.lua`, and
`test-base-needs.lua` checks were rerun and passed. The current full offline
gate passed 113 Lua sources, 189 regression scripts, and 302 checks with 0
failures; Java was skipped. These remain control-flow fixtures, not native farm
acceptance.

Required replay: use one isolated assigned farm tile and record its crop state,
resident shell identity, task/claim IDs, native action queue before/after,
required real tools/seeds/water, and `CFarmingSystem` state before/after. Compare
plow, seed, and water separately with a player and a resident shell. Correlate
any `receiveGlobalObjects: player is null` event. Also run one supplied
non-farming job and one missing-resource job to find the earliest divergence in
selection, claim, route, native action, result, or cleanup. Do not treat an
empty action queue as success.

Source review for the public food-availability report found a separate current-
development handoff gap inside this broader base-life report. `Needs.decide()`
already selects real safe food and the existing action path verifies hunger
reduction, but ordinary active base-task states returned from `tick()` without
rechecking needs. A resident could therefore remain committed to work, a task
action, or a supply transfer after hunger became urgent. The controller now
checks these ordinary task states on a bounded cadence and yields actionable
self-care through the existing task suspension owner. The claim remains held;
native transfer leases are released through their current owner, and normal
task restoration remains responsible for resumption. Focused claim-suspension,
needs, task validation/arrival, base action/cooking/security/recovery checks
passed; the exact-worktree offline gate passed 112 Lua sources, 177 regression
scripts, 289 checks, 0 failures. Test scripts remain local under ignored
`tools/` policy. This confirms an offline arbitration gap, not the specific
September 23 Steam report or native food access. Keep that report open pending
the live replay below.

Live replay: with one resident assigned ordinary non-guard work and another
case in a real supply transfer, make the resident hungry while safe edible food
is in an accessible assigned fridge/pantry. Verify ordinary work yields,
actual food access and Build 42 eating reduce hunger, the exact task claim is
retained without duplication, and useful work resumes. Repeat with food only
inside a nested container and with unavailable/unsafe food to confirm truthful
failure/retry rather than fabricated relief. Include save/reload while the task
is suspended if the task claim persists across that state.

For that replay, use a disposable save with a safe, loaded base and two or more
base residents. Keep player orders, urgent needs, active threats, and in-flight
jobs out of the baseline; give the base usable chairs/beds and ordinary
recreation objects. Enable existing autonomy diagnostics. Observe across one
full in-game day, recording each resident's identity, duty/schedule, visible
behavior, and periodic **Write Survivor Status to Log** output. Then run one
controlled useful-work case with the required real items available and one
resource-missing case. In the latter, confirm no work is fabricated and record
any visible/logged blocked reason or complaint. If a resident appears stuck,
capture repeated status lines with `state`, `decision`, `destination`,
`lastFailure`, `failureTick`, and `retryAt`, plus the matching short DebugLog
slice. Classify standing during a valid wait/retry separately from a resident
that remains stationary after its decision or native action has failed.

2026-09-29 staged Build 42 observation: the owner reports that residents mostly
stood in place or relocated occasionally without useful work, and that Work
and Schedule controls did not produce an obvious result. Treat the behavior as
valid live regression evidence; it does not by itself identify whether native
movement/actions, configuration, or UI dispatch was the first failure.

Current-source review confirmed two Notebook defects that could make controls
look inert or misleading. First, the Crew view enables controls using the
Notebook-selected base, but service writes resolved only the owner's primary
base; a resident in another owned base therefore failed schedule, job, and
work-preference writes. Second, periodic refresh restored the selected row
after `populate()` had painted the detail controls, so a row could show one
resident while the controls reflected another. The existing service and
persistence owners now accept the selected owned base, reject stale/foreign
base IDs, and notify the same runtime duty owner. Crew selection is preserved
through refresh/populate and details repaint after restoration. Notebook tabs
and successful preference feedback were made more explicit. No task scheduler,
duty owner, or persistence path changed.

Focused `test-notebook-base-context.lua`, `test-notebook-refresh.lua`,
`test-base-setup-ui.lua`, duty-schedule, work-preference, order-routing,
companion-command, base-duty, job/task-board, ambient-life, and needs checks
passed. `tools/verify.ps1 -SkipJava` passed 112 Lua sources, 182 regression
scripts, 294 checks, 0 failures; `git diff --check` passed. Regression files
under ignored `tools/` are local-only and are not tracked Git evidence.

This fixes confirmed Notebook-to-service targeting and stale selection display,
not the reported base-life inactivity itself. Keep BUG-KS-013 open. Build 42
must still confirm UI input/focus, selected secondary-base writes, schedule and
preference persistence after closing/reopening, runtime duty notification,
real task discovery/claim, native movement/action start, truthful blocked
reasons, interruption/reassessment, and useful work over a full in-game day.
Use the short replay in `DEVELOPMENT_TESTING.md` before the full-day run.

2026-09-30 focused runtime-log review of `dev-runs/20260928-021135` found
bounded movement/action recovery, not a conclusive cause for the owner's
visible inactivity: `ks-dev-14` logged `base_movement:FailedStuck` at frame
35762, then `BASE_IDLE` with retry 36122 at frame 36000, followed by
`BASE_PATROL` at frame 36300. Rest attempts logged failure and a ground-rest
fallback, then `BASE_AMBIENT_REST` with retry 44209; later traces show repeated
ground-rest fallback with bounded retry. This confirms failures are being
classified/re-elected in that run, but does not prove residents then perform
useful native work or that furniture recovery is safe. Keep the live full-day
replay open; do not add an idle animation or a parallel scheduler from these
traces alone.

2026-09-30 owner follow-up: base work appeared to function provisionally, but
the full-day, supplied-task, and missing-resource replay was not completed.
Keep BUG-KS-013 open and provisionally observed working; do not treat this as
passed. The schedule was still hard to read: too much explanatory/status text,
unclear hour feedback, and a weak current-hour cue. KS-PROD-008 Slice J now
reduces that text and strengthens color/hour feedback offline; mouse/joypad,
small-screen rendering, save/reopen, and schedule semantics still need the
short Build 42 schedule replay in `DEVELOPMENT_TESTING.md`.

2026-09-30 couch/table exit report review: the loaded controller enters and
leaves recovery using vanilla `ISRestAction` / `ISSitOnGround` and the native
character sitting state. Knox releases its rest reservation and, on
interruption, requests the native `forceGetUp` transition; it does not select
or teleport to an exit square, move furniture, or own collision resolution.
Source and offline fixtures do not reproduce a native stand-up collision or
establish a safe alternate exit. Classify this adjacent report as **unconfirmed,
native/live-only geometry**, not a confirmed controller defect. Do not add a
Knox position correction without a Build 42 reproduction showing a Knox-owned
continuation failure. The exact replay is in `DEVELOPMENT_TESTING.md`.

## BUG-KS-014 — No reliable base cleanup order
Status: deferred
Priority: medium
Owner: Codex / OpenCode
Type: feature request
Related: KS-PROD-008

### Report
There is no dependable way to direct survivors to collect loose ground items
and place them into appropriate storage.

### Verification needed
Compare existing hauling, storage claims, and job/task-board behavior before
adding a new cleanup job. Do not duplicate the existing hauling/organize path.

Offline source review distinguishes two existing paths from the reported need:
carried-inventory cleanup/deposit and a claimed corpse-hauling task. No general
base job was found that collects arbitrary loose ground items and routes them to
typed storage. `KnoxInventoryActions.queueDrop` is an existing native fallback
for a carried item at the actor's current square; it uses
`ISInventoryTransferAction`, and cleanup checks source removal plus a non-nil
world item. That does not discover loose items, target a persisted zone square,
prove destination-zone receipt, or restore ownership after an ambiguous native
partial transfer. The locally installed Build 42 `ISInventoryTransferAction`
resolves a floor destination by checking the actor's current square and then
neighboring squares; the existing Knox drop wrapper cannot request a specific
zone square. The bounded ground-item cleanup/storage concept remains a future
design candidate in `docs/production/ROADMAP.md`; do not treat current cleanup
dropping as ground storage. No new cleanup system or ground stockpile was added
in this pass.

Owner follow-up (2026-10-01): the requested future UI should filter real
containers and let existing hauling/resupply route items through those
container policies with less per-container setup. A separate `Storage Zone`
work area was requested for filtered placement on real floor squares, with an
intended four-item-per-tile corner arrangement. The current native floor
transfer path cannot prove an exact requested square, per-item receipt, or
rollback after ambiguous partial transfer. Keep this ground-zone design
deferred; do not simulate the four-corner layout or create abstract stock.
Container-filter semantics and UI are a separate implementation package and
must preserve legacy role/priority behavior for old saves.

## BUG-KS-015 — Loot deposit and resupply are unreliable
Status: todo
Priority: high
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Loot, food, tools, materials, medicine, and ammunition do not always flow
reliably between survivors, jobs, needs, and designated base storage.

### Verification needed
Trace one real loot → storage → need/job resupply loop and identify the first
failed transfer, claim, reservation, or ownership boundary.

The existing path connects loot selection and
carried-item protection (`KS_SurvivorLooting`), controller-owned deposit trips
and retries, typed/capacity-aware destinations (`KS_BaseStorage`), native
inventory-transfer actions, shortage/task supply planning, and persistent duty
ownership. Focused storage, organizer, supply, needs, cleanup, job, inventory,
and persistence tests passed in the 2026-09-27 review. These fixtures cannot
prove native movement, reachability, container mutation, or save/reload. Keep
this report open for one disposable live loop: real loot → assigned typed
storage (then General fallback) → need/job withdrawal, checking item identity
and counts before/after and after reload.

### 2026-09-30 confirmed generic-loot receipt gap
Source tracing confirmed that `LOOTING` treated generic exploration plans as
successful once the native action queue became empty. Unlike need food/water,
party food, base resupply, and away-team collection, generic clothing/medicine/
weapon/scavenge candidates had no inventory receipt gate. A refused or partial
native transfer could therefore reach `loot-complete` despite the planned item
not being carried. Generic loot now verifies every selected item by exact native
inventory identity; zero/partial receipts record a truthful failure, cool down
the source container, release the existing item/container leases, and return to
normal arbitration. It does not fabricate a transfer or undo a partial real
transfer. Special-purpose result owners are unchanged.

Focused local `test-generic-loot-receipt.lua`, `test-survivor-looting.lua`, and
`test-companion-loot-orders.lua` passed. The new focused regression is under
ignored `tools/` policy and is not Git-tracked evidence. The 2026-09-28 runtime
slice contains 29 generic `loot-complete` events but no exact inventory receipt
trace; it neither reproduces nor disproves the reported clothing/medicine/
weapon symptom. Build 42 must still verify success, refusal, partial transfer,
equipment reconsideration, cooldown/retry, and save/reload with real item
identity/counts. This is offline-fixed / live-pending, not a claim that the
community report was reproduced.

Connected base-supply planner/routing, group-support, away-team executor,
away-team lifecycle, and survivor-needs focused checks also passed. The current
dirty-tree `tools/verify.ps1 -SkipJava` passed 112 Lua sources, 183 regression
scripts, 295 checks, 0 failures; `git diff --check` passed. Java was skipped;
no Java/runtime bridge file changed.

2026-09-30 owner follow-up: loot/storage behavior was not fully exercised.
The existing receipt correction is offline evidence only; BUG-KS-015 remains
provisionally unconfirmed/live-pending, not passed. Replay exact real item
identity/count through pickup, return, assigned/general storage deposit,
shortage reassessment, and save/reload.

## BUG-KS-016 — Storage category routing is incomplete
Status: offline_fixed_live_pending
Priority: high
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Survivors sometimes use containers that do not match their assigned category.
The reports also request multiple storage areas of one type, a General Storage
fallback, and a Log & Firewood Storage area.

### Confirmed offline boundary
`KS_BaseContextMenu` exposed “Use for Logs & Lumber” and
`KS_BaseStorage` already classified logs, tree branches, twigs, and firewood
under the `logs` role. `KS_BaseManager.STORAGE_CATEGORIES` did not admit
`logs`, however, so selecting that visible option failed with
`unknown_storage_category` before any persistent assignment or native transfer
could occur.

### Current correction
The manager, player menu, and persistence validator now accept the existing
`logs` role. The same assignment path now exposes and persists the already
implemented `general` role, whose matcher and deposit fallback accept otherwise
unclassified real items. The storage label follows each assigned role. Focused
coverage selects/removes both policies, checks persistence validation, verifies
General Storage fallback, and checks Log, TreeBranch, Twigs, and Firewood
classification. No new transfer, claim, or resupply owner was added.

### Validation and remaining scope
On 2026-09-27, `test-base-storage-menu.lua`, `test-base-storage.lua`,
`test-base-organize-wiring.lua`, `test-base-supply-routing.lua`,
`test-base-supply-planner.lua`, `test-base-jobs.lua`,
`test-base-task-board.lua`, `test-multi-base.lua`, `test-base-needs.lua`, and
`test-inventory-cleanup.lua` passed. `tools/verify.ps1 -SkipJava` passed: 112
Lua syntax checks, 175 scripts, 287 checks, 0 failures; `git diff --check`
passed.

Multiple same-category stores, typed overflow, and category selection have
offline coverage. Real loot → storage → need/job resupply behavior, physical
container transfer, and save/reload remain live-unverified. Loose ground-item
pickup is a separate future feature candidate, not implemented by this fix.

### 2026-10-01 container-filter follow-up
The previous one-role-per-container player menu is now a multi-filter editor on
the existing real-container policy. Filters can be combined, with General
Storage exclusive as the catch-all. `KS_BaseStorage` applies the same filters
to deposits, organizer choices, base task-material reads, food/water supply
retrieval, and storage-based log-processing eligibility. The context menu
resolves the clicked square against every player-owned base/outpost, so a
container in an outpost writes to that outpost's policy. Existing unversioned
role/priority records are not rewritten and preserve their former behavior;
editing one promotes that container to strict filter semantics. Contents which
do not match remain physically untouched and are not used through that policy.
Nothing creates an abstract stockpile or moves real items outside the existing
native transfer/result path.

Focused `test-base-storage-menu.lua`, `test-base-storage.lua`,
`test-companion-base-domain.lua`, `test-autonomy-water-source.lua`,
`test-base-woodcutting.lua`, `test-base-needs.lua`,
`test-base-organize-wiring.lua`, `test-base-supply-routing.lua`, and
`test-base-task-supply-entry.lua` passed. The regression files are under
ignored `tools/` policy and are local-only evidence. Build 42 still needs real
container deposit/withdrawal, filter visibility and persistence, outpost
targeting, old-save compatibility, capacity/content preservation, and native
action/reload acceptance. Ground storage remains a separate deferred feature
under `BUG-KS-014`.

### 2026-10-01 owner storage clarification and offline continuation

The owner clarified the intended policy: any eligible container in an owned
base radius participates automatically; explicit vanilla item-category filters
are preferred, while unmatched items may use a real unfiltered container as a
fallback. The existing context submenu was replaced with a large, scrollable
filter window populated from Project Zomboid script-item `DisplayCategory`
values plus Knox convenience groups and General Storage. Persistence accepts
validated `display:<category>` keys in the same per-container policy. Loaded
unassigned containers are represented only by short-lived references: no
policy, container name, capacity, inventory instance, or item ledger is
created. The existing organizer can now find real misplaced items in these
containers and route them toward an explicit matching filter, one item at a
time through its existing native transfer owner. Unconfigured containers are
not shuffled among one another. Job material lookup, supply lookup, and
deposit discovery can use the same transient real-container references.

Focused storage UI, menu, storage, organizer, task-supply, needs, water,
woodcutting, and base-domain tests passed. The full offline verifier passed 103
Lua syntax checks, 200 regression scripts, 303 checks, 0 failures; Java was
skipped. `git diff --check` passed. These tests use offline engine doubles and
do not establish Build 42 UI rendering, native transfer success, filter save/
reload, capacity behavior, or resident movement. Re-test those live before
changing the status above. Container cleaning and filtered ground `Storage
Zone` remain separate feature work; the latter remains gated on exact-square
native placement, receipt, and rollback evidence.

`deployDev` then succeeded. SHA-256 comparison found all 110 `mod/42` source
files identical in the local development mod and Workshop `Contents`; the
Workshop payload additionally contains the two expected generated Knox agent
files. This is local staging only, not upload or live acceptance.

## BUG-KS-017 — Base boundaries are inaccurate or cannot join connected areas
Status: todo
Priority: high
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Large bases may calculate inaccurate boundaries, and players cannot reliably
attach additional connected buildings or areas to an existing base.

### Verification needed
Offline review found the boundary editor selects two world squares and commits
through `KS_BaseManager.setTerritory`; `KS_Persistence.normalizedBaseTerritory`
sorts both axes into canonical min/max coordinates before saving. Territory
ownership is one axis-aligned rectangle and applies to all floors. The existing
selector regression only checks cursor setup, modal invocation, and one save
call; it does not assert selected coordinates or persisted bounds. No offline
geometry defect is confirmed, and UI projection/hit-testing still requires a
live replay.

2026-09-30 offline re-review: `TerritorySelector` forwards the two selected
world squares to `KS_BaseManager.setTerritory`; persistence sorts both axes,
rejects undersized/overlapping rectangles, and stores inclusive min/max bounds
with `allFloors=true`. `containsSquare` uses the same inclusive rule. The
`test-base-selectors.lua`, `test-companion-base-domain.lua`, and
`test-multi-base.lua` fixtures cover cursor setup/save routing, territory
normalization/domain, and overlap, but do not prove native cursor projection
or rendered highlights. No new runtime log was available; no source change is
justified without the live coordinate-versus-highlight-versus-saved-bounds
comparison below.

On a disposable copy of the affected save, record the Build 42 version, Knox
revision, runtime/mod path, save identity, and the existing base ID/bounds.
Using the current boundary editor, select the same large asymmetric area in
both corner orders. Record the two clicked world-square coordinates, draft
highlight, confirmation dimensions, saved min/max bounds, and reopened editor
state. Check all four boundary edges and immediately adjacent tiles against
base ownership, then save/reload and check the same values again. For a
connected building/area, record whether it lies inside the rectangle or
outside it; the current single-rectangle model cannot claim disjoint areas, so
do not interpret this as an existing polygon/union feature.

## BUG-KS-018 — Fort Waterfront boundary selection flips
Status: todo
Priority: high
Owner: Codex / OpenCode
Type: UI/behavior
Related: BUG-KS-017

### Report
Open Base Management → Edit Boundary can flip between the main fort and the
pasture/farm area while selecting the full Fort Waterfront location.

### Verification needed
Reproduce on the same disposable Fort Waterfront save referenced by BUG-KS-017.
Record the clicked world-square coordinates and screenshots of the live draft
highlight and confirmation size while selecting the main fort and pasture/farm
corners in both directions. Compare those values with the saved territory
bounds and the reopened boundary display before and after save/reload. If the
clicked squares themselves differ from the cursor target, investigate
Build 42 cursor/screen-to-iso hit-testing; if clicks are correct but the draft
or saved bounds differ, isolate rendering versus persistence next. Offline
normalization currently sorts reversed corners, so a live flip is not yet
explained by source inspection. Keep this report separate from the larger
connected-area feature request in BUG-KS-017.

## BUG-KS-019 — Survivors leave doors open after passing through
Status: resolved_offline_live_pending
Priority: medium
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Survivors do not always close doors after traversal. Any automatic close policy
must respect permissions/settings and avoid open/close loops.

### Verification needed
Test normal passage, combat interruption, player-owned doors, locked/blocked
doors, and repeated pathing through the same doorway.

Offline source review confirmed a narrow failure in the supported `setOpen`
fallback: door cleanup requested `setOpen(true)`, so a door wrapper without a
toggle method could never be closed by that path. The fallback now receives
the requested open/closed state, with focused coverage in
`tools/test-door-discipline.lua`. This does not confirm the reported behavior
for native Build 42 doors; the live traversal scenarios above remain required.

2026-09-30 status check: `lua tools/test-door-discipline.lua` passes in the
current worktree. The offline fallback correction is complete; the original
native-door symptom remains unconfirmed until the Build 42 replay below.

## BUG-KS-020 — Barricade jobs stop before completing valid windows
Status: offline_fixed_live_pending
Priority: medium
Owner: Codex / OpenCode
Type: job
Related: KS-PROD-008

### Report
Barricade work may stop after one window or one pass instead of processing all
valid windows. The report also requests configurable plank counts per side.

### Current evidence and acceptance
Offline source review confirmed the explicit-order continuation gap described
below. Build 42 replay is still needed to verify native multi-window execution,
material delivery, interruption/retry, and persistence. Treat plank-count
options as a separate design request.

The explicit building order path enumerates up to 24 valid targets in the
clicked building, queues one task per target, and reuses existing queued or
claimed target tasks. A source defect was confirmed in the continuation handoff:
only the first queued target was assigned as manual, so later windows depended
on autonomous selection and stalled when `automaticJobs` was disabled. Each
queued target from the explicit order now retains a `manualOrder` marker in its
existing task record. The controller claims one such task through the task
board before the automatic-jobs gate, preserving capability checks, atomic
claims, bounded retry, and one native action at a time. Successful completion
clears that marker; cancelled tasks remain unclaimable. Automatic defense work
is separate and intentionally discovers one opening per pass. Focused offline
tests now cover the disabled-autonomy multi-target handoff, claim uniqueness,
bounded retry, and cancelled/future tasks. Native two-window execution,
material delivery, interruption, and save/reload remain live-pending.
Plank-count-per-side remains a separate feature request.

Focused `test-manual-barricade-order.lua`, barricade, task-board, task-validation,
base-job, base-action-lifecycle, duty-controller/simulation, and schedule checks
passed. `tools/verify.ps1 -SkipJava` passed 113 Lua source checks, 189 regression
scripts, 302 checks, and 0 failures; Java was skipped. `git diff --check` passed.
The new script is under ignored `tools/` and is local-only evidence.

## BUG-KS-021 — Owned survivor map tracking is incomplete
Status: todo
Priority: medium
Owner: Codex / OpenCode
Type: UI/feature
Related: KS-PROD-008

### Report
Owned survivors should remain visible on the map while offscreen, with nearby
survivors optionally grouped into a marker.

### Existing owner and implementation

Offline source review found an existing Knox-owned overlay in
`KS_MapOrders.ownedLocations`: it resolves owned living survivors from loaded,
persisted logical, then last-known coordinates, and renders durable death
evidence separately. Nearby living owned-survivor locations now form a
transient derived projection inside the existing map refresh. Sorted survivor
IDs seed non-transitive anchor clusters within 20 world tiles on the exact same
floor; marker positions prefer loaded coordinates over logical/persisted and
last-known coordinates. Group summaries retain unique member IDs/names and
loaded, persisted, and last-known counts. Deceased evidence remains an
individual marker. Survivors without usable coordinates are not assigned a
fabricated point; the existing overlay reports their count and invalid
coordinate count. Duplicate IDs are ignored. The existing native-first
right-click path is unchanged; no marker-click detail path currently exists.
Ownership, identity, faction/group membership, formation, persistence, and
destination orders are not mutated.

Focused `test-map-owned-locations.lua` covers singleton, nearby grouping,
same-floor separation, non-transitive anchoring, loaded/logical/last-known
confidence, invalid/stale/dead/foreign records, ownership changes, movement
regrouping, duplicate identity, no membership mutation, rendered summary and
right-click preservation. Build 42 projection, appearance, interaction,
streaming and save/reload remain live-unverified; this is a missing feature
slice, not a reproduced stale-marker defect.

## BUG-KS-022 — Faction base map markers are missing or stale
Status: todo
Priority: low
Owner: Codex / OpenCode
Type: UI/feature
Related: KS-PROD-008

### Report
Known faction bases should have map markers that update or disappear when a
faction moves, dies, or abandons the location.

### Verification needed
Wait until faction/base lifecycle is live-validated. Do not add marker state
that can become another stale ownership system.

Offline source inventory found durable faction-owned base records and existing
relocation/removal paths, but no faction-base map-marker consumer. This is a
missing map feature, not a stale-marker regression in the current implementation.
Any later implementation should derive presentation from current faction/base
records rather than adding a parallel marker ledger. Lifecycle and map behavior
still require live validation.

## BUG-KS-023 — Survivor work priorities need more player control
Status: todo
Priority: high
Owner: Codex / OpenCode
Type: feature request
Related: KS-PROD-008

### Product scope
This is a player-control feature, not a confirmed scheduler defect. It applies
only to player-owned survivors in base duty through the existing one-job
selector. Active companions have no autonomous task-election path and receive
no effective work controls; if one is assigned to base duty, the base selector
can use its preserved preferences. NPC faction residents and independents keep
their existing behavior.

### Implementation and evidence
The existing sparse `duty.workPriorities` map now stores High, Normal, Low, or
Disabled for the selector-backed groups: guard, patrol, repair, cooking,
farming, woodwork, barricade, and hauling. Missing entries resolve to Normal.
Legacy 1/2/3/4/false values migrate to High/Normal/Low/Low/Disabled; unknown
keys or invalid values are discarded. High/Normal/Low only break otherwise
equal selector choices; Disabled excludes that category from new autonomous
selection. It does not cancel a claimed task or an active native organizing
action. Direct task assignments still use the existing task-board claim path.
Hauling Disabled also prevents a new ambient organize round. Existing claims,
reservations, explicit orders, active supply runs, and native work ownership
remain with their current systems. No selector-backed groups currently exist
for medical, cleaning, or scavenging, so those controls were not added.

Focused base-work preference, task-board, base-job, companion/base conversion,
organizer-interruption, needs, duty-controller, Notebook, and persistence
recovery regressions passed. Full `tools/verify.ps1 -SkipJava` passed with 112
Lua sources, 181 regression scripts, 293 checks, and 0 failures. The regression
scripts under `tools/` are ignored/local-only. Build 42 acceptance remains open
for visible UI, selection, interruptions, companion-to-base conversion, native
task execution, and save/reload.

### Broader controls still out of scope
No RimWorld-style priority grid, new job groups, companion job selector,
medical/cleaning/animal-care/scavenging scheduler, or alternate task owner is
implied by this slice.

The same player-control review found that automatic equipment upgrades were
unconditionally reconsidered both during idle autonomy and after loot, despite
the need for an explicit player preference. The existing per-survivor policy
record now stores `autoEquipment`; missing values preserve the historical
enabled behavior. The owned-survivor Tactics menus expose individual and party
controls, including player-owned base residents, and the controller gates both
automatic reconsideration sites. Manual inventory equipment and combat weapon
selection remain separate. Focused preference, controller-sync, equipment
intelligence, companion-command, and combat regressions passed. This closes
that specific control gap; the broader ranked-role and additional work-group
request above remains a feature candidate, not a confirmed defect. Native
equipment actions and save/reload still require Build 42 acceptance.

## BUG-KS-024 — Offscreen survival behavior is incomplete
Status: in_progress
Priority: critical
Owner: Codex
Type: behavior/architecture
Related: KS-PROD-008, BUG-KS-001

### Report
Survivors should continue bounded travel, looting, eating, resting, combat,
injury, death, resource gathering, and return-to-base behavior while away from
the player.

### Verification needed
Reconcile this report with the existing unloaded-survival architecture and
BUG-KS-001. Never manufacture native combat, loot, death, or world damage from
an unloaded state without documented simulation authority.

### Evidence
Offline source review found `KS_UnloadedSurvival.advanceHibernated` applying a
daily deterministic "scuffle" to autonomous and supply-running survivors. It
could reduce persisted health, mark an unloaded survivor dead, and create a
`fight` trace at virtual coordinates; later restoration could apply the saved
health to the native body. That crossed the loaded/native-combat boundary.

The scuffle branch is removed. Unloaded survival still advances only its
persisted needs, real carried supply consumption, rest, and logical travel. It
does not create combat injury, death, blood, or fight traces. Focused unloaded
survival, group, world-trace, and event-runtime tests pass. `tools/verify.ps1
-SkipJava` then checked 112 Lua files and ran 175 regression scripts (287
checks, zero failures). Native materialization and real save/reload behavior
remain live-unverified.

The same transition review found automatic hibernation removed a native shell
before committing its `hibernated` ledger state. A failed final ledger write
could therefore unregister the controller after body removal, leaving no valid
active or unloaded owner. Hibernation now commits stored ownership first; a
failed commit retains the active shell, and removal succeeds only when the
bridge confirms that no shell remains. A failed removal re-captures the loaded
snapshot before its bounded retry. Focused lifecycle, virtual-base-return,
unloaded-survival/base-return, and away-team tests pass, followed by the same
full offline gate. Native removal acknowledgement and real save/reload remain
live-unverified.

Away-team dispatch had the same ownership mismatch across a multi-member
handoff. A failed pre-removal store/team commit could leave a live body with a
`hibernated` ledger; a middle/final native removal failure could restore normal
duties for members whose bodies were already gone. Dispatch now rolls stored
ledger ownership back to `loaded` for every still-live member on a pre-removal
abort. Members already confirmed removed remain hibernated and recoverable,
while the durable dispatch record is blocked rather than reported as outbound.
Focused coverage exercises valid, invalid, duplicate, dead, store/team failure,
first/middle/final removal failure, recovery and retry paths. It preserves the
same identity, inventory/equipment/needs ledger, orders and affiliation in
fixtures. The current `tools/verify.ps1 -SkipJava` run checked 112 Lua files
and ran 176 regression scripts (288 checks, zero failures). Live native
teardown, save/reload, rematerialization and duplicate-body evidence remain
required.

The blocked-dispatch recovery path is now also covered offline. Only members
whose removal was acknowledged retain the `away` duty beneath the blocked
ledger; members whose shell remains live recover their previous duty
immediately. The blocked ledger persists across a Lua persistence reload and
an acknowledged removed member can release its prior duty only after the
canonical record-restoration path has registered a body. Finalization failure
uses the same blocked ownership path. This does not prove native removal,
record reconstruction, inventory/equipment restoration, or duplicate-body
prevention in Build 42; those remain live acceptance requirements.

## BUG-KS-025 — Independent survivor/group/faction decision-making feels weak
Status: todo
Priority: high
Owner: Codex
Type: behavior/architecture
Related: KS-PROD-008

### Report
Independent survivors, groups, and factions can feel like random wandering or
looting instead of making decisions around supplies, danger, food, water,
healing, shelter, combat, and travel.

### Verification needed
Measure the existing decision chain and identify the first missing or failing
priority before adding new behavior or faction types.

Offline review did not identify a deterministic priority/ownership failure.
The existing single-survivor need evaluator gives active threats and medical,
water, food, recovery needs precedence; the controller then applies durable
orders, group-support/scavenge coordination, and ordinary autonomy through the
existing controller path. Focused needs, work-priority, anti-flap, group support,
group scavenging, and behavior-integration tests passed in the 2026-09-27
review. This does not establish that decisions look believable during native
gameplay. Keep the report open until a live observation identifies the first
undesired decision with survivor identity, state, need/threat snapshot, group
role, and selected action.

On 2026-09-29, a narrower faction-base supply-election gap was confirmed and
closed under KS-PROD-008: eligible matching-faction residents can now answer
their base's actual shortage through the existing receipt-gated supply run.
Focused auto-scavenge, group-sortie, supply-planner, base-needs, inventory
cleanup, and routing checks passed; `tools/verify.ps1 -SkipJava` checked 112 Lua
sources and 178 regression scripts (290 checks, 0 failures). This does not
resolve the broader reported independent/faction decision quality; it remains
reported pending native observation. See D-022 and the faction supply replay in
`DEVELOPMENT_TESTING.md`.

## BUG-KS-026 — World population ownership is not yet proven unified
Status: todo
Priority: high
Owner: Codex
Type: architecture/design
Related: KS-PROD-008

### Report
Solo survivors, groups, and factions should use one balanced population,
identity, origin, affiliation, and lifecycle system, with solos common, groups
less common, and factions rarer.

### Verification needed
Source review indicates a shared foundation, but live allocation, origin
uniqueness, event ownership, and performance remain to be demonstrated. Do not
tune population counts until a measured bottleneck exists.

The 2026-09-27 offline ownership review found no deterministic identity/origin
collision path: `KS_WorldPopulation` allocates through the persistence-owned
`allocateWorldSurvivor` boundary, which rejects reused population origin keys;
groups and factions attach to canonical survivor IDs, and event-entry creation
allocates those same identities before claiming event duty. Focused world-
population, contextual-origin, faction-development, event-entry, and named-event
runtime tests passed. These checks do not prove Build 42 spawn-catalog
completeness, live materialization/activation, concurrent streaming behavior,
or real-map performance. Keep population balance and unified ownership reported
until those are measured in-game.

## BUG-KS-027 — Custom survivor/group/faction creator is missing
Status: todo
Priority: low
Owner: Codex / OpenCode
Type: feature
Related: KS-PROD-008

### Report
The owner would like a creator for custom survivor, group, faction, and event
definitions including appearance, traits, skills, gear, relationships,
hostility, spawn rules, and locations.

### Verification needed
This is a future expansion, not a current bug. Defer until existing population,
identity, faction, persistence, and performance boundaries are stable.

## BUG-KS-028 — Group followers pause instead of fluidly following their leader
Status: in_progress
Priority: high
Owner: Codex / OpenCode
Type: behavior
Related: KS-PROD-008

### Report
Followers in NPC groups or factions may stop, think, and resume repeatedly
instead of following their leader fluidly. The problem appears more visible in
followers than leaders. Groups must still perform needs, jobs, combat,
traversal, and survival behavior without becoming permanently locked to
formation movement.

### Intended direction
Leaders should be able to issue group-level orders comparable to player group
orders. Followers should retain local autonomy for urgent needs, threats,
traversal, recovery, and valid individual tasks. Leader orders should be
explicit, interruptible, persisted where appropriate, and resumed after a
valid interruption instead of repeatedly resetting the follower brain.

### Verification needed
Reproduce with a leader and at least two followers across ordinary movement,
doors, fences, combat interruption, needs, distance changes, and save/reload.
Compare decision cadence, route ownership, formation refresh, order arbitration,
and native movement completion. Determine whether the pause is caused by
formation cadence, route requests, order arbitration, native movement timing,
or expected autonomy interruption.

Do not solve this by teleporting followers, ignoring threats/needs, or
reissuing native movement orders in a loop.

### Offline evidence
The `GROUP_FOLLOW` native-success branch was unconditionally entering a
45-tick `GROUP_WAIT`, even when the leader had already moved beyond the route's
completed formation slot. That source-level delay made a follower wait before
normal formation arbitration could consider the next bounded route. Successful
group routes now return to `IDLE` for the next controller tick without issuing
a movement request themselves. Existing route-commit, cadence, threat, need,
combat, traversal, and movement-failure owners remain authoritative.

`tools/test-autonomy-formation.lua` now covers native group-route success,
immediate re-arbitration, and no duplicate request from the success handler.
Focused formation, relationship, unloaded-group, order-routing/signals, and
behavior-integration checks passed. `tools/verify.ps1 -SkipJava` checked 112
Lua files, ran 176 regression scripts, and reported 288 checks with zero
failures. Build 42 still must verify actual leader-plus-multiple-follower
movement, doors/fences, combat/need interruptions, native route timing, and
save/reload continuity. The bounded leader-order slice below is now part of
the follow-up evidence path; it does not complete this bug.

### Leader-order slice
The first NPC leader-order slice adds one durable group directive owned by the
canonical travel-group leader: `follow` or explicit bounded `hold`. It is
distinct from the leader's read-only autonomous life-intent summary and does
not own native movement, combat, or timed actions. Successful ordinary roam
and regroup routes now call the existing follow wrapper; invalid, dead, or
detached leaders are rejected. Persistence validates stored issuer, group, and
faction leadership, ignores legacy unbounded records, defaults a new directive
to a 0.25-game-hour lease, and keeps an identical default reissue's deadline
and revision. There is no autonomous hold choice, order UI, destination command,
or group mission in this slice.

Relationship coordination delivers a changed directive to current loaded
followers as pending formation-only arbitration. Delivery itself does not
cancel or replan. The controller may apply a responsive hold only after its
danger scan and only when traversal or a timed action no longer owns the body;
needs, jobs, combat, recovery, and retry owners remain protected. Identical
follow delivery causes no cancellation or route churn; a native cancellation
must report `MOVE_CANCELLED`, and a failure retries no faster than 60 ticks.

Extended relationship-coherence, autonomy-formation, and roaming-autonomy
coverage exercises persistence, delivery, route-only issuance, expiry,
deduplication, safe cancellation/retry, and fixture-shaped interruption.
The focused relationship, formation, roaming, order-routing, faction,
human-encounter, unloaded-group, and priority suites passed; `tools/verify.ps1
-SkipJava` checked 112 Lua files, ran 176 regression scripts, and reported 288
checks with zero failures; `git diff --check` passed. Build 42 still must verify
a disposable leader-plus-two-follower ordinary travel/regroup replay, a
developer-assisted persistence-API hold during fence/door and need/combat cases,
cancellation, expiry/reload, and no duplicate route requests. Leader-selected
destination movement, complex missions, raids, and group-order UI remain future
bounded work.

### Membership-change projection evidence — 2026-09-29
Canonical persistence removes a member and performs leader succession
synchronously, but loaded controller group caches were refreshed only by the
existing 60-tick relationship assignment cadence. A leader removal inside that
window could leave a loaded follower temporarily targeting the old leader and
formation slot. Persistence now raises a transient refresh request; the next
existing relationship-coordinator pass projects the canonical roster and
successor immediately. The forced pass is read-only with respect to group
objectives, preserves runtime life intent, suppresses objective announcements,
and does not cancel or issue native movement. The normal 60-tick cadence remains
unchanged when no membership change requested a refresh.

`tools/test-group-runtime-refresh.lua` exercises a loaded three-member group,
removes the leader inside the cadence window, and verifies successor/follower
projection, removed-member cleanup, no objective rewrite or announcement, and
normal cadence throttling afterward. Focused relationship-coherence,
unloaded-group, autonomy-formation and faction-persistence tests passed. The
current full offline gate checked 112 Lua sources and 179 regression scripts
(291 checks, 0 failures); the new test is local under ignored `tools/` policy.
This closes only the offline stale-projection handoff. Build 42 must still
verify native route behavior after member/leader removal, group cohesion,
movement arbitration and save/reload; the wider BUG-KS-028 follow behavior
remains live-unverified.

### Player-owned shared destination slice — 2026-09-29

Owner decision: implement a player-selected destination for the current
player-owned companion roster only. Independent NPC and faction leaders retain
their existing autonomous `lifeIntent` route, read-only group objective and
follower formation behavior; none of those owners are changed.

The existing **Move Party Here** action now enters one session-scoped shared
destination record in `KS_CompanionService`. The record snapshots Follow-duty
companions with no individual directive at issue time; Hold/Relax and base-duty
survivors are excluded. It is not a player-group leadership or persistence
record. Each
remaining companion reads the same destination through existing companion
service synchronization and routes independently through the existing
autonomy/native movement owner. A later explicit individual order removes only
that survivor from this command; a superseding party order cancels it. Threat,
combat, urgent needs, native traversal/actions and recovery remain higher
priority, and the still-active destination is reconsidered by the ordinary
controller when they release ownership.

The selected destination must be a finite point on loaded standable ground.
Arrival requires the actual same-floor character square within 1.5 tiles; native
route success outside that tolerance does not complete it. The command expires
after one in-game hour. Success reports “Party destination set for N companions”;
invalid selection reports the destination rejection reason. Explicit
cancellation is **Knox Survivors → Orders → Cancel Party Destination** and
reports cancellation; all-participant arrival reports completion. Arrival of
all still-eligible participants,
expiry, an invalid destination, or an empty valid participant roster clears the
record. Dead, dismissed or reassigned participants are pruned; later recruits do
not inherit the order. The player remains the command authority and existing
Follow anchor; no companion route leader or succession state is introduced.

Terra's review found that adding the shared record to `players[playerId]` would
create duplicate order ownership beside each survivor's durable `duty.directive`
and require succession, cancel, normalization and sync-cache changes. This
slice therefore stays runtime-only and intentionally does not survive save or
reload. This avoids claiming a persistence guarantee that the current ownership
model cannot safely provide.

Focused `test-party-destination.lua`, `test-directive-handoff.lua`,
`test-order-menu-callbacks.lua`, `test-order-routing.lua`,
`test-companion-commands.lua`, `test-radial-orders.lua`,
`test-autonomy-formation.lua`, `test-relationship-coherence.lua`,
`test-group-runtime-refresh.lua`, and `test-unloaded-groups.lua` passed.
`tools/verify.ps1 -SkipJava` checked 112 Lua sources, ran 180 regression
scripts, and passed 292 checks with 0 failures. `git diff --check` passed after
the production-record updates. These tests establish offline dispatch,
session-state, route-owner handoff, precedence, expiry, roster pruning and
session-reset behavior only. Build 42 pathing, rendered command UI, physical
arrival tolerance, interruption/resumption timing and any future persisted
order remain live acceptance; this runtime-only command intentionally does not
survive save/reload. Do not mark this bug or the companion movement slice
live-verified.

### Player-party cohesion extension — offline implementation

The player is the sole normal party anchor. `KS_CompanionService` derives the
Follow/no-directive roster, assigns stable runtime slots, and smooths its facing
from sustained player movement; no companion is promoted to a leader. The
existing controller remains responsible for arbitration and native routes.
Player-only target reservations extend the shared autonomy reservation table:
normal paired/single-file slots stay stable, while an unavailable slot or narrow
local approach compresses to a distinct nearby standable square. The player's
last finite standable loaded square is a bounded fallback during a brief
missing-square interval; traversal and a moving vehicle yield without creating
a companion leader. Members leaving Follow eligibility release their slot
leases. Death, dismissal, detachment/shutdown and reassignment release them
through existing lifecycle/controller cleanup.

During the D-025 destination order, eligible companions use distinct staging
tiles within its unchanged same-floor 1.5-tile destination radius. Native route
completion is not arrival; `markPartyDestinationArrived` checks live character
coordinates and clears only after all retained participants arrive. Arrived
members hold their staging lease while the rest of the snapshot travels.
Cancellation, supersession, expiry, individual-order removal and save/reload
remain owned by D-025; neither destination nor formation state is persisted.
NPC group/faction target calculation, leader projection/succession, combat, and
traversal engine owners were not changed.

Source review found the shared destination's old eligibility check excluded
individual directives but still admitted primary Hold/Relax companions. The
active destination slice now snapshots only primary-Follow companions with no
individual directive, as required by D-026; those primary orders remain
authoritative.

Focused local `test-player-party-cohesion.lua`, `test-party-destination.lua`,
`test-autonomy-formation.lua`, `test-directive-handoff.lua`,
`test-companion-sync-cache.lua`, combat/needs priority, order-routing/menu,
NPC group-scavenge, relationship, group-refresh, and unloaded-group regressions
passed. `tools/verify.ps1 -SkipJava` checked 112 Lua sources, ran 181 regression
scripts, and passed 293 checks with 0 failures; `git diff --check` passed.
These offline checks do not establish Build 42 pathfinding, native obstacle
traversal, animation, crowding, player movement/vehicle transitions, rendered
status, or interruption/resumption. BUG-KS-028's original NPC group cohesion
report remains open for its separate live acceptance.

## BUG-KS-029 — Firearm behavior needs a dedicated stabilization pass
Status: in_progress
Priority: high
Owner: Codex
Type: behavior
Related: KS-PROD-005, KS-PROD-008

### Report
Firearm use, aiming, reloads, target selection, ammunition handling, friendly
fire, and combat recovery need a complete reliable gameplay pass.

### Scope note
This is a future stabilization track, not incidental work in group movement.
Use real Project Zomboid weapons, ammunition, aiming, reload, damage, and
native action state. Live evidence is required for claims about actual shots,
hits, damage, and recovery.

### Offline review and live acceptance
The first bounded firearm review found no source-confirmed offline defect.
`KS_FirearmSupport.lua` selects only carried real weapons, delegates reload and
racking to native timed actions, and does not write ammunition, magazine,
chamber, projectile, hit, damage, or kill state. The developer-only
`firearm_duel` fixture may seed its own pistol, empty magazine, and loose rounds
but is not gameplay supply behavior. Existing focused firearm, empty-hand,
reload-yield, combat-scenario/intelligence, equipment-intelligence, and
weapon-preference tests cover readiness, native action deduplication, fallback,
policy persistence, and fixture boundaries.

Required Build 42 evidence is one hostile `firearm_duel` replay plus an
allied/neutral bystander check: record weapon, magazine, chamber and loose-round
state before/after reload and a shot; native aiming/reload/attack state; target
health; friendly-fire result; interruption/recovery; and save/reload after a
reload and a shot. Native hook invocation telemetry is not proof of a shot or
damage without corresponding native observation. Keep BUG-KS-030 vehicle work
deferred; no vehicle ownership defect was identified by this firearm pass.

### Offline stabilization pass — 2026-09-29

Owner-approved stabilization only. `KS_FirearmSupport.lua` and the existing
`KS_SurvivorAutonomyController` combat owner remain the only owners. Native
Build 42 still owns the reload/rack timed actions, the swing/attack hook,
projectile/ballistic result, damage, weapon condition, chamber/magazine state,
and ammunition consumption. No second combat scheduler, ammo ledger, simulated
hit, health mutation, or parallel weapon inventory was added, and Java was not
changed.

Source-confirmed defects corrected:

- The bounded reload-preparation budget (`RELOAD_PREPARATION_TIMEOUT_TICKS`) was
  a single unkeyed clock. A completed encounter could leave `reloadYieldStreak`
  and `reloadPreparationStartedAt` set, so the next engagement's fresh reload
  could immediately report `reload_stalled` and force a melee fallback. The
  budget is now keyed to the exact encounter target and prepared weapon identity,
  and is reset by `Controller:clearFirearmCombatState()` at every terminal
  boundary (target drop, retarget, success, failure, close/ranged fallback,
  weapon-preference change, directive abandon, controller error, detach
  recovery, flee, and shutdown).
- A ranged survivor that repeatedly failed to approach/pursue a target
  (`COMBAT_FAILED`) only received a generic threat cooldown and could retry the
  same gun indefinitely. `Controller:noteRangedCombatFailure()` now bounds
  consecutive ranged failures; at the threshold the encounter releases firearm
  ownership through the existing melee-fallback owner
  (`forceMeleeFallback`), preserves the still-valid target by clearing its
  generic unreachable cooldown, and resets on a real melee hand or a successful
  native fire request. Java's close-range reposition remains bounded by the
  native movement owner (`tickMovement` failure plus its own cooldown).
- Melee fallback re-equipped on every re-engagement window. `fallbackToMelee`
  is now a no-op when usable melee is already held, and the melee path prefers
  the exact carried item id (`equipNpcOwnedWeaponById`) instead of a same-type
  alternative.
- `wantsRanged` gained a bounded retention flag so an encounter already
  committed to a gun is not flipped to melee by a target pacing across the
  survivor-choice threshold. It never overrides an explicit melee order, the
  absence of a threat, or native skill/accuracy.

Focused `test-firearm-support.lua` and `test-combat-reload-yield.lua` were
extended for readiness, exact weapon identity, hysteresis, fallback idempotence,
budget keying, bounded ranged failure, no duplicate fire request while a native
action owns the weapon, teardown clearing, and directive preservation across
lifecycle/shutdown. Existing firearm, empty-hand, weapon-preference,
equipment-intelligence, combat-intelligence, autonomy-formation, threat
classifier, human-encounter, and combat-scenario-reporting regressions passed.
`tools/verify.ps1 -SkipJava` checked 112 Lua sources, ran 181 regression scripts,
and passed 293 checks with 0 failures; `git diff --check` passed.

This is offline evidence only. No native reload completion, shot, ammo
reduction, damage, animation, sound, friendly-fire, reposition, or save/reload
result is claimed. Live Build 42 acceptance remains open and is enumerated in
`DEVELOPMENT_TESTING.md`.

## BUG-KS-030 — Driving and vehicle behavior needs a dedicated stabilization pass
Status: in_progress_offline_update_live_pending
Priority: high
Owner: Codex / OpenCode
Type: behavior/compatibility
Related: KS-PROD-005, KS-PROD-008

### Report
Vehicle boarding, seating, driving, navigation, passenger group behavior,
vehicle ownership, fuel, exits, and recovery need a complete reliable gameplay
pass when the existing vehicle system is ready for focused work.

### Scope note
Per D-019, driving joins the core-completion track: autonomous NPC driving,
group vehicle acquisition, and 2–3 car convoys with no hard count cap.
Use real Project Zomboid vehicle state and native actions; do not add a
parallel abstract driving simulation. Hotwiring/key acquisition, forced entry,
player-assigned vehicle work orders with HP thresholds, specialist workstations,
and any vehicle-work UI remain deferred future tracks plugging into the
existing job catalog and Materials routing.

### Offline evidence (admission seam)
`VehicleTravel.assessReadiness` (`KS_NpcVehicleTravel.lua`) is now the single
shared verdict for a parked vehicle: driver, engine, driveability, speed,
towing, fuel (`getRemainingFuelPercentage`, sub-1% reads unfueled), and locks
(`areAllDoorsLocked`) resolve to one `ok, reason` result reusing the drive-
admission vocabulary; missing native state fails closed as
`vehicle_state_unknown`; locked vehicles are rejected (forced entry stays
deferred). Discovery (`safeVehicle`) delegates its state portion; drive
admission (`startDrive`) consumes the shared verdict with an identical local
fallback for contexts that never load the travel module. No movement, routing,
formation, leader-order, away-team, lifecycle, or persistence owner changed.
Focused vehicle set (`test-npc-vehicle-travel.lua` with the new ready/low-fuel/
locked/unknown matrix, `test-vehicle-driver.lua` with the fallback matrix,
`test-companion-vehicles.lua`, `test-vehicle-ownership.lua`,
`test-vehicle-navigation.lua`, `test-vehicle-journeys.lua`) passed 6/6;
`tools/verify.ps1 -SkipJava` passed 112 Lua sources, 176 scripts, 288 checks,
0 failures; `git diff --check` passed. Native fuel/condition/lock semantics,
real transfer/boarding, convoy seating, and control release remain live-only.

Boarding is now transactional: group boarding commits an explicit per-member
roster (`{member, vehicle}`) attached to the driver run, and every abort or
arrival rolls it back at once — pending leases cancel immediately instead of
waiting out the action timeout, and seated passengers get the existing native
exit (which still refuses a moving vehicle itself). Overflow beyond free seats
stays unleased and unclaimed rather than silently skipped. The same pass closed
a latent traversal hazard: clearing an absent driver-run key during `pairs`
is undefined behavior, so `stopDriver` now only clears a present key.
Focused roster/rollback coverage plus the full gate above pass with no frozen-
boundary changes. Real multi-car driving (a driver run per car), native seat
animation, and convoy spacing remain live future gates.

Duty/order arbitration now reaches vehicle leases: `onDutyChanged` routes an
active boarding lease or live driver run through the existing directive-
interruption owner (lease-free survivors untouched), and every `cancel` settles
the attached roster — except player takeover (`stopDriving`), which preserves
passenger leases so riders stay with the new driver. The same pass hardened
`stopDriver` against clearing an absent run key mid-traversal. Organizer-begin
needed no change: the tick vehicle guard already blocks it while a lease is
active or the survivor rides. Covered by the duty-lease matrix in
`test-companion-commands.lua` and the cancel/takeover matrix in
`test-vehicle-driver.lua` within the same 112/176/288 green gate.

Boarding stays interruptible and abort-stranded riders recover: a busy
boarding lease now yields to retreat-worthy danger (`fleeAssessment`) or a
critical need (`Needs.decide`, same non-`roam` convention as organizer rounds)
through the existing lease owner, rearming threat/think scans for next-tick
arbitration instead of holding the survivor deaf up to the 45s timeout; checks
fail safe on lean native state. An abort-time exit refused by a moving vehicle
marks the rider for a bounded stationary retry in the vehicle tick sweep (new
ownership wins, attempts while moving do not count down, 20-try give-up), so
no passenger sits lease-free with no owner. Covered by the new
`test-vehicle-boarding-urgency.lua` (healthy boarding kept, exhausted boarding
released, rescans armed) and the stranded-recovery matrix in
`test-vehicle-driver.lua` (moving waits, stopped retries). Full gate now
112 Lua sources, 177 scripts, 289 checks, 0 failures; `git diff --check`
passed.

Arrival is deterministic and honest: each roster passenger exits exactly
once with no re-queue on later ticks, the driver stays seated with nothing
queued and no run beneath them, and the feed speaks arrival exactly once;
base-vs-wasteland recognition stays explicitly pending with no lookup
invented. An unrecoverable exit reports one restrained member line instead
of printing forever. Multi-driver orchestration is confirmed out of reach
offline (one driver run per car plus native physics) and stays a Codex+live
design slice.

### Offline correction — roster rollback respects exact vehicle ownership

Source review found `rollbackRoster()` treated a roster member in any vehicle
other than the driver's run vehicle as an unseated passenger and called
`CompanionVehicles.cancel(member)`. A stale roster could therefore clear the
member's newer driver run and reset controls on another vehicle, contrary to
the existing exact-roster ownership rule. Rollback now cancels only a member
who is on foot; it requests native exit only for a passenger still seated in
the exact run vehicle, and leaves a member in another or unknown vehicle
untouched. The existing driver run remains the sole owner of its vehicle
controls and passenger cleanup.

Focused `test-vehicle-driver.lua` reproduces a stale roster entry after the
passenger begins driving another vehicle and verifies the newer run, vehicle,
and controls survive rollback. The connected vehicle set
(`test-vehicle-driver.lua`, `test-npc-vehicle-travel.lua`,
`test-companion-vehicles.lua`, `test-vehicle-ownership.lua`,
`test-vehicle-navigation.lua`, `test-vehicle-journeys.lua`,
`test-vehicle-boarding-urgency.lua`, and
`test-survivor-lifecycle-policy.lua`) passed. `tools/verify.ps1 -SkipJava`
passed with 112 Lua sources, 181 regression scripts, 293 checks, 0 failures;
`git diff --check` passed. Java was not changed. This closes only the offline
roster ownership defect; native boarding/driving, occupied save/reload, and
identity continuity remain live/unimplemented boundaries below. The focused
regression is under the ignored `tools/` policy and remains local, not Git-
tracked evidence.

### Player-follow vehicle transitions — 2026-10-01 offline implementation

Connected the player vehicle transitions through the existing companion vehicle
owner. When the local player enters a stopped vehicle, nearby same-floor members
of the player's Follow roster now try native entry: passenger seats when the
player drives; when the player rides and the driver seat is free, one nearby
follower may try the existing native driver path only if Experimental NPC
Driving is enabled, with passenger boarding as fallback. On player exit, seated
Follow members in that exact vehicle receive the existing native exit action;
queued entry into that same vehicle is cancelled. Held, explicitly directed,
base-duty, distant, and non-party survivors are excluded. The prior vehicle is
remembered only in weak runtime state for the native exit callback.

Follow-up source comparison against Build 42's `ISVehicleMenu.onEnterAux`
confirmed another reason a visually empty seat could be rejected: Knox treated
any locked passenger door as if its seat did not exist, while vanilla queues
native unlock/open/enter/close actions. Companion boarding now follows that
native action sequence, including vanilla key-on-door transfer behavior,
instead of returning `no_free_passenger_seat` solely for a locked door. Focused
fixture coverage verifies the action order; whether the survivor has native
authority to unlock the real door still depends on Build 42 state and remains
live-pending.

Added a per-survivor “Drive Nearest Vehicle” order on foot. It considers only
loaded, same-floor vehicles within 30 tiles, tries nearest first, and delegates
each candidate to the existing opt-in native driver/readiness/route owner. The
existing enter/driver/exit context callbacks now show honest failure reasons
instead of appearing silent. No seats, routes, movement, or membership are
simulated or persisted by this change.

Focused vehicle regressions cover entry role selection, experimental driver
opt-in and passenger fallback, exact-vehicle exit and pending-entry cleanup,
nearest loaded candidate order, and rejected-command feedback. These are offline
fixtures only. The latest available 2026-10-01 DebugLog has no Knox vehicle
command/entry event, so the owner’s earlier “won’t get in” observation remains
reported rather than reproduced; the source gap is the missing player
enter/exit handoff and nearest-car command. Unarmed stomp damage is also still
unconfirmed: that log records combat admission and target changes, but no native
attack/hit receipt. Do not change native damage based on that evidence.

### Remaining live verification
Disposable-save Build 42 acceptance: real vehicle engine off/on, empty fuel,
damaged/non-driveable condition, locked driver door, blocked/occupied seats,
player-near vehicle, towing, and one valid fueled vehicle; driver/passenger
roles; group orders and destination travel; threat interruption; unavailable or
destroyed vehicle; control release; native boarding/exit animations and route
behavior; and group travel/convoy behavior. Save/reload while occupied and
unloaded/rematerialized passengers must explicitly check stable identity,
inventory, orders, group membership, no duplicate bodies, and no lost survivors.
Seat restoration is not currently implemented, so this scenario is an
acceptance/limitation probe rather than a claimed supported restore behavior.
Record native accessor values, admission reasons, route/seat transitions, and
control ownership. Native part consumption remains a separate gate.

## BUG-KS-031 — Automatic base supply claims ended before storage receipt
Status: in_progress
Priority: high
Owner: Codex
Type: behavior
Related: KS-PROD-008, BUG-KS-015

### Confirmed offline defect and correction
An automatic loaded base supply run previously recorded `collected` as its
terminal outcome immediately after pickup. That cleared the durable
`activeSupplyRun` and transient shortage claim before the resident returned and
the assigned typed-storage container confirmed receipt. Another resident could
therefore be elected for the same still-unmet shortage while the first real
item was in transit.

The autonomy owner now records `collected_returning`, persists the
`base_supply_deposit` return intent, and retains the run/claim until the native
inventory cleanup path confirms the item left the resident and reached the
destination. Missing carried items terminate explicitly. Focused election and
inventory-cleanup regressions verify duplicate-run suppression and release
only after receipt. Offline fix verified; native transfer, save/reload, and
container capacity remain live-only under BUG-KS-015/Slice E.

### Validation
2026-09-28: `test-base-auto-scavenge.lua`, `test-base-needs.lua`,
`test-inventory-cleanup.lua`, and `tools/verify.ps1 -SkipJava` passed; 112 Lua
files, 177 regression scripts, 289 checks, 0 failures. `git diff --check`
passed.

## BUG-KS-032 — Gift and money social acts rewarded trust without transfer
Status: todo
Priority: high
Owner: Codex
Type: behavior
Related: KS-PROD-008, D-020

### Symptom
The survivor context menu exposed `Offer Gift` and `Give Money`. Both called
`socialAct`, which increased relationship trust, recorded a meeting, played a
thank-you response, and returned success without checking or transferring a
real player-owned item. Knox has no account/balance owner for abstract money.

### Reproduction
Call `KnoxCompanionService.socialAct(player, survivorId, "offer_gift")` or
`"give_money"` while the survivor is nearby. Before correction, the offline
social-act regression asserted the trust increase with no inventory fixture.

### Evidence and correction
The service's `SOCIAL_ACTS` definitions granted +8/+6 trust; the context menu
advertised each action; `KS_OrderSignals` also mapped both to a thank-you
gesture. Neither path touched inventory. Those social-act definitions and stale
gesture mappings were removed. A distinct `Give Item` entry now opens the
existing Trade UI in gift mode. It requires explicit selection of an eligible
real item, rechecks recipient survival/task reserves, then uses the existing
native transfer journal, capacity check, receipt verification, rollback, and
survivor capture. The existing `gift` contribution rule grants its modest trust
increase only after that transaction verifies. `Give Money` remains removed:
there is no abstract account balance, though real supported currency objects
can be selected as real items. Direct calls to the old social-act names return
`unknown_social_act` before relationship, meeting, speech, or gesture mutation.

### Acceptance
No social-only action may stand in for a gift or money transfer. Gift trust is
awarded only after the selected real item is received and captured. Abstract
money remains unsupported; tangible currency follows the same item receipt
path as any other supported gift.

### Validation
2026-09-28: local ignored `tools/test-social-acts.lua`,
`tools/test-trade-valuation.lua`, `tools/test-trade-action.lua`, and
`tools/test-trade-ui.lua` edits passed (these are not tracked Git evidence).
Coverage includes missing gift selection, same-instance successful delivery,
post-receipt contribution reward, rollback with no reward, and menu/UI routing.
The full `tools/verify.ps1 -SkipJava` gate checked 112 Lua sources and ran 177
regression scripts (289 checks, 0 failed). `git diff --check` passed. These are
offline checks; live Build 42 still needs to confirm native gift/barter transfers,
recipient capacity, action cancellation, and save/reload of the received item.

## BUG-KS-033 — Base-job supply pickup failed to recover entry traversal
Status: todo
Priority: medium
Owner: Codex
Type: traversal
Related: KS-PROD-008

### Confirmed offline defect and correction
After a resident claimed real tools/materials from assigned base storage, an
entry-related native movement failure in `BASE_TASK_SUPPLY_MOVE` immediately
failed the entire task. The same controller already provided bounded
alternate-window and permission-gated door-break recovery for ordinary base
work movement, but this earlier storage leg bypassed it. The route now uses the
existing alternate-entry machinery with the actual assigned container's room
and approach. Quiet entry retains the exact task/item/container lease; a
permitted door break retains that lease until success, then resumes the same
route. If no permitted entry works, the existing task failure path releases
the claim and exact storage reservations. No transfer or work completion is
inferred from traversal success.

### Validation
Local ignored `tools/test-base-task-supply-entry.lua` exercises locked-route
entry, lease-preserving quiet entry, same-route resumption, one real transfer
queue after arrival, permitted door-break resumption, and truthful failure with
reservation release. `test-entry-and-escort.lua`, base-action lifecycle, task
validation, supply arrival, claim suspension and inventory cleanup regressions
also pass. The 2026-09-28 offline gate checked 112 Lua sources and ran 178 Lua
regression scripts (290 checks, 0 failed); Java was skipped. The focused script
is local under ignored `tools/` policy, not tracked Git evidence.

This does not reproduce or resolve every public locked-door report. Build 42
must verify native door/window actions, route continuation to a real container,
item receipt, permission/protection behavior, interruption and save/reload.
Corpse/fence handling remains bounded by existing drop cooldown and task retry
owners in offline coverage, but the reported repeated physical fence behavior
remains live-only and unconfirmed for current development.

## BUG-KS-034 — Base-job completion was reported before task-board acceptance
Status: todo
Priority: high
Owner: Codex
Type: base_jobs
Related: KS-PROD-008

### Confirmed offline defect and correction
Native executors verify their world result before asking the existing task board
to finish the claimed task. If ownership had been revoked or reassigned in the
meantime, the board correctly rejected the stale completion, but the autonomy
controller had already emitted `task_finished_ok`, advanced automatic-work
pacing, and several executor callers announced the job as complete. The
controller now treats the board response as the authoritative task outcome:
only accepted finishes emit task-finished success/failure and update pacing;
rejections emit a distinct failure diagnostic/reason, apply bounded retry delay,
and clear only the stale controller's transient state/reservations. Completion
speech is gated on board acceptance. Already-applied native world effects are
not rolled back or misrepresented as undone, and persistence/task-board ownership
is unchanged.

### Validation
Local ignored `tools/test-base-task-validation.lua` covers accepted automatic
completion/pacing, rejected stale ownership, failure evidence, task and supply
lease cleanup, no false success diagnostic, and no completion announcement.
Connected base-action lifecycle, task-board/persistence ownership, supply,
corpse, repair, farming, woodcutting, and base-work regressions were run with
the full offline verifier. The 2026-09-28 exact-worktree results are recorded
in `WORK_QUEUE.md` and `CURRENT_STATE.md`. Tests are local under the existing
ignored `tools/` policy and are not tracked Git evidence.

Build 42 still needs a real base-job completion while its claim is revoked or
reassigned, including native action result, truthful resident feedback, next
activity arbitration, and save/reload. Ordinary accepted work also needs a live
replay to confirm the native result and task-board lifecycle align.

## BUG-KS-035 — Active base supply runs could outlive their shared claim
Status: todo
Priority: high
Owner: Codex
Type: base_work
Related: KS-PROD-008, BUG-KS-031

### Confirmed offline defect and correction
The shared loaded-world shortage lease expired after 1.5 in-game hours even
when the same resident's persisted `duty.activeSupplyRun` still owned an
unfinished search or return. A different resident could then be elected for
the same shortage, duplicating travel and resource acquisition. The existing
autonomy owner now rehydrates a transient claim from each same-base resident's
valid active run before shortage election, including when the resident is
unloaded or the old transient lease expired. The claim remains ephemeral; the
persisted duty run remains authoritative and clears only through existing
terminal supply-run cleanup. No persistence schema, storage owner, or mission
system changed.

### Validation
Local ignored `tools/test-base-auto-scavenge.lua` advances world time beyond
the lease expiry while the first resident still owns an active run, then proves
the helper cannot start a duplicate and the original durable run remains
unchanged. Connected supply-planner, inventory-cleanup, and base-needs tests
passed. `tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 178
regression scripts (290 checks, 0 failures); `git diff --check` passed. The
focused fixture remains local under the repository's ignored `tools/` policy.
Build 42 still needs a real long-running shortage trip past the lease window,
including unload/reload, native pickup, return, storage receipt and
reassessment.

## BUG-KS-036 — Finalized loaded encounters were absent from survivor memory
Status: todo
Priority: high
Owner: Codex
Type: social
Related: KS-PROD-008, D-021

### Confirmed offline defect and correction
The loaded encounter coordinator committed greetings, declines, hostile
disposition, and group membership, but none of those final outcomes were added
to the existing persistent survivor history. That history already feeds later
dialogue recounts and the Survivor Card, so loaded social life could be real in
relationships yet forgotten by the same survivors. `KS_OffscreenStories` now
appends a bounded `meet` fact to each participant's existing canonical ledger;
it fails closed if that ledger is missing, deduplicates the same participant,
outcome, and world-time entry, and retains the existing 12-entry cap. The
relationship owner records only finalized outcomes: hostile means persisted
hostile disposition (not a successful robbery/fight), joined means a real group
mutation, and incomplete/interrupted encounters are not recorded. Existing
dialogue recounts distinguish joining, parting, and hostility without claiming
an unverified fight.

### Validation
Focused `test-offscreen-stories.lua`, `test-offscreen-recount.lua`,
`test-human-encounters.lua`, `test-relationship-coherence.lua`, and
`test-survivor-view-model.lua` passed.
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 178 regression
scripts (290 checks, 0 failures); `git diff --check` passed. Focused test edits
remain local under ignored `tools/` policy. Build 42 still needs loaded greet,
decline, join/rejection, and hostile encounter replay, followed by save/reload
and later dialogue/Card inspection. No native robbery or combat result is
implied by this history entry.

## BUG-KS-037 — Offscreen meeting intent was consumed before loaded acceptance
Status: todo
Priority: medium
Owner: Codex
Type: persistence/social
Related: KS-PROD-008, D-016, D-021

### Confirmed source boundary and correction
`KS_OffscreenStories` persists a pair-specific `pendingMeet` intent, but
`KS_SurvivorRelationships.observePair()` consumed the two ledgers when it only
selected a forced loaded outcome. A later approach failure, danger/activity
interruption, membership change, or timeout therefore lost the offscreen event
before any loaded encounter result was committed. The coordinator now carries
the matching pair-phase/kind/time token through the runtime encounter and
consumes only after an accepted greet, decline, join/rejected-join result, or
hostile handoff. Transient aborts retain the durable intent. Stale matching
intents expire after the existing 72-hour freshness bound, and pair-scoped
cleanup protects a newer intent for another partner. A failed hostile handoff
retains its intent while the existing short cooldown prevents per-tick retries.
Outcome selection, relationship policy, group ownership, and memory content are
unchanged; no second persistence/history owner was introduced.

### Validation
Focused `test-human-encounters.lua`, `test-offscreen-stories.lua`,
`test-offscreen-recount.lua`, and `test-relationship-coherence.lua` passed.
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 178 regression
scripts (290 checks, 0 failures). `git diff --check` passed after canonical
record updates. Focused test changes remain local under ignored `tools/`
policy. Build 42 still needs an offscreen pending encounter, interrupted loaded
approach, later recontact/finalization, and save/reload replay. No native
movement, robbery transfer, or combat outcome is proven offline.

## BUG-KS-038 — Rejected faction admission could leave a partial group join
Status: resolved_offline
Priority: medium
Owner: Codex
Type: persistence/social
Related: KS-PROD-008, BUG-KS-037

### Confirmed source boundary and correction
`addTravelGroupMember()` previously appended the survivor to the travel group
and allied its relationships before calling the authoritative
`addFactionMember()` owner. It ignored a `false` result, then still reported the
group as accepted. That owner can reject lifecycle-owned identities such as an
event-managed survivor, leaving group membership, faction roster/affiliation,
and the encounter result inconsistent. Faction admission now runs before those
mutations; rejection returns `faction_admission_rejected` and leaves group,
faction, affiliation, and relationship state unchanged. Successful faction
admission remains on the same base-resident notification and formation path.
No second group, faction, or persistence owner was added.

### Validation
Focused `test-faction-persistence.lua`, `test-human-encounters.lua`,
`test-autonomy-formation.lua`, `test-unloaded-groups.lua`,
`test-relationship-coherence.lua`, and `test-faction-development.lua` passed.
`tools/verify.ps1 -SkipJava` checked 112 Lua sources and ran 178 regression
scripts (290 checks, 0 failures); `git diff --check` passed after canonical
record updates. Focused test changes remain local under ignored `tools/`
policy. Build 42 still needs normal accepted recruitment through runtime
formation/base duty and save/reload; the offline rejection case does not prove
native encounter, movement, or persistence behavior.

## BUG-KS-039 — Removing typed storage left mutated native capacity behind
Status: resolved_offline
Priority: medium
Owner: Codex
Type: storage/behavior
Related: KS-PROD-008, BUG-KS-016

### Confirmed source boundary and correction
Assigning any current typed storage called `KS_ToolCupboard.applyInfinite`,
which raises the native container's capacity to its Build 42 limit and records
the assignment in world-object ModData. `Remove Storage` cleared the container
label and canonical base policy but did not restore the capacity or remove that
marker. The previously green storage-menu test only asserted policy/name removal,
and `ToolCupboardCapacity` still advertised a retired single-cupboard workflow.

The existing `KS_ToolCupboard` owner now records the pre-assignment capacity
once per physical container index. It restores that exact observed capacity
and removes the matching assignment marker only after
`removeBaseStoragePolicy` succeeds and no other base policy owns that same
compartment. Independent compartments and overlapping active policies retain
their own limit/restore state. No item is moved/deleted and no persistence-domain
schema or storage owner was added. The old `ToolCupboardCapacity` sandbox option
is labeled compatibility-only for legacy Tool Cupboard records; current typed
storage uses Build 42 native capacity. Legacy typed assignments which predate
the original-capacity snapshot cannot recover a capacity value that was already
overwritten. A known legacy original is reused; otherwise removal leaves the
current capacity unchanged, clears the retired assignment metadata, and reports
that restoration could not be confirmed. No guessed original is written.

The Astra follow-through reproduced two remaining offline failures in the
OpenCode correction: removal lookup reapplied capacity even when persistence
rejected removal, and a silently rejected native setter discarded rollback
metadata as though restoration succeeded. Removal now resolves identity without
mutating capacity/name; restoration requires exact readback and retains rollback
evidence on failure. A recorded capacity belonging to another mod is restored
without clamping it to Knox's assignment ceiling. These are capacity-lifecycle
corrections, not a change to storage categories or transfer ownership.

### Validation and remaining live scope
Focused `test-tool-cupboard.lua`, `test-base-storage-menu.lua`,
`test-base-storage.lua`, `test-base-supply-routing.lua`, and
`test-sandbox-settings.lua` passed, including restoring the original capacity,
preserving a sibling compartment, and retaining contents. The current dirty-tree
`tools/verify.ps1 -SkipJava` gate checked 112 Lua sources, ran 182 regression
scripts, and passed 294 checks with 0 failures; `git diff --check` passed.
Build 42 must still verify real ItemContainer capacity restoration and contents
after assignment/removal, multiple compartments/overlapping policies, and
save/reload. Offline checks do not prove native capacity/weight semantics.

When a live/offline failure is found, add it using this format so ModForge can import it automatically:

## BUG-KS-040 — Companion threat scan throws while checking party-loot eligibility
Status: resolved_offline_live_pending
Priority: high
Owner: Codex
Type: runtime/behavior
Related: KS-PROD-008, BUG-KS-013

### Symptom
The owner reported two Knox Lua errors immediately after loading the staged
Build 42 mod. Companion autonomy logged a recovered `think` exception twice
within the first seconds.

### Reproduction
Load the staged mod in Build 42 with an owned survivor entering settled
companion-follow thinking while `perceivedThreats` is present. The observed run
reported the error at frames 166 and 196.

### Evidence and correction
`C:\Users\Gary\Zomboid\Logs\2026-09-30_02-40_DebugLog.txt` reports
`Object tried to call nil` at
`KS_SurvivorAutonomyController.lua:10957`, from the `next(self.perceivedThreats)`
expression that supplies `threatActive` to party-food-support eligibility. The
controller's reservation cleanup also called `next(owners)`. Both paths now use
one guarded `Controller.hasEntries` helper based on `pairs`, including safe
handling for nil/non-table values. This preserves the same threat and lease
semantics while avoiding the runtime call failure. The exact cause of the
runtime's nil `next` binding is not established; don't claim more than the
observed failing call.

### Acceptance
No controller exception during threat-present settled following or reservation
cleanup. Threats still suppress party scavenging, and last-owner cleanup still
removes the empty threat reservation bucket.

### Validation
Focused `test-autonomy-formation.lua`, generic-loot receipt, looting, companion
loot, base supply routing, group support, and away-team executor checks pass.
`tools/verify.ps1 -SkipJava` passed 112 Lua sources, 183 regression scripts,
295 checks, 0 failures. `deployDev` completed; SHA-256 comparison matched all
122 source mod files in the local game folder and Workshop `Contents`, with no
missing or differing files. The observed Build 42 errors establish a runtime
defect; the fix itself remains live-pending until the same scenario loads
without errors and retains correct threat/lease behavior.

## BUG-KS-041 — Work-preference cell click throws in the Notebook
Status: resolved_offline_live_pending
Priority: high
Owner: Codex
Type: runtime/ui
Related: BUG-KS-013, KS-PROD-004

### Symptom
Clicking a Crew & Schedule work-preference cell throws a Lua exception instead
of saving the selected base resident's work preference.

### Reproduction
In the 2026-09-30 Build 42 log, click a work-preference cell in the Notebook.
At 02:52:29, frame 1875, the stack is
`onCrewPriorityCell(KS_SurvivorNotebook.lua:979)` from vanilla
`ISButton.onMouseUp(ISButton.lua:47)`.

### Evidence and correction
`C:\Users\Gary\Zomboid\Logs\2026-09-30_02-48_DebugLog.txt` records
`Object tried to call nil` at `local any = next(map) ~= nil`. The map is
normalized to a table immediately before this call. The current Build 42 Lua
environment does not provide a callable global `next` on this path; the same
failure class was previously observed in autonomy. The prior callback had a
safe `pairs` loop, which was replaced during the preference-model update. The
callback now checks for any entry with `pairs` and still sends either the
preference map or `nil` reset through the existing CompanionService owner.
Selection, persistence, task ownership, and base arbitration are unchanged.

This confirms a specific UI write failure, not the broader BUG-KS-013 report
that base residents appear inactive. The log does not establish which resident,
base, task, or native action was under test.

### Acceptance
Click each preference state through High, Low, Disabled, and Normal; no Lua
exception occurs, the selected resident/base receives the write, and values
remain correct after closing/reopening the Notebook. Then perform the separate
BUG-KS-013 supplied-job and missing-resource replay.

### Validation
Focused `test-notebook-refresh.lua`, `test-notebook-base-context.lua`, and
`test-work-priorities.lua` passed. The regression executes the real callback
with global `next` unavailable, checks selected identity/base forwarding, and
checks that returning to Normal persists a reset. The full offline gate passed
112 Lua sources, 183 regression scripts, 295 checks, and 0 failures;
`git diff --check` passed. The focused test is under ignored `tools/` policy
and is not tracked Git evidence. Build 42 replay of the corrected callback
remains open.

### 2026-10-01 follow-up — persistence normalizer still used unavailable `next`

The newest `2026-10-01_03-53_DebugLog.txt` records repeated clicks failing at
`normalizeWorkPreferences(KS_Persistence.lua:49)`, called by the preference
setter and then `onCrewPriorityCell`. The earlier callback's `pairs` loop was
already fixed, but the new four-state persistence normalizer independently
called global `next`, which is unavailable in this Build 42 Kahlua path. The
normalizer now records whether it accepted a supported non-Normal entry while
iterating with `pairs`; preference writes no longer call `next`. The focused
work-preference test explicitly removes global `next` around a real persistence
write. Offline-fixed; preference UI save/reopen remains live-pending.
Focused preference, schedule, Notebook, and vehicle tests pass. The full
verifier passed 102 Lua sources, 197 regression scripts, 299 checks, and 0
failures; `git diff --check` passed. `deployDev` completed and all 113
repository mod files match local and Workshop development copies by SHA-256;
the Workshop copy has only its two generated agent files extra. This is staging
parity, not Workshop publication.

## BUG-KS-042 — Base picker loses selected outpost
Status: resolved_offline_live_pending
Priority: high
Owner: Codex
Type: ui/state
Related: BUG-KS-013, BUG-KS-017, BUG-KS-018

### Symptom
Selecting an owned outpost in Base & Work can appear to return to the home
base. Base-scoped area controls could also mutate the primary base while an
outpost was displayed.

### Confirmed offline cause and correction
`KS_SurvivorNotebook.lua` defined `BaseView:prerender` twice. Lua retained the
later method, which only updated Remove Selected enablement and replaced the
earlier picker-commit logic. Consequently, selecting an outpost never wrote its
ID to the Notebook window; the existing safe resolver then correctly fell back
to the oldest owned base. The duplicate was removed and both responsibilities
now live in one method. Edit Boundary, Add Area, and Remove Selected now resolve
through `BaseView:selectedBase`, keeping those actions on the same validated
owned base as the picker. Persistence, base identity, and ownership rules are
unchanged.

### Validation and remaining acceptance
The local ignored regression `tools/test-notebook-base-context.lua` executes
the real picker callback with two bases and verifies selecting Outpost 2 commits
its ID and refreshes views once. It also executes the three area callbacks and
asserts they target the selected outpost. Focused Notebook refresh and Base UI
checks passed; the full offline verifier and `git diff --check` results are
recorded in the current work item. The regression is under ignored `tools/`
policy and is not tracked by Git. Build 42 still needs to confirm rendered
dropdown behavior, visible view switching, editing/removing outpost areas,
closing/reopening the Notebook, and save/reload. This fix does not implement
base naming or change BUG-KS-017/018 territory geometry reports.

`deployDev` completed after verification. SHA-256 comparison matched all 122
source payload files against both the local development mod and Workshop
`Contents` (0 missing, 0 different); this is staging only, not publication.

## BUG-KS-043 — Cold unpowered stove remains eligible for cooking
Status: resolved_offline_live_pending
Priority: medium
Owner: Codex
Type: behavior
Related: BUG-KS-013, KS-PROD-008

### Report
A survivor may repeatedly try to cook after appliance power is lost; one
community example describes broccoli queued in an oven after power loss. This
specific report is not yet reproduced live.

### Confirmed source defect and correction
`KS_BaseCooking.usable` correctly rejects an unpowered microwave and accepts a
powered stove or a non-microwave stove with positive current temperature, but
then returned `true` for every remaining stove. A cold, unpowered appliance
could therefore pass discovery, resolution, action validation, and execution
gates despite no supported evidence that it could heat. The final fallback now
rejects the appliance. Existing powered and positive-temperature cases remain
eligible. No fuel model, retry owner, or cooking scheduler was added.

### Validation and remaining acceptance
`tools/test-base-cooking.lua` now exercises the real task-discovery predicate
for cold/unpowered, powered, and already-hot non-microwave stoves while keeping
microwave cases. Focused cooking, base-job, task-board, and base-duty checks
passed. The test is local under ignored `tools/` policy and is not tracked Git
evidence. Native fuel-backed stove semantics and actual heating remain
unverified. Build 42 replay must verify a powered oven/stove, power loss during
selection and before action start, positive residual heat, any valid fuel-backed
appliance, bounded failure/claim cleanup, and save/reload without a false
cooking result. Do not claim the community broccoli report was reproduced.
`deployDev` completed after the fix. SHA-256 comparison matched all 122 source
payload files against both local and Workshop `Contents` copies, with no
missing or different files; no Workshop upload or Build 42 test occurred.

## BUG-KS-044 — Base & Work content exceeds constrained tab height
Status: resolved_offline_live_pending
Priority: medium
Owner: Codex
Type: ui/layout
Related: BUG-KS-013, KS-PROD-004

### Report
Base work/storage lists and lower controls may overflow their Notebook area on
short or split-screen viewports. The owner also reports schedule controls and
hour selection are difficult to read; that separate visual clarity report is
not resolved by this layout correction.

### Confirmed offline geometry and correction
`BaseView:createChildren()` used a fixed vertical stack ending at the hint row,
whose measured content bottom is `self.hintLabel:getBottom() +
UI_BORDER_SPACING` (520px at the current 14px Small font). The Notebook clamps
its overall window to viewport height, leaving a shorter Base & Work tab on
short screens, but the view had no outer scroll extent. The three data lists
already have their own bounded `ISScrollingListBox` viewports; their contents
were not shown to escape those boxes. BaseView now reports its final content
extent to the existing `KS_SurvivorUILayout` adapter, which supplies bounded
vertical scrolling and resize fitting. Control placement, list ownership, and
base/task behavior are unchanged.

### Validation and remaining acceptance
The local ignored `tools/test-notebook-layout.lua` checks the measured hint
extent, adapter binding after tab ownership, each list's bounded viewport,
scroll reachability at a constrained height, tab stencil, and resize refit.
Focused Notebook/Base UI/Card layout tests passed. The full offline verifier
passed 112 Lua sources, 184 regression scripts, 296 checks, and 0 failures;
`git diff --check` passed. The test is ignored under repository `tools/` policy
and is not tracked Git evidence.
Build 42 still needs short/split-screen and enlarged-font visual replay, wheel
and joypad navigation to lower controls, and schedule hour/color clarity.
`deployDev` succeeded after verification. SHA-256 comparison matched all 122
source payload files against local and Workshop `Contents` (0 missing, 0
different); this is staging only, not publication or live acceptance.

### 2026-10-01 nested list wheel follow-up
The owner reported Task Queue and Storage scrolling through their sibling
sections despite each `ISScrollingListBox` having a bounded viewport. The
sections. The owner's screenshot after the first staged attempt showed that
the rows themselves visibly escaped the Work Areas box and overlapped controls;
wheel forwarding was not the root cause. Build 42's installed
`ISScrollingListBox:doDrawItem` skips rows outside its viewport before drawing.
Knox's six custom Notebook row callbacks replaced that function but omitted its
visibility guard, so offscreen rows were drawn. A shared guard now mirrors the
native cull condition in all six callbacks while preserving each row's normal
next-Y return. The prior parent wheel change remains limited to avoiding a
second forwarded event. Focused layout regressions check top/bottom/scroll
culling and coverage across all custom callbacks. Build 42 must confirm rows
remain within each box while scrolling Work Areas, Tasks, Storage, Crew,
Missions, and World. The regression is local-only under ignored `tools/` policy.

## BUG-KS-045 — Player conversations cannot continue and retain first-contact tone
Status: fixed_offline_live_pending
Priority: medium
Owner: OpenCode
Type: social/behavior
Related: KS-PROD-008 Slice G

### Report
The owner reports that player-survivor interactions feel like they stop after
one attempt and repeatedly tell the player the survivor needs more time, making
conversation feel unavailable or static.

### Confirmed source boundary
`Controller:beginPlayerConversation()` admits only idle/travel/companion/base
states. After the first accepted conversation it sets `PLAYER_CONVERSATION`, but
does not accept a repeated request from the same player to continue or refresh
that attention lease. `CompanionService.talk()` then reports the survivor as
busy. Separately, a saved `warm_up` social disposition selects
`player_warm_up` on every Talk action even after the existing relationship
ledger has recorded enough meetings to satisfy the current warm-up meeting
threshold. The `player_talk` dialogue bank is therefore never used for that
relationship unless another system changes its disposition.

### Expected
The same player may continue a safe, nearby conversation by refreshing its
existing short attention lease; it must still yield immediately to danger,
urgent needs, a new player directive, distance/floor changes, vehicles, and
active native work. A guarded first-contact response should progress to ordinary
personality-aware dialogue after the existing familiarity threshold, without
automatically recruiting the survivor or changing their persisted disposition.

### Current correction
The same player may refresh the existing `PLAYER_CONVERSATION` attention lease
after range, visibility, danger, vehicle, native-action, and ownership guards
pass. Another player still cannot take over. A persisted `warm_up` response
uses the first-contact dialogue while the existing meeting/recruitment-attempt
threshold is unmet, then moves to the ordinary personality-aware `player_talk`
bank. The persistent disposition and recruitment gate are unchanged.

The new `KS_SurvivorInteractionUI` adds a lower-center prompt using the current
Build 42 Interact binding (E by default) and a compact player-scoped window with
the nearby survivor's live 3D model, name, and Friendly/Neutral/Mean/Hostile
action tabs. Talk, needs, social acts, Trade/Give Item and Recruit route through
their existing owners. Repeated Talk/social actions leave the panel available
for follow-up; recruitment and real trade actions keep their existing
eligibility/receipt checks.

### Acceptance
- A first Talk uses guarded first-contact dialogue; after the recorded
  familiarity threshold, later Talk uses the ordinary player-talk bank.
- Repeated Talk/social actions from the same player remain available while the
  active conversation is safe and nearby; another player cannot take its lease.
- Existing danger/needs/action interruption and recruitment trust rules remain
  authoritative.
- The compact interaction UI uses existing service, relationship, trade, and
  recruitment methods; its Friendly/Neutral/Mean/Hostile group labels do not
  invent transfer, combat, or relationship outcomes.

### Validation
Focused `test-social-interaction-ui.lua` (now also covering prompt naming/key,
own-panel hover exclusion, and foreign-window suppression),
`test-player-conversation.lua`, `test-player-reputation.lua`,
`test-player-social.lua`, `test-social-acts.lua`, `test-survivor-dialogue.lua`,
and `test-order-menu-callbacks.lua` passed. The current `tools/verify.ps1
-SkipJava` run checked 113 Lua sources and 188 regression scripts (301 checks,
0 failures) on 2026-09-30. An earlier dirty-tree run had one
`test-base-naming.lua` failure; the focused naming regression now passes and
the current full verifier also passes, so that result is not a reproduced
source defect. Focused scripts under `tools/` are ignored/local and are not
Git-tracked evidence.
`git diff --check` passed for the changed files.

Build 42 must still verify lower-center prompt placement, Interact-key behavior
alongside ordinary world interaction, the rendered survivor model, category
and button readability at small/large UI scales, repeated conversation,
dialogue progression, and danger/need/directive interruption and resumption.

<!--
## Example template — not a bug record
Status: todo
Priority: critical
Owner: OpenCode
Type: bug

### Symptom
What visibly fails.

### Reproduction
Exact steps/build/save/setup.

### Evidence
Log line, failing test, screenshot reference, or source boundary.

### Expected
What should happen.

### Acceptance
Observable fix criteria.

### Validation
Focused regression plus required live test.
-->

## BUG-KS-046 — Unknown fluid taint state was treated as clean water
Status: offline_fixed_live_pending
Priority: high
Owner: Codex / Luna
Type: needs/safety

### Symptom

A fluid container could be admitted as clean drinking water when the taint-marker
inspection threw or returned an unsupported value. This was a fail-open path in
`KS_SurvivorNeeds.waterState`: it defaulted `tainted` to false and only changed
that value when `fluid:contains(Fluid.TaintedWater)` succeeded.

### Evidence

The installed vanilla `ISDrinkFromBottle.lua` uses
`fluidContainer:contains(Fluid.TaintedWater)` and applies poison/sickness effects
when the marker is present. The Knox predicate therefore cannot safely call an
uninspectable fluid clean. This is a source-confirmed offline safety defect; no
runtime error or native consumption was reproduced.

### Correction

`waterState` now rejects the candidate when the taint enum/tag is missing, the
native accessor throws, or its result is not a boolean. Known clean water remains
eligible. Known tainted water retains the existing emergency policy at critical
thirst; unknown water is never admitted, even at that threshold. Needs, storage,
looting, group support, and autonomy continue to use this shared classifier; no
new water inventory or resource owner was added.

### Validation

`test-survivor-needs.lua` covers failed/missing taint inspection, choosing known
clean water over unknown water, refusing an all-unknown supply at critical
thirst, and preserving the known-tainted critical fallback. The exact-worktree
full Lua gate and live replay are recorded in `CURRENT_STATE.md` and
`WORK_QUEUE.md`. The regression lives under ignored `tools/` policy and is
local-only evidence. The owner's latest Build 42 test did not complete the
clean/tainted/unknown matrix. Therefore BUG-KS-046's source correction remains
offline-fixed, while native water compatibility and consequences remain
provisionally unconfirmed/live-pending, not passed.

KS-PROD-008 Slice K also reuses this fail-closed policy for loaded native
water objects. Direct drinking is restricted to player-owned base and
faction/base residents inside their current base/camp boundary, uses vanilla
`ISTakeWaterAction`, and verifies actual thirst plus source depletion. Focused
offline evidence passes; native taint/sickness, depletion, full-inventory,
pathing, contention, and reload acceptance remain open. This does not upgrade
BUG-KS-046 to live-verified.

### Live acceptance

On a disposable Build 42 save, compare a known clean water bottle, known tainted
water, and a custom/unsupported fluid container. Verify normal thirst selects
only known clean water, critical thirst may use known tainted water through the
native drink action, and an uninspectable item is deferred/reported as
unavailable rather than consumed. Confirm real thirst reduction and native
sickness/poison consequences; save/reload with a partially consumed bottle.

## BUG-KS-047 — Nearby survivor interaction window failed during portrait setup
Status: offline_fixed_live_pending
Priority: high
Owner: Codex / Luna
Type: UI/runtime

### Symptom and evidence

The 2026-09-30 17:05 Build 42 log contains 21 stack entries for
`attempted index: setState of non-table: null`. The stack runs from vanilla
`ISUI3DModel:setState` to `KS_SurvivorInteractionUI.lua:292`, then through
`InteractionUI.open` and `onContextKey`. The interaction window therefore
failed before it could open, matching the report that the prompt key did not
work.

### Correction

The portrait is now added as a child before calls backed by its native
`UI3DModel` object. In Build 42, `ISUIElement:addChild` instantiates that child;
`ISUI3DModel:setState` dereferences the native object. No error is swallowed.
The same window also registers a configurable Knox keybinding named
`Talk to Nearby Survivor`, default F, and displays the resolved binding. The
existing native `OnContextKey` path remains available for Project Zomboid and
controller compatibility; Knox does not globally rebind vanilla Interact.
The minimal translucent prompt now explicitly reads `Press [key] to talk to
[survivor]` using the resolved binding and a stronger readable font. It
continues to pass mouse input through and the existing modal,
vehicle, aiming, visibility, and range gates remain authoritative.

### Validation and live acceptance

Focused `test-social-interaction-ui.lua` models native-child readiness, custom F
binding/label, mismatched-key rejection, modal/dead/vehicle/aiming/no-target
gating, mouse pass-through, and native context compatibility. The full offline
result and exact remaining input/render acceptance are in `CURRENT_STATE.md`,
`WORK_QUEUE.md`, and `DEVELOPMENT_TESTING.md`. Build 42 must confirm the panel
opens without the exception, F and remapped bindings work, native
Interact/controller behavior remains available, and ordinary world mouse/input
behavior is unaffected.

## BUG-KS-048 — Schedule hour cells had no continuous paint gesture
Status: offline_fixed_live_pending
Priority: medium
Owner: Codex / Luna
Type: UI

### Symptom and evidence

The Crew & Schedule hour cells already stored the selected tool on click and
assigned an `SCHEDULE_COLORS` background value, but there was no mouse stroke
state or hover path to paint multiple hours by dragging. This source gap
matches the new report. Whether Build 42 visibly renders the assigned cell
colors correctly remains a native UI presentation question.

### Correction

The existing Notebook cell controls now start a stroke on left mouse-down,
paint only hovered hour cells for the captured resident and tool, and end on
release (including release outside the cell) or scroll. No pointer capture is
taken. Click and joypad activation still paint one cell through the same draft
and persistence path. Save serialization, base-resident eligibility, selected
resident, selected base, and current-hour marker are unchanged.

The owner then reported that no painted color appeared and the yellow current
hour outline remained around hour 12. Installed Build 42 `ISButton` source
shows its assigned background color is drawn only when `button.background` is
true; the Notebook set `backgroundColor` but left this flag unset for hour and
preference cells. Both control families now enable their native button
background and keep the selected fill color during hover. The yellow border and
star deliberately continue to indicate the current real-world hour; painting
changes the cell fill independently.

### Validation and live acceptance

`test-notebook-schedule-clarity.lua` covers one-cell paint, drag across cells,
repaint with another tool, resident-target stability, release/scroll stop,
color projection, save/reload, defaults, narrow wrapping and base-resident
scope. The controls still need Build 42 pointer/render, zoom/UI-scale, joypad,
scrolling, and save/reopen acceptance; offline button fields do not prove
native rendering. The regression also asserts that both schedule-hour and
preference cells enable the installed vanilla button's background renderer and
retain their semantic fill on hover. The full verifier passed 102 Lua files,
197 scripts, 299 checks, and 0 failures; `git diff --check` passed. Build 42
visual and input acceptance remains open.

## BUG-KS-049 — Activity Feed could not be hidden and suppressed history when disabled
Status: offline_fixed_live_pending
Priority: medium
Owner: Codex / Luna
Type: UI/state presentation

### Evidence

The current `KS_ActivityFeed.hide()` set the window visible and raised it, while
`toggle()` always called `show()`. The close button was disabled, and
`addLine()` returned before recording whenever the display Sandbox option was
off. This made the advertised visibility control ineffective and coupled
presentation to event retention.

### Correction and validation

The existing feed window now exposes its close affordance, which hides the
window without clearing its seven-line buffer. The existing party context-menu
entry reports Show/Hide and toggles the same owner. Hidden or Sandbox-disabled
presentation continues recording the bounded recent feed; the Sandbox option
still controls whether the feed can be displayed. `tools/test-activity-feed.lua`
covers close/toggle/reopen, hidden and disabled event retention, bounded history,
and game-start reset. Focused and full offline results are in `CURRENT_STATE.md`
and `WORK_QUEUE.md`. Build 42 close-button rendering, input pass-through,
context-menu usability, and visible event behavior remain live-pending.

## BUG-KS-050 — Knox radial orders ignored radial visibility and global enable settings
Status: offline_fixed_live_pending
Priority: medium
Owner: Codex / Luna
Type: settings/UI

### Evidence and correction

The vanilla emote radial wrapper and stale Knox submenu callbacks could show
Knox orders without checking the master Sandbox switch. There was no dedicated
radial visibility setting; `OrderGestures` controls acknowledgement animations,
not menu visibility. The new `ShowRadialOrders` Sandbox option defaults on,
which preserves behavior for old saves. The radial owner now checks that
setting and the master enable gate at both root insertion and submenu refill;
when disabled, stale callbacks restore the vanilla radial. Classic right-click
orders remain independently governed by `ShowLegacyContextCommands`.

Focused radial/settings regressions prove hidden Knox slices, preserved vanilla
actions, stale-callback handling, default-on old-save behavior, and independent
classic context commands. The full offline result is in `CURRENT_STATE.md` and
`WORK_QUEUE.md`. Build 42 radial visibility and mouse/joypad behavior remain
live-pending. No legacy key was removed, renamed, or migrated destructively.

## BUG-KS-051 — Closing the interaction window left its attention lease active
Status: offline_fixed_live_pending
Priority: medium
Owner: Codex / Luna
Type: interaction/autonomy cleanup

### Evidence and correction

Talk and social actions set the interaction window's `attentionStarted` state
after the existing runtime conversation lease was admitted. Closing the window
removed only the UI; the runtime lease then persisted until ordinary timeout or
another interruption. `InteractionUI.close()` now releases that exact
survivor/player lease through `KnoxSurvivorRuntime.endPlayerConversation()`
when this window started it. Trade keeps its existing separate begin/release
owner. No movement owner or interaction system was added, and distance/range
rules are unchanged.

`test-social-interaction-ui.lua` verifies the release uses the exact survivor
and player and that the panel can reopen. Connected interaction and trade tests
pass offline. Build 42 must confirm that an attentive survivor stays nearby
while the window is open, resumes ordinary arbitration on close, and still
interrupts for danger, urgent needs, native actions, and out-of-range movement.

## BUG-KS-052 — Automated QA cleanup lacked run-scoped ownership
Status: offline_fixed_live_pending
Priority: high
Owner: Codex / Luna
Type: QA harness safety

### Evidence and correction

The active QA coordinator removed `ks-dev-*` fixtures using only the developer
ID prefix and kept the run-to-fixture association in transient memory. A reload
could lose that association, so the harness could not safely distinguish a
current fixture from a stale one. The dormant full coordinator also had a
40-tile helper that removed every loaded zombie, and its job matrix could add
zones to an existing base without restoring them. The full coordinator is now
hard-quarantined and the ordinary-world cleanup helper is inert.

The opt-in smoke slice now uses a structured manifest and one coordinator.
Canonical persistence tags automated fixtures with a run ID and owner token;
cleanup requires both values to match, verifies the native body is absent, and
retains ownership on any uncertain failure. A later run can reconcile only
persistently tagged prior-run survivor fixtures. Unknown or ordinary identities
are never deleted. The report distinguishes `TIMEOUT` and `CLEANUP_ERROR` from
`HARNESS_ERROR`, preserves dependencies and human-required labels, and continues
independent scenarios. Base work, melee, firearms, group/faction continuity, and
save/reload are catalogued but remain human-required until their fixture
creation and rollback contracts are implemented.

The follow-up base-task adapter pass (KS-PROD-011, 2026-09-30) confirmed that
the legacy setup can reuse and mutate the player's real base. A read-only
`QA-BASE-ADAPTER-001` gate now reports `BLOCKED` with the missing rollback
owners; no base, zone, task, item, or resident is created. This is an unsafe
QA fixture boundary, not evidence of a gameplay bug. Keep the real base task
scenario `QA-BASE-001` human-required until an exact disposable-base rollback
contract and a removable/restorable native work-target fixture are available.

Offline follow-up checks on 2026-09-30 passed the fail-closed adapter gate,
base task board, real-material eligibility, task action lifecycle and cleanup,
retry/supply-entry, and report parsing. Current full offline counts are 115 Lua
sources, 192 regression scripts, 307 checks, 0 failures. No Build 42 base task
was created or executed.

The next KS-PROD-011 follow-up removed the unconditional
`save_is_disposable=true` assertion and added a one-run save identity gate.
Known unprefixed save names classify as `ORDINARY_SAVE`; a `KSQA-` name without
the explicit run declaration is `UNKNOWN_SAVE`; unreadable identity and stale
or mismatched run/save declarations have distinct blocked classifications.
Only scenarios requiring world mutation depend on an approved gate; read-only
readiness and the base rollback preflight continue. Save identity changes
invalidate the run and abort cleanup rather than targeting the newly loaded
world. This is a QA safety correction, not a gameplay defect, and does not
prove a save is disposable or provide save creation/discard. Human save setup
and restoration remain external and live-pending. Do not repeat the earlier
base-task rollback preflight; its `QA-BASE-001` disposition remains `BLOCKED`.

Focused QA, save-isolation, coordinator, base-task gate, task lifecycle, and
parser regressions passed. `tools/` tests are ignored by Git policy and provide
local-only evidence. Current exact-worktree `tools/verify.ps1 -SkipJava` passed
116 Lua sources, 194 regression scripts, 310 checks, 0 failures;
`git diff --check` passed. Java, Build 42, staging, and Workshop upload were
not run. Disposable-save creation/discard, reload re-arming, native fixture
materialization/removal, and the Developer Tools workflow remain live/manual
acceptance. Do not enable the quarantined full coordinator.

### KS-PROD-011 manual arming/read-only follow-up — 2026-09-30

This is QA safety work, not a new gameplay bug. Developer Tools now displays
the exact current save identity and status, offers one-run confirmation only
in Developer Mode, and keeps run start separate. Approval is identity/run
sequence bound and expires on start attempt, completion, menu/reload, identity
change, or coordinator error. Read-only survivor, base/task/duty, and
group/faction snapshots are active on ordinary saves; map projection is
excluded because the current query may initialize player persistence. The
parser records arm/consume/expiry metadata.

Focused Developer Tools, snapshots, isolation, coordinator, manifest,
automated-QA, and PowerShell 7 parser tests passed. Exact full offline result:
116 Lua sources, 196 regression scripts, 312 checks, 0 failures; `git diff
--check` passed. Tests under ignored `tools/` are local-only evidence. No live
Build 42 run occurred. The owner must verify menu visibility/input, exact-save
confirmation, separate start, and report correlation on an externally
prepared disposable save. Save creation/discard remains external and
`QA-BASE-001` remains blocked by its independent rollback gap.

The 2026-09-30 Build 42.21 debug log adds a KS-PROD-011 QA harness follow-up,
not a new gameplay bug: its START line has legacy `save_is_disposable=true`
metadata and the loaded local/Workshop QA coordinator was not the current
repository version. `KS_SurvivorAutonomy.lua` produced a Kahlua local-index
error (`Index 200 out of bounds for length 200`); the later missing
`KnoxAutonomyController.new` caused `QA-ENCOUNTER-001` to report
`HARNESS_ERROR` and recruitment to be skipped. The current manual-arm flow was
not exercised. Classification: stale staged payload/debug-loader uncertainty.
Refresh staging before the next debug run; do not use the legacy destructive
path on an ordinary save. Current source and debug-loader behavior remain
unverified in Build 42.

### BUG-KS-053 — Debug-mode Kahlua local limit blocks autonomy controller
Status: offline_fixed_live_pending
Priority: high
Owner: Codex / Luna; Human for Build 42 confirmation
Type: bug

The 2026-09-30 Build 42.21 log loaded Knox from
`C:\Users\Gary\Zomboid\Workshop\KnoxSurvivors\Contents\mods\KnoxSurvivors\42`.
At 22:40:09 the Kahlua compiler threw `ArrayIndexOutOfBoundsException: Index
200 out of bounds for length 200` during Lua loading. Later,
`KnoxAutonomyController.new` was nil at `KS_SurvivorAutonomy.lua:309`, causing
repeated registration failures and `QA-ENCOUNTER-001` to end `HARNESS_ERROR`;
recruitment was skipped. The log's QA START also used legacy
`save_is_disposable=true`, proving it was not the current QA coordinator.

The source controller then had exactly 200 top-level `local` declarations; it
contained an unused `approachSector` helper and was the only client Lua source
at that count. Removing that dead helper leaves 199. A local regression guards
the controller below Kahlua's 200-local ceiling. This is a source-correlated
fix, not proof that the debug loader now succeeds. The updated source was
staged to both the local mod folder and the exact Workshop development path
shown in the log; source files match by SHA-256. The two intentional Workshop
runtime JAR/checksum files were retained. No public Workshop upload occurred.

Offline focused autonomy/QA checks and the full verifier pass; Build 42.21
restart, controller registration, QA status metadata, and encounter cleanup
remain pending. Do not use the legacy destructive QA payload on an ordinary
save. First confirm the new log loads the current QA START protocol and has no
Kahlua exception.

### BUG-KS-053 retest update — Kahlua headroom expanded

The next Build 42.21 log (`2026-09-30_23-18_DebugLog.txt`) confirms the game
used the Workshop development root and the current QA manifest v2. It still
threw the Kahlua 200-local overflow after the first reduction to 199, so that
attempt was insufficient. The run recorded `saveIdentity=unavailable` and
correctly blocked `QA-ENCOUNTER-001`; this identity issue is separate from the
Lua compilation failure and is not caused by the save's display name in the
observed evidence.

The autonomy controller now stores ten rarely used tuning constants on its
existing `Controller.TUNING` table instead of module locals, reducing its
module-scope local count to 189. The test now requires at most 190, leaving
headroom under Kahlua's limit. Focused autonomy/QA tests and the full verifier
passed 116 Lua files, 197 regression scripts, 313 checks, 0 failures. The
updated source is staged in both local and active Workshop development paths;
all 127 repository payload files match by hash, with only the Workshop Java
agent JAR and checksum retained as extra runtime files. Fresh Debug Mode
confirmation remains required.

### BUG-KS-053 retest update — newest log predates the 153-local source

The newest available log, `2026-09-30_23-49_DebugLog.txt`, records the active
Workshop root at 23:49:12. Its controller file was staged at 23:42 and had 189
module locals. At 23:49:22 Kahlua again threw `Index 200 out of bounds for
length 200`; the controller then failed to register (`new of non-table: null`
at `KS_SurvivorAutonomy.lua:309`). This is the same startup failure, not a
save-name failure. The QA run separately reported `saveIdentity=unavailable`,
which blocked destructive scenarios and does not cause Lua compilation errors.

The repository controller was subsequently reduced to 153 module-scope local
declarations by moving 36 tuning values onto its existing `Controller.TUNING`
table. A local budget regression now caps this module at 160. Focused autonomy,
formation, roaming, base-duty, combat-scenario, and companion-command checks
passed; `tools/verify.ps1 -SkipJava` passed 116 Lua sources, 197 regression
scripts, 313 checks, 0 failures; `git diff --check` passed. The updated 127-file
source payload is now staged identically in the local mod and active Workshop
development folders by SHA-256. Only the existing Workshop Java-agent JAR and
checksum remain as intentional extras. This newest source has not yet been
loaded by Build 42; controller registration remains live-pending. Run one new
debug launch and inspect only its fresh first error/START section before QA.
Tool-based regressions are local-only because `tools/` is ignored by Git.


### BUG-KS-053 retest update — 2026-10-01 fresh Debug Mode failure and correction

The owner supplied a fresh screenshot/debug run at 00:25. The log reports two
`ArrayIndexOutOfBoundsException: Index 200 out of bounds for length 200` failures
in Kahlua `LexState.new_localvar`, followed by `attempted index: new of
non-table: null` at `KS_SurvivorAutonomy.lua:309`. The screenshot shows the same
constructor registration line. This run loaded the active Workshop source, and its
controller SHA-256 matched the current repository, local-mod, and Workshop files.
Therefore the previous module-scope-local reduction was insufficient; the error
is not stale staging and is unrelated to the save label. The independent QA save
identity warning does not explain Lua compilation failure.

Source inspection found `Controller:tick` had 231 local declarations in the
Build 42/Kahlua debug compilation path; the existing base native-action dispatch,
receipt, and completion block was a coherent 511-line section. It now runs through
`Controller:updateBaseTaskAction`, returning a handled signal to the existing
`tick` arbiter. Standard Lua reports 163 locals for `tick`; the existing
base-action lifecycle regression exercises dispatch, waiting, receipts, failures,
interruption, and timeout through the delegation. Focused checks, full offline
verification, and syntax validation pass. This is a source correction, not proof
of Kahlua or controller registration in Build 42. Stage the updated controller
and make one fresh Debug Mode launch; check that the compiler exception and
line-309 nil-constructor error are both absent. QA destructive scenarios remain
blocked until save identity is available and explicitly armed.


### BUG-KS-053 — owner confirmation after staged tick split (2026-10-01)

**Startup error status: live-confirmed absent on the owner's fresh restart.**
After the `Controller:tick` split was staged, the owner restarted Build 42 and
reported that the errors were gone. This confirms the reported Kahlua index-200
exception and consequent `KnoxAutonomyController.new` nil error no longer appear
in that startup. Scope is limited to this replay; QA save identity/arming and
encounter gameplay remain unverified and are not marked complete.

### BUG-KS-054 — Sandbox options parser rejects section comments (2026-10-01)

**Status:** confirmed source/configuration defect; fixed offline and restaged; Build 42 Sandbox-menu retest pending.

The owner's report that Knox Survivors had no Sandbox options is confirmed by `C:\Users\Gary\Zomboid\console.txt` from the latest launch. Build 42 loaded the active Workshop development root, then `CustomSandboxOptions.readFile` failed with `unknown block type "--"` at `CustomSandboxOptions.parse`. The reorganized `sandbox-options.txt` contained seven Lua-style `--` section comments, which this parser does not accept. Removed only those comment lines; option declarations and page IDs remain unchanged. Added a regression that rejects comment lines in the Sandbox definition.

**Next:** restart Build 42 and open the Knox Survivors Sandbox section. Confirm all seven pages/options load without a `CustomSandboxOptions` parse exception. This is not live-confirmed until that replay passes.


### BUG-KS-030 — passenger approach pace follow-up (2026-10-01)

The owner reported that following survivors approached vehicles too slowly.
Boarding now temporarily requests native `setRunning(true)` during the existing
vehicle-seat path action and restores the previous running state when boarding
completes or is cancelled/abandoned. Sprint and endurance behavior are
unchanged. Focused offline tests cover the native flag and restoration; jog
animation/speed in Build 42 remains unverified.

### BUG-KS-048 — current-hour marker source correction (2026-10-01)

The owner observed the yellow current-hour marker stuck at 12 while Build 42 time was 17:00. The duty schedule conversion already round-trips every hour through its canonical persistence writer. The confirmed UI defect was that the marker preferred `KnoxNightShelter.currentHour()`, whose fallback is noon. It now reads Build 42 `getGameTime():getTimeOfDay()` first, supports `GameTime.getInstance()` as fallback, and omits the marker if time is unavailable. Focused regression covers 17:45 despite the old helper returning 12, singleton fallback, and unavailable clock. Actual rendering, explicit save, and reopen behavior remain live-pending.

Follow-up from owner retest: the painted assignment still did not retain its cell color. Build 42 `ISButton:setEnable()` restores `backgroundColorEnabled`, a snapshot captured before later color changes. The Notebook previously updated only `backgroundColor`/hover color, so later refresh restored the stale snapshot. A shared Notebook helper now synchronizes the visible, hover, and enabled-cache colors for schedule hours, schedule tools, and base-work preference cells before enable/disable refresh. Regression simulates the native cache restore and confirms repaint survives it. This is offline-fixed; actual visual rendering and save/reopen remain Build 42 pending.

### 2026-10-01 owner follow-up — prompt visibility and action eligibility

The owner reports F interaction appears inconsistently and requests text-only prompt rendering plus removal of invalid actions. Source confirms two prompt inconsistencies: proximity visibility checked `survivor:CanSee(player)` while the interaction contract is player-facing, and update() displayed the affordance while aiming even though the F/native-key admission rejected aiming. The visibility gate now uses `player:CanSee(survivor)` and the prompt hides during aiming, matching the key gate. The prompt now draws only the resolved key and talk text; panel fill, border, and keycap graphics are removed, while mouse-event capture remains disabled.

The Neutral category previously left Trade, Give Item, and Recruit buttons visible-but-disabled for player companions and other ineligible affiliations. These actions now appear only for independent, ungrouped, non-faction survivors; trade/gift remain single-player only. Talk and needs remain available through their existing owners. Regression covers player-facing visibility despite survivor-facing occlusion, aiming consistency, no prompt rectangles/borders, and independent/player/faction/group action lists. Native rendered input/UI behavior remains Build 42 live-pending.

### BUG-KS-055 — Starting spouse identity repeated and successor could receive a duplicate

**Status:** confirmed offline defect; fixed offline; fresh-save and player-death Build 42 replay pending.

`KS_SpouseStart` reserved `ks-spouse-<playerId>` for every fresh save. `KS_Persistence` derives a new survivor's default personality and stable traits from that ID, so the same first player slot reused the same personality seed across worlds. Separately, player succession converted existing companions—including the spouse—to base residents but did not mark the successor as inheriting the household; the fresh-character spouse starter could therefore create another spouse when enabled.

New spouse reservations now use a one-time `ZombRand` identity suffix, persisted before activation. Existing pending/complete spouse IDs are preserved for old saves and retries. Successful succession marks the new character's spouse start as `skipped_succession`; the existing spouse remains in the inherited household. Focused `test-spouse-start.lua` covers distinct identity/personality seeds across fresh saves, stable reservation, legacy pending IDs, succession without a second spouse, and spouse continuity as a base resident. Full offline verification is recorded in the implementation follow-up. Build 42 must still verify fresh-save variation, save/reload stability, and both player-death continuation settings.

### BUG-KS-056 — Build 42 storage controls call unavailable Kahlua `next`
Status: fixed_offline_live_pending
Priority: high
Owner: Codex
Type: ui/persistence

The 2026-10-01 09:02 DebugLog records a user click failing at
`clearInfinite(KS_ToolCupboard.lua:199)` with `Object tried to call nil`.
That line called global `next`, which is unavailable in this Build 42 Kahlua
path. Source review found the same hazard in storage-filter save, filter menu
clear/toggle, and the remaining capacity cleanup checks. Those checks now use
`pairs`-based entry detection; no storage records, survivor identities, or save
state were reset. Focused storage tests explicitly run with global `next=nil`.

This confirms the storage/filter click failure and its runtime exception. It
does not explain the reported missing squad/residents: the same log says the
world population ledger remains `48/48`, with one survivor restored, 46 outside
the activation band, and one virtual survivor waiting on its square. It contains
no identity list for the player's squad/base residents and no population
activation failure. Keep that disappearance report open pending a log that
includes those IDs; do not reset or rewrite the save.

Offline-fixed; restage and retest filter save/clear plus survivor identity
continuity in Build 42. Focused checks: `test-base-storage-menu.lua`,
`test-base-storage-filter-ui.lua`, `test-tool-cupboard.lua`, and
`test-companion-base-domain.lua`. Full verifier and live retest status are in
WORK_QUEUE.md. Tests under ignored `tools/` are local-only evidence.

### BUG-KS-057 — Faction residents' scheduled sleep used ambient sitting

**Status:** confirmed source defect; fixed offline; Build 42 sleep replay pending.

Faction-base residents whose duty schedule selected `sleep` were routed to
`beginAmbientBaseRest`, which selects an ambient rest posture instead of the
shared native sleep/assigned-bed recovery path. The correction routes only
faction-owned bases through `beginRecovery("sleep")`; player-owned base
schedule behavior is unchanged. Independent survivors, traveling groups,
camps, and unloaded survivors already use shared needs/sleep handling; no
universal night scheduler was added.

Focused evidence: `test-faction-scheduled-sleep.lua` confirms faction schedule
uses the native sleep recovery owner and player-owned base schedule retains its
prior path. `test-survivor-needs.lua`, assigned-bed, faction-bed, camp, group,
night-shelter, and unloaded-survival regressions also pass. Native bed selection,
movement, sleep animation, interruption, and reload still require Build 42.

### BUG-KS-058 — Failed hibernation removal strands the live controller

**Status:** fixed_offline_live_pending
**Priority:** high
**Owner:** Codex / Luna; Human for Build 42 acceptance

When `bridge:removeNpc(id)` refused to remove a body after its real state had
been captured and `markStored` committed, the hibernation path captured again
and set the still-registered controller to `STOPPED`. `activeIds` continued to
exclude the survivor from unloaded advancement, while the main loop skipped its
controller. The survivor therefore had a native body and an `active` lifecycle
label but no ordinary autonomy or offscreen progression. This was a confirmed
source defect; the available 2026-10-01 09:45 log did not reproduce it.

The remove-failure branch now rolls the stored ledger back to `loaded` before
resuming the existing controller at `IDLE`. The same ID, controller, and native
shell are retained; no spawn, restore, replacement identity, or native result
is fabricated. If rollback or controller resumption fails, a runtime-only
recovery-pending entry retries ledger reconciliation without repeating
shutdown/removal. A confirmed absent body completes the already-committed
hibernation and unregisters that shell. Save/menu boundaries retry pending
rollback and log the result.

Focused regressions: `test-hibernate-rollback-recovery.lua`,
`test-survivor-lifecycle-policy.lua`, `test-unloaded-survival.lua`,
`test-world-presence.lua`, `test-away-teams.lua`, `test-unloaded-groups.lua`,
`test-unloaded-base-return.lua`, `test-virtual-base-return-transaction.lua`,
`test-persistence-recovery.lua`, and `test-ai-priority-stability.lua`.
`tools/` tests are ignored by Git and provide local-only evidence. Build 42
remove refusal, same-body identity, menu/save recovery, rematerialization,
same-person inventory/order/group/faction continuity, and duplicate-body
acceptance remain unverified.

### BUG-KS-059 — Missing native body remained excluded from survivor activation

**Status:** offline same-ID follow fallback implemented; Build 42 rematerialization still pending.
**Priority:** high. **Owner:** Luna; human owns live acceptance.

Owner observation: a player-owned survivor appeared on the map near the player,
but no body appeared. Switching the survivor from resident to party changed the
saved duty to `companion` / `waiting_for_leader`, yet the survivor still did not
appear. This visible behavior is valid evidence; map coordinates alone do not
prove a native body exists.

Source review found that normal activation excludes every ID still in the
autonomy `activeIds` list. If the bridge had already lost a body's native
character while its controller/runtime registration remained, the ID was
permanently filtered out of the restore candidate scan. `recallToParty` updated
the canonical duty but did not repair that stale active projection. Before
candidate selection, autonomy now releases only ordinary active registrations
for which the bridge explicitly confirms the body is absent. It preserves the
canonical ID/record/duty, does not capture or spawn a replacement, leaves valid
detach/hibernate transitions alone, and requeues a base task claim if applicable.
The existing population owner then attempts its normal same-ID restoration.

Focused local-only regression: `tools/test-stale-active-body-recovery.lua`.
Build 42 must still confirm that this identity appears after reload/recall,
retains inventory/orders/group/faction state, and has exactly one native body.

**2026-10-01 save-load follow-up:** the newest run is `playtest01` and the
Workshop development payload is byte-identical to source for autonomy,
population, persistence, and companion service. `global_mod_data.bin` still
contains canonical `ks-world-4` identity Stacy Byrd, player affiliation,
Follow duty, native record, and a hibernated/sleeping logical state. The
11:08 DebugLog records restoration only for unrelated `ks-dev-1`; population
summary reports one virtual survivor waiting, but the existing aggregate did
not identify it. This is evidence her identity was not deleted and that she
had no confirmed body restoration in that load. Source review found virtual
rematerialization required a hidden safe square even for an owned companion.
That can keep a nearby hibernated companion stored. Owned player companions
now may rematerialize at their real safe logical square even when visible;
independent population still requires hidden placement. A keyed deferred
reason is now logged for any owned companion that remains ineligible. Focused
coverage is in `test-world-population.lua`; Build 42 must still prove Stacy
appears with one body and retained state.

**2026-10-01 live retest:** `2026-10-01_11-32_DebugLog.txt` loads the Workshop
development root and names the failed identity: `activation-deferred
id=ks-world-4 reason=virtual_square_not_loaded_or_visible` at startup and
frames 301 through 2401. No Knox Lua exception or sleep rejection appears.
The latest `playtest01` save still contains Stacy's canonical `ks-world-4`
record, player owner `player-1`, explicit Follow order, and hibernated
`sleeping` ledger at x=1468,y=7310,z=1. Build 42 uses z=0 for ground level and
z=1 for the level above it. The failure occurs before record relocation or
body creation because no safe loaded square is found around that saved
same-floor position; the log does not distinguish an unloaded floor from
loaded but blocked squares.

**2026-10-01 offline correction:** after the saved virtual square search fails,
an owned player companion with an explicit Follow order may restore the same
canonical survivor on the nearest safe loaded square within four tiles of its
owning player, on that player's current floor. The existing native record
relocator and population activation remain authoritative; the logical position
is updated only after record relocation succeeds. Hold, base residents, and
independent survivors do not use this fallback. Focused regression covers a
sleeping follower on an unavailable floor, owner matching, same-ID record and
ledger update, and no fallback for Hold. Build 42 must confirm one real body,
no duplicate, and retained identity, inventory, sleep/recovery state, and
Follow order. Base-resident recovery to a safe assigned-base tile is a separate
not-yet-implemented slice. Focused lifecycle/persistence/population tests pass;
`tools/verify.ps1 -SkipJava` passed 103 Lua sources, 203 regression scripts,
306 checks, zero failures. `deployDev` succeeded and all 114 repository mod
files match the local and Workshop development copies by SHA-256. This is
staging only; no Steam upload or Build 42 retest has occurred.

### BUG-KS-060 — Native storage-filter list clicks ignored wrapped row data

**Status:** offline interaction path corrected; owner reports the filter UI/checkmarks still were not apparent; Build 42 retest required.
**Priority:** high. **Owner:** Luna; human owns live UI acceptance.

The filter editor populated native `ISScrollingListBox` rows as `{ text, item =
{ key } }`; Build 42's callback passes `row.item`, not the full row. The handler
now accepts the actual native payload and direct callers. A later owner report
said the editor still was not apparent and checkmarks did not visibly update.
Source tracing found the filter action was nested under the broader Knox
Survivors world-object submenu, contrary to the requested right-click → Set
Filters flow. It is now placed directly on the world-object context menu for
single-container objects; multi-compartment objects expose a direct
**Set Container Filters** submenu. Selected rows now use a filled green state
and a plain `X` glyph instead of depending on Unicode check-mark font support.
These are offline source/UI-contract fixes; rendering and input remain unproven
until Build 42 retest. Independent categories remain multi-select; General
retains its exclusive/all-items meaning.

`tools/test-base-storage-filter-ui.lua` now uses the exact payload observed in
Build 42's `ISScrollingListBox:invokeOnMouseDownFunction`, checks selected and
unselected draw output, toggles multiple categories, and saves native
DisplayCategory values. `tools/test-base-storage-menu.lua` verifies Set Filters
is on the top-level world-object context menu. Tests under `tools/` are
ignored/local-only. Build 42 must confirm the window opens, visible checks
respond, multiple categories persist after close/reopen, and old assignments
still load.

### BUG-KS-061 — Radial hid party orders when all companions were offscreen

**Status:** fixed offline; Build 42 radial visibility/input acceptance pending.
**Priority:** normal. **Owner:** Luna; human owns live UI acceptance.

The emote radial's Knox root and Party Orders tab were gated on a nearby loaded
follower body. A valid durable player-party roster with all members stored or
offscreen therefore had no Knox order entry. Party-wide orders already target
the persisted player roster, so the entry now remains visible when that roster
exists. Individual follower commands remain limited to nearby loaded bodies;
no remote per-survivor command or second order owner was added.

`tools/test-radial-orders.lua` covers offscreen-roster root visibility and
party-wide order access while confirming individual Followers are omitted.
Build 42 must confirm the vanilla emote radial opens, the Knox entry is visible,
and party-wide commands still reach eligible stored survivors through existing
order arbitration.

### BUG-KS-062 — Kahlua event validation calls unavailable global `next`

**Status:** fixed offline; staged replay pending. **Priority:** critical.
**Owner:** Luna.

The newest `2026-10-01_10-55_DebugLog.txt` contains 334 repeated Lua failures
from 10:56:23 through 10:59:04: `Object tried to call nil in emptyList`. The
stack is `KS_KnoxEvents.emptyList` → event validation/maintenance →
`KS_EventRuntime.update` → `KS_SurvivorAutonomy.update`. This is a confirmed
Knox/Kahlua compatibility defect, not a save-name issue. Event validation and
corrupt undeployed-record recovery called global `next`, which this Build 42
Kahlua runtime does not expose. Both checks now use `pairs` iteration, without
changing event policy or inventing outcomes.

`tools/test-knox-events.lua` runs both empty-roster validation and malformed
undeployed recovery with global `next` set to nil. The test is local-only under
the ignored `tools/` policy. The sleeping label is separate: the view model
shows `Sleeping` when the unloaded survival record is in its sleep phase; the
party order remains `Following`. Current available logs do not correlate a
specific survivor's fatigue/state to the owner's selected row, so that label is
not changed speculatively. Confirm the same survivor's order/activity after
staging; native restoration and in-game status presentation remain live checks.
