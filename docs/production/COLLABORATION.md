<!-- modforge-doc
authority: canonical
load: on-demand
purpose: canonical private collaboration ledger
-->

# Knox Survivors — collaboration and external-work ledger

Updated: 2026-09-28

This is the private production ledger for translators, compatibility partners, external mod authors, donated assets/work, permissions, and joint work. Public credits should be derived from confirmed records here, not from memory or an old chat.

## Rules

- Record the person's/project's preferred public name exactly.
- Record what they contributed and whether it is code, translation, testing, compatibility help, art/audio, research, or advice.
- Record permission/license boundaries when files or code are exchanged.
- Never imply contributor status merely because another project was used as a reference or compatibility target.
- Keep unauthorized forks/reuploads separate from collaboration records.
- Translation ownership/maintenance should identify language, current maintainer, source, and whether it is official or community-maintained.
- Before a public release, reconcile this file with player-facing credits/Workshop text.
- Keep one person/project record per collaborator. Append conversation and work updates to that record instead of creating a new note for every message.
- Store only the contact reference needed to identify the collaboration. Do not copy private addresses, tokens, or unrelated personal information into the repository.
- A conversation is not an approval. Record proposed work, confirmed permission, delivered files, review state, and public-credit wording separately.

## Confirmed project ownership

| Name | Role | Scope | Public credit status |
|---|---|---|---|
| .exe | Creator / project owner | Original Knox Survivors code, framework, direction and release ownership | Confirmed |

## Runtime / dependency relationships

| Project | Relationship | Notes | Contribution claim |
|---|---|---|---|
| Project Zomboid / The Indie Stone | Base game / engine | Knox targets Project Zomboid Build 42 and uses native game systems/assets under the game's normal modding context | Not a Knox contributor |
| external Java runtime | Historical Java-runtime interoperability reference | Not bundled or required by the current KnoxBridge candidate; modules that use other Java runtimes need an explicit KnoxBridge port | Reference only; do not imply authorship of Knox |
| Superb Survivors | Concept inspiration | README explicitly identifies inspiration for the survivor-mod concept, not a source-code dependency | Inspiration only |

## Translators

| Language | Contributor / team | Source / fork | Official or community | Permission / notes | Public credit |
|---|---|---|---|---|---|
| PT-BR (Brazilian Portuguese) | badbhop (Allan Christian; GitHub: `badbhop`) | Standalone injector: `badbhop/KnoxSurvivors_PTBR` (v1.0 zip); fork/PR to `exe-create/KnoxSurvivors` | Community standalone now; official integration only after owner review/merge | Standalone must disclose unofficial status (recorded in its README); no mod source merged; owner performs native `getText()` integration | Approved — `badbhop (Allan Christian)`, PT-BR localization contributor |

### COLLAB-PTBR — badbhop (Allan Christian, PT-BR translator)

- Contact reference: Discord `babhop`; GitHub `badbhop`; standalone repo `badbhop/KnoxSurvivors_PTBR`
- Relationship: translator
- Project or language: Brazilian Portuguese localization of Knox Survivors UI
- Started: 2026-09-24
- Current status: active
- Official or community work: community standalone (Phase 1 injector); official native integration deferred to Phase 2 after owner review/merge
- Permission/license boundary: owner approved the standalone community addon with explicit unofficial-status disclosure; owner performs all main-mod edits; translator owns Portuguese strings and testing. No main-mod source merged as of 2026-09-28.
- Public credit wording: approved — `badbhop (Allan Christian)`, PT-BR localization contributor; native integration remains pending owner review and merge
- Canonical tasks/bugs: none (localization support work is owner-side future scope; hardcoded-string reports arrive via the pending-items catalog, not `BUGS.md`)
- Files/package location: `KS_PTBR_Injetor.lua` + `sandbox.json` (v1.0 zip at the standalone repo, verified 2026-09-28: repo live with README carrying the temporary-project disclaimer, Issues channel open with 0 issues, 4 commits; install targets Workshop content `108600/3749727604`); pending-items reports per component folder with `.txt` + screenshots/clips; overflow list `KS_Text_Overflow_PTBR.txt` expected at handoff

#### Conversation and decision log

| Date | From/To | Topic | Decision or request | Follow-up | Evidence/link |
|---|---|---|---|---|---|
| 2026-09-24 | collaborator → owner | Offer to translate to PT-BR; first-day injector results | Owner welcomed the work; agreed mix: standalone addon now, official integration later | Translator keeps building injector | First Drive folder with screenshots/files |
| 2026-09-24 | owner → collaborator | Direction confirmation | Standalone addon continues independently; long-term official PT-BR in-mod; translator owns strings/testing, owner refactors for localization support; credit for PT-BR work confirmed in principle | Both continue in parallel | Message record |
| 2026-09-24 | collaborator → owner | Method: monkey-patch injector; vanilla-aligned PT-BR terms | Accepted; specific terms adjustable at official integration | Translator continues | Message record |
| 2026-09-24 | collaborator → owner | Base Manager hardcoded zone labels (8 defaults saved to persistence) | Owner verified 8 labels + persistence + notebook rendering; agreed design: stable `labelKey` stored, `getText()` at render with English fallback, one-time exact-match migration, player renames untouched, headers/tabs translated at render directly | Owner implements when ready; translator sends 8 key names + EN sources + header/tab strings in scope | Message record |
| 2026-09-24 | collaborator → owner | Layout clipping with long PT-BR strings | Noted; containers loosened once longest strings are visible; snug-in-English panels to be listed | Translator compiles overflow list | Message record |
| 2026-09-24 | owner → collaborator | AI-workflow transparency (OpenCode/Codex, budget models) | No objection; collaborator uses conversational single-model dialectic method | None | Message record |
| 2026-09-25 | collaborator → owner | Phase 1 injector / Phase 2 catalog workflow; encoding fix (Latin-1/UTF-8); Lua dir cleanup; dev-tools testing | Owner confirmed split is correct; keep injecting, catalog tricky strings, don't refactor main mod | Translator continues | Message record |
| 2026-09-26 | collaborator → owner | Base Manager 90–100%; header brand question; video clips; pending-items package format | Owner: keep `Knox Survivors` title untouched (brand identity; set via `setTitle()`); clips may be shared locally; pending-items format approved; overflow expected | Translator shares locally; sends catalog | Drive preview package + clips |
| 2026-09-26 | collaborator → owner | ES/IT/FR auto-generation after PT-BR | Deferred: lock PT-BR first; auto-generated languages need native-speaker check before official ship | Later | Message record |
| 2026-09-26 | collaborator → owner | Roadmap v1.0/v2.0/v3.0; dev options left untranslated | Accepted; dev options out of scope unless owner asks | Translator continues v2.0 | Message record |
| 2026-09-26 | collaborator → owner | Workshop on hold; GitHub zip distribution instead | Accepted; focus on clean functional translation over fighting upload tools | Translator published v1.0 zip | Standalone repo |
| 2026-09-27 | owner → collaborator | Slow replies explained; refactor in progress; fork/PR offer; disclosure restated | Translator agreed; keeps cataloging; will use fork/PR when set up | Owner sets up merge timing | Message record |
| 2026-09-28 | owner → collaborator | Fork/PR workflow: fork `exe-create/KnoxSurvivors`, branch `pt-br-dictionary-update`, PR to main; requested username, credit name, repo link; hardcoded-report format specified | Awaiting collaborator reply | Collaborator | Message record |

#### Work log

| Date | Contributor work | Knox-side work | Result/evidence | Next action |
|---|---|---|---|---|
| 2026-09-24 | Day-one injector (context menus, order catalog) + Drive files | Approach reviewed | Working, non-intrusive | Continue |
| 2026-09-25 | Encoding fix, submenu pattern matching, cache cleanup, dev-tools testing method | Confirmed | Stable coverage growing | Continue |
| 2026-09-26 | Base Manager 90–100% incl. concatenated strings; video clips; pending-items preview package | Header decision (keep title); format approved | Awaiting full catalog | Catalog + v2.0 |
| 2026-09-26 | v1.0 zip on standalone GitHub repo; translation refinements, tooltips | None required | Community-available | v2.0 + overflow list |
| 2026-09-28 | Local files reviewed by owner: v1.3 injector, 574 lines (order-catalog label wrapper, UI string-replacement tables, context-menu option patches; UTF-8 byte escapes for accents); PTBR `Sandbox.json` covers 115/117 EN keys — only `ShowLegacyContextCommands` + tooltip absent | None required | Matches claimed scope; 2 missing keys flagged for translator | v2.0 + overflow list |

#### Handoff checklist

- [x] scope and files identified (PT-BR UI; injector + sandbox.json now, Translation files + catalog later)
- [x] permission/license recorded (standalone with disclosure; owner integrates)
- [x] build/version and compatibility context recorded (current Knox version; Build 42)
- [ ] delivered files preserved or linked (v1.0 zip linked; full catalog + overflow list pending)
- [ ] review task/bug linked (none yet — create on catalog arrival if code changes needed)
- [x] public credit wording confirmed (`badbhop (Allan Christian)`, PT-BR localization contributor)
- [ ] integration/release status recorded (not integrated; community-only)

#### Joint plan (both sides may propose edits via fork PR)

Agreed 2026-09-24 through 2026-09-28. Either side may propose changes to this plan; owner approves.

**Phase 1 — Standalone coverage (badbhop leads, owner unblocked).**
- badbhop keeps extending the injector (v1.0 action layer done; v2.0 management layer next; v3.0 immersion last), testing with Sandbox dev tools, keeping zero-LUA-error stability.
- badbhop does NOT refactor main-mod code; tricky strings go to the catalog with version, location, screenshot, EN source + PT-BR proposal.
- badbhop keeps the unofficial-status disclosure in README/release notes and distributes via the GitHub zip.
- Owner does nothing blocking here; merges stay slow during the refactor, nothing on badbhop's side is blocked by that.
- Done when: management + immersion layers are covered as far as injection can reach, catalog + overflow list are complete, v1.0+ zip is public.

**Phase 2 — Native integration (owner leads, badbhop supports).**
- badbhop sends one package: Translation `.txt` dictionary, pending-items catalog per component folder, overflow list, clips/screenshots, plus GitHub username + preferred credit name + repo link.
- Owner creates one review task, then implements in order: (a) render-time `getText()` for headers/tabs; (b) `labelKey` storage + render resolution + exact-match migration for the 8 default zone labels, player renames untouched; (c) container loosening from measured longest strings; (d) `Translate/PTBR/` file from the dictionary.
- badbhop tests the integrated build and reports breakage against the same catalog format.
- Done when: PT-BR renders natively without the injector, saves migrate cleanly, credit is published in `CREDITS.md`.

**Standing rules.**
- Brand title `Knox Survivors` stays untranslated everywhere.
- Dev options stay untranslated unless the owner asks.
- ES/IT/FR only after PT-BR ships, and only with native-speaker checks.
- Either side may pause for life/work with no penalty; the record holds the state.
- Open questions: exact 8 key names + EN sources (babhop to propose); header/tab string scope list (babhop to propose); longest-string measurements (babhop to deliver); merge timing (owner to call during refactor).

### Per-collaborator record template

Use this template inside the appropriate contributor section for each real collaborator. Keep the stable identity and the running work log together.

```markdown
### COLLAB-<short-id> — <preferred public name>

- Contact reference: <platform/profile or private reference; no secrets>
- Relationship: <translator / tester / compatibility author / contributor / researcher>
- Project or language: <scope>
- Started: YYYY-MM-DD
- Current status: proposed | active | awaiting handoff | review | integrated | paused | closed
- Official or community work: <which>
- Permission/license boundary: <confirmed wording or pending>
- Public credit wording: <exact approved wording or pending>
- Canonical tasks/bugs: <KS-PROD-###, BUG-KS-###, or none>
- Files/package location: <repository path, fork, PR, or external link>

#### Conversation and decision log

| Date | From/To | Topic | Decision or request | Follow-up | Evidence/link |
|---|---|---|---|---|---|
| YYYY-MM-DD | owner / collaborator | short topic | confirmed wording, proposal, or unanswered question | person responsible | file, PR, screenshot, or message reference |

#### Work log

| Date | Contributor work | Knox-side work | Result/evidence | Next action |
|---|---|---|---|---|
| YYYY-MM-DD | files, translation, test, or report | integration/review needed | exact evidence | owner |

#### Handoff checklist

- [ ] scope and files identified
- [ ] permission/license recorded
- [ ] build/version and compatibility context recorded
- [ ] delivered files preserved or linked
- [ ] review task/bug linked
- [ ] public credit wording confirmed
- [ ] integration/release status recorded
```

For the PT-BR translator, keep the standalone injector, pending hardcoded-string catalog, overflow report, screenshots/videos, and eventual native-string handoff in one `COLLAB-*` record. Do not treat the standalone addon as official integration until the files are reviewed and merged by the project owner.

## Mod-author collaboration

_No repository-backed external co-author/contributor record is confirmed in the retained documents yet._

| Author / project | Collaboration | Files/systems affected | Permission | Status | Public credit |
|---|---|---|---|---|---|

## Compatibility work

| Project / mod | What was tested | Evidence | Status | Owner |
|---|---|---|---|---|
| external Java runtime | Knox Java runtime bootstrap / Patch API path | `docs/production/RUNTIME_AND_MIGRATION.md`, `README.md`, runtime logs/tests | Supported path; live release compatibility still follows release gates | Knox project |

## Support-scale coordination

The owner reports Knox Survivors is approaching 26,000 active users. At that scale, translation offers, compatibility help, donated work, and external-author coordination should be recorded here before implementation so permissions and public credit do not get lost in support traffic. Player reports that are not collaboration belong in `SUPPORT_AND_TRIAGE.md`.

## Incoming collaboration workflow

1. Capture request/offer in ModForge Inbox.
2. Record author/project identity and contact reference.
3. Define exact scope and permission boundary.
4. Create task(s) with owner and acceptance criteria.
5. Keep exchanged code/assets traceable to source and permission.
6. Review integration and compatibility evidence.
7. Update this ledger and `CREDITS.md` before release.

## Conversation capture

When the owner pastes a collaborator conversation, the receiving agent should:

1. identify or create the single matching collaborator record;
2. summarize only decisions, requests, promises, delivered work, risks, and unanswered questions;
3. append dated entries to the conversation/work tables;
4. link any concrete issue to the existing `BUGS.md` or `WORK_QUEUE.md` item;
5. leave vague ideas or unconfirmed claims in the conversation log rather than promoting them to project truth;
6. return a short reply draft only when the owner asks for one.

Never rewrite the entire conversation into production documentation, and never expose private contact details in a public-facing file.
