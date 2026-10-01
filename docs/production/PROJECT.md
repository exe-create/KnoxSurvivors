<!-- modforge-doc
authority: canonical
load: always
purpose: stable product vision and operating principles
-->

# Knox Survivors — production project definition

Updated: 2026-09-28

## Product

Knox Survivors is a single-player Project Zomboid Build 42 survivor/NPC mod rebuilt from the ground up by **.exe**. Its goal is a persistent living human population that uses Project Zomboid's existing systems wherever practical and still feels like the base game rather than a separate follower or colony game.

Current public release line: `0.3.0-rc1`, with mod metadata targeting Project
Zomboid Build `42.20–42.21`. Build 42.21 compatibility is being tested and is
not verified; the metadata range is not a compatibility guarantee.

## The fantasy

You load into ordinary Zomboid — and then the county proves it is alive. Over a rise you hear a fight: a small group battling another over food, materials, or old history. On a porch cowers a lone survivor, scared, looking for shelter. Down the road a faction base is building up and farming, and its people might let you stay until you get on your feet. A retired cop, a guardsman, a drifter — someone who wants conversation but not company. None of it scripted. The same universal rules move groups, factions, and lone wanderers alike, so every meeting feels discovered rather than staged.

## The people

Survivors are rare — never armies — but ordinary exploration finds them without hours of searching. Each one is a persistent person with a face, history, relationships, possessions, health, skills, and responsibilities: solos are the norm, travelling groups uncommon, factions rare. Meeting, recruiting, or losing someone matters, because losing the medic, the mechanic, the shooter, or the farmer changes what a community can actually do through real skills and real stocks.

## The danger

Walking-Dead unpredictable. Strangers may share, talk, rob, or attack depending on history and current relations — humans scarier than the dead, and the greatest reward in the county is earning someone's trust and surviving together. Hostility is never random and never guaranteed; it grows out of what actually happened between people.

## The home

Bases are real homes, not menus: claimed buildings with honest boundaries, labelled storerooms, guard posts, farms, woodlots, and workshops. Residents work real shifts with real tools and materials — guarding, barricading, repairing, farming, cooking, hauling the dead — and everything they make, move, or consume is a genuine world change. Shortages create work; work consumes resources; nobody conjures supplies.

## The company

Survivors can join you and stay joined: follow, hold, guard, return home, loot on directive — orders that survive interruption, unloading, and save/reload. The Survivor Card, Notebook, HUD, and activity feed tell you the truth about who they are, how they feel, and what they are doing, quietly until something matters.

## The living county

Life continues everywhere, all the time, whether you are watching or not. Off-screen survivors keep travelling, eating from their packs, resting, holding their intent, and accruing history in real time through a cheaper ledger — the same person and story, without the cost of loaded bodies, pathfinding, or animation. Nothing is faked to save performance: anything needing a real body waits for one, and every abstract outcome reconciles onto the same survivor when you meet again. Groups form, factions settle, encounters and raids resolve — always through loaded native outcomes, never invented ones.

## Your county, your rules

Conservative immersive defaults out of the box, with deep organized sandbox settings for exact customization and plain-language rarity presets on the way — so every player gets their apocalypse, lonely or lively, without anyone left out. Settings shape behavior and pacing; they never bypass identity safety, real resource requirements, or save integrity.

## What it is not

Not a colony game of programmable pawns. Not scripted story encounters. Not a strategy map, a resource counter, or a second simulation fighting the first. Other games inform individual mechanics only; Project Zomboid remains the foundation, and a Knox survivor remains an AI-controlled Project Zomboid survivor.

Kept and growing (not current release promises until their gates pass): vehicles, cooking breadth, trading depth, camps, faction raids and large events, away missions, full faction politics, a creator on the vanilla character creator with Knox additions, and multiplayer compatibility. See `DECISIONS.md` D-004, D-015–D-018 and `docs/design/NPC_SYSTEM_INSPIRATION.md`.

## Core NPC rule

> **A Knox survivor is another Project Zomboid survivor controlled by AI, not a colony-game pawn.**

Project Zomboid is the foundation. Other games may contribute individual design lessons, but Knox should translate those lessons into PZ's real world/items/actions rather than imitate their full game loops.

See `../design/NPC_SYSTEM_INSPIRATION.md`.

## Product principles

- Persistent survivor identity matters more than disposable NPC bodies.
- Vanilla systems, items, containers, actions, combat, farming, clothing and world objects are preferred where practical.
- Survivors should behave as people trying to survive, not as a free army or player-programmed colony workforce.
- Loaded and unloaded states should represent the same persistent person and continuing story.
- Off-screen life is continuous and real, never faked: survivors keep travelling, consuming real supplies, resting, holding intent, and accruing history in real time through a cheaper ledger — not through invented outcomes. Performance comes from cheaper computation (no pathfinding, animation, or per-tick bodies), never from fabricating supplies, combat, loot, death, or world damage.
- Real shortages/problems should create work; work should consume real resources.
- Survivors, specialists and established groups should be uncommon enough that finding or losing one matters.
- The same universal rules move independents, groups, and factions — encounters are discovered, never staged.
- Danger is relations-driven and wide-ranging: strangers may help, talk, rob, or attack based on real history.
- Every roadmap system is kept and grows later; gates, not cuts, sequence the work.
- Survivors stay fluid: traversal, combat, and actions hand off immediately to the next thought — never a frozen pause while the brain "thinks." Completion or interruption releases ownership on the same update and re-arbitrates on the next tick.
- Single-player is the current supported focus.
- Experimental vehicle autonomy, raids/large faction events, away-team missions, full construction and multiplayer NPC support are not current release promises.
- Save integrity, identity/lifecycle correctness, native action ownership and real-player/IsoPlayer ownership take priority over feature breadth.
- The next playable milestone is a core-completion pass: connect, repair, expand and polish existing systems until the survivor loop is coherent, believable, playable and fun before starting unrelated feature families.
- Existing experimental systems with real implementation and a clear player purpose should be completed safely; systems that have not meaningfully started remain deferred until the core loop is reliable.
- Player-facing defaults should be balanced and performance-conscious, while meaningful behavior and population/performance limits remain configurable where the architecture supports it.

## Engineering principles

- One authoritative owner per system boundary.
- Prefer one primary survivor intention/job plus bounded emergency reactions over competing permanent controllers.
- Existing systems should be connected through shared arbitration/claims/needs/history where useful, not rewritten merely to look uniform.
- Smallest architecture-safe fix at the first confirmed failure.
- No fabricated supplies, native success, damage or verification.
- Cheaper off-screen simulation must preserve ledger truth: same rates, same intent, real consumption, deterministic history, idempotent reconcile — with physical consequences materialized only through loaded native actions.
- Live engine behavior requires live engine evidence.
- Historical evidence is useful but does not automatically represent current truth.

## Project operating model

The repository is fully usable without ModForge. `AGENTS.md`, Git, and the
canonical `docs/production/` records are the standalone operating path for
Codex, OpenCode, and human work. ModForge is an optional local coordination and
indexing desk that makes the same records easier to browse, triage, hand off and
keep synchronized; it is not required to edit code or continue development.

- The repository's canonical production/design records remain durable truth.
- ModForge may index those records, maintain its generated coordination snapshot,
  and perform guarded write-through only where the project contract allows it.
- Codex/OpenCode may work normally from the repository without ModForge running,
  using the same task IDs, evidence rules and Git review path.
- ModForge keeps roadmap, tasks, bugs, decisions, design intake, documentation map, collaboration ledger, evidence state and handoffs aligned when it is active.
- The assigned Codex Boss is the engineering authority for implementation, expansion, debugging and release hardening; Luna is the normal Boss, and Sol/Astra require the escalation or explicit owner assignment in `AGENTS.md` and `AI_WORKFLOW.md`.
- OpenCode is the budget-engineering authority for confirmed bugs, support work, focused implementation, cleanup and compatibility/collaboration support.
- Live acceptance is tracked evidence and a release gate, not a universal blocker for independent mechanics. The project may continue bounded development while a live scenario remains open, provided the unverified boundary is recorded honestly.
- Project Zomboid's real APIs, native systems, assets, items, actions, resources and runtime state are preferred. Reverse-engineering notes and reusable Zomboid modding references may be consolidated later as a knowledge/documentation project; they are not a current milestone priority.
- The human owner remains final for product direction, source-write permissions, release decisions, collaborators and public commitments.

## ModForge source boundary

ModForge-managed production/design records may be maintained automatically. Gameplay/source code is read-only by default unless the owner explicitly enables a source write.

Any owner-approved ModForge source write must leave a change note and remains unverified until the normal Git diff + Codex/OpenCode/QA path validates it.

This boundary applies only to ModForge Studio. It does not restrict normal
Codex/OpenCode or human repository work.

## Operational scale

As of 2026-09-26, the owner reports Knox Survivors is approaching 26,000 active users. Treat that as owner-reported operational context, not independently verified analytics. At that scale, support triage, compatibility records, collaborator tracking, release evidence and careful public wording are production responsibilities.

See `AI_WORKFLOW.md` for the operating loop.
