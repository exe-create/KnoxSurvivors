# Knox Survivors — player-facing changelog and commit format

This file is the owner of **three public-output rules**: the changelog entries
between Steam updates, the commit-message format, and the public-artifact
boundary. Announcements are written accurately and in the game's own voice
from what accrues here.

## 0.3.0-rc2 — public test download, 2026-11-15

- A manual-install download for Build 42.22 single-player, with the compiled mod
  and a short installation README. One Java runtime is required separately.
- Native gameplay and save/reload acceptance remain pending. Please use a test
  save and report movement around doors, furniture and wall corners.

<!-- Movement candidate, 2026-11-15; unannounced until native acceptance.
- Keep an intermediate waypoint across a tile edge until it is actually reached.
- Preserve route bends when the body is beside the outgoing route.
- Reject furniture when choosing a wall-corner recovery step.
-->

<!-- Pending native Test G, unannounced.
- Survivors approaching a corner at an angle can take the open side when a wall borders the other side.
-->

## Changelog rules

<!-- Unannounced draft, 2026-11-14: source-only; requires dated native acceptance
before inclusion in a Steam announcement.
- Movement: improved recovery around wall corners while following and working
  at base, with safer sidesteps and resumption of the original job or supplies.
-->

- Compatibility: the mod now targets Project Zomboid Build 42.22 only and no longer loads on 42.21 or older.

- Creator: tick **Companion** or **Spouse** on a roster card, vanilla-checkbox style, or find the marked under the **Spouses & Companions** row. Companions stop at your Companion Limit and only one spouse is allowed - a refusal pops up centered naming the rule, while unticking seeds that person into the world instead. Default groups generate with unique names and varied looks and kits; outfits, weapons and packs offer vanilla and modded items alike, dropping anything the running game cannot build; duplicate names on an old file load once, not twice. A Viewpoint target card names the survivor under the crosshair and opens the talk panel on click.

- Creator: the "create a person or group" chooser now offers the behaviours and a blank group only, not the shipped town and service starting rosters.

- Companions: equipping gear inside a managed pack no longer fails with "interaction ended" once the short conversation lease lapses.
- Combat: companions answer zombies that are attacking them even during the post-flee disengage window, instead of standing still among them.

- Missions: the world map offers the crew destination again even with the optional legacy command menus off (their default).
- Conversation: a survivor finishing a work step says so instead of failing generically, and the refused line is retried automatically.

- Conversation: talking to a survivor who is finishing a work step now says so instead of a generic failure, and the refused line or question is tried again by itself once the step ends.

- Missions: right-clicking the world map now offers the crew destination again even with the optional legacy command menus switched off (their default).

- UI: every Knox window now wears the same dark slate and green sheet, the close buttons are the vanilla white circle X again, and F opens conversation with the nearest survivor in the isometric view.

- Add the entry **in the same pass** as the player-visible change, newest
  first, under the current candidate heading.
- Player copy only: no internal file names, no evidence classes, only landed
  behavior. Behavior still native-unverified stays unannounced until a dated
  acceptance card confirms it.
- When the owner ships a build, the section under its version is the
  announcement draft.

## Commit format (when a pass commits)


```
<area>: <what a player gets>

- owners touched: KS_….lua, …
- offline: <gate names> green (fixture falsified once)
- native: unverified | verified <date, card ref>
```

One line, professional and plain. The body never hides native-unverified
state.

## Public-artifact boundary

Commit messages, changelog entries and announcement drafts describe Knox
Survivors' own work only — no other project's code, assets, sources or
comparisons. Inspiration from other mods is limited to visual/behavioral ideas
we re-implement as our own work; internal design notes keep that record, and
the Superb Survivors lineage is the one design-forerunner inspiration allowed
in prose. Per-mod compatibility naming lives in
[COMPATIBILITY.md](COMPATIBILITY.md) and player-facing integration labels.

## 0.3.0-rc1 (in development)

- Companions join the player's melee and walk into a locked target instead of standing at range.




- A survivor no longer writes off a container it could not reach in one go: a blocked doorway is retried and the room stays usable.
- Base management now wears a dark slate sheet with green accents: buttons, tab boxes, list frames and the close X all stand out from the background instead of blending into it.
- The creator no longer lists town-named rosters like Rosewood Police; police, military and fire crews are created as groups with their real behaviour instead.
- The companion inventory menu (Saw Logs, Give to Companion) now reads from translation tables, with first-pass Spanish and German available.
- Companions climb ladders and sheet ropes to follow you between floors, and pry locked doors and windows with a crowbar before smashing them.
- Awaiting native verification: a resident sorting or preparing beds leaves a player-protected item where it is, with a named reason, instead of carrying it into storage.
- Awaiting native verification: a resident whose bed is picked up or scrapped is offered a free bed in the base again, and anyone left without one is named instead of quietly losing their bed.
- Awaiting native verification: the home's bed list stops crediting a resident with a bed that was picked up or scrapped, so the count of residents without a bed matches what is actually standing.

- Awaiting native verification: a resident with no bed sleeps in an absent neighbour's bed
- Awaiting native verification: a resident with no bed sleeps in an absent neighbour's bed, and leaves it alone with a named reason while the neighbour is home.

- Awaiting native verification: a cook fetches a stored ingredient from across the base
- Awaiting native verification: a cook fetches a stored ingredient from across the base and returns to the stove instead of abandoning the order at the first obstacle.

- Awaiting native verification: a group member stopped by terrain waits out its retry
- Awaiting native verification: a group member stopped by terrain waits out its retry and then walks on, instead of repeating the same failed step.

- Awaiting native verification: a group that joined up in the field keeps following its leader
- Awaiting native verification: a group that joined up in the field keeps following its leader after he claims a base, instead of splitting up and running indoors.

- Awaiting native verification: if a recipe needs an ingredient the settlement will not release from storage, the resident says so and stops instead of taking a substitute or leaving a task half-claimed; a permitted alternative the recipe itself selects is used when available.
- Awaiting native verification: qualified residents walk to a distant base store for a recipe-selected ingredient, take it only once they arrive, and return to the work surface before sewing.
- Awaiting native verification: qualified residents can fetch the recipe-selected ingredients from nearby base storage before sewing a sleeping bag, respecting storage filters and actual item transfers.

- Awaiting native verification: danger no longer makes residents repeat an already finished sleeping-bag craft or placement; unfinished preparation remains available to resume.

- Awaiting native verification: residents walk to sleeping bags elsewhere on the same loaded base floor before collecting them; access and item position are checked again on arrival.

- Awaiting native verification: residents collect nearby sleeping bags left on their base floor and continue unpacking and placing them, respecting capacity and access rules.

- Awaiting native verification: residents can retrieve a sleeping bag from their backpack or nearby base storage, unpack it, and place it inside the base. Beds are assigned only after the furniture actually exists.

- Awaiting native verification: a qualified resident with the real materials and a usable surface can sew a sleeping bag for a measured settlement bed shortage; existing bags prevent duplicate crafting. The packed bag still needs unpacking and placement.

- Awaiting native verification: scavenging pairs collect the combined materials needed by queued jobs and share usable tools, using the same stock checks as individual runners.

- Awaiting native verification: automatic scavenging pairs respect scheduled sleep and recreation and leave a resident scheduled for duty at home. Trips already underway keep their normal return rules.

- Awaiting native verification: solo survivors whose needs are met can approach a group leader they actually spot; normal social rules decide whether they join, while independent survivors keep their choice to remain alone.

- Awaiting native verification: wood, material, clothing, ammunition and fuel trips retain their purpose and destination in the same durable intent record as other supply runs.

- Awaiting native verification: NPC settlements report when residents still lack beds, without repeating an unchanged shortage or pretending beds were made.

- Awaiting native verification: automatic supply work respects scheduled sleep and recreation; residents check the base alarm before settling into scheduled sleep.

- Awaiting native verification: tired or winded residents can sit and muse; greetings, agreement, refusals and warnings gesture only when their spoken line is accepted.

- Awaiting native verification: send a gather or scavenging crew from the base roster, choosing a nearby destination, mission and residents without opening the map.

- Awaiting native verification: NPC settlements stagger sleep and work shifts instead of sharing one clock; player-written schedules stay yours.

- Awaiting native verification: queued base jobs ask supply runners for the exact missing material or usable tool, and a specific-item fetch searches for the item you named.

- Awaiting native verification: squad members keep following their leader through long walks without idle choices interrupting a formation route; reaching their slot releases them to ordinary work.

- Awaiting native verification, source-only after the frozen M-1 install:
  a full pack during pantry food retrieval now hands off to safe surplus
  stowage at home; food inside a pantry bag is checked through its live cupboard
  before pickup. An unfinished pickup never counts as a meal.

- Awaiting native verification: Survivor Melee Strength offers Weakling, Normal,
  Strong and SUPER STRONG. It scales ordinary survivor weapon hits against
  zombies and other survivors; Normal keeps current damage, and damage to or
  from your character is unchanged. Firearms, shoves and stomps are unaffected.

- Awaiting native verification: a survivor with an unsplinted fracture and a splint in a bag now brings it to hand and splints; a hand-held splint still goes straight to treatment, and a full pack follows the existing base-only capacity recovery.


- Awaiting native verification: a survivor with an exposed wound and a disinfectant in a bag now brings it to hand and disinfects; a hand-held disinfectant still goes straight to treatment, and a full pack follows the existing base-only capacity recovery.


- Awaiting native verification: a survivor carrying a bandage in a bag now brings it to hand and keeps the wounded body part with it before treatment; a full pack still stows safe surplus at the base first, and no owned destination still means refusal and no drop.

- Awaiting native verification: a survivor carrying a bandage in a bag whose pack is full now stows safe surplus at their base and then treats the wound, instead of retrying a transfer that can never fit.

- Awaiting native verification: taking supplies from an NPC faction base now earns one warning before the group turns hostile; a second theft by the same player from the same group turns them hostile.

- Awaiting native verification: a survivor carrying a meal or a bottle in a bag whose pack is full now stows safe surplus at their base and then eats or drinks, instead of retrying a transfer that can never fit.

- Awaiting native verification: a survivor whose pack is too full to drink at a base tap now stows safe surplus in a nearby owned container and then drinks; with no owned place to put it they say they cannot drink and drop nothing.

- Awaiting native verification: survivors can try another food store or water source after a failed route, while explicit orders keep their existing retry rules.

- Awaiting native verification: after a failed food or water pickup, survivors can try another eligible store before retrying the failed source.

- Awaiting native verification: independent survivors stuck in a traversal state on confirmed unloaded terrain can rejoin the saved offscreen lifecycle after its existing grace period.

- Awaiting native verification: returning survivors wait for their actual saved or travelled tile to become safe instead of being shifted to a nearby spawn point.

- Awaiting native verification: residents prefer powered refrigeration for perishable deposits when storage filters and player priorities are equal; frozen food favors a freezer, with ordinary storage retained as fallback.

- Awaiting native verification: corpse-handling crews can recognize the visible body of a known survivor when starting to collect it.

- Awaiting native verification: an NPC can give one short outcome line when its actual current zombie target dies in sight, without changing player defense credit.

- Awaiting native verification: living witnesses can react by name when they actually see a person their owner already knew die.

- Awaiting native verification: patrols distinguish an actually visible zombie from nearby unseen pressure, with short anonymous recognition in the survivor's own voice.

- Awaiting native verification: patrols can call out the actual name of a visible person the owner already knows, while retaining ordinary repeat reports.

- Awaiting native verification: zombie encounters use short combat-entry lines matched to the survivor's personality, including masked curses, without adding extra speech cues.

- Awaiting native verification: friendly survivors can greet a visible player as a first meeting or a familiar face, and conversation timing no longer mixes world hours with patrol speech ticks.

- Awaiting native verification: the developer spectator browser uses the shared window layout correctly when opened.

- Awaiting native verification: survivors can resume combat when a doorway they were waiting behind becomes clear, even across different rooms.

- Awaiting native verification: survivors stop their approach movement before attacking, and short defensive backsteps give way when the next attack is ready.

- Awaiting native verification: the Survival Guide presents one clear page per system — recruiting, setting up a base, beds, storage and hauling, orders and jobs, autonomy, threats and factions — with grounded control names and an updated one-time notice.

- Awaiting native verification: patrolling survivors react to a visible living stranger in their own voice, remember recent first-contact lines and retain regular patrol warnings.

- Awaiting native verification: ready armed survivors at melee reach can request a swing without the firearm-style aiming delay.

- Awaiting native verification: group followers first try the entrance their leader actually used, subject to their own safe-entry permissions.

- Awaiting native verification: idle residents collect loose base stock into suitable storage or Drop Points, keeping loaded bags intact and yielding to needs and orders; bag contents count toward floor stock.

- Awaiting native verification: survivors follow the game’s fracture rules when choosing splints and refuse head or torso casts while still reporting the injury.

- Awaiting native verification: applying splints or stitches can earn the same care standing and personal response as bandaging, after the required materials are used.

- Awaiting native verification: residents can walk carried stock to a Drop Point and set it down there; changed or unavailable yards retain the item for a later attempt.

- Awaiting native verification: treating a survivor with bandages or disinfectant can earn standing and a personal thank-you, with a cooldown between rewards.

Staging checkpoint — 2026-11-07: this increment is now installed locally and in the Workshop payload with 173-file parity. The proposal's earlier source-only/install wording below records its draft-time state; native acceptance and announcement approval remain pending.

### 0.3.0 release-notes proposal — 2026-11-08 — owner approval and native acceptance pending

This is review copy only, assembled from landed source changes. These sentences
remain unannounced until their corresponding M-1 results are recorded. The
2026-11-07 proposals below remain dated history; this proposal is the current
combined review copy. Candidate metadata remains `0.3.0-rc1`.

Proposed opening:

"Knox Survivors 0.3.0 brings together companion, settlement and everyday survival
repairs for single-player Build 42.21. Survivors have clearer interactions,
more coherent shared entrances and improved access to the supplies they carry."

Proposed player-facing bullets, each awaiting its own native acceptance:

- Choose Weakling, Normal, Strong or SUPER STRONG survivor melee strength.
  Normal keeps current damage; damage to and from your character stays unchanged.

- Survivors retrieve bagged bandages, disinfectant and splints before treating
  themselves. When their pack is full at home, they can stow safe surplus in
  owned storage before treatment, eating or drinking. Without a suitable place
  to stow it, they refuse and keep their property.
- Food and water searches can try another eligible source after a failed route
  or pickup. Perishable deposits prefer powered cold storage when filters and
  player priorities are equal; frozen food prefers a freezer.
- Group followers try the entrance their leader used. Close combat stops
  approach movement before attacking, bounds defensive backsteps and can resume
  when a waiting doorway clears.
- Talk and person targeting, group recruitment and settlement capacity have
  received repairs. Residents can share carried meals and supplies, clean with
  carried equipment, and haul loose stock to storage or Drop Points.
- Completed wound care can earn standing and a personal response. Residents
  can voice their own needs when other residents belong to their home.
- Known people and visible threats receive recognition and short combat lines.
  Groups stay out of the world list until a real meeting or observer report.
- Taking supplies from an NPC faction base earns one warning before repeat
  theft by the same player turns that group hostile.
- The Survival Guide has eight system chapters. Survivor restoration retains
  the saved or travelled location until it is safe to materialize.

Review limits: the newer source repairs are not installed. Native combat,
needs consumption, transfer, speech, UI and save/reload acceptance remains open.
This draft claims no stand-off/keep-up fix, noise investigation, preservation
transfer/eat-from-base, generator activation/repair, creator grouping, farmstead
or livestock runtime. Strength covers ordinary weapon HP damage; the separate
already-processed hit route remains outside verified coverage. No version bump,
public announcement or Workshop upload is implied.

### Current release-copy proposal — 2026-11-07 recognition/outcome increment — owner approval pending

All new behavior awaits native verification. Proposed addition to the earlier
candidate's release copy:
“Your patrols can call out people you already know and distinguish visible
zombies from nearby unseen pressure. Living witnesses can react by name to a
known person's death, and corpse-handling crews can recognize a known body when
starting to collect it. Zombie encounters have short personality-matched entry
and outcome lines, with masked curses.”

These source changes and the earlier movement, doorway, care, hauling, guide and
spectator repairs are packaged candidates, not native acceptance. Installed
copies remain at the earlier developer-spectator stage. Later reanimated-person
identity, noise-investigation behavior and the base-choice prompt are not
claimed. Native body/metadata/save, sight/speech, combat and performance cards
remain open; the existing debug status has evidence fields for that work rather
than a new hearing model. Metadata and description remain unchanged. Final
wording, staging, announcement and upload remain owner decisions.

### Prior five-pass proposal — 2026-11-07 — superseded above

All new behavior awaits native verification. Proposed combined wording:
“This candidate improves first-person person targeting, group recruitment and
settlement capacity. Residents tend wounds, share meals and supplies, clean with
carried equipment and haul loose stock into suitable storage or Drop Points.
Completed care can earn standing and a personal response. Followers first try
their leader's entrance, stop approach movement before attacking, end backsteps
with recovery and resume combat when a waiting doorway clears. Patrols react
to visible strangers, friendly Talk distinguishes first and known meetings,
and conversation timing stays consistent with patrol speech. Zombie encounters
gain short personality-led combat-entry lines with masked curses. The Survival
Guide is organized by system, and developer testing has a spectator-browser
opening repair.”

The current installed candidate includes the earlier content and developer
spectator, but **predates the five new source passes**. The new package is not
installed. Native damage/animation/doorway behavior, speech/sight, spectator
operation, save/reload and performance remain unverified. R2b, R3 and later
strike/outcome barks are not claimed. Follow keep-up design, StartAction capture
and other board cards remain open; retreat stays off. Keep the current candidate
metadata/description pending owner review; no public announcement or upload is
implied. Review artifact: `build/live-combat-handoff-20261107/release-copy-proposal.md`.

### Prior live-test repair-copy proposal — 2026-11-07 — superseded above

All new behavior below awaits native verification. Proposed addition to the
combined update copy: “Survivors stop their approach movement before a close
attack, keep defensive backsteps inside their recovery time, and resume combat
when a doorway they were waiting behind clears. The developer spectator browser
also has an opening-error repair.” These describe source changes, not native
acceptance. Existing recruitment, care, hauling, guide and recognition content
remains in the combined update; the current installed candidate already carries
those earlier passes plus the developer spectator. These three new repairs are
source/package-only and need a future owner-authorized stage.

**R2a draft addition (same date, awaiting native verification):** “Friendly
survivors can distinguish a first visible meeting from a familiar player, while
conversation and patrol speech share consistent timing.” This pass is also
source/package-only; the installed candidate is unchanged.

Known opens: native combat damage/animation and doorway continuation; follow
keep-up cover/contact design; spectator UI/streaming/restore smoke; StartAction
NPE capture and the board's other M-1 cards. Retreat stays off. Metadata,
description, announcement and Workshop upload remain owner decisions. An
unannounced review copy is retained in
`build/live-combat-handoff-20261107/release-copy-proposal.md`.

### Prior combined release-copy proposal — 2026-11-07 — superseded above

Proposed combined wording, all new behavior awaiting native verification:
“Survivors gain improved first-person interaction targeting, group recruitment
and settlement promotion. Residents tend wounds, share meals and supplies,
clean blood and grime with carried equipment, and bring loose stock to suitable
storage or Drop Points while keeping loaded bags intact. Completed wound care
can earn standing and a personal response. Group followers first try the entrance their leader used, and ready armed survivors can schedule a close melee swing without firearm-style aim settling. Patrolling survivors can react to a visible stranger in their own voice.”

The earlier seven passes are installed candidates; S3a hauling, shared group entry and contact scheduling are newer source
and needs a future authorized stage. Native smoke/save/performance acceptance
and the known inventory error remain open. Other treatment producers and the
voice/society increment are excluded. No metadata/version/announcement decision
is implied. Earlier draft paragraphs below are dated proposals, superseded by
this consolidated wording for the owner's single review.

### Prior drain copy proposal — 2026-11-07 — owner approval pending

The current workspace package additionally contains splint/stitch care standing
and native fracture eligibility. Proposed addition: “Completed wound treatment
can earn a personal response and standing; survivors choose casts using the
game’s injury rules.” These remain candidate changes awaiting native testing.
The seven-pass source/package receipt is on WORK_QUEUE; installed copies and
release metadata were not changed. Earlier draft wording is retained as dated
history and requires consolidation by the owner before announcement.

### Release-copy addendum proposal — 2026-11-07 — owner approval pending

The D1 workspace package also contains surface cleaning, native loose-stock
reads, costed bandage/disinfect standing and carried-stock Drop Point placement.
Proposed wording: “Residents can clean blood and grime with carried supplies,
bring surplus to Drop Points, and respond to completed wound care.” These are
candidate changes awaiting native testing, not an acceptance or announcement.
No description/version metadata is changed. CS2a will supersede this package.

### Release-copy draft — 2026-11-07 — owner approval pending

Proposed scope: the 171-file candidate plus the pending crosshair repair after
staging and smoke testing. Unbuilt hygiene/storage work is excluded. No version,
mod.info description or Workshop description has been changed or approved.

> This candidate update revises survivor interaction targeting in first person,
> group recruitment and settlement promotion. Residents have improved self-care,
> shared meals and supply sharing, while storage gains container priorities and
> the Drop Point area. Door-follow recovery, clean-water selection and repairs
> to badly damaged structures also receive attention. Testing continues; please
> report interaction, inventory or survivor-behavior problems you encounter.

### Awaiting native acceptance — unannounced source changes, 2026-11-06

- A survivor fetching ingredients for a bed walks to storage on another floor of the same house, carries the item back to the crafting surface, and refuses by name when that floor cannot be reached.
- Interrupted cleaning releases the current action so other queued work can
  continue, without spending cleaner or changing equipment after cancellation.

- Floor stock reads actual loose items; unavailable stock or tiles are no longer
  treated as an empty Drop Point with room to spare.

- Residents can clean blood and grime with their carried tools and cleaning
  liquid, retrieving and equipping supplies first and yielding to urgent needs.

- Revised first-person target handling checks every supported survivor field and
  retains the nearby-square fallback when a descriptor cannot identify a person.

- A group with a looter or solo background can become a faction after an
  explicit home choice and a properly supported group home; roaming and
  independent choices stay as chosen.

- Nearby residents can eat together using their own bagged food, retrieving it
  before eating and releasing the meal safely when interrupted.

- The notebook handles survivors holding ordinary items without trying to read
  them as guns; unreadable ammunition stays unknown.

- A survivor carrying spare food may hand it to a nearby resident who is hungry,
  keeping their own meal first; rotten or unsafe food is never offered, and the
  giver says why.

- A survivor answers from what has actually passed between you: remembered help
  makes the reply warmer, remembered quarrels make it guarded, and an even or
  missing history answers exactly as it did before.

- The stockpile area is now called **Drop Point** and takes any item, with
  heavy or large loads going there ahead of a shelf.

- A resident who cannot reach a job, a shelf or a door says so in one line
  ("I can't get through, take a look.") instead of printing a cancel notice;
  a missing material still reads as a notice.

- Nearby off-duty base residents can sit down together, eat food they carry and exchange a few words after both have eaten.

- Groups joining a faction now stay together when there is room; a refused or interrupted promotion no longer leaves only part of the group enrolled.

- Settlements use discovered beds more consistently when considering new members and outposts.

- Survivors only move into a household that has a bed, food and water to spare, and a second outpost is founded only once the base they live in has filled up.
- Residents now repair a door, wall or barricade that is nearly destroyed instead of walking past it.

- A household travelling together can be recruited as one, instead of you asking each of them in turn.

- Survivors fill up at the clean tap in a base instead of the tainted barrel beside it.

- Survivors splint their own broken limb when they carry a splint, instead of waiting for someone else to do it.

- Followers open the door they are stuck at and come in, and a new Require Close Contact option (off by default) lets you order a survivor from across the room while companions always know where you are.

- Residents go to the bed they were assigned
, sleep there, and wake at the hour their own fatigue planned; the bed menu refuses chairs and offers a way out of an assignment that is no longer a bed.

- A trained survivor names the worst injury in the group and who is treated first, in their own voice.



- Survivors stop outdoor base work while soaked, cold or overheating, and the job waits.


- Survivors splint a companion's broken limb when someone carries a splint.


- Survivors change a companion's spent bandage instead of leaving it on.


- Survivors carrying disinfectant but no bandage now treat a companion's open wound instead of walking past it.

- Travelling group members can offer a spare cigarette to someone who wants one.

- Survivors recheck their wounds and remove dressings after the wounds heal.

- Survivors keep treating the same wound while changing a dirty dressing.

- Followers keep a short commitment to their route when formation positions shift behind them.

- Survivors with a reason to enter can try quieter entrances before forcing a selected door or window.

- Followers choose a fence on the way to their destination when recovering from a blocked route.

- Let groups and companions try permitted alternate entrances, with regrouping aimed at the missing member.
- Keep window detours out of combat, including danger that appears after choosing the entrance.
- Queue a fence climb only after finding a valid approach.
- Read and edit main inventory and backpack contents directly on the creator's Gear page.
- Give the creator warmer colours and equipment columns that adapt to text size.
- Refuse extra supplies when adding them would discard another saved item.
- Show the selected primary weapon in the creator preview, with one model for a two-handed weapon.
- Add belt, holster, eyewear, socks and neckwear choices to Gear.
- Clear stale off-hand equipment when a survivor starts with a one-handed weapon.

These source entries await the live board's ([ROADMAP.md](ROADMAP.md)) dated native acceptance card before announcement.

### Since the last Workshop build

*(nothing logged yet — the first player-visible change starts this list)*

Entry template, one behavior per bullet:

- *<what the player now experiences> — keep it one clear sentence; the "why"
  goes in only when it is not the feature itself.*
