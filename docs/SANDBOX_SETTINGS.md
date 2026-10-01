# Sandbox settings

Knox Survivors exposes **52 settings across seven pages**. The pages follow a
player task: core rules, population, world/factions, base work, companion
controls, display, and developer tools. The option keys, types, defaults, and
their `SandboxVars.KnoxSurvivors` storage names are unchanged except that the
redundant `AllowCompanionPartyScavenging` control is retired. Moving an option
between pages does not change its saved value.

The old `AllowCompanionPartyScavenging` value is ignored. Companion Auto-Loot
is the one in-game control for nearby pickup and the bounded party-food detour.
It is saved per companion; turn it off for anyone who should not pick things
up. Existing companions with no saved Auto-Loot preference remain enabled, as
before. The food detour still requires settled Follow, nearby safe real food,
and the existing threat/order/need checks. No base-resident or NPC-faction
behavior is changed.

`ToolCupboardCapacity` remains visible under **Bases & Work** as a legacy
compatibility option because old marked Tool Cupboard assignments still read
it. Current typed storage assignments use native container capacity. The
classic right-click command setting also remains as an optional alternate
order surface. It defaults off and does not change Auto-Loot or any other
gameplay permission.

## General

| Setting | Purpose |
|---|---|
| Enable Knox Survivors | Master gameplay gate; disabling preserves saved survivors. |
| Start with a Spouse | Creates one initial trusted companion for a new character. |
| Survivors Continue After Player Death | Transfers the existing household to the next character; the spouse becomes a base resident and no second spouse is generated for the successor. |

## Population

| Setting | Purpose |
|---|---|
| World Survivor Population | Persistent whole-map starting/target population. |
| Population Refill Days | Days between replacement/new arrivals; `0` means no routine arrivals. |
| Chance of Starting Survivor Groups | Chance for nearby starting identities to form a small group. |
| Maximum Starting Group Size | Size limit for those initial groups. |
| Maximum Starting Groups | Number of initial groups created. |
| Disable Survivor Caps | Opts out of active-body and companion limits; may cost performance. |
| Maximum Active Survivors | Normal limit for loaded survivor bodies. |
| Survivors Loaded Per Update | Limits body creation per population update to avoid spikes. |
| Minimum Survivor Spawn Distance | Hidden first-materialization distance from local players. |
| Survivor Encounter Distance | Distance at which persisted survivors may materialize; effective value stays at least 10 tiles beyond the minimum spawn distance. |

## World & Factions

| Setting | Purpose |
|---|---|
| Cautious Everyday Travel | Chooses ordinary walking/crouching route behavior. |
| Allow Autonomous Survivor Retreat | Gates new autonomous retreat admissions; does not disable combat or explicit orders. |
| Automatic Zombie Engagement Distance | Range for automatic engagement of visible zombies. |
| Allow NPC Factions | Allows new NPC faction formation; does not delete existing factions. |
| Survivors Needed to Form a Faction | Minimum group size before faction promotion is considered. |
| Maximum NPC Faction Members | Limits future faction recruitment; lowering it does not remove members. |
| Allow Hostile Survivor Encounters | Allows independent survivors to threaten/rob each other. |
| Allow Survivor and Player Combat | Allows hostile survivors and players to fight under existing hostility rules. |
| Use Reputation for Recruiting | Makes relationship reputation part of recruitment eligibility. |
| Enable Knox Events | Enables scripted faction/named-world event dispatch; off by default. |
| Allow Faction Raids | Enables automatic real-member raids; off by default and depends on factions/hostility. |
| First Possible Faction Raid Day | Earliest world day for an automatic raid. |
| Faction Raid Check Interval | Minimum time between raid scheduling checks. |

## Bases & Work

| Setting | Purpose |
|---|---|
| Automatic NPC Base Work Areas | Creates practical default areas at autonomous NPC faction bases; player bases remain manually configured. |
| Survivors Cook at Base | Enables supported real-resource cooking tasks. |
| Survivors Read at Base | Enables supported book reading/recreation at base. |
| Legacy Tool Cupboard Capacity | Compatibility for old marked cupboards only; does not set capacity on current typed storage. |

## Companions & Orders

| Setting | Purpose |
|---|---|
| Companion Limit | Maximum active companions per local player. |
| Follower Formation | Preferred paired or single-file formation. |
| Follower Spacing | Preferred distance between follower positions. |
| Allow Survivors to Open Doors and Windows | Allows owned survivors to open closed doors/windows while routing. |
| Survivors Bandage Their Player | Allows safe, nearby owned survivors to treat a bleeding player when eligible. |
| Use Gestures When Giving Orders | Enables rate-limited acknowledgement/movement gestures. |
| Show Knox Orders in Emote Radial | Adds Knox actions to the vanilla emote radial; on by default. Off leaves vanilla radial actions intact. |
| Show Knox Orders in Right-Click Menus | Alternate command surface, off by default. When off, Knox order menus do not appear in right-click menus, even if the radial integration is unavailable. When on, survivor and party context menus are available. This does not change the F interaction prompt or care/inventory controls. |
| Allow NPC Driving (Experimental) | Enables the bounded companion driving order; Build 42 vehicle behavior remains live-pending. |
| NPC Driving Speed Limit | Speed cap for the experimental driver. |
| Survivor Aiming Assistance | Changes commitment/aim settling only; native skill still owns accuracy and effectiveness. |

## Interface

| Setting | Purpose |
|---|---|
| Show Companion HUD | Displays the companion status panel. |
| Show Survivor Activity Feed | Displays the Knox activity window; hiding it does not stop event recording. |
| Show Survivor Speech | Displays survivor speech bubbles/lines. |
| Show Survivor Names | Displays visible survivor nameplates. |
| Survivor Name Distance | Maximum nameplate distance; line of sight is still required. |

## Developer Tools

| Setting | Purpose |
|---|---|
| Enable Developer Tools | Enables manual developer context-menu actions; off by default. |
| Automatic Test Scenario | Optional persistent developer population preset; `None` is the default. |
| Test Spawn Distance | Minimum placement distance for developer-spawned actors. |
| Allow Destructive Tests | Explicitly allows test actions that alter the area. Keep off on saves you care about. |
| Log Developer Diagnostics | Enables verbose developer status output; normal errors are separate. |
| Ignore Job Tool and Resource Requirements | Developer cheat that can provide real items for supported jobs. It can leave those items in the world; keep off during ordinary resource-loop play. |

## Compatibility and save behavior

Sandbox defaults are stored with the save when its rules are created. The
following retired values can still exist in older `SandboxVars` data but no
longer create controls or change runtime behavior:

- `AllowCompanionPartyScavenging`: retired; the in-game per-companion Auto-Loot
  policy now owns this behavior.
- `AutomatedQAMode`: retired with the in-game QA runner.

No save is rewritten and no keys are renamed. `ToolCupboardCapacity` remains
active for legacy Tool Cupboard markers, while `ShowLegacyContextCommands`
remains an active presentation preference. New controls or system-wide
presets are not implied by this cleanup.

Project Zomboid-native movement, actions, combat, item transfer, driving,
rendering, and persistence remain subject to the live acceptance recorded in
`docs/DEVELOPMENT_TESTING.md`; settings registration and offline tests do not
prove those engine behaviors.
