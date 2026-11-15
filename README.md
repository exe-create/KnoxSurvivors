# Knox Survivors

Knox Survivors is a single-player survivor mod for Project Zomboid Build 42.22 only (42.21 and older are no longer supported). Version `0.3.0-rc2` is a public test build; native gameplay and save/load acceptance are pending.

## Download and install

Download **KnoxSurvivors-0.3.0-rc2.zip** from [GitHub Releases](https://github.com/exe-create/KnoxSurvivors/releases/tag/v0.3.0-rc2). Extract it and follow the included **README.txt**. The ZIP contains just the `mods` folder and that README, including the compiled gameplay module. Choose the ZIP attachment under Assets; GitHub's automatic source archives are for developers.

You also need exactly one Java runtime: ZombieBuddy 2.3.4 or [KnoxBridge Runtime](https://github.com/exe-create/KnoxBridge/releases/tag/v0.1.0-alpha11). The [installation README](release/README.txt) explains setup, duplicate Workshop copies, module approval and rollback. Back up your saves and start with a disposable test save. Official release builds may be used for personal gameplay and testing; see [LICENSE.md](LICENSE.md).

## Build

This repository contains mod source in `mod/`, the Java gameplay module in `java/`, and Workshop description copy in `workshop/`. Copy `gradle.properties.example` to a private `local.properties` and set the required game/runtime paths. Run `./gradlew.bat :java:check packageUnifiedMod` to build and check the player ZIP under `build/distribution/archives/`. Run `python scripts/verify-release.py build/distribution/archives/KnoxSurvivors-0.3.0-rc2.zip` to verify its layout, versions and exact source/JAR bytes. These commands do not install or publish anything.

Use either ZombieBuddy or KnoxBridge Runtime, never both in one game process. The separate Knox Survivors Launcher is retired. Test with a disposable save and back up existing saves first.

Run `./gradlew.bat :java:check` for the offline checks. The vocabulary and five UI source guards require Bash and Python on PATH. The UI guards run as part of the normal check, including the whole-tree text, home-source and scroller rules. These checks cover compilation and offline contracts; native gameplay, save/load and performance still require testing in Project Zomboid.

## For development (agents and future contributors)

Offline Lua fixtures live in `java/fixtures/` and Java verifiers in `java/src/test/`. Runtime adapters share one gameplay JAR. `packageWorkshopCandidate` separately prepares a workspace-only Workshop layout and generated metadata; Steam publication is a separate operation. The public test ZIP contains no development tools or studio records.

## People & Factions creator

Choose **KNOX CREATOR** in the main-menu column. Choose **Create...** for a blank
Custom group, a starting template or an independent survivor example. Defaults
start hidden; show them to preview or edit their planned people and loadouts.
Edit people, appearance, equipment, traits, skills and starting policies. Hover
equipment for item details; main/backpack supplies have separate quantities. Save
the roster before starting a world. Personal definitions live in the game's
user Lua data file `KnoxSurvivors/creator.txt`, outside the mod's update folders;
keep your own backup before manual edits or downgrades. The editor retains an
existing readable previous copy and verifies writes by reading them back. If a
save fails, edits stay open; explicitly choose DISCARD to leave without saving.

Groups need a suitable real building with enough catalogue positions; larger
rosters can remain pending. Their world receipts prevent duplicate startup
spawns. Captivity/eating, coordinated robbery compliance and vehicle convoys
remain unfinished. This creator is a test candidate awaiting native UI,
equipment and save/reload checks.

## Reporting a bug

While paused, choose **Report a bug**. Fill in what happened and how to reproduce
it, then open the GitHub draft to review and submit it yourself. **Export
diagnostics** optionally saves a small file in
`Zomboid/Lua/KnoxSurvivors-diagnostics.txt`; attach it yourself if useful. The
export contains version/runtime/population information. The mod does not upload
reports or collect your saves, player names, file paths or network addresses.
Reports posted on GitHub are public. This new interface still needs native UI
and browser/export verification.

## Medical help

Owned companions and base residents have a **Medical Help** menu: ask directly,
or set **Auto Medical: On/Off**. Automatic help defaults on. They need a safe
opportunity, real carried supplies and a reachable patient; a direct request
explains a refusal. Supported aid includes uncovered bleeding wounds and
exposed-wound disinfection. Their own native medical maintenance remains active
when automatic help is off. Full injury treatment and native acceptance remain
pending.
