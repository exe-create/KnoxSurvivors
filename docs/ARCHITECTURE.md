# Architecture

## Product boundary

A survivor is an autonomous human agent. It is not a scripted zombie and it is not a second local-input player.

The product rule is also that a survivor is **not a colony-game pawn**: it should remain a persistent Project Zomboid survivor whose AI chooses and executes work in the same world. `docs/design/NPC_SYSTEM_INSPIRATION.md` records the current cross-game design research. Planned arbitration/reservation/memory improvements in that note must not be mistaken for already-complete architecture.

Knox Survivors owns:

- persistent survivor identity;
- goals, planning, and decisions;
- movement and interaction intent;
- relationships, orders, camps, and factions;
- serialization and migration of Knox-specific state.

Project Zomboid owns the active `IsoPlayer` representation and normal world mechanics wherever those mechanics can be reused safely.

### Persistent survivor memory

`KS_OffscreenStories` adds sparse, deterministic storylets to the existing
hibernated-survivor ledger. One persisted attempt marker is consumed per
six-hour phase whether or not a story resolves. A survivor pair shares one
canonical pair/phase token, while each survivor retains its own bounded history
and scar list. UI consumers use the normalized newest-first recent-history API;
they never receive the raw nested ledger.

The design is an original implementation informed by The Indie Stone's public
descriptions of future NPC storylets and metaworld simulation. Those historical
plans are design reference, not current vanilla behavior or an engine contract.
Storylets may adjust bounded Knox-owned state and relationship intent, but never
create supplies or mutate world geometry. Real robbery transfers, vehicles,
combat, corpses, blood, barricades, and other visible scenes remain loaded-world
engine work. Virtual vehicle ownership always ends before scar reconciliation
when a body materializes.

## Runtime layers

Automatic follower self-care excursions share the existing movement owner and a
short leader-relative safety envelope. They are not persisted orders; ordinary
Follow/Hold/group duties survive rejection or cancellation. Entrance attempts are
similarly scoped to one pending container search, with a bounded object-keyed
history. Forced window entry uses native timed actions and verified world state.
Settlement discovery caches are runtime-only, keyed by base object and worker;
they never replace real resources or persist claims beyond the task board.

Passenger vehicle orders take a temporary lease over their exact native timed actions.
`KS_CompanionVehicles` reserves a seat only for the queued request; `KS_SurvivorRuntime`
hands off through the existing controller interruption boundary before queueing.
Ground AI waits during that lease and while seated. Expiry, injury, queue removal,
retirement and world reset release transient ownership. Persistent companion duty
remains authoritative, so it resumes after disembarking. Seats/actions are never
serialized into Knox identity data, and no driver behavior is implied by this path.
An autonomous driver's committed passenger roster is scoped to that exact vehicle
run: abort cleanup cancels an unseated member or exits a member still in that run's
vehicle, but cannot cancel or control a member who has moved to another vehicle.

1. **Identity model** — stable IDs and persistent human state independent of a loaded engine object.
2. **World representation** — an `IsoPlayer` created only while its cell is active.
3. **Controller** — converts goals into movement, combat, and interaction intent.
4. **Actions** — executes player-valid actions such as equipping, transferring items, attacking, healing, and barricading.
5. **Simulation** — advances survivors away from loaded cells without keeping full engine objects alive.
6. **Persistence** — saves Knox-owned state and reconstructs world representations safely.

## Persistent person, temporary body

The Knox survivor record is the authoritative person. An off-slot `IsoPlayer` shell is
not trusted as a save-game entity and is never the survivor's identity. Before a shell
is removed, Knox snapshots its current world tile, inventory, worn slots, and hand
equipment. When that survivor's cell is active again, Knox creates a new shell with the
same stable ID and restores the snapshot. To the player this is the same person
continuing to exist; reconstruction is only an engine lifecycle detail.

Java survivor record schema 5 stores the engine human visual, name and voice, inventory and
equipment snapshot, native `BodyDamage`, and native physiology/nutrition state. Older
record schemas migrate forward by supplying engine defaults for fields they did not
contain. New survivors receive real wearable inventory items selected with Build 42's
default, profession, and trait clothing definitions; a restrained separate roll may add
a schoolbag or duffel bag.

Inventory sub-schema 3 captures each root item using native `InventoryItem.saveWithSize`, with
its native world version, total nested-item count, and existing worn/hand bindings. Native container
serialization carries bag contents and item-specific fields such as food state, fluids and rounds.
Restore preflights all native roots and nested counts before clearing the destination inventory;
missing mod items or incomplete decoding reject reconstruction while leaving the encoded record
intact. Schema-2 records remain readable with their old type/condition/uses/visual semantics. They
cannot recover nested contents or quantities that the old format never saved. A fresh capture
upgrades the inventory subrecord; old agent jars cannot read the new sub-schema.

Offscreen food/water consumption decodes detached native items, never an IsoPlayer or a new default
item inferred from its type. Ordinary safe food is reduced with `multiplyFoodValues`; pure clean
water uses native fluid quantity adjustment at the Build 42 bottle ratio of 0.12 fluid per 0.1
thirst. Consumed quantity determines relief. Reusable bottles and partial food remain serialized;
simple fully consumed food is removed from its actual saved container. Scripted food callbacks,
byproduct-producing food, unsafe food/fluids and legacy quantity-unknown snapshots are not consumed
offscreen. Those cases require loaded actions or further supported simulation work. Registry rejects
consuming an active identity, and Lua applies relief only after the updated record is committed.

Records are saved by stable ID under the rebuild-specific `KnoxSurvivors_IsoPlayer`
global ModData key. Every loaded survivor has a separate runtime containing its temporary
body, movement request, traversal route, combat controller, and latest record. Saving
captures all active runtimes rather than whichever NPC happened to act last. This key
remains separate from legacy IsoZombie-era Knox data.

The Lua domain has its own schema number. Schema 18 includes canonical profession and trait
IDs, perk levels and XP, player relationships, affiliation and duty, player factions,
stable bases, work zones, storage policies, task records, validated autonomous life intent,
and bounded immutable origin context metadata.
Java record versions and Lua domain versions are never advanced together by assumption. Migrations normalize
partial development saves in place and never erase an encoded person record.

Profession and trait generation uses Build 42's live definitions, costs, granted traits,
and exclusions. It is deterministic per stable survivor ID and is saved before the body
can be reconstructed. Existing bodies restore saved physiology after the engine applies
their identity rules, then restore saved perk progress. The active body is captured back
into the capability profile; translated labels are never used as save keys.

## Population and origin policy

Survivors are durable world inhabitants, not a refill effect around the active player.
New identities originate from the map's real spawn-region point tables, supplemented by
native ground-floor building room rectangles. A candidate is
rejected when its square is currently visible, occupied, unsafe, or too close to a
player. A valid identity may originate in another town and remain virtually simulated
until its cell loads; loading a cell activates the survivor at their recorded location
instead of relocating them toward the player.

The production population core now maintains a configurable persistent target, defaults
to 48 living identities, and limits physical materialization separately from world count.
Fresh-world identity allocation is limited to six records per population maintenance pass so
the full persistent target cannot monopolize Project Zomboid's game thread during initial load.
The records remain lightweight and the same final target is reached over later slow reconciliation
passes; physical body activation retains its separate, stricter budget. On a new world, allocation
first reserves a bounded cohort of four to twelve durable identities
in the player's actual starting region, then balances the remaining population across the map.
This is an origin policy, not player-centered spawning: every identity still uses a real spawn or
building origin, remains subject to hidden-square activation, and may begin elsewhere in the region.
When that cohort contains sufficiently close origins, one compact pair is created; cohorts of eight
or more may also contain one three-person group. These use the canonical travel-group and relationship
records before first materialization. A shared location-only itinerary moves the whole unmaterialized
group by the same delta, preserving member spacing; if any member materializes, the remaining pending
members wait rather than independently scattering. Most starting-region identities remain solo.
Allocation prefers player starts for two allocations out of three and native building locations
for the third when available. Metadata is cached once
per map; supplemental locations are thinned to one per 100-tile cell. Death is durable
and does not trigger an immediate nearby replacement; after the configured refill interval,
one new identity is allocated at a still-unused origin. Active world survivors hibernate
when they leave the player band and restore at their saved square when that area becomes
relevant again. Developer scenarios remain available as a separate bounded test harness for
social, faction, base, and companion behavior.

Spawn-region coordinates retain a bounded, sorted set of the canonical professions that
vanilla associates with that exact point. Duplicate coordinates merge this evidence instead
of multiplying origins. Native building candidates retain only a building ID and one
high-confidence context classified from exact normalized `RoomDef.getName()` aliases or narrow
semantic prefixes: law enforcement, medical, military, fire service, automotive, agriculture,
food service, or private security. Within a 100-tile thinning cell a semantic building outranks
a generic building; the two-player-starts-to-one-building source policy, regional balancing,
origin uniqueness and activation safety gates are unchanged. Unknown or modded room names are
generic. Room-name lists themselves are catalog-only and are not saved.

Schema 18 persists only the selected origin's bounded context, profession-candidate list and
building ID. The origin has no public mutation path and persistence returns defensive copies.
Schema-17 survivors keep their exact origin and capability profile and receive no inferred
metadata or profession reroll; malformed metadata collapses to generic. Ordinary new identities
attempt contextual native profession candidates before the generic deterministic profession
roll. Existing profiles always win, while authored event professions remain strict and do not
fall back. Context grants no gear, items, faction membership, hostility, or fabricated supplies.

The optional `DisableSurvivorCaps` setting preserves those configured values but bypasses the
active-body and recruitment count checks. WorldPopulation remains a finite starting count; later
arrivals can exceed it, one identity per refill interval, from unused origins only. No numeric
faction count cap currently exists. The scheduler constructs at most two bodies per population
reconciliation in either mode; this is a rate limit, not another total-population cap. Disabling
caps is an explicit performance tradeoff. Re-enabling them preserves existing identities and
companions instead of deleting excess members. No infinity value is persisted in save records.

Before first materialization, an identity has a location-only `unloadedSurvival` ledger with
`pendingMaterialization=true`. It stores a short itinerary between nearby catalog locations,
departure/rest timestamps and lightweight destination memory. Population reconciliation advances
that itinerary without allocating a character, changing the birth origin, or steering it toward a
player. First activation uses the progressed position with the same hidden/standable/safe-square
requirements. This ledger contains no invented physiology or inventory and must never be applied
as real character stats. The first successful body capture replaces it with real needs and record
coordinates. Every subsequent capture also replaces stale virtual coordinates with the fresh
record position. Ordinary hibernated survivors continue through the existing survival simulation.

Pre-materialization travel is a coarse location simulation, not native offscreen pathfinding or
resource generation. Routes stay on the same floor, within 600 tiles of the last stop, at a net
40 tiles/game-hour with two-to-five-hour stops. Reconciliation performs at most eight legs and
48 hours of catch-up; older excess time does not trigger unbounded world scans. These constants
are implementation policy awaiting live density/pacing evidence, not claims of full offscreen
human simulation. Saved body records remain authoritative once they exist.

When an already-valid travel candidate is a classified native building matching the survivor's
persisted profession, that bounded facility set is preferred before the existing deterministic
hash selection. Floor, radius, minimum movement, previous-target, duty and group ownership gates
remain authoritative, and an absent or unknown match uses the original generic candidate pool.
This affects destination choice only; it neither predicts nor creates the building's loot.

Captured independent survivors reuse that nearby-catalog itinerary through UnloadedSurvival;
they no longer drift 1.25 tiles/hour on an arbitrary heading. An unavailable catalog leaves them
at their current location. Explicit return-home trips use 40 net tiles/game-hour and refresh the
destination against the current assigned base; replacement companion duty cancels the old trip.
Virtual trips are coarse simulation, not loaded pathfinding or a guarantee of a traversable route.

Independent survivors, base residents and briefly stored companions split elapsed time between
awake activity and rest. Walking spends endurance; stationary time restores it. Fatigue rises while
awake only when the existing Needs sleep policy requires sleep, and decreases only during a saved
sleep phase. Rest starts at 0.30 endurance and ends at 0.80; sleep starts at 0.72 fatigue and ends
at 0.35. A maximum of eight transitions per six-hour physiology step bounds the work. These are
coarse Knox rates, not a claim to simulate the full native sleep/trait physiology offscreen.
Rest preserves the itinerary/base-return directive; real capture clears stale virtual phases.
Sleeping/resting/sheltering identities restore through the same hidden-square virtual-location
handoff as travelling identities. No world loot, wound healing or extra supplies are generated
by these travel phases. Away teams retain their existing mission travel/recovery policy.

Fully stored autonomous travel groups advance as one cohort in `UnloadedSurvival.advanceAll`.
The existing travel-group record owns one optional `unloadedTravel` itinerary; condition is derived
from the members' real ledgers rather than saved as a second group health/needs model. Shared
walking translates each member by the same delta, preserving their captured offsets. Highest
fatigue/lowest endurance determine shared rest timing; each member retains individual needs,
recovery and real encoded inventory consumption. A member more than 20 tiles away causes a
leader wait and bounded approach to within six tiles before shared travel resumes. No loaded
body is moved by this simulation, and different-floor groups do not invent offscreen stair routes.

Any active member or conflicting companion/base/mission duty prevents cohort travel. Stored
members still advance needs/rest in place; the active controllers retain navigation ownership.
Unequal capture clocks catch up physiology in place before the common travel interval begins.
Membership/leader/capture-clock changes rebase the saved itinerary from current member positions.
Death uses ordinary identity/social cleanup and ends that cohort update; the next reconciliation
rebuilds membership. Direct single-member simulation cannot move a group member independently.
Waiting/regrouping phases use the same hidden-square restoration boundary as travelling phases.

## Minimal active-survivor loop

The first playable survivor is intentionally a small priority controller, not a complete
planner. Each decision update selects one state, and only one action owns the body:

1. **Threat** — flee when unsafe, otherwise equip and engage one nearby zombie.
2. **Injury** — stop somewhere safe and treat the most urgent wound with a carried item.
3. **Critical thirst/hunger** — consume real safe food or water from carried inventory through
   the shipped timed actions.
4. **Exhaustion** — sit/rest for endurance, or enter the native sleeping event for fatigue when
   the current sleep rules require it.
5. **Loot need** — approach one reachable container and take a small ranked set of useful
   items through normal inventory transfer actions, based on current equipment and stock.
6. **Idle travel** — choose a nearby reachable destination and walk there.

The controller chooses *what* to do. Small action executors own *how* to move, equip,
attack, transfer, or treat. Threats may interrupt travel and looting; an executor must
finish, fail, or be cancelled before another executor writes movement or combat input.
This keeps combat, inventory, and medicine independently testable.

The survivor initially uses the engine's real inventory, equipped-item slots, combat
pipeline, and `BodyDamage`. Knox persists a portable snapshot of those values rather
than treating the live `IsoPlayer` object as the save record. Directly applying damage,
teleporting items, or healing wounds is reserved for unloaded-world simulation; an
active survivor should use the same world actions and consume the same items as a player.

Self-care is temporary action ownership, not a durable order. The controller records the real
need/BodyDamage state before queuing a native eat, drink, bandage, or improvisation action. An empty
queue is not considered success unless that authoritative state changed. Failure installs one
bounded retry instead of selecting the same action every tick. Immediate danger clears the native
action or wakes the survivor through `SleepingEvent.wakeUp`, then exposes the unchanged Follow,
Hold, group-travel, or roaming role after danger ends. Sitting remains native endurance recovery;
fatigue uses `SleepingEvent.setPlayerFallAsleep` without local-player fades or time-control writes.

Carried drinking candidates must expose a readable native taint state. A verified clean water
source is eligible normally; verified tainted water retains the existing critical-thirst fallback
only. Missing taint metadata, a failed `Fluid.TaintedWater` inspection, or a non-boolean result is
unknown water and is rejected. It must never silently become clean water because the vanilla drink
action can apply sickness/poison from that same fluid marker.

Loaded thirsty base residents may also select a direct-drink native water object through the
existing supply search and movement state. Search is limited to the same-floor 12-tile loaded
area and, for player-owned bases or faction/base camps, to the current owned boundary. The shared
Needs owner checks `hasFluid`, positive native fluid amount, and a readable boolean
`isTaintedWater()` result. Existing transient autonomy reservations lease the exact object while
the resident approaches; orders, group objectives, threats, higher-priority needs, and native
movement/action outcomes remain authoritative. Vanilla `ISTakeWaterAction` owns drinking and
fluid/thirst changes. Knox reports completion only when the real thirst and source amount both
decrease; emptying the source is valid, but an unchanged source or stat is not. Full inventory is
not bypassed. This is loaded-only behavior: no offscreen water source or persistent water claim is
created. Bottle filling and use by unowned/field companions remain outside this slice. Build 42
thirst, sickness, depletion, movement, and reload results remain live-unverified.

## Confirmed 42.20 engine surface

Inspection of the installed `projectzomboid.jar` confirms:

- `IsoPlayer(IsoCell)` and `IsoPlayer(IsoCell, SurvivorDesc, int, int, int[, boolean])` constructors;
- `IsoPlayer.setNpc(boolean)`;
- local-player storage through `IsoPlayer.players[]` and `IsoPlayer.setLocalPlayer(...)`;
- the shipped Lua `SpawnRegionMgr.getSpawnRegions()` function and its loaded region point tables;
- `isNpc()` players skip ordinary local-input movement, then consume
  `AIComponent.getHumanControlVars()` during `IsoPlayer.updateInternal2()`;
- normal inventory and equipment live on `IsoGameCharacter` through `getInventory()`,
  `setPrimaryHandItem(...)`, and `setSecondaryHandItem(...)`;
- off-slot NPC combat input is represented by `AIComponent.getHumanControlVars()` together
  with the ordinary `IsoPlayer` aim, charge, and attack fields;
- injuries live in the normal `BodyDamage` and `BodyPart` objects, and the shipped Lua
  actions support a doctor and a separate patient.

These are confirmed entry points, not proof that an off-slot NPC is lifecycle-safe. Every affected subsystem must be tested in game.

## Off-slot melee integration

Build 42.20's `SwipeStatePlayer` animation callbacks restrict collision checks and swing
sounds to local players. Knox does not make a survivor local to bypass that restriction.
The Java agent redirects only the three relevant local-player predicates to a Knox-owned
predicate that accepts the real local player or the exact `KnoxIsoPlayerShell` class.
The rest of each callback remains unmodified engine code, including hit selection,
damage, endurance, weapon condition, sound, blood, reactions, and death.

Standing-zombie target visibility has one separate off-slot boundary in Build 42.20.3:
`IsoZombie.isTargetVisible()` reads the target player's local-lighting index, which a contained
shell intentionally does not own. A second transformer adapts only that method's `getIndex()` and
`isCouldSee(int)` calls for the exact Knox shell. Live combat refuses to start unless both this
two-call adapter and the three-call survivor-melee adapter report their expected patch counts.
Zombie target selection, approach, attack state, collision, hit rolls, BodyDamage, reactions, and
death remain native.

The shell supplies its controller-owned forward direction as its aim vector because it
has no mouse or controller input component. The combat executor synchronizes the human
AI control variables, target square, facing, charge, and attack request. If a melee
request does not enter `SwipeStatePlayer`, the executor makes one explicit state entry
and records that fallback in the diagnostic log.

Combat approach targets are placed inside the equipped weapon's maximum range with
enough margin for the movement executor's arrival tolerance. A generic adjacent-square
center is not a valid melee stopping distance: it can report arrival while the weapon's
collision volume still cannot reach the target.

Live zombie targets are not treated as stationary after the first approach. If a target
moves beyond the equipped weapon's effective attack margin, the combat executor clears
the stale swing request, paths back into range, and then settles its aim again. Locked-door
combat remains fixed in place and does not use this re-approach rule.

Combat is a temporary movement owner, not a durable order. Entry cancels the current engine
movement request while leaving the companion/group directive intact. Every terminal, invalid-target,
exception, and explicit-reset path clears the attack flags, `AttackType`, attack square, AI input,
combat route, and pathfinder before releasing ownership. The Lua controller then resumes its normal
decision loop, where an existing Follow/group directive can request movement again.

Threat awareness distinguishes immediate proximity, visible zombies, and zombies already
targeting the survivor or a travelling companion. Active threats receive priority over an
idle visible zombie, while bounded score hysteresis keeps a valid target until danger changes
meaningfully. Reservations scale with urgency: one survivor owns an ordinary distant target,
two may answer an immediate/group threat, and up to three may defend a survivor already under
attack. Companion/group role leashes prevent a visible zombie from pulling the whole party away.

Retreat remains part of this same small decision layer rather than a tactical planner. Low health
or three nearby zombies per nearby ally interrupts combat, chooses a standable direction weighted
away from the closest pressure, and starts one ordinary Java movement request. Short-lived group
plans keep loaded members moving roughly together. Two safe scans end retreat and expose the
durable Follow/Hold/travel order to the normal decision loop again. Base residents may use the
same threat admission and movement owner: their current task claim is suspended across danger,
and active supply-run intent/carried delivery remains durable for the existing return/deposit
path. A direct player companion remains excluded from autonomous retreat. This does not create a
base-specific combat or retreat controller.

## Off-slot firearm integration

Firearms preserve Build 42.20.3's split ownership instead of implementing Knox ammunition or
ballistics. Lua's shipped `ISReloadWeaponAction.canShoot` is the readiness authority;
`BeginAutomaticReload` and `ISRackFirearm` own magazine, loose-ammunition, chamber, jam, and timed
action transitions. Knox only selects a carried functional weapon and refuses to queue a second
preparation action while the first still owns that firearm.

Weapon preference lives in the existing persisted `survivor.policies.weaponPreference` field:
`auto` (legacy/default), `melee`, or `ranged`. Player changes pass through companion ownership
validation; there is no separate command/planner registry. `auto` favors a usable melee weapon
for novices and close threats. Native Aiming level 4+ with a same-floor target at least three tiles
away can prefer ranged combat. Explicit ranged preference still requires native viable ammo/reload;
explicit melee prefers melee when available, with a usable firearm as fallback if no melee remains.
Preference is considered at combat acquisition/preparation, not every frame. Existing native combat
owns close-range repositioning/fallback and threat selection. A changed preference releases attack/
reload ownership without erasing Follow/Hold/Guard. Unchanged controller sync does nothing.
The individual and party menus use native checked options; mixed party values show no active check.
Faction doctrines remain future integration, not inferred from faction names or hidden buffs.

Java captures the equipped firearm for the encounter, maintains facing and floor aim, and owns one
bounded approach or close-range reposition request. It does not call `pressedAttack()` for a ranged
request. Instead it returns `COMBAT_FIREARM_REQUEST`, and the Lua controller invokes the shipped
`ISReloadWeaponAction.attackHook` once. That native hook owns the ranged sound and world-noise event
and enters `DoAttack`; the normal `OnWeaponSwingHitPoint` callback remains responsible for
ballistics, damage, chamber state, magazine count, jamming, condition, and ammunition consumption.
`setAuthorizeMeleeAction(true)` is required because Build 42 uses the legacy-named method as the
general player attack authorization gate, including firearms.

An active rack/reload temporarily releases Knox combat ownership without clearing the underlying
Follow, Hold, or group directive. A missing compatible round or magazine selects an actual carried
melee weapon instead of retrying reload. If a close-range backing route fails, the ranged owner
returns a distinct fallback result and the controller switches to melee without placing the nearby
threat on the unreachable-target cooldown. Dead targets, weapon changes, terminal attacks, and
explicit resets clear ranged intent and the temporary route through the same combat teardown used
by melee.

`KS_SurvivorAutonomyController` owns a bounded firearm-encounter state machine on top of these
native boundaries; it never becomes a second combat scheduler. A ready firearm commits the
encounter to the ranged class for its current exact target until a real invalidation (weapon
removed/broken/empty, no compatible ammo, or a close/overwhelming threat). The bounded
reload-preparation budget is keyed to the exact prepared weapon identity and target, so a finished
encounter cannot strand a later reload with a stale clock. Consecutive native ranged
`COMBAT_FAILED` results (failed approach/pursuit) are bounded; at the threshold the encounter
releases firearm ownership through the existing melee-fallback owner while keeping a still-valid
target eligible. Melee fallback is idempotent when melee is already held and prefers the exact
carried item identity. Every terminal boundary — target drop, retarget, kill, failure, close/ranged
fallback, weapon-preference change, directive abandon, controller error, detach recovery, flee, and
shutdown — clears the transient firearm state through `clearFirearmCombatState()` without touching
native queues or persistent directives. Player-facing weapon preference, aiming assistance, and
native skill/accuracy/damage/ammunition remain exactly as documented above.

The shell's LOS override must remain disabled because off-slot `IsoPlayer.updateLOS()`
writes into a real local player's render channel. A scheduled Lua awareness adapter restores
only the omitted vanilla discovery edge by calling `TestZombieSpotPlayer` for nearby zombies.
Vanilla still evaluates sight and owns zombie target selection; Knox does not assign targets
or make survivors immune. The adapter runs every 30 ticks rather than once per frame.

## Hard constraints

- Do not place NPCs into `IsoPlayer.players[]` unless a narrowly scoped experiment requires it.
- Do not use `IsoPlayer.setInstance(...)` for NPC ownership.
- Do not assign keyboard, mouse, controller, camera, or split-screen ownership to an NPC.
- Keep Knox identity separate from `onlineId`, `playerIndex`, and transient engine references.
- Prefer ordinary timed actions and inventory APIs when they work for an NPC.
- Treat multiplayer as compatibility-only until authority and replication are designed and tested.
- No feature is complete until save/load and cell unload/reload behavior are verified.

## Build 42 render-shell constraint

Build 42.20's FBO renderer excludes moving objects whose concrete class is exactly `IsoPlayer` and renders those objects only from the local-player array (or the multiplayer player map). Knox must not use either collection for NPC ownership.

The contained engine representation is therefore a minimal `KnoxIsoPlayerShell` subclass. It remains an `IsoPlayer` for engine gameplay checks while avoiding the renderer's exact-class branch. `KnoxNpc` remains the owner of identity and behavior; the shell must never become the persistent domain model or a local-player slot.

Build 42.20 also assigns the receiver to the global `IsoPlayer.instance` during every
`IsoPlayer` update, including a non-local subclass. The shell wraps its inherited update
and restores the actual pre-update instance before returning. Without that guard, the
last NPC updated can be mistaken for the local player by later camera, UI, rendering, or
Lua work. Periodic development diagnostics verify the global binding plus local-player
and NPC alpha, invisibility, and model-manager state.

The inherited `IsoPlayer.updateLOS()` is also local-player ownership code: it iterates
the cell's moving objects and writes their alpha values for `playerIndex`. Because an
off-slot shell uses channel 0 only so the renderer can display it, running that method
from an NPC overwrites the real player's visibility results. The shell therefore makes
`updateLOS()` a no-op. The actual local player remains the sole owner of channel 0 LOS
and naturally controls whether survivor bodies are visible from the camera.

## Implementation order

Engine pathfinding supplies a route, while Knox supplies human control intent to the NPC
component. Locomotion must pass before any other executor is added. The next supported
slice is then: inventory ownership and equip, one-zombie melee combat, one-container
transfer, normal injury reception, self-bandaging, and finally player-to-NPC treatment.
Each slice is live-tested alone and across save/reload before the next one begins.

The verified single-survivor runtime remains available through compatibility bridge
methods. Active survival is now scheduled by one Lua autonomy controller per stable ID;
movement and combat state remain inside that identity's Java runtime. Shared reservations
prevent two survivors from selecting the same zombie or world item. Expensive container
searches run only for an unmet need and use a retry cooldown instead of scanning every
frame. Group and faction state must never be inferred from transient engine bodies.

## Relationships and encounter history

Social history is owned by persistent survivor IDs, never by temporary `IsoPlayer`
shells. A low-frequency observer records an encounter only when two loaded survivors are
actually within awareness range on the same level. The save retains their names, first
and most recent meeting times, number of meetings, nearby world-hours, and shared
completed roaming, looting, and combat activity.

The loaded relationship coordinator records finalized social outcomes through the
existing `KS_OffscreenStories` history owner. Each participant's existing canonical
unloaded-survival ledger receives a bounded `meet` entry only after a greeting,
decline, persisted hostile disposition, successful group mutation, or rejected join
has actually resolved. Missing ledgers fail closed; this path never creates a partial
survivor record. The 12-entry history cap and persistent-ID references are shared with
offscreen storylets. Dialogue recounts and Survivor Card summaries read that same
history. A hostile entry means the relationship became hostile; it does not prove a
fight, robbery, or item transfer. In-progress or interrupted approaches do not enter
history.

Active allegiance is also resolved only from persisted IDs. `affiliation` owns player/faction
membership, travel-group and faction records own their member and leader lists, and pair/faction
relationship records own disposition. Runtime character lists are derived caches used for movement
and ally assistance; they never decide membership. One deterministic classifier resolves self,
allied, neutral, or hostile, with shared player ownership/group/faction taking precedence over stale
pair hostility. Save-load normalization removes duplicate roster copies, repairs missing leaders,
and removes dead members from active groups, factions, and camps while retaining historical encounter
records. This prevents an unloaded shell or transient controller reset from changing allegiance.

An ungrouped pair that enters awareness range now interrupts only safe, non-combat work,
approaches, faces one another, and holds a short visible conversation. Mutual agreement
creates a persistent travelling group. The lowest stable ID is the initial route leader;
other members satisfy urgent personal needs but otherwise wait for or follow that leader.
Followers receive stable staggered slots behind the leader and refresh their destination as
the leader moves instead of all chasing one occupied square. The leader waits when a member
falls outside the soft travel leash and walks back toward a severely separated member.
This is the movement foundation for later selectable tactical formations; it does not yet
change combat roles or weapon positioning. An established group
can separately invite a lone survivor. Three consenting members unlock faction readiness,
and relationship history must show nearby time or shared survival activity. There is no
arbitrary minimum number of days together. Proximity alone
is not enough: greeting and agreement must complete without combat interruption.

Dialogue still calls the engine's normal `Say` method for world speech bubbles. The same
line and major encounter outcomes also pass through a client-side activity feed built from
vanilla `ISCollapsableWindow` and `ISRichTextPanel` components. This is separate from the
base game's chat window because Build 42 creates that window only for multiplayer clients.

Independent survivors notice one another within 14 tiles, but only consider a cautious
encounter within 10. Social work never interrupts combat or an unsafe action. One approaches
while the other waits, avoiding artificial teleporting or constant magnetic movement. A
persisted ally never starts a social encounter; a known hostile keeps distance rather than
falling back into a friendly greeting. Neutral first contact deterministically becomes either
a brief cautious greeting or no interaction, with a short memory cooldown. Joining requires
later familiarity plus shared activity, so proximity alone cannot form a party. Only one pair
may own a survivor in a social scan, and group leaders—not every member—initiate an invitation.
Completed greetings and interruptions release both controllers back to their durable behavior.

Stable identity traits supply sociability and aggression. Existing valid first aggression can
still produce the limited normal-timed-transfer robbery executor and durable hostility; it does
not add a new surrender or diplomacy system. Hostile loaded survivors and players now route
through the same live native-combat owner used for zombies, while the controlled combat gate
remains zombie-only. Human target routing and cleanup are focused-test verified, but lethal
human PvP remains behind a live Build 42 animation/collision/BodyDamage verification gate.

The installed 42.20.4 CombatManager eligibility gate is now adapted at exactly three
verified checkPVP call sites (calcValidTarget, calcHitListShove, removeTargetObjects).
Only a live Knox combat owner's exact accepted human pair receives single-player
eligibility, in both directions so the target can defend itself. Ownership reset,
target replacement and failed startup revoke it; an unrefreshed lease expires after
five seconds. Godmode, dead/detached actors, unrelated pairs and multiplayer do not
gain this exception. Native checkPVP itself is unmodified, as are hit calculation,
damage and ammunition. No player/global PvP settings are changed. This is not a
general permission for NPC aggression against neutral humans. Player-first attacks
use native OnWeaponSwing and OnWeaponSwingHitPoint to refresh directional permission
for loaded survivor bodies only. The existing affiliation, faction relations and
personal trust determine friendly protection; the combat sandbox toggle is honored.
Hit-point refresh discards windup permission if recruitment or peace intervened.
The one-second transient permission does not authorize NPC retaliation by itself:
only the existing post-hit event records aggression. No persistent schema changes.
Both directions still require native animation/collision/BodyDamage live proof.

Purposeful exploration considers useful nearby supplies before undirected roaming. A
survivor searches reachable containers for stronger melee weapons, better protective clothing,
a wearable bag, limited food/water/medical stock, and missing essential tools. They play
the search animation when an uninspected container is already convenient. A visit may take
up to two ranked items. Survivors then travel before considering another optional stop;
blocked rooms are cooled down instead of repeatedly forcing entry.

Independent loaded roaming keeps one goal until movement completes, fails, or a higher-priority
danger/self-care owner interrupts it. Useful ranked containers remain the first choice. When none
is currently worthwhile, the survivor prefers a nearby unvisited building, then a safe nearby area,
rather than an arbitrary tile. Candidates near an obvious zombie concentration are rejected. A
bounded twelve-entry, loaded-session memory cools completed destinations briefly and failed ones
longer, so the survivor leaves exhausted areas without creating permanent world knowledge.
Container inspection memory also expires, allowing later reconsideration if the world changes.

An independent survivor also stores one lightweight `lifeIntent`: the reason for the current
autonomous activity (`find_food`, `find_water`, `find_medical`, `scavenge`,
`investigate_building`, or `travel_area`) plus a coarse phase and optional destination. This is
continuity, not another action owner or planner. Native movement, traversal, combat, reload and
timed-action state remain runtime-only. Temporary interruption leaves the reason intact; satisfying
the need, finishing the search, or accepting companion/base/camp duty clears or replaces it. Restore
therefore starts from one durable purpose and a fresh runtime decision instead of reviving stale
movement or combat ownership.

Persistent travel groups additionally keep one validated `objective` copied from the current
leader's autonomous `lifeIntent`. This is shared context, not shared movement ownership: the leader
still owns the real destination request and other members use the existing formation/follow path.
Only the current leader can replace the objective, an unchanged objective does not churn revisions,
and leadership replacement clears the objective and any persisted leader directive. Save
normalization applies the same invalidation when it repairs a missing or invalid leader. While an
entire group is hibernated, a coordinate-bearing objective moves the cohort through the existing
coarse travel ledger; arrival changes both the
leader and group intent to `reassess` before ordinary itinerary selection can resume. Thus unload
does not split one purposeful trip into unrelated per-member decisions or restore an obsolete live
path request.

Travel groups may also retain one leader-authorized, bounded `follow` or explicit `hold` directive.
It is validated against the current stored leader, group, and faction leadership and is delivered by
relationship coordination as pending formation-only arbitration, never as a second scheduler or a
destination command. Native traversal/timed actions and existing danger, need, job, combat, recovery,
and retry owners retain control; any responsive hold cancellation is performed only by the controller
after those owners release it and native cancellation confirms success.

Once a loaded group reaches a shared building/scavenging objective, nearby followers may assist
through the ordinary ranked exploration path. The existing container and item reservations keep
members from choosing the same work, and slot-based delay/cooldown prevents a simultaneous search
burst. Followers do not persist a duplicate personal intent, do not assist another member's food,
water, or medical need, and return to formation behavior when too far from the leader.

Loaded travel groups cooperate on critical carried supplies through `KS_GroupSupport`. A nearby
member missing immediate bandaging material, clean water, or food can receive one real item from an
ally through the existing native inventory-transfer action. The donor keeps a minimum personal
reserve (and an additional reserve when sharing the same need); favorite and equipped items are
never offered. Medical, then water, then food determine priority. Recipient and item reservations
permit only one transfer at a time, completion is verified against the real source and destination
containers, and combat/failure releases all temporary ownership.

If no safe spare exists, a nearby follower waits with the group rather than starting an unrelated
route. The leader evaluates nearby member shortages and owns one ordinary `find_food`, `find_water`,
or `find_medical` world search. That intent flows through the persisted group objective above, so
members follow and can assist at arrival. A separated follower remains free to solve its own urgent
need. No resources are created, abstracted, or transferred while unloaded.

Temporary camps remain lightweight faction shelter records rather than miniature bases. The camp
stores one building identity, loaded bounds, and the current durable faction-member IDs. Runtime
controllers derive camp assignment from that persisted faction link on registration and low-frequency
reconciliation; no second survivor affiliation is created. Members choose deterministic, reserved,
standable positions inside the shelter, with slot-staggered rest, reposition, excursion, and quiet-idle
choices. Needs and threats retain priority. An excursion uses ordinary roaming and at most one normal
ranked exploration opportunity before returning through native movement. Camp identity survives those
temporary owners and is cleared when the camp is removed or converted to a permanent faction home.
Nearby real containers remain available to the ordinary need/looting paths; camps create no abstract
stockpile, item generation, work board, territory, or storage ownership.

## Player companions and presentation

### Player trust and faction reputation

Personal trust remains in `survivor.playerRelationships[playerId]`; faction reputation extends the
existing canonical faction-pair relationship, not a second diplomacy registry. Positive contribution
records have fixed supported reasons, per-kind cooldowns and a rolling 24-hour budget (12 personal
trust, 8 faction reputation shared across members). Reward windows survive save/load and do not
reset on clock rollback. Faction relationship getters deep-copy nested reward data. Personal trust
governs recruitment only when the **Require Trust to Recruit** sandbox option is enabled; it is off
by default. Explicit hostility always blocks Talk/recruitment and positive credit regardless of that
option. Group/faction ownership, companion limits, life, loaded availability and range also remain
authoritative.

The native `OnZombieDead` boundary grants defense credit only when the dead zombie's actual attacker
is a real local player and its current target is a living loaded Knox survivor: same floor, zombie
within eight tiles of that survivor, player within twenty. Missing native evidence earns nothing.
A weak body-key set suppresses repeated callbacks; persisted cooldown/budgets bound separate kills.
No full-world scan, custom kill, inventory reward or damage mutation is involved. Positive help does
not automatically erase hostility or create an alliance. Credit acknowledgement uses existing speech.

A native player hit on a previously non-hostile survivor records a trust loss and, for NPC-faction
members, negative reputation plus hostile faction disposition through the existing relationship.
Repeated attacks on an already-hostile target are not additional unprovoked aggression. Player-owned
factions are not made hostile to themselves. Trade credit now follows verified exchange completion,
and quotation reads trust/faction reputation. Gift/treatment/construction credit reasons remain a
persistence contract; their gameplay completion adapters are still unfinished.

Recruitment is a persistent affiliation transition, not a UI flag. A namespaced player ID
owns one player faction; a survivor may belong to only one authority and cannot remain in
an NPC travel group after recruitment. Talk history and trust are saved per player. Follow,
Hold, Return to Base, and Dismiss update duty first, then the active controller reconciles
that durable order on its next update. Threats and critical needs remain above ordinary
orders, so survival can interrupt a command without deleting it.

Companion commands are split into three durable concepts. The primary order is Follow or
Hold. Vaulting/climbing is a standing traversal policy. Loot-area, loot-building, and
loot-corpses are temporary directives; after the target has been searched, the survivor
returns to the primary order. Header commands use the same service as individual and world
context menus. NPC travel groups and factions reject any survivor whose affiliation or duty
is player-owned, including stale pending meetings.

The player-party **Move Party Here** command is a session-scoped shared destination intent
owned by `KS_CompanionService`, not a persisted player-group record. It snapshots currently
eligible companions in primary Follow duty with no individual directive; Hold, Relax, Guard,
base assignment, and other individual orders remain authoritative exclusions. Each
participant receives the same destination through `syncController` and then routes through
that survivor's existing autonomy/movement owner. A later individual order removes only
that companion from the shared order. A new party movement/search order, Follow/Hold/Relax,
Return to Base, Resume Normal Duty, or explicit cancellation supersedes the shared intent.
Needs, combat/threat, traversal, native actions and recovery remain above it; the same active
intent is offered again through normal controller arbitration after temporary interruption.
Each survivor is considered arrived only on the same floor within 1.5 tiles of the selected
square. The one-hour world-age expiry, arrival completion, cancellation and invalid/empty
roster clear the runtime record. A dismissed, dead, reassigned or otherwise ineligible
participant is removed from that command; no new companion inherits it after selection.
The player remains the party authority and anchor; no companion is elected as group leader.
Player-anchored runtime slots are implemented separately under D-026. No NPC faction/travel-group objective is read or written. Because current player-scoped
persistence has no shared order lifecycle compatible with individual order cancellation and
controller sync, the destination deliberately does not survive save/reload.

The player-party cohesion projection is runtime-only and is derived from the same recruited
companion roster. `KS_CompanionService` assigns stable per-session slots to Follow-eligible
companions and smooths the party heading from meaningful player movement; facing changes
while stationary do not rotate slots. Hold/Relax, individual directives, base duty, death,
dismissal and ownership changes remove only the affected survivor. The player remains the
normal anchor; short-lived spatial fallback may use the player's last finite loaded square
during a brief missing-square interval, but never promotes a companion to leader. The
controller uses its existing formation target and native movement path. Its player-only
fallback compresses into a small set of standable nearby squares when a preferred slot is
blocked or leased. These position leases use the autonomy system's shared transient
reservation table and release through existing controller cleanup; no second scheduler is
introduced. NPC `GROUP_FOLLOW` target calculation and leader projection remain unchanged.

While a shared destination is active, eligible companions receive distinct loaded staging
tiles within its canonical 1.5-tile arrival area when available. Reaching a staging tile does
not itself complete the order: `KS_CompanionService` verifies the same-floor live character
position against the original destination. A member that arrives waits loosely at its leased
tile until the other still-eligible participants arrive; cancellation, supersession, expiry,
roster loss, or completion releases it back to normal player-anchored Follow arbitration.

Follow reuses the existing staggered slot structure rather than targeting the player's
occupied square. Slots are refreshed on a bounded cadence and a route is replaced only when
the slot changes by a meaningful distance or floor; pace-only changes update the active Java
request without replacing its destination. Close followers walk, moderately separated
followers run, and far followers may request sprint. Each movement tick re-evaluates the
remaining route, real health, endurance, fatigue, and native `canSprint()` result, so sprint
downgrades to run and then walk as the gap closes. The implementation uses native
`setRunning`/`setSprinting` state and the existing NPC human-control variables; it never
changes coordinates or movement speed directly. Hold is an explicit guard at both follow
start and refresh boundaries.

The runtime registry is deliberately narrow. Gameplay and interface code may resolve a
temporary character or request a fresh semantic snapshot, but cannot take ownership of a
controller. The companion view model returns copied values for name, duty, activity,
health, needs, weapon, and distance. The right-side HUD only queries player-owned
companions, pools at most six live 3D portraits per local player, and releases every body
reference on unload or teardown. World and HUD context menus call the same companion
service.

## Base and work boundary

Player and NPC settlements share stable base records. A base keeps its original home
building separate from an editable territory boundary. Territory applies to its X/Y area
on every building floor and classifies ownership only; it never blocks navigation into,
out of, or through the building. A base owns its territory, work zones, storage policies,
residents, and queued tasks; it never stores a live square,
container, character, or controller reference. Storage markers use namespaced world-object
ModData plus coordinates, object index, and container index so multi-container furniture
does not collapse into one destination.

Duty, physical presence, capability requirements, and claim ownership are checked before
a resident can take work. Claims are released when a survivor leaves the base and are
recovered after an interrupted load. Guard and patrol zones now have a recurring executor:
the resident claims a persisted task, walks to a standable point in the zone, holds the
post for a bounded interval, records the result, and reopens the same task on its next
cycle. A depot policy can also pair with a categorized destination policy: the resident
finds one matching item in the loaded depot, walks to it, and moves it through the normal
off-slot inventory-transfer action. The persistent task stores stable policy keys and an
item full type rather than an engine object, so a save/reload can safely retry if the item
was taken. Before a claimed task starts its actual world action, a resident checks its
exact item requirements against their carried inventory plus currently loaded assigned base
containers. Missing items are collected one transfer at a time through the same off-slot
inventory action; streamed-out or absent storage blocks the task rather than becoming an
implicit supply pool. Farming zones now have a small maintenance executor: the resident discovers the
first ripe or dry seeded plant in the loaded zone, walks to it, and queues the vanilla harvest
or watering action. An empty suitable square can then be plowed and a carried seed sown as
separate persisted tasks, again using the vanilla timed actions and state verification. A
woodcutting zone likewise resolves a loaded tree, requires a real axe, and queues the vanilla
`ISChopTreeAction`; completion is accepted only after the tree object is removed. Log-to-plank
production resolves a carried log and saw, validates the vanilla `SawLogs` recipe, and queues
`ISCraftAction`; completion is accepted only after the source log is consumed. Corpse handling
now has the same kind of executor: a resident finds a loaded human or zombie body inside the
bounded base territory but outside its Corpse Drop Area, walks to it, unequips held items, then
uses the vanilla grab and drop actions to drag it toward the center of that area. The saved task keeps only corpse coordinates,
its inventory-item ID with a static-object fallback, and the destination zone ID; live object
references never enter ModData. Interrupted hauling releases the body before the claim is
closed. Animal Care Areas now discover loaded feeding troughs and create separate water or
feed tasks only when a resident carries a valid supply. Water uses Build 42's normal
`ISAddFluidFromItemAction`; feed uses the same inventory-transfer path as a player, which
lets `ItemContainer` notify the trough and update its animals and overlay. The task persists
only the master trough coordinates/index and the supply's item type/ID, then verifies that
the real trough water or feed amount increased. Structure repair delegates its entire ruleset
to Build 42's moveable-repair system. A resident scans a drawn Repair Area, or the loaded base
territory when no repair area exists, and considers only doors, thumpable structures, and
barricades between 20% and 95% health that vanilla `canRepairObject` approves. The task keeps
coordinates, object index, sprite name, and the concrete tools/materials found for that repair.
After travel, `ISMoveablesAction` performs the normal equip, animation, sound, skill-chance,
resource-consumption, multi-tile repair, and synchronization path. Knox records success only
if the actual object health rises; a legitimate skill failure remains a failed retryable task.
Barricade work is the exception: when a resident carries a hammer, plank, and
nails, the controller discovers an unbarricaded loaded window inside the base and queues the
vanilla `ISBarricadeAction`; completion is accepted only after a real plank count increase.
Vanilla crop ownership is not treated as a Knox survivor ID because single-player off-slot
bodies do not provide a stable unique crop owner.

Automatic discovery queues all currently executable job families before selecting work.
The shared task board chooses by persisted priority and filters each resident against skill,
trait, recipe, and real assigned-storage item requirements. This prevents renewable farming or tree work
from starving security and cleanup, while also preventing a resident without the exact tools
or materials from claiming a task another resident prepared.

Automatic shortage runs share this settlement boundary. Player-owned base
residents require their persisted per-resident loot-run permission. For a
faction-owned base, an ordinary autonomous resident whose persisted faction ID
matches the base owner may be elected for that base's actual loaded-storage
shortage through the existing supply planner and receipt-gated run/deposit
owner. Explicit specialization, tasks, events, away work, and active generic
group-sortie leases remain respected. The group-sortie query is read-only; it
does not become a second task or mission owner.

Player territory is also sent to the Java traversal runtime as a protected structure area.
Friendly and neutral survivors may still use doors and try an unlocked window, but they
cannot escalate to smashing a window or breaking a locked door inside that territory.
Explicitly hostile survivors are exempt so later raids can use the same policy boundary.

## Faction base scouting

A faction home begins as persistent planning data before becoming a claimed engine object.
The leader periodically examines loaded buildings within 30 tiles. Candidates need at
least two rooms and 30 tiles; residential status, water, room count, and area improve the
score. Buildings overlapping an existing vanilla safehouse are excluded. The chosen
building ID, bounds, score, and an exterior approach square are stored before travel.

The group follows its normal leader while the leader travels to that approach square.
Arrival promotes the candidate to `homeBase`; a failed route rejects it for 24 in-game
hours so another building can be considered. A selected home receives a vanilla safehouse
boundary with a namespaced synthetic Knox faction owner. This makes vanilla overlap checks
reject player claims in that building. The boundary is reconciled on load and periodically
while the faction is active. A stable base record is then created and faction members become
residents. They return toward a loaded home and alternate between short local patrols and
idle periods while the first real job executors are built. Trespass hostility remains a
separate gameplay layer.

Captured route waypoints are not assumed to be unobstructed floor. Before crossing into
an adjacent square, the traversal layer asks the engine whether that edge contains a
door, window, window frame, low fence, tall climbable wall, or hard blockage. It pauses
walking while a normal engine interaction or climb state owns the body. Unloaded,
barricaded, unclimbable, and static obstructions produce an explicit route failure
instead of allowing the survivor to walk in place forever.

## Carried inventory cleanup

The existing Looting policy exposes `itemUtility` (retention priority, not a trade price) and
`cleanupPlan`. Cleanup begins above 90% of native maximum carry weight and, once active, stops
below 80%. Recursive inspection is cycle/depth bounded. Equipped, attached, hand-held, favorite,
medical, ammunition, essential-tool, best-melee, needed-food/water, valuable/accessory, unknown
modded and queued/claimed-job items remain protected. Favorited bags protect their contents;
nonempty bags themselves are not discarded. Surplus food/water and recognized base materials
are deposit-only. Inferior spare gear, broken weapons and known vanilla junk may be dropped.

The normal controller thinks about cleanup after threats/self-care, without interrupting a claimed
base task. It queues one item through the existing off-slot native inventory transfer adapter,
then verifies source removal plus destination/world receipt. Nearby reachable assigned storage
from the canonical player/faction base is preferred; categorized storage precedes depot/general.
Floor drops use a private native `ItemContainer("floor", nil, nil)` like the vanilla loot panel,
never a local-player indexed inventory. No item is manually deleted or recreated by cleanup.

Cleanup is temporary `INVENTORY_CLEANUP` ownership. Danger/new commands cancel it, timeout and
failure clear it, and Follow/Hold/Guard remain persistent underneath it. Evaluation and failure
cooldowns bound repeated attempts. Inventory changes use the ordinary snapshot/capture path;
transient item references are not serialized. Useful surplus can also initiate `MOVING_TO_DEPOSIT`
for a loaded owned container within 128 tiles on the current floor. The native adjacent-tile finder
selects the interaction side; the existing movement/traversal runtime owns the route. Companions,
directives, travelling groups, away duties and claimed jobs cannot take this autonomous detour.
Arrival recomputes canonical base ownership, item utility/job protection and the exact container
policy/capacity/interaction edge before queuing a real transfer. Movement failure or timeout cools
down that storage key for 1800 ticks (at most 16 remembered keys); cleanup retry waits 600 ticks.
Danger, new commands, detachment and shutdown discard transient trip ownership. No teleport,
abstract stockpile or persisted item reference is introduced. Cross-floor/distant deposits, broader
reserve/modded valuation and currency/trading prices remain separate work. Protected-heavy
inventories may remain overweight when no safe disposal or practical owned deposit is available.

## Independent survivor barter quotation

`KS_TradeValuation.quote(player, survivorId, playerItems, survivorItems)` is a read-only policy
boundary, not a completed trade or permission to transfer. It resolves the active body from the
existing runtime and life/affiliation/hostility/trust/faction reputation and base task needs from
existing persistence. A local real player and living non-player-owned survivor must be within three
tiles on the same floor. Quoting does not create relationships, award reputation, move items,
change orders or capture a second inventory record.

Actual inventory ownership is walked recursively, with 4096-item and 16-level bounds. Offers are
dense unique arrays of at most 32 item references per side. Stale ownership, shared inventory,
favorite/hidden/equipped/attached/hand items, favorite or hidden bag contents, nonempty bags, unsafe food/water,
broken weapons and unclassified items are rejected. Real food relief, fluid amount, bandage power,
condition, protection, bag capacity and weapon/ammunition fields drive the initial known-item
values. Native `AmmoType.getItemKey()` returns the `Base.*` key; compatibility is not guessed from
a name/category or a nonexistent `isAmmo()` method. Unknown modded items have no assumed price.

Whole-basket checks preserve existing food/water/treatment reserves, best carried melee capability,
compatible ammo/magazines and queued/claimed base job requirements. Real incoming replacements may
cover food/water/medical/melee/task reserves. Need urgency, carried stock and canonical job demand
affect value. Incoming duplicate utility falls with the whole basket, independent of selection
order; equivalent food portions retain equivalent value. Trust/reputation reduce a bounded spread,
but never eliminate it. Quotes contain a deterministic fair/low indication, not random acceptance
rolls. Values are initial barter utility, not vanilla prices or proof of a balanced economy.

Native 42.20.3 `ISTradingUI` resolves `getPlayerByOnlineID` and sends network trading messages.
Its unmodified multiplayer protocol cannot be used for off-slot bodies. `KS_TradeUI` uses native
collapsable-window, scrolling-list and button widgets, fonts, item icons and checkmarks instead;
it never registers the survivor as a real local/network player. The existing survivor context menu
exposes Trade for independent/non-player-owned survivors, with hostile/distant/multiplayer guards.
The stock lists expose only supported unlocked real items; reserves remain subject to the whole
basket quote. Selecting items does not move them. Quotes show fair/low or a concrete refusal reason.
Stock refresh is limited to once per second; selection changes explicitly refresh the quote.

`beginBrowse` acquires the same controller lease as an exchange, for at most two wall-clock minutes
or 7200 controller ticks. Closing, changing scenes/resolution, player death, distance, danger or a
new directive releases it. One window exists per actual local player viewport. Mouse and joypad
callbacks select real item references. `queue(..., session)` validates and hands off that exact
lease to one exchange action; stale browsing cleanup cannot release a newer owner. Closing during
the action cancels that trade before completion, not unrelated queued actions. One exchange is
allowed per window; reopen for another. Successful stock refresh cannot hide a failed queue result.

`KS_TradeAction.queue` provides the single-player exchange action used by that window.
It uses a short player `ISBaseTimedAction` and an identity-bound `TRADING` lease on the existing NPC
controller/runtime. It declines native traversal, active actions, claimed work and perceived danger;
it cancels existing movement only after those checks. The normal threat scanner remains active.
Combat, flee, new directives, detachment and shutdown cancel the lease; release cannot overwrite
a newer behavior. A 1800-controller-tick ceiling bounds the exchange-action lease. Persistent duty,
group/camp and identity records are not rewritten by the lease.

Completion rechecks real offers, canonical relationships, adjacent unobstructed squares, vehicles,
hit/attack state, native source-removal/destination-add rules, item ID collisions and root inventory
capacity. Native `hasRoomFor` receives net root weight; nested outgoing weight is conservatively
not credited, so a valid crowded bag trade may need more room. Both offers then move through native
`ISTransferAction.transferItem` in one non-yielding callback, with original instance/container
receipt checks. No fake TradeUI/floor stockpile or type-based item recreation is used. The existing
survivor snapshot must succeed before mutation and after both transfers; only then is bounded
trade reputation recorded. Reputation failure cannot reverse or repeat a completed exchange.

Transfer/final-capture failures restore the original item instances to their original containers
using native `AddItem(instance)` and verify both sides. The pre-exchange encoded survivor record is
retained if a restored inventory cannot be recaptured. Unexpected rollback/persistence-recovery
failure retains the journal's actual references in `KnoxTradeActions.failedExchange`, logs
`RECOVERY_REQUIRED` and blocks further trading for the session. This is a diagnostic stop, not a
durable recovery ledger or proof against process crashes. Ordinary cancel/queue removal before
completion never mutates inventory. Multiplayer is explicitly rejected; no network protocol is
being simulated. The window reports recovery failure and instructs testers to stop and retain logs;
it does not offer an unsafe retry. Rarity sourcing, additional medical/material classes, broader
currency coverage, durable fault recovery and live UI/save/animation/economy evidence remain unfinished.

## Native wallets and physical currency

`media/registries.lua` registers the namespaced `knoxsurvivors:wallet` ItemBodyLocation through the
native ModRegistries entry point, before script loading. Shared `KS_Wallets` requires the native
Human body locations and adds that location. After script loading, it changes only CanBeEquipped
on the four existing Base wallet container definitions (Wallet, Wallet_Female, Wallet_Male and
Wallet_Hide). Removed definitions or replacements that are no longer containers are skipped. No
item types are replaced and no contents, weights, capacity, sound, icons or acceptance rules change.
Other mods that alter those wallets' wearing slot may conflict; this is not a key-ring tag patch.

Exact 42.20.3 evidence: native inventory menus recognize `InventoryContainer.canBeEquipped`, native
`ISWearClothing.complete` calls setWornItem, and ISInventoryPage lists worn containers. Key rings
have a separate tag-based UI path and are not wearable examples to copy. InventoryContainer's load
restores contents while its wearing location comes from the item script/factory. Knox's existing
native-payload snapshot and worn-flag restoration therefore retain the same wallet type, contents
and slot alongside a backpack. Existing equipment evaluation can wear a carried wallet without a
new NPC action, model, automatic free wallet or per-tick inventory scan. The wallet has no added
visible 3D attachment. Unequip it before disabling the mod so a save does not retain a removed slot.

`KS_Currency` recognizes only real Base.Money, MoneyBundle, SilverCoin and GoldCoin objects. It
returns read-only descriptions, not an account balance. Cash bundles use the exact native recipe
ratio of 100 bills. Cash stock saturation counts bill equivalents so unpacking does not manufacture
value. Coins have initial barter utility, not claimed real-world/vanilla monetary values. Existing
quote needs, stock, relationship spread, reserves, item ownership and verified exchange govern
payment. Currency can be selected inside a worn wallet; a favorite/hidden wallet protects contents.
Trade receipts still go into normal root inventory, and players can move them with native inventory
controls. No automatic change, currency generation, account ledger or NPC-specific money storage.

Native wallet acceptance permits maps/literature/FITS_WALLET items with its original capacity 1
and maximum item size 0.2. Bills and gold/silver coins have FITS_WALLET; MoneyBundle does not. Native
UnbundleMoney is the way to put that cash in the wallet. Large gold bars cannot be squeezed into it.
Bars remain protected by cleanup but are not priced until conversion/rarity policy is verified.
Cleanup also explicitly protects cash bundles and both coin types instead of discarding bundled
cash as native-category Junk. Further currencies, precious-metal conversion, hiring contracts,
economy balance and live wallet/trade persistence remain separate unfinished work.

## Building entry policy

Entry selection belongs to the controller; crossing the selected edge belongs to the
traversal executor. The intended preference is:

1. Let the native path use an already-open edge or open a closed, unlocked door/gate.
2. If that preferred edge fails, select another usable door before a window where the
   target room exposes both choices.
3. Open a usable window through the native state, then climb through only after the
   window is genuinely passable. Open or broken windows still use native climbability.
4. Temporarily suppress only the failed XYZ edge and retain the original destination so
   another entrance, low fence, or other human-accessible route remains eligible.
5. Optional loot abandons and cools down a room when every scanned entry fails. Only urgent
   food, water, or medical needs may force the door with sufficient endurance.

Build 42 completes the world-state portion of `OpenWindowState` only for a local player.
The off-slot NPC traversal adapter therefore waits for the engine animation variable
`StopAfterAnimLooped=success` before calling the normal `IsoWindow.ToggleWindow(...)`
completion. It must not toggle on an attempt, struggle, or failed animation. This keeps
the animation, sound, exertion, lock outcome, alarm behavior, sprite change, path-map
invalidation, and synchronization in their engine-owned sequence without assigning the
NPC a local-player slot.

Barricaded or otherwise unsafe openings may be rejected. Forced entry must preserve
normal time, noise, equipment, injury, and zombie-attraction consequences. Ordinary
traversal never initiates window smashing. The current traversal slice executes native
door/gate opening and window, frame, fence, and climbable-wall states on an already selected
route edge; deliberate locked-door breaching remains a separate, survival-need-gated action.
Traversal must never delete an obstacle, fake passability, teleport across it, or alter its
health directly.
## 2026-08-31 native feedback boundaries

- Single-player survivor labels use vanilla text/camera projection and the real viewing player's
  `CanSee` plus NPC alpha. `showTag` is multiplayer faction metadata, not an SP rendering switch.
  Relationship lookups are cached at the existing 15-tick update; no NPC claims a viewer slot.
- Clothing replacement evaluates native mutually exclusive body locations, not just the exact
  worn slot. The native worn collection remains authoritative; unreadable metadata rejects upgrades.
- `KnoxSwipeStateTransformer` also handles one **audio-only** check in exact 42.20.3
  `CombatManager.attackCollisionCheck`: bytecode 1628 `IsoPlayer.isLocalPlayer()`, followed by
  the branch to 1822 and `HandWeapon.isRanged`. Same-length virtual-to-static substitution preserves
  the operand stack, exception tables and native impact body. Any shape mismatch fails closed.
  It does not grant local-player status to other combat, input, networking or rendering systems.
  The original three SwipeStatePlayer callback substitutions remain unchanged.

## Knox Events: persisted lifecycle and raid roster boundary

`KS_KnoxEvents` owns `KnoxPersistence.getKnoxEventState()` (additive Lua schema 14).
Event records contain IDs, phase/revision/timestamps, source and target base identity,
location fingerprints, and canonical survivor IDs. They never contain alternate actor,
inventory, health, faction, or companion records. Existing native survivor snapshots
remain authoritative. The event service does not write survivor duty or allocate actors.

The shared phase graph is scheduled -> spawning -> approaching -> active -> objective
-> withdrawing -> completed, with cancellation/failure edges. Callers supply the expected
revision; stale callbacks cannot advance a newer phase, and repeated same-phase callbacks
are idempotent. Timers may invalidate a plan or request withdrawal, but cannot manufacture
an arrival, victory, loot transfer, or completed return. An interrupted/deployed party
retains its roster until an actual dispatcher cleanup result. Malformed deployed metadata
also retains that roster for recovery instead of silently releasing potentially live actors.

The first policy is a raid proposal using an existing hostile faction relationship,
existing source/target bases, and living canonical source-faction residents with native
snapshots. No claimed job or away-team member is borrowed. At most 40% of the living
roster is proposed, with at least two available residents left home; five residents can
send two. Roster/ownership/location and remaining home strength are rechecked before
departure. Proposals do not override existing work: a member becoming unavailable cancels
an unstarted plan. `KS_EventRuntime` checks live health/loadout and takes a temporary
`duty.eventId` binding through all-member persistence validation. The base duty itself
retains home, faction, order, and job preferences. Base claims and Away Teams reject
event-bound residents. Releases compare the event ID and never overwrite a newer owner.

Maintenance uses the existing population interval, handling up to 16 records per call
(explicit maximum 32), with a persisted round-robin cursor. Finished history expires after
seven game days and is pruned toward 128 entries in bounded batches. A separate expiring
per-faction cooldown retains the 24-hour scheduling limit even when history is pruned.
These are initial internal policies, not new player-facing sandbox settings.

Explicitly scheduled raids now dispatch ready loaded residents; there is still no random
raid scheduler. `spawning` is the shared claim phase, not permission to create replacement
members. The runtime inspects up to eight events every 30 controller ticks. Controller
projection is transient: EVENT_TRAVEL/EVENT_WAIT yield to existing combat and self-care,
use normal native movement/pace requests, retain existing retry cooldowns, and reuse group
follow/regroup logic. Arrival points are distinct and outside the target building on the
approach side; short loaded segments lead toward an unloaded destination. Repeated route
failures or a member fleeing request whole-party withdrawal. No coordinates are written
on active actors, no local-player slot is claimed, and no combat state is forced.

Wholly stored event parties use the existing `advanceStoredGroup` cohort scheduler, not
parallel event physiology. It preserves relative positions, uses the weakest member's
endurance/fatigue for shared rest, advances real stored food/water consumption, and commits
route state back through the event's expected revision. A mixed loaded/stored party waits
for regroup rather than moving its hidden half independently. Individual stored updates
cannot snap event-bound base residents back to ambient home coordinates. A surviving
single-member withdrawal is supported; released members no longer block its cohort.

Loaded arrival at the target advances to active; offscreen arrival does not fabricate
combat/objective completion. Withdrawals release members when their real loaded square or
persisted virtual route reaches home. Death or a replaced duty resolves only that member;
a removed/lost home fails the event and retains faction identity under autonomous duty.
Malformed deployed records remain reserved for recovery rather than pretending to return.

Stored residents use fresh persisted physiology/home state plus a read-only decode of their
real equipped native item before an all-member event claim; this never reconstructs a body or
defaults equipment. Automatic scheduling runs only at the existing population interval and
uses a persisted next-check/cursor. It considers established explicitly hostile factions with
real bases and eligible real rosters, permits one automatic event at a time, rejects targets
over 600 tiles away, and then enters the same proposal/dispatch/objective path. Default sandbox
policy allows the first check after day seven and spaces successful checks by seven days.
Disabling automatic raids prevents new schedules but does not erase a deployed party.

Actual live raid combat/loot/return evidence and the other Knox Event faction policies remain
unfinished. Native human combat remains the existing authority and still needs its documented
live evidence. Named event factions may not bypass this common persistent-survivor lifecycle.

`KS_EventFactions` is the read-only catalog for Police, Scientists, Military, Black Division,
Scavengers and PMC policy identity. Catalog entries contain only naming, world-age, base,
objective, persistence and future loadout-theme constraints. They grant no actor, item, skill,
accuracy, damage, health or relationship state. When an existing ordinary NPC faction is bound
to one policy, `faction.eventIdentity` records the policy/source event on that same canonical
faction; survivor affiliation, duty, inventory and relationships remain in their existing domains.
Malformed identity metadata is dropped during save normalization and a faction cannot be rebound
to a different event identity. The catalog does not yet spawn or trigger a named faction.

Named-event entry preparation reuses the cached world population catalog. It chooses one unused
ground-floor player/building-spawn anchor within a bounded ring of the event target, rejects points
within 60 tiles of any supplied local player, and derives up to six compact distinct origins around
that anchor. `createEventFactionPopulation` preflights the full batch, allocates ordinary
population-managed `ks-world-*` identities, one normal travel group and one normal NPC faction in
one non-yielding persistence transaction. A failed allocation removes every new identity and
restores its world-ID serial; retrying the same source event returns the existing faction.

Before first real materialization, event entrants retain `pendingMaterialization` and wait at the
entry anchor rather than independently advancing the ordinary roaming itinerary. Normal hidden,
loaded, distance and standability gates still decide when each body may appear. The first real
capture clears entry waiting and transfers physiology/location ownership to the existing native
snapshot path.

Named arrivals now use `kind=faction_entry` in the same persisted event ledger. Scheduling stores
only policy, objective, party size and target; it creates no survivor. At due time the runtime
claims `scheduled -> spawning`, selects one safe cached-world anchor, invokes the idempotent entry
allocation, and commits faction/member/group identity plus every member's temporary `duty.eventId`
in one ModData transaction. A persisted 15-world-minute retry prevents missing-origin attempts
from becoming an update storm, while retry after reload remains safe because source-event binding
cannot allocate a second faction.

Entry parties use distinct common approach/return points and the existing loaded EVENT_TRAVEL and
stored-cohort movement. An incomplete mix of materialized and unmaterialized members waits rather
than splitting into independent itineraries. Real loaded positions establish arrival; no timer
fabricates it offscreen. The initial shared objective is deliberately only a bounded one-hour
presence state allowed by the selected policy. It grants no loot, combat outcome, faction-specific
behavior or items. Withdrawal returns toward the saved entry anchor, releases temporary event duty,
and applies the selected policy's persistence boundary.

For `persistsAfterEvent=false`, departure is a two-phase lifecycle rather than deletion. Reaching
the entry anchor writes a pending departure marker that excludes the identity from activation and
lightweight simulation. The autonomy owner then captures and removes a loaded IsoPlayer shell using
the same transactional boundary as hibernation; a stopped controller and bounded backoff retain
ownership after capture/removal failure. Only successful teardown finalizes `departed` and clears
actionable social/duty ownership. A stored member with no shell can finalize immediately.
Identity, native record, equipment and history remain durable, while the empty event faction is
retained as non-actionable history. `alive` remains true because departure is not death; a real death
clears pending departure and continues through the existing corpse/reanimation path. Police and
Scavengers use the persistent branch and rejoin ordinary world life after event duty releases.

The destructive developer action **Schedule Police Entry Here** is the first explicit live harness.
It is not an automatic Police event. On the ordinary first-materialization path only, a canonical
`knox_event` Police member derives `base:policeofficer` from its faction policy. Existing capability
generation still balances real vanilla profession/trait points; existing appearance code applies
the native Police creator clothing definition; existing starter gear grants only a real nightstick,
Police walkie-talkie and bounded ordinary survival supplies. Capture then makes those normal
profession, clothing and inventory states authoritative, so restore never reapplies the theme.
Automatic named triggers, real faction objectives, disposition realization, other faction
loadouts and persist-after-event policy differences remain later event-runtime responsibilities.

Scientists use the same one-time materialization boundary without inventing a parallel character
type. Build 42.20.3 has no Scientist profession, so the current medical-research entrant policy
uses the real balanced `base:doctor` profession, native Doctor creator clothing plus the real
`Base.JacketLong_Doctor`, and ordinary real `Base.Clipboard`, `Base.Pen` and `Base.Scalpel` items.
Only bounded normal water, food and medical rolls supplement that field kit. It grants no vial,
research result, firearm, artificial stat or combat multiplier. Once captured, the ordinary native
appearance/inventory record remains authoritative and the policy cannot issue the kit again.

Military entrants follow that same boundary using Build 42.20.3's real `base:veteran` profession
(including its native Aiming/Reloading boosts and Desensitized trait), native Veteran creator
clothing, and a bounded list of real army clothing items. Their ordinary field kit contains a
Hunting Knife, M9, one compatible 9mm magazine, three native five-round 9mm stacks and a military
walkie-talkie. Knox does not prefill the magazine, chamber a round or alter weapon accuracy; the
existing native reload/firearm controllers must establish all usable gun state. Capture remains
the one-time handoff to normal persistent appearance and inventory ownership.

Scavenger `scavenge_world` entries reuse the raid objective's real-transfer evidence instead of
creating abstract loot. At objective start, each member receives the existing `loot_area` search
bounded to 18 tiles around the persisted target. Only a completed native transfer from a real
world container into that member's real inventory creates a durable item-ID receipt. Containers
outside the area, other characters' inventories, queued/no-op transfers and duplicate receipts do
not count. Six items at most complete the search; three exhausted searches per member or the
two-hour deadline produce an honest partial/no-supplies outcome. Persistent Scavengers retain the
actual carried items and return to ordinary world life after withdrawal. Boss spawning remains
disabled and no automatic Scavenger trigger exists.

The first faction-specific objective is Police `secure_area`. Its event record owns only bounded
observation evidence: next scan time, same-floor loaded-zombie count, clear-window start and final
outcome. Every 0.02 world hours at most, the runtime counts living zombies within 18 tiles of the
persisted target (capped at 24). It never directs those zombies or Police actors; common perception,
combat and retreat systems retain ownership. A threat resets the clear window, while at least 0.05
world hours of separated zero-threat observations permits `area_secure` withdrawal. The deadline
records elapsed presence when positive clearance evidence is unavailable.

Companion survival missions reuse the existing persisted directive boundary rather than adding a
second planner or resource simulation. `find_food`, `find_water`, and `find_medical` are bounded
nearby searches over real world containers and carried/native items. The controller keeps the
companion's underlying order, interrupts it for the search, and restores that order when the
mission completes or is interrupted. Three unproductive attempts clear the directive with a
contextual failure message instead of looping forever. Automatic Knox events remain separately
gated by `EnableKnoxEvents`, which is off by default.

The player-facing menus call these **Survival Orders**. “Mission” remains an internal execution
term for a bounded temporary directive; base work continues to use durable jobs, while larger
long-distance expeditions can use the event/away-team domain later.

Party controls are thin wrappers over the same durable companion state. Relax is the ordinary
`relax` companion order applied to each selected member. Party vehicle controls call the existing
per-companion native passenger-seat actions; they do not create a second vehicle ownership or
teleport path.

The Find Better Weapon survival order reuses the same bounded nearby-container search as other
supply orders. It consults the equipment policy's safe usable-melee score and requires a meaningful
upgrade; the order never fabricates an item or overrides a usable firearm.

The general area order is presented as **Explore and Search Area**. It remains the existing bounded
loot-area directive: the name reflects that survivors travel through nearby buildings/containers,
search useful supplies, and leave when the local search is exhausted.
### Automatic base-duty selection fairness

`KS_BaseJobs.ensureAutomaticTask` discovers the existing task types and zones,
then evaluates all queued work that the resident can actually perform.  The
selection keeps role preference as the first pass and preserves task priority;
it only subtracts a bounded score from a task whose persisted `lastClaimedBy`
matches the resident.  This gives equal-priority recurring work a chance to
rotate between residents without introducing parallel scheduler state.  The
task board and native task execution remain unchanged.
### Base-task retry policy

The persisted task record owns retry timing for failed base actions.  A blocked
run increments `failureStreak` and applies bounded exponential backoff (0.25 to
8 world-hours); successful work resets that streak.  Controllers continue to
release native action ownership immediately, and the task board reopens the
same record only after `retryAtHours`.  This keeps temporary material or target
failures from becoming per-tick action storms without inventing a second queue.
### Initial cohort allocation

The world-population allocator may seed up to three compact travel cohorts when
enough identities exist.  Cohort count scales with population, uses nearby
same-floor player-spawn origins, and is deterministic per world age/index.  The
allocator removes selected identities from the solo pool, so no origin or member
is duplicated.  Small test populations retain the original single-pair path;
later relationship/faction systems remain responsible for additional grouping.
### Automatic duty hints

Base residents with an `auto` job preference use their persisted profession as a
selection hint only.  The hint is computed at assignment time and never rewrites
the player's duty preference.  Existing task eligibility, required materials,
priority, and fairness selection remain authoritative, so a profession can
prefer a role without claiming work it cannot perform.
### Completion pacing for recurring work

Base-task completion records a short `retryAtHours` interval before recurring
work can reopen.  Normal duties use a half-hour interval and depot sorting uses
a shorter queue-clearing interval.  This is persisted on the existing task
record, so unload/reload cannot erase the pacing, while failed actions continue
through their independent exponential backoff policy.
### Companion tool acquisition

`find_tools` is a bounded companion directive, not an abstract mission.  It
filters real nearby containers through the existing essential-tool policy,
reserves one unbroken item, and transfers it through the normal native inventory
action.  Completion and bounded failure both clear only the temporary directive,
leaving the companion's persistent Follow/Hold duty intact.

### Base-task material resupply

Base workers keep the claimed task as the authoritative intent.  When its
requirements are not currently available, the autonomy controller may perform
up to three bounded searches for an exact required full type in nearby real
containers.  A selected item is reserved and moved through the existing native
transfer action; after arrival, the controller re-evaluates the same task rather
than creating a second task or an abstract resource pool.  Failed attempts use
the task's existing persisted retry/backoff fields, and successful completion
resets the failure streak.  The standalone `KnoxBaseSupplyPlanner` only performs
safe requirement matching and never owns inventory, reservations, or task state.

### Base-needs scheduling

`KnoxBaseNeeds` is a small priority layer over the existing queued task list. It
reads `KnoxBaseStorage.summarize` when a real loaded-container snapshot exists,
keeps each task's original value in `basePriority`, and applies bounded bonuses
for shortages or urgent cleanup. It never creates tasks, changes eligibility, or
owns claims; `KnoxBaseJobs` and `KnoxBaseTaskBoard` remain the authoritative
scheduler and fairness boundary. Missing snapshots leave priorities unchanged.

### Persistent workforce rotation

When a task is claimed, persistence records `lastClaimedAtHours`. Both automatic
selection and the task-board fallback apply the same bounded recent-claim
penalty, while the existing priority and eligibility rules remain authoritative.
This keeps equal recurring work moving between eligible residents without adding
another roster or scheduler state, and the timestamp survives save/load.

### Off-screen base duty progression

`KS_UnloadedSurvival` inspects the resident's existing claimed base task while
advancing the persisted survival ledger. Only guard and patrol are abstracted as
time-based watch shifts; after a bounded four-hour shift the existing
`finishBaseTask` path records completion. World-changing tasks remain claimed and
are never simulated as completed without a loaded square and native action.
`KS_BaseDutySimulation` owns only this eligibility/time calculation, keeping
task ownership and persistence in their existing modules.

### Persistence normalization

The persistence root sanitizes new fields in place when loading older records.
Task priorities, retry counters, recency timestamps, off-screen shift time, and
duty revisions receive bounded defaults. Existing unloaded-life fields are only
clamped when present; a missing ledger remains missing until a real engine
capture supplies it. This preserves the distinction between an initialized
survivor and a record that has never had a valid body snapshot.

Full graph normalization runs once at the real `OnGameStart` save boundary and
again only if an authoritative top-level ModData domain table is replaced. Normal
gameplay accessors reuse that completed graph instead of scanning every survivor,
faction, camp, base, and task on each read. Persistence-owned mutation functions
maintain their local invariants directly; small externally mutable domains such as
the automatic event cursor and faction event identity validate only their own
record on access. This keeps corrupt-save repair while preventing autonomy and
combat ticks from turning persistence reads into repeated whole-world work.

### Base-task claim restoration

The task board owns a resident's durable claim while the autonomy controller
owns only its loaded execution state. On controller reconstruction,
`getClaimedBaseTaskForSurvivor` validates and returns that claim before any new
work is selected. Invalid owners and duplicate claims are returned to the queue;
the deterministic highest-priority claim survives. A one-time schema migration
repairs old saves globally, while normal restores scan only the resident's base.

### Companion patrol directive

`patrol_area` is a persisted companion directive layered over the existing
movement owner. `KS_CompanionPatrol` derives four inset waypoints from the saved
area and selects the next point from the survivor's real current square. The
controller moves through the normal directed path, pauses between points, and
retains the directive across temporary behavior preemption. Repeated invalid
targets clear the directive through the normal ownership-checked persistence
path. Off-screen `base_working` locations are accepted by materialization so
resident duty progress does not restore from a stale record square.

### Guard and base patrol semantics

Guard and Patrol share `KS_CompanionPatrol` only as an area-geometry helper;
their ownership remains different. Guard resolves one deterministic post from
the persistent task identity and then uses the existing timed watch duty.
Patrol resolves the next indexed waypoint, records each arrival on the existing
base-task record, enters a bounded pause, and requests the following stop
through the normal movement owner. A complete route resets its progress before
the task enters the existing recurring-work cooldown.

The task record, not the loaded controller, owns `patrolStep` and
`patrolStopsCompleted`. This lets interrupted or unloaded work resume without a
parallel patrol registry. Companion patrols continue to derive their start from
survivor identity so several companions do not intentionally select the same
first point; base routes derive it from task identity so changing workers does
not rotate a partially completed route.

### Canonical player-facing orders

`KS_OrderCatalog` is the vocabulary boundary for menus, notebook actions, and
future migrated saves. Familiar labels are aliases only; they normalize to the
existing Knox primary orders, companion directives, or base preferences before
validation and persistence. `KnoxCompanionService.issueOrder` and
`issueOrderAll` are the individual and party dispatch boundaries, while
`KS_BaseTaskBoard` and `KS_BaseJobs` retain ownership of task claims and native
world actions. This keeps broad survivor command coverage without adding a
second task manager or allowing UI labels to create divergent saved state.

### Resource away-team handoff

Resource away teams remain persisted rather than silently materialized. Their
state advances through outbound, awaiting_collection, collecting, returning,
and complete/blocked. A future loaded-world executor must explicitly materialize
the existing survivor record, reuse the normal autonomy and inventory-transfer
owners, and return the shell through the same capture/removal boundary. No
separate collector may create items or bodies outside that contract.

### Hibernation removal refusal and same-shell recovery

`KS_SurvivorAutonomy.hibernateDistantWorldSurvivors` remains the loaded-shell
teardown coordinator; `KS_UnloadedSurvival` owns the durable stored/loaded
ledger transition; `KS_SurvivorAutonomyController` owns resumption of that
same controller after transient native ownership has been released. If native
removal refuses and the bridge still returns the controller's exact body, the
coordinator must commit `rollbackStored` before returning the controller to
`IDLE`. The controller is not ticked while the ledger remains hibernated.
A failed rollback remains a recovery-pending loaded shell and retries ledger
reconciliation only; it must not repeat shutdown/removal or enter unloaded
simulation. If the bridge confirms the body absent, the already-committed
hibernation can complete and the existing activation path later restores the
same canonical identity. This boundary creates no second lifecycle manager or
replacement body. See BUG-KS-058 and its focused regression/Build 42 acceptance
in WORK_QUEUE.md and DEVELOPMENT_TESTING.md.
