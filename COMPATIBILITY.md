# Compatibility - other survivor and NPC mods

## Build-42.22.2 gate — 2026-11-10 (owner word)

Steam stable went 42.22.2 on 2026-11-09; both Knox mods had declared
`versionMax=42.21`, which the mod selector treats as incompatible. The ceiling
was raised to `42.99` in eight live`mod.info`copies (Knox Survivors repo ×2,
local, Workshop; KnoxDrugzz / `ZomboidDrugzz` repo ×2, local, Workshop) plus
the staged candidate copy; `knox-parity.sh` re-verified **PARITY OK (173
files)**. Backups: `build/staging-preservation/mod-info-version-bump-20261110/`
and KnoxDrugzz `maintenance/staging-backups/20261110-001141-version-bump/`.
Manifest field only — no gameplay source changed; the payload jar itself had
already been re-pinned to the installed 42.22.2 build by the 2026-11-09 23:47
staging. Native acceptance of 42.22.2 engine behavior remains unverified and
belongs to the next owner session.

**Correction 2026-11-10, later same day (owner word "any max version"):** the ceiling was
then removed entirely — every Knox manifest now declares only `versionMin`, matching how
working third-party mods ship. The four per-build `42\mod.info` copies (which had kept the
old 42.21 ceilings and caused the red flag the owner screenshotted) were fixed in the same
pass; `knox-parity.sh` re-verified **PARITY OK (173 files)**.

## Source correction - 2026-11-05

Supersedes the old order and Bandits "not started" wording below: **Bandits first,
A-Life later**, per owner direction. The existing threat classifier now reads the
installed Bandit marker and public Bandit.IsHostile predicate. Neutral and unknown
Bandits are excluded from ordinary zombie acquisition and current-target
retention. Hostile Bandits still enter the ordinary threat gates. No external
brain, allegiance or registry is written. This is a one-way conservative guard,
not full compatibility: reciprocal targeting, pressure scans, faction diplomacy,
loot ownership and native combat need paired-mod testing.

Installed source: `3268487204/mods/Bandits/42.21/media/lua/shared/Bandit.lua:600`
and client `BanditZombie.lua` marker checks. Kahlua `bandit_disposition` drives
the actual classifier, acquisition and retention functions. A-Life's code/assets
are not used. The earlier table is the dated pre-repair record.

KnoxDrugzz 2.6.2's OnConsume is not a complete NPC integration: its effect tick
currently enumerates active/online players. An NPC-only consume hook would leave
effect duration/cleanup wrong. No empty sandbox toggle or copied drug simulation
is added. A public per-character effect update plus persistence/time contract is
needed before implementing optional autonomous drug use. Native integration is
unverified and remains planned.

Status: **record only, 2026-11-04.** Nothing in this file is a native test. It
says what exists, what was inspected, and what a real integration would still
need. A claim here never promotes a mod to "supported".

## What Knox Survivors is

A Lua payload plus a Java runtime. The runtime is one of `KnoxBridge` or a
compatible `ZombieBuddy` build (`KS_JavaBridge.lua`), and `workshop/description.bbcode`
already tells players that other Java mods do not become compatible on their own:
their authors have to support the chosen runtime. The same is true in reverse -
another mod's NPCs are not automatically friendly to our survivors just because
both mods are installed.

## Current state, per mod

Inspected on this machine under
`C:/Program Files (x86)/Steam/steamapps/workshop/content/108600/`:

| Order | Mod | Installed copy found | What is true today | Status |
| --- | --- | --- | --- | --- |
| 1 | Project A-Life NPCs | `3803984183/mods/ProjectALifeNPCs` (42.20) | Both mods load; nothing in our payload recognises an A-Life NPC as a friendly, and nothing in A-Life knows about a Knox survivor. Their bodies are not in `KnoxSurvivorRuntime`, so our threat scan never sees them as companions of the player. | **WIP - not started** |
| 2 | Bandits | `3268487204/mods/Bandits` (42.20 and 42.21) | Same as above. A Bandit body is only reachable to our scan through the ordinary zombie list or the human-hostility gate, which is exactly the path that could make our people swing at somebody else's friendly. | **WIP - not started** |
| 3 | Stay With Me | not found | No `mod.info` under the Workshop content root named or describing "Stay With Me" during this pass, so its API and even its presence are unconfirmed. | **Unknown - cannot claim anything** |

"Not started" is deliberate wording. No shim, registry or patch file for any of
these exists in this tree. Reading a mod's folder is not reading its API: this
pass listed their files and grepped their class and predicate names, and nothing
more.

Two facts from that shallow read matter for the risk below:

- Bandits' client Lua references a `BanditZombie` body class (62 occurrences) and
  an `isBandit` predicate (10 occurrences), so its people are spawned as
  zombie-class bodies. Our threat scan walks `cell:getZombieList()` and evaluates
  every entry as a zombie, which means a neutral Bandit is reachable to our
  survivors through exactly the path that has no friendliness question in it.
- A-Life keeps its relations in `ProjectALife/Combat/ALifeHordeRelations.lua` and
  works with `IsoPlayer`-shaped bodies. That file name is the record an
  integration would read; its contents were not read in this pass.

## Why the risk is real

Our survivors pick targets in one place, `Controller:evaluateThreat`:

- every body in `cell:getZombieList()` is evaluated as a zombie;
- bodies registered in `KnoxSurvivorRuntime` are evaluated as our people;
- players are evaluated through `KnoxHumanCombatRelations`.

A foreign NPC that another mod spawns as a zombie-like body has no marker we
read, so "friendly" is not a concept our scan can hold. Conversely, our
companions are `IsoPlayer`-shaped bodies with no marker another mod reads, so
their NPCs have the same problem pointing back at us. Any fix has to answer that
one question on both sides: *is this body somebody's friend?*

## What an integration needs, in order

**1. Project A-Life NPCs.** A-Life already keeps its own population records. A
first integration should read, not write:

- a read-only predicate that answers whether a body belongs to an A-Life group
  that is currently neutral or friendly to the player;
- the same predicate for a body that is currently hostile, so our people treat a
  hostile A-Life NPC as a threat rather than as scenery;
- a place to subscribe to that answer changing (peace, recruitment, faction
  flip) so a target is dropped through the existing `shouldDropCombatTarget`
  path instead of a second hostility store.

**2. Bandits.** The same shape, with Bandits' own faction answers. Bandits should
be the one to say "this bandit is currently raiding this player", because it owns
that record; our side then only has to consult it. Nothing should be inferred
from body class, because a raider and a neutral bandit are the same class.

**3. Stay With Me.** Cannot be scoped until its presence and API are confirmed.
Its stated behaviour (followers that stay with the player) overlaps our own
follow owner, so the first question is not "how do we mark them friendly" but
"who owns the follow order for a body both mods could drive", which is a design
decision, not a patch.

## Rules any of these integrations must keep

- No second hostility table: an answer comes from the mod that owns the record,
  and our existing gates (`hostileHuman`, leash, line of sight, distance) still
  decide whether a fight can happen.
- No body-class guessing: two bandits, one raiding and one trading, are the same
  class. Only a record may separate them.
- No write into another mod's state from our payload. We read; they own.
- A missing mod, a missing function or an error must leave today's behaviour
  exactly as it is, with one line in the log and no spam.
- Nothing here is accepted until a native session with both mods loaded shows
  our survivors and theirs refusing to fight while their records say friendly,
  and fighting when they say hostile.
