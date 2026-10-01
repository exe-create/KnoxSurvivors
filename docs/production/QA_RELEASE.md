<!-- modforge-doc
authority: canonical
load: always
purpose: canonical verification and release contract
-->

# Knox Survivors — QA and release contract

Updated: 2026-10-01

## Evidence levels

Use these states consistently:

1. **Planned** — described but not implemented.
2. **Implemented** — code exists; behavior not yet proven.
3. **Offline verified** — focused/unit/regression/build evidence passes.
4. **Live verified** — required behavior passed in real Project Zomboid on the target build.
5. **Release ready** — candidate-wide offline/live gates pass and no release blocker remains.

Never skip from “implemented” to “release ready.”

## QA tooling status — in-game runner retired

The in-game `KS_AutomatedQA` startup coordinator, Developer Tools submenu,
save-arming flow, and `AutomatedQAMode` Sandbox option have been retired at the
owner's request. Normal gameplay no longer loads QA scenarios or asks the owner
to prepare a disposable save. Existing Sandbox saves may retain the old key; it
is no longer registered or read.

`KS_QAManifest.lua`, `KS_AutomatedQA.lua`, the save-isolation and base-task
adapters, and the PowerShell report parser remain in the repository for direct
offline regression coverage only. They are not part of the playable runtime
path. The destructive legacy runner remains inactive.

Use ordinary Build 42 play for native acceptance and
`tools/verify.ps1 -SkipJava` for offline source/regression checks. Human playtests must name the
specific survivor action and expected result; offline tests never establish
native or release readiness.

## Current release gate

The exact Survivors source candidate `e93ed2655470212a6e78305171ccff63f7893c58` passed the full offline and native payload gates on 2026-09-29. Steam publication/download parity and live Build 42 acceptance remain open; the matching KnoxBridge alpha8 menu review gate is not yet live-verified. The public Knox Survivors Workshop item currently reports a Steam removal and still contains old Setup.cmd/option-2 instructions. GitHub's latest KnoxBridge release remains alpha5. Do not claim release parity until the existing items are updated and verified publicly.

The current worktree is dirty relative to `e93ed26` and contains later gameplay
changes. The offline and payload evidence above remains scoped to that exact
candidate; it does not verify the current dirty worktree. A fresh full exact-tree
gate including Java and candidate/payload review is required before using these
additions in a release candidate. No live Build 42 claims are implied.

On 2026-09-30, the current dirty worktree passed the Lua-only
`tools/verify.ps1 -SkipJava` gate (112 sources, 182 regression scripts, 294
checks, 0 failed) and `git diff --check`. Java/build/payload gates have not been
rerun on this dirty tree; the `e93ed26` Java/native-payload results remain
scoped to that earlier candidate.

Later, on 2026-09-30, `gradlew.bat deployDev` completed successfully for the
current worktree. All 124 files under `mod/` match the deployed local mod at
`C:\Users\Gary\Zomboid\mods\KnoxSurvivors` and the Workshop `Contents` payload;
the Workshop payload additionally contains the generated Java agent and its
checksum. The current source gate passed 113 Lua sources, 189 regression
scripts, 302 checks, 0 failures; Java was skipped. This stages the current
candidate for local testing but does not prove the game loaded it. The existing
Workshop item 3749727604 still displays Steam's removal notice, so no update was
uploaded: re-uploading cannot restore availability and must not be used to
bypass the removal. Use the staged local mod for testing; resolve the item
status through Steam Support before another Workshop publication attempt.

### Focused/offline gate

- focused tests for every release-bound changed subsystem;
- Lua syntax/regression coverage appropriate to the exact current source;
- Java build/verifiers;
- payload/staging validation;
- no unexplained regression or source-confirmed blocker.

### Required live Build 42.20.4 coverage

At minimum cover:

- companion Follow/Hold/Return/Guard/Patrol/order interruption and recovery;
- representative base jobs using real tools/materials, including claim/release cleanup;
- storage/organizer behavior with real items and reservations;
- firearms, native damage/reload and melee fallback;
- save/reload during representative active work/combat/travel;
- hibernation/rematerialization preserving identity, needs, equipment, inventory, orders, relationships and activity;
- detached-companion lifecycle across recognized vault/climb/window/fence/sheet-rope traversal, cell-edge/streaming gaps and vehicle occupancy; prolonged unexplained detachment must hibernate safely, reject detached order writes without losing the prior order, and recover through save/reload/rematerialization without duplication;
- multi-day real food/water behavior without duplicate or fabricated consumption;
- factions/groups/events enabled for the candidate, including loaded ↔ unloaded transitions;
- vehicle entry/travel only where the candidate advertises/supports it;
- Survivor Card / Notebook / inventory / health / medical UI at multiple UI scales;
- KnoxBridge startup, module allow/deny, and uninstall/restore path;
- the current KnoxBridge main-menu JAR review gate, optional remembered exact-hash choices, and no-restart behavior when the effective allowed set is unchanged;
- any direct Steam bootstrap route only after a real Steam startup acceptance.

## Quick owner playthrough

Use this short checklist after a risky change or before advancing a live gate. Use a disposable save, record the Git revision, and test one startup path at a time. Mark a step **PASS** only when the expected result is observed in the real game; otherwise record **FAIL**, preserve the save/log, and create or update the relevant bug/task.

1. **Startup path** — install KnoxBridge using the current OS instructions, launch normally through Steam with KnoxBridge as the sole Java runtime, confirm the Knox module loads, enter a disposable save, and record the runtime/build. The separate Knox Survivors Launcher is deprecated and must not be used for acceptance. Keep external Java runtime as a separate alternative and never stack runtime agents.
2. **Survivor identity** — create or recruit one survivor. Example: note the name/identity, location, equipment, and relationship, then confirm they remain the same after a save/reload.
3. **Orders and movement** — issue Follow, Hold, or Return. Example: send the survivor through a doorway or around an obstacle, interrupt with a nearby threat, and confirm the order recovers or fails visibly rather than silently hanging.
4. **Combat** — test one threat, then several. Example: confirm real damage/health changes, weapon or melee behavior, retreat/recovery, and no fabricated combat result.
5. **Items and work** — transfer a real item and assign one representative job. Example: move an item between inventory/storage, confirm reservations and consumption, then verify the job completes or reports its failure.
6. **Persistence** — save during active work, travel, or combat and reload. Example: verify identity, location, needs, equipment, inventory, order, relationship, and activity are preserved once.
7. **Time and off-screen behavior** — travel roughly 300+ tiles away and return, or advance a controlled period. Example: confirm unloaded survivors/events do not invent native outcomes and can retry failed materialization.
8. **UI and runtime boundary** — inspect the relevant Survivor Card, Notebook, inventory, health, or order UI; when runtime code changes, verify Bridge discovery, exact-hash allow/deny behavior, and that no competing instrumentation runtime is active.

For each step record only: **PASS/FAIL**, expected result, actual result, save name, runtime path, revision, and the smallest useful log excerpt. A PASS advances evidence; a FAIL becomes a reproducible bug/task; an unrun step remains **unverified**.

### Fast 20-minute pass

Use this when checking a small change or deciding whether a build is worth deeper testing:

1. Start a disposable save with one supported runtime path.
2. Create or recruit one survivor and note their identity, equipment, location, and current order.
3. Give one movement/order command, interrupt it with a safe nearby threat, and observe recovery.
4. Transfer one real item, assign one simple job, and confirm the item/job state changes correctly.
5. Save during the activity, reload, and confirm identity, location, equipment, inventory, order, and job state.
6. Travel far enough to unload the area, return, and check that no outcome was invented without the required loaded/native behavior.
7. Record PASS, FAIL, or unverified for each step before moving on.

### Owner full playthrough checklist

The long checklist for a serious playthrough while Codex is away. Setup once: disposable save,
default sandbox settings, Developer Tools + diagnostics ON, KnoxBridge as the only
Java runtime with normal Steam Play, and write down the save name and mod revision.
Work top to bottom. Tick what passes; anything else becomes a FAIL report (format below) —
you never need to diagnose, just describe what you saw. Unrun stays unticked.

**Startup and first people**
- [ ] Game loads with the mod on, no startup errors. Good = you reach the world normally.
- [ ] Living survivors exist out in the county but don't feel like an army. Good = you find some by exploring, not crowds on every corner.
- [ ] A survivor you watch keeps doing survivor things (walking, looting, resting). Good = they look busy with a purpose, not frozen or vibrating in place.

**Meeting and recruiting**
- [ ] Walk up to a survivor and Talk. Good = they stop briefly, conversation happens, then they resume what they were doing.
- [ ] Recruit one survivor. Good = a companion HUD row appears with portrait, name, health, and needs.
- [ ] Dismiss (or send home) and re-check. Good = no frozen clone left behind, no duplicate of them wandering around.

**Orders and movement**
- [ ] Order Follow and walk through a doorway. Good = they come through without long pauses or getting stuck.
- [ ] Order Follow over/through a fence. Good = they climb after you and resume quickly — no standing frozen for seconds after landing.
- [ ] Order Hold, walk away, then Follow again. Good = they stay, then rejoin; the order label always matches what they're actually doing.
- [ ] Spook them mid-order with a nearby zombie. Good = they react to danger, then go back to the order (or visibly fail it) — never silently hang.

**Combat**
- [ ] Let your companion fight ONE zombie. Good = real swinging, real health changes on someone, zombie actually dies or hurts someone.
- [ ] Throw them into a small group. Good = they fight sensibly; overwhelming odds make them run to safety instead of suiciding.
- [ ] After the fight, check their health/injuries screen. Good = wounds shown are real and treatable, nothing fake.

**Needs and health**
- [ ] Watch hunger/thirst drop over time and see them eat/drink from carried supplies. Good = real items get consumed.
- [ ] Open Medical Check on a companion and treat a real wound with a bandage. Good = vanilla treatment window, bandage consumed, wound improves.

**Storage**
- [ ] Assign a container as Food storage and another as general storage (right-click container menus).
- [ ] Give a survivor loot and watch it get deposited. Good = food lands in the food container, odd items land in general — nothing vanishes or duplicates.

**Base and jobs**
- [ ] Set up a base and assign one simple job (e.g. guard, farming, barricade) with the needed tools/materials present.
- [ ] Watch the job happen. Good = the survivor walks there, does the visible work action, and the world actually changes (or honestly reports why it can't).

**Companion UI**
- [ ] Open the Survivor Card: identity, skills, health, needs, equipment all look right and match the real survivor.
- [ ] Open the Notebook: party, base, known survivors, factions sections show true info, not stale entries.
- [ ] Watch speech bubbles/activity messages during all of the above. Good = readable, matches what's happening, doesn't block right-click menus.

**Vehicles**
- [ ] Order a companion into a car as passenger, then out. Good = clean entry/exit, no clones, no stuck seats.
- [ ] Order a drive (experimental) in a fueled running car on open ground. Good = it either drives properly or refuses with a visible reason — never freezes, teleports, or steals your controls.
- [ ] Save and reload with a companion in/near the car. Good = same people, same car, no duplicates.

**Off-screen life**
- [ ] Travel 300+ tiles away, wait a while, come back. Good = the same survivors with the same names/gear, sensibly changed (hungrier, moved) — no duplicates, no invented corpses/loot/blood.
- [ ] Leave a companion at an unloaded base and return later. Good = they're there, still themselves, still on duty.

**Save and reload (the big one)**
- [ ] Save in the middle of activity (walking, working, or fighting) and reload. Good = same identities, locations, needs, equipment, inventory, orders, relationships, and jobs. Nothing lost, nobody duplicated.

**Groups and factions out in the world**
- [ ] If you spot independent survivors or groups traveling, watch a while. Good = they move together, wait for stragglers, don't jitter or pile onto one tile.
- [ ] If you meet a hostile survivor, note what caused it. Good = hostility feels earned (you attacked, stole, or they're with enemies) — not random, not guaranteed.

**Performance and feel**
- [ ] Play at least an hour with normal population. Good = smooth game, no action spam in logs, no mass freezing, survivors feel like people rather than robots.
- [ ] If anything felt off but you can't name it, write one sentence about the moment anyway. Vague reports still help.

**When something fails**, copy this, fill it in, and send it (Discord/DM/notes — wherever we triage):
Result: FAIL / item name / what you did / what you expected / what actually happened / repeatable? / save name + revision + runtime path.

### Specific failure signals

Look for these concrete symptoms rather than trying to diagnose their cause:

- a survivor changes identity, duplicates, disappears, or returns as a different survivor;
- an order says it is active but the survivor is motionless, loops, walks to the wrong place, or never recovers after interruption;
- a survivor walks through an obstacle, cannot reach an obvious destination, or becomes permanently detached;
- combat changes no real health/body state, resolves without contact, duplicates damage, or leaves a survivor stuck in combat;
- an item appears, disappears, duplicates, transfers to the wrong container, or is consumed without a real action;
- a reservation, job, storage claim, or base assignment remains locked after cancellation, death, reload, or failure;
- save/reload loses needs, equipment, inventory, relationship, order, location, health, or job state;
- unloaded activity creates blood, smashed windows, combat history, loot, death, or terminal outcomes without valid simulation evidence;
- returning to an unloaded area creates duplicate survivors, stale shells, duplicate events, or failed materialization that cannot retry;
- the UI shows a different state from the survivor, inventory, health, or order actually observed in the world;
- launcher and external Java runtime both appear active, the wrong runtime loads, or startup reports PASS before the required bridge/patch/combat checks are real;
- performance degrades sharply, survivors spam the same action, or the game becomes unstable during ordinary population/activity levels.

### Useful report format

Send or record a failed result in this compact form:

```text
Result: FAIL
Build/revision:
Runtime path: KnoxBridge via normal Steam Play / other:
Save:
Steps: 1) ... 2) ... 3) ...
Expected:
Actual:
Repeatable: yes / no / unknown
Evidence: screenshot, timestamp, or smallest relevant log excerpt
```

Do not spend time reproducing a failure indefinitely. One clear reproduction is enough to record it; a second reproduction is useful confirmation. If it does not reproduce after two focused attempts, mark it intermittent or unverified and move to the next scenario.

## Bug conversion rule

Any failed acceptance scenario becomes a bug/task with:

- exact build/revision;
- save/setup;
- reproduction steps;
- logs/evidence;
- expected behavior;
- first confirmed failing boundary when known;
- focused regression requirement.

## Candidate evidence record

When the exact candidate passes a gate, record:

- Git commit plus whether the worktree is clean;
- exact Lua source/test counts;
- exact failed-check count;
- Java/build/package result;
- target Project Zomboid build;
- live scenarios actually completed;
- runtime path used;
- remaining experimental/not-promised systems.

Do not keep creating dated release-readiness files. Update `CURRENT_STATE.md`, this QA contract, the active work queue and public `RELEASE_NOTES.md` as evidence changes.

## Release decision

Only the project owner decides publication. AI agents may summarize evidence and blockers, but they do not publish, upload or change public promises without explicit approval.

The 2026-09-30 22:39 debug log supersedes the earlier provisional “stale local
payload” diagnosis. Build 42 actually loaded the Workshop development path
recorded in BUG-KS-053, where the QA START line was legacy and the autonomy
controller failed to register after a Kahlua 200-local compiler overflow. The
unused controller helper has now been removed and source staged to that exact
path; the fresh Debug Mode startup replay is still required. The QA arming
workflow is not accepted until current save-identity/manifest metadata appears
in a new report.

A subsequent 2026-09-30 Build 42.21 run loaded the current QA manifest v2 from
the Workshop development path but still hit the Kahlua limit after the first
reduction to 199 locals. That attempt is recorded as insufficient. The
controller now has 189 module-scope locals after moving ten tuning values to
its existing `Controller.TUNING` table; the test guards a 190 maximum. The log
also reports `saveIdentity=unavailable`, which blocks encounter QA but is a
separate issue from compilation. Both game paths now contain the current
127-file source payload. Retest fresh startup; do not claim success before the
new log confirms controller registration.


### 2026-10-01 — owner-retired in-game QA surface

The in-game runner and save-arming UI are removed from the packaged mod after
the owner reported that the workflow was confusing and not useful. QA-only Lua
modules were moved outside `mod/42/media/lua`; only the offline regression suite
loads them directly. This does not change native gameplay acceptance, which is
performed by ordinary player replays. No automated QA scenario is active in the
game.


Removal verification (2026-10-01): offline harness/menu/Sandbox regressions
passed; full verifier passed 102 packaged Lua files, 197 regression scripts,
299 checks, 0 failures. All 109 `mod/42` files hash-match local and Workshop
development staging; no QA `.lua` remains under the game-loaded client directory.
Public Workshop upload and gameplay acceptance were not performed.
