<!-- modforge-doc
authority: canonical
load: always
purpose: canonical settled decision ledger
-->

# Knox Survivors — active project decisions

Updated: 2026-09-30

These are settled operating/product decisions extracted from the current repository documentation. Agents should not reopen them without new evidence or owner direction.

## D-001 — Single-player is the current supported focus

Multiplayer NPC support is not a current release promise.

Source: `README.md`, `RELEASE_NOTES.md`.

## D-002 — Prefer native Project Zomboid systems where practical

Survivors use real items, actions, containers, combat, clothing, farming, and other vanilla systems instead of simulated success where practical.

Source: `README.md`, `docs/ARCHITECTURE.md`, `docs/production/PROJECT.md`.

## D-003 — Live engine behavior requires live evidence

Offline doubles/tests do not prove native animation, projectile damage, item transfer, pathing, UI behavior, or other engine-bound behavior.

Source: `docs/production/QA_RELEASE.md`, `docs/DEVELOPMENT_TESTING.md`.

## D-004 — Experimental systems remain experimental until accepted

Vehicle autonomy, automatic raids/large faction events, away-team dispatch, developer QA modes, and other explicitly experimental systems must not become release promises without their acceptance gate.

Source: `README.md`, `docs/production/QA_RELEASE.md`, `RELEASE_NOTES.md`.

## D-005 — KnoxBridge is the sole supported Knox Java runtime path

KnoxBridge is the only supported public Knox Java runtime/setup path. The
separate Knox Survivors Launcher is deprecated and unsupported; the owner has
requested its repository be made private, a setting change still pending
confirmation. Do not distribute, recommend, or use old launcher builds.
Retain its source only as a historical archive.
The direct Knox Java agent remains a source rollback artifact, not a player
setup option. Never stack KnoxBridge with external Java runtime or another instrumentation
runtime. Java modules must explicitly implement the KnoxBridge contract;
arbitrary or JARs that use other Java runtimes are not assumed compatible.

Source: `README.md`, `docs/production/RUNTIME_AND_MIGRATION.md`,
`docs/production/RESEARCH_AND_COMPATIBILITY.md`.

## D-006 — Historical engineering evidence does not own current status

`docs/FEATURE_AUDIT.md` and Git history preserve deep implementation evidence. Current production truth is routed through `docs/production/` and must be reconciled against the current worktree.

Source: `docs/README.md`, `docs/production/SOURCE_REGISTRY.md`.

## D-007 — ModForge is optional coordination; Codex/OpenCode implement

ModForge owns organization, roadmap, documentation, low-cost planning/review,
bug/decision tracking, and handoffs when it is being used. Codex/OpenCode remain
the normal coding path and must be able to work directly from the repository
without ModForge installed, running, or synchronized.

Source: `docs/production/PROJECT.md`, `docs/production/AI_WORKFLOW.md` and owner direction.

## D-008 — Canonical repository records are the durable production truth

`docs/production/WORK_QUEUE.md` and `docs/production/BUGS.md` own repository-backed work state independently of ModForge. ModForge may edit those records through guarded write-through, but its local database and generated `.modforge/PROJECT_STATE.md` are coordination/cache layers rather than competing truth. External repository edits win on sync conflicts.

Source: owner direction and the production hardening workflow.

## D-009 — One implementation owner per work item

A single coding lane owns dependent implementation for a task. Planner, Grunt, Researcher, and QA agents may support or independently review it, but they must not make competing edits to the same dependent work. Adjacent discoveries are triaged separately unless the active task demonstrably requires them.

Source: owner direction and the production hardening workflow.

## D-010 — Codex and OpenCode own technical execution for assigned implementation

For an approved work item, the assigned Codex Boss is the technical authority for Codex engineering and OpenCode is the technical authority for bounded budget/scoped engineering. Normal routing is GPT-6 Luna Boss, GPT-5.6 Luna Planner and GPT-5.6 Terra support/review. Sol and Astra require the evidence-gated escalation in AGENTS.md or explicit owner assignment; the authorized Astra whole-project pass does not change that default. ModForge, Boss, Planner, and cheap support agents own coordination, scope, priority, constraints, evidence, and routing; they do not compete with or repeatedly re-plan the active implementation unless project vision, architecture ownership, scope, evidence, or release safety is violated. The human owner remains final for product/reputation/release/public decisions.

Source: owner direction and the production hardening workflow.

## D-011 — Usage exhaustion and logs must fail safe

Running out of model allowance, rate limit, or credits must not silently enable paid usage, mark work complete, or alter release status. Preserve completed evidence/diffs, use only a deliberately configured safe free fallback when capable, otherwise pause the item for later resumption. Debug/console logs are on-demand diagnostic evidence only and must not be preloaded into routine project context; inspect the smallest relevant recent slice when the active runtime/test boundary requires it.

Source: owner direction and the ModForge 1.9 failover/diagnostics policy.


## D-012 — Knox NPCs remain Project Zomboid survivors, not colony pawns

Other games are mechanic references only. The NPC architecture should connect current Knox systems around one primary intention/job, bounded emergency reactions, real PZ resources, group/base needs, persistent relationships/history and loaded ↔ unloaded continuity.

Do not replace working Knox systems simply to imitate another game's architecture.

Source: owner 2026-09-26 research direction and `docs/design/NPC_SYSTEM_INSPIRATION.md`.

## D-013 — Standalone development remains supported

The minimum supported workflow is: read `AGENTS.md`, load the small canonical
production path, identify a task/bug or explicit owner request, inspect Git,
implement with the assigned coding tool, validate, and update the existing
canonical record. ModForge sync, generated state, Inbox, Change Ledger and
handoff UI are optional accelerators and must never be prerequisites for work.

Source: owner workflow direction and `AGENTS.md`.

## D-014 — Complete and connect existing systems before unrelated expansion

The next playable milestone prioritizes finishing, connecting and polishing the
systems already implemented: survivor loops/brains, movement/pathing, native
actions, combat/threat awareness, persistence/off-screen continuity,
storage/base/jobs, companion orders/UI, events/factions/world life, and the
launcher/runtime boundary where required. A new feature family stays deferred if
it has not meaningfully started or has no clear purpose in the core loop.

An implemented experimental system with a real player purpose should be brought
to a safe complete state rather than abandoned as a half-connected promise.

Source: owner milestone direction, 2026-09-26.

## D-015 — Balanced defaults with explicit player customization

Player-facing defaults should be conservative, believable and performance-aware.
Meaningful population, autonomy, event, difficulty and performance behavior
should be configurable where the existing architecture supports it. Settings do
not bypass ownership, native-world requirements, evidence gates or save safety.

Source: owner milestone direction, 2026-09-26.

## D-016 — Off-screen simulation is continuous, real, and cheaper — never faked

Unloaded survivors continue in real time: travel, needs, rest, intent, group membership, and history keep advancing through the persisted ledger at the same rates and triggers as loaded life. Performance savings come from cheaper computation (coarse travel, stepped needs, bounded storylets, no bodies/pathfinding/animation), not from inventing supplies, combat results, loot, injury/death, blood, smashed windows, robbery, or raid outcomes. Every abstract outcome reconciles idempotently onto the same identity through loaded native actions; failed materialization stays retryable.

Source: owner vision direction, 2026-09-28.

## D-017 — Rare-but-findable population, relations-driven hostility, deferred politics/creator/MP

Settled from owner concept answers, 2026-09-28:

- **Rarity:** survivors stay rare — never armies — but findable without hours of searching. The apocalypse feels empty yet encounters, fights, and immersive world activity happen through ordinary exploration. Everyone keeps moving, eating, and surviving off-screen. Defaults stay conservative; named modes/presets (e.g. Lonely / Balanced / Lively) should eventually let each player pick their preference without leaving anyone out.
- **Hostility:** encounters are relations-driven. A survivor may be hostile or not depending on history and current relations — never random aggression and never guaranteed peace.
- **Deferred:** full faction politics (alliances/wars/territory deals), the survivor/faction creator built on the vanilla character creator plus Knox additions, and multiplayer compatibility are future tracks. Single-player remains the supported focus (D-001); these tracks begin only after the core loop is live-verified, each with its own approved work item.

Source: owner concept direction, 2026-09-28.

## D-018 — Walking-Dead danger, universal living-world moments, keep-all-systems

Settled from owner concept answers, 2026-09-28:

- **First moments:** loading in feels like normal Zomboid — then the world proves alive. Stumble on a small group fighting another over food, materials, or past history. Find a lone scared survivor looking for shelter. Come across a faction base building up and farming. Meet police, military, or a solo survivor who wants conversation but not company. Universal and systemic, never scripted encounters — the same rules for groups, factions, and independents.
- **Danger:** unpredictable and human. Strangers may share, talk, rob, or attack depending on history and relations — humans scarier than zombies, and the greatest benefit comes from working together when it clicks. Think Walking Dead realism. This sharpens D-017: relations-driven, but wide-ranging rather than mostly-cautious.
- **Keep all:** every system on the roadmap stays — vehicles, cooking, trading, camps, raids — with more expansion later, not less. Nothing is cut.
- **Join-as-member (future):** asking to join or live at a faction base as a member rather than a leader is a future feature track with its own work item, after the core loop is live-verified. Today recruitment means survivors joining the player, not the reverse.
- **Preset naming:** future rarity presets get the best plain player-facing names; sandbox settings stay numerous and organized for exact customization. Placeholder names in current docs are not final.

Source: owner concept direction, 2026-09-28.

## D-019 — Driving joins the core-completion track; offline-first tempo

Settled from owner direction, 2026-09-28:

- **Driving scope:** autonomous NPC driving, group vehicle acquisition, and group/faction convoys move from experimental-gated (D-004) to the core-completion track. NPCs use vehicles on their own for a believable world; groups obtain and share cars; convoys run 2–3 carloads with no hard count cap — bounded only by real vehicle availability, condition, and fuel, plus documented performance budgets. Seating, entry/exit, control release, and persistence stay identity-safe under existing ownership.
- **Storage support:** heavy vehicle/base materials (logs, metal sheets, parts) route through the existing typed-storage policies; no second stockpile owner is created to serve vehicles.
- **Tempo:** live Build 42 testing is halted unless absolutely needed. Progress is proven offline with focused regressions plus `tools/verify.ps1 -SkipJava`; every live-only boundary is recorded as an open replay item with its exact scenario, not run. Evidence gates themselves do not move — deferred live items still block their release claims.

Source: owner direction, 2026-09-28.

## D-020 — Social transfer consequences require verified real transfer

Gift or money interactions may not award relationship trust, play a received-
gift response, or report success unless the existing physical item owner has
verified the corresponding transfer. `Give Item` therefore uses the existing
trade UI/action in explicit one-way gift mode, including real inventory
ownership, capacity, receipt, rollback, and capture checks. Its gift contribution
is awarded after the verified transfer only. Abstract currency balances are not
an owner; supported tangible currency items are transferred as real items.
Social-only actions must never stand in for a missing economy operation.

Source: source-confirmed `BUG-KS-032`, 2026-09-28.

## D-021 — Loaded social memory records finalized outcomes only

The loaded relationship coordinator owns encounter decisions and verified
social consequences; `KS_OffscreenStories` owns bounded personal history in
each survivor's existing persistent ledger. Record an event only after its
loaded outcome is committed (greeting, disposition, or real group membership).
Interrupted encounters are not memories. Hostility records a persisted hostile
encounter, never an assumed fight, robbery, or transfer. Fail closed when a
canonical survivor ledger is unavailable; do not create partial persistence
state for narrative convenience. Existing dialogue and presentation consume
that history.

Source: source-confirmed `BUG-KS-036`, 2026-09-28.

## D-022 — Faction bases answer their own real supply shortages

Player-owned base residents still require the existing per-resident player
permission before automatic loot runs. A resident of a faction-owned base may
answer that base's real storage shortage through the existing supply planner
when its persisted faction affiliation matches the base owner and its duty is
ordinary autonomous work. Explicitly specialized residents and existing task,
event, away-team, need, and group-sortie ownership retain their current
arbitration. The run remains one real-item, persisted, shortage-claimed trip
through the existing receipt-gated deposit path; no separate faction mission or
storage owner is created.

Source: source-confirmed faction supply-election boundary under KS-PROD-008,
2026-09-29.

## D-023 — Base danger may suspend work into the shared retreat owner

An ordinary base resident may use the existing bounded, threat-weighted
retreat when danger and a checked escape lane justify it. Direct player
companions remain excluded from autonomous retreat. Retreat suspends the
current base task without completing or releasing its task-board claim, and
releases transient work reservations. An active base supply run, explicit
order, and carried delivery remain owned for the existing return/deposit path.
After the existing safe-scan clear condition, the resident returns through
normal base arbitration. Do not create a separate base-defense or retreat
controller, and do not use offline tests as proof of native escape/combat.

Source: source-confirmed `BUG-KS-012` retreat ownership boundary,
2026-09-29.

## D-024 — Automatic equipment upgrades are a per-survivor player policy

The persisted `autoEquipment` preference controls only opportunistic equipment
reevaluation by autonomy (idle and post-loot). A missing value means enabled
to preserve existing saves and behavior. Explicit inventory management and
combat equipment selection retain their current owners and do not consult this
policy. Store the setting in the survivor's existing `policies` record; do not
add a Sandbox option, equipment manager, or alternate inventory path.

Source: `KS-PROD-008` player-control completion slice, 2026-09-29.

## D-025 — Player party destinations are shared session intents, not group leadership

The player may issue one destination to the current eligible companion roster
through the existing party-command owner. The command is session-scoped because
the current player-scoped persistence record cannot safely own shared-order
cancellation, succession, per-member overrides and controller synchronization.
Each companion independently uses its existing controller/native movement
owner. The player remains the party authority and existing Follow anchor; no
companion route leader, or NPC travel-group objective/faction-leader destination
policy is added in this destination slice. Existing
individual directives override the shared destination and remove only that
member from its participant set. Temporary threat/combat, urgent needs,
traversal, native actions and recovery retain priority and resume through the
ordinary controller. The order expires after one in-game hour and clears on
cancellation, invalid/empty roster, or all eligible members arriving within
1.5 same-floor tiles. Player-anchored runtime formation is separately governed
by D-026 and does not change the destination's command or persistence owner.

Source: owner direction for `BUG-KS-028`, 2026-09-29.

## D-026 — Player-party cohesion is a runtime projection around the player

The player remains the normal party authority and spatial anchor. The existing
`KS_CompanionService` derives Follow-eligible recruited members and assigns
stable runtime-only formation slots/headings; `KS_SurvivorAutonomyController`
continues to arbitrate the survivor's one active intention and owns every native
movement request. Player-only formation targets may use unique leases in the
existing autonomy reservation table; they do not add a second movement owner,
persisted party roster, companion leader, or player faction. Hold/Relax, base
duty, individual directives, and invalid/dead/dismissed members remain excluded.
Shared destination participants remain governed by D-025's snapshot,
cancellation, expiry, individual-order, and physical arrival rules. NPC travel
group/faction formation and leadership are unchanged.

Source: approved player-party cohesion package for `BUG-KS-028`, 2026-09-29.

## D-027 — Firearm intent is bounded; native Build 42 owns weapon behavior

Combat intent may choose a firearm, but Project Zomboid's own reload/rack timed
actions, attack hook, projectile/ballistics, hit/damage calculation, weapon
condition, chamber/magazine/ammunition state, and gunshot sound remain the sole
owners of firearm behavior. Knox may only select a real carried weapon, commit
one encounter to that exact weapon class for its current target until a real
invalidation, bound its own reload-preparation window and ranged approach/pursuit
failures, and fall back to a real carried melee weapon through the existing
combat/melee owner. Knox must never fabricate ammunition, damage, hits, reload
completion, or a parallel ballistics/ammunition model, and must clear its
transient firearm state through one teardown owner at every terminal combat
boundary. Java is not changed for this; the existing bridge contract stands.

Source: owner-approved `BUG-KS-029` firearm stabilization package, 2026-09-29.

## D-028 — Work preferences are a base-resident selector hint

The four player-facing states (High, Normal, Low, Disabled) apply only to
player-owned survivors in base duty through the existing one-job task selector.
High/Normal/Low break otherwise equal task choices; Disabled prevents future
autonomous selection without cancelling active native work, claims, explicit
assignments, or active supply delivery. Missing values mean Normal. Only
categories already mapped by the selector are exposed. Active companions do
not receive autonomous work selection or effective controls; a companion's
saved policy may be used after assignment to base duty. Faction and independent
survivors remain unchanged.

Source: owner-approved bounded `BUG-KS-023` work-preference slice, 2026-09-29.

## D-029 — Active companion work remains subordinate to survival and orders

An active companion may autonomously perform only low-risk nearby work when
enabled by an explicit player-facing control. Explicit player orders, combat and threats,
urgent needs, traversal, formation, destination travel, active supply runs, and
recovery retain higher priority. Disabling the policy prevents new autonomous
work admission; companions remain available for orders, formation, combat, and
survival. Work must use real world resources/actions and existing ownership;
no parallel global scheduler or reuse of the base-resident selector as a
companion policy is permitted. Base-resident work behavior is unchanged.

The initial category and detailed admission semantics were left to the
Planner/Boss to bound. D-030 records the resulting approved first slice and its
explicit exclusions.

Source: owner direction for active-companion autonomous work, 2026-09-29.

## D-030 — Companion field support starts with one nearby food pickup

Active companion work is distinct from base-resident jobs. The first slice is
controlled by the companion's existing in-game Auto-Loot permission; no
second Sandbox allow/disallow switch is used. The retired
`AllowCompanionPartyScavenging` Sandbox key is ignored, including when it is
present in an older save. It applies only to a player-owned companion in settled Follow, on
the same floor, with one safe food item in a loaded container within 12 tiles
of both companion and player. An unfinished route is abandoned if the player
moves beyond a 3-tile leash, the anchor becomes unavailable, an actionable
need takes priority, or Auto-Loot is disabled in game. Threat, combat, explicit
orders, traversal, destinations, supply runs, and recovery retain their
existing arbitration. Turning off Auto-Loot stops an unfinished route through
the controller; an already queued native transfer may finish, and a
higher-priority combat or explicit directive may interrupt it through its
existing owner. Success requires the exact item in
companion inventory. The item remains
carried by the companion; no base stock or player inventory receipt is implied.

This slice uses the existing controller as arbiter, loot planner, transient
reservations, native movement/transfer, and inventory ownership. It adds no
base-task selector, scheduler, task board, persistent work claim, or offscreen
work. Missing per-companion Auto-Loot values retain the existing enabled
default for old saves. Water, woodcutting, organizing,
broader scavenging, companion-to-player delivery, NPC factions, independent
survivors, and base work remain outside this first slice.

Source: owner clarification and bounded KS-PROD-008 implementation decision,
2026-09-29.

## D-031 — Retreat choice is survivor-specific and risk-comparative

This is a design decision for the future retreat-policy implementation, not a
change to the currently implemented `BUG-KS-012` admission logic. Keep its
existing controller and native movement owner stable until a separate bounded
implementation pass has a focused scorer/acceptance path. A survivor's choice
must compare the danger of fighting with the danger and feasibility of leaving;
"many zombies" alone is not a complete decision.

The future explainable assessment may use current health, bleeding/injury/pain,
armor and clothing, carried weapon/ammo, combat skill, strength/fitness, the
survivor's own and nearby group's capability/cohesion, number/type/range of
threats, surprise/preparedness, flanking/surrounding, route/choke/door safety,
player behavior, recent success/failure, confidence/morale, and hunger/thirst/
fatigue/panic moodles. Missing native inputs must be treated as unknown or
neutral, never fabricated. Any randomness is a small deterministic tie-break
for genuinely close assessments; it cannot reverse a clear safe-fight, unsafe-
route, or overwhelming-danger result. It must not create a second combat,
movement, or group-order owner.

#### Acceptance matrix for the future slice

| Situation | Expected policy result | Required evidence |
|---|---|---|
| Healthy, prepared survivor/group; one ordinary zombie; safe engagement | Hold/fight, no arbitrary flee | Explainable low/contained risk and no flee admission |
| Injured, bleeding, unarmed or exhausted survivor; multiple active threats; viable clear route | Admit retreat when route risk is lower | Native route begins once, needs/claims/orders recover afterward |
| Strong equipped group with cohesion versus a small threat | Usually fight/hold; leader does not scatter the group | Group capability and cohesion affect the result |
| Survivor is surrounded or all escape lanes are blocked/dangerous | Do not claim a nonexistent safe retreat; use existing defense/recovery | No fake movement or endless repeated flee request |
| Prepared versus surprised encounter, including nearby player fighting or withdrawing | Context may change a close decision but does not override explicit order or clear lethal risk | Same real inputs, bounded explainable difference |
| Recent injury/failure, low morale or severe moodles | Shift relative confidence/risk without producing random oscillation | Stable result across a short window; bounded retry/hysteresis |
| Equivalent close cases with the bounded tie-break | Outcomes may vary only within the narrow tie band and remain stable for that encounter | Deterministic replay per survivor/encounter; no per-tick reroll |

Offline acceptance must cover the scorer's inputs, missing-data handling,
threshold boundaries, stable tie-break, hysteresis, and arbitration precedence.
Build 42 acceptance must separately compare one zombie, a small group, an
overwhelming group, injuries/equipment, prepared/surprised approaches, player
behavior, blocked/viable exits, group cohesion, combat interruptions, and
post-retreat resumption using real native health/ammo/movement outcomes. Until
that package is separately scoped, do not tune or expand current fleeing code.

Source: owner-approved retreat-redesign factors and acceptance requirements,
2026-09-30.

## D-032 — Knox radial visibility is a separate player policy

The Sandbox option `ShowRadialOrders` controls whether Knox adds its actions to
the vanilla emote radial. It defaults on. The compatibility key
`ShowLegacyContextCommands` controls the alternate Knox order menus in
right-click; it defaults off and is never automatically enabled as a radial
fallback. Players may enable either or both surfaces. When both are off, Knox
orders are hidden from those two surfaces. The F interaction prompt, survivor
care controls, Notebook, and target-specific vanilla interactions remain
separate. `OrderGestures` remains a separate acknowledgement-animation setting.
The radial and context-menu paths continue to use their existing command
owners; this setting only controls presentation.

Source: owner-requested radial visibility behavior, implemented and covered by
offline settings/radial regressions, 2026-09-30. Build 42 radial rendering and
mouse/joypad acceptance remain pending.

## D-033 — QA coverage stays offline; no in-game coordinator

The automated scenario manifest, coordinator, save-isolation gate, and parser
are retained only as developer/offline regression fixtures. They are not loaded
by normal game startup, are not exposed in Developer Tools, and have no Sandbox
setting. The in-game arming flow was retired because it required confusing
save preparation without advancing ordinary gameplay testing. Existing offline
regressions may load these modules directly.

If an in-game test runner is proposed again, it requires a separate explicit
owner request and a demonstrated safe disposable-save lifecycle. Until then,
owner validation uses ordinary Build 42 play with short, specific replay steps;
`tools/verify.ps1` remains the automated source/regression path.

Source: owner direction to remove the confusing QA feature while preserving the
mod and offline regression suite, 2026-10-01.
# D-034 — autonomy controls are ownership-scoped and safety-preserving

Player-owned companions may receive a future player-facing "Use Judgment /
Orders Only" policy, but it applies only to discretionary companion choices.
Turning it off must not suppress urgent survival needs, danger response,
combat, explicit player orders, follow/formation, traversal, vehicle recovery,
or other interruption/recovery behavior. Existing specific policies such as
Auto-Loot remain specific and must not be presented as a general free-will
switch.

Independent survivors and NPC factions remain autonomous under the shared
survivor/group/faction owners; the player does not toggle their autonomy.
Loaded behavior uses native Project Zomboid actions and world state. Unloaded
Knox survivors continue only the existing truthful abstract travel,
needs/resources, rest, and history simulation; Knox does not invent native
combat, looting, movement, or world effects offscreen. This rule defines the
safe product boundary, not an implementation claim. A broad companion policy
requires a separate audit of elective admissions before its switch is added.

Source: owner request for understandable orders, per-survivor permissions, and
a free-will control, bounded by the existing ownership and offscreen-truth
rules; 2026-10-01.

# D-035 — starting spouse identity follows the household lifecycle

`SpawnWithSpouse` applies to a genuinely new character and creates one
save-persistent spouse with a per-save randomized identity/personality seed.
The reservation is written once and remains stable across retry and reload.
When `ContinueSurvivorsAfterPlayerDeath` transfers the existing household to a
successor, the current spouse remains in that household as a base resident and
the successor does not receive a second spouse. If household continuation is
disabled, a genuinely new character follows the ordinary `SpawnWithSpouse`
setting. Existing spouse identities and old saves are preserved.

Source: owner request to vary starting spouses and avoid contradictory spouse
creation when continuing an existing household; offline persistence and
spouse-start regressions, 2026-10-01. Live save/reload acceptance remains open.

# D-036 — survival sleep outranks ordinary companion movement orders

When a survivor reaches the existing sleep admission threshold, sleep may
temporarily interrupt ordinary Follow/Hold movement intent. The persisted
player order remains intact and is reconsidered after native sleep/recovery.
Urgent threats and other existing higher-priority arbitration remain in force;
this does not make the survivor forget or rewrite the order. Ordinary rest
continues to yield to direct movement orders except at the existing critical
recovery threshold. The shared native sleep action still owns entering,
remaining asleep, and waking.

Source: owner request that owned and independent survivors actually sleep when
they need it; controller arbitration regression and connected sleep tests,
2026-10-01. Build 42 sleep animation, assigned-bed movement, interruption,
order resumption, and save/reload remain unverified.

# D-037 — base storage uses all eligible real containers with filters as preferences

Eligible real containers inside an owned base/outpost boundary participate in
storage automatically; the player does not have to assign every container.
Per-container vanilla item-category filters identify preferred destinations
and organizer homes. Matching filtered containers rank ahead of unfiltered real
container fallback, using the existing priority, distance, capacity, reachability,
reservation, and transfer owners. Filter settings remain in the existing
per-container policy record. Automatic discovery is transient and must not
write a policy, alter container title/capacity, or invent item state.

Ground Storage Zones are a separate future feature: they may place only real
items through a proven exact-square native transfer/receipt and rollback path.
Resident house cleaning is also separate from personal hygiene and carried-item
organizing; any future explicit or free-time cleaning must use real native
actions and remain below urgent needs, threats, orders, and assigned work.

Source: owner clarification and offline storage integration, filter UI, and
organizer regressions, 2026-10-01. Build 42 filter UI, native transfer,
reachability, capacity, and save/reload acceptance remains open. House cleaning
and ground placement are not implemented by this decision.

# D-038 — explicit Follow rematerializes near its owning player when needed

When a player-owned companion has an explicit Follow order and its persisted
offscreen square is unavailable or unsafe, the existing population owner may
restore the same canonical survivor on a safe loaded square within four tiles
of the owning player, on that player's current floor. The saved logical square
always gets first choice. The native survivor record and virtual location must
both be updated through their existing owners before normal body activation.
This fallback does not apply to Hold, base residents, independent survivors,
or faction members, and it never fabricates a body or bypasses standability and
occupancy checks. Build 42 must verify single-body restoration and state
continuity before native acceptance is marked complete.

Source: owner request following Stacy Byrd's confirmed failed rematerialization
and explicit preference for followers to load near the player when the saved
square cannot be used; offline population regression, 2026-10-01.
