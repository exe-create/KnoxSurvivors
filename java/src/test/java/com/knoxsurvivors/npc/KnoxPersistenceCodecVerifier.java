package com.knoxsurvivors.npc;

import java.io.StringReader;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;

/** Production Lua + installed B42 table codec. No world, save folder or native actors. */
public final class KnoxPersistenceCodecVerifier {
    /** The palette lives in one place. A second copy is how windows drift apart. */
    private static void verifySinglePalette(Path root) throws Exception {
        Path clients=root.resolve("mod/42/media/lua/client");
        String[] signatures={"0.090,0.086,0.078","0.902,0.878,0.831","0.639,0.612,0.561",
            "0.62,0.62,0.60","0.600,0.576,0.529","0.500,0.480,0.443"};
        Path[] files;
        try (var walk=Files.walk(clients)) {
            files=walk.filter(path -> path.getFileName().toString().endsWith(".lua"))
                .sorted().toArray(Path[]::new);
        }
        for (Path file : files) {
            if (file.getFileName().toString().equals("KS_SurvivorUILayout.lua")) continue;
            // The creator's colours are appearance presets (hair, skin, cloth), not
            // window chrome: a grey there is a person's hair, not a panel.
            if (file.getFileName().toString().startsWith("KS_Creator")) continue;
            var lines=Files.readAllLines(file);
            for (int index=0; index<lines.size(); index++) {
                String compact=lines.get(index).replace(" ", "");
                for (String signature : signatures) {
                    if (compact.contains(signature))
                        throw new AssertionError("Duplicate palette copy in "
                            + root.relativize(file) + ":" + (index + 1)
                            + " - read UILayout.theme instead");
                }
            }
        }
    }

        /** B42's getFileWriter takes (name, create, append); two arguments throw at runtime. */
    private static void verifyFileWriterArity(Path root) throws Exception {
        Path[] files;
        try (var walk=Files.walk(root.resolve("mod/42/media/lua"))) {
            files=walk.filter(path -> path.getFileName().toString().endsWith(".lua"))
                .sorted().toArray(Path[]::new);
        }
        String call="getFileWriter(";
        for (Path file : files) {
            var lines=Files.readAllLines(file);
            for (int index=0; index<lines.size(); index++) {
                String line=lines.get(index);
                int at=line.indexOf(call);
                if (at<0) continue;
                int close=line.indexOf(")", at);
                String arguments=close<0 ? "" : line.substring(at+call.length(), close);
                long commas=arguments.chars().filter(value -> value==',').count();
                if (commas>=2) continue;
                throw new AssertionError("getFileWriter needs (name, create, append) in "
                    + root.relativize(file) + ":" + (index + 1));
            }
        }
    }

    /**
     * A fixture may only run when every global it names is really loaded. The
     * harness loads some modules by source section, so an absent global reads as
     * nil and a fixture that accommodates nil would pass while proving nothing.
     * This turns that silence into a named failure.
     */
    private static void requireGlobals(Object environment, Class<?> table, String fixture,
            String... names) throws Exception {
        for (String name : names) {
            Object value = table.getMethod("rawget", Object.class)
                .invoke(environment, name);
            if (value == null)
                throw new AssertionError(fixture + " needs global " + name
                    + ", which this harness has not loaded");
        }
    }

    public static void main(String[] args) throws Exception {
        Path root=Path.of(args[0]);
        verifySinglePalette(root);
        verifyFileWriterArity(root);
        Class<?> table=Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> platformType=Class.forName("se.krka.kahlua.vm.Platform");
        Object platform=Class.forName("se.krka.kahlua.j2se.J2SEPlatform").getConstructor().newInstance();
        Object environment=platform.getClass().getMethod("newTable").invoke(platform);
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"_G",environment);
        Class.forName("se.krka.kahlua.stdlib.BaseLib").getMethod("register",table).invoke(null,environment);
        for (String library : new String[]{"se.krka.kahlua.j2se.MathLib", "se.krka.kahlua.stdlib.StringLib",
                "se.krka.kahlua.stdlib.TableLib", "se.krka.kahlua.stdlib.OsLib",
                "se.krka.kahlua.stdlib.CoroutineLib", "se.krka.kahlua.stdlib.RandomLib"})
            Class.forName(library).getMethod("register",platformType,table).invoke(null,platform,environment);
        Object thread=Class.forName("se.krka.kahlua.vm.KahluaThread")
            .getConstructor(platformType,table).newInstance(platform,environment);
        thread.getClass().getField("debugOwnerThread").set(thread,Thread.currentThread());
        Method compile=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
            .getMethod("loadis",java.io.Reader.class,String.class,table);
        Method call=thread.getClass().getMethod("pcall",Object.class,Object[].class);
        Runner runner=new Runner(compile,call,thread,environment);
        runner.run("stdlib",Files.readString(Path.of(args[1]).resolve("stdlib.lua")));
        runner.run("setup", "require=function() return true end; data={}; "
            +"ModData={getOrCreate=function(k) data[k]=data[k] or {};return data[k] end}; "
            +"Events={OnSave={Add=function(f) savedHook=f end},OnGameStart={Add=function(f) loadedHook=f end}}; "
            +"getGameTime=function() return {getWorldAgeHours=function() return 12 end} end");
        String production=Files.readString(root.resolve("mod/42/media/lua/client/KS_Persistence.lua"));
        runner.run("KS_Persistence",production);
        runner.run("zone_display_label",Files.readString(root.resolve("java/fixtures/zone-display-label.lua")));
        String fixture=Files.readString(root.resolve("java/fixtures/companion-persistence-codec.lua"));
        String portable = sampleRecord();
        benchmarkRecordLocation(portable);
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"expectedRecord",portable);
        runner.run("seed",fixture);
        runner.run("vehicle_assignment",Files.readString(root.resolve("java/fixtures/vehicle-assignment.lua")));
        runner.run("KS_OrderCatalog",Files.readString(root.resolve("mod/42/media/lua/client/KS_OrderCatalog.lua")));
        Object uiLayoutModule=runner.run("KS_SurvivorUILayout",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorUILayout.lua")));
        table.getMethod("rawset",Object.class,Object.class)
            .invoke(environment,"KnoxSurvivorUILayout",uiLayoutModule);
        runner.run("ui_scale",Files.readString(root.resolve("java/fixtures/ui-scale.lua")));
        Object creatorModule=runner.run("KS_Creator",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_Creator.lua")));
        table.getMethod("rawset",Object.class,Object.class)
            .invoke(environment,"KnoxCreator",creatorModule);
        runner.run("creator_factions",Files.readString(root.resolve("java/fixtures/creator-factions.lua")));
        runner.run("creator_slots",Files.readString(root.resolve("java/fixtures/creator-slots.lua")));
        runner.run("creator_layout",Files.readString(root.resolve("java/fixtures/creator-layout.lua")));
        runner.run("ui_fit_text",Files.readString(root.resolve("java/fixtures/ui-fit-text.lua")));
        runner.run("viewpoint_perspective",Files.readString(root.resolve("java/fixtures/viewpoint-perspective.lua")));
        Object highlightPalette=runner.run("KS_BaseHighlights",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseHighlights.lua")));
        table.getMethod("rawset",Object.class,Object.class)
            .invoke(environment,"KnoxBaseHighlights",highlightPalette);
        runner.run("zone_colours",Files.readString(root.resolve("java/fixtures/zone-colours.lua")));
        runner.run("KS_Settings",Files.readString(root.resolve("mod/42/media/lua/client/KS_Settings.lua")));
        runner.run("sandbox_balance",Files.readString(root.resolve("java/fixtures/sandbox-balance.lua")));
        runner.run("base_roles",Files.readString(root.resolve("java/fixtures/base-roles.lua")));
        runner.run("KS_GroupScavenge",Files.readString(root.resolve("mod/42/media/lua/client/KS_GroupScavenge.lua")));
        runner.run("group_scavenge_roles",Files.readString(root.resolve("java/fixtures/group-scavenge-roles.lua")));
        runner.run("KS_Controller",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")));
        runner.run("KS_EquipmentIntelligence",Files.readString(root.resolve("mod/42/media/lua/client/KS_EquipmentIntelligence.lua")));
        runner.run("KS_CompanionVehicles",Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionVehicles.lua")));
        runner.run("KS_NpcVehicleTravel",Files.readString(root.resolve("mod/42/media/lua/client/KS_NpcVehicleTravel.lua")));
        runner.run("vehicle_swap",Files.readString(root.resolve("java/fixtures/vehicle-swap.lua")));
        runner.run("vehicle_admission",Files.readString(root.resolve("java/fixtures/vehicle-admission.lua")));
        runner.run("KS_BaseBarricades",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseBarricades.lua")));
        runner.run("entrance_invariant",Files.readString(root.resolve("java/fixtures/entrance-invariant.lua")));
        String baseMenuSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseContextMenu.lua"));
        runner.run("barricade_refusal_source","local BaseContextMenu={};"
            +section(baseMenuSource,"-- BARRICADE REFUSAL COPY (pure)","-- END BARRICADE REFUSAL COPY")
            +"codecBarricadeRefusal=BaseContextMenu;");
        runner.run("barricade_refusal_copy",Files.readString(root.resolve("java/fixtures/barricade-refusal-copy.lua")));
        runner.run("armed_defence",Files.readString(root.resolve("java/fixtures/armed-defence.lua")));
        runner.run("base_home_defense",Files.readString(root.resolve("java/fixtures/base-home-defense.lua")));
        runner.run("formation_room_boundary",Files.readString(root.resolve("java/fixtures/formation-room-boundary.lua")));
        runner.run("rest_spot_retry",Files.readString(root.resolve("java/fixtures/rest-spot-retry.lua")));
        runner.run("journey",Files.readString(root.resolve("java/fixtures/companion-journey.lua")));
        runner.run("playtest_core_recovery",Files.readString(root.resolve("java/fixtures/playtest-core-recovery.lua")));
        runner.run("all_work_interactions",Files.readString(root.resolve("java/fixtures/all-work-interactions.lua")));
        runner.run("ambient_action_recovery",Files.readString(root.resolve("java/fixtures/ambient-action-recovery.lua")));
        runner.run("base_idle_life",Files.readString(root.resolve("java/fixtures/base-idle-life.lua")));
        runner.run("idle_animation_recovery",Files.readString(root.resolve("java/fixtures/idle-animation-recovery.lua")));
        runner.run("KS_SurvivorOrigins",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorOrigins.lua")));
        runner.run("KS_SurvivorCapabilities",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorCapabilities.lua")));
        runner.run("profession_origin",Files.readString(root.resolve("java/fixtures/profession-origin.lua")));
        runner.run("stale_base_claim",Files.readString(root.resolve("java/fixtures/stale-base-claim.lua")));
        String interactionSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInteractionUI.lua"));
        runner.run("pending_attention_source", "local safeCall=pcall;local InteractionUI={};"
            +section(interactionSource,"function InteractionUI.ownsAttention", "function InteractionUI.update()")
            +"codecInteractionUI=InteractionUI");
        String tradeUiSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_TradeUI.lua"));
        runner.run("pending_trade_source","local Window={};"
            +section(tradeUiSource,"function Window:update()", "function Window:prerender()")
            +"codecTradeWindow=Window");
        String medicalSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorContextMenu.lua"));
        runner.run("medical_attention_source", "local SurvivorContextMenu={};local CONVERSATION_DISTANCE=4;"
            +"local function distanceToPlayer() return 1 end;"
            +section(medicalSource,"local function medicalMessage", "local function onMedicalCheck")
            +"codecMedicalContext=SurvivorContextMenu");
        String layoutSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorUILayout.lua"));
        runner.run("person_surface_source","local Layout={};"
            +section(layoutSource,"-- Person-bound surfaces (talk, trade, pack, card)","return Layout\n")
            +"Layout.bindInteractionWindow=function() end;"
            +"codecPersonSurface=Layout");
        runner.run("person_surface_close",Files.readString(root.resolve("java/fixtures/person-surface-close.lua")));
        String activitySource=Files.readString(root.resolve("mod/42/media/lua/client/KS_ActivityFeed.lua"));
        runner.run("notice_policy_source","local Layout=rawget(_G,\"KnoxSurvivorUILayout\") or {}; local THEME=Layout.theme or {}; local ActivityFeed={};"
            +section(activitySource,"-- NOTICE POLICY (pure)","-- END NOTICE POLICY")
            +"codecActivityFeed=ActivityFeed");
        runner.run("notice_rail",Files.readString(root.resolve("java/fixtures/notice-rail.lua")));
        String traversalSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"));
        runner.run("traversal_memory_source","local Controller={};"
            +"local function safeObjectBoolean(object,methodName,fallback) "
            +"if object==nil then return fallback end "
            +"local value=object[methodName] "
            +"if type(value)==\"function\" then local ok,result=pcall(value,object) if ok then return result==true end return fallback end "
            +"if value~=nil then return value==true end return fallback end\n"
            +section(traversalSource,"-- TRAVERSAL MEMORY (owner: this controller)","-- END TRAVERSAL MEMORY")
            +"codecTraversalMemory=Controller");
        runner.run("traversal_memory",Files.readString(root.resolve("java/fixtures/traversal-memory.lua")));
        runner.run("entry_candidate_score_source","local Controller={};"
            +"local function safeObjectBoolean(object,methodName,fallback) "
            +"if object==nil then return fallback end "
            +"local value=object[methodName] "
            +"if type(value)==\"function\" then local ok,result=pcall(value,object) if ok then return result==true end return fallback end "
            +"if value~=nil then return value==true end return fallback end\n"
            +section(traversalSource,"-- ENTRY SCORE (pure)","-- END ENTRY SCORE")
            +"codecEntryScore=Controller");
        runner.run("entry_candidate_score",Files.readString(root.resolve("java/fixtures/entry-candidate-score.lua")));
        runner.run("courage_threshold_source","local Controller={};"
            +section(traversalSource,"-- COURAGE THRESHOLD (pure)","-- END COURAGE THRESHOLD")
            +"codecCourage=Controller");
        runner.run("personality_traits",Files.readString(root.resolve("java/fixtures/personality-traits.lua")));
        runner.run("forced_entry_admission_source","local Controller={};"
            +"local LOCKED_DOOR_MIN_ENDURANCE=0.40\n"
            +section(traversalSource,"-- FORCED ENTRY ADMISSION (pure)","-- END FORCED ENTRY ADMISSION")
            +"codecForcedEntry=Controller");
        runner.run("forced_entry_admission",Files.readString(root.resolve("java/fixtures/forced-entry-admission.lua")));
        String eventsSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_KnoxEvents.lua"));
        runner.run("KS_KnoxEvents",eventsSource);
        runner.run("raid_intent_source","local KnoxEvents={};"
            +section(eventsSource,"-- RAID INTENT (pure)","-- END RAID INTENT")
            +"codecRaidIntent=KnoxEvents;");
        runner.run("raid_warning",Files.readString(root.resolve("java/fixtures/raid-warning.lua")));
        String alarmAnswerSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"));
        runner.run("alarm_answer_source","local Controller={};"
            +section(alarmAnswerSource,"-- ALARM ANSWER (pure)","-- END ALARM ANSWER")
            +"codecAlarmAnswer=Controller;");
        runner.run("base_alarm_answer",Files.readString(root.resolve("java/fixtures/base-alarm-answer.lua")));
        runner.run("raid_alarm_source",Files.readString(root.resolve("java/fixtures/raid-alarm-source.lua")));
        String inventorySource=Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionInventory.lua"));
        runner.run("inventory_attention_source", "local CompanionInventory={};local UILayout=codecPersonSurface;"
            +"local active,attention,exposedBodies,knownBodies={},{},{},{};"
            +"local localPlayerFor=function(n) return getSpecificPlayer(n) end;"
            +"local function nearby() return true end;local function displayName() return 'Patient' end;"
            +"local function inventoryLog() end;local function setVisiblePage(page,v) page:setVisible(v) end;"
            +"local function isSurvivorContainer(n,inv) return inv==exposedBodies[n]:getInventory() end;"
            +section(inventorySource,"local function releaseAttention", "local function nearby")
            +section(inventorySource,"function CompanionInventory.canManage", "-- Resolve through native")
            +section(inventorySource,"function CompanionInventory.show", "if Events ~= nil and Events.OnTick ~= nil")
            +"codecInventory=CompanionInventory");
        runner.run("interaction_attention",Files.readString(root.resolve("java/fixtures/interaction-attention.lua")));
        String nameplateSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNameplates.lua"));
        runner.run("nameplate_env","__ksEvents=Events;__ksRequire=require;"
            +"Events=setmetatable({},{__index=function() return {Add=function() end} end});"
            +"KnoxSurvivorNames={resolve=function(id) return nil,nil,'Name-'..tostring(id) end};"
            +"require=function(name) return rawget(_G,'KnoxSurvivorNames') or true end");
        runner.run("KS_SurvivorNameplates",nameplateSource);
        runner.run("nameplate_off_cost",Files.readString(root.resolve("java/fixtures/nameplate-off-cost.lua")));
        requireGlobals(environment,table,"nameplate_status","KnoxSurvivorNameplates");
        runner.run("nameplate_status",Files.readString(root.resolve("java/fixtures/nameplate-status.lua")));
        requireGlobals(environment,table,"nameplate_density","KnoxSurvivorNameplates");
        runner.run("nameplate_density",Files.readString(root.resolve("java/fixtures/nameplate-density.lua")));
        runner.run("nameplate_restore","Events=__ksEvents;__ksEvents=nil;require=__ksRequire;__ksRequire=nil;"
            +"KnoxSurvivorNames=nil");

        String worldSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_WorldPopulation.lua"));
        runner.run("record_location_cache_source",section(worldSource,"local function finite", "local function coordinateKey")
            +section(worldSource,"local recordLocationCache", "local function materializeVirtualLocation")
            +"codecRecordLocation=recordLocation");
        runner.run("record_location_cache",Files.readString(root.resolve("java/fixtures/record-location-cache.lua")));
        runner.run("storage_filter_setup","codecPreviousStorage=KnoxBaseStorage;codecPreviousFilterUI=KnoxBaseStorageFilterUI;"
            +"codecPreviousCollapsable=ISCollapsableWindowJoypad;ISCollapsableWindowJoypad={derive=function() return {} end}");
        runner.run("storage_filter_owner",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorage.lua")));
        runner.run("storage_filter_ui",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorageFilterUI.lua")));
        runner.run("storage_food_routing",Files.readString(root.resolve("java/fixtures/storage-food-routing.lua")));
        runner.run("storage_fuel_routing",Files.readString(root.resolve("java/fixtures/storage-fuel-routing.lua")));
        runner.run("storage_summary_cache",Files.readString(root.resolve("java/fixtures/storage-summary-cache.lua")));
        runner.run("storage_capacity_overflow",Files.readString(root.resolve("java/fixtures/storage-capacity-overflow.lua")));
        runner.run("KS_EquipmentIntelligence",Files.readString(root.resolve("mod/42/media/lua/client/KS_EquipmentIntelligence.lua")));
        runner.run("role_kit",Files.readString(root.resolve("java/fixtures/role-kit.lua")));
        runner.run("storage_filter_common",Files.readString(root.resolve("java/fixtures/storage-filter-common.lua")));
        runner.run("base_supply_planner",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseSupplyPlanner.lua")));
        runner.run("floor_stock",Files.readString(root.resolve("java/fixtures/floor-stock.lua")));
        runner.run("base_supply_storage_snapshot",Files.readString(root.resolve("java/fixtures/base-supply-storage-snapshot.lua")));
        String jobsSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseJobs.lua"));
        runner.run("base_zone_reconciliation_source","local BaseJobs={};"
            +section(jobsSource,"BaseJobs.AUTOMATIC_TYPES = {","-- Work areas are duty destinations")
            +section(jobsSource,"local function canonicalZoneType", "local function itemRequirements")
            +"codecZoneJobs=BaseJobs");
        runner.run("base_zone_reconciliation",Files.readString(root.resolve("java/fixtures/base-zone-reconciliation.lua")));
        runner.run("KS_BaseJobs",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseJobs.lua")));
        // Pain is a body read that the eligibility gate consumes. Load the real
        // snapshot and pain rule, plus the real canPerformTask, so the fixture
        // drives production Lua rather than a copy of the rule. The whole needs
        // module is deliberately not loaded here: it changes what later fixtures
        // see and would make them pass for the wrong reason.
        runner.run("pain_work_needs_source","local Needs={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNeeds.lua")),
                "function Needs.snapshot","function Needs.isNeedCurrent")
            +"codecPainNeeds=Needs");
        runner.run("pain_work_gate_source","local BaseManager={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseManager.lua")),
                "local function meetsRequirements","-- BASE LAYOUT PROPOSAL (pure)")
            +"codecPainGate=BaseManager");
        // The assignment gate is a real function from the task board, so the
        // fixture can check the reason passthrough instead of skipping it.
        runner.run("pain_work_claim_source","local TaskBoard={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseTaskBoard.lua")),
                "function TaskBoard.canClaimSpecific","function TaskBoard.claimSpecific")
            +"codecClaimBoard=TaskBoard");
        runner.run("witness_social_source","local CompanionService={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua")),
                "local WITNESS_CAP = 6","function CompanionService.socialActs")
            +"codecWitness=CompanionService");
        requireGlobals(environment,table,"witnessed_act","codecWitness");
        runner.run("witnessed_act",Files.readString(root.resolve("java/fixtures/witnessed-act.lua")));
        requireGlobals(environment,table,"pain_work","codecPainNeeds","codecPainGate","codecClaimBoard");
        runner.run("pain_work",Files.readString(root.resolve("java/fixtures/pain-work.lua")));
        runner.run("weather_shelter_needs_source","local Needs={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNeeds.lua")),
                "function Needs.snapshot","function Needs.isNeedCurrent")
            +"codecWeatherNeeds=Needs");
        requireGlobals(environment,table,"weather_shelter","codecWeatherNeeds");
        runner.run("weather_shelter",Files.readString(root.resolve("java/fixtures/weather-shelter.lua")));
        // Illness is the engine's own infection flag on the body this mod
        // persists whole. The reader and the gate are production Lua, and the
        // fixture fails if either is missing rather than accommodating nil.
        runner.run("infection_needs_source","local Needs={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNeeds.lua")),
                "function Needs.snapshot","function Needs.isNeedCurrent")
            +"codecIllnessNeeds=Needs");
        requireGlobals(environment,table,"infection_read","codecIllnessNeeds","codecPainGate");
        runner.run("infection_read",Files.readString(root.resolve("java/fixtures/infection-read.lua")));
        runner.run("raid_watch",Files.readString(root.resolve("java/fixtures/raid-watch.lua")));
        runner.run("raid_aftermath",Files.readString(root.resolve("java/fixtures/raid-aftermath.lua")));
        runner.run("raid_intruder",Files.readString(root.resolve("java/fixtures/raid-intruder.lua")));
        runner.run("base_intent",Files.readString(root.resolve("java/fixtures/base-intent.lua")));
        runner.run("base_kind",Files.readString(root.resolve("java/fixtures/base-kind.lua")));
        runner.run("faction_war",Files.readString(root.resolve("java/fixtures/faction-war.lua")));
        runner.run("leader_intent_source","local BaseManager={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseManager.lua")),
                "-- LEADER INTENT (pure)","-- END LEADER INTENT")
            +"codecLeaderIntent=BaseManager");
        runner.run("leader_intent",Files.readString(root.resolve("java/fixtures/leader-intent.lua")));
        runner.run("leader_withdrawal_source","local Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "-- WITHDRAWAL AUTHORITY (pure)","-- END WITHDRAWAL AUTHORITY")
            +"codecWithdrawal=Controller");

        runner.run("role_hours",Files.readString(root.resolve("java/fixtures/role-hours.lua")));
        runner.run("schedule_hour_label",Files.readString(root.resolve("java/fixtures/schedule-hour-label.lua")));
        String baseManagerSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseManager.lua"));
        runner.run("base_layout_source","local BaseManager={};"
            +section(baseManagerSource,"BaseManager.ZONE_TYPES = {","local function worldAge()")
            +section(baseManagerSource,"function BaseManager.addZone","function BaseManager.containerReference")
            +section(baseManagerSource,"function BaseManager.containsSquare","function BaseManager.setTerritory")
            +section(baseManagerSource,"function BaseManager.containerReference","function BaseManager.setStorageFilters")
            +section(baseManagerSource,"-- BASE LAYOUT PROPOSAL (pure)","-- END BASE LAYOUT PROPOSAL")
            +"codecBaseLayout=BaseManager");
        runner.run("base_layout",Files.readString(root.resolve("java/fixtures/base-layout.lua")));
        runner.run("base_storage_layout",Files.readString(root.resolve("java/fixtures/base-storage-layout.lua")));
        runner.run("KS_BaseCompound",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseCompound.lua")));
        runner.run("base_compound",Files.readString(root.resolve("java/fixtures/base-compound.lua")));
        runner.run("KS_BaseStorageDepot",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorage.lua")));
        runner.run("depot_filters",Files.readString(root.resolve("java/fixtures/depot-filters.lua")));
        runner.run("base_rally_source","local BaseManager={};"
            +section(baseManagerSource,"-- BASE RALLY (pure)","-- END BASE RALLY")
            +"codecBaseRally=BaseManager");
        runner.run("base_rally",Files.readString(root.resolve("java/fixtures/base-rally.lua")));
        runner.run("rally_admission_source","local Controller={};"
            +section(alarmAnswerSource,"-- RALLY ADMISSION (pure)","-- END RALLY ADMISSION")
            +"codecRallyAdmission=Controller;");
        runner.run("rally_route",Files.readString(root.resolve("java/fixtures/rally-route.lua")));
        runner.run("rally_reach_source","local BaseManager={};"
            +section(baseManagerSource,"-- BASE RALLY (pure)","-- END BASE RALLY")
            +"codecBaseReach=BaseManager");
        runner.run("rally_reach",Files.readString(root.resolve("java/fixtures/rally-reach.lua")));
        runner.run("bed_roster_source","local BaseManager={};"
            +section(baseManagerSource,"-- BASE BED ROSTER (pure)","-- END BASE BED ROSTER")
            +"codecBedRoster=BaseManager");
        runner.run("bed_roster",Files.readString(root.resolve("java/fixtures/bed-roster.lua")));
        runner.run("home_attention_source","local BaseManager={};"
            +section(baseManagerSource,"-- BASE HOME ATTENTION (pure)","-- END BASE HOME ATTENTION")
            +"codecHomeAttention=BaseManager");
        runner.run("home_attention",Files.readString(root.resolve("java/fixtures/home-attention.lua")));
        runner.run("home_status_source","local BaseManager={};"
            +section(baseManagerSource,"-- BASE HOME STATUS (read-only)","-- END BASE HOME STATUS")
            +"codecHomeStatus=BaseManager");
        runner.run("home_status",Files.readString(root.resolve("java/fixtures/home-status.lua")));
        runner.run("auto_barricade",Files.readString(root.resolve("java/fixtures/auto-barricade.lua")));
        runner.run("homecoming_source","local Homecoming={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_Homecoming.lua")),
                "-- HOME COMING (pure)","-- END HOME COMING")
            +"codecHomecoming=Homecoming");
        runner.run("homecoming",Files.readString(root.resolve("java/fixtures/homecoming.lua")));
        runner.run("layout_reveal_source","local Layout={};"
            +section(layoutSource,"-- Bring one existing child","function Layout.routeWheelToChildren")
            +"codecLayoutReveal=Layout");
        runner.run("layout_reveal",Files.readString(root.resolve("java/fixtures/ui-layout-reveal.lua")));
        runner.run("one_window_source","local Layout={};"
            +section(layoutSource,"-- ONE KNOX SURFACE (pure)","-- END ONE KNOX SURFACE")
            +"codecOneWindow=Layout");
        runner.run("one_window",Files.readString(root.resolve("java/fixtures/one-window.lua")));
        runner.run("weapon_word_source",
            section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorViewModel.lua")),
                "-- WEAPON WORD (pure)","-- END WEAPON WORD")
            +"codecWeaponWord=weaponWord;codecWeaponCondition=conditionWord");
        runner.run("weapon_word",Files.readString(root.resolve("java/fixtures/weapon-word.lua")));
        runner.run("ammo_word_source",
            section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorViewModel.lua")),
                "-- WEAPON WORD (pure)","-- END WEAPON WORD")
            +"codecAmmoWord=ammoWord");
        runner.run("condition_rows_source",
            section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorViewModel.lua")),
                "-- CONDITION ROWS (pure)","-- END CONDITION ROWS")
            +"codecConditionRows={painFraction=painFraction,bleedingWord=bleedingWord,medicalLabel=medicalLabel,infectionWord=infectionWord}");
        runner.run("condition_rows",Files.readString(root.resolve("java/fixtures/condition-rows.lua")));
        runner.run("order_row_source",
            section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorViewModel.lua")),
                "-- ORDER ROW (pure)","-- END ORDER ROW")
            +"codecOrderRow={orderRowLabel=orderRowLabel}");
        runner.run("order_row",Files.readString(root.resolve("java/fixtures/order-row.lua")));
        // The temporary-override fixture owns a survivor, a base and a player
        // faction. Run it against a scratch ModData root and round-trip that
        // root through the same codec, so its records cannot change the
        // shared survivor count that save_event asserts.
        Method get=table.getMethod("rawget",Object.class),set=table.getMethod("rawset",Object.class,Object.class);
        Object savedData=get.invoke(environment,"data");
        Object scratchData=platform.getClass().getMethod("newTable").invoke(platform);
        set.invoke(environment,"data",scratchData);
        runner.run("schedule_override",Files.readString(root.resolve("java/fixtures/schedule-override.lua")));
        Object scheduleGraph=get.invoke(environment,"data");
        ByteBuffer scheduleBytes=ByteBuffer.allocate(8*1024*1024);
        scheduleGraph.getClass().getMethod("save",ByteBuffer.class).invoke(scheduleGraph,scheduleBytes);
        scheduleBytes.flip();
        Object scheduleRestored=platform.getClass().getMethod("newTable").invoke(platform);
        scheduleRestored.getClass().getMethod("load",ByteBuffer.class,int.class)
            .invoke(scheduleRestored,scheduleBytes,240);
        if(scheduleBytes.hasRemaining())
            throw new AssertionError("Schedule override codec did not consume exact snapshot");
        set.invoke(environment,"data",scheduleRestored);
        runner.run("schedule_override_reload","verifyScheduleOverrideReload()");
        set.invoke(environment,"data",savedData);
        runner.run("base_needs",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseNeeds.lua")));
        runner.run("base_priority_cache",Files.readString(root.resolve("java/fixtures/base-priority-cache.lua")));
        runner.run("KS_AwayTeamExecutor",Files.readString(root.resolve("mod/42/media/lua/client/KS_AwayTeamExecutor.lua")));
        runner.run("away_team_results",Files.readString(root.resolve("java/fixtures/away-team-results.lua")));
        runner.run("away_scout_live_handoff",Files.readString(root.resolve("java/fixtures/away-scout-live-handoff.lua")));
        runner.run("away_return_travel",Files.readString(root.resolve("java/fixtures/away-return-travel.lua")));
        runner.run("away_squad_dispatch",Files.readString(root.resolve("java/fixtures/away-squad-dispatch.lua")));
        runner.run("away_mission_purpose",Files.readString(root.resolve("java/fixtures/away-mission-purpose.lua")));
        runner.run("KS_SurvivorLooting",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorLooting.lua")));
        runner.run("away_cargo_delivery",Files.readString(root.resolve("java/fixtures/away-cargo-delivery.lua")));
        runner.run("reset_looting","KnoxSurvivorLooting=nil");
        runner.run("KS_BaseStorage_by_label",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorage.lua")));
        runner.run("KS_BaseOrganize",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseOrganize.lua")));
        runner.run("base_supply_targets",Files.readString(root.resolve("java/fixtures/base-supply-targets.lua")));
        runner.run("settlement_storage_problems",Files.readString(root.resolve("java/fixtures/settlement-storage-problems.lua")));
        runner.run("base_organize_misfiled",Files.readString(root.resolve("java/fixtures/base-organize-misfiled.lua")));
        runner.run("unshelved_cargo_report",Files.readString(root.resolve("java/fixtures/unshelved-cargo-report.lua")));
        runner.run("overflow_deposit_wiring",Files.readString(root.resolve("java/fixtures/overflow-deposit-wiring.lua")));
        runner.run("KS_MissionTargets",Files.readString(root.resolve("mod/42/media/lua/client/KS_MissionTargets.lua")));
        runner.run("KS_VehicleNavigation",Files.readString(root.resolve("mod/42/media/lua/client/KS_VehicleNavigation.lua")));
        runner.run("KS_NpcVehicleTravel",Files.readString(root.resolve("mod/42/media/lua/client/KS_NpcVehicleTravel.lua")));
        runner.run("vehicle_fetch_order",Files.readString(root.resolve("java/fixtures/vehicle-fetch-order.lua")));
        runner.run("KS_MapOrders",Files.readString(root.resolve("mod/42/media/lua/client/KS_MapOrders.lua")));
        runner.run("map_base_destination",Files.readString(root.resolve("java/fixtures/map-base-destination.lua")));
        runner.run("map_car_fetch_menu",Files.readString(root.resolve("java/fixtures/map-car-fetch-menu.lua")));
        runner.run("vehicle_approach",Files.readString(root.resolve("java/fixtures/vehicle-approach.lua")));
        runner.run("vehicle_surface_driving",Files.readString(root.resolve("java/fixtures/vehicle-surface-driving.lua")));
        runner.run("mission_dispatch_targets",Files.readString(root.resolve("java/fixtures/mission-dispatch-targets.lua")));
        runner.run("mission_area_dispatch",Files.readString(root.resolve("java/fixtures/mission-area-dispatch.lua")));
        runner.run("KS_Creator",Files.readString(root.resolve("mod/42/media/lua/client/KS_Creator.lua")));
        runner.run("creator_roster",Files.readString(root.resolve("java/fixtures/creator-roster.lua")));
        runner.run("creator_handover",Files.readString(root.resolve("java/fixtures/creator-handover.lua")));
        runner.run("creator_menu_button",Files.readString(root.resolve("java/fixtures/creator-menu-button.lua")));
        runner.run("creator_appearance",Files.readString(root.resolve("java/fixtures/creator-appearance.lua")));
        runner.run("KS_SurvivorStartingGear",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorStartingGear.lua")));
        runner.run("creator_pack_items",Files.readString(root.resolve("java/fixtures/creator-pack-items.lua")));
        String autonomySource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomy.lua"));
        runner.run("availability_source","local Autonomy={};KnoxSurvivorAutonomy=Autonomy;controllers={};"
            +"local function freeForLiveMission() return true end;"
            +"local function canWatchMission() return false end;"
            +section(autonomySource,"local MAX_SCOUT_PARTY = 3","-- CompanionService calls this only after"));
        runner.run("mission_availability",Files.readString(root.resolve("java/fixtures/mission-availability.lua")));
        runner.run("duty_revision_stamp",Files.readString(root.resolve("java/fixtures/duty-revision-stamp.lua")));
        runner.run("mission_roles",Files.readString(root.resolve("java/fixtures/mission-roles.lua")));
        String controllerSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"));
        runner.run("mission_claims_source",section(controllerSource,
            "local function sortiePeerClaimedContainer","local function findExploration")
            +"\n_G.sortiePeerClaimedContainer=sortiePeerClaimedContainer");
        runner.run("mission_shared_claims",Files.readString(root.resolve("java/fixtures/mission-shared-claims.lua")));
        String companionInventorySource=Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionInventory.lua"));
        runner.run("inventory_refusal_source","CompanionInventory={};"
            +section(companionInventorySource,"function CompanionInventory.refusalText","-- Resolve through native container ownership")
            +"\n_G.inventoryRefusalText=CompanionInventory.refusalText;"
            +"_G.inventoryRequest=CompanionInventory.request");
        String notebookCrewSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNotebook.lua"));
        runner.run("crew_inventory_source","CrewView={};"
            +section(notebookCrewSource,"function CrewView:onInventory()","function CrewView:prerender()")
            +"\n_G.crewInventoryHandler=CrewView.onInventory");
        runner.run("crew_inventory_access",Files.readString(root.resolve("java/fixtures/crew-inventory-access.lua")));
        String notebookSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNotebook.lua"));
        runner.run("notebook_crew_selection_source","ISPanelJoypad={prerender=function() end};local CrewView={};"
            +section(notebookSource,"function CrewView:refreshGuardOverrideControl", "function CrewView:onSaveSchedule")
            +section(notebookSource,"function CrewView:prerender()", "function CrewView:onJoypadDown")
            +"codecCrewView=CrewView");
        runner.run("notebook_draft_source","CrewView={};"
            +section(notebookSource,"function CrewView.draftAllAnything","function CrewView.scheduleStatusText")
            +"\ncodecDraftAllAnything=CrewView.draftAllAnything");
        runner.run("notebook_priority_source","CrewView={};"
            +section(notebookSource,"local PRIORITY_STATE_LABELS","local PRIORITY_STATE_NEXT")
            +section(notebookSource,"local PRIORITY_STATE_HINTS","function CrewView:paintCrewDetail()")
            +"\ncodecPriorityHint=CrewView.priorityHint");
        runner.run("notebook_guard_source","CrewView={};"
            +section(notebookSource,"function CrewView.guardControl","function CrewView:refreshGuardOverrideControl")
            +"\ncodecGuardControl=CrewView.guardControl");
        String fenceSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"));
        runner.run("fence_hop_source","Controller={};"
            +section(fenceSource,"function Controller.fenceHopDirection","local FENCE_HOP_RETRY_TICKS")
            +"\ncodecFenceHopDirection=Controller.fenceHopDirection");
        runner.run("fence_hop_direction",Files.readString(root.resolve("java/fixtures/fence-hop-direction.lua")));
        runner.run("fence_traversal_source","Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "-- FENCE TRAVERSAL (pure)","-- END FENCE TRAVERSAL")
            +"\ncodecFenceTraversalRefusal=Controller.fenceTraversalRefusal");
        runner.run("fence_traversal",Files.readString(root.resolve("java/fixtures/fence-traversal.lua")));
        runner.run("window_combat_source","Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "-- WINDOW COMBAT POLICY (pure)","-- END WINDOW COMBAT POLICY")
            +"\ncodecWindowCombatPolicy=Controller.windowCombatPolicy");
        runner.run("window_combat",Files.readString(root.resolve("java/fixtures/window-combat.lua")));
        runner.run("notebook_guard_control",Files.readString(root.resolve("java/fixtures/notebook-guard-control.lua")));
        runner.run("notebook_priority_anything",Files.readString(root.resolve("java/fixtures/notebook-priority-hint.lua")));
        runner.run("notebook_draft_anything",Files.readString(root.resolve("java/fixtures/notebook-draft-anything.lua")));
        runner.run("notebook_crew_selection",Files.readString(root.resolve("java/fixtures/notebook-selection-refresh.lua")));
        runner.run("crew_faction_source","local CrewView={};"
            +section(notebookSource,"-- FACTION CHOICES (pure)","-- END FACTION CHOICES")
            +"codecCrewFaction=CrewView");
        runner.run("crew_faction_move",Files.readString(root.resolve("java/fixtures/crew-faction-move.lua")));
        runner.run("crew_guard_override_source","ISPanelJoypad={prerender=function() end};local CrewView={};"
            +section(notebookSource,"local SCHEDULE_ASSIGNMENT_LABELS = {","local SCHEDULE_TOOLS = {")
            +section(notebookSource,"local function currentScheduleHour()","local function responsiveControlColumns")
            +section(notebookSource,"function CrewView.scheduleStatusText","function CrewView:paintCrewDetail")
            +section(notebookSource,"function CrewView:onGuardTonight","function CrewView:refreshGuardOverrideControl")
            +section(notebookSource,"function CrewView:refreshGuardOverrideControl","function CrewView:onSaveSchedule")
            +"codecCrewView=CrewView;codecScheduleStatusText=CrewView.scheduleStatusText;"
            +"codecCurrentScheduleHour=currentScheduleHour");
        runner.run("crew_guard_override",Files.readString(root.resolve("java/fixtures/crew-guard-override.lua")));
        KnoxSurvivorRecord beforeMeal=KnoxSurvivorRecord.decode(portable);
        var meal=beforeMeal.inventory.consumeSupply("food",.1,KnoxInventorySnapshotVerifier.Item.class);
        if(meal==null || Math.abs(meal.hungerRelief()-.1)>.000001)
            throw new AssertionError("Journey recovery meal has no real native-shaped receipt");
        portable=new KnoxSurvivorRecord(beforeMeal.id,beforeMeal.x,beforeMeal.y,beforeMeal.z,
            beforeMeal.positionX,beforeMeal.positionY,beforeMeal.appearance,meal.inventory(),
            beforeMeal.health,nativePhysiology((float)(.6-meal.hungerRelief()))).encode();
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"expectedRecord",portable);
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"expectedHunger",.6-meal.hungerRelief());
        runner.run("KS_Runtime",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorRuntime.lua")));
        runner.run("KS_Unloaded",Files.readString(root.resolve("mod/42/media/lua/client/KS_UnloadedSurvival.lua")));
        runner.run("offscreen_supply_arity",Files.readString(root.resolve("java/fixtures/offscreen-supply-arity.lua")));
        runner.run("offscreen_origin_read_budget",Files.readString(root.resolve("java/fixtures/offscreen-origin-read-budget.lua")));
        runner.run("save_event",Files.readString(root.resolve("java/fixtures/companion-save-event.lua")));
        Object names=runner.run("KS_Names",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNames.lua")));
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"codecNames",names);
        runner.run("KS_ReputationView",Files.readString(root.resolve("mod/42/media/lua/client/KS_ReputationView.lua")));
        runner.run("view_require","require=function(name) if name=='KS_SurvivorNames' then return codecNames end if name=='KS_ReputationView' then return rawget(_G,'KnoxReputationView') end return true end");
        runner.run("KS_ViewModel",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorViewModel.lua")));
        runner.run("readiness_view",Files.readString(root.resolve("java/fixtures/companion-readiness-view.lua")));
        runner.run("reputation_view",Files.readString(root.resolve("java/fixtures/reputation-view.lua")));
        runner.run("party_summary",Files.readString(root.resolve("java/fixtures/party-summary.lua")));
        runner.run("party_detail",Files.readString(root.resolve("java/fixtures/party-detail.lua")));
        runner.run("map_condition_source","local Orders={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_MapOrders.lua")),
                "-- MAP CONDITION (pure)","-- END MAP CONDITION")
            +"codecMapCondition={markerCondition=Orders.markerCondition}");
        runner.run("map_condition",Files.readString(root.resolve("java/fixtures/map-condition.lua")));
        runner.run("compass_source","local Indicators={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SpeechIndicators.lua")),
                "-- COMPASS (pure)","-- END COMPASS")
            +"codecCompass={compassWord=Indicators.compassWord}");
        runner.run("patrol_sighting_source","local Patrol={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionPatrol.lua")),
                "-- PATROL SIGHTING (pure)","-- END PATROL SIGHTING")
            +"codecPatrol={sightingWord=Patrol.sightingWord,sightingDue=Patrol.sightingDue,contactWord=Patrol.contactWord,feedLine=Patrol.feedLine}");
        runner.run("patrol_sighting",Files.readString(root.resolve("java/fixtures/patrol-sighting.lua")));
        Object patrolModule=runner.run("KS_CompanionPatrol_module",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionPatrol.lua")));
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"KnoxCompanionPatrol",patrolModule);
        runner.run("patrol_overlay_source","local Orders={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_MapOrders.lua")),
                "-- PATROL OVERLAY (pure)","-- END PATROL OVERLAY")
            +"codecPatrolOverlay={patrolRoutes=Orders.patrolRoutes,routeArrow=Orders.routeArrow,livePatrolStops=Orders.livePatrolStops,patrolLegendRows=Orders.patrolLegendRows}");
        runner.run("patrol_overlay",Files.readString(root.resolve("java/fixtures/patrol-overlay.lua")));
        runner.run("death_feed_require","require=function(name) if name=='KS_SurvivorNames' then return codecNames end return true end");
        runner.run("death_feed_env","ISCollapsableWindow={derive=function() return {} end};ISPanel={derive=function() return {} end};ISRichTextPanel={derive=function() return {} end};ISButton={new=function() return {} end};ISUIElement={derive=function() return {} end};ISWindow={derive=function() return {} end}");
        runner.run("KS_ActivityFeed",Files.readString(root.resolve("mod/42/media/lua/client/KS_ActivityFeed.lua")));
        runner.run("death_killfeed",Files.readString(root.resolve("java/fixtures/death-killfeed.lua")));
        runner.run("faction_witness_env","__ksEvents=Events;Events=setmetatable({},{__index=function() return {Add=function() end} end});require=function(name) return true end");
        runner.run("KS_HumanCombatRelations",Files.readString(root.resolve("mod/42/media/lua/client/KS_HumanCombatRelations.lua")));
        runner.run("faction_witness",Files.readString(root.resolve("java/fixtures/faction-witness.lua")));
        runner.run("faction_witness_restore","Events=__ksEvents;__ksEvents=nil");
        runner.run("conversation_digest",Files.readString(root.resolve("java/fixtures/conversation-digest.lua")));
        runner.run("radio_mode_reload",Files.readString(root.resolve("java/fixtures/radio-mode-reload.lua")));
        int size=0;
        for(int pass=0;pass<2;pass++) {
        Object graph=get.invoke(environment,"data");
        ByteBuffer bytes=ByteBuffer.allocate(8*1024*1024);
        graph.getClass().getMethod("save",ByteBuffer.class).invoke(graph,bytes);
        size=bytes.position();bytes.flip();
        Object restored=platform.getClass().getMethod("newTable").invoke(platform);
        restored.getClass().getMethod("load",ByteBuffer.class,int.class).invoke(restored,bytes,240);
        if(bytes.hasRemaining()) throw new AssertionError("Codec did not consume exact snapshot");
        set.invoke(environment,"data",restored);
        runner.run("reload_production",production);
        runner.run("verify", "verifyPersistedCompanion(); loadedHook(); verifyPersistedCompanion(); verifyReloadedGroupIndex(); verifyVehicleAssignmentReload(); verifyRadioModeReload(); verifyReadinessView()");
        }
        runner.run("extract","savedRecord=KnoxPersistence.getRecord('codec-person')");
        String loaded=(String)get.invoke(environment,"savedRecord");
        KnoxSurvivorRecord record=KnoxSurvivorRecord.decode(loaded);
        if(!portable.equals(record.encode())) throw new AssertionError("Portable record changed across B42 codec");
        var physiologyBody=new PhysiologyBody();
        record.physiology.restore(physiologyBody);
        if(!engineBytes(physiologyBody.stats).equals(record.physiology.encode().split("\\|",-1)[2])
            || !engineBytes(physiologyBody.nutrition).equals(record.physiology.encode().split("\\|",-1)[3])
            || Math.abs(physiologyBody.hours-12)>.000001 || physiologyBody.asleep
            || physiologyBody.asleepTime!=0)
            throw new AssertionError("Installed stats/nutrition payload changed across production restore");
        System.out.println("Installed B42 physiology PASS actualStats=true actualNutrition=true productionRestore=true actorFacade=true worldSave=false");
        var body=new KnoxInventorySnapshotVerifier.Body();
        record.inventory.restore(body,KnoxInventorySnapshotVerifier.Item.class);
        if(body.inventory.items.size()!=2 || !body.inventory.items.get(0).favorite
            || !body.inventory.items.get(1).communalBase.equals("home")
            || Math.abs(body.inventory.items.get(1).hunger+.1)>.000001)
            throw new AssertionError("Spent meal duplicated or personal/provision ownership changed");
        if(record.inventory.consumeSupply("food",.8,KnoxInventorySnapshotVerifier.Item.class,"home")!=null)
            throw new AssertionError("Loaded communal reserve was redistributed");
        System.out.println("Portable survivor record PASS nativeShapedItems=true spentMealAbsent=true personal=true reserve=true");
        runner.run("firearm_safe_call", "require=function(name) if name=='KS_SafeCall' then return {invoke=function(item,method) if item==nil or item[method]==nil then return nil end return item[method](item) end} end return true end");
        runner.run("KS_FirearmSupport",Files.readString(root.resolve("mod/42/media/lua/client/KS_FirearmSupport.lua")));
        runner.run("firearm_inventory",Files.readString(root.resolve("java/fixtures/firearm-inventory-ownership.lua")));
        runner.run("firearm_efz",Files.readString(root.resolve("java/fixtures/firearm-efz-compat.lua")));
        runner.run("cooking_action_stub", "ISToggleStoveAction={derive=function(self,name) return {} end}");
        runner.run("KS_BaseCooking",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseCooking.lua")));
        runner.run("cooking_policy",Files.readString(root.resolve("java/fixtures/base-cooking-policy.lua")));
        runner.run("base_recipe_meal",Files.readString(root.resolve("java/fixtures/base-recipe-meal.lua")));
        runner.run("base_recipe_execution",Files.readString(root.resolve("java/fixtures/base-recipe-execution.lua")));
        runner.run("faction_transfer_allocation",Files.readString(root.resolve("java/fixtures/faction-transfer-allocation.lua")));
        runner.run("KS_FactionProperty",Files.readString(root.resolve("mod/42/media/lua/client/KS_FactionProperty.lua")));
        runner.run("verify_faction_transfer_allocation","runFactionTransferFixture()");
        String serviceSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua"));
        runner.run("tactics_readout_source","CompanionService={};"
            +section(serviceSource,"local TACTIC_DEFAULTS = {","function CompanionService.commonTactics")
            +section(serviceSource,"function CompanionService.commonTactics","local function playerPartyMemberIds")
            +"KnoxCompanionService=CompanionService");
        runner.run("KS_RadialOrders",Files.readString(root.resolve("mod/42/media/lua/client/KS_RadialOrders.lua")));
        runner.run("tactical_readout",Files.readString(root.resolve("java/fixtures/tactical-readout.lua")));
        runner.run("invite_base_source","CompanionService={};"
            +section(serviceSource,"-- The homes this player may offer a newcomer","-- Base invitations are the second half")
            +"KnoxCompanionService=CompanionService");
        runner.run("base_invite_base",Files.readString(root.resolve("java/fixtures/base-invite-base.lua")));
        String talkPanelSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInteractionUI.lua"));
        runner.run("talk_panel_model","InteractionUI={}"
            +section(talkPanelSource,"local ACTION_LIMIT = 6","local function safeCall(fn, ...)")
            +"local function safeCall(fn, ...) if type(fn) ~= \"function\" then return false, nil end return pcall(fn, ...) end\n"
            +"local function isHostile() return false end\n"
            +section(talkPanelSource,"-- Live tactics for the survivor in this window","function Window:createChildren()")
            +"KS_TAB_PLAN=InteractionUI.tabPlan;KS_STATE_LINE=InteractionUI.stateLine;"
            +"KS_NEXT_CYCLE=nextCycle;KS_CYCLE_LABEL=cycleLabel;KS_ACTION_LABEL=actionLabel");
        runner.run("talk_panel_ask","CompanionService={}"
            +"local state={hearing=true,character=nil,reason=\"survivor_unavailable\",hostile=false}\n"
            +"local spoken=nil\n"
            +"local function validateInteraction(player, survivorId) if state.character==nil then return nil, state.reason end return state.character, nil end\n"
            +"local function socialSpeech(character, survivorId, event, fallback) spoken={event=event,text=fallback} return fallback end\n"
            +"CompanionService.getPlayerId=function(player) return \"player-1\" end\n"
            +"CompanionService.isSociallyHostileToPlayer=function(survivorId, playerId) return state.hostile==true end\n"
            +"KnoxJavaBridge={canHearOrder=function(a,b) return state.hearing end}\n"
            +section(serviceSource,"-- Questions a survivor can actually answer","function CompanionService.askAbout")
            +section(serviceSource,"function CompanionService.askAbout","-- Sims-style social menu.")
            +"KS_ASK=ASK_ANSWERS;KS_ASK_SET=function(t) for k,v in pairs(t) do state[k]=v end end;"
            +"KS_ASK_SPOKEN=function() return spoken end;KS_ASK_RESET=function() spoken=nil end");
        runner.run("talk_ask",Files.readString(root.resolve("java/fixtures/talk-ask.lua")));
        runner.run("talk_panel",Files.readString(root.resolve("java/fixtures/talk-panel.lua")));
        runner.run("KS_OffscreenStories",Files.readString(root.resolve("mod/42/media/lua/client/KS_OffscreenStories.lua")));
        runner.run("KS_SurvivorDialogue",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorDialogue.lua")));
        requireGlobals(environment,table,"pain_refusal_line","codecWeatherNeeds");
        runner.run("pain_refusal_line",Files.readString(root.resolve("java/fixtures/pain-refusal-line.lua")));
        runner.run("order_willingness_source","local CompanionService={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua")),
                "function CompanionService.witnessLadder","local function recordWitnesses")
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua")),
                "function CompanionService.orderWillingness","function CompanionService.orderContact")
            +"codecOrders=CompanionService");
        requireGlobals(environment,table,"order_willingness","codecOrders","KnoxSurvivorDialogue");
        runner.run("order_willingness",Files.readString(root.resolve("java/fixtures/order-willingness.lua")));
        // The plate asks the order gate, so it must run after that section exists.
        requireGlobals(environment,table,"nameplate_standing","KnoxSurvivorNameplates","codecOrders");
        runner.run("nameplate_standing",Files.readString(root.resolve("java/fixtures/nameplate-standing.lua")));
        requireGlobals(environment,table,"social_standing","codecOrders");
        runner.run("social_standing",Files.readString(root.resolve("java/fixtures/social-standing.lua")));
        requireGlobals(environment,table,"ask_standing","codecOrders");
        runner.run("ask_standing",Files.readString(root.resolve("java/fixtures/ask-standing.lua")));
        requireGlobals(environment,table,"witness_ladder","codecWitness","KnoxSurvivorDialogue");
        runner.run("witness_ladder",Files.readString(root.resolve("java/fixtures/witness-ladder.lua")));
        requireGlobals(environment,table,"witness_voice","KnoxSurvivorDialogue");
        runner.run("witness_voice",Files.readString(root.resolve("java/fixtures/witness-voice.lua")));
        requireGlobals(environment,table,"refusal_personality","KnoxSurvivorDialogue");
        runner.run("refusal_personality",Files.readString(root.resolve("java/fixtures/refusal-personality.lua")));
        requireGlobals(environment,table,"voice_coverage","KnoxSurvivorDialogue");
        runner.run("voice_coverage",Files.readString(root.resolve("java/fixtures/voice-coverage.lua")));
        requireGlobals(environment,table,"weather_voice","KnoxSurvivorDialogue","codecWeatherNeeds");
        runner.run("weather_voice",Files.readString(root.resolve("java/fixtures/weather-voice.lua")));
        requireGlobals(environment,table,"bite_voice","KnoxSurvivorDialogue");
        runner.run("bite_voice",Files.readString(root.resolve("java/fixtures/bite-voice.lua")));
        requireGlobals(environment,table,"weather_wet_voice","KnoxSurvivorDialogue");
        runner.run("weather_wet_voice",Files.readString(root.resolve("java/fixtures/weather-wet-voice.lua")));
        requireGlobals(environment,table,"weapon_broken_voice","KnoxSurvivorDialogue");
        runner.run("weapon_broken_voice",Files.readString(root.resolve("java/fixtures/weapon-broken-voice.lua")));
        requireGlobals(environment,table,"ammo_word","KnoxSurvivorDialogue");
        runner.run("ammo_word",Files.readString(root.resolve("java/fixtures/ammo-word.lua")));
        requireGlobals(environment,table,"line_of_fire","KnoxSurvivorDialogue");
        runner.run("line_of_fire",Files.readString(root.resolve("java/fixtures/line-of-fire.lua")));
        runner.run("offscreen_hearsay",Files.readString(root.resolve("java/fixtures/offscreen-hearsay.lua")));
        runner.run("KS_HouseClearing",Files.readString(root.resolve("mod/42/media/lua/client/KS_HouseClearing.lua")));
        runner.run("house_clearing",Files.readString(root.resolve("java/fixtures/house-clearing.lua")));
        // An earlier fixture replaces the KnoxPersistence global with a stub, so
        // the real module is restored before this fixture captures it.
        runner.run("KS_Persistence",production);
        runner.run("KS_AwayTeamExecutor",Files.readString(root.resolve("mod/42/media/lua/client/KS_AwayTeamExecutor.lua")));
        // Kept last: this fixture adds two survivor identities and two away
        // teams, and save_event asserts a shared survivor count, so it must not
        // run before an exact-count assertion.
        runner.run("supply_run_continuation",Files.readString(root.resolve("java/fixtures/supply-run-continuation.lua")));
        runner.run("leader_succession",Files.readString(root.resolve("java/fixtures/leader-succession.lua")));
        // State-adding fixtures run after save_event's shared-count assertion.
        runner.run("last_stand_source","local Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "-- LAST STAND (pure)","-- END LAST STAND")
            +"codecLastStand=Controller");
        runner.run("last_stand",Files.readString(root.resolve("java/fixtures/last-stand.lua")));
        runner.run("combat_approach_source","local Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "-- COMBAT APPROACH (pure)","-- END COMBAT APPROACH")
            +"codecCombatApproach=Controller");
        runner.run("combat_approach",Files.readString(root.resolve("java/fixtures/combat-approach.lua")));
        runner.run("threat_reservation_source","local Controller={};"
            +section(controllerSource,"-- THREAT RESERVATION (pure)","-- END THREAT RESERVATION")
            +"codecThreatReservation=Controller");
        runner.run("threat_reservation",Files.readString(root.resolve("java/fixtures/threat-reservation.lua")));
        runner.run("scheduled_bed_sleep_source","local Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "-- SCHEDULED BED SLEEP (pure)","-- END SCHEDULED BED SLEEP")
            +"codecScheduledBedSleep=Controller");
        runner.run("scheduled_bed_sleep",Files.readString(root.resolve("java/fixtures/scheduled-bed-sleep.lua")));
        runner.run("base_advice_source","local BaseManager={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseManager.lua")),
                "-- BASE ADVICE (pure)","-- END BASE ADVICE")
            +"codecBaseAdvice=BaseManager");
        runner.run("base_advice",Files.readString(root.resolve("java/fixtures/base-advice.lua")));
        runner.run("body_check_source","local Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "-- BODY CHECK (pure)","-- END BODY CHECK")
            +"codecBodyCheck=Controller");
        runner.run("body_check",Files.readString(root.resolve("java/fixtures/body-check.lua")));
        runner.run("radio_status_source","local BaseContextMenu={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseContextMenu.lua")),
                "-- RADIO STATUS (pure)","-- END RADIO STATUS")
            +"codecRadioStatus=BaseContextMenu");
        runner.run("radio_status",Files.readString(root.resolve("java/fixtures/radio-status.lua")));
        runner.run("radio_mode_source","local BaseContextMenu={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseContextMenu.lua")),
                "-- RADIO MODE (pure)","-- END RADIO MODE")
            +"codecRadioMode=BaseContextMenu");
        runner.run("radio_mode",Files.readString(root.resolve("java/fixtures/radio-mode.lua")));
        runner.run("radio_arrival_source","local BaseManager={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseManager.lua")),
                "-- BASE RADIO ARRIVAL (pure)","-- END BASE RADIO ARRIVAL")
            +"codecRadioArrival=BaseManager");
        runner.run("radio_arrival",Files.readString(root.resolve("java/fixtures/radio-arrival.lua")));
        runner.run("radio_risk_source","local BaseManager={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseManager.lua")),
                "-- BASE RADIO ARRIVAL (pure)","-- END BASE RADIO ARRIVAL")
            +"codecRadioRisk=BaseManager");
        runner.run("radio_risk",Files.readString(root.resolve("java/fixtures/radio-risk.lua")));
        runner.run("raid_demand_source","local KnoxEvents={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_KnoxEvents.lua")),
                "-- RAID DEMAND (pure)","-- END RAID DEMAND")
            +"codecRaidDemand=KnoxEvents");
        runner.run("raid_demand",Files.readString(root.resolve("java/fixtures/raid-demand.lua")));
        runner.run("leader_withdrawal",Files.readString(root.resolve("java/fixtures/leader-withdrawal.lua")));
        runner.run("death_trace",Files.readString(root.resolve("java/fixtures/death-trace.lua")));
        runner.run("raid_history",Files.readString(root.resolve("java/fixtures/raid-history.lua")));
        runner.run("vehicle_assignment_contract",Files.readString(root.resolve("java/fixtures/vehicle-assignment-contract.lua")));
        runner.run("recruit_refusal",Files.readString(root.resolve("java/fixtures/recruit-refusal.lua")));
        runner.run("faction_formation_notice",Files.readString(root.resolve("java/fixtures/faction-formation-notice.lua")));
        runner.run("KS_FactionCamps",Files.readString(root.resolve("mod/42/media/lua/client/KS_FactionCamps.lua")));
        runner.run("camp_introduction",Files.readString(root.resolve("java/fixtures/camp-introduction.lua")));
        runner.run("camp_reaction",Files.readString(root.resolve("java/fixtures/camp-reaction.lua")));
        runner.run("household_place_line",Files.readString(root.resolve("java/fixtures/household-place-line.lua")));
        runner.run("KS_BaseStorage",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorage.lua")));
        runner.run("storage_counted_label",Files.readString(root.resolve("java/fixtures/storage-counted-label.lua")));
        runner.run("capability_level_ups_source","local Capabilities={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorCapabilities.lua")),
                "-- LEVEL UPS (pure)","-- END LEVEL UPS")
            +"codecLevelUps=Capabilities");
        runner.run("capability_level_ups",Files.readString(root.resolve("java/fixtures/capability-level-ups.lua")));
        runner.run("text_wrap_source","local Layout={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorUILayout.lua")),
                "-- TEXT WRAP (pure)","-- END TEXT WRAP")
            +"codecTextWrap=Layout");
        runner.run("ui_text_wrap",Files.readString(root.resolve("java/fixtures/ui-text-wrap.lua")));
        runner.run("prompt_layout_source","local Prompt={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInteractionUI.lua")),
                "-- PROMPT LAYOUT (pure)","-- END PROMPT LAYOUT")
            +"codecPromptLayout=Prompt");
        runner.run("prompt_layout",Files.readString(root.resolve("java/fixtures/prompt-layout.lua")));
        runner.run("survivor_company",Files.readString(root.resolve("java/fixtures/survivor-company.lua")));
        runner.run("task_giveup",Files.readString(root.resolve("java/fixtures/task-giveup.lua")));
        // Kept last: it adds two survivor identities, and earlier fixtures assert
        // shared survivor counts. The needs rule and notice owner are real.
        runner.run("death_cause_needs_source","local Needs={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNeeds.lua")),
                "function Needs.snapshot","function Needs.isNeedCurrent")
            +"codecDeathNeeds=Needs");
        // Earlier fixtures install their own notice stub and do not put the real
        // module back, so the owner is restored before this fixture captures it.
        runner.run("KS_ActivityFeed",Files.readString(root.resolve("mod/42/media/lua/client/KS_ActivityFeed.lua")));
        requireGlobals(environment,table,"death_cause","codecDeathNeeds","KnoxActivityFeed","KnoxPersistence");
        runner.run("death_cause",Files.readString(root.resolve("java/fixtures/death-cause.lua")));
        System.out.println("B42 persistence codec PASS passes=2 bytes="+size+" productionLua=true realTableCodec=true worldSave=false");
    }
    static String sampleRecord() throws Exception {
        var body=new KnoxInventorySnapshotVerifier.Body();
        var personal=new KnoxInventorySnapshotVerifier.Item("Base.PersonalKeepsake");personal.favorite=true;
        body.inventory.AddItem(personal);
        for(int i=0;i<2;i++) {
            var food=new KnoxInventorySnapshotVerifier.Item("Base.Meal"+i);
            food.hunger=-.2f;food.communalBase="home";body.inventory.AddItem(food);
        }
        var receipt=KnoxInventorySnapshot.capture(body,240)
            .consumeSupply("food",.8,KnoxInventorySnapshotVerifier.Item.class,"home");
        if(receipt==null) throw new AssertionError("Initial real-record consumption failed");
        return new KnoxSurvivorRecord("codec-person",105,205,0,105.5f,205.5f,
            KnoxAppearanceSnapshot.decode("1|0|240||QWRh|U3Vydml2b3I||1|1.0"),receipt.inventory(),
            KnoxHealthSnapshot.decode("1|240|91|0|0|"),
            nativePhysiology(.6f)).encode();
    }

    // Actual installed engine data objects; the actor itself remains a facade.
    // Inspected constructors/save/load: no world/update/native actor is started.
    public static final class PhysiologyBody {
        final Object stats,nutrition;
        float asleepTime=123;double hours=2;boolean asleep=true;
        public PhysiologyBody() throws Exception {
            stats=Class.forName("zombie.characters.Stats").getConstructor().newInstance();
            nutrition=Class.forName("zombie.characters.BodyDamage.Nutrition")
                .getConstructor(Class.forName("zombie.characters.IsoPlayer")).newInstance(new Object[]{null});
        }
        public Object getStats() {return stats;}
        public Object getNutrition() {return nutrition;}
        public void setAsleepTime(float value) {asleepTime=value;}
        public void setHoursSurvived(double value) {hours=value;}
        public void setAsleep(boolean value) {asleep=value;}
    }
    private static KnoxPhysiologySnapshot nativePhysiology(float hunger) throws Exception {
        var body=new PhysiologyBody();
        Class<?> stat=Class.forName("zombie.characters.CharacterStat");
        String[] names={"HUNGER","THIRST","FATIGUE","ENDURANCE","PANIC"};
        float[] values={hunger,.3f,.2f,.8f,17f};
        for(int i=0;i<names.length;i++)
            body.stats.getClass().getMethod("set",stat,float.class).invoke(body.stats,stat.getField(names[i]).get(null),values[i]);
        body.nutrition.getClass().getMethod("setWeight",double.class).invoke(body.nutrition,76.5);
        body.nutrition.getClass().getMethod("setCalories",float.class).invoke(body.nutrition,1275f);
        return KnoxPhysiologySnapshot.decode("1|240|"+engineBytes(body.stats)+"|"+engineBytes(body.nutrition)
            +"|0|12|false|"+hunger+"|0.3|0.2|0.8");
    }
    private static String engineBytes(Object state) throws Exception {
        ByteBuffer bytes=ByteBuffer.allocate(65536);
        state.getClass().getMethod("save",ByteBuffer.class).invoke(state,bytes);
        byte[] encoded=new byte[bytes.position()];bytes.flip();bytes.get(encoded);
        return java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(encoded);
    }

    private static void benchmarkRecordLocation(String encoded) throws Exception {
        KnoxNpcRegistry registry=new KnoxNpcRegistry();
        var large=new KnoxInventorySnapshotVerifier.Body();
        for(int i=0;i<240;i++) large.inventory.AddItem(new KnoxInventorySnapshotVerifier.Item("Base.Stock"+i));
        String worst=KnoxSurvivorRecord.decode(encoded).withInventory(KnoxInventorySnapshot.capture(large,240));
        // Warm both production entry paths; retain checksums so work is observed.
        for(int i=0;i<32;i++) {registry.persistentRecordX(encoded);registry.persistentRecordLocation(encoded);}
        for(int size : new int[]{128,512,2048}) compareLocationPaths(registry,encoded,size);
        compareLocationPaths(registry,worst,256);
        boolean rejected=false;
        try {registry.persistentRecordLocation("corrupt");} catch(RuntimeException expected) {rejected=true;}
        if(!rejected) throw new AssertionError("Bulk location bypassed record validation");
    }
    private static void compareLocationPaths(KnoxNpcRegistry registry,String encoded,int count) {
        long before=System.nanoTime();long oldSum=0,newSum=0;
        for(int i=0;i<count;i++) oldSum+=registry.persistentRecordX(encoded)+registry.persistentRecordY(encoded)+registry.persistentRecordZ(encoded);
        long oldNs=System.nanoTime()-before;before=System.nanoTime();
        for(int i=0;i<count;i++) {
            var point=registry.persistentRecordLocation(encoded);newSum+=point.get("x")+point.get("y")+point.get("z");
        }
        long newNs=System.nanoTime()-before;
        if(oldSum!=newSum) throw new AssertionError("Population coordinate paths disagree");
        System.out.println("Record location workload count="+count+" encodedBytes="+encoded.length()
            +" oldCalls="+(count*3)+" newCalls="+count+" oldMs="+oldNs/1_000_000.0+" newMs="+newNs/1_000_000.0
            +" coordinatesEqual=true nativeFrameTime=false");
    }

    private static String section(String source,String start,String end) {
        int first=source.indexOf(start), last=source.indexOf(end,Math.max(0,first));
        if(first<0 || last<=first) throw new AssertionError("Missing production source section: "+start);
        return source.substring(first,last);
    }

    private record Runner(Method compile,Method call,Object thread,Object environment) {
        Object run(String name,String source) throws Exception {
            Object closure=compile.invoke(null,new StringReader(source),name,environment);
            Object[] result=(Object[])call.invoke(thread,closure,new Object[0]);
            if(result.length==0 || !Boolean.TRUE.equals(result[0]))
                throw new AssertionError(name+": "+java.util.Arrays.toString(result));
            return result.length>1 ? result[1] : null;
        }
    }
}
