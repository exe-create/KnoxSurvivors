# Development testing

## In-game testing

There is no in-game Automated QA menu or automatic QA run. The prior save
arming flow was retired because it was confusing and did not help ordinary
playtesting. Existing saves may retain an `AutomatedQAMode` SandboxVars value;
the option is no longer registered and Knox no longer reads it.

For gameplay checks, launch Build 42 normally with Knox Survivors enabled and
follow one short replay from the active bug/work item. Record what you expected
and what the survivor actually did. Offline checks do not prove native movement,
actions, combat, rendering, inventory, or save/reload behavior. Existing manual
Developer Tools (spawn, combat scenarios, and diagnostics) are separate from the
retired QA runner and remain available when enabled.

## Offline verification

Run the focused `tools/test-*.lua` regression for the changed subsystem, then:

```powershell
./tools/verify.ps1 -SkipJava
git diff --check
```

The QA manifest/coordinator/save-isolation/parser code is retained only for
existing offline harness regressions; it is not required or loaded by gameplay.
Tests under `tools/` are ignored by Git policy and provide local-only evidence.

## Archived in-game QA harness evidence (not active)

### Stale Developer QA payload — 2026-09-30

The latest available debug log (`Zomboid/Logs/2026-09-30_21-40_DebugLog.txt`,
events through 22:07) ran Build 42.21 with the older QA protocol: its START line
contains `save_is_disposable=true` and lacks `saveIdentitySource` and
`manifestVersion`. Hash comparison showed the loaded local/Workshop QA file did
not match the current repository version. That run reported a Kahlua
`Index 200 out of bounds for length 200` load error, then
`KnoxAutonomyController.new` was unavailable during `QA-ENCOUNTER-001`;
encounter ended `HARNESS_ERROR`, recruitment was skipped, and later controller
registration errors repeated. Do not count that run as a test of the current
manual arming path. The current source and located staged Lua files compiled
with the installed Build 42 Kahlua compiler outside the game's debug loader;
that does not reproduce or clear a debug-mode issue. Refresh local staging
before the next launch and capture a new log. Do not run the legacy
`save_is_disposable=true` QA path on an ordinary save.

These local tests validate manifest shape, dependency blocking, exception and
timeout status handling, run IDs, ownership refusal, partial fixture registry,
ordinary-world safety, the no-mutation base fixture gate, and report parsing.
The existing base-task board, material requirement, claim cleanup, retry, and
native-action lifecycle regressions remain the offline task-owner evidence;
they do not enable a live QA fixture. `tools/` tests are ignored by Git
policy and therefore are local-only evidence unless separately staged by the
owner. None of these tests proves Project Zomboid native behavior.

For a symptom outside that automated slice, use Developer Tools > Diagnostics >
**Write Survivor Status to Log** while the relevant survivor is loaded. The
existing status line reports current controller context; immediately after it,
the command prints up to twelve recent failures from the centralized autonomy
failure path, oldest first. Each `recent_failure` line includes survivor ID,
game tick, normalized reason, controller state, active decision, retry deadline,
and position when available. This is a transient controller ring: it is not
saved, does not poll every tick, and clears when the controller unloads. It
does not capture failures that bypass `recordFailure`; use their owning
diagnostic/reproduction path. The ring is evidence for diagnosis, not a second
state owner or proof of native behavior.

Build 42 acceptance for this diagnostic should use a loaded survivor after a
native recoverable movement failure: invoke the status command, confirm the
failure row matches the visible controller state/retry, then unload/reload and
confirm the session ring is empty while persistent survivor state remains
unchanged. This verifies only the diagnostic integration; it does not accept
the underlying movement behavior.

## Barricade route regression - 2026-09-19

Assign one resident to barricade an accessible unbarricaded window. Confirm the
resident walks to the usable side adjacent to the opening instead of targeting
the window's own tile. The log should reach `base_task_barricade` without
`base_task_move:FailedStuck`, then the native action should add exactly one
plank. Repeat while another worker or the player changes that opening during
the trip; the old task should stop with a specific stale-target reason and must
not barricade a different object that took the old object index.

## Base work and faction expeditions - 2026-09-19

1. On a backed-up save, enable Ignore Job Tool and Resource Requirements. Give
   an empty-handed resident barricade work with no assigned storage. Verify a
   real hammer/plank/nails, native action, increased plank count, and resumed
   duty. Repeat with a full typed store and disabled farming/wood areas: no bulk
   kit of logs should be added to the worker or store automatically.
2. Enable a farming or wood area and verify native work, inventory quantities,
   and carry load. Disable the free-resource option: no further items should
   be supplied automatically, and existing real inventory must survive reload.
3. Observe an NPC faction with at least three loaded residents. An idle automatic
   pair should keep its formation across relationship updates, loot real world
   containers, return, and deposit. Assign guard duty mid-trip; the expedition
   must release that member. Repeat with death and streaming unload/reload.
4. With six residents, verify two guard and two patrol areas without duplicates
   after reconciliation/reload. A new farm plot must be centered on diggable
   terrain. A house with enough dry containers but no fridge should get food
   storage. Existing player/faction storage assignments must remain intact.
5. Let a faction scavenging pair search a building with no useful remaining
   containers. Confirm the leader returns toward the faction home instead of
   switching into random roaming. At the return buffer or lease end, confirm
   the pair dissolves cleanly and carried surplus follows the existing base
   deposit path.


## Autonomous leader order gesture replay - 2026-09-14

Create a loaded autonomous group with a leader and nearby followers. Let the
leader acquire or change a shared objective such as scavenging or investigating.
Confirm the leader gives a relevant gesture and nearby followers acknowledge
without interrupting movement, combat, or jobs. Repeat while one follower is
busy, far away, or on another floor; gestures should be suppressed or skipped
while the durable group objective continues normally.

## Bounded NPC leader-order replay - 2026-09-27

Use a disposable Build 42 save with one ordinary loaded travel-group leader and
two followers. Observe ordinary travel and a regroup route. For developer-assisted
delivery testing only, resolve the observed leader's group with
`KnoxPersistence.getTravelGroupFor(observedLeaderId)` and issue an explicit hold
with `KnoxPersistence.issueTravelGroupLeaderOrder(group.id, group.leaderId,
'hold', getGameTime():getWorldAgeHours())`; clear it with
`KnoxPersistence.clearTravelGroupLeaderOrder(group.id, group.leaderId)`. If that
console path is unavailable, record this replay as developer-assisted/blocked;
do not add a QA UI or claim an automatic hold policy.

Repeat while a follower has a fence or door transition pending and while a need
or combat decision owns it. Confirm delivery does not create duplicate route
requests, traversal/timed actions complete naturally, and any later responsive
cancellation occurs only after existing priority arbitration. Check failed
cancellation retry and 15-game-minute expiry. Reload before expiry should retain
the same valid directive/revision; expiry or cancellation should restore ordinary
formation. A newly successful leader roam/regroup route may supersede an injected
hold with follow: record that revision change rather than calling it a failed hold.
Record leader/follower IDs, order/revision/deadline, controller state, and the
relevant movement evidence for each step. This is live acceptance only; offline fixtures do not prove native
route, action, or cancellation behavior.

## Player companion shared destination — Build 42 acceptance

Use a disposable save with at least two player-owned companions. Right-click
loaded standable ground and choose **Knox Survivors → Orders for This Location
→ Move Party Here**. Confirm the activity feed reports the number of eligible
companions and each eligible survivor begins through its own controller. Only
companions in primary Follow duty with no individual directive participate;
Hold, Relax, Guard, base duty, and other explicit individual commands remain
authoritative. A newly recruited companion after selection must not inherit the
active destination.

Interrupt one destination route with combat/threat, urgent hunger/thirst or
injury, a native door/fence traversal, and recovery. Verify those owners retain
the body and that the same destination resumes through the existing controller
after each temporary interruption. Issue an individual order during party travel
and verify only that companion leaves the shared command. Issue a new party
movement/order and verify it supersedes the destination. Use **Knox Survivors →
Orders → Cancel Party Destination** and verify all remaining shared routes are
released through normal controller arbitration.

Arrival tolerance is same-floor within 1.5 tiles of the selected square. Verify
the feed reports completion only after every still-eligible participant is
physically inside tolerance; a successful route result outside tolerance is not
arrival. The intent expires after one in-game hour. Invalid/non-standable or
missing selected ground must be rejected. Dismissal, death or reassignment
removes that participant; if none remain, the order clears. The player remains
the party authority and existing Follow anchor. No companion route leader is
elected, so NPC-style leader succession is not part of this slice.

The active destination is runtime-only and must be absent after save/reload; it
must not be described as restored. Offline regressions exercise validation,
dispatch, arbitration, expiry, roster pruning and session reset only. They do
not prove rendered UI, native pathing, physical arrival, interruption timing or
save/reload behavior in Build 42.

## Firearm stabilization — Build 42 acceptance (BUG-KS-029)

Disposable save, one recruited survivor carrying a usable melee weapon, a pistol,
a compatible magazine, and compatible loose rounds. Set the survivor's weapon
preference to **Prefer Ranged**, then produce a real hostile encounter.

Record, before and after each step, the exact weapon full type and item id, the
magazine/chamber/loose-round counts, the native aiming/reload/attack state, the
target identity/health/floor, and the controller state/decision:

1. survivor acquires the target and equips the exact carried pistol;
2. native reload/rack completes once (no repeated queue requests);
3. the native attack hook fires and the engine plays sound/animation;
4. real ammunition decreases by the native amount and no ammo is fabricated;
5. zombie health/damage changes through native ballistics;
6. target death clears target, attack, reload, and reservation ownership;
7. a second target is acquired without stale state;
8. exhausting compatible ammo falls back to the carried melee weapon once;
9. a point-blank threat falls back to melee without a reload loop;
10. a blocked ranged approach falls back to melee without a loop and stays
    eligible (no false unreachable-target cooldown);
11. combat interruption by urgent needs, traversal, a vehicle, or a new order
    resumes afterward without a stale attack/reload action;
12. changing weapon preference mid-combat and mid-reload cancels the native
    preparation once and preserves Follow/Hold/Guard;
13. save/reload preserves the persisted preference and truthful weapon/ammo state;
14. party formation and an active Move Party Here destination resume after combat.

Also keep the existing one-zombie and small-group native combat acceptance debt
from `BUG-KS-009`/`BUG-KS-012`, and the hostile `firearm_duel` plus
allied/neutral bystander safety check. Offline hook telemetry is not proof of a
shot, damage, or ammo change; only native observation counts.

## Player-party cohesion / formation — Build 42 acceptance

Use a disposable save with at least three recruited player companions. Keep two
on Follow and assign one Hold; only the Follow pair should participate. Right-
click **Move Party Here**, then walk at ordinary speed, run, sprint, turn in
place, make a sharp turn, and stop. Verify the player remains the anchor,
individual identities retain stable slots across direction and roster changes,
companions spread outdoors rather than stack, and route requests do not churn on
stationary facing changes. Recruit and dismiss members during travel; later
recruits must not join the active destination snapshot, and remaining slot
owners must not reshuffle.

Repeat beside a narrow door, open/closed doorway, fence, window, stairs, corner
and a crowded passage. Verify a blocked preferred slot compresses to a distinct
nearby standable square; only the companion entering traversal owns its native
action; other followers do not request the same tile; those who have crossed
wait/regroup without oscillating; post-landing slot evaluation resumes promptly.
Introduce one blocked route and a severe separation: confirm bounded retry,
walk/run/sprint catch-up, no teleportation or route spam, and movement failure
streak reset after a real successful recovery.

Interrupt followers with combat/retreat, urgent food/water/medical needs, a
native timed action, Hold/Guard or another individual directive, vehicle
boarding, unload/detach, and dismissal/death. Each higher owner must retain
control; invalid members release their transient slot leases; eligible companions
reacquire player-relative formation through normal controller arbitration.
Make the player climb/vault, enter a moving vehicle, briefly lose a loaded
square, then recover. The player remains anchor; any last-position fallback is
brief, loaded and standable, with no companion promotion or persistent leader.

During **Move Party Here**, verify each Follow-eligible participant stages at a
distinct tile within the existing 1.5-tile final area when available. Arrived
companions wait loosely while others route. Cancellation, a superseding order,
Hold/individual directive, expiry, death/dismissal, and player death must release
only the appropriate transient reservations and preserve D-025 membership and
completion rules. A native route success outside the selected point's tolerance
must not count as arrival. Save/reload must intentionally clear the
session-scoped destination and formation slots; this package does not add
persistence.

Offline regressions prove deterministic projection, target leases, arbitration
and cleanup only. They do not establish Build 42 pathfinding, native traversal,
animations, real arrival, or rendered activity/status behavior.

## Loaded group membership-removal refresh — 2026-09-29

In a disposable Build 42 save, load a three-member travel group and let all
three controllers complete one formation projection. Remove or kill the leader
while the relationship coordinator is inside its normal 60-tick assignment
interval. On the next coordinator tick, verify the canonical successor is
projected as leader, the remaining follower targets that successor with the
correct slot/member list, and the removed survivor no longer owns group
formation. Observe native route handling separately: this change refreshes
controller projections but deliberately does not cancel or issue movement.
Confirm danger, needs, current traversal, and timed actions retain arbitration;
then save/reload and verify identity, membership, successor, and follower
behavior remain coherent. Offline coverage proves only the transient refresh
handoff and controller projection, not Build 42 movement or persistence.

## Deferred base-task resume replay - 2026-09-14

Give a resident a claimed base job, interrupt it with danger or a failed supply
transfer, and confirm the resident enters a visible waiting state instead of
repeatedly reselecting the same task. Stock the required material or clear the
danger and confirm the original task resumes at its scheduled retry.

## Ambient base-position replay - 2026-09-14

Leave two residents without jobs in the same base and allow both to choose an
ambient walk. They should select different available tiles and avoid crowding
the same destination. Confirm the reservation clears after arrival, movement
failure, interruption by danger, and save or shutdown cleanup.

## Corpse-carrier threat replay - 2026-09-14

Assign a corpse-haul job and confirm the resident completes native pickup before
moving while dragging. Place one zombie several tiles away and confirm the
resident continues the route without attacking it. Place a real zombie close to
the carrier: the resident should release the corpse, flee or defend against the
immediate threat, and retain the haul task for later resumption. Confirm the
carrier never enters the visible pickup, swing, loot, and pickup loop.

## Autonomous retreat Sandbox option — Build 42 acceptance

Use a disposable save and compare `Allow Autonomous Survivor Retreat` enabled
and disabled. For each setting, exercise an independent survivor, a base
resident, a faction resident, and an autonomous group member. Present one
zombie and then an overwhelming group with a real viable escape route. Enabled
should retain the existing bounded admission policy; disabled should prevent a
new autonomous retreat without disabling threat detection, combat, or ordinary
group movement. Direct player companions must continue to obey Follow/Hold and
must not begin autonomous retreat under either setting. Interrupt a real base
task and supply run with retreat while enabled, then verify task/claim and
delivery resumption, and save/reload during recovery. Offline tests do not
prove native combat, movement, escape-lane selection, formation cohesion, or
save/reload behavior.

## Blocked base-job supply replay - 2026-09-14

Assign a repair, construction, farming, or woodwork job while its required tool
or material is absent from the assigned central cupboard. The resident should
remain associated with the base job, wait at the settlement, and explain that
the cupboard needs stocking. They must not leave on a generic supply search or
pull an unrelated item from another building. Stock the missing requirement and
confirm the same claimed job resumes through the normal storage transfer path.

## Formation route stability replay - 2026-09-14

Have a leader walk slowly through doorways and around corners with several
followers. Confirm followers keep moving toward their committed formation slots
without reversing or changing direction every few frames. A small leader step or
pace change should preserve the route; a meaningful slot shift, floor change or
blocked route should trigger one bounded refresh. Repeat in a crowded building and
around a base entrance, then verify followers do not pile onto the leader.


## Repair supply replay - 2026-09-14

Damage a repairable door or structure while the worker has empty hands. Put the
required tools and parts in the assigned central storage and confirm the worker
collects them before native repair begins. Include an empty/depleted tool, a usable
duplicate, and optional repair parts; the usable combination should be selected.

Remove the target or make it structurally invalid during the supply trip. The
repair must stop safely. After delivery, verify native equipment, tool use, part
consumption and health change. A stored item must never be treated as already
carried, and a same-sprite object must never be substituted for a stale target.


## Structural crew replay - 2026-09-14

Give equipped repairers/builders several damaged structures, unfinished perimeter
edges and unbarricaded openings. Claim or block the first target and verify other
workers select another available site. Mix repair, construction and barricading
near one tile: only one structural task should occupy that tile at a time. Remove
a claimed repair object and leave another with the same sprite nearby/on the tile;
the old task must fail safely instead of repairing a substituted object.

Verify actual native repair health changes, barricade material consumption and
built perimeter stages. Repeat with empty hands and the required repair tools and
parts in the assigned central cupboard; the worker must wait at the base when a
requirement is absent instead of launching a world supply search. Live mixed-crew
path/action acceptance remains pending.


## Corpse and woodwork crew replay - 2026-09-14

Place two bodies on one tile and assign two haulers. Confirm they select different
bodies. Add a second corpse disposal area: bodies already inside either enabled
area must stay there. Designate a body's square as disposal while a worker is on
the way and confirm the old pickup stops. Disable that area and verify cleanup
can resume. Repeat with a blocked or claimed body and another available body.

Assign two woodworkers with multiple trees and log-processing areas. Confirm a
busy/retrying tree or processing area does not hide other available work, and
that native chopping/crafting still produces actual logs/planks. Watch for route
conflicts and inspect actual corpse grab/drag/drop animations in a disposable save.


## Multi-garden and animal work replay - 2026-09-14

Assign two farmers and two animal carers. Put empty plots in the first garden and
ripe/dry crops in later gardens; place feed needs before a separate thirsty trough
area. Verify maintenance wins over expansion, each resident selects a distinct
available target, and a failed/claimed target does not idle the rest of the crew.
After retry expiry, verify failed work is attempted again. Include a manually
prioritized task and confirm its priority is preserved.

Watch a crop through watering and rain: workers should refill to a safe reserve,
leave healthy crops alone and respect the native maximum where present. Give two
equally useful targets at different distances and check preference for nearby
same-floor work; blocked routes still use the ordinary job recovery. This replay
is pending and remains necessary despite passing offline selection checks.


## Base supplies and action ownership replay - 2026-09-13

Use an empty-handed resident with an animal-care area and real feed/water in
assigned storage. Confirm the worker collects the supply, reaches the trough and
changes its contents. Include an empty bottle of the same type alongside a full
one. Block every adjacent trough tile: the worker should defer rather than target
the occupied trough tile. Replace/remove a trough while a job is claimed and check
that the old job cannot act on a different object.

Put seeds, water and a digging tool in the worker's backpack. Confirm an unpack
precedes the native farm action. Include dead crops and two seed varieties: dead
crops must not receive watering jobs, and claimed planting must retain its selected
crop. Give a different order, introduce a threat, or unload/reload during a transfer,
turn-to-start, corpse pickup or work action. Old queued work must be cancelled;
temporary danger must retain the job claim for a fresh attempt afterward. These
are still live acceptance checks; mocked queues cannot prove native animations.


## Turn-aware driving replay - 2026-09-13

Enable experimental NPC driving in a disposable test save. From a passenger seat,
order a companion to drive to loaded open ground ahead, around a bend, behind the
car and around a parked obstruction. Confirm continuous steering, clearance for
the whole body, and braking near the destination. Repeat with a long vehicle and
one with offset body/collision parts. A destination without room for the nose must
be rejected or approached safely, never marked clear using only the centreline.

Block the route for about 14 seconds, then clear it: the same order should resume
without a no-progress cancellation. Cancel before the NPC reaches the driver seat:
the vehicle's controls must remain untouched. Cancel after driving, injure the NPC,
change driver, or attach a trailer: verify control release and player takeover.
Compare normal/poor tires and brakes, turns beside walls, downhill approaches and
newly moving pedestrians. Offline diagnostic journeys use simplified independent
dynamics and do not replace these native-physics checks.

### Base downtime replay - 2026-09-12

Use the matching updated agent. Leave several idle residents in a large base with
rooms, an upper floor and a yard. Confirm short walks, no immediate doorway ping-pong,
no pileups at occupied destinations, and indoor destinations after dark. A blocked
route should settle into an idle retry rather than escaping the base boundary.
Place a suitable book in assigned storage: watch collection, native reading and
return. Give Follow during the transfer/read/return, then restore base duty; the
physical book must remain accounted for. Turn off Base Reading during a read and
confirm the book is returned without starting another read. These checks also apply
to autonomous faction residents at their own base.

## Permanent guard/patrol replay - 2026-09-12

Use the matching newly staged mod and Java agent; this adds the area-routing bridge.

1. Give a companion Patrol Area, and assign a resident to a patrol work area. Watch
   several circuits: real stops and observation pauses should repeat without clearing
   the order. Include a narrow two-tile area and a larger irregular obstacle layout.
2. Block one corner, barricade a route, and stream out a destination. The survivor
   should try another in-area position or keep watch with a blocked-route status.
   Three failures must not erase Guard/Patrol. Clear the obstruction and verify retry.
3. Choose an area where the engine would prefer an outside shortcut or another
   floor. Verify that shortcut is rejected; the NPC must not tour the neighborhood
   to complete a patrol. Check both entry from outside and normal in-area movement.
4. Interrupt through thirst, hunger, combat and Follow. Needs/danger should preserve
   duties for resumption; Follow releases the companion order. Disable a base work
   area to release its resident, including while they are waiting on a blocked route.
5. Leave a guard and a partly completed patrol unloaded for more than four game
   hours, then return/save/reload. The original claims, last guard positions and real
   patrol progress should remain; needs and elapsed watch time still advance.
6. Shove/displace a guard outside the area. Verify movement stops safely, then a
   normal approach can bring them back. Test a new Move/Follow order to the same
   endpoint to catch a stale area restriction. Read the status log for failure and
   attempted destination when a route cannot resume.

Offline regressions use native API doubles and captured route data; they do not
prove game pathfinding or door/stair animation behavior in these layouts.

## Cooking and outdoor work replay - 2026-09-12

1. In a disposable powered base, assign Main Supplies and optionally a fridge as
   Food & Drink storage. Put raw fish or another nonmetal ingredient inside. The
   Developer Job Supplies option now includes raw fish. Keep a microwave empty.
2. Assign a resident **Cooking** or leave Automatic jobs enabled. Watch physical
   collection, native microwave operation/cooking, and delivery. Check real food
   state and inventories; only saying "Cooking" is not acceptance.
3. Test a hungry resident with raw ingredients and no ready meal. They should cook
   locally, then actually eat. Existing ready meals should take precedence.
4. Interrupt with Follow, thirst, danger and save/reload during cooking. Check the
   same ingredient remains and the microwave shuts off. Move the resident away:
   its native timer must expire within two game minutes without remote toggling.
5. Remove power, clear a storage assignment, fill the fridge/cupboard, take the
   ingredient yourself, or occupy the appliance before the cook arrives. Verify
   bounded failure/recovery, no duplicated food and no stolen player cooking.
6. Place a Cooking area outside the home and repeat. Also complete consecutive tree
   or crop jobs in an outside work area: residents should select the next job there.
   Disabling the area should remove that permission, without bypassing materials.

Ovens, BBQs, campfires and recipe preparation are not enabled by this executor.
`tools/test-base-cooking.lua` uses native API doubles, not simulated proof of actual
heat/animations. Long accelerated-time and real appliance acceptance remain pending.

## Faction development replay - 2026-09-12

Use a fresh disposable world with initial group maximum 4 and faction minimum 4.
Opening-group chance still applies; established saves keep existing cohorts. Observe
normal groups rather than the developer command that directly spawns a faction.
Let a cohesive group travel/shelter together for at least one game hour, including
an offscreen interval. Developer Tools > Faction & World Events > **Write Faction
Formation Status to Log** shows member count, required count and missing shared
survival evidence. Follow formation into camp/home selection and resume after
save/reload. Repeat with factions disabled and with members separated or partly
active. Offline formation tests pass; this live development loop remains pending.


## Travel, reading and driver replay - 2026-09-12

Pending live acceptance; automated doubles do not establish in-game physics or
animation quality. Use a disposable save with the matching freshly built agent.

1. Walk past one zombie, then a small crowd. Compare facing/behind, crouched/upright,
   blocked LOS and an actual pursuing attacker. Routine travel should not provoke
   a neighborhood hunt. Contact must remain dangerous. Repeat with cautious travel
   disabled, an aggressive companion and a crouching/running actual group leader.
2. Stock a suitable book in Main Supplies. An idle resident should collect, read
   and return it through visible native actions. Interrupt with thirst, an order
   and a threat; then repeat after save/load, after moving the book into a carried
   bag, and after removing the storage assignment. Confirm no lost/duplicated book.
3. Hold/Guard a hungry companion carrying safe food and water. They should consume
   supplies and resume the same order. Shove a guard away from the assigned post.
4. Enable Experimental NPC Driving on a quiet outdoor road. Start the engine, take
   a passenger seat, right-click the map 20–40 tiles ahead and select **Drive Here
   (Experimental) > [companion]**. Repeat with the NPC already a passenger and then
   already driving. Verify native entry/switch, correct heading and measured speed.
5. Place parked vehicles/walls beside the centreline, a bend, a pedestrian and a
   temporary obstruction. Check braking, waiting, detour and arrival. Use **Stop
   Driving** and take over the driver seat; NPC inputs must stop controlling the car.
   Test a different vehicle size, route failure and injury while driving.
6. Reject unloaded/distant destinations and a trailer clearly. Try map annotations
   and debug options. Current routes are limited to 160 tiles of loaded outdoor
   ground; this is not yet general long-distance road navigation.


## Base storage and permanent duty replay - 2026-09-09

Use a disposable save for **Developer Tools + Job Tests: Provide Tools and
Materials**. Normal play leaves this off. Right-click main supplies to manage
storage; Developer Tools > Base & Job Tests can stock real materials for testing.

1. Right-click a dry cupboard/crate inside your base > Knox Survivors > Set Storage
   > **Use as Main Supplies**. Right-click a fridge/pantry > **Use for Food & Drink**.
   A fridge/freezer object offers each compartment separately. Check the Work tab
   for assigned locations and the Base highlights for marked tiles.
2. Put edible food, raw meat, a water bottle and tools in the assigned stores.
   Empty one resident's carried food. They should collect a safe meal at home,
   eat it, and resume work. Repeat with the pantry upstairs. Spoiled/unsafe food
   must not be selected for eating. A full kitchen falls back to main supplies.
   Also let hunger become urgent while the resident is actively doing ordinary
   non-guard base work, then during a real supply transfer. Work should yield
   through the existing self-care path, real food access/eating should relieve
   hunger, and the same task should resume without a duplicated claim or item.
   Repeat with unsafe/unavailable food and verify truthful bounded failure;
   do not count a native action request alone as eating success.
3. Send a resident to find base supplies. Existing assigned stock must not be
   taken and redeposited as a new find. Watch them return from an actual find,
   approach the assigned container, transfer the item and resume base life.
   Repeat for a faction resident and after streaming/reload.
4. Assign guard and patrol work. Guards hold their post until released; patrols
   walk successive points and repeat. Add hunger/thirst, then a nearby attack:
   duty should resume after the interruption. Remove the security area while
   staffed/moving and verify the resident stops that duty.
5. Set a corpse drop area and a hauler. Watch native pickup, continuous dragging,
   arrival and release. The temporary dragged-body proxy must not draw weapon
   swings or bite steering. Place a real attacking zombie nearby to check a
   genuine emergency still takes priority. Confirm the dropped body is in the area.
6. Issue Follow/Hold/Guard and watch gestures; busy actors must finish their native
   action. Disable order gestures and confirm player and NPC leaders both comply.

All six are pending live acceptance; Lua tests verify control flow and invariants,
not the visual animation, stairs, doors or driving behavior inside the game.

### Typed storage capacity restore — Build 42 acceptance (BUG-KS-039)

On a disposable save, record the native `getCapacity()` and contents of two
compartments on one furniture object (for example a fridge/freezer). Assign a
typed storage role to each and verify the assigned compartments use only the
installed Build 42 native capacity ceiling. Remove one assignment through its
normal context-menu entry: its original capacity and all real contents must
remain/restored, while the sibling assignment keeps its own capacity marker and
limit. Remove the final assignment and verify its original capacity is restored
and the active assignment marker is gone. Repeat after save/reload and, where
two valid owned bases can reference the same native compartment, remove each
policy in turn; the capacity must remain raised until the last policy is
removed. No item should move or disappear solely due to a capacity restore.

`ToolCupboardCapacity` is a legacy setting for old Tool Cupboard records only;
it does not configure current typed storage. Offline tests verify the lease and
ModData control flow, not native capacity persistence or item preservation.

Also check an old typed assignment without an original-capacity snapshot: its
removal must leave the current capacity unchanged and report unconfirmed
restoration, rather than inventing an original. If a native setter rejects an
observed original (including a value created by another mod), rollback metadata
must remain and the UI must not claim confirmed restoration. Rejected policy
removal must leave capacity/name unchanged; identity lookup must not reapply
assignment effects. Local fixtures reproduce silent setter rejection and
rejected removal against the pre-Astra snapshot, but native acceptance still
requires this replay.

## Base-job supply entry recovery - 2026-09-28

Use a disposable loaded base with one real claimed job and the required item in
its assigned storage. Put that store behind a locked door with a usable quiet
window route. Confirm the resident tries the existing alternate-entry path,
keeps the exact item/container reservation, enters, resumes the same storage
approach, transfers the item natively, then resumes the claimed work. Repeat
with all quiet entries unavailable and a permitted melee-equipped forced
entry; verify the lease remains owned through door combat and the same real
item is still checked at arrival. Then repeat with protected structures,
opening disabled, inadequate endurance, or no valid forced entry and verify
truthful task failure plus released claims/reservations. Interrupt traversal
with danger or an order, and save/reload during the route if practical. Record
native movement/action outcomes and item counts; offline tests do not prove
these Build 42 results.

The public locked-door persistence report is not considered reproduced by this
scenario; it validates the assigned-storage leg that previously bypassed the
existing traversal recovery. Corpse/fence behavior remains a separate live
replay.

## Integrated settlement and encounter acceptance - 2026-09-09

These scenarios are pending live acceptance on the installed Build 42 runtime.
Use a disposable save and normal player commands; record the relevant survivor
IDs and base IDs so streaming/reload results refer to the same people.

1. Recruit a roaming survivor and Talk within four tiles in clear sight. They
   should stop briefly without losing their Follow order, then resume. Walk away,
   change floors, issue an order, or expose an attacker during attention: the new
   activity must win. An active worker must finish/release work before casual talk.
2. Give a base one central cupboard with seeds, crop water, axe, saw, hammer, logs,
   planks and nails. Keep builders'/farmers' inventories empty; create work areas,
   including an external wood lot. Watch native transfers before real planting,
   watering, chopping, sawing, barricading and construction. Add two hinges and a
   doorknob for a door; construction skill requirements still apply. No manual
   inventory injection should be necessary to get cupboard-backed discovery started.
3. Put a broken tool and empty bottle ahead of usable copies in storage, and put
   broken/empty duplicates on a worker. They must acquire usable instances, not
   repeatedly walk to work with invalid supplies. Remove real required stock:
   no task may succeed or create materials. Restore supplies and check recovery.
4. Complete a small rectangular construction area. Keep exactly the intended gate;
   the opposite wall must be filled and finished edges must not attract repeated
   frame-building attempts. Interrupt one worker during gathering and one during
   work; verify native cancellation, retained items and coherent task recovery.
5. Observe two independent survivors greeting. Introduce danger during approach
   and again during the greeting. The escaping survivor must keep escaping and
   the waiting partner must return to normal activity. A resting resident must
   get up before walking over, without leaving a stuck furniture reservation.
6. Test an injured/unarmed survivor against a visible hostile human. Verify an
   escape route, then recovery and return to duty when safe. Repeat with unseen
   people behind walls, established peace, and player combat disabled; those must
   not generate inappropriate retreat. Keep zombie/self-defense checks enabled.
7. Observe independent residents and a returning supply team across streaming and
   save/reload, using a base whose territory is larger than its home. Verify real
   stock, IDs, membership and claims persist; arrival/resident positions must use
   the actual territory rather than a single corner. Check clear activity labels
   while workers gather, wait, retreat, eat, deposit and return.

Record frame times at the configured population during ordinary play and crowded
job/combat situations. Offline regressions do not establish frame-time performance,
multiplayer support, native animation quality or multi-day survival balance.

## Repeatable offline verification

Run `./tools/verify.ps1` from PowerShell. It checks every mod Lua source with Lua 5.1,
runs every `tools/test-*.lua` script, then runs Java check/build. All checks run even
if an earlier test fails; the command exits nonzero on any failure. Per-check output
and `summary.json` are written to the ignored `build/verification` directory.
Use `-Lua` and `-Luac` for explicit interpreter paths, `-GameDirectory` when native
Lua fixtures need a non-default game installation, or `-SkipJava` for a focused Lua
pass (the summary records that omission). This does not stage, deploy or start a game.

The [current QA and release contract](production/QA_RELEASE.md) defines the integrated
acceptance order. For the current additions, check paired and single-file followers
at spacing 1 and 3 through doorways and turns; no movement to an unloaded/blocked
slot or leader tile should be issued. Verify injured companions show both current
activity and needs. Try boarding while native actions cannot start, then retry when
available: no phantom seat reservation or queued duplicate should remain. A save
with refill days 0 retains its initial people but never replaces routine population
losses; enabling refill later waits a full configured interval.

Java Gradle verifiers write diagnostics to `java/build/verification-logs/<task>/`
instead of the player's `Zomboid/KnoxIsoPlayer.log`. Synthetic failure cases are
expected there. Use game `console.txt` and the normal agent log for live evidence;
a verifier run should not update either gameplay log.

Knox Survivors now exposes its test harness through real Build 42 sandbox settings.
Developer tools are off by default. Enable them on a test save, then select one automatic
scenario or use the in-world right-click menu described in
[Sandbox Settings](SANDBOX_SETTINGS.md). The tools never rewrite vanilla sandbox values.

## One-click combat tests

### Human-combat eligibility regression (pending live)

Use a disposable test save with coop PvP off and Knox survivor/player combat on.
Attack an independent neutral survivor: verify a real native hit, health/injury
change, and hostility only after contact. Miss once and confirm no hostility from
the miss. Check a recruited companion and a friendly survivor remain protected.
Then test a hostile survivor attacking the player and another hostile survivor;
verify two-way native damage, godmode protection, death cleanup and movement resume.
Repeat the player swing with Knox survivor/player combat disabled. Do not enable
global PvP to make this test pass. Multiplayer combat is not covered by this adapter.

With developer tools enabled, right-click the ground and open
**Knox Survivors - Developer Tools > Run Combat Scenario**. The menu provides a one-on-one
fight, one survivor against a zombie group, a travel group fight, a faction fight, and a
larger stress test. Each preset creates its survivor population, spawns only its own tagged
zombies nearby, and watches for both survivor damage to zombies and native zombie damage to
survivors. It does not remove ordinary world zombies or alter sandbox population values.

The activity feed reports PASS, PARTIAL, FAIL, or BLOCKED. A PASS requires evidence of
two-way combat. **Write Combat Snapshot to Log** records every test survivor's controller and
Java combat state plus each test zombie's target, distance, target-seen timer, attack action,
attack outcome, collision-damage flag, and survivor health. **Cleanup Combat Test** removes
only zombies created by the selected preset; the deliberately spawned development survivors
remain persistent so save/reload can still be tested.

For the current native-bite gate, run **Survivor vs Zombie** and then **Survivor vs Crawler**.
Keep the player far enough away that the test remains uncontaminated, and wait for each automatic
result. The start line records `crawler=false` or `crawler=true crawlerConfigured=true`; if the
latter is not true, stop there and collect the logs. If either result is not PASS, write one
combat snapshot before cleanup, close the game normally, and use the collected run folder. That
single comparison distinguishes failure to acquire, approach, transition into the bite animation,
fire its collision event, or apply BodyDamage.

The 2026-08-25 duel and survivor-group runs reported PARTIAL: survivor approach, melee
animation, damage, kills, and moving-target re-approach worked, but zombie collision damage was
not consistently visible. Engine inspection isolated two lifecycle hazards: an off-slot zombie
could be re-entered from `hitreaction`, and a completed bite could be re-entered with stale
`ZombieBiteDone=true`. The current patch defers those transitions, clears the native terminal
flags before each new bite, and records the survivor's `AttackType`, hit-reaction action,
floor-aim state, and `attackedBy` result in the snapshot. It also gives the survivor a short
native-defense interval between swings, including stomp targeting for downed zombies. This is
ready for a fresh live confirmation; it is not marked verified until the run records a real
survivor reaction and health/injury change.

The current zombie handoff no longer forces either Build 42 combat state. Fresh engine evidence
showed that the old bridge was trying to write the unused off-slot lighting bit, which Build
42.20.3 does not create for a contained NPC. Crawlers can attack because their close-range branch
skips that standing-zombie visibility gate. Knox now adapts only the single
`IsoZombie.isTargetVisible()` lookup for a confirmed Knox shell; real players still use their
normal lighting data. The adapter does not change target selection, pathing, collision, attack
states, animation callbacks, hit rolls, or BodyDamage. The standing-zombie result is still
live-unverified until the next duel records the full native attack and injury sequence.

The shell's `isLocalPlayer()` override is also explicitly false. Local-player combat callbacks
needed by survivor melee remain covered by the existing three-call callback transformer; the
NPC itself no longer leaks into unrelated local input, music, or building-entry branches.

The awareness handoff now keeps a short native-target memory instead of reissuing the same
target every frame. Close-range perception refreshes are paced, and a zombie keeps its current
survivor target unless that target is lost or a clearly more urgent target appears. This is
intended to prevent attack-state churn while preserving normal zombie target selection and
collision rules. Movement also reports `FailedStuck` after a real no-displacement window, and
failed traversal edges receive a brief cooldown so a survivor can choose another route instead
of repeating the same locked door, fence, or window attempt.

Save capture attempts every active survivor independently. If one shell is unloading or
otherwise cannot be captured, successful records are still written and the save log reports
the failed IDs instead of aborting the entire capture pass.

## Production world population and hibernation — live retest required

The production population core now allocates survivors from the map's real Build 42 player
spawn definitions and materializes only nearby loaded identities. A first live run confirmed
that a 64-survivor test population initialized and that `ks-world-50` materialized when the
player entered its area. That run also exposed a streamed-out lifecycle bug: the shell lost
`getCurrentSquare()`, was labelled `STORED`, and repeatedly failed persistence capture.

The lifecycle fix changes that path in three ways: hibernation is checked every 30 ticks
instead of only during the slower population reconciliation pass; behavior controllers call
a missing-square body `DETACHED` rather than claiming it is already stored; and Java record
capture can fall back to the shell's last finite XYZ position when the engine has already
streamed its square out. Removal still happens only after capture succeeds.

For the next live pass:

1. Use a fresh or disposable save with a noticeable world population and developer diagnostics
   enabled. Travel through normal player-spawn neighborhoods until a survivor activates.
2. Confirm `population-activated id=... mode=... square=... playerDistance=...` appears and the
   survivor stays physically valid while you remain in the area.
3. Move away from the survivor. A normal distance hibernation should log
   `hibernate-attempt reason=distance` followed by `state=HIBERNATED` without any repeating
   `CAPTURE_FAILED` lines.
4. If the engine streams the square first, the Java log may report
   `NPC persistence capture fallback ... reason=no_current_square`; Lua should still complete
   one `state=HIBERNATED reason=detached` transition and remove the runtime cleanly.
5. Return to the saved area and confirm the same identity restores at the recorded square.
6. During the same run, watch for `MOVE_ALREADY_REQUESTED`, verify zombies actually complete
   attack animations against survivors, and confirm survivor health can fall below 100.
7. Recruit a companion or let a travelling group form, then lead it through a building exit,
   around a fence, and far enough to require running catch-up. A blocked formation route may
   log one `formation_movement:...` failure, but it must enter `GROUP_WAIT` or
   `COMPANION_WAIT` until the reported `retryAt` tick instead of issuing failures every frame.
   Put that group under pressure with three zombies per nearby survivor, or let one member
   fall to 25% health. The leader should choose one retreat direction and members should run
   or sprint toward nearby separate tiles, rather than each selecting an unrelated escape.
8. Change direction while a follower is catching up. The status line should show a bounded
   `formationFailures` streak; a successful catch-up must reset it to zero.
9. Separate one travelling-group member by more than the retrieve leash. The leader should
   wait or move back toward that member rather than continuing to widen the separation.

## Barter quotation / exchange / Trade window — live verification required

Run `tools/test-trade-valuation.lua` with the repository root argument. It executes the quote module
against real Knox persistence and native-shaped inventory objects: full-type ownership, known item
subtypes, quantity/condition, food/water safety, stock/urgency, offer order and food portion splitting,
whole-basket reserve protection, native ammo-key matching, nested bags, favorite/equipped items,
oversized/corrupt inventory, canonical base task demand, life/affiliation/hostility, player identity,
trust/reputation, reload stability and the nonzero spread. Quotes never change inventory or rewards.

`tools/test-trade-action.lua` additionally executes the installed 42.20.3 `ISTransferAction` and
base timed-action Lua with native-shaped containers and the real Knox controller/runtime/quote/
persistence domain. Its optional second argument is the game installation directory. Native Java
containers and record encoding remain mocked here. It covers exactly-once exchange, original item
identity/receipt, full-capacity root swaps, source/destination policy and ID rejection, cancellation,
queue failure, invalidated offers/relationships/life/reach, capture failures, transfer exceptions
before and after insertion, verified rollback, reputation error isolation, lease expiry, directive
changes, unload/detachment and retaining a recovery journal after an injected rollback failure.

`tools/test-trade-ui.lua` runs the actual UI/context callbacks and exchange/controller code with
native-shaped widget stubs. It checks single initialization, viewport/font layout, joypad focus,
fair-offer selection, completed exchange, close cancellation, two-minute expiry, danger, menu/death/
resolution cleanup, changed inventory, persistent capacity-error feedback and hostile/multiplayer
menu guards. It is not a rendered game UI test. Valuation checks also reject hidden items/hidden bag
contents and shared-inventory browsing; action checks cover browsing-to-exchange lease handoff.

Use an independent nearby NPC on a backed-up single-player save. Stand beside them with no blocked
edge and right-click Trade. Select items on both sides with double-click or Offer / Remove (joypad
A; left/right changes list). Y or Trade confirms an acceptable offer; B or Close cancels. Test a
low offer, then a fair one, and ensure the refusal/fair indication is readable. Try duplicate/stale
items, nearly equivalent goods, unsafe food, mismatched ammo, a whole reserve basket and a fair
useful exchange. Verify the real items change owners exactly once only for a valid accepted offer.
Repeat while moving away, entering danger, changing inventory after the quote and interrupting the
action; neither side may lose its payment or receive free items. Save/reload immediately afterward
and check both inventories and completion-only reputation. Also check nested bags, container
capacity, hostile/recruited targets and split-screen. While browsing, close the window, leave reach,
allow two minutes to pass, introduce a threat, or return to the menu: the survivor must be released
without losing its underlying activity. Opening/closing alone must never grant inventory access or
reputation. Verify both small/large fonts, list scrolling, long names, window close/minimize behavior
and controller focus. Reopen after completing one exchange to trade again. Real animation, native
container side effects, rendered layout and save/reload exchange integrity need live evidence.
`[Trade] RECOVERY_REQUIRED` is a hard test failure: stop further trading, retain the logs and do not
assume the before-record or inventory has safely recovered. Fault-recovery UX/durable recovery is
unfinished. Multiplayer trade is deliberately rejected rather than using fake player IDs.

## Wallet / currency gate — live verification required

Run `tools/test-wallet-currency.lua` with the repository root; optional second argument is the
42.20.3 installation. It checks the actual native wallet definition/UnbundleMoney recipe, executes
native wallet acceptance and wear completion Lua against native-shaped fixtures, then real Knox
equipment selection and barter using cash inside a worn wallet. Checks include missing/changed
script definitions, repeated setup, separate slot, unchanged non-wallet definitions, accepted and
rejected contents, supported/unknown currency, denomination ratio, stock saturation, trade receipt,
remaining coin ownership and no repeated equip. Native objects/registry initialization are mocked;
this does not prove the full game bootstrap. Inventory cleanup tests protect bundles/coins, and
the Java inventory snapshot verifier round-trips wallet cash/coins plus a separately worn backpack.

On a backed-up test save, obtain an existing Base wallet, cash, coins and a backpack. Use the normal
inventory Wear option for both wallet and backpack. Confirm a separate accessible wallet container;
drag bills/coins into it, confirm capacity/size limits still apply and a gold bar is rejected. A
MoneyBundle must be unpacked using the native recipe before its bills can enter the wallet. No
free wallet or cash should appear merely from loading the mod. Wear/unequip should keep contents.

Give a survivor a carried wallet and cash/coins, let existing equipment evaluation equip it, then
unload/restore and save/reload. Check the same types/counts and wallet/backpack worn state. Trade
with a neutral survivor using bills/coins from a worn wallet or a bundle from normal inventory.
Verify real payment, no duplicate currency, no emptied wallet lost or unequipped, preserved favorite
protection and clean action cancellation. Repeated equivalent trades must not manufacture value.
Check native menu labels/bag switching and console errors. This mod slot should be unequipped before
disabling/removing Knox. Broader currency/rarity balance and compatibility with other wallet mods
remain unverified. Then continue the reputation gate below.

## Player contribution / reputation gate — live retest required

On a disposable backed-up save, find a neutral survivor and kill a zombie actively targeting them
within eight tiles. Stay on the same floor and within twenty tiles of the survivor. Confirm a bounded
acknowledgement and trust increase in the existing survivor card; repeated rapid kills must not spam
credit. Repeat with a faction member and inspect the canonical faction relationship reputation.
Save/reload and confirm trust/reputation and reward cooldowns survive. Unrelated kills, another
floor, a zombie targeting the player, NPC-made kills and missing native target evidence earn nothing.
If the native death event has already cleared its target in a particular death path, record that
missing-evidence case; do not treat nearby kills as proof of defense.

With survivor/player combat enabled, hit a previously neutral survivor. Confirm Talk/Recruit become
unavailable with a hostile label, trust drops, and their NPC faction becomes hostile if applicable.
Continued combat must not repeatedly apply the first-aggression penalty. A hostile target cannot
be made recruitable just by talking/help credit. Test with both split-screen players if available:
only the actual player's relationship should change. No test grants items, cash, health or XP.
Trade credit is now wired only after a captured, verified exchange; gifts/medical/construction
rewards still lack completion adapters.

## Weapon preference gate — live retest required

Give a companion a usable bat, pistol, compatible magazine and real rounds. Under Orders →
Weapon Preference, choose Prefer Melee, Prefer Ranged and Survivor Choice in turn. Confirm only
the active option has the native checked marker and a newly opened menu reflects saved state.
Melee should keep the bat available; ranged should use the pistol only when native ammo/reload
allows it. Remove compatible ammo and verify melee fallback without reload spam. Survivor Choice
should usually keep a novice on melee; a survivor with native Aiming 4+ and room to aim may use a gun.

In the sandbox, repeat Survivor Choice with Survivor Aiming Assistance set to Native Skills,
Basic Assistance, and Strong Assistance. The setting changes automatic firearm commitment and
the visible aim-settle delay only. It must not change the survivor's native Aiming level, XP,
native shot accuracy, ammunition, reload action, weapon condition, or damage. A low-skill
survivor may commit sooner with assistance while still producing native low-skill firearm
results. A high-skill survivor should settle faster than a low-skill survivor in every mode.

Change preference during a reload and during combat; check no simultaneous reload/fire/weapon-swap
loop, then confirm Follow/Hold/Guard remains intact. Set two companions to different preferences:
the party menu should show no single checked preference. Apply a party choice and confirm both
update. Save/reload, send a companion home/re-recruit, and verify the policy remains. Run the existing
Survivor Firearm Test: its test identity now explicitly prefers ranged to exercise real reload/fire.
Automated policy/menu/native-shaped fixtures cannot prove live timing, sound, ammo or animations.

## Carried cleanup / deposit gate — live retest required

On a backed-up disposable save, overload a survivor with a broken spare weapon, an inferior spare,
vanilla junk, extra food and planks. Also include equipped/attached gear, a favorite bag, ammo,
medical supplies and an accessory. Observe away from storage, then beside a categorized container
or depot assigned to their own base. Only eligible low-value items may be dropped; useful surplus
food/materials should be deposited rather than discarded. Confirm dropped objects remain lootable
and deposited items really exist in the destination. Required job supplies must remain carried.

Repeat with full storage, an intervening wall, a foreign/unassigned container, combat interruption
and replacement Hold/Follow. There should be one action at a time, no transfer spam, no command
loss and no item disappearance/duplication after save/reload. Unknown/favorite/valuable gear stays
protected. Also place an unassigned base resident 20–60 tiles from their own loaded assigned
storage with useful spare gear/materials. Confirm they walk to a valid interaction side, transfer
real items and return to normal behavior. Repeat with a blocked approach and then another eligible
container: failure must cool down rather than loop. During a trip change the base/storage, favorite
the selected item, issue Follow/Hold, trigger combat, or unload/save/reload. No old transfer may
survive invalid ownership and no duplicate/missing item may result. Travelling groups and active
companions must not abandon their roles for this detour. The local trip selector is same-floor and
128 tiles maximum; it does not claim cross-floor or unloaded-container logistics.
A protected-heavy inventory may remain overweight. Automated `test-inventory-cleanup.lua` and `test-base-storage.lua`
cover policy/action ownership and native-shaped fixtures, not in-game animation or world transfer.

## Unloaded survival ledger — live retest required

When a captured survivor is not active, Knox now advances a compact persisted survival
ledger rather than freezing their needs completely. It uses the portable inventory record:
if an unloaded survivor drinks or eats, real stored quantities are consumed before the need
is relieved. Partial food and reusable water bottles remain. Independent survivors distinguish
awake travel from endurance rest and sleep in the same ledger, then restore those needs when
the survivor materializes again. Fully stored travel groups share travel/rest decisions;
away-team missions retain their earlier policy.

1. Give a survivor at least one food item and one drink, then allow normal distance
   hibernation. Do not use a developer preset that gives the survivor endless supplies.
2. Advance enough game time while away for needs to matter, then return until the same ID
   restores. The survivor should retain its identity and have its restored needs applied.
3. Look for restrained `[KnoxSurvivors][Unloaded]` event lines only when a food/water item was
   consumed or an exceptional condition occurred. There should be no per-tick spam.
4. Save, quit, and reload while the survivor is hibernated; returning to the area must restore
   the same stored ledger and must not duplicate the consumed item.
5. Leave a faction resident at a settled base, travel away for at least one in-game day, then
   return. The resident should restore at a safe valid point inside its own base territory,
   not at the old hibernation tile or stacked with every other resident. This is ambient
   off-screen base life, not an away mission.

The focused `test-unloaded-survival.lua` check covers record-backed consumption, rest
recovery, and durable starvation/dehydration death. It does not prove live engine behavior.
`test-world-presence.lua` also exercises real Lua persistence and the production itinerary across
capture, travel, interrupted sleep, module reload and hidden-square activation. In a disposable
save, compare a rested independent survivor and an exhausted one after several unloaded hours;
the rested survivor should progress between nearby locations, and the tired one should pause,
recover and resume. Save/reload during the pause and confirm no snap back to the capture tile.
Send a companion to an unloaded base several hundred tiles away and verify gradual travel,
rest when needed and arrival at the current base. Reassign Follow during the trip and verify the
old return destination no longer controls movement. These pacing/restore checks remain live-only.

For stored groups, keep three members together, exhaust one, and leave their area. Advance time,
save/reload, then inspect the same identities: the group should rest together and later travel
with preserved spacing. Separating one before hibernation should make the others wait while that
member approaches, not teleport them together. Keep one member loaded in a repeat run: stored
members must not independently drift while the loaded controller owns the group. Verify native
regroup/activation after returning, member/leader death cleanup and retained inventory quantities.
`test-unloaded-groups.lua` covers the production Lua scheduler, shared itinerary, real persistence,
rest/reload, unequal clocks, separation, death and per-member supply transactions without a live
engine. Different-floor regrouping remains delegated to loaded navigation, not this simulation.

Do not call this gate complete until activation, hibernation, restoration, and one real zombie
attack have all been observed in game, and the collected log contains no formation retry storm.

## Party commands, zombie parity, and base territory — live pass pending

The latest build adds occupation/trait persistence, recruitment, companion orders, the
right-side HUD, and the shared base domain. Compilation and standalone save tests pass;
the following behavior is not yet called live-verified:

1. Start with the normal three-survivor scenario and confirm the player stays visible.
2. Right-click a nearby independent survivor. With the default **Require Trust to Recruit** setting
   off, `Recruit` should be immediately available inside four tiles. On a second disposable save,
   enable that setting: three successful `Talk` conversations separated by the half-hour in-game
   cooldown should raise trust enough to recruit. Hostile, grouped, or faction survivors must refuse
   recruitment under both policies.
3. Recruitment should create one companion HUD row. Confirm the portrait, name, activity,
   weapon, health, food, water, and rest bars update without stealing mouse input.
4. Test Follow and Hold from both the world menu and HUD right-click. Lead a zombie close;
   combat may interrupt the order, but the survivor should resume it afterward.
5. Stand within four tiles of a companion, right-click them, and choose `Medical Check`.
   The real player should walk into range, play the vanilla medical-check action, and open
   the regular body-part treatment window for that survivor. Treat a real minor wound with
   a carried bandage, then save/reload: the treatment and the consumed item must persist.
   Do not treat this as complete until it has been checked with an off-slot survivor body.
6. Return to the main menu and reload. The same person, occupation, traits, perk progress,
   ownership, command, and HUD row must return. No duplicate panels should appear.
7. Inside an unclaimed building, use `Knox Survivors > Establish Home Base`. Right-click
   a container inside it and set one storage category. Reload and confirm both remain.
8. Choose `Return to Base` while the home area is loaded. The survivor should move back,
   then alternate between short patrols and idle time around the home. They are not eligible
   for future jobs until physically inside the saved base bounds. Repeat while the home area
   is unloaded: the survivor should say they are heading back, disappear only after a normal
   capture/removal handoff, and later restore near the base with a `VIRTUAL_BASE_RETURN` log
   rather than reappearing at the old location. This unloaded route remains live-unverified.
9. If possible, repeat recruitment/HUD ownership with a second split-screen player. Each
   viewport must show and command only its own companions.
10. Right-click the `SQUAD` header. Test whole-party Follow, Hold, and traversal policy.
   Right-click the world and issue Loot Nearby Area, Loot This Building, and Loot Dead
   Bodies. Critical needs and combat may interrupt, but survivors must resume and then
   return to their primary order when the directive finishes.
11. From a world-square Party Orders menu, issue `Move Party Here`. Survivors should
    travel to the selected square, report arrival once, then return to their underlying
    Follow or Hold order. Issue `Guard This Location` and confirm they stay near the
    selected square, still defend themselves, and return there after a short fight.
    Save/load once while a guard order is active; its location and order must survive.
    Individual survivor menus also provide `Move to Me` and `Guard Here`; the HUD row
    should change from Follow/Hold to the current directive while either is active.
12. Close the activity feed with X, then reopen it through the `SQUAD` header menu. Speech
    must show the speaker name plus a stable party/group/faction label and color.
13. On a disposable save, record the Build 42 version, mod root, base ID, and
    current bounds. Use `Set Home Base Boundary` to select one asymmetric area
    in both corner orders. Record clicked world squares, draft highlight,
    confirmation dimensions, persisted min/max bounds, and reopened state.
    Check all four edges and adjacent tiles for ownership, then save/reload and
    compare again. Residents must navigate every floor normally. The current
    owner supports one axis-aligned rectangle across floors; a disconnected
    area is a model limit, not a polygon/union acceptance expectation.
    Friendly survivors may open ordinary entries but must not smash player-base windows
    or attack its locked doors.
14. Open the Survivor Notebook from the party header and verify Party, Home Base,
    Survivors, and Factions show distinct, readable data.
15. From a player-owned base, use `Knox Survivors > Set Work Area`, choose Guard Area or
    Patrol Area, and select two opposite corners. The zone should appear in the Notebook's
    Home Base tab. A base resident should claim the recurring task, walk to a standable point,
    remain there briefly, and then record `completed_guard` or `completed_patrol` before the
    same zone becomes available again. Combat, a new companion order, leaving the base, or
    a save/reload must release the claim instead of leaving a permanently stuck task.
16. Set an Animal Care Area over one or more loaded feeding troughs. Give a base resident a
    container holding water and an animal-feed bag. A trough below half capacity should create
    one persisted refill task: water uses the normal pour animation and fluid transfer, while
    feed uses the normal inventory transfer and trough sound. The task should finish only when
    the real trough amount increases. Full troughs, missing supplies, a removed trough, or an
    incompatible fluid must be skipped or released for retry instead of claiming success.
17. To test depot sorting, mark one container `Depot` and another `Food`, `Building Materials`,
    or another supported category. Put one matching item in the depot, send a base resident
    home, and watch for one transfer with the normal rummage animation. The task should finish
    only after the item leaves the depot; an empty depot or unloaded destination must leave the
    task waiting/retryable rather than deleting the item or claiming success.
18. Give a base resident a hammer, a plank, and at least two nails, then leave an unbarricaded
    closed window inside the base boundary. The resident should walk to it, play the vanilla
    Build action, consume one plank and two nails, and complete only when the real barricade
    reports one additional plank. Fully barricaded windows should be skipped; missing tools or
    materials should leave no claimed task behind.
19. Set a farming work area over a loaded crop patch. With one ripe plant, the resident should
    queue the normal Harvest action and the plant should no longer report harvestable after
    completion. With a seeded plant below full water and a usable water item in inventory, the
    resident should queue the normal Water Plant action and the plant's water level should
    increase. Missing water, unloaded plants, and plants that no longer need work should be
    skipped and retried later rather than claimed indefinitely. With a usable digging tool and
    a matching carried seed, an empty suitable square should then be plowed and the resulting
    furrow seeded as two separate normal actions. No seed should mean no pointless plowing.
20. Set a Woodcutting Area over one or more loaded trees and give the resident a usable axe.
    The resident should equip the axe, play the normal Chop Tree action, and finish only when
    the tree object is gone. Missing axes, unloaded trees, or an already-chopped target should
    be released and retried rather than reported as success. If the resident carries a log and
    a usable saw, the next task should use the vanilla SawLogs recipe and consume the log for
    real planks; missing recipe, tool, or skill should leave it retryable.
21. Set a Corpse Drop Area on clear ground inside the base, then leave a human or zombie body
    elsewhere in the loaded base territory. The resident should walk adjacent to the body, put
    away held items, use the normal grab animation, drag the body to the drop-area center, and
    use the normal drop action. Bodies already in the drop area and animal bodies
    are deliberately excluded from this job. Starting combat, changing the resident's order,
    or failing the route while dragging must release the body and leave the task retryable.
22. Damage a player-built door, thumpable wall/fence, or barricade to between 20% and 95%
    health. Give a base resident the exact tools and materials shown by vanilla Repair mode.
    With no Repair Area the resident should maintain a loaded target anywhere in the base;
    drawing a Repair Area should restrict discovery to that zone. The normal repair animation,
    sound, material consumption, and skill-based chance should run. Knox must report success
    only if object health rises. Empty supplies, a barricaded door, a removed target, objects
    below 20% health, and a legitimate failed skill roll must remain failed/retryable rather
    than being silently restored or reported as repaired.
23. Draw a **Defense Construction Area** at least three tiles wide around a small outdoor
    perimeter, then give a base resident a hammer, planks, nails, hinges, a doorknob, and the
    required Carpentry level. The resident should build the planned access frame, then its
    door, before working through wall frames and first-stage walls. Each step must use vanilla
    Build actions, consume the actual recipe materials, and finish only when the expected
    Build 42 entity exists in the world. Remove a target or supplies mid-action to confirm the
    persistent task is released for retry rather than being marked complete.

Report the first exception or incorrect ownership transition rather than continuing on a
damaged test save. Live portrait framing, world-menu picking, distant-base return, and
split-screen isolation are the highest-risk checks in this gate.

## Active test: three independent survival controllers

Start a new Build 42.20 development save. The active scenario does not alter sandbox
settings, remove loaded zombies, freeze zombies, or make survivors immune. It uses the
save's normal zombie population. Three survivors are placed in a broad nearby test band
so social behavior can be observed without searching the map for hours; their survival
decisions and world interactions are otherwise live.

1. Fully close Project Zomboid so the new Java agent can load.
2. Start it with `Run Knox Survivors Dev.bat` and create/load the new save.
3. All three survivors should spawn or restore with their identities,
   health, needs, inventory, and equipment intact.
4. Each survivor now owns a separate decision controller. They can independently roam,
   detect and fight nearby zombies, satisfy carried food/medical/water needs, search for
   missing supplies, loot a reserved item, and re-evaluate their carried melee weapon.
5. Survivors should prefer reachable uninspected containers over random roaming. They
   visibly search, take up to two ranked need/upgrade items when present, and re-evaluate
   worn clothing and their carried melee weapon. They should not empty the container.
6. Survivors notice one another within 24 tiles. One approaches while the other safely
   waits, then they exchange short speech bubbles and matching lines in the small vanilla-
   styled Knox Survivors activity window. The encounter can join, decline, or become hostile.
   Afterwards group members follow their leader unless a need or zombie interrupts.
7. Let the test run until all three survivors complete at least two decisions. Their choices
   do not need to match.
8. Zombies can attack during this test. Do not intentionally lead a large group into the
   survivors while controller ownership is being checked.
9. Leave the game running for several minutes. The player and visible survivors must not
   fade permanently. Each periodic `render RENDER_DIAGNOSTICS` line should keep the local
   player at `alpha=1.0,targetAlpha=1.0`; NPC alpha may legitimately change with the real
   player's line of sight.
10. If a survivor encounters a locked door while pursuing optional loot, they may try a
    usable window but otherwise abandon and cool down that room. Only urgent food, water,
    or medical searches may attack a locked door, and only with sufficient endurance.
11. A survivor below the endurance threshold should choose the most comfortable free seat
    within eight tiles, walk to it, and sit while recovering. If no usable seat is reachable,
    the survivor sits on the ground. Look for `recovery-posture` and increasing
    `recovery-progress endurance=` values before the survivor stands and resumes autonomy.
12. After a group forms, followers should settle into separate staggered positions behind
    the leader rather than sharing one destination. Walk far enough to stretch the group. A gap
    of roughly five tiles should request running; a gap of twelve or more should request sprint
    catch-up when endurance and fatigue allow it. The live status line should expose
    `running=true`/`sprinting=true` and the route pace while the gap closes.
    The leader should wait around ten tiles of separation and move back toward a member who
    falls roughly fourteen tiles behind. After any zombie dies, every controller must leave
    combat and keep travelling; `releaseThreat` errors or `state=STOPPED` fail this gate.

Useful `console.txt` lines begin with:

```text
[KnoxSurvivors][Autonomy]
```

The expected result is:

```text
RESULT scenario=survival status=PASS reason=three_independent_autonomy_controllers
```

PASS proves all three stable identities made and completed decisions through separate runtime
controllers, then captures all three records. The controllers continue running after PASS so
longer observation can reveal combat, looting, needs, or navigation problems.

The development launcher monitors the run and collects its logs when the game closes.
`summary.txt` now counts both Test Lab and autonomy results, local-player alpha corruption,
alternate-entry events, and movement/combat failures. This keeps the next diagnosis
available without requiring the tester to copy console output manually.

The social result sequence is `meeting`, `greeting-approach`, `greeting-started`, then
`travel-group`. A two-person travelling group is not a faction. Adding a third consenting
survivor is the faction boundary once shared travel, loot, or combat has been recorded;
there is no minimum number of days together.

Persistent sociability and aggression influence three encounter outcomes. Joining creates
or expands a travelling group. Declining places that pair on a six-hour cooldown so they
carry on naturally. A hostile encounter currently robs up to two unequipped supplies using
normal timed inventory-transfer actions and records lasting hostility. Lethal survivor PvP
is not yet claimed because the verified melee bridge currently targets zombies only.

The faction/base sequence is `faction-formed`, `faction-base-candidate`,
`MOVING_TO_BASE_CANDIDATE`, then `faction-base-selected`. The final milestone evidence is:

```text
RESULT scenario=faction_base status=PASS
```

The candidate scorer currently requires a loaded building with at least two rooms and
30 tiles, favors residential buildings with water, rejects overlap with an existing
vanilla safehouse, and saves the building ID and bounds. Selection occurs only after the
leader reaches a standable exterior scouting point. It creates a vanilla safehouse boundary
and a stable faction-base record, then assigns faction members as residents. Residents
currently return, idle, and patrol; registered work tasks do not yet execute. The boundary
is restored on load and prevents the player from claiming an overlapping safehouse.

For the autonomy-cadence test, watch one survivor around several buildings for roughly
two minutes. After a useful loot visit or nearby rummage, the next normal decision must be
a roam leg rather than another container. An optional locked room should log
`blocked-area=optional_locked_entry` and be left behind. Urgent food, water, or medical
searches may still attempt one forced entry when endurance is at least 0.40.

For moving-target combat, let a zombie approach and then change distance during the fight.
The survivor may finish a swing already in progress, but must stop swinging at empty space,
move back into effective range, and resume. `knox-since-launch.log` records this correction
as `NPC combat REAPPROACH`.

Survivors immediately notice zombies within seven tiles, can notice visible zombies within
sixteen tiles, and prioritize zombies targeting a group member within twenty tiles. Combat
start lines record `awareness=immediate`, `visible`, `active_target`, or `group_target` so a
missed threat can be diagnosed without guessing from the screen.

Zombies should now discover a nearby survivor without first being attacked or led into the
survivor's swing range. Compare a survivor and the player standing at similar distance and
visibility. The result need not alternate perfectly, but survivors must be valid vanilla
targets and take normal attacks. Any `[ZombieAwareness] failed=` line fails this gate.

## Current foundation regression gate

This gate covers the 2026-08-26 constructor, Survivor Card, and detached-lifecycle fixes:

1. Launch through the development shortcut and load a backed-up save with at least two
   survivors active.
2. Open and close Survivor Card for two different survivors. Both cards must render without
   `ISUI3DModel.lua:110`, `setState of non-table: null`, player invisibility, or camera/input
   changes.
3. Leave the card closed and play normally for at least two status intervals. Every
   `RENDER_DIAGNOSTICS` survivor entry must report `instanceIsLocal0=true`.
4. With developer tools enabled, create a test survivor and travel far enough to stream its
   square out. A `detach-detected` transition may appear briefly, but it must be followed by
   one `hibernate-attempt` and `state=HIBERNATED` instead of repeating `state=DETACHED`.

The Java build and standalone policy checks prove the code path exists; only this live gate
proves Build 42 actually follows it.

## Already verified and hibernating

- one-survivor spawn, appearance, equipment, reconstruction, and save/reload;
- doors, windows, locked-window fallback, and low-fence traversal;
- melee approach, animation, damage, weapon use, and zombie death;
- container transfer and rummaging action;
- native injury reception, self-bandaging, and medical presentation persistence;
- native hunger/thirst consumption and physiology persistence;
- repeated autonomous roaming with independent completed movement requests.
- three simultaneous persistent survivor runtimes across save/reload remain the active gate.

For the firearm gate, use the developer **Survivor Firearm Test** once in a clear outdoor
area. The survivor should equip the seeded real pistol, queue a native reload when needed,
hold a visible stand-off distance, and fire through the normal aiming animation. Take a
combat snapshot after the first shot and confirm `firearm=` reports a real weapon with its
round count changing, while the Java status reports `ranged=true`. A reload or shot sound
must be audible/attract nearby zombies; a gun must not close to melee range or use the
floor-shove animation. This is a live gate: the standalone firearm test only proves that
Knox selects owned weapons and delegates reload to `ISReloadWeaponAction`.

For the passenger-vehicle gate, park a stopped vehicle with an empty installed passenger
seat, sit in the driver seat, then right-click a nearby companion and choose
**Orders → Enter My Vehicle**. The companion must path to an unlocked passenger door, use
the normal enter animation, occupy a passenger seat, and leave seat zero to the player.
Repeat with every passenger seat occupied: the companion must remain outside and say that
there are no more seats. Then use **Orders → Exit Vehicle** while stopped and confirm the
normal exit animation. Do not save/reload this slice as vehicle-seat restoration is not yet
implemented; no error, detached-shell hibernation, or change to vehicle keys/engine state is
acceptable while a companion is seated.

## Vehicle/driving stabilization acceptance — BUG-KS-030

Use a disposable Build 42 save. Record the stable survivor IDs, inventory,
orders, group membership, vehicle ID, seat/driver identity, native engine/fuel/
condition/lock/occupancy/towing accessor values, admission reason, movement
result, and vehicle controls at each transition.

1. Compare engine off/on, empty fuel, damaged/non-driveable, locked driver door,
   blocked/occupied seat, player-near/occupied vehicle, towing, and one valid
   fueled vehicle. Rejected candidates must not queue boarding or take controls.
2. Exercise passenger entry/exit and explicit driver admission with the player
   in seat zero. Fill passenger seats and confirm overflow members remain
   unleased. Try group orders before boarding, during boarding, and while
   riding; a real destination drive must use the current native route owner.
3. Interrupt boarding/driving with threat, critical need, duty/order change,
   injury, player driver takeover, engine/vehicle unavailability, and a blocked
   or destroyed vehicle. Confirm only the exact run roster is settled, native
   controls are released safely, and other cars/runs remain untouched.
4. Verify arrival/abort passenger exits, including a moving-car refusal followed
   by stationary retry. Verify no duplicate body, lost survivor, item loss, or
   stale order/group identity after unload/rematerialization.
5. Separately save/reload while occupied. Vehicle-seat restoration is not
   currently implemented: treat this as a limitation probe, record what Build
   42 restores, and check for identity/inventory/order/group corruption. Do not
   claim occupied-seat restoration as supported unless a later implementation
   adds and validates it.
6. For multi-car/group travel, test each real driver run and convoy spacing
   separately; native part consumption from Materials is another acceptance
   gate.

Offline `test-vehicle-driver.lua` now covers stale-roster cleanup while a member
has begun a separate run in another vehicle. It does not prove any native seat,
route, physics, control, persistence, or streaming behavior above.

## Known limits

### Fence and wall climb replay

Use an open disposable save with a survivor approaching a climbable tall fence
and then a wall edge. Confirm the log contains one `STARTED_FENCE_CLIMB` or
`STARTED_WALL_CLIMB` for each attempted edge while the native transition is in
progress; repeated route ticks must not issue duplicate climb requests. A
successful native crossing should advance to the next route node. An actually
unclimbable or blocked edge should end through the ordinary bounded movement
failure path instead of holding the survivor against the obstacle forever.

### Already-arrived work and formation orders

Give a survivor a work or follow order while they are already standing on the
selected destination tile or an adjacent arrival tile. The order should enter
the action or follow state on the next autonomy tick without a visible turn,
backtrack, or new route attempt. Repeat this for a guard post, patrol stop,
corpse-drop approach, and a companion follow refresh. Fence, wall, and window
edge crossings remain separate: being near an edge must still issue the native
crossing interaction and must not be treated as ordinary arrival.

- The active gate integrates already verified survival actions per survivor; it does not
  claim every action will naturally occur during one short run.
- Firearm sound-attraction/targeting, cooking, lethal survivor PvP, deliberate construction, and
  interactive Notebook management remain later gates.
  Guard/patrol work-zone drawing, one-item depot sorting, one-plank barricading, crop work,
  wood processing, corpse hauling, trough feeding/watering, and structure repair now have
  initial executors.
  Passenger companions can use native entry/exit actions, but NPC driving, group vehicle travel,
  and vehicle-seat restoration after save/load remain later gates.
  The current Notebook is the readable domain shell, not the finished base administration
  interface; newer jobs still require live in-game confirmation.
- If a recorded square is not loaded, the survivor remains stored instead of being
  teleported to the player.
- Room-wide alternate-entry planning, sleep furniture selection, death, and
  zombification remain unverified in game. For the death gate, kill one infected survivor
  and one survivor who should not turn under the active sandbox rule. Both must leave a
  normal lootable corpse after save/reload; only the eligible corpse should later reanimate.
  The log must contain `CORPSE_CREATED` with `reanimationScheduled=true` for the former and
  `false` for the latter. The alternate-entry implementation is present in the active gate
  but still requires its first live end-to-end observation.
- Unloaded Return to Base now has a persisted virtual-route handoff, but it still needs its
  first live save/reload and rematerialization test.
- The Java agent requires the development launcher.

## Knox Events ledger / real-roster raid proposal checks

Run `lua tools/test-knox-events.lua .` from the repository root. This loads the real
persistence service over a fixture ModData store and checks additive schema migration,
hostility gating, five-member/two-raider selection, claimed-work exclusion, one active
party per faction, defensive snapshots, revision-checked phases, save-state reconstruction,
death/relocation/peace invalidation, home-defender loss, malformed record recovery, bounded
maintenance, history pruning, and cooldown retention across pruning/reload. It also checks
that survivor count, native record strings, and base/affiliation intent are not rewritten.

Run `lua tools/test-event-stored-readiness.lua .` to verify the inactive-party dispatch
boundary. It checks fresh persisted physiology and home position, read-only native equipped-
weapon readiness, active-body exclusion, atomic all-member qualification, bounded retry,
save reconstruction, and dispatch without materializing or manufacturing survivors/items.

Run `lua tools/test-event-automatic-scheduler.lua .` to verify automatic proposal policy:
world-age/settings gates, explicit hostility, persistent scan timing, real minority rosters,
one active automatic event, source/target distance, faction cooldown, reload, and poisoned-state
normalization. With Developer Tools and Allow Destructive Tests enabled, **Schedule Eligible
Faction Raid Now** invokes this same scheduler without waiting for the calendar gate; it still
requires two real hostile bases and an eligible five-member source faction.

Run `lua tools/test-event-factions.lua .` for the named-faction policy boundary. It verifies all
six stable definitions, defensive catalog copies, world-age/objective constraints, no artificial
combat multipliers, disabled Scavenger boss, future PMC contract role, canonical faction binding,
idempotency/rebind rejection, malformed-save cleanup and no survivor/inventory/duty creation.
This is policy/persistence coverage only; it does not prove a Police/Military/etc. encounter.

Run `lua tools/test-event-entry.lua .` for the named-party entry transaction. It checks bounded
cached-world origins, compact party placement, local-player separation, ordinary persistent
world identities, canonical group/faction ownership, no pre-body itinerary scattering, normal
activation eligibility, idempotent retry, injected mid-batch rollback, world-age policy, and
entry-wait cleanup after a real-state capture. It does not materialize an IsoPlayer or validate
the themed appearance/loadout that later event runtime work must request.

Run `lua tools/test-named-event-runtime.lua .` for the persisted named-event lifecycle. It covers
schedule-without-allocation, world-age/objective validation, due-time one-shot party creation,
atomic event duty, no duplicate retry, local-player entry separation, distinct approach points,
real-position arrival, the bounded common objective, entry-anchor withdrawal, identity/faction
retention, fully stored cohort travel and persisted retry cooldown when no safe origin exists. It
also covers the policy split after withdrawal: Police remains present, while Scientists retain
identity/native records but enter two-phase pending/complete departure, stop activation/offscreen
simulation and leave only a historical empty faction after every shell is retired.

Run `lua tools/test-survivor-capabilities.lua .`, `lua tools/test-survivor-starting-gear.lua .`
and `lua tools/test-event-entry.lua .` for Police first materialization. Together they verify the
canonical event-policy lookup, real `base:policeofficer` selection with balanced vanilla points,
native Police starter items, and protection against rewriting an existing persisted profile.

Run `lua tools/test-character-appearance.lua .`, `lua tools/test-survivor-capabilities.lua .`,
`lua tools/test-survivor-starting-gear.lua .`, `lua tools/test-event-factions.lua .` and
`lua tools/test-named-event-runtime.lua .` for Scientist first materialization. They verify the
real balanced `base:doctor` profession, native clothing application with the real lab coat item,
the ordinary clipboard/pen/scalpel field kit, canonical policy propagation and one-time event
identity. These checks do not claim research simulation or a completed Scientist feature.

The same focused set covers Military first materialization: real balanced `base:veteran`, four
real army clothing items, and a restrained M9 kit with one compatible `Base.9mmClip` and exactly
three native five-round `Base.Bullets9mm` stacks. For a live gate on a disposable day-14-or-later
save, choose **Schedule Military Exit Test Here**. Verify three entrants materialize with stable
identity/gear, use the existing native reload/firearm path rather than appearing with fabricated
loaded state, execute the bounded secure-area objective, and depart through the existing event-only
lifecycle. Save/reload must not duplicate clothing, firearms, magazines or ammunition.

For the Scavenger real-loot gate, use a disposable day-7-or-later save and choose **Schedule
Scavenger Search Here** on a loaded square near several ordinary world containers. Three persistent
Scavengers should enter, search only the bounded nearby area through existing looting behavior,
and withdraw after six completed transfers, three exhausted searches per member, or two in-game
hours. Inspect their real inventories: only items physically transferred from real containers may
be retained. Empty/no-op transfers, containers outside 18 tiles and other survivors' inventories
must not count. Save/reload during the objective and verify receipt/item identity is not duplicated.

Live named-entry gate: on a disposable day-one-or-later save, enable **Developer Tools** and
**Allow Destructive Tests**, then right-click a loaded ground square and choose **Schedule Police
Entry Here**. The feed should report one event ID. Confirm three Police identities enter from a
believable offscreen anchor rather than beside the player, approach distinct nearby positions,
remain ordinary neutral survivors during the initial bounded objective, withdraw toward that same
anchor, and keep one identity/faction record each after save/reload. Inspect
`[KnoxSurvivors][Events]` for `spawning`, `active`, and `completed`; no phase may create a second
party. On first appearance, Police members should use recognizable ordinary Build 42 Police
clothing, own/equip a nightstick and carry a Police walkie-talkie. Save/reload must preserve the
same profession, clothing and items without issuing a second kit. Automatic Police triggers,
disposition behavior and the `assist` objective are not part of this gate. For `secure_area`, place
a small number of zombies inside 18 tiles of the selected target. Police must remain on objective
while a living threat remains, fight only through common combat behavior, then withdraw after the
area stays clear for roughly three in-game minutes. Reload during that clear window and confirm the
event neither completes twice nor invents a cleared result.

Event-only departure live gate: on a disposable day-14-or-later save with **Developer Tools** and
**Allow Destructive Tests** enabled, right-click a loaded ground square and choose **Schedule
Scientists Exit Test Here**. Keep at least one member loaded through its return. A survivor must
not disappear before reaching the saved entry anchor. At the anchor, the
loaded shell must capture/remove once, the event must wait for every member, and no corpse may be
created. Save/reload afterward and revisit the area: departed identities must not materialize again
or count toward living world population. Repeat while killing one withdrawing member; that member
must use the ordinary death/corpse path while surviving members depart normally. Inspect autonomy
logs for one `state=DEPARTED` per surviving loaded member and no repeated removal, restore or event
completion loop. On first materialization, confirm the entrants retain the same medical profession,
lab coat and ordinary field items after save/reload without receiving duplicate equipment.

This is not an end-to-end raid scenario. The runtime can now dispatch explicitly scheduled
plans, but no random scheduler is enabled. Do not manually advance phases and describe
that as a successful live raid. `lua tools/test-event-runtime.lua .` additionally runs
the real persistence, event runtime, controller travel entry point, and unloaded cohort
scheduler over engine fixtures. It covers readiness rejection, all-member duty claims,
base-job exclusion, native movement requests, stable projection, combat interruption,
reload, actual-position arrival, loaded/stored return, cooldown retention, shared fatigue,
mixed-loaded waiting, casualties, malformed roster recovery, and lost-home cleanup.

Pending live dispatch gate: use five equipped residents of an established hostile faction
and an existing target base. Explicitly schedule its proposal through `KnoxEvents.scheduleRaid`
or the developer context command. Verify only the selected party leaves, native movement/obstacles
and group regrouping work, combat/self-care can interrupt it, the same IDs and gear persist
across hibernation/reload, and withdrawal returns/releases survivors without duplication.
Inspect `[KnoxSurvivors][Events]` transitions; timers must not claim combat victories.
Automatic scheduling and real supply objectives are implemented but not live-proven and must
not be presented as a release-ready raid feature. No substitute NPCs or free equipment are permitted.

### 2026-09-19 combat, hauling, settlement and HUD replay

Run `powershell -ExecutionPolicy Bypass -File tools/verify.ps1` before the live replay. In a
disposable save, verify these native behavior boundaries:

1. Give one armed and one unarmed survivor several standing zombies. The armed survivor should
   swing; the unarmed survivor should shove. Equip a loaded gun and confirm repeated shots create
   normal projectiles, impacts, sound, ammunition use and reload actions instead of entering shove.
2. Knock a hostile survivor down. Their controller must wait for Build 42's native get-up graph;
   combat must not clear the floor state immediately.
3. Order a resident to haul a corpse around a corner into its drop area. The backward-drag
   animation must move toward the chosen destination, finish once, and release the corpse.
4. Attack a neutral until they become hostile near defensive companions and residents. Owned
   allies should acquire that hostile human while friendly/allied humans remain protected.
5. Put a zombie directly across a fence or wall edge. The survivor should hold/ignore it until the
   barrier no longer separates them instead of walking continuously into the obstruction.
6. Let a travelling faction claim a base. Its leader and followers should leave their temporary
   travel formation, receive resident duty immediately, and begin a job or bounded base-life choice.
7. Leave residents idle with chairs and readable books. They should alternate bounded yard/room
   movement, native rest/reading and sparse relevant thoughts without synchronized pacing or spam.
8. Bleed beside an idle owned survivor carrying a usable bandage. With **Survivors Bandage Their
   Player** enabled, they should approach and use the native aid action; disabling it should stop
   player treatment.
9. Compare the compact companion HUD with the Knox survivor card. `H/F/W/R` mean Health, Food,
   Water and Rest remaining; the card uses the same higher-is-better values.

Offline verification proves decision boundaries, compilation and fixtures. Projectile visuals,
native drag direction, get-up timing, real pathfinding and UI readability remain live acceptance.

### Base-job completion authority live replay

In a disposable Build 42 save, let a resident complete one real-resource base
job and verify that the native world result, task-board state, resident
completion feedback, released reservations, and next useful activity agree.
Repeat with the job claim reassigned/revoked while the native action is in
progress or immediately before controller completion. The physical effect may
already exist, but Knox must not report the stale task as accepted or retain
the old resident's transient supply lease. Save/reload and verify the task and
claim remain owned only by the authoritative board. Offline regression
`test-base-task-validation.lua` covers board acceptance/rejection, diagnostics,
pacing, local cleanup and feedback; it does not prove native action timing,
world result, save/reload, or live arbitration.

### Base supply ownership past the loaded lease

In a disposable Build 42 save, start a real base shortage trip and leave it
searching or returning for longer than 1.5 in-game hours while another willing
resident is available. The second resident must not start a duplicate trip;
the original run must retain ownership through unload/reload and terminate only
after the existing truthful outcome path (including native storage receipt
when carrying a real item). Confirm the shortage is reassessed after completion.
Offline `test-base-auto-scavenge.lua` advances beyond lease expiry while the
persisted active run remains and verifies that no helper run is elected. It
does not prove Build 42 scheduling, real pickup/deposit, or save/reload.

### Loaded social memory and later recount

In a disposable Build 42 save, let two loaded survivors complete a cautious
greeting, a decline, a group join (and a rejected join), then test a persisted
hostile disposition. Confirm each participant's Survivor Card/history and later
dialogue recount reflect only the resolved outcome after save/reload. Interrupt
one approach and one greeting before finalization and confirm neither creates a
completed encounter memory. A hostile memory must not claim a fight or robbery
unless those native outcomes separately occurred. Offline coverage is in
`test-human-encounters.lua`, `test-offscreen-stories.lua`,
`test-offscreen-recount.lua`, and `test-relationship-coherence.lua`; these
fixtures do not prove native encounter timing, persistence, speech, or UI.

For a successful faction recruitment, let a loaded faction leader complete the
join encounter with an eligible independent. Verify the canonical faction and
travel-group roster both contain the same survivor, faction affiliation and
home-base duty are correct, and the survivor receives the existing runtime
duty update. On the next group-coordination pass verify the persisted leader
and current formation are reflected without duplicate membership. Save/reload
and confirm the same identity, group, faction, base duty, and leadership remain.
The offline faction-persistence fixture also exercises a rejected lifecycle
admission and confirms it cannot leave partial group/faction/alliance state;
native encounter, movement, and save/reload remain live-only.

For the offscreen-to-loaded handoff, preserve a disposable pair with a real
offscreen `pendingMeet` in both canonical survivor ledgers, then bring both
survivors into loaded contact. Interrupt the first approach with immediate
danger or an explicit activity change; confirm neither ledger loses the intent
and no completed memory/disposition is invented. After the interruption clears,
allow the same pair to meet again and finalize the forced outcome. Confirm both
matching intents clear only after acceptance, the expected real loaded result
occurs, and memory/dialogue appear after save/reload. Repeat with an intent older
than 72 game hours and confirm it no longer forces an encounter. Combat, robbery
transfer, native approach, and save/reload remain separate evidence; an
offscreen `rob` intent does not prove successful theft.

### Faction-owned base shortage response

In a disposable Build 42 save, establish a faction-owned base with an assigned
real-storage shortage and at least one ordinary resident whose persisted
faction ID matches the base. Include a specialized resident, a wrong-faction
resident, and an active generic group-sortie pair where practical. Confirm the
matching available resident is elected only for the base's actual shortage,
while specialized/wrong-faction residents and current sortie owners are not
double assigned. Observe real item pickup, return, native deposit, shortage
reassessment, and save/reload while returning with supplies. Player-owned base
residents must retain the existing explicit loot-run opt-in rule. Offline
`test-base-auto-scavenge.lua` and `test-group-scavenge.lua` cover election
eligibility and sortie exclusion; supply planner/routing fixtures cover the
existing offline-owned path. They do not prove native faction scheduling,
movement, transfer/capacity, reassessment, or save/reload.

### Base resident threat retreat and duty resumption

In a disposable Build 42 save, start with one base resident on a real claimed
work task and another carrying a real shortage item on an active return run.
First expose healthy equipped residents to one zombie and a small group; confirm
they hold/fight under the existing thresholds when danger is not overwhelming.
Then expose a resident with immediate overwhelming pressure and a genuinely
viable escape lane. Confirm one native retreat route starts, ordinary work
action/transfer reservations are interrupted, the same task claim or durable
supply run remains owned, and the resident does not return until the existing
safe-scan rule clears. Verify the task resumes through base arbitration or the
carrier returns to native storage, receives confirmed deposit, and triggers
shortage reassessment. Repeat while a faction pair is on a group sortie to
confirm both members respond coherently without duplicate route requests or a
stale outing. Save/reload once during a supply-bearing retreat and compare
identity, active run, carried item and duty. Offline
`test-combat-intelligence.lua` covers admission/claim/lease preservation and
safe-scan boundaries; it does not prove native pathing, combat, item transfer,
group cohesion, or persistence.

### Automatic equipment preference

On a disposable Build 42 save, inspect a player-owned companion and a
player-owned base resident with a clearly inferior equipped weapon and better
real weapon/clothing/bag items in inventory. Verify the default-enabled policy
upgrades only through the existing native owned-item actions while idle and
after a real loot transfer. Disable automatic upgrades, repeat both cases, and
confirm the current equipment remains unchanged. Then explicitly equip an item
through inventory controls and enter combat requiring a suitable weapon; those
paths must still work while automatic upgrades are disabled. Re-enable the
policy and save/reload; verify it persists and the normal automatic reevaluation
resumes. Offline coverage in `test-weapon-preferences.lua`,
`test-companion-sync-cache.lua`, and `test-equipment-intelligence.lua` proves
the policy default, persistence representation, sync, and gate under fixtures;
it does not prove native equip/wear, inventory action ownership, combat, or
save/reload.
## Owned-survivor map grouping — BUG-KS-021

On a disposable Build 42 save, open the world map with one owned survivor and
verify the existing individual marker. Move a second owned survivor within 20
world tiles on the same floor and confirm one grouped marker shows both names
and that one is loaded/unloaded as appropriate. Move them beyond 20 tiles and
confirm individual markers return; repeat across floors to confirm those stay
separate. Move survivors while the map is open and verify groups recompute.
Change ownership, unload/rematerialize, save/reload, and kill a survivor;
confirm stale groups disappear or rebuild from current authoritative locations,
persisted logical coordinates are distinguished from loaded positions, and
death evidence stays an individual marker. Check an owner with
no valid coordinates receives only the unavailable-location notice, with no
marker at a fabricated position. Confirm native map projection, zoom/pan,
right-click tools, and marker text remain usable. The current owned-marker
overlay has no click-to-open individual detail path; names remain visible on
the grouped label and no new click owner is introduced here. Offline tests do
not establish native projection, appearance, hit testing, or save/reload
behavior.

## Base-work preferences — BUG-KS-023

In a disposable Build 42 save, select a player-owned base resident in the
Survivor Notebook Crew tab. Confirm each currently selector-backed group
(guard, patrol, repair, cooking, farming, woodwork, barricade, and hauling)
shows and cycles High, Normal, Low, Disabled. Confirm active companions have no
effective preference controls while on companion duty. Compare two otherwise
equal queued real tasks with different categories under each preference and
confirm High wins an equal choice, Normal is the default, Low remains eligible
but loses equal choices, and Disabled blocks a new autonomous selection.
Confirm materially higher-priority/urgent work, needs, danger/combat, explicit
player task assignments, traversal, and an active supply delivery retain their
existing arbitration and are not suppressed by preferences.

Start an ambient organizer native action, change Hauling to Disabled, and
confirm the action and its item/container reservations finish or fail through
their existing owner without being cancelled by the preference change; verify
no new organizer round begins afterward. Assign a recruited companion to base
duty and confirm its saved preference now affects the base selector, then
return it to companion duty and confirm ordinary follow/hold/directive behavior
remains unchanged. Save/reload with non-Normal preferences and confirm the
states persist. Confirm an older save with no map reads as Normal and old
1–4/false values migrate safely. Offline preference, selector, task-board,
companion/base conversion, organizer, needs, and persistence tests do not prove
the rendered Notebook UI, native work action, live interruption/resumption, or
Build 42 save/reload.

## Active companion party food scavenging — KS-PROD-008

Offline scope is implemented: the existing per-companion in-game Auto-Loot
permission admits one safe-food pickup for a player-owned companion only when
settled in Follow with no actionable need, threat,
combat, active supply, or explicit directive. The loaded, same-floor search is
limited to 12 tiles from both actors; the player movement leash is 3 tiles.
The existing controller, loot planner, transient item/container reservations,
native route/transfer actions, and exact inventory receipt own the loop. An
unfinished route releases its leases and returns to ordinary Follow if the
player moves, the anchor becomes unusable, a need interrupts, or Auto-Loot is
disabled in game. Changing Auto-Loot does not cancel an already queued native
transfer; it counts only after the exact item appears in the companion's
inventory. Combat or a direct order may interrupt through the existing owner.
The item stays with the companion. No work intent or claim is persisted, so
reload restores normal autonomy. The old `AllowCompanionPartyScavenging`
Sandbox key is retired and ignored; missing per-companion Auto-Loot values
retain their existing enabled default. Focused
coverage lives in ignored local `tools/test-autonomy-formation.lua`,
`tools/test-survivor-looting.lua`, and `tools/test-sandbox-settings.lua`.

Build 42 acceptance remains open. On a disposable save, enable Auto-Loot for
one owned companion in game, leave it in Follow with the player
stationary, and place one safe food item in a loaded same-floor container
within 12 tiles of both. Confirm one real item transfers into companion
inventory, no extra items are taken, and the companion returns to formation.
Repeat with unsafe/no food, full inventory capacity, and inaccessible
containers; there must be no false success or wandering. Move the player more
than three tiles during approach, trigger an urgent need and a zombie threat,
issue a direct order, traverse a door/window, and start destination travel;
confirm existing owners interrupt or outrank the unfinished route and leases
are released. Turn Auto-Loot off during approach (route should cancel) and
during a native transfer (the action may finish, with exact receipt required).
While the transfer is queued, issue a direct order and confirm it takes
ownership through directive interruption and releases its lease.
Repeat disabled, with NPC faction residents, with a base-resident companion,
and after save/reload. Native movement, transfer timing, item weight/capacity,
and save/reload are not proven by offline fixtures. Water, woodcutting, base
work, offscreen work, and companion-to-player delivery are outside this slice.
The retired Sandbox key is ignored; vary only each companion's in-game Auto-Loot
permission during this replay.

## Staged base-life / Notebook stabilization — BUG-KS-013

The 2026-09-29 staged Build 42 observation reported residents mostly idle or
relocating without useful work and Work/Schedule controls without an obvious
result. Offline fixes now route Notebook writes to the selected owned base and
keep the selected resident's details synchronized after refresh. This replay
checks those UI connections before the existing full-day acceptance; it does
not treat the offline base-life tests as proof of native work.

### Short Notebook context/save replay

1. Use a disposable save with two player-owned bases and at least one living
   resident assigned to the non-primary base. Open the Notebook, select that
   base, then open **Crew & Schedule** and select its resident.
2. Confirm the resident name is shown, work controls are enabled, and the
   current schedule/task summary belongs to that resident. Leave the page open
   through at least two automatic refreshes; the selected row and detail must
   stay aligned.
3. Change one work category, paint a schedule window, save it, close the
   Notebook, and reopen it. Confirm the save feedback appeared and both values
   reappear for the same resident/base. Repeat with the primary base and verify
   an active companion or foreign/non-resident row cannot change those values.
4. Change the selected resident to a second base resident and wait for refresh;
   verify the controls change to that resident and do not silently write the
   previous resident.

### Schedule color and input replay — KS-PROD-008 Slice J

For one player-owned base resident, open **Crew & Schedule** and confirm the
resident name, `NOW` hour/assignment, selected paint tool, and short save status
are visible without the former instructional paragraph. Select **Work**, paint
two hours, then select **Patrol** and repaint one of them. Each cell should
change immediately to the corresponding color while keeping its 24-hour label;
the real current hour should have the yellow outline and `*`. Save, wait for
the saved status, close/reopen the Notebook, and confirm colors/assignments
return for the same resident. Switch residents and verify the name/current
assignment follows selection. Check mouse and joypad operation at normal and
small/split-screen resolutions with enlarged UI fonts; scroll to all controls.
Confirm active companions/non-base records cannot edit a base schedule and
that work/duty behavior did not change. Offline tests cover drawing, transforms,
owner routing, and layout decisions, not Build 42 rendering or device input.

### Full-day base-life replay

With two or more player base residents in a safe loaded base, leave the Notebook
through one in-game day. Record each resident's identity, assigned base,
schedule, current visible activity, and periodic **Write Survivor Status to
Log** snapshot. Provide the real prerequisites for at least one supported job;
verify task discovery/claim, route start, native action, authoritative result,
cleanup, and next arbitration. Repeat with missing material or unreachable
work and verify an honest blocked/deferred state. Interrupt one active job with
an urgent need or threat and confirm normal resumption/reassessment. At the
first mismatch between the UI, persisted duty, runtime decision, task claim,
movement, native action, and verified world result, capture that exact snapshot
and only the corresponding short DebugLog slice. Native pathing/actions,
visible productivity, and full-day behavior remain live acceptance.

### Generic loot receipt honesty — Build 42 acceptance (`BUG-KS-015`)

On a disposable save, order one survivor to loot a container with one clothing,
medicine, or weapon item. Record the exact item identity and inventory count
before the action; verify the native transfer, resulting inventory receipt, and
completion message agree. Repeat with the transfer refused and with a multi-item
selection where only one item transfers. Refusal/partial receipt must not report
`loot-complete`; it must report a bounded failure, release item/container
reservations, cool the source, and permit later arbitration without duplicating
or deleting any real item. Save/reload after a successful and a failed attempt.
Offline tests exercise receipt logic and cleanup only; native queue acceptance,
inventory mutation, timing, and save/reload remain unverified.

### BUG-KS-040 companion startup exception replay

After the corrected local mod is staged, load the same save and let an owned
companion settle into follow with a threat map present (one nearby zombie is
sufficient). Check the first 2–3 seconds of the new DebugLog for
`controller_tick`/`think` exceptions; confirm threat awareness still blocks
optional party scavenging. Exercise reservation release once and confirm no
exception or stale threat lease. Record game build, loaded mod root, and exact
log timestamp. The prior failure was recorded twice at frames 166 and 196 in
`2026-09-30_02-40_DebugLog.txt`; offline checks do not close this replay.

### BUG-KS-041 Notebook work-preference click replay

After staging the corrected source, open **Crew & Schedule** for a player-owned
base resident and click a work category through High, Low, Disabled, and Normal.
Confirm each click gives the expected saved feedback without a Lua exception,
the same resident and selected base remain active, and the value is still
correct after closing and reopening the Notebook. Repeat once after changing
resident selection. Capture only the short DebugLog slice around any failure.
The prior failure was `Object tried to call nil` in `onCrewPriorityCell` at
frame 1875 of `2026-09-30_02-48_DebugLog.txt`, called from vanilla
`ISButton.onMouseUp`; the offline regression now runs this callback with global
`next` unavailable. Passing this UI replay does not close BUG-KS-013: separately
verify one real supplied base task, one missing-resource case, and full-day
resident activity through native movement/action and reassessment.

### BUG-KS-042 selected outpost Notebook acceptance

With at least a home base and Outpost 2 owned by the same player, open Base &
Work and select Outpost 2. Verify the label and displayed work areas, queue,
residents, and storage all belong to Outpost 2. Edit a boundary, add a work
area, and remove that work area; each operation must target Outpost 2 and leave
the home base unchanged. Switch back to Home and verify its data is unchanged.
Close/reopen the Notebook, then save/reload and repeat the selection check.
The offline fixture executes the actual picker and area-action callbacks and
proves selected-ID routing only; it does not prove Build 42 combo rendering,
input, screen refresh, or persistence behavior.

### BUG-KS-043 appliance power-loss cooking acceptance

In a disposable base, test a powered non-microwave stove/oven with a valid
real ingredient and record appliance power, temperature, item identity, action
queue, and task result. Remove power before selection, then repeat after a
cooking task has been selected but before its native heat action begins. A
cold unpowered appliance must not be newly selected or report cooking success;
the real ingredient and task claims must remain truthful through failure and
reassessment. Check a stove with positive residual heat and a fuel-backed
appliance separately: the offline guard preserves current heat, but native fuel
semantics are unknown and must not be inferred. Repeat across save/reload and
confirm no stale task or fabricated cooked item. The offline regression proves
only the existing eligibility predicate for powered, hot, and cold/unpowered
fixtures; it does not prove native appliance behavior.

### BUG-KS-044 constrained Base & Work viewport acceptance

Open the Notebook in a short-height or split-screen viewport, then repeat with
an enlarged UI font. On Base & Work, use mouse wheel and joypad navigation to
reach the storage list, lower controls, and final hint. Verify the tab clips
scrolled content at its viewport, each zone/task/storage list scrolls within
its own box, and no controls overlap another section. Resize/reopen and confirm
the content extent remains reachable. Also inspect schedule-hour colors and
labels independently. Offline coverage checks the measured content extent and
existing scroll adapter only; actual Build 42 rendering/input remains open.

### Speech Arrow input-pass-through acceptance

With a nearby off-screen survivor speaking, test right-click/world interaction
and aiming outside the Activity Feed while an arrow is visible, then over the
Feed itself. Repeat with several simultaneous arrows, after indicator expiry,
and with the Feed visible and hidden. Record whether the Feed or Arrow consumed
the input. Offline source and `test-speech-indicators.lua` verify the overlay
requests no mouse events and has no input handlers; only Build 42 can establish
UI-manager propagation and overlap behavior.

### Player-owned base/outpost rename — KS-PROD-008 Slice H

On a disposable Build 42 save with one home and at least one outpost, open Base
& Work, rename Home, then select and rename the outpost. Test leading/trailing
spaces, blank input, a duplicate owned name, and a 33-character name. Confirm
success/error feedback, the selected base remains selected, its displayed name
updates immediately, and the other base remains unchanged. Cancel the dialog
and verify it does not mutate data. Close/reopen the Notebook and save/reload;
confirm both names persist and all base IDs, territories, work areas, tasks,
storage assignments, residents, and duties remain unchanged. Confirm faction
bases do not expose the player rename action. Offline coverage exercises the
actual persistence validator and Notebook callbacks with a text-entry fixture;
it does not prove Build 42 dialog rendering/input or native save/reload.

### BUG-KS-046 — drinking candidate taint-state acceptance

On a disposable Build 42 save, test a real clean bottle, a real tainted bottle,
and a mod/custom fluid whose taint inspection is unavailable. At ordinary thirst,
only verified clean water should be selected. At critical thirst, the existing
policy may select known tainted water and the native action must apply its real
sickness/poison effect. An uninspectable fluid must never be consumed. Confirm
real thirst reduction, remaining fluid quantity, and a partially consumed bottle
across save/reload. Offline fixtures cover classification and decision only;
they do not emulate the native timed action or fluid persistence.

The latest owner test did not complete this clean/tainted/unknown-water matrix;
native behavior remains provisionally unconfirmed/live-pending.

### KS-PROD-008 Slice K — loaded native water-object drinking

Offline `test-survivor-needs.lua` and `test-autonomy-water-source.lua` cover
known clean water; tainted water at ordinary versus critical thirst; unknown
taint; empty source rejection and depletion-to-zero completion; source within
12 tiles/same floor versus beyond range; base/camp boundary; unreachable
approach; source contention; explicit follow interruption; native queue/full
inventory refusal; source reservation release; and the required joint real
thirst/source result check. They use fixtures and do not prove PZ behavior.

Build 42 replay, using disposable saves and real sinks, rain collectors or
another vanilla water object:

1. Place a player-owned base resident and a faction/base resident inside their
   respective base/camp boundary. Give each urgent thirst, no carried water,
   and a reachable known-clean native source within 12 tiles on the same floor.
   Verify it selects the source, reaches an adjacent tile, uses the native
   drink action, thirst falls, and the source amount decreases.
2. Repeat with a source outside 12 tiles, on another floor, outside the owned
   boundary, unloaded, empty, and uninspectable. Each must be ignored without
   drinking or changing source/thirst state.
3. At ordinary thirst, verify known-tainted source is rejected. At critical
   thirst, verify vanilla action may drink it and record actual native
   sickness/poison consequences. Do not call a mock or selection result a pass.
4. Test carried bottle, assigned base-storage bottle, and a searchable loaded
   world container with water item to ensure these existing real-item paths
   still precede/follow the new source path correctly. Bottle filling from an
   object is not included.
5. Test full inventory and native action refusal. Confirm no items are dropped,
   transferred, fabricated, or removed by Knox; source lease releases and the
   failure/backoff is truthful.
6. Interrupt approach and action with a zombie, explicit order, group travel,
   and a higher-priority injury. Confirm water reservation cleanup and normal
   arbitration/task resumption.
7. Use two residents targeting one source: the exact transient lease must
   prevent duplicate simultaneous targeting, expire through cleanup, and never
   persist. Save/reload with partially consumed native source and survivor
   identity/thirst; verify native state and normal need reassessment.

No Build 42 replay was performed in the implementation session. Native
`ISTakeWaterAction`, source depletion, actual thirst and sickness effects,
full-inventory refusal, movement/reachability, contention, and save/reload
remain live-pending. The implementation does not consume map water offscreen or
write fluid/thirst values. Bottle filling is a separate later package.

### Couch/table stand-up recovery — `BUG-KS-013` adjacent live report

Use a disposable Build 42 save in a safe loaded room. Place a couch with a
table directly in its forward exit area, plus nearby alternative clear tiles.
Record the resident's exact square and furniture object before sitting. Allow
the native sit/rest action to begin and complete, then observe one ordinary
stand-up and one threat interruption; repeat the interruption case with an
explicit player order. Check whether the engine stands the resident into the
table, whether Knox reports a state/route failure, and whether the resident can
recover through normal native movement without clipping or teleporting. Repeat
with adjacent tiles blocked, no valid nearby exit, a wall/door edge, and a
counter or other furniture instead of the table. Save/reload once while seated
and once after recovery; confirm identity, orders, duties, needs, and rest-spot
reservation cleanup. Capture before/after XYZ, sitting state, controller
state/decision/failure, and only the short DebugLog slice for the attempted
stand. Source review found no Knox-owned stand-position logic; do not classify
this as fixed unless reproduction identifies a Knox continuation failure.

### Filtered ground-storage design gate — no placement implementation yet

The existing `KnoxInventoryActions.queueDrop` path creates an `ItemContainer`
of type `floor` and delegates to native `ISInventoryTransferAction`. In the
locally installed Build 42 script, `getNotFullFloorSquare()` checks the actor's
current square and then neighboring squares; `transferItem()` uses the selected
square. `updateInventoryCleanup` verifies source removal and that
`item:getWorldItem()` is non-nil, but not exact destination-square identity or
an inverse rollback. The existing drop path is not evidence that zone
placement is safe.

Proposed smallest slice, still requiring native API confirmation and an approved
work item:

- Limit the first version to player-owned bases/outposts. Persist each bounded
  rectangular zone under its canonical base ID, one floor per zone, and enforce
  the existing base-territory boundary at selection and transfer time. No
  shared or inferred cross-base destination.
- One zone has one existing storage category. Reuse
  `KnoxBaseStorage.classifyItem`; it returns one canonical category and gives
  Tools precedence over Weapons. Unknown/miscellaneous items match General
  only. Do not introduce custom overlapping item predicates.
- Reject overlapping ground-storage rectangles to keep one deterministic
  destination owner. Existing exclusive work areas remain non-overlapping;
  decide whether guard/patrol overlays may share the rectangle only after
  checking player clarity and controller behavior.
- Preserve the current assigned-container ranking, typed overflow and General
  fallback first. Ground placement is considered only if no currently valid
  assigned container accepts the real item. Among ground zones, exact category
  precedes General; then use configured zone priority, distance, and stable
  zone ID as deterministic tie-breakers. A zone's priority must not make it
  outrank an eligible real container.
- Cap the first placement zone at 256 squares. Move only one already-carried
  real item per work cycle; do not scan or collect loose world items in this
  slice. The roadmap's 32 candidate/10-minute scan caps apply only if a later,
  separately scoped loose-item collection slice is approved. These are proposed
  limits, not measured Build 42 performance.
- Keep ground items as native world items. A resident must reach a valid loaded
  tile in the owning zone; native transfer must prove the exact item instance
  at the exact destination square. Refusal/interruption must either leave the
  item with its prior owner or use a proven native return transfer before
  claiming recovery. No abstract counts, item recreation, teleport, or
  `worldItem`-only receipt.
- Revalidate selected base ID, territory, zone revision/bounds, item owner,
  filter, reservations, and destination immediately before action. Relocation
  or zone removal must use existing persistence/task cleanup; no separate
marker, zone, or item ledger.

Before coding, verify Build 42 floor-container lookup, target-square transfer,
item identity/receipt and rollback under success, refusal, partial transfer,
capacity/blocked square, and interruption. Live acceptance must also cover
same-base and multi-base/outpost routing, zone edits/removal, filter overlap,
save/reload, and UI clarity. A later loose-world-item collection feature must
separately test its search scan caps, reserved/job-required-item exclusions,
pickup receipt, and retry. Existing assigned-container storage remains the
only implemented destination until this evidence and an implementation owner
are approved.

## 2026-09-30 interaction shortcut and schedule-stroke acceptance

### Nearby survivor interaction

Use a disposable Build 42 save with one visible survivor at normal conversation
range. Confirm the prompt displays the configured Knox key (F by default), the
panel opens without an `ISUI3DModel:setState` Lua error, and a key remapped in
Options → Controls is both displayed and honored. Confirm the native Interact
and controller/context route remains usable. Repeat while aiming, in a vehicle,
outside range, with a modal open, and while another UI owns the pointer; none
should open the panel. With the prompt visible, test left/right click, aiming,
normal world interaction, and Activity Feed overlap. The prompt must not capture
input; the panel must retain its ordinary mouse/joypad behavior. Check for no
repeat portrait exception in the short DebugLog slice. F shares the default
vehicle-headlight key; verify its existing behavior while inside a vehicle.

### Crew & Schedule paint gesture

Select a named base resident and record the selected paint tool. Click one hour,
then hold left mouse on another cell and drag across at least three cells. Only
visited cells should receive the selected color/state; release stops painting.
Repeat after changing the tool, with a scroll gesture during a held stroke, and
release outside the hour grid. Change selected resident before starting the
next stroke and confirm saved/draft values remain separate. Save, close/reopen
Notebook, and verify the colors/state persist. Repeat at the smallest supported
viewport/enlarged UI scale and with joypad navigation; wheel scrolling and
unrelated controls must remain usable. Offline tests do not establish native
color rendering or event propagation.

## 2026-09-30 multi-window and away-from-base acceptance

### Ordered barricade sequence (BUG-KS-020)

Offline continuation coverage lives in ignored/local
`tools/test-manual-barricade-order.lua`: it exercises automatic jobs disabled,
per-target claims, second-target selection, retry deadline, cancellation, and
ineligible ordinary work. This does not prove persisted task serialization or
Build 42 action continuation; the replay below remains required.

On a disposable owned base containing two unbarricaded windows in one building,
set autonomous jobs off, right-click the building and order barricading. Record queued task IDs, target
coordinates, resident, claim, carried/planned hammer/planks/nails. Allow the
first vanilla action to finish; verify its actual world result, claim cleanup,
and selection of the second target without a duplicate task or repeated first
opening. Verify the explicit order continues through the existing task board
despite autonomous jobs being disabled. Cancel a queued later window in the
Notebook and confirm it is skipped; interrupt with danger/order and confirm the
same claim resumes; trigger one bounded failure and verify its retry deadline
before retry; then save/reload while another target is queued and confirm the
remaining manual-order task is still eligible. Repeat with windows on multiple
floors if `findTargetsInBuilding` returns them, no materials, and a target
secured by the player during travel. No task should report success without
native verification. Offline coverage proves task-board continuation only,
not native work or save behavior. Metal-sheet installation has only a partial
validation branch in the barricade adapter; no metal work task or result receipt
is implemented. Verify the installed Build 42 metal-action contract and target
result separately before scoping that feature.

### Base-life farming failure capture (BUG-KS-013)

Use one isolated assigned farming tile and one resident shell. Record resident
ID/body type, base and schedule, zone bounds, task ID/type/target, persisted
claim owner, carried real tool/seed/water, `ISTimedActionQueue` and character
action queue before/after, and the plant's `CFarmingSystem` Lua-object state.
Exercise plow, seed, and water separately; compare an equivalent action by the
local player. A drained action queue is not a result: record whether the native
plant state actually changed. Correlate `receiveGlobalObjects: player is null`
messages with the exact action but do not assume causality. Then run one
supplied non-farming task and one missing-resource task; trace selection,
claim, route, action, failure/retry, and reassessment. Verify failed work is
shown as blocked with its reason, claims are released/backed off correctly, and
the resident chooses another valid activity. This is a live/native replay; the
offline tests do not prove Build 42 farming support on `KnoxIsoPlayerShell`.

Source audit note (2026-09-30): Knox has no registration or invocation of
`receiveGlobalObjects`; its farming module reads the farming singleton and
queues vanilla actions. The warning is therefore not currently attributable to
a Knox callback. On replay, capture the exact local-player versus survivor-shell
action and global-object warning timing alongside native crop state. Do not add
a guard or count a drained action queue as success without identifying a
Knox-owned divergence.

### Metal-sheet barricade readiness (deferred feature)

The installed Build 42 `ISBarricadeAction.lua` exposes metal mode through
`ISBarricadeAction:new(character, targetObject, true, false)`. It requires an
unbarricaded `BarricadeAble`, equipped `BlowTorch` and `SheetMetal`; its native
completion path consumes the sheet, attaches it with `addMetal`, and transmits
the barricade. The base timed action resets its queue on stop. Knox currently
queues wood mode and verifies plank count, so a Knox metal-work regression does
not yet exist. Before implementation, settle whether the player-facing task is
metal barricading of eligible openings or a narrower target policy. Then test
real tool/sheet acquisition, claim/reservation cleanup, native result
verification, interruption, unavailable target/material, retry, and
save/reload in Build 42. This source inspection establishes the script contract,
not live survivor-shell execution or resource synchronization.

### Natural behavior away from a base

Record each survivor's identity/type, location/floor, group/faction, player
order, needs/moodles, threat, formation, route/state, active task, and recent
activity. Observe one independent/group survivor and one player companion away
from base in a safe loaded area, then repeat with danger, an urgent need, and an
explicit order. Distinguish purposeful roam/exploration, follower/relax duty,
needs or recovery pauses, and native movement stalls. Do not use animation alone
as evidence of useful behavior. If the same no-progress state repeats, capture
the smallest correlated DebugLog slice and current status before changing
arbitration.

### 2026-09-30 interaction/UI stabilization replay

On a disposable Build 42 save, verify the nearby prompt is minimal, legible,
translucent, explicitly says `Press F to talk to [name]` (and reflects a
remapped binding), and does not overlap
vanilla panels or capture world input. Open the shared interaction panel, use
Talk, and confirm ordinary wandering is suppressed while the conversation is
open; close it and confirm normal arbitration resumes. Repeat with trade open,
then test threat, urgent need, native action, cancellation, and moving out of
range. Existing conversation/trade range thresholds were not changed.

Show and hide the Activity Feed with its close control, existing context-menu
toggle, and `ShowActivityFeed` Sandbox option. Confirm the seven most recent
events are still available after hiding/reopening, hidden display does not
block world input, and errors continue to reach logs. With Knox enabled, toggle
`ShowRadialOrders` and confirm only Knox slices disappear/reappear; vanilla
emotes remain, and `ShowLegacyContextCommands` continues independently. Use
mouse and joypad. Verify the Notebook remains accessible from Base management
and Party management; a global vanilla sidebar button remains deferred pending
a supported integration point. For storage, capture the exact clicked object
and every visible menu label if duplicate assignment choices remain; test the
Knox container path across compartments and General/typed categories without
removing legacy settings or saved assignments.

Offline regressions: `test-activity-feed.lua`, `test-radial-orders.lua`,
`test-sandbox-settings.lua`, `test-social-interaction-ui.lua`,
`test-player-conversation.lua`, `test-speech-indicators.lua`,
`test-base-storage-menu.lua`, and
`test-order-menu-callbacks.lua`. The exact current-tree full gate passed 113
Lua sources, 190 scripts, 303 checks, 0 failures (`-SkipJava`); Java was
skipped. These UI mocks do not prove Build 42 rendering, mouse/joypad
propagation, native movement, interaction range, or save compatibility. The
focused scripts are under ignored `tools/` and are local-only Git evidence.

### KS-PROD-011 manual arming and read-only coverage — 2026-09-30

Focused Developer Tools, read-only snapshot, save-isolation, coordinator,
manifest, automated-QA, and PowerShell 7 parser tests passed. The exact
current-tree `tools/verify.ps1 -SkipJava` result and `git diff --check` are
recorded in the production work queue and QA contract. Tests under `tools/` are
ignored by Git and provide local-only evidence. No Build 42 run, Java check,
staging, or Workshop upload was performed. Developer Tools rendering/input,
save identity stability, one-run arming and report output, external disposable
save restore/discard, and all native scenarios remain unverified.

### KS-PROD-011 / BUG-KS-053 — Build 42 Debug Mode loader retest

The latest log showed the game loaded the local Workshop development root at
`C:\Users\Gary\Zomboid\Workshop\KnoxSurvivors\Contents\mods\KnoxSurvivors\42`.
Its legacy QA START line (`save_is_disposable=true`) predates the current
save-identity coordinator. The same launch hit Kahlua's 200-local ceiling;
`KnoxAutonomyController.new` then remained unavailable. Source review found
exactly 200 top-level locals in that controller and one unused helper. The
helper is removed and the source has a regression guard requiring fewer than
200. Updated files were staged to the exact active root and to the separate
local-mod root; both match the repository payload by hash, with the two
intentional Workshop Java agent files preserved.

On the next fresh game launch, verify the first Knox QA START line has
`saveIdentitySource=core.getGameSaveWorld` and `manifestVersion=2`, and that
there is no Kahlua local-index error or `KnoxAutonomyController.new` exception.
If either appears, stop before testing gameplay and preserve the complete
first-error stack slice. Then check the Developer Tools QA submenu on an
ordinary save: it should show `ORDINARY_SAVE`, keep arming unavailable, and
allow only read-only snapshots. Disposable-save arm/start acceptance remains a
separate subsequent replay. Native Debug Mode acceptance is still open.

The next Debug Mode log (`2026-09-30_23-18_DebugLog.txt`) still showed
`Index 200 out of bounds for length 200` after the controller had been reduced
to 199 locals. That initial reduction was insufficient. The current source
moves ten constants to the existing `Controller.TUNING` table, leaving 189
module locals; the focused guard permits at most 190. The same run's QA START
used the current manifest v2 from the Workshop development root, but reported
`saveIdentity=unavailable`; it correctly blocked `QA-ENCOUNTER-001`. Save
identity unavailability is separate from the compiler failure and remains an
open native timing/API question. Recheck both only after restarting with the
new 189-local payload.

The 23:49 log was written before the next source reduction: its Workshop
controller was staged at 23:42 with 189 module locals, while the repository
controller was updated at 23:58. The current controller has 153 top-level
locals, guarded at 160, and its 127-file payload has been recopied and
SHA-256-checked in both the local and active Workshop development paths. Offline
focused checks and full verification pass (116 Lua, 197 regression scripts,
313 checks, 0 failures). `tools/` regressions are ignored/local-only. For the
next replay, start Build 42 fresh, then inspect the new DebugLog for (1) no
`Index 200 out of bounds`, (2) no `KnoxAutonomyController.new` error, and (3)
the current manifest-v2 QA START line. Stop there if either startup error
remains; save identity and disposable-save arming are separate gates.


### BUG-KS-053 — Kahlua controller registration replay (2026-10-01 update)

The 00:25 owner run is the current failure baseline: verify the game loads the
exact staged `KS_SurvivorAutonomyController.lua` hash, then inspect only the
first exception after Lua startup. It showed two Kahlua local-index-200
exceptions in `LexState.new_localvar` and the consequent nil constructor at
`KS_SurvivorAutonomy.lua:309`, even though staged and repository hashes matched.
The source now splits base-task action/result handling into
`Controller:updateBaseTaskAction`; offline lifecycle tests exercise the delegated
path. For the next test, launch Debug Mode once and confirm both error signatures
are absent and controller registration proceeds. Save identity/arming is a separate
QA gate; do not run destructive scenarios until the owner has prepared and armed
a disposable save.


**BUG-KS-053 replay result (2026-10-01):** the owner restarted Build 42 with the
newly staged controller and reported the startup errors gone. This closes only
the startup-loader check for that replay. QA save identity, one-run arming, and
any encounter or gameplay scenario still require their own evidence.


### 2026-10-01 — QA runner retirement

The runtime coordinator and QA-only probe modules were moved to
`dev/qa-harness`, outside the game-loaded mod tree. In-game save arming and its
Sandbox setting are retired. The offline QA harness regressions remain local
developer tests; they do not represent a game menu or require owner setup.


Removal verification (2026-10-01): 14 offline QA fixture files compile from
`dev/qa-harness`; focused removal checks pass. The full verifier passed 102 Lua
sources, 197 regression scripts, 299 checks, 0 failures. Both local and Workshop
development `mod/42` payloads match the repository's 109 files by SHA-256.
Tests in ignored `tools/` remain local-only evidence.

### BUG-KS-054 — Sandbox options parser replay

The corrected source removes unsupported `--` comment lines from `mod/42/media/sandbox-options.txt`; the focused regression requires the Sandbox definition to contain no such comment lines. In Build 42, restart after staging, open the Knox Survivors Sandbox section, and confirm the seven organized pages and their options appear. Check `console.txt` for absence of `CustomSandboxOptions.readFile` / `unknown block type "--"`. A successful parser replay confirms menu availability only; then separately test Auto-Loot behavior and legacy-save compatibility.


### BUG-KS-030 — player and companion vehicle replay (Build 42 pending)

Use a disposable/currently safe save and one owned Follow companion close to a
parked, unlocked vehicle with enough seats. First turn Experimental NPC Driving
off: enter as driver and confirm the companion tries a passenger seat; stop and
exit and confirm the companion tries to exit. Repeat entering as passenger and
confirm the companion uses a passenger seat when no opted-in driver is available.
With the setting on and a running, fueled, unlocked vehicle whose driver seat is
free, enter as passenger and confirm one nearby follower attempts the driver
seat through vanilla actions. On foot, use the companion Orders menu’s “Drive
Nearest Vehicle” and confirm it chooses the nearest loaded usable car, reports a
clear refusal for disabled driving/no usable car, and does not force entry or
create movement. Test no free seats, held/directed companions, distant/floor
separation, threat interruption, leaving before boarding completes, a moving
vehicle, manual get-in/get-out/drive commands, and save/reload identity, roster,
inventory, and orders. Confirm no duplicate survivor bodies. Native animation,
seat assignment, vehicle physics, event timing, control release, and persistence
remain human/live required.

The latest available unarmed-combat log is not a stomp-damage replay: it records
combat admission and changing zombie targets but no attack/hit receipts. For the
owner’s low-damage report, separately record one stomp sequence against a
knocked-down zombie with the survivor identity, target health before/after,
combat action evidence, and elapsed time; do not treat combat-start logs as
proof of hit or damage.

#### BUG-KS-030 locked-seat follow-up

Repeat the player/Follow-companion vehicle test with a parked vehicle whose
passenger door is locked. Observe whether the companion queues and completes
Build 42's native unlock/open/enter/close sequence. If the survivor lacks the
actual key/access, confirm entry is refused cleanly and no passenger lease or
false “boarded” result remains. Also test an unlocked door, a door-open vehicle,
all seats physically occupied, and a removed seat; distinguish each failure
from “no free passenger seat.” The offline test only verifies the action queue
shape, not the game’s native authorization, item transfer, animation, or result.

#### BUG-KS-030 / BUG-KS-041 / BUG-KS-048 — boarding pace and schedule controls

After staging, open Crew & Schedule for a player-owned base resident. Click a
work-preference cell once and cycle it through High, Low, Disabled, and Normal;
confirm the value changes and no `normalizeWorkPreferences` exception appears.
Select Work or another schedule tool and click/drag across several hour cells.
Confirm each fill changes immediately, the current-hour gold outline/star stays
independent of the fill, Save Hours reports success, and closing/reopening keeps
the assignments. A party companion with no base duty remains outside the
preference controls; assign base duty first to test that transition.

Then place a Follow companion beside the player's parked vehicle and enter as
driver. Observe whether the companion jogs through the native seat approach and
returns to normal pace after entering. Repeat with cancellation or an
unavailable seat and confirm the prior movement pace is restored. This replay
is required because offline checks cannot prove native movement speed, button
rendering, or persistence.

Offline result (2026-10-01): the preference normalizer now works with global
`next` absent, schedule and preference buttons enable the vanilla button fill,
and the boarding lease restores the prior native running state. Six focused
work-preference/Notebook/vehicle scripts passed; full verification passed 102
Lua files, 197 scripts, 299 checks, 0 failures. `deployDev` and source/local/
Workshop SHA-256 parity passed (113 source files; two generated agent files are
intentional Workshop extras). This result does not replace the Build 42 replay.

Schedule current-hour follow-up: In a live save at 17:00, open Crew & Schedule for a base resident and verify hour 17, not 12, carries the gold current-hour marker. Paint two distinct hour blocks, click Save Hours and confirm its saved feedback, close and reopen the Notebook, and verify both cell colors remain. Offline evidence: `currentScheduleHour` prefers Build 42 `getGameTime()`, falls back to `GameTime.getInstance()`, and returns nil rather than a false noon when the clock cannot be read; 24-hour persistence conversion is separately round-trip tested. This replay remains required for actual ISButton rendering and save/reopen integration.

Schedule color retention replay: Choose a tool with a distinct color, paint an hour, move focus away and back (or wait for the Notebook refresh), and confirm the assignment color remains. Repeat for a base-work preference cell. Then click Save Hours, close/reopen the Notebook, and confirm the painted assignments remain. The source defect was a stale `ISButton.backgroundColorEnabled` snapshot restored by the native `setEnable()` call; the Notebook now synchronizes visible, hover, and restore-cache colors. Offline test coverage simulates that native cache behavior; Build 42 appearance and durable save/reopen remain mandatory live checks.

Interaction UI replay: Approach a visible survivor and confirm the transparent, text-only prompt says `Press F to talk to [name]`. Turn to aim and confirm the prompt hides while aiming; stop aiming and verify F opens the same nearby target. Repeat while the survivor faces away but remains visible to the player. In the Neutral tab, independent ungrouped survivors may show Trade/Give/Recruit when service rules allow; player companions, faction members, and grouped survivors should not show those entries. Mouse input and native/controller Interact remain usable. Offline tests cover asymmetric sight, matching aim gates, prompt drawing no rectangles/borders, and action filtering. Build 42 visual/input confirmation remains required.
# Survivor command-surface replay — KS-PROD-008 Slice G

In a disposable Build 42 save, leave **Show Knox Orders in Emote Radial** on
and **Show Knox Orders in Right-Click Menus** off (the defaults). Open the
vanilla emote radial beside an owned companion. Navigate Party, Followers,
Residents, and Nearby Survivors; test category opening/back with mouse and
joypad. Confirm follower Movement, Survival, Tactics/permissions, Vehicles,
Gear/Pickup, and Formation; resident Work Preference, Survival/More Supplies,
Resident Policies, Recall, and Cancel Supply Order; nearby Interact opens the
same panel as F. The survivor right-click menu should not add an `Interact
(F)` duplicate or Knox order commands. F remains the talk key; the right-click
choice does not itself open the panel.

With the context option still off, confirm Knox order menus are absent from
survivor, party, resident, clicked-location, and map-driving right-click
surfaces even if radial integration is unavailable. F, Care/View, base
management, storage assignment, and ordinary target interactions should remain.
Then turn the radial option off and context option on; confirm the vanilla
radial remains usable and the right-click order path returns. Turn both off
and confirm both Knox order surfaces are absent. Map point driving orders are
available only through the opted-in context/map route; the emote radial does
not select arbitrary clicked coordinates.

For the nearby interaction panel, confirm Trade/Give/Recruit only appear when
the existing relationship, ownership, and mode eligibility allows them.
Offline tests cover dispatch ownership, scope gates, page navigation,
settings independence, and context hiding. Build 42 visual/input, joypad,
and native action acceptance is still required.

### Starting spouse, survivor search, zombie pursuit, power and UI scrolling — 2026-10-01

On two genuinely fresh saves with **Start with a Spouse** enabled, compare the
spouse name/personality/traits. Reload one save and confirm the same spouse and
identity remain. Then kill the player and create the next character twice: with
**Survivors Continue After Player Death** enabled, confirm the existing spouse
is now a base resident and no second spouse appears; with continuation off,
confirm a genuinely new character follows the normal Start with a Spouse rule.

For item orders, put one real valid medicine, essential tool, weapon upgrade,
clothing item, and ammunition type in searchable nearby containers. Issue each
matching order separately and compare exact inventory identities/counts before
and after; repeat with unavailable items, full inventory, interruption, and a
retry. Do not count a log/function return as a transfer receipt.

For zombie pursuit, compare one ordinary sprinting zombie against the player
and a stationary survivor at the same range/line of sight, with no alternate
target; record target identity, pursuit speed, and behavior after obstruction.
For power, separately test grid power, generator on/off/fuel exhaustion, a
native light switch, television, powered cooking appliance, and gas pump after
grid failure. Record native state and actual item/fuel result before changing
Knox code.

For scroll isolation, scroll each Notebook tab to a distinct offset, switch
between tabs, then scroll over Base & Work's Storage, Tasks, and page whitespace.
Repeat at narrow resolution and in every other Knox panel with lists. Record
which viewport and scroll thumb move. Offline structure has separate view
objects; the owner's reported Build 42 wheel behavior remains unresolved.

The 2026-10-01 screenshot displayed `Storage: 1 assigned`, which is not the
current Notebook text (`filtered | usable containers`). Current source files
have since been copied to the subscribed Workshop folder, but it still contains
11 obsolete QA/probe Lua files. Fully exit the game, disable the Workshop
duplicate, enable the clean local `KnoxSurvivors` mod, and restart before
judging the new scroll fix. Check
the displayed storage summary first; if it still says `assigned`, stop because
the test loaded the stale copy. Then scroll Work Areas, Tasks, Storage, and page
whitespace separately, including a narrow viewport.

The arrow overlay is now explicitly non-capturing after UI registration, with
mouse callbacks returning false. With the current local copy, test right-click,
aiming, and normal world interaction at several screen positions while an
arrow is visible. Repeat with Activity Feed visible and hidden, then after the
arrow expires. Offline tests verify the configured pass-through boundary only;
native UI-manager behavior still needs this replay.

### Sleep orders, faction bed assignment, sprinter pursuit, storage filters

In Build 42, keep a Follow companion under a non-urgent follow order until the
existing fatigue threshold starts sleep. Confirm the survivor reaches the
best available assigned/native bed, actually sleeps, and retains the follow
order for after waking. Repeat with no bed, an occupied bed, a threat during
approach/sleep, a base resident with an assigned bed, and a faction leader plus
member with beds on different floors. Save/reload and unload/rematerialize at
least one survivor; record bed coordinates, duty/order, fatigue, native action,
and actual asleep state. Offline tests only prove arbitration, persisted bed
references, and loaded-bed selection conditions.

For the sprinter report, use one sprinting zombie and compare a stationary
survivor with the player at the same distance and line of sight, ensuring no
alternate target is nearby. Record native target identity, pursuit speed,
obstruction response, and whether a player target changes pursuit. Knox does
not force target selection or sprint speed. Container filters and filtered
ground zones have no live acceptance yet: do not test a four-corner layout as
implemented functionality; it remains a design request gated on exact native
square placement, item receipt, and safe rollback.

### Base & Work scroll containment and container filters — Slice L

In Build 42, open Base & Work and scroll while the pointer is over Work Areas,
Task Queue, and Storage separately. Confirm each list moves inside its own box
without moving a sibling section; scroll over page whitespace and confirm only
the page moves. Repeat in a narrow/split-screen viewport, at larger UI scale,
after switching tabs, and with joypad navigation.

Right-click a real fridge, toolbox/crate, and ordinary container inside Home,
then repeat in Outpost 2. Choose **Set Filters…** and confirm the large list
shows vanilla item `DisplayCategory` checkboxes, Knox convenience categories,
and General Storage. For a single-compartment container, confirm `Set Filters…` is a first-level right-click action; for multi-compartment objects choose the intended compartment first. Select several categories, save, reopen, and verify the
selection and base context survived. Try a filter with a translated native
category and one without a translation. Put matching and nonmatching real
items in the container; verify deposits, supply/need retrieval, task-material
fetch, and chest-to-chest organizing obey the saved filters. Then leave another
eligible container unconfigured: confirm NPCs use matching filters first and
use this real container only as fallback, without Knox changing its name or
capacity. Confirm the organizer moves a real misplaced item toward a matching
filtered container, one item at a time, and does not shuffle between unfiltered
chests. Existing mismatching contents should remain in place after filters
change. Fill or block a destination and verify honest fallback/failure behavior.
Load an older one-role-storage save and confirm existing contents/records remain
until edited. Record item identity/count, filter state, base ID,
claim/reservation, native action result, capacity, and before/after contents.
These are live requirements; offline fixtures do not prove UI rendering,
joypad focus, native transfer, persistence, or capacity behavior.

The 2026-10-01 clarification build was staged with `deployDev` after the
offline gates. All 110 source `mod/42` files match both the local mod and
Workshop `Contents` by SHA-256; Workshop has two generated Knox agent files
extra. This was staging only; no Steam upload or live test occurred.

Do not use the organizer replay as proof that survivors clean floors, remove
trash, or clean a whole house. No house-cleaning order/free-time activity is
implemented yet. Ground `Storage Zone` placement remains deferred until exact
native target-square placement, item receipt, and inverse rollback are proven.

### Container filter click/save and survivor continuity — BUG-KS-056
In Build 42, right-click one real container inside an owned base and select
`Set Filters…`; select one category, save, reopen, then clear it and reopen.
Check that no Lua exception appears and that the filter label persists. Separately
record the player's squad IDs and a base resident in the Notebook before leaving
the area; after re-entering/reloading, compare the visible roster with the
smallest DebugLog slice showing `population status`, `population-activated`, and
any `population-activation-failed` records. Do not infer lost identity from
missing nearby bodies alone; offscreen survivors may be outside the activation
band.

### Survivor needs and faction scheduled sleep — BUG-KS-057

In Build 42, set an NPC faction-base resident's duty schedule to Sleep and let
the sleep window begin. Confirm the resident routes to its assigned reachable
bed when available and enters native sleep; then repeat with an unavailable bed
to observe the supported fallback. Interrupt with a nearby threat and confirm
native wake/recovery plus duty resumption. Save/reload during the sequence and
check identity, faction membership, duty, and bed assignment. Compare with an
independent survivor at night, a traveling group leader/follower, a camp member,
and a player-owned base resident to ensure only the faction scheduled-sleep
route changed. Record actual hunger, thirst, fatigue, inventory supplies,
native sleep/action state, task/order, and post-reload state. Offline tests do
not prove native pathing, bed occupancy, animation, interruption, or persistence.

### Hibernation teardown refusal recovery — BUG-KS-058

Use an isolated Build 42 save only if a supported way exists to make native
`removeNpc` refusal safe and reproducible; do not induce failure by damaging a
player's only save. Record canonical survivor ID, runtime/native identity,
ledger status/revision, lifecycle state, square, controller state, and the
`hibernate-remove-failed`/rollback diagnostics. Confirm a failed removal keeps
the same body, rolls `hibernated` back to `loaded`, and returns the controller
to ordinary arbitration without spawning or registering a second body. Confirm
that a failed persistence rollback stays pending and does not repeat native
removal. Then test normal hibernation, same-ID rematerialization at the saved
logical position, and save/menu boundaries with inventory/equipment, needs,
orders, group/faction membership, and identity continuity. Compare the exact
native body count before and after. Offline fixtures do not prove Build 42
bridge teardown, saved body continuity, or duplicate-body absence.

### Resident rematerialization, storage filters, and radial — BUG-KS-059/060/061

In a copied/test save, record the survivor's canonical ID, party/base duty,
identity, inventory, group/faction membership, and visible native body count.
Load the save and inspect the same survivor in Notebook/map. If the map shows a
logical location but no body, use the existing owner UI to recall a player-owned
base resident to the party; do not create a replacement identity. Confirm the
same ID obtains one native body, then compare inventory, orders, group/faction,
and identity. Capture population activation lines only as supplemental
diagnostics, not as proof that the player observed a body.

For the current `playtest01` reproduction, Stacy Byrd is `ks-world-4`. The
11:47 save still shows player-1 Follow ownership and hibernated/sleeping state
at x=1468,y=7310,z=1 (z=0 is ground level; z=1 is the level above). The
offline fallback now preserves the saved position when a safe square exists;
otherwise an explicit Follow companion can restore within four tiles of its
owning player on a safe, loaded square on the player's current floor. Stage the
current source to the test copies and load `playtest01`. Leave Stacy on Follow.
Confirm one real body appears near the owner, same name/identity and inventory
remain, Follow persists, and there is no duplicate. Confirm the log reports
`activation-fallback id=ks-world-4` and then normal population activation. If
still missing, provide the new per-ID activation line and state whether the
player was on ground level or upstairs. A visible map entry alone does not
prove body materialization. Hold, independent survivors, and base residents do
not use this fallback; assigned-base recovery is not yet implemented.

Right-click a real single-compartment container inside an owned base and
confirm **Set Filters…** is visible directly in the world-object menu (not
hidden in the Knox submenu). For a multi-compartment object, open the direct
**Set Container Filters** submenu and choose the intended compartment. Open
the large editor; toggle two vanilla categories on and one back off. Confirm
the green filled check state changes immediately, save, close, reopen, and
confirm the same checks and saved label. Repeat in Home and Outpost 2. Confirm
General Storage retains its existing exclusive all-items semantics and does
not erase other categories silently until selected.

Open the vanilla emote radial with all owned companions offscreen/stored. Confirm
Knox Orders and Party Orders remain present; verify individual Followers stay
hidden until a companion body is nearby, then confirm an individual command
still uses the normal order owner. Live appearance, input, save/reload, native
rematerialization, and no-duplicate-body behavior remain human-required.

Player-facing acceptance: an absent owned survivor must return as the same
person with one body and preserved inventory/orders/membership; container
filters must be easy to find, show each checked category, allow multiple
categories, and persist across reopening; party-wide radial orders must remain
available for stored/offscreen companions without exposing individual commands
for unloaded bodies. Do not interpret an offline pass as confirmation of any
of these native UI or lifecycle outcomes.

### Kahlua event-update error and resident-to-party status — BUG-KS-062

After installing the staged build, start the same save and open Debug Mode.
Confirm the repeated `Object tried to call nil in emptyList` errors no longer
appear during the first minute. In the Notebook, select the same base resident,
assign her to Party once, and verify her order reads **Following**. Her activity
may read **Sleeping** only while her saved/offscreen sleep state is active; once
awake/materialized it should update from the live controller. Confirm she
materializes as the same identity with one body. Record the row's order,
activity, needs/sleep state, and body visibility separately; the prior log did
not correlate a specific survivor's sleep state to the reported row.
