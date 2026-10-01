# Knox Survivors — Feature Completion Specification

## Target

The target release state is:

# FEATURE COMPLETE — READY FOR FULL QA / POLISH

At that point remaining work should primarily be:

- live QA;
- discovered bug fixes;
- balancing;
- performance tuning;
- compatibility testing;
- UI/animation polish;
- release preparation.

A feature does not count as complete merely because code exists.

Major required systems must have a real production implementation, be connected to normal gameplay, preserve required state, and not depend on developer commands.

`production/CURRENT_STATE.md` and `production/WORK_QUEUE.md` track current status. `FEATURE_AUDIT.md` is the retained deep historical implementation/evidence ledger.

`ARCHITECTURE.md` defines how these systems must be implemented safely.

`DEVELOPMENT_TESTING.md` defines existing verification procedures.

---

# Core Vision

Knox survivors should behave like persistent human survivors sharing the Project Zomboid world with the player.

They are AI-controlled Project Zomboid survivors, not colony-game pawns. Other games may inform specific job/priority/social/off-screen mechanics, but Project Zomboid remains the gameplay foundation. See `design/NPC_SYSTEM_INSPIRATION.md`.

They should be able to:

- survive independently;
- explore;
- loot real world resources;
- manage inventory and equipment;
- eat, drink and rest;
- become injured and recover;
- fight and flee;
- use melee weapons and firearms;
- improve skills;
- remember other survivors and players;
- form relationships;
- form travelling groups;
- form factions;
- scout and establish settlements;
- maintain bases;
- perform useful jobs;
- join and travel with players;
- follow persistent player orders;
- undertake away missions;
- survive while unloaded;
- persist correctly through streaming and save/load.

Behavior should remain grounded, systemic, restrained and compatible with normal Project Zomboid mechanics wherever technically safe.

No magical resources when real world resources can be used.

---

# Required Production Systems

## Survivor Foundation

- persistent identity separate from engine body;
- safe materialization/hibernation/reconstruction;
- simultaneous survivors;
- durable death;
- safe teardown;
- no duplicate/stale/invisible bodies;
- no real-player ownership corruption;
- persistent appearance, inventory, equipment, health and location.

## Autonomous Survival

- roaming and purposeful exploration;
- building/container interaction;
- useful looting;
- food/water/medical resource management;
- inventory evaluation and equipment upgrades;
- endurance/fatigue/rest;
- injury/treatment/recovery;
- threat detection;
- fighting and fleeing;
- obstacle/entry handling;
- bounded failure recovery.

## AI / Action Ownership

Priority approximately:

danger
→ medical emergency
→ critical needs
→ direct player order
→ companion responsibility
→ group/faction responsibility
→ base responsibility
→ resource need
→ exploration
→ idle.

Only one system owns exclusive body/movement actions at a time.

Support interruption, cancellation, resumption, route replacement, lost targets, missing resources, combat interruption and bounded retries.

## Navigation / Human Movement

Support believable:

- walking;
- running;
- sprinting;
- useful sneaking;
- group/companion catch-up;
- doors/windows;
- fences/climbing;
- locked-entry recovery;
- indoor/outdoor movement;
- supported multi-floor movement;
- alternate routes;
- abandonment of impossible goals.

## Combat

Support:

### Survivor → Zombie

and:

### Zombie → Survivor

through native Project Zomboid mechanics wherever safely possible.

Include:

- melee;
- pursuit/positioning;
- endurance;
- weapon condition;
- hit reactions;
- injuries;
- BodyDamage;
- scratches/bites;
- death;
- group/companion combat;
- fleeing.

### Firearms

Include:

- firearm selection;
- ammunition;
- magazines;
- reload;
- aiming;
- range;
- firing;
- sound attraction;
- condition;
- sensible firearm/melee decisions;
- safe target selection.

Do not fabricate combat outcomes just to satisfy tests.

## Needs / Health / Inventory

Persist and use:

- hunger;
- thirst;
- fatigue;
- endurance;
- health/injury/bleeding;
- food/water;
- medicine;
- clothing;
- weapons;
- equipment;
- carrying capacity.

Player must be able to appropriately inspect/manage survivor inventory, equipment and medical condition.

## Skills / Traits / Occupations

Persist and use:

- occupation;
- traits;
- perk levels;
- XP;
- relevant job/skill requirements.

## Social World

Support:

meet
→ recognize
→ remember
→ relationship/history
→ trust/friendliness/hostility
→ recruitment/group decisions.

Include contextual conversation and persistent relationships.

## Natural Groups

Support:

solo survivor
→ meeting
→ relationship
→ mutual joining
→ small travelling group
→ compatible third survivor
→ faction eligibility.

Groups should travel, catch up, wait, fight and survive together.

## Factions

Persist:

- faction identity;
- leader;
- members;
- relationships/history;
- goals/state;
- base/territory;
- residents;
- resources where applicable.

Faction formation should emerge from compatible survivors and shared history.

## Settlement Scouting

Homeless factions should:

scout
→ evaluate candidate
→ travel
→ reject failed/unreachable candidates
→ claim suitable home
→ establish persistent settlement.

Useful evaluation includes:

- size;
- rooms;
- accessibility;
- defenses;
- zombie pressure;
- water;
- storage;
- farming space;
- nearby resources;
- ownership conflicts.

## Base System

Support player and NPC faction bases with:

- ownership;
- persistent home;
- editable territory/yard;
- residents;
- work zones;
- multiple assigned Project Zomboid containers with typed storage categories,
  including General Storage fallback and multiple containers per category;
- player-configured per-container allow-filters, including several categories
  on one real container; the explicit General Storage filter is an exclusive
  catch-all;
- resources;
- jobs/tasks;
- defenses.

Territory must not break ordinary navigation.

## Base Management UI

Provide usable management for:

- establishing/viewing a base;
- territory;
- work areas;
- storage;
- residents;
- assignments;
- active/queued work.

Work areas should support where applicable:

- Guard;
- Patrol;
- Farming;
- Woodcutting;
- Corpse Drop;
- Repair.

Typed storage policies are separate from work areas and remain the canonical storage model.
Container filters are saved on that same per-container policy and are honored
by existing deposit, organizer, task-material, food/water retrieval, and
log-processing routes. Legacy single-role records keep their former behavior
until edited; filter-versioned records are strict. Editing filters never ejects
existing items that do not match. Container discovery, native item transfer,
reservations, capacity restoration, and result verification stay with their
existing owners. Filtered ground placement is not included; exact native target
square receipt and rollback remain required first.

## Base Jobs

The current required production job family includes:

- guard;
- patrol;
- corpse hauling to a designated Corpse Drop area;
- categorized storage/organizer work that respects active reservations and personal needs;
- barricading;
- farming;
- cooking;
- tree cutting;
- log processing;
- corpse cleanup/burning where supported;
- damaged-structure repair.

Jobs must use appropriate real world tools/materials/resources and recover safely after interruption/failure.

Animal-care jobs and general construction jobs were intentionally retired from the current production scheduler. Do not silently re-add them because older saves/docs mention them.

## Defense boundary

Current required settlement defense work is **barricading plus supported repair behavior**.

General player-style construction of new walls, gates, doors or access structures is not a current production requirement. Any future construction system requires a separately approved design/work item using real materials, tools, skills and valid vanilla/world actions.

## Companions

Support:

meet
→ talk
→ trust
→ recruit
→ adventure/travel
→ return/home/work
→ dismiss.

Persistent commands include:

- Follow;
- Hold/Stay;
- Return to Base;
- Guard;
- Move/Go To;
- Loot Nearby;
- Loot Building;
- Loot Corpses;
- traversal policy;
- base/job assignment.

Danger and critical needs may interrupt an order without deleting it.

## Companion HUD

Show useful:

- identity;
- activity/order;
- weapon;
- health;
- hunger/thirst;
- fatigue;
- urgent injuries/needs.

Support individual and party commands and safe unloaded cleanup.

## Survivor Card

Expose useful:

- identity;
- age;
- occupation;
- traits;
- skills/XP;
- time alive/known;
- relationship/trust;
- group/faction;
- base/job/activity;
- health/injuries;
- needs;
- equipment;
- useful actions.

## Survivors Notebook

Track:

- Companions/Party;
- Home Base;
- Known Survivors;
- Base Residents;
- Away/Unloaded Survivors;
- NPC Factions.

Expose relevant identity, social, job, location, faction, base, resource and mission information.

## Away Teams / Missions

Support persistent purposeful missions for resources such as:

- food;
- medicine;
- weapons/ammunition;
- tools;
- building supplies.

Persist participants, objective, destination, departure, state, ETA and result.

Results must be derived from world/simulation rules rather than free resource generation.

## Unloaded-World Simulation

Do not keep unnecessary IsoPlayer bodies alive.

Unloaded survivors must continue enough persistent simulation to support:

- travel;
- supply consumption;
- rest/recovery;
- risk;
- missions;
- return home;
- group/faction progression.

Reconstruction must produce the same persistent survivor.

## Camps

Support lightweight temporary camps/shelters for homeless survivors/groups without creating a second full base system.

## Vehicles

Implement the safest coherent level possible of:

- recognition;
- entry/exit;
- travel;
- companion/group interaction;
- persistence.

Never compromise the contained IsoPlayer architecture to support vehicles.

## Faction Conflict / Raids

After ordinary faction life is stable, support restrained conflict influenced by:

- hostility;
- territory;
- resource pressure.

Integrate travel, combat, bases, defenses, injuries/death, resources and persistence.

Avoid constant hostility and magical equipment.

## World Population

Support:

- configurable persistent population;
- region-balanced origins;
- separate active-body limit;
- gradual refill after durable deaths;
- non-player-centered spawning;
- loaded-area materialization;
- hibernation/restoration.

## Lifecycle / Hibernation

Required conceptual loop:

persistent survivor
→ ACTIVE/materialized
→ capture
→ HIBERNATED
→ unloaded simulation
→ same survivor reactivation.

No:

- duplicates;
- identity replacement;
- inventory loss;
- repeating capture loops;
- permanent DETACHED state.

## Failure Recovery

Important tasks must resolve failures into a bounded outcome such as:

alternate route
→ alternate target
→ retry later
→ alternate task
→ return home
→ safe idle.

Never infinite-loop.

## Player Feedback

Provide restrained useful feedback through:

- speech;
- activity state;
- HUD;
- Notebook;
- order results;
- important needs/problems.

Avoid spam.

## Persistence

Critical persistent state includes where applicable:

- identity;
- appearance/clothing;
- inventory/equipment;
- health/BodyDamage;
- needs;
- location;
- occupation/traits;
- skills/XP;
- relationships/history;
- group/faction;
- companion ownership/orders;
- bases/residents;
- work zones/storage;
- jobs/tasks;
- missions;
- camps;
- unloaded state.

## Diagnostics

Maintain diagnostics sufficient to identify the first real failure involving:

- player ownership;
- IsoPlayer instance ownership;
- lifecycle;
- combat/damage;
- action/movement ownership;
- routes;
- task claims;
- persistence;
- faction/base state.

Prefer transition/event diagnostics over repetitive spam.

## Architecture Cleanup

Remove abandoned experiments, obsolete conflicting runtime paths and genuine duplicate ownership systems when encountered.

Do not rewrite working architecture merely for cleanliness.

---

# Feature-Complete Acceptance Loops

## Independent Survivor

persist
→ roam
→ explore
→ loot
→ equip
→ manage needs
→ fight/flee
→ receive real injury
→ treat/recover
→ continue surviving.

## Social World

meet
→ remember
→ relationship
→ travelling group
→ third compatible survivor
→ faction
→ scout
→ travel
→ establish settlement.

Loaded social outcomes enter the existing bounded personal history only after
the greeting, disposition change, group mutation, or rejected join is finalized.
Later dialogue and survivor views read that history. An entry records hostility,
not an unverified fight, robbery, or transfer; interrupted encounters are not
remembered as completed outcomes.

## Settlement

storage/organizing
→ guard/patrol
→ barricade/repair
→ farming/cooking
→ wood processing
→ corpse cleanup
→ resource mission
→ return.

## Player Companion

meet
→ talk
→ trust
→ recruit
→ HUD/orders
→ travel/loot/fight
→ inventory/equipment management
→ medical treatment
→ return to base
→ job assignment
→ Survivor Card
→ Base Setup
→ Notebook.

## Persistent World

Support normal gameplay with:

- independent survivors;
- groups;
- factions;
- settlements;
- camps;
- missions;
- unloaded activity;
- appropriate faction conflict.

Meaningful save/load and unload/revisit testing must preserve critical state and restore the same survivor without duplicate identity/body or real-player corruption.

---

# Definition of Done

The project may be declared:

# FEATURE COMPLETE — READY FOR FULL QA / POLISH

when:

1. no major required system above remains missing;
2. promised mechanics have real production implementations rather than placeholders/debug-only paths;
3. major systems are connected into coherent normal gameplay;
4. critical persistent state survives reconstruction and save/load;
5. the major acceptance loops have usable gameplay paths;
6. remaining work is primarily QA, bugs, balancing, optimization, compatibility and polish.
