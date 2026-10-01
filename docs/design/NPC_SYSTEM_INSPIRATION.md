<!-- modforge-doc
authority: canonical
load: on-demand
purpose: NPC-system design direction derived from owner research and current Knox implementation
-->

# Knox Survivors — NPC system design direction

Updated: 2026-09-28

## 2026-09-30 Workshop reference review — player expectations only

The public description for the historical *Superb Survivors!* Workshop item
describes a player expectation set: survivors seek basic necessities and
shelter, can be approached/recruited, accept orders, perform recognizable base
roles, and may be hostile. This is useful as a reminder that NPCs need to be
findable, understandable, and visibly useful; it is not a Knox implementation
specification. The page identifies the item as Build 41, single-player, work in
progress, and currently incompatible/removed from the Workshop. Its removal
notice does not state a reason, so no legal or moderation conclusion is drawn.

Against current Knox authorities, the underlying identity, encounters,
relationships, group/faction membership, orders, base work, real storage,
combat, persistence, and offscreen continuity owners already exist. Their main
unfinished product question is whether they produce a clear, observable native
outcome in the live game: especially BUG-KS-013's base day and BUG-KS-015's
real loot/receipt/resupply replay. Recruitment, group behavior, hostile
encounters, and UI clarity likewise remain acceptance- or issue-specific; the
old description is not evidence that Knox lacks those systems. Keep quests,
scripted raids, and broad feature parity out of scope unless separately
approved against Knox's existing rules. Nearby owned-survivor map grouping is
already implemented offline under BUG-KS-021; faction-base markers remain
deferred under BUG-KS-022.

This comparison uses the public description only as high-level player-facing
reference. No source code, assets, text, data structures, or interface layout
from the old item are used or reproduced. Project Zomboid remains the technical
foundation, and Knox's own owners and acceptance evidence remain authoritative.
Reference: [Steam Workshop item 1905148104](https://steamcommunity.com/sharedfiles/filedetails/?id=1905148104).

## Core rule

> **A Knox survivor is another Project Zomboid survivor controlled by AI, not a colony-game pawn.**

Project Zomboid remains the foundation. Other games are references for solving specific AI/design problems, not templates to copy wholesale.

The desired result is a living human population whose survivors:

- have persistent identity, history, relationships, possessions, health, skills and responsibilities;
- physically use Project Zomboid's real world, items, containers, actions and combat while loaded;
- continue the same goals in a cheaper abstract form while unloaded;
- make choices without requiring constant player micromanagement;
- remain rare enough that individuals, deaths, specialists and factions matter.

## Research provenance

This direction was promoted from the owner's 2026-09-26 research notes covering:

- Project Zomboid's published NPC/metaverse concepts;
- RimWorld;
- Survivalist: Invisible Strain;
- State of Decay 2;
- Rebuild 3;
- Dead State.

Re-verified 2026-09-28 against live TIS sources. The research is inspiration only. No proprietary code, assets, text, data, or exact implementations from those games are to be copied.

## What each reference contributes

| Reference | Useful lesson for Knox | What Knox should avoid |
|---|---|---|
| Project Zomboid NPC plans | Loaded ↔ off-screen continuity, persistent people, groups, goals, world events and simplified distant simulation | Simulating full physical AI across the whole map |
| RimWorld | One concrete job at a time, work priorities, job claims/reservations, storage priority | Turning humans into programmable colony pawns |
| Survivalist: Invisible Strain | Prioritized roles, autonomous communities, social memories, relationships, organized storage | Requiring the player to micromanage every survivor |
| State of Decay 2 | Individual usefulness, specialists, community pressure and consequences when a useful survivor is lost | Converting Project Zomboid's real items into generic resource counters |
| Rebuild 3 | Group-level goals, missions, faction decisions, survivor specialties and generated events | Turning Knox into a strategy-map game |
| Dead State | Base responsibilities driven by actual shortages/problems, specialists and useful facilities | Depending on scripted crisis events for normal life |

### Primary research links

- Project Zomboid, current planned-features page (still lists NPC survivors driven by off-screen survival): https://projectzomboid.com/blog/the-game/
- Project Zomboid, *The Zuckerverse* (off-screen storylets and explicit Crusader Kings inspiration): https://projectzomboid.com/blog/news/2022/03/the-zuckerverse/
- Project Zomboid, *The Coding of the Living Dead*: https://projectzomboid.com/blog/news/2012/10/the-coding-of-the-living-dead/
- Project Zomboid, NPC/metagame discussion: https://projectzomboid.com/blog/news/2014/07/its-an-npc-related-mondoid1-no-hype-pls/
- Project Zomboid, *Lone Survivor*: https://projectzomboid.com/blog/news/2022/04/lone-survivor/
- Project Zomboid, *On the Verge*: https://projectzomboid.com/blog/news/2013/07/on-the-verge/
- RimWorld hauling/work reference: https://rimworldwiki.com/wiki/Hauling and https://rimworldwiki.com/index.php?title=Work
- Survivalist: Invisible Strain: https://store.steampowered.com/app/1054510/
- Survivalist multiple roles / storage policy / Organizer patch: https://steamdb.info/patchnotes/9371355/
- Survivalist organizer-role conflict + gossip/memory decay patch: https://steamdb.info/patchnotes/13486262/
- State of Decay 2 official player guide: https://www.stateofdecay.com/wp-content/uploads/2022/07/PlayerGuide.pdf
- Rebuild 3: https://www.rebuildgame.com/about.php and https://store.steampowered.com/app/257170/
- Dead State jobs/allies references: https://deadstate.fandom.com/wiki/Jobs and https://deadstate.fandom.com/wiki/Allies

## 2026 research verification and one useful addition

The research direction still matches Project Zomboid's current public plan: its official game page continues to describe planned NPC survivors as using a system that tracks off-screen survival. The 2022 NPC framework article describes the unloaded world as a simplified, event-driven **storylet** simulation rather than full physical pathfinding everywhere.

That article also explicitly names **Crusader Kings** as an inspiration for dynamic NPC stories. For Knox, the useful lesson is narrow:

- create reusable event/storylet templates with clear conditions;
- feed them real survivor traits, relationships, group state, location and shortages;
- let outcomes update persistent state and memories;
- materialize only the physical consequences that matter when the survivor returns to the loaded world.

Do **not** turn Knox into a grand-strategy character simulator. Crusader Kings belongs in the research set specifically for procedural story/event structure, while Project Zomboid remains the simulation and gameplay foundation.

## TIS vision synthesis (verified 2026-09-28)

This section distils what The Indie Stone have actually published, so Codex implements toward the same shape TIS describes without guessing at engine internals.

### 1. NPCs are players with AI brains

2014 TIS direction: no separate survivor object class diverging from the player. An NPC is a player object driven through the same movement/combat/inventory mechanisms, plus a despawn/respawn path into an abstract world model. Knox already follows this shape: stable Knox identity owns the person; a contained `KnoxIsoPlayerShell` is only the temporary loaded body (`docs/ARCHITECTURE.md`). Never invert that ownership.

Implementation consequences for Codex:

- All durable state lives in `KS_Persistence.lua` / Java survivor records by stable ID, never on the transient shell.
- Shell teardown must capture tile, inventory, worn/hand slots, needs and orders before removal; restoration must re-create one body with the same ID.
- `IsoPlayer.players[]`, `setInstance`, camera/input ownership are never NPC tools. See `ARCHITECTURE.md` hard constraints.

### 2. Meta = abstract storylets, not distant physics

TIS "metaverse" model (2012/2022):

- Off-screen Kentucky is void + knowledge of buildings, rooms, roads, zombie density — not pathfinding biters everywhere.
- Each NPC/group is a virtual token moving between buildings along roads at plausible speed (foot vs vehicle).
- A library of conditioned events fires on triggers such as travel, meeting, looting, shelter, illness. Personality, skill, weapon, group state weight the branch.
- Events set flags, move tokens, change state, and attach a context-customizable recount line so survivors can later tell the player or each other what happened.
- Narratives chain: one outcome opens the next eligible event; flags enable future narratives weeks later.

Knox translation (already the architecture, to be connected not replaced):

- Loaded: `KS_SurvivorAutonomyController.lua` + executors own real movement, native timed actions, combat, transfers.
- Unloaded: `KS_UnloadedSurvival.lua` + `KS_OffscreenStories.lua` + `KS_WorldPopulation.lua` itinerary advance needs, rest, coarse travel, one persisted story attempt per phase, bounded supply consumption.
- Return: `KS_WorldTraces.lua` + `KS_EventRuntime.lua`/`KS_KnoxEvents.lua` materialize only what reconciles safely: position, needs, real carried supplies, relationship/history, traces. Never manufacture native combat, loot, death, blood, smashed windows, or terminal raid outcomes off-screen (see `BUG-KS-001`, `BUG-KS-002`, `BUG-KS-024`).

### 3. Three TIS stages map directly to Knox gates

1. **Event library** — chainable, conditioned, weighted storylets. Knox: off-screen stories, encounters, faction events, world traces. Must stay bounded, deterministic where practical, persisted once.
2. **Manifest to the player** — behaviours, scripted dialogue, and player roles for witnessed events. Knox: autonomy executors, `KS_SurvivorDialogue.lua`, activity feed, speech indicators, gestures, trade/talk/recruit. Every abstract outcome that can be witnessed needs an explicit loaded behaviour + dialogue + safe fallback.
3. **Alter the world** — persist what happened at a building/area so next load reflects it. Knox: world traces, corpse/barricade/repair state, storage contents, faction base records. Only loaded native actions mutate geometry; unloaded outcomes queue as retryable traces.

### 4. Observations, traits, and looting missions

2012 TIS sketches: survivors observed over time yield trait notes; the player picks looting-mission members by capability; they leave, time passes, they return with supplies, injuries, or not at all. Knox equivalent:

- `KS_SurvivorCapabilities.lua`, origins/profession/traits, perk/XP persistence feed suitability — never a permanent caste label.
- `KS_GroupScavenge.lua`, away-team executor, base supply planner convert a real shortage into one owned mission with reserved members, equipment checks, destination, ETA, and real-item return — never free-item generation.
- Survivor Card / Notebook / HUD present capability and history honestly; they never promise what offline doubles cannot prove.

## Immersive / natural / smooth — Knox feel guide

Use this as the acceptance lens for every system below. If a change breaks any line, it is not an improvement.

### Immersive (believable people in a real apocalypse)

- Survivors act from needs, orders, duties, and memory — never random wandering to look busy.
- Speech, gestures, activity labels, and Notebook history describe what actually happened or is happening.
- Death, injury, loss of a specialist, and faction moves have visible consequences through real skills, real stocks, and real rosters.
- No magic: no spawned food/ammo/fuel, no invented kills, no teleport catch-up, no second body for the same person.

### Natural (Project Zomboid first)

- Loaded behaviour uses vanilla movement, doors/windows/fences, containers, timed actions, combat, farming, repair, cooking, medical, and vehicle entry — with Knox supplying intent, not reimplementing physics.
- Idle life uses furniture, books, TV, rest, snacks, hygiene, ambient walks — the base-life decision path in `BUG-KS-013` is the checklist, not a new idle minigame.
- Social contact is proximity + awareness + agreement: approach, face, greet, converse, invite. Proximity alone never forces a party; hostility is durable and blocks talk/recruit.
- Player orders are durable commitments (Follow/Hold/Return/Guard/Move/Loot directives + traversal policy). Danger and critical needs may interrupt; ordinary autonomy must not silently overwrite them.

### Smooth (no fights over the same body)

- One primary intention + one active job + bounded emergency reactions. Exactly one owner writes movement/combat/action input at a time.
- Every job answers the universal lifecycle: can/why start, owner, reservations, interrupts, resume, invalidation, failure, completion, off-screen equivalent, rematerialization reconciliation.
- Reservations expire or release on completion, failure, interruption, hibernation, and owner loss. A stuck claim is a bug.
- Feedback is restrained: activity state, short speech, HUD/Notebook updates, order results, real problems. No per-tick spam, no duplicate route spam, no run-stop-return loops.

### Fluid (never freeze, always continue thinking)

The fence pause taught this law: a survivor must never stand frozen while its brain catches up. The proven pattern generalizes to every traversal, combat, and action handoff:

- Observe native completion state *before* applying any refresh cadence — a climb that finished between ticks must not hide behind the old deadline.
- Latch the busy state, leave the native action untouched, and reevaluate on the first landed/completed update.
- A successful route or action returns to `IDLE` for next-tick arbitration; the success handler issues no new movement itself and imposes no timed wait.
- Interruption (danger, injury, order change, detachment) releases ownership on the same update; the durable duty survives and resumes through the normal loop.
- Pace-only changes update the live request; only meaningful slot, floor, or blockage changes replace a destination.
- Bounded diagnostics (`traversal_started/completed`, state/decision/destination/failure/retry in status logs) so a real stall is distinguishable from thinking.

Player-visible bar, from community research on what kills NPC mods: followers never vanish, clone, or return as strangers; hold orders actually hold (no stealth-blasting); nobody loops pickup-swing-loot-pickup; nobody reissues routes every frame; a blocked-edge cooldown picks another route instead of hammering a locked door. Reliability is the ceiling — features never outrank it.

## Operating model

Every survivor should converge on this loop:

`persistent survivor state`
→ `decision / priority arbitration`
→ `one primary job`
→ `physical or abstract execution`
→ `result / world consequences`
→ `state, relationship and history updates`
→ `choose again`

### The key ownership rule

A survivor normally has:

**one primary intention + one active job + emergency reactions**

Emergency survival/combat can interrupt a job. It should not create multiple permanent systems fighting for movement/action ownership.

This is an architectural direction, not a request to rewrite every existing Knox controller at once.

## Priority hierarchy

The exact numeric weights may remain internal, but the conceptual ordering should be approximately:

1. immediate survival;
2. life-saving emergency;
3. critical physical need;
4. active combat/threat response;
5. direct player commitment/order;
6. group/base responsibility;
7. assigned role/preference;
8. ordinary autonomous work;
9. social/personal/free activity.

A lower layer should not continuously steal ownership from a valid higher layer.

## Universal job lifecycle target

Existing Knox systems should gradually expose the same lifecycle questions:

- Can this job start?
- Why should it start now?
- What survivor owns it?
- What items, destination, container, bed, corpse, vehicle, target or worksite does it reserve?
- What can interrupt it?
- Can it resume?
- What invalidates it?
- What happens on failure?
- What happens on completion?
- Is there a safe off-screen equivalent?
- What state must be reconciled when the survivor materializes again?

Barricading remains barricading. Corpse hauling remains corpse hauling. Firearms remain firearms. Scavenging remains scavenging. The goal is shared operating rules around those systems, not replacement for replacement's sake.

## Current repository mapping

The current Knox worktree already contains much of the foundation. The table below distinguishes **existing implementation** from the broader design target.

| Design concept | Current Knox foundation | Current status / gap |
|---|---|---|
| Decision owner | `KS_SurvivorAutonomyController.lua` and `KS_SurvivorAutonomy.lua` | **Partial.** There is a central autonomy/controller path, but not every behavior is expressed through one universal job contract yet. |
| Reservations / claims | autonomy reservation tables, `KS_BaseTaskBoard.lua`, base-task claims, group/support leases | **Partial.** Strong subsystem claims exist; a single shared reservation API across every job type does not yet exist. |
| Base needs | `KS_BaseNeeds.lua`, `KS_BaseJobs.lua`, `KS_BaseSupplyPlanner.lua` | **Implemented foundation.** Needs can influence base work and supplies; this can grow into broader mission generation. |
| Work priority / roles | `KS_BaseJobs.lua`, survivor origin/job preferences, duty scheduling | **Implemented foundation.** Preferences and task eligibility exist; richer prioritized multi-role profiles remain a design direction. |
| Organized storage | `KS_BaseStorage.lua`, `KS_BaseOrganize.lua`, supply planner | **Implemented/active work.** Current organizer code already avoids reserved items and re-resolves destinations. |
| Group planning | `KS_GroupScavenge.lua`, travel groups, away-team/event systems | **Partial.** Specific coordinated group behaviors exist; there is not yet one generic planner converting any group need into a mission. |
| Persistent relationships | `KS_Persistence.lua`, `KS_SurvivorRelationships.lua` | **Implemented foundation.** Meetings, shared activity, trust/disposition and faction relationships are persisted. |
| Event → memory → relationship | relationship encounter history, off-screen stories/events | **Partial.** Gameplay history exists, but a general-purpose named memory ledger with decay/gossip/consequences is not yet a universal system. |
| Loaded ↔ unloaded continuity | `KS_UnloadedSurvival.lua`, persistence, lifecycle policy, off-screen stories | **Implemented foundation.** Same survivor persists through loaded/hibernated states; additional job equivalence and reconciliation can be generalized. |
| World evidence after off-screen events | `KS_WorldTraces.lua`, event runtime | **Implemented/active work.** Abstract events can leave materialized traces rather than disappearing as pure text. |
| Materialization / reconciliation | persistence capture/restore, lifecycle and population systems | **Implemented foundation.** This remains one of the highest-risk areas and must stay identity-safe. |
| Rare meaningful population | world population, groups/factions/camps | **Existing policy direction.** Balance values remain tunable; design should continue favoring significance over endless replacement. |

## System dossiers — how each part should work and be implemented

Each dossier follows the same contract so Codex can implement without re-planning: **feel → PZ-native behaviour → Knox owners → inspiration translation → must never → acceptance/validation**. Authority remains `FEATURE_SPEC.md` for scope, `ARCHITECTURE.md` for ownership, `QA_RELEASE.md` + `DEVELOPMENT_TESTING.md` for evidence, `WORK_QUEUE.md`/`BUGS.md` for task state.

### 1. Identity, persistence, lifecycle

Should feel like the same person every time you meet them — same face, name, voice, gear, injuries, memory of you.

PZ-native behaviour: one stable ID owns appearance, profession/traits/perks, inventory snapshot, `BodyDamage`, physiology, location, affiliation, duty, relationships, history. The shell is disposable. Save captures every active runtime, not the last actor. Migrations normalize in place and never erase a person.

Knox owners: `KS_Persistence.lua`, Java survivor records, `KS_SurvivorLifecyclePolicy.lua`, `KS_SurvivorRuntime.lua`, `KS_WorldPopulation.lua`. Related queue: `KS-PROD-008` dependency step 1; `BUG-KS-008`.

Inspiration translation: TIS persistent people + metaverse despawn/reassemble; Dwarf Fortress-style durable identity without its colony complexity.

Must never: duplicate bodies, replace identity on restore, lose inventory/orders on hibernation, trust a shell as save truth, write NPCs into local-player slots.

Acceptance: save/reload preserves ID, body state, inventory, equipment, orders; hibernation/rematerialization preserves the same; no duplicate/stale/invisible bodies. Validation: lifecycle-policy + persistence-recovery focused tests, then disposable-save live replay per `CURRENT_STATE.md`.

### 2. Off-screen continuity, storylets, traces

Should feel like life continued while you were away — they travelled, rested, ate from their packs, met someone, left a trace — never like the world rolled dice for corpses and loot. Off-screen simulation is continuous and real, only cheaper: the same person, same intent, same rates, real consumption, deterministic history — without loaded bodies, pathfinding, animation, or per-tick cost. Nothing is faked to save performance; anything that needs a native body waits for one.

PZ-native behaviour: unloaded ledger keeps ID, destination, mission, group, carried supplies, needs, intent. Coarse travel (same floor, bounded legs/hours), real supply consumption from the portable record, rest/sleep phases, one story attempt per phase. Physical outcomes (blood, smashed windows, death, loot, raid results) wait for loaded native evidence; failed materialization stays retryable.

Knox owners: `KS_UnloadedSurvival.lua`, `KS_OffscreenStories.lua`, `KS_WorldTraces.lua`, `KS_EventRuntime.lua`, `KS_KnoxEvents.lua`. Related: `BUG-KS-001`, `BUG-KS-002`, `BUG-KS-024`.

Inspiration translation: TIS storylets + CK event chains + Zed Stories world alteration, implemented as conditioned templates with flags, weights from traits/skills/relationships/shortages, and recount lines. Rebuild contributes group-goal framing; Dead State contributes shortage-driven pressure without scripted-crisis dependence.

Must never: abstract scuffles that kill off-screen, unloaded raids declaring victory/defeat, consumed traces on failed placement, invented supplies.

Acceptance: loaded → unloaded → loaded replay shows coherent travel/needs/history, retryable traces, no fabricated outcomes. Validation: six focused event/trace tests + unloaded/group/base-return tests offline, then live raid/trace replay.

#### 2A. Off-screen survival ledger — exactly what Codex owns

File: `KS_UnloadedSurvival.lua:1`. Rules, not physics:

- Step cap `MAX_STEP_HOURS = 6`; meal triggers match loaded thresholds (`FOOD_TRIGGER = 0.45`, `WATER_TRIGGER = 0.45`); hunger `0.026`/hr, thirst `0.040`/hr; starvation `1.20`/hr, dehydration `2.00`/hr.
- Rest model: walk spends endurance `0.025`/hr; rest restores `0.090`/hr from `0.30` to `0.80`; sleep recovers fatigue `0.055`/hr from `0.72` to `0.35`, max 8 transitions per 6h step. These are coarse Knox rates, not native sleep physiology.
- Travel: return trips `40` tiles/game-hour; vehicle legs `300`; pre-materialization itinerary max 8 legs / 48h catch-up, same floor, within 600 tiles, 40 net tiles/hr with 2–5h stops. Captured independents reuse catalog itinerary; no `1.25 tiles/hr` drift heading.
- Groups: fully stored cohorts advance one shared `unloadedTravel` itinerary; condition derives from member ledgers; shared delta preserves offsets; highest fatigue / lowest endurance sets rest; >20 tiles triggers leader wait + bounded approach to 6 tiles; different floors never invent stair routes; active member or conflicting duty blocks cohort travel.
- Duty: only `guard`/`patrol` accrue off-screen watch time via `KS_BaseDutySimulation.lua:14` (`canAdvanceOffscreen`); world-changing jobs stay claimed and resume loaded. Away-team missions keep their own travel/recovery policy.
- Consumption: `consumeStoredSupply` decodes detached native items only; ordinary safe food via `multiplyFoodValues`, clean water at `0.12` fluid per `0.1` thirst; partials/reusables persist; unsafe/scripted/byproduct/quantity-unknown cases defer to loaded actions; never spend serialized inventory while the live body still owns it (`nativeBodyAbsent` guard).
- Base return: hibernated residents restore at a safe valid point inside own territory, not the capture tile or a stack; `areaDimensions` handles inclusive min/max vs legacy spans.

Off-screen storylets (`KS_OffscreenStories.lua:11`): at most one narrative event per step; bounded, deterministic, ledger-recorded; history cap 12, scar cap 4; effects land only on survivor ledger, relationship records, queued scar traces, activity feed. Hard bans: no need relief without real items, no health gain, no items/loot/supplies, no world mutation, never touch away-team/event-owned/non-hibernated survivors. Pair/phase token is canonical; meet radius 60, detour max 10, scan cap 48, ride min distance 150.

Traces (`KS_WorldTraces.lua`): `markTraceVisited` only on materialization success; breach success = blood helper success OR ≥1 window smash; throwing/false paths stay retryable and consume exactly once on later success.

Prioritize in this order: (1) identity-safe hibernate/restore with no duplicates (`BUG-KS-024`, `BUG-KS-008`); (2) needs/travel/rest parity loaded vs unloaded; (3) storylet breadth only after (1)–(2) are live-verified; (4) trace retry/materialization. OpenCode owns narrow retry/ledger fixes; Codex owns lifecycle/ownership/cross-member changes.

### 3. Brains, autonomy, arbitration

Should feel like a person choosing one sensible thing, pausing for danger, then resuming — not a puppet vibrating between orders.

PZ-native behaviour: one controller tick selects one state (threat, injury, critical need, loot, travel). Executors own how. Threat interrupts travel/loot; executors finish/fail/cancel before another writes input. Self-care verifies real state change, installs one bounded retry, preserves Follow/Hold/group duty across interruption.

Knox owners: `KS_SurvivorAutonomyController.lua`, `KS_SurvivorAutonomy.lua`, needs/loot/medical probes. Related: `KS-PROD-008` step 2; `BUG-KS-013`, `BUG-KS-025`.

Inspiration translation: RimWorld one-job-at-a-time + manual priorities as ordering intuition; Survivalist role priorities without micromanagement burden; Kenshi-style squad-duty persistence as future study only.

Must never: parallel controllers fighting for movement, per-tick reselection storms, autonomy overwriting a valid player order, infinite retry loops.

Acceptance: fresh-save observation shows needs/interruption/resumption with bounded diagnostics; idle residents choose base-life, not parking. Validation: autonomy/lifecycle/formation/behaviour focused tests, then live day-long base observation.

### 4. Reservations and claims

Should feel like competent housemates — nobody steals the plank, bed, corpse, seat, or kill another is already handling.

PZ-native behaviour: before taking/moving a resource, check active job, loadout, need, or reservation. Categories: item/stack, container/slot, work target, destination square, bed/rest point, corpse, barricade/window/door, vehicle/seat, combat target where exclusivity matters, support recipient, mission slot. Release on completion/failure/interruption/hibernation/owner loss.

Knox owners: autonomy reservation tables, `KS_BaseTaskBoard.lua`, `KS_GroupSupport.lua`, container/item targeting in storage/organize/looting. Direction: unify semantics without breaking working specialized claims. Atomic claim boundary is `KnoxPersistence.claimBaseTask`; selection defers to `KS_BaseJobs.selectEligibleTask` when loaded (`KS_BaseTaskBoard.lua:64`).

Inspiration translation: RimWorld reservations + Survivalist organizer conflicts + reserved-storage lessons. The failure it prevents is the organizer taking a job's material.

Must never: a second global ledger competing with task-board claims; silent claim leaks after cancel/death/reload.

Acceptance: two workers never take the same target; blocked/claimed work fails over to alternate work with visible reason. Validation: task-board/claim focused tests + live two-worker crew replays.

#### 4A. Reservation contract Codex must preserve

Check-before-take order everywhere: active task claim → loadout/need reservation → container/slot policy → world target. Release triggers: completion, failure, interruption, hibernation, owner loss, duty change, death. A stuck claim after cancel/death/reload is a bug, not a tuning issue.

Covered today: task-board atomic claims with `lastClaimedBy`/`lastClaimedAtHours` fairness; group-support recipient+item single-transfer leases with verified source/destination containers; combat target caps (1 ordinary / 2 immediate / 3 defending); organizer destination re-resolution that skips reserved/favorite/equipped/job-required/foreign items; vehicle-seat single-request leases; support-recipient exclusivity.

Do not add a universal reservation manager as a second owner. Generalize by converging compatible claim/lease checks behind shared own/release semantics only where it fixes a proven steal/leak. Route any new reservable (bed, corpse, barricade target, mission slot) through the existing task/claim owner for that family.

### 5. Movement, pathing, traversal

Should feel like walking with you — steady follow, sensible doors/fences, brief pauses only for real obstacles, no teleport rescue.

PZ-native behaviour: engine pathfinder supplies routes; Knox supplies intent. Staggered follow slots, bounded refresh cadence, native traversal ownership (climb/vault/fence/sheet-rope), first-landed reevaluation, retry cooldowns on failed edges, stuck detection from real displacement. Leader waits / walks back for separated members; different floors use loaded navigation, never invented stair routes.

Knox owners: Java traversal runtime, `KS_GroupCohesion.lua`, formation follow, companion service. Related: `BUG-KS-011`, `BUG-KS-028`, `BUG-KS-019`.

Inspiration translation: Survivalist follow/zone intuition (stay in role, return after errand) without its policy-spiral micromanagement; Mount & Blade party-travel pacing as future study only.

Must never: teleport followers, reissue native movement in a loop, hold a follower in a timed wait after native success, walk through obstacles, tour the neighbourhood for an in-area patrol.

Acceptance: leader-plus-two-followers route through travel, door/fence, interruption, recovery with no route spam or multi-second post-landing freeze. Validation: formation/order/conversation focused tests, then live fence/door replay.

### 6. Native actions and interruption

Should feel like hands doing real work — search, carry, equip, treat, repair, harvest — that can be interrupted by danger and resumed or cleanly failed.

PZ-native behaviour: prefer ordinary timed actions and inventory APIs. One lease owns the exact action; expiry/injury/queue-removal/retirement/reset release it. Persistent duty resumes after. Sitting recovers endurance; native sleep event owns fatigue; danger wakes via engine event without touching fades/time controls.

Knox owners: action adapters, companion vehicle leases, base-job executors (barricade/repair/farm/cook/chop/saw/corpse/animal-care), medical/loot executors. Related: `KS-PROD-005` native-action gate.

Inspiration translation: TIS "behaviour-tree" confidence — small robust behaviours composed by the controller, not scripted cutscenes.

Must never: fabricate item transfer, completion, or damage; leave queued native work after duty change; remote-toggle appliances or inventories.

Acceptance: one native work action and one danger-interrupted action verified in game with real inventory/world change. Validation: action-ownership focused tests, then live single-action replay.

### 7. Combat, threat awareness, retreat, firearms

Should feel dangerous but fair — they notice, face, fight with what they carry, call for help when it matters, and run when it is hopeless.

PZ-native behaviour: threat layers (proximity, visible, targeting ally/self) with hysteresis; bounded target reservations (1 ordinary, 2 immediate/group, 3 defending an attacked survivor); companion/group leashes so one zombie does not pull the party. Melee through native swipe/collision/damage; firearms through native readiness/reload/rack/attack-hook ownership; Knox only selects carried functional weapons and refuses duplicate prep actions. Retreat needs a real open lane + visible/targeting danger; healthy equipped survivors hold 1v1/small non-targeting fights; critical health/injury/exhaustion or crowd pressure admits retreat through existing native movement with two-safe-scan completion and order preservation.

Knox owners: `KS_ZombieAwareness.lua`, `KS_ThreatClassifier.lua`, combat/firearm support, group cohesion. Related: `BUG-KS-009`, `BUG-KS-012`, `BUG-KS-029`.

Inspiration translation: State of Decay specialist consequence (losing the shooter matters because skill/ammo are real); Dead State danger prioritization without scripted rescues.

Must never: off-slot lighting writes, invented hits/damage/kills, friendly-fire carelessness, run-stop-return loops, guard-duty autonomous retreat where ownership forbids it.

Acceptance: controlled 1v1 hold, small-group hold, overwhelming-group retreat through a viable lane and recovery — all with native health/ammo/position evidence. Validation: zombie-awareness/combat-intelligence/formation focused tests, then live duel + bystander + save/reload replay.

Owner proposal for a later retreat-policy design (not approved for implementation
in this pass): confidence should weigh health/injuries, armor/equipment,
weapons/ammunition, strength/fitness/skills, personal and group strength,
whether the player fights or flees, prior combat success/survival, recent
injuries/failures, morale, needs/moodles, surprise/preparation, encirclement,
choke points/escape routes, and group cohesion, with only a bounded random
factor. Keep BUG-KS-012's current bounded retreat policy stable until this
multi-factor design has an explicit owner decision, behavior table, and live
acceptance plan. Do not turn the proposal into independent roll modifiers or a
second combat owner.

### 8. Needs, health, inventory, equipment

Should feel like bodies with limits — hunger, thirst, fatigue, endurance, injury, capacity — solved with real things, not bars that fill themselves.

PZ-native behaviour: loaded needs use carried safe food/water, native eat/drink/bandage/improvise actions, verified state change. Off-screen consumption decodes detached native items at real ratios (including bottle fluid math), keeps reusables/partials, skips unsafe/scripted/byproduct cases for loaded handling. Equipment evaluation prefers real upgrades (weapon, protection, bag, tools) with favorite/equipped protection and carry-load honesty.

Knox owners: needs/medical/equipment/loot probes, `KS_SurvivorLooting.lua`, `KS_GroupSupport.lua` sharing (one real item, donor reserves, verified containers). Related: `BUG-KS-015`.

Inspiration translation: State of Decay real-supply pressure; Survivalist role-item intuition (farmers hold seed/water, cooks hold food) without hoarding loops.

Must never: consume without source removal + need relief, duplicate/deposit phantom items, eat unsafe food off-screen, abandon role for a detour (travelling groups/companions exempt).

Acceptance: real loot → typed storage → need/job withdrawal preserves identity/counts across save/reload. Validation: storage/supply/needs/cleanup/inventory focused tests, then live multi-day food/water replay.

### 9. Storage, organizing, supplies

Should feel like a shared house with labelled cupboards — deposits land where they belong, the cook can find food, the builder can find planks.

PZ-native behaviour: typed storage policies on real containers (including multi-compartment furniture), General fallback for unclassified real items, typed overflow, capacity awareness, same-role multiples. Organizer moves one real item per cycle through native transfer, skips reserved/favorite/equipped/job-required/foreign items, re-resolves destinations. Supply planner connects shortages to gathering without bulk free kits.

Knox owners: `KS_BaseStorage.lua`, `KS_BaseOrganize.lua`, `KS_BaseSupplyPlanner.lua`, `KS_BaseContextMenu.lua`, `KS_BaseManager.lua` categories. Related: `BUG-KS-015`, `BUG-KS-016`; roadmap ground-item candidate stays deferred.

Inspiration translation: RimWorld stockpile priority + hauling order; Survivalist organizer + storage-zone lessons (nearest-valid vs correct-store tension, distance/capacity honesty).

Must never: second inventory/stockpile owner, ground-stockpile invention, category mismatch between menu and manager, organizer stealing reserved loads.

Acceptance: typed deposit, General fallback, logs/firewood routing, overflow, save/reload identity/count. Validation: base-storage/menu/organize/supply/planner/job focused tests, then live deposit/withdrawal replay.

#### 9A. RimWorld storage model — how Knox implements it today

Categories (`KS_BaseManager.lua:25`, mirrored in `KS_BaseStorage.lua:64`): `food, water, medical, weapons, ammunition, tools, logs, building, farming, clothing, junk` plus assignable `general`. Menu, manager registry, and persistence validator must admit the same set — `BUG-KS-016` was exactly this mismatch (`logs` visible in menu but rejected by manager; `general` implemented but not assignable). Any new category needs all three updated together with focused coverage.

Matching (`KS_BaseStorage.lua:291`): `supplies` accepts anything (legacy); `food` accepts `IsFood`/DisplayCategory Food plus water items, with safe-food filtering at meal choice; `general` accepts anything unclassified; all others use `matchesCategory` (medical bandage/tool types, weapon/ammo tags, log/firewood types, etc.). Labels live in `Storage.label` (`KS_BaseStorage.lua:259`).

Deposit ranking (RimWorld stockpile priority, PZ-native): priority tier first (`critical 0 < preferred 1 < normal 2 < low 3`, `KS_BaseStorage.lua:270`), then exact-type match, then distance. Same-role multiples, typed overflow, and General fallback are supported; container deposit stays preferred. A valid typed container beats General; General beats nothing; ground placement is only the deferred roadmap candidate and must never appear silently. Native `VehicleMaintenance` parts (tires, batteries, brakes, gas tanks — verified in installed Build 42 item scripts) resolve to the Materials role through the existing building matcher; mechanic hand tools were already Tools. No vehicle role or stockpile owner was added.

Organizer (`KS_BaseOrganize.lua:1`): ambient re-shelving only — one bounded round per idle decision, `SCAN_RADIUS 16`, `MAX_INSPECT 40`, `STEP_TIMEOUT_TICKS 1800`. A move qualifies only when strictly better: higher priority tier, or misplaced-item (current shelf rejects it) to an accepting shelf. Equal-tier shuffles never qualify so settled bases stay settled. Not a task-board job; central sorting stays retired. Executes through the same native transfers as deposits; interrupted carry stays in pocket for the next pass.

Supply planner (`KS_BaseSupplyPlanner.lua:13`, `KS_BaseNeeds.lua:19`): answers only whether an existing world item satisfies a declared requirement; counts/moves/reserves nothing. `matchesRequirement` enforces usable/broken/uses/water rules so a broken/empty duplicate cannot satisfy work; `missingRequirements` nets out already-carried stock so workers do not over-fetch. `Needs.priorityBonus` layers a small explainable bump over persisted priority (corpse 24, cook/harvest/seed 20 when food < 3/person, water 16, building 12, guard/patrol 6) and only applies when ≥1 assigned container was actually inspected — zero loaded policies means unknown, not shortage.

Survivalist lessons applied: organizers fix misplacements (do not let non-organizers dump anywhere); role items stay carried (farmers hold seed/water, cooks hold food); distance/capacity are honest (near valid beats far correct only within the ranking above; full/blocked/unloaded/out-of-base destinations leave ownership unchanged with retry/backoff).

Prioritize: (1) keep menu/manager/persistence categories in lockstep; (2) protect reserved/job-required/favorite/equipped items from organizer/deposit paths; (3) shortage honesty (no bulk free kits, no phantom stock); (4) ground-item pickup/placement only via the roadmap candidate with its caps (256 squares, 32 candidates/scan, 10-min cadence, 1 item/cycle) after a reproduced need + proven native path. OpenCode owns category/matcher/deposit fixes; Codex owns ownership/transfer/architecture changes.

### 10. Bases, territory, jobs, duties

Should feel like a home you defend and keep — clear bounds, assigned corners for guard/farm/wood/corpse/repair, residents doing real shifts.

PZ-native behaviour: stable base records own home building, editable X/Y territory (all floors, ownership only, never a navigation blocker), work zones, residents, queued tasks. Duty + presence + capability + claim checked before work. Guard/patrol/farm/wood/corpse/repair/cook/barricade executors use vanilla actions and verify real world change (plank count, crop state, log consumption, trough amount, object health). Discovery queues executable families before selection; task board picks by priority then skill/trait/recipe/real-stock eligibility with fairness and backoff.

Knox owners: `KS_BaseManager.lua`, `KS_BaseJobs.lua`, `KS_BaseTaskBoard.lua`, `KS_BaseNeeds.lua`, zone executors, duty simulation/scheduling. Related: `BUG-KS-013`, `BUG-KS-017`, `BUG-KS-018`, `BUG-KS-019`, `BUG-KS-020`.

Inspiration translation: Dead State shortage-driven responsibilities + facilities mattering; Rebuild group-goal framing at base scale; Survivalist zone/role intuition without menu-sprawl.

Must never: territory that breaks pathing, disjoint-area claims on a single-rectangle model, fabricated completion, builders needing injected kits, animal-care/construction silently re-added after retirement.

Acceptance: one supplied job completes with real world/inventory change; idle residents show base-life (rest, furniture, books, ambient walks) with blocked-reason honesty. Validation: base-job/ambient/needs/duty focused tests, then live full-day base + two-window barricade + territory-corner replay.

#### 10A. Scheduling, tasks, jobs — how Knox runs work today

Automatic families (`KS_BaseJobs.lua:27`): `guard, patrol, barricade, farm_water/harvest/plow/seed, chop_tree, saw_logs, haul_corpse, burn_corpse, repair, cook`. Animal-care and general construction are retired — do not re-add from old saves/docs (`FEATURE_SPEC.md`).

Task lifecycle (single owner per step): discovery queues executable families → `TaskBoard.queue` validates type via catalog → `claimBest` defers to `BaseJobs.selectEligibleTask` then atomic `claimBaseTask` → resident checks exact requirements against carried + loaded assigned containers (`Planner.missingRequirements`) → collects one transfer at a time via native off-slot action → travels → runs vanilla action → verifies real change (plank count, crop state, log consumed, trough amount, object health) → releases claim → history/memory update. Blocked/streamed-out storage blocks the task; nothing becomes an implicit pool. Stale targets fail with a specific reason and never act on a substituted object index.

Selection (`KS_BaseJobs.lua:889`): explicit role preference keeps its first/fallback passes; the sparse player-base work map exposes High/Normal/Low/Disabled only for the existing guard, patrol, repair, cooking, farming, woodwork, barricade, and hauling groups. High/Normal/Low break otherwise equal selector scores; Disabled excludes an automatic task only when every owning group is disabled. Missing values mean Normal; legacy 1/2/3/4/false migrate to High/Normal/Low/Low/Disabled. Capability/skill affinity remains bounded (`level*2`, cap 12: Woodwork, Mechanics, Axe, Farming, Aiming, Strength, Cooking); `Needs.priorityBonus` adjusts task priority; `lastClaimedBy −18` plus recency decay prevents monopoly; queue order breaks remaining ties. Eligibility (`canPerformTask`: duty, presence, capability, recipe, real-stock) stays authoritative. Active companions do not use this selector; their saved map is dormant until base assignment.

Duty schedule (RimWorld-style, PZ-native): persisted windows in `KS_Persistence.lua:2647` (default sleep 22–6, work 8–12/13–18, recreation 12–13/18–20, anything else); 24-hour strip transforms are UI-only, windows stay the sole authority; `scheduleAssignment` (`KS_BaseJobs.lua:804`) returns `sleep/recreation/work/anything` (plus guard/patrol assignments); sleep/recreation are no-work windows honored as rest; `anything`/missing/non-base duty preserves historical behavior. NPC groups/factions get the default clock lazily once. Player edits go through `CompanionService.setBaseDutySchedule` validation.

Zones vs storage: work areas (`farming, cooking, woodcutting, log_processing, guard, patrol, corpse, repair, general`) are duty destinations, never ownership/safehouse bounds; a resident inside one may continue work without walking home. Storage policies are the separate canonical container model. Territory is one X/Y rectangle on all floors for ownership only; it never blocks navigation. `containsWorkSquare` gates the stay-and-work permission; disabled areas and other floors grant nothing.

Group jobs: `KS_GroupScavenge.lua:1` sends idle pairs (≥3 members, 2-hr lease, day only, dissolve at nightfall) through normal exploration + formation; loot is real container transfers; lease table is loaded-only. Away-team executor persists participants/objective/destination/ETA/result with the blocked-ledger ownership rules in `BUG-KS-024`.

Prioritize for Codex (dependency order, maps to `KS-PROD-008` steps 5→2→9): (1) one supplied job end-to-end with real change + save/reload; (2) claim/release/fairness with no monopoly or leak; (3) needs-bonus honesty (unknown ≠ shortage); (4) schedule windows honored without starving security/cleanup; (5) shortage → mission → return → deposit → memory chain via planner + group scavenge + organizer; (6) two-worker/crew replays (corpse pair, wood pair, barricade pair) before any new job family. The approved BUG-KS-023 four-state base-resident preference slice is implemented in the existing selector; Build 42 UI, execution, interruption, and save/reload remain acceptance. New planners, cross-system arbitration, persistence changes, broader categories, and ranked multi-role profiles remain separately scoped work. Never add a colony grid by stealth.

### 11. Companions, orders, HUD, Card, Notebook

Should feel like trusted company — clear orders, readable state, honest records — never a second job board fighting your voice.

PZ-native behaviour: durable primary (Follow/Hold) + traversal policy + temporary loot directives that return to primary; companion service owns validation; header/individual/world menus call the same path. Follow uses staggered slots, cadence-gated refresh, walk/run/sprint by gap, native run/sprint state, hold guards at boundaries. HUD pools live portraits for player-owned companions only; Card/Notebook expose identity, skills, health, needs, equipment, duty, history, faction/base/mission state from semantic snapshots, never live references.

Knox owners: `KS_CompanionService.lua`, `KS_PartyCommands.lua`, `KS_OrderCatalog.lua`/`KS_OrderSignals.lua`, `KS_RadialOrders.lua`, `KS_CompanionHUD.lua`, `KS_SurvivorCard.lua`, Notebook, `KS_MapOrders.lua` overlay, `KS_SpeechIndicators.lua`, `KS_ActivityFeed.lua`. Related: `BUG-KS-008`, `BUG-KS-010`, `BUG-KS-011`, `BUG-KS-021`.

**Player-facing hub direction:** the Survivor Journal should be the main vanilla-style entry point for existing world history, survivors, groups/factions, relationships, bases, work/schedules, areas/storage and missions. It reads authoritative view data from those owners and creates no parallel state. Keep Knox interfaces visually cohesive, readable, mostly translucent, and draggable/resizable where that helps. The existing direction/Arrow UI stays the single survivor-locating overlay: visibility alone must not capture right-click, aiming, or other world input; intentionally interacting with its controls may consume input. Improve its readability/size/placement and allow dragging without creating a replacement overlay. Treat this as the future UI architecture, not a reason to defer core simulation fixes or rebuild every screen at once.

Inspiration translation: TIS observations/character-sheet + mission-pick intuition; Survivalist command-mode clarity without constant re-issue.

Must never: stale-shell order writes changing persisted orders, HUD stealing input, overlay backgrounds blocking right-click, map markers from a parallel ledger.

Acceptance: orders survive interruption/unload/save; speech renders readable and click-through; map shows owned locations with confidence. Validation: order-routing/radial/notebook/speech/card/view-model/map focused tests, then live order + UI-scale + save replay.

### 12. Social, relationships, memory

Should feel like people remembering what you actually did — gratitude, grudges, gossip that fades, invitations earned over time.

PZ-native behaviour: encounters recorded by persistent IDs on same-level awareness range only; names, first/recent times, meeting counts, nearby hours, shared roaming/loot/combat. Pair/faction disposition owns friendliness; trust/reputation have fixed reasons, per-kind cooldowns, rolling 24h budgets, clock-rollback safety. Greeting needs approach/face/agreement without combat; joining needs familiarity + shared activity; hostility blocks talk/recruit and is not erased by unrelated help. Player hits create real trust loss + faction consequence; defense credit needs native attacker/target/floor/range evidence.

Loaded greetings, declines, hostile dispositions, and group join results now enter the existing bounded survivor history after finalization. Later dialogue/Card views consume those facts; interrupted encounters and assumed robbery/combat results are excluded. Behavior-level memory consequences remain a later connected slice.

Knox owners: persistence relationships, `KS_SurvivorDialogue.lua`, encounter observer, trust/reputation, trade/quotation. Related: `BUG-KS-025`.

Inspiration translation: Survivalist social memories + gossip/decay; CK relationship-context dialogue substitution (name → "my brother-in-law, X") as presentation only; Dead State ally-history weight without scripted arcs.

Must never: Sims-style invented affinity, second diplomacy registry, proximity-only party formation, group leaders bypassed by every member inviting.

Acceptance: meet → recognize → remember → trust/hostility → recruit/group reads coherently in Card/Notebook/dialogue across save/reload. Validation: relationship/origin/behaviour focused tests, then live meet/greet/join + hit/hostility + defense-credit replay.

### 13. Groups, factions, camps, missions, events

Should feel like a county with a few real crews — solos common, groups rarer, factions rare — each with a home, needs, and stories you can stumble into.

PZ-native behaviour: solo → meeting → mutual join → small travel group (lowest-ID leader, staggered slots, leash/wait-back, shared objective copied from leader intent) → compatible third → faction eligibility (shared activity, not day-count) → homeless-faction scouting (size/rooms/access/defense/pressure/water/storage/farm/resources/ownership) → claim → settlement/camp. Camps are lightweight shelter records, not mini-bases. Missions are shortage-justified, member/equipment-reserved, destination/ETA-persisted, abstract-while-unloaded, real-item-settled. Faction conflict stays restrained, hostility/territory/pressure-driven, loaded-combat-settled.

Knox owners: travel groups, `KS_GroupScavenge.lua`/`KS_GroupSupport.lua`/`KS_GroupCohesion.lua`, factions/camps/safehouses/scouting, away-team executor, event/faction runtime, off-screen stories. Related: `BUG-KS-024`, `BUG-KS-026`, `BUG-KS-001`.

Inspiration translation: Rebuild group goals/missions/specialties/events; State of Decay community pressure; TIS virtual tokens on roads + meeting triggers.

Must never: population refill as player-centered spawning, group/faction/event records inventing identities, unloaded conflict manufacturing outcomes, camps growing storage/territory/work-board ownership.

Acceptance: natural solo → group → faction → settlement chain observable; shortage → mission → return → deposit → memory chain closes; conflict stays rare and loaded. Validation: population/origin/faction/event-entry/group focused tests, then live formation/scout/mission/conflict replay.

### 14. Population, origins, balance

Should feel like meeting someone who came from somewhere — a town, a shop, a station — not a spawn effect circling you.

PZ-native behaviour: finite persistent target (default 48) with separate active-body budget and per-pass allocation caps; new-world cohort in the starting region from real spawn/building origins with hidden/square safety gates; virtual itineraries pre-materialization; unused-origin refill after durable deaths; no snap-to-player relocation; building-context profession hints without gear/faction/supply invention.

Knox owners: `KS_WorldPopulation.lua`, persistence allocator, origin metadata, spawn-region/building catalogs. Related: `BUG-KS-026`, `BUG-KS-027` (deferred creator).

Inspiration translation: TIS region-balanced origins + density knowledge without full simulation; Rebuild rarity intuition (solos > groups > factions).

Must never: visible/occupied/unsafe/near-player activation, origin-key reuse, caps-disabled treated as infinite, numeric tuning without measured bottleneck.

Acceptance: fresh world reaches target over passes without thread monopoly; deaths refill slowly from unused origins; materialization respects budgets. Validation: population/origin focused tests + frame-time measurement, then live travel/materialization/hibernation replay.

### 15. Presentation, dialogue, feedback

Should feel quiet until it matters — a gesture, a line, a label, a log — never a wall of popups.

PZ-native behaviour: engine `Say` for world bubbles + collapsible activity feed for history; gesture on leader objective change with busy/far/floor suppression; transparent click-through speech overlay with stale/expiry handling; status logs with state/decision/destination/failure/retry; diagnostics as transitions/events, not spam.

Knox owners: dialogue, gestures, speech indicators, activity feed, HUD/Card/Notebook, debug/status logs. Related: `BUG-KS-010`.

Inspiration translation: TIS recount lines + context substitution; CK variant-line intuition for natural retelling.

Must never: foraging imports for a speech arrow, full-viewport background panels, input-eating overlays, per-tick log spam standing in for evidence.

Acceptance: indicator colour/projection readable; world menus open over/under feed; logs identify first failure without noise. Validation: speech-indicator/UI/order focused tests, then live visual + menu replay.

### 16. Performance, defaults, customization

Should feel calm at normal populations and honest about cost — conservative out of the box, tunable where the architecture allows.

PZ-native behaviour: separate world-count vs body budgets, per-pass allocation/route caps, scan cadence limits, bounded histories/retries/ledgers, pooled HUD portraits, same-floor/locality selectors, no per-tick cell scans. Settings change behaviour, never ownership, native requirements, evidence gates, or save safety.

Knox owners: `KS_Settings.lua`/sandbox options, population caps, scheduler cadences, verification budgets. Related: `KS-PROD-008` step 9.

Inspiration translation: RimWorld priority-discipline (don't haul the whole map at priority 1) + Survivalist distance/capacity honesty.

Must never: tuning counts to hide a measurement gap, disabling caps treated as a fix, settings that bypass persistence/identity safety.

Acceptance: measured loop cost at configured population + crowded job/combat; meaningful settings verified in fresh save. Validation: full offline gate + frame-time notes, then live measurement.

## Role design: preference, not a permanent caste

Avoid:

`Bob = Farmer forever`

Prefer a ranked capability/preference profile:

1. farming;
2. hauling;
3. repair;
4. guarding.

The survivor chooses the highest-priority valid work that the current group/base actually needs and that the survivor can perform.

Skills, traits, profession, equipment, health, relationships, current order and urgency may all affect suitability without making the survivor a colony pawn.

## Shared reservation direction

The research highlights a recurring failure mode: an organizer or generic worker can take an item another job requires.

Knox should continue moving toward a shared rule:

> Before taking or moving a resource, check whether an active job, loadout, survivor need or other reservation owns it.

Likely reservation categories include:

- item / stack;
- container or storage slot;
- work target;
- destination square;
- bed/rest point;
- corpse;
- barricade/window/door;
- vehicle/seat;
- combat target where exclusivity matters;
- support recipient;
- mission slot.

Reservations must expire or be released on completion, failure, interruption, hibernation and owner loss.

## Group needs should create missions

The individual survivor loop should not be the only planner.

Example:

`base food is low`
→ base need is raised
→ group planner decides a scavenging mission is justified
→ suitable members are selected
→ equipment/supplies are checked and reserved
→ the group travels
→ the mission continues abstractly if unloaded
→ real food is acquired or the mission fails
→ survivors return
→ storage/organizer places the supplies
→ shortage clears
→ participants gain history/memories
→ other groups may remember an encounter.

That is one story produced by existing systems feeding each other.

## Social memory direction

Relationships should primarily come from events that actually happened.

Prefer:

- Sarah abandoned Bob during a dangerous fight.
- Bob remembers the abandonment.
- Later Sarah rescues Bob while injured.
- The new event changes Bob's trust/disposition.

Avoid a disconnected Sims-style relationship minigame that invents arbitrary numbers without world history.

A future generalized memory record could contain:

- event type;
- participants;
- place/time;
- severity;
- witnessed/direct/heard-about source;
- relationship effects;
- decay policy;
- whether the event can be gossiped about;
- links to faction reputation or future decisions.

The current relationship and off-screen story systems are the starting point; this should not become a second competing relationship model.

## Specialists should matter because the world uses real systems

Keep real Project Zomboid food, medicine, ammo, fuel, tools, weapons and containers.

The lesson from State of Decay is not the abstract resource counter; it is that losing one capable person changes what a community can do.

Examples:

- losing the best mechanic makes vehicle maintenance harder;
- losing an experienced medical survivor makes serious injuries riskier;
- losing a strong shooter changes group combat capability;
- losing the primary farmer may force more scavenging.

These consequences should emerge from skills/capabilities and real work requirements rather than scripted punishment.

## Loaded and unloaded must be the same story

### Loaded

Use actual Project Zomboid state:

- body;
- inventory/equipment;
- needs/health;
- movement/pathing;
- combat;
- buildings/containers;
- timed/native actions.

### Unloaded

Keep the same:

- survivor ID;
- destination;
- mission;
- group;
- possessions/supplies;
- relationships;
- injuries/needs;
- important job/intent.

Use cheaper event/simulation logic instead of pretending the entire map is physically loaded.

On return, **materialize and reconcile the result**, never create a second contradictory version of the survivor.

## Player QOL — what players expect, what is already there, what comes later

Researched against community expectations for companion/survival NPCs (reliability-first mods, party/base-life feature sets, Survivalist role/storage/organizer lessons, and the recurring plea that talk must match behavior). None of the future items below are promises; each needs its own approved work item after the core loop is live-verified.

Already implemented foundations Codex must not regress: Follow/Hold/Return/Guard/Patrol/Move/loot directives with traversal policy; companion HUD with pooled portraits; Survivor Card on vanilla panels; Notebook (party, base, known survivors, away, factions); order gestures with disable option; speech indicators; activity feed; nameplates with distance; owned-survivor map overlay; typed storage labels and base highlights; work zones and duty schedules; weapon preference menu; trade quotation and verified exchange; Talk/recruit with trust rules; medical check on real wounds; status/diagnostic logs; organized sandbox settings.

Future QOL candidates (gated, in rough value order):

- **Hold means hold.** A hold/stealth posture that genuinely suppresses combat engagement — the most-cited dealbreaker in the genre when it leaks.
- **Refuse with a reason.** A terrified or principled survivor may decline an order into obvious death — but says why, keeps the durable duty, and resumes when safe. Never silent disobedience, never deleted orders.
- **Callouts that matter.** Low ammunition, serious injury, lost target, blocked route, missing supplies — one honest line or label each, no spam. The player should always know *what* they are doing and *why*.
- **Self-recovery with evidence.** Stuck detection from real displacement, alternate route/target selection, bounded retry then visible wait state with the failure reason in the status log — never an infinite loop, never a silent statue.
- **Brave together.** Allies count toward courage: a companion beside the player holds where a loner would flee, and says so through behavior rather than meters.
- **Quiet moments.** Survivors eating together, resting, conversing, reacting to weather and night — base life that looks busy because needs and duties are real, not decorative idles.
- **Talk matches behavior.** Dialogue, gestures, and activity labels describe the actual ledger: no recounting events that never happened, no hatred that still follows blindly, no "cooking" without heat and food state.
- **Come/rally.** A short-range recall to the player's side that respects danger and current leases, then returns to the durable order.
- **Clean vehicle handoffs.** Boarding, seating, passenger travel, and driving release without clones, phantom seats, or control leaks — each handoff verified in game before the next is attempted.
- **Base ↔ field without babysitting.** Send a companion home or call them out with inventory, orders, and affiliation intact across streaming and save/reload.
- **Readable at a glance.** UI scaling, high-contrast indicators, capacity/error feedback on trades and storage, and plain-words reasons whenever work cannot start.

Bar-raising checklist (what makes hiring managers and players stare): same-person continuity across every save/streaming edge; zero freeze-think pauses; orders that survive the world; consequences that emerge from real skills and stocks; performance that holds at full population; compatibility that never fights other mods for the same ownership; settings that let every player tune their apocalypse; and vanilla art, language, and manners throughout — nothing that looks or talks like AI slop.

## Recommended architectural growth path

These are design targets, not automatically approved implementation tasks.

### A. Formalize decision arbitration

Document one common intent/job ownership contract around the existing autonomy controller. First use it to describe current behavior; migrate systems only when doing so fixes a concrete ownership problem or enables an approved feature.

### B. Generalize reservations

Unify compatible existing claim/lease concepts behind shared ownership/release semantics without breaking specialized systems that already work.

### C. Generalize base/group need planning

Let shortage/problem detectors create needs. Let planners turn needs into missions/jobs. Do not let every survivor independently solve the same shortage.

### D. Expand role preferences and capability selection

Use skills, profession, traits, equipment and experience to decide who is suitable. Preserve flexible fallback work.

### E. Add an event/memory ledger

Build on current relationship history/off-screen stories. Record meaningful events once and let relationships, reputation, dialogue and future decisions consume that history.

### F. Expand off-screen job equivalents

Only abstract jobs whose effects can be represented safely. Physical world-changing work that cannot be reconciled safely should pause until loaded.

### G. Strengthen materialization reconciliation

Every abstract outcome must have an explicit, idempotent path back to real Project Zomboid state.

## Design guardrails

- Do not add twenty isolated systems when existing systems can be connected.
- Do not create a second persistence/relationship/base-work owner.
- Do not fabricate resources to make AI appear competent.
- Do not simulate world-changing work off-screen unless it can reconcile safely.
- Do not make direct player orders meaningless; emergency survival can interrupt, but normal autonomy should not constantly overwrite player commitments.
- Do not let every NPC independently react to a group-level shortage.
- Do not make humans so common that deaths and specialists stop mattering.
- Do not turn Knox into RimWorld, Rebuild, State of Decay, Dead State or Survivalist. Borrow the useful operating principle and translate it into Project Zomboid.

## Research still worth doing later

The current research is sufficient to guide the next architecture/design pass. Additional research is optional rather than blocking.

If deeper examples are useful later, the highest-value candidates are:

- **Crusader Kings** — deeper study of reusable story/event chains and character-context-driven outcomes; this is the most directly justified extra reference because Project Zomboid's own NPC article names it as an inspiration;
- **Kenshi** — persistent squads, jobs and autonomous settlement work;
- **Mount & Blade / Bannerlord** — parties, faction/world-level travel and conflict above individual agents;
- **Dwarf Fortress** — event-driven memories/relationships and needs, with careful filtering to avoid colony-game complexity.

Any new reference should be captured as a design/research item first and evaluated against the core Knox rule before becoming implementation work.

## Dream-mod vision — what Knox is going for

Owner direction 2026-09-28: rare survivors who act as players, fully inside Project Zomboid's existing mechanics, highly customizable per-player preference, and feeling alive whether loaded or not. Settled concept calls in D-017.

- **Rare-but-findable:** survivors stay rare — never armies — but ordinary exploration produces encounters without hours of searching. The apocalypse feels empty yet alive: meetings, fights, and immersive world activity happen naturally. Everyone keeps moving, eating, and surviving off-screen. Conservative defaults out of the box (`WorldPopulation = 48`, active bodies `16`, refill `5` days in `KS_Settings.lua:7`); named modes/presets (e.g. Lonely / Balanced / Lively) should eventually let each player pick their preference so nobody is left out.
- **Players, not pawns:** survivors roam, explore, loot real containers, eat/drink/rest, get hurt and recover, fight and flee, improve skills, remember people, form travelling groups, found factions, scout and settle bases, work jobs, join the player, follow durable orders, run away missions, and persist through streaming and save/load (`FEATURE_SPEC.md` acceptance loops).
- **Scavenge → group → faction → base:** independents meet by proximity/awareness/agreement, build shared history, travel as small groups with a leader, admit compatible thirds, reach faction readiness through shared survival (not day-count), then homeless factions scout real buildings (size, rooms, access, defense, pressure, water, storage, farm, resources, ownership conflict) and claim a persistent home. Camps stay lightweight shelter records — never a second base system. Future track (D-018): the player asking to join or live at a faction base as a member rather than a leader — today recruitment runs the other direction only.
- **Diplomacy with other factions:** trust (personal, earned), disposition (friendly/neutral/wary/hostile), reputation (faction-level), and bounded memory (reasons, timestamps, decay, gossip eligibility) all live in the existing relationship/faction records. Loaded meetings need proximity, same floor, approach, facing, agreement. Trade is verified native exchange. Truce/hostility flips existing disposition and encounter eligibility. Safehouse diplomacy happens loaded at a real location. Help never auto-erases hostility. No second diplomacy registry, no omniscient gossip.
- **Immersive encounters and raids:** presence and intent may travel/store off-screen; terminal outcomes require loaded native arrival, combat, looting, or objective interaction. Danger is Walking-Dead unpredictable: a stranger may share, talk, rob, or attack depending on history and current relations — humans scarier than zombies, the greatest benefit from working together when it clicks. Group-on-group conflict runs on the same universal rules over real causes (food, materials, past history), never scripted encounters. Failed traces stay retryable and consume only on native success. Full faction politics (alliances/wars/territory deals) is a deferred future track (D-017, D-018).
- **Living off-screen:** intent → coarse travel → real carried-supply consumption → rest/needs → one bounded storylet → persisted history/trace → reconcile as the same person. No off-screen combat resolution, loot generation, injury/death, blood, smashed windows, robbery, raid results, or teleports. This is TIS's storylet shape in Knox form — an original implementation, not another mod's code.
- **Customizable but safe:** conservative immersive defaults out of the box; meaningful population, autonomy, off-screen life, encounters/raids, bases/jobs, combat/difficulty, performance, and UI/feedback tunable where the architecture supports it. Settings never bypass identity ownership, native requirements, save safety, or evidence gates (see Settings direction below). Future tracks: named rarity modes, any user-expected sandbox settings, and eventually a creator built on the vanilla character creator plus Knox additions for factions/groups/independents (D-017). Multiplayer compatibility is a future track; single-player stays the supported focus until then.

## Settings direction — highly customizable, safely bounded

Current surface (`KS_Settings.lua:4`): population/rarity, autonomy, events/factions/raids, combat/difficulty, bases/jobs, performance, UI/feedback, lifecycle/start options, plus developer/QA tools. Sandbox labels live in `mod/42/media/lua/shared/Translate/EN/Sandbox.json`; `docs/SANDBOX_SETTINGS.md` currently omits several implemented options and needs a doc refresh when settings change.

Codex rules:

- Groups to expose (using existing IDs only, ranges match `sandbox-options.txt`/`KS_Settings.lua`): World Population Rarity (target 0–256, default 48; group chance 0–100 default 65 / max size 2–6 default 4 / count 1–4 default 3; refill 0–30d, default 5); Survivor Autonomy (cautious travel on, engagement 2–16 default 4, door/window on, paired formation spacing 1–3 default 1); Off-screen Life (bounded pacing controls only if architecture supports them; conservative deterministic default stays); Encounters/Raids (hostile encounters on, events/raids off, raid day 1–90 default 14, interval 1–30 default 7; raids also require factions + hostile encounters per `KS_Settings.lua:226`); Bases/Jobs (auto work areas on, real-resource requirements enforced, cupboard 100–2000 default 500); Combat/Difficulty (Native Skills aiming default, combat only where relationships permit, experimental driving off); Performance (active bodies 1–48 default 16, activations 1–4 default 2, no cap bypass by default); UI/Feedback (HUD/feed/speech on, nameplates on/8–40 default 24, diagnostics/dev tools off).
- Gaps to scope as future work items (not silent additions): autonomy priority/schedule depth, retreat thresholds, needs/rest pacing, off-screen story/travel cadence, loot intensity, faction-formation frequency, non-raid event frequency, base-job priority depth.
- Never configurable: identity ownership, persistence/lifecycle, native item/action/resource requirements, safe spawning, ownership arbitration, migration integrity, fabricated supplies/world effects, unloaded combat outcomes, live-evidence/release gates. `DisableSurvivorCaps` and `IgnoreJobResourceRequirements` must carry prominent safety/performance wording; developer scenarios/destructive tests stay clearly non-gameplay.

## Dev / modder guide — how systems work and stay healthy

- **One owner per boundary:** identity/persistence (`KS_Persistence.lua` + Java records), brains (`KS_SurvivorAutonomyController.lua`), movement (Java traversal + cohesion), combat (awareness/threat/firearm), storage (`KS_BaseStorage.lua`), jobs (`KS_BaseJobs.lua` + `KS_BaseTaskBoard.lua` + `KS_BaseNeeds.lua` + `KS_BaseSupplyPlanner.lua`), companions (`KS_CompanionService.lua` + catalog/signals), social/groups/factions (relationship + group/faction records), off-screen (unloaded ledger + storylets + traces + event runtime), population (`KS_WorldPopulation.lua`). Connect through these owners; never add a parallel controller, ledger, or simulation.
- **Must stay retired:** central "Main Supplies" + container sorting (`KS_OrderCatalog.lua:72`, `KS_Persistence.lua:5896`, `KS_BaseStorage.lua:864`, `KS_BaseJobs.lua:1102`, `KS_SurvivorAutonomyController.lua:11985`, `KS_BaseManager.lua:311`); animal care (`KS_Persistence.lua:414`, `KS_BaseJobs.lua:9`); construction/defense areas (`KS_Persistence.lua:396`); Base Setup window (removed; Notebook via `KS_BaseContextMenu.lua:316` is canonical); legacy right-click orders stay opt-in/off (`KS_Settings.lua:275`).
- **Legacy shims to preserve:** `LEGACY_TASK_TYPES`/`LEGACY_ORDER_ALIASES` + canonical normalization and stale-record cancellation (`KS_Persistence.lua:77`); legacy fridge policy (`KS_BaseStorage.lua:223`); task aliases (`KS_OrderCatalog.lua:86`); label normalization (`KS_BaseJobs.lua:789`). They are save compatibility, not extension points.
- **QA tooling boundary (KS-PROD-011 / D-033):** The manifest, coordinator, and parser remain offline regression fixtures only; the in-game QA runner and save-arming UI were retired. Their presence in source does not imply playable survivor behavior or live coverage. Gameplay acceptance comes from ordinary Build 42 replays with explicit expected outcomes.
- **Dormant by design (do not "finish" unprompted):** orphan menu/helpers with zero callers (e.g. unwired `KS_BaseContextMenu.lua:298` territory/zone entries marked Retired). Deletable candidates, not features. `FEATURE_AUDIT.md` Goals 13/14/15 still list retired paths as active — that file is non-authoritative history; do not follow it over current retirement entries.
- **Experimental until gated:** NPC driving (off, `KS_Settings.lua:20`), faction raids (off, `:30`), Knox events (off, `:26`), away-team dispatch, dev QA modes. No promises without their acceptance gates (`D-004`, `QA_RELEASE.md`).
- **Evidence discipline:** offline doubles prove control flow only. Engine behaviour (animation, pathing, damage, transfer, UI render, streaming, save) needs disposable-save Build 42 live replay with the exact scenario in `QA_RELEASE.md` / `DEVELOPMENT_TESTING.md`. Record counts, revision, runtime path, and remaining gaps honestly.

## Prioritize guide — what Codex works on first

Use this order when `WORK_QUEUE.md` / `BUGS.md` leave room for judgment. It does not create new task IDs; it tells Codex which existing boundary matters most.

1. Lifecycle/identity safety (`KS-PROD-008` step 1; `BUG-KS-008`, `BUG-KS-024`): no duplicates, no lost orders/inventory, blocked-ledger recovery. Nothing else outranks this.
2. Loaded job correctness (`KS-PROD-008` step 5): one supplied guard/patrol/barricade/farm/chop/saw/corpse/repair/cook job with real tool/material, native action, verified world change, claim release, save/reload intact.
3. Storage honesty (`BUG-KS-015`, `BUG-KS-016`): typed deposit + General fallback + overflow; organizer never steals reserved loads; planner never invents stock.
4. Scheduling fairness (`BUG-KS-013`, `BUG-KS-023`): existing one-job election retains task priority, capability, security coverage, fairness and anti-monopoly; player work preferences only affect otherwise equal eligible choices; sleep/recreation remain honored and security/cleanup must not be starved.
5. Unloaded parity (`BUG-KS-024`, `BUG-KS-001`, `BUG-KS-002`): needs/travel/rest/storylet/trace behaviour matches loaded intent with retryable materialization and no fabricated outcomes.
6. Movement/combat polish (`BUG-KS-011`, `BUG-KS-012`, `BUG-KS-028`, `BUG-KS-029`): follow cadence, retreat admission, firearm stabilization — only after 1–5 are stable.
7. Expansion only with owner approval: richer multi-role profiles, new work groups, ground-item zones, generic mission planner, memory ledger with decay/gossip. Each needs a bounded work item with scope, acceptance, validation, and one owner. Never a colony grid or second simulation by stealth.

Routing: narrow category/matcher/schedule/selector/retry fixes → OpenCode; persistence/identity/lifecycle, new claims/planners, cross-system arbitration → Codex; vision/scope/release calls → Boss/owner.

## Codex execution map — how to use this document

This note is design authority, not a task list. Codex/OpenCode must still work from `docs/production/WORK_QUEUE.md`, `BUGS.md`, `CURRENT_STATE.md`, and `ROADMAP.md`.

1. Pick the active `KS-PROD-*` or `BUG-KS-*` ID first; if none fits, return the uncertainty instead of inventing a feature.
2. Read `FEATURE_SPEC.md` for scope, `ARCHITECTURE.md` for ownership, and the dossier above for feel + must-never rules.
3. Fix the first confirmed failing boundary through the listed Knox owner; do not create a parallel controller, ledger, or simulation.
4. Run the cheapest focused test first (`tools/test-*.lua`), then `tools/verify.ps1 -SkipJava`, then Java/build/package only when the boundary needs it.
5. Record offline evidence in the owning task/bug; leave every engine-bound behaviour as live-unverified with the exact replay in `QA_RELEASE.md` / `DEVELOPMENT_TESTING.md`.
6. Update `CURRENT_STATE.md` position, `WORK_QUEUE.md`/`BUGS.md` state, and `DECISIONS.md` only when a settled choice changed — never a new parallel plan document.
7. Escalate by boundary: narrow reproducible defect → OpenCode; persistence/identity/lifecycle/cross-system → Codex; vision/architecture/evidence/release risk → Boss/owner. Follow `AI_WORKFLOW.md` escalation ladder.

## Retreat policy design and acceptance — D-031

The next retreat-policy design uses a survivor-specific comparison between
fighting risk and retreat risk, while preserving the existing controller as the
sole admission owner and Project Zomboid as the combat/movement authority. The
assessment should account for condition/injury, protection/equipment, actual
weapon/ammo, capability/fitness, group strength/cohesion, threat count/type,
surprise, escape lanes/chokes, recent combat experience, player conduct, morale,
and current moodles. Missing values are neutral/unknown. Bounded randomness is
a stable tie-break only; it cannot overturn clear danger or an unsafe escape.

| Test case | Expected behavior |
|---|---|
| Healthy, armed, prepared against one ordinary threat | Fight/hold; no arbitrary flee |
| Injured/bleeding or unarmed against a dangerous group with a clear lane | Retreat if the real lane is safer; later resume the durable role |
| Strong cohesive group against a small threat | Fight/hold without scattering |
| Surrounded or no safe exit | No fictitious retreat; bounded defensive recovery |
| Surprise/player fighting or withdrawing | May affect close decisions, never override explicit orders or clear lethal risk |
| Recent failure, morale/moodles, equivalent close tie | Bounded stable difference; no per-tick reroll or oscillation |

D-031 is design-only. The current BUG-KS-012 retreat owner and thresholds
remain unchanged pending a separately approved implementation package and
native combat/pathing replay.
