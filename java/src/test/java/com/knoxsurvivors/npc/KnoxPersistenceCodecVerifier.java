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
        if (table.getMethod("rawget",Object.class).invoke(environment,"KnoxSurvivorUILayout") != uiLayoutModule)
            throw new AssertionError("UI adapters must share the production layout module");
        runner.run("ui_scale",Files.readString(root.resolve("java/fixtures/ui-scale.lua")));
        runner.run("KS_DevSpectateCatalog",Files.readString(root.resolve("mod/42/media/lua/client/KS_DevSpectateCatalog.lua")));
        runner.run("dev_spectate_catalog",Files.readString(root.resolve("java/fixtures/dev-spectate-catalog.lua")));
        runner.run("KS_BugReport",Files.readString(root.resolve("mod/42/media/lua/client/KS_BugReport.lua")));
        runner.run("bug_report",Files.readString(root.resolve("java/fixtures/bug-report.lua")));
        runner.run("bug_report_pause_source","local R=KnoxBugReport;local Report={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BugReportUI.lua")),
                "local function sync()","-- UI draw continues")
            +"KnoxBugReportSync=sync");
        runner.run("bug_report_pause",Files.readString(root.resolve("java/fixtures/bug-report-pause.lua")));
        runner.run("ui_window_lifecycle",Files.readString(root.resolve("java/fixtures/ui-window-lifecycle.lua")));
        runner.run("KS_CreatorWorld",Files.readString(root.resolve("mod/42/media/lua/client/KS_CreatorWorld.lua")));
        Object creatorModule=runner.run("KS_Creator",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_Creator.lua")));
        table.getMethod("rawset",Object.class,Object.class)
            .invoke(environment,"KnoxCreator",creatorModule);
        runner.run("creator_library",Files.readString(root.resolve("java/fixtures/creator-library.lua")));
        runner.run("creator_world_placement",Files.readString(root.resolve("java/fixtures/creator-world-placement.lua")));
        runner.run("KS_SpouseStart",Files.readString(root.resolve("mod/42/media/lua/client/KS_SpouseStart.lua")));
        runner.run("creator_start_placement",Files.readString(root.resolve("java/fixtures/creator-start-placement.lua")));
        runner.run("creator_default_overrides",Files.readString(root.resolve("java/fixtures/creator-default-overrides.lua")));
        runner.run("KS_CreatorLoadoutInfo",Files.readString(root.resolve("mod/42/media/lua/client/KS_CreatorLoadoutInfo.lua")));
        runner.run("creator_loadout_info",Files.readString(root.resolve("java/fixtures/creator-loadout-info.lua")));
        runner.run("KS_CreatorAppearanceUI",Files.readString(root.resolve("mod/42/media/lua/client/KS_CreatorAppearanceUI.lua")));
        String creatorPanelSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_CreatorPanel.lua"));
        runner.run("creator_view_source","local Panel={};local Creator=KnoxCreator;local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end;"
            +section(creatorPanelSource,"function Panel.editorMetrics", "local function computeMetrics")
            +section(creatorPanelSource,"function Panel.previewSignature", "function Window:previewDesc")
            +"codecCreatorView=Panel;local Window={};"
            +"KnoxCreatorAppearanceUI.install(Panel,Window,Creator,nil);"
            +section(creatorPanelSource,"function Window:commit", "-- A private descriptor")
            +section(creatorPanelSource,"function Window:previewDesc", "function Window:refreshRail")
            +"codecCreatorCommitWindow=Window");
        runner.run("creator_preview",Files.readString(root.resolve("java/fixtures/creator-preview.lua")));
        runner.run("creator_controls_refresh",Files.readString(root.resolve("java/fixtures/creator-controls-refresh.lua")));
        runner.run("KS_CharacterAppearance",Files.readString(root.resolve("mod/42/media/lua/client/KS_CharacterAppearance.lua")));
        runner.run("creator_polish",Files.readString(root.resolve("java/fixtures/creator-polish.lua")));
        runner.run("ui_page_scroll",Files.readString(root.resolve("java/fixtures/ui-page-scroll.lua")));
        String installedList=Files.readString(Path.of(args[1]).resolve("media/lua/client/ISUI/ISScrollingListBox.lua"));
        String creatorUiSource="creatorUiFactory=function(b)\nlocal Creator=KnoxCreator;local UILayout=KnoxSurvivorUILayout;local LoadoutInfo=KnoxCreatorLoadoutInfo;"
            +"local ISScrollingListBox=b.List;local ISLabel=b.Label;local MainScreen=b.Main;local UITransition=b.Transition;"
            +"local UIFont=b.Font;local getTextManager=b.textManager;local getSoundManager=b.soundManager;"
            +"local getPlayer=b.player;local _G={MainScreen=MainScreen};"
            +"local Panel={ENABLED=true};local Window={};local Picker={};KnoxCreatorAppearanceUI.install(Panel,Window,Creator,UILayout);"
            +section(installedList,"function ISScrollingListBox:setOnMouseDownFunction", "function ISScrollingListBox:setOverrideAButtonFunction")
            +section(installedList,"function ISScrollingListBox:invokeOnMouseDownFunction", "function ISScrollingListBox:setOnMouseDoubleClick")
            +section(creatorPanelSource,"local WIDTH, HEIGHT, PAD, ROW", "local iconCache = {}")
            +section(creatorPanelSource,"local iconCache = {}", "local function accentFor")
            +section(creatorPanelSource,"local function labelOf", "local Picker = ISPanel:derive")
            +section(creatorPanelSource,"function Window:createChildren", "function Window:createFactionList")
            +section(creatorPanelSource,"function Window:createFactionList", "function Window:setNote")
            +section(creatorPanelSource,"function Window:selected()", "function Window:openChooser")
            +section(creatorPanelSource,"function Window:selectCard", "function Window:openCargo")
            +section(creatorPanelSource,"function Window:openCargo", "-- The kind control")
            +section(creatorPanelSource,"function Window:onCycleSkill", "function Window:promptFor")
            +section(creatorPanelSource,"function Window:onNewFaction", "function Window:onRenameFaction")
            +section(creatorPanelSource,"function Window:onAddPerson", "function Window:commit")
            +section(creatorPanelSource,"local function descriptorChoices()", "function Window:onCycleSkill")
            +section(creatorPanelSource,"function Window:commit", "function Window:onKeyDown")
            +section(creatorPanelSource,"function Window:closePicker", "function Panel.restoreMainMenu")
            +section(creatorPanelSource,"function Panel.restoreMainMenu", "function Panel.previewSignature")
            +section(creatorPanelSource,"function Panel.previewSignature", "function Panel.open")
            +section(creatorPanelSource,"function Panel.open", "local SUB_SCREENS")
            +section(creatorPanelSource,"Picker.MAX_ROWS = 200", "function Picker:onRow")
            +section(creatorPanelSource,"function Picker:onRow", "-- The card grid")
            +section(creatorPanelSource,"local SUB_SCREENS", "function Panel.installMenuButton")
            +section(creatorPanelSource,"function Panel.installMenuButton", "local menuVisibilityTicks")
            +"return Window,Picker,Panel,syncButtonVisibility end";
        Path creatorUiPath=root.resolve("build/creator-pass-20261105/creator-ui-source.lua");
        Files.createDirectories(creatorUiPath.getParent());
        Files.writeString(creatorUiPath,creatorUiSource);
        runner.run("creator_ui_source",creatorUiSource);
        runner.run("creator_ui_flow",Files.readString(root.resolve("java/fixtures/creator-ui-flow.lua")));
        System.out.println("Creator inventory "+runner.run("creator_inventory_surfaces",
            Files.readString(root.resolve("java/fixtures/creator-inventory-surfaces.lua"))));
        Object openEvidence=runner.run("creator_open_evidence",
            Files.readString(root.resolve("java/fixtures/creator-open-evidence.lua")));
        Path evidencePath=root.resolve("build/creator-pass-20261105/creator-open-evidence.txt");
        Files.createDirectories(evidencePath.getParent());
        Files.writeString(evidencePath,String.valueOf(openEvidence));
        System.out.println("creator_open_evidence artifact="+evidencePath);
        System.out.println("creator_open_evidence summary="+String.valueOf(openEvidence));

        runner.run("creator_factions",Files.readString(root.resolve("java/fixtures/creator-factions.lua")));
        runner.run("creator_add_target",Files.readString(root.resolve("java/fixtures/creator-add-target.lua")));
        System.out.println("Creator population variety "+runner.run("creator_population_variety",
            Files.readString(root.resolve("java/fixtures/creator-population-variety.lua"))));
        System.out.println("Population unique names "+runner.run("population_unique_names",
            Files.readString(root.resolve("java/fixtures/population-unique-names.lua"))));
        runner.run("creator_slots",Files.readString(root.resolve("java/fixtures/creator-slots.lua")));
        runner.run("creator_layout",Files.readString(root.resolve("java/fixtures/creator-layout.lua")));
        runner.run("ui_fit_text",Files.readString(root.resolve("java/fixtures/ui-fit-text.lua")));
        runner.run("ui_value_row",Files.readString(root.resolve("java/fixtures/ui-value-row.lua")));
        runner.run("ui_stat_strip",Files.readString(root.resolve("java/fixtures/ui-stat-strip.lua")));
        runner.run("ui_empty_state",Files.readString(root.resolve("java/fixtures/ui-empty-state.lua")));
        runner.run("ui_footer_placements",Files.readString(root.resolve("java/fixtures/ui-footer-placements.lua")));
        runner.run("ui_columns",Files.readString(root.resolve("java/fixtures/ui-columns.lua")));
        runner.run("ui_timeline",Files.readString(root.resolve("java/fixtures/ui-timeline.lua")));
        runner.run("ui_table",Files.readString(root.resolve("java/fixtures/ui-table.lua")));
        runner.run("ui_cards",Files.readString(root.resolve("java/fixtures/ui-cards.lua")));
        runner.run("ui_sheet_material",Files.readString(root.resolve("java/fixtures/ui-sheet-material.lua")));
        runner.run("ui_chips",Files.readString(root.resolve("java/fixtures/ui-chips.lua")));
        String crewSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNotebook.lua"));
        runner.run("crew_responsive_source","crewLayoutFactory=function(FONT_HGT_SMALL,BUTTON_HGT,ISLabel)\nlocal UI_BORDER_SPACING=10\nlocal UILayout=KnoxSurvivorUILayout\nlocal CrewView={}\n"
            +"local UIFont={Small=1};local getTextManager=function() return {getFontHeight=function() return FONT_HGT_SMALL end,MeasureStringX=function(self,f,v) return #v*FONT_HGT_SMALL*0.55 end} end\n"
            +section(crewSource,"local function timelineTextLines(","local KnoxTimeline =")
            +section(crewSource,"local SCHEDULE_TOOLS = {","local SCHEDULE_COLORS = {")
            +section(crewSource,"local PRIORITY_COLUMNS = {","local PRIORITY_COLORS = {")
            +section(crewSource,"local PREF_HEADER_H =","function KnoxPrefTable:initialise()")
            +section(crewSource,"local function layoutCrewText(","function CrewView:drawEntry(")
            +"\nreturn CrewView, PRIORITY_COLUMNS, SCHEDULE_TOOLS, KnoxOrderCatalog.scheduleBlocks end");
        runner.run("crew_responsive_layout",Files.readString(root.resolve("java/fixtures/crew-responsive-layout.lua")));
        runner.run("schedule_readable_source", "scheduleReadableFactory=function(font,width)\n"
            +"local UILayout=KnoxSurvivorUILayout;local UIFont={Small=1};local getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(self,f,v) return #v*font*0.55 end} end\n"
            +"local ISPanel={};function ISPanel:derive() return setmetatable({}, {__index=self}) end; function ISPanel:setHeight(v) self.height=v end\n"
            +section(crewSource,"local function timelineTextLines(","local CrewView =")
            +"\nreturn setmetatable({width=width,height=1},{__index=KnoxTimeline}) end");
        runner.run("schedule_readable_layout",Files.readString(root.resolve("java/fixtures/schedule-readable-layout.lua")));
        runner.run("notebook_header_source", "notebookHeaderFactory=function(font)\nlocal UILayout=KnoxSurvivorUILayout;local UIFont={Small=1,Medium=2};local Window={}\n"
            +"local manager={getFontHeight=function(self,f) return f==2 and font+4 or font end,MeasureStringX=function(self,f,v) return #v*(f==2 and font+4 or font)*0.55 end}\n"
            +section(crewSource,"local function notebookHeaderLayout(","local inheritedTitleBarHeight =")
            +"local getTextManager=function() return manager end;"
            +section(crewSource,"function Window:layoutSheetHeader()", "local inheritedWindowRender")
            +"\nreturn function(width,name,detail,attention) return notebookHeaderLayout(width,name,detail,attention,manager) end,Window end");
        String installedTabs=Files.readString(Path.of(args[1]).resolve("media/lua/client/ISUI/ISTabPanel.lua"));
        runner.run("notebook_tabs_source", "notebookTabsFactory=function(font)\nlocal UILayout=KnoxSurvivorUILayout;local UIFont={Small=1};local ISTabPanel={}\n"
            +"function ISTabPanel:derive() return setmetatable({}, {__index=self}) end\n"
            +"local getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(self,f,v) return #v*font*0.55 end} end\n"
            +section(installedTabs,"function ISTabPanel:getTabX(","function ISTabPanel:setOnTabTornOff(")
            +section(crewSource,"local SheetTabs =","function Window:createChildren()")
            +"\nreturn SheetTabs end");
        runner.run("notebook_header_tabs",Files.readString(root.resolve("java/fixtures/notebook-header-tabs.lua")));
        runner.run("notebook_window_source","local Window={};local UILayout=KnoxSurvivorUILayout;"
            +section(crewSource,"-- Keep minimums font-relative,","function Window:onJoypadDown")
            +"NotebookWindow=Window");
        runner.run("notebook_attention_cadence",Files.readString(root.resolve("java/fixtures/notebook-attention-cadence.lua")));
        runner.run("notebook_resize",Files.readString(root.resolve("java/fixtures/notebook-resize.lua")));
        runner.run("ui_page_feedback_source", "uiPageFeedbackFactory=function(font)\nlocal UIFont={Small=1};local UI_BORDER_SPACING=10;local FONT_HGT_SMALL=font;local BUTTON_HGT=font+6;local ATTENTION_HEIGHT=16+font+4+(BUTTON_HGT+2)*3;local UILayout=KnoxSurvivorUILayout\n"
            +"local getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(self,f,v) return #v*font*0.55 end} end\n"
            +"local ISLabel={};function ISLabel:new(x,y,h,name,r,g,b,a) local o={x=x,y=y,height=h,name=name,r=r,g=g,b=b,a=a};function o:initialise() end;function o:setNameWithoutMoving(v) self.name=v end;function o:setX(v) self.x=v end;function o:setY(v) self.y=v end;function o:setHeight(v) self.height=v end;function o:setVisible(v) self.visible=v end;function o:getBottom() return self.y+self.height end;return o end\n"
            +"local BaseView={};local WorldView={};local StoresView={}\n"
            +section(crewSource,"local function layoutPageFeedback(","local ZONE_TYPES =")
            +section(crewSource,"function BaseView:layoutPage()","function BaseView:actionReason()")
            +section(crewSource,"function WorldView:layoutPage()","function WorldView:populate(")
            +section(crewSource,"function StoresView:layoutPage()","function StoresView:selectCategory(")
            +"\nreturn BaseView,WorldView,StoresView end");
        runner.run("ui_page_feedback",Files.readString(root.resolve("java/fixtures/ui-page-feedback.lua")));
        runner.run("card_detail_source", "cardDetailFactory=function(font)\nlocal UILayout=KnoxSurvivorUILayout;local UIFont={Small=1};local PADDING=10;local SECTION_GAP=8\n"
            +"local getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(self,f,v) return #v*font*0.55 end} end\n"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorCard.lua")),
                "local function drawCardText(","local function dayLabel(")
            +"\nreturn {text=drawCardText,detail=drawCardDetail,footer=placeCardButtons} end");
        runner.run("card_readable_details",Files.readString(root.resolve("java/fixtures/card-readable-details.lua")));
        String cardBindingSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorCard.lua"));
        runner.run("card_binding_source","cardBindingFactory=function(KnoxSurvivorViewModel,CompanionInventory)\n"
            +section(cardBindingSource,"local function companionSnapshot(","-- Vanilla (re)creates")
            +section(cardBindingSource,"local function cardCharacter(","local function ensureViews(")
            +"\nreturn companionSnapshot,cardCharacter end");
        runner.run("survivor_card_binding",Files.readString(root.resolve("java/fixtures/survivor-card-binding.lua")));
        String talkReadableSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInteractionUI.lua"));
        runner.run("talk_readable_source", "talkReadableFactory=function(font)\nlocal UILayout=KnoxSurvivorUILayout;local UIFont={Small=1};local PADDING=10;local ACTION_LIMIT=6;local Window={};local ISCollapsableWindowJoypad={prerender=function() end}\n"
            +"local getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(self,f,v) return #v*font*0.55 end} end\n"
            +section(talkReadableSource,"local function talkTextLayout(","function Window:createChildren()")
            +section(talkReadableSource,"function Window:layoutTalkText()","function Window:setCharacter(")
            +"\nWindow.drawTalkText=drawTalkText;return Window end");
        runner.run("talk_readable_feedback",Files.readString(root.resolve("java/fixtures/talk-readable-feedback.lua")));
        String tradeSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_TradeUI.lua"));
        runner.run("trade_readable_source", "tradeReadableFactory=function(font,stock)\n"
            +"local UILayout=KnoxSurvivorUILayout;local UIFont={Small=1};local getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(self,f,v) return #v*font*0.55 end} end\n"
            +"local KnoxTradeValuation={stock=function() return stock end};local Window={}\n"
            +section(tradeSource,"local function itemName(","function Window:createChildren()")
            +section(tradeSource,"function Window:refreshStock()","function Window:stopBrowsing(")
            +"\nreturn Window end");
        runner.run("trade_message_layout_source", "tradeMessageLayoutFactory=function(font)\n"
            +"local UILayout=KnoxSurvivorUILayout;local UIFont={Small=1};local PAD=10;local getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(self,f,v) return #v*font*0.55 end} end;local Window={}\n"
            +section(tradeSource,"local function itemName(","function Window:drawStock(")
            +section(tradeSource,"function Window:layoutTrade()","function Window:prerender()")
            +"\nreturn Window end");
        runner.run("trade_readable_layout",Files.readString(root.resolve("java/fixtures/trade-readable-layout.lua")));
        String pickerSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_BasePicker.lua"));
        runner.run("base_picker_layout_source","local BasePicker={}\nlocal Window={}\n"
            +section(pickerSource,"local PADDING =","local Window =")
            +section(pickerSource,"function Window:finish(","function Window:onJoypadDown(")
            +"\nbasePickerFixture={layout=pickerLayout,window=Window,owner=BasePicker}");
        runner.run("base_picker_layout",Files.readString(root.resolve("java/fixtures/base-picker-layout.lua")));
        String digestSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_ActivityFeed.lua"));
        runner.run("digest_window_layout_source","digestLayoutFactory=function(font,w,h)\n"
            +"local getCore=function() return {getScreenWidth=function() return w end,getScreenHeight=function() return h end} end\n"
            +"local getTextManager=function() return {getFontHeight=function() return font end} end\n"
            +"local UIFont={Small=1};local THEME=KnoxSurvivorUILayout.theme\n"
            +"local ISCollapsableWindow={}; function ISCollapsableWindow:derive() return setmetatable({}, {__index=self}) end; "
            +"function ISCollapsableWindow:new(x,y,width,height) return setmetatable({width=width,height=height},{__index=self}) end; "
            +"function ISCollapsableWindow:setTitle(t) self.title=t end; function ISCollapsableWindow:setResizable(v) self.resizable=v end\n"
            +section(digestSource,"local DIGEST_WIDTH =","local RAIL_WIDTH =")
            +section(digestSource,"local function digestPosition(","function DigestWindow:createChildren()")
            +"\nlocal win=DigestWindow:new(0,0); local x,y=digestPosition(win.width,win.height,w,h); return win,x,y end");
        runner.run("digest_window_layout",Files.readString(root.resolve("java/fixtures/digest-window-layout.lua")));
        String spectateSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_DevSpectate.lua"));
        runner.run("spectate_window_source", "spectateWindowFactory=function(layout,w,h)\n"
            +"local require=function(name) if name==\"KS_SurvivorUILayout\" then return layout end end\n"
            +"local getPlayerScreenWidth=function() return w end;local getPlayerScreenHeight=function() return h end\n"
            +"local ISCollapsableWindow={};function ISCollapsableWindow:new(x,y,width,height) return {x=x,y=y,width=width,height=height} end\n"
            +"function ISCollapsableWindow:setTitle(v) self.title=v end;function ISCollapsableWindow:setResizable(v) self.resizable=v end\n"
            +section(spectateSource,"require \"ISUI/ISCollapsableWindow\"","local Spectate =")
            +"local Window=setmetatable({},{__index=ISCollapsableWindow})\n"
            +section(spectateSource,"function Window:new(playerNum)","function Spectate.openBrowser")
            +"return Window:new(0) end");
        runner.run("spectate_window_layout",Files.readString(root.resolve("java/fixtures/spectate-window-layout.lua")));
        String filterSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorageFilterUI.lua"));
        runner.run("storage_filter_layout_source","storageFilterLayoutFactory=function(font)\n"
            +"local UIFont={Small=1};local getTextManager=function() return {getFontHeight=function() return font end,MeasureStringX=function(self,f,v) return #v*font*0.55 end} end\n"
            +"local UILayout=setmetatable({scaled=function(v) return math.floor(v*font/14) end},{__index=KnoxSurvivorUILayout})\n"
            +"local ISLabel={};function ISLabel:new(x,y,h,name) local o={x=x,y=y,height=h,name=name}; "
            +"function o:initialise() end;function o:setNameWithoutMoving(v) self.name=v end;function o:setX(v) self.x=v end;function o:setY(v) self.y=v end;function o:setHeight(v) self.height=v end;function o:setVisible(v) self.visible=v end;return o end\n"
            +"local ISCollapsableWindowJoypad={prerender=function() end};local FilterWindow={}\n"
            +section(filterSource,"function FilterWindow:applyModeLayout()","local function matchesDisplayCategory(")
            +"\nreturn FilterWindow end");
        runner.run("storage_filter_layout",Files.readString(root.resolve("java/fixtures/storage-filter-layout.lua")));
        String talkSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInteractionUI.lua"));
        runner.run("talk_viewport_source","local UILayout=KnoxSurvivorUILayout;"
            +section(talkSource,"local WINDOW_WIDTH =","local PADDING =")
            +section(talkSource,"local function interactionWindowSize(","function Window:new(")
            +"talkViewportSize=interactionWindowSize");
        runner.run("talk_viewport",Files.readString(root.resolve("java/fixtures/talk-viewport.lua")));




        runner.run("viewpoint_perspective",Files.readString(root.resolve("java/fixtures/viewpoint-perspective.lua")));
        runner.run("viewpoint_target_source", "local Compat={};local currentTarget=function() return nil end;"
            + section(Files.readString(root.resolve("mod/42/media/lua/client/KS_ViewpointCompatibility.lua")),
                "local function visibleSurvivor", "-- The aimed survivor")
            + section(Files.readString(root.resolve("mod/42/media/lua/client/KS_ViewpointCompatibility.lua")),
                "local function targetField", "local function directSurvivorActions")
            + "codecViewpointTarget=Compat;");
        runner.run("viewpoint_target",Files.readString(root.resolve("java/fixtures/viewpoint-target.lua")));

        Object highlightPalette=runner.run("KS_BaseHighlights",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseHighlights.lua")));
        table.getMethod("rawset",Object.class,Object.class)
            .invoke(environment,"KnoxBaseHighlights",highlightPalette);
        runner.run("zone_colours",Files.readString(root.resolve("java/fixtures/zone-colours.lua")));
        runner.run("base_highlight_picking",Files.readString(root.resolve("java/fixtures/base-highlight-picking.lua")));
        runner.run("base_highlight_render_source","zoneRenderFactory=function() local DRAFT_ALPHA=0.16;"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseZoneSelector.lua")),
                "local Selection = {}","-- Native area highlights expire")
            +"return hookTick,unhookTick end;territoryRenderFactory=function() "
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseTerritorySelector.lua")),
                "local Selection = {}","-- Native area highlights expire")
            +"return hookTick,unhookTick end");
        runner.run("base_highlight_render",Files.readString(root.resolve("java/fixtures/base-highlight-render.lua")));
        runner.run("KS_Settings",Files.readString(root.resolve("mod/42/media/lua/client/KS_Settings.lua")));
        verifySandboxDefaults(root);
        runner.run("sandbox_balance",Files.readString(root.resolve("java/fixtures/sandbox-balance.lua")));
        runner.run("survivor_strength_settings",Files.readString(root.resolve("java/fixtures/survivor-strength-settings.lua")));
        runner.run("base_roles",Files.readString(root.resolve("java/fixtures/base-roles.lua")));
        runner.run("KS_GroupScavenge",Files.readString(root.resolve("mod/42/media/lua/client/KS_GroupScavenge.lua")));
        runner.run("group_scavenge_roles",Files.readString(root.resolve("java/fixtures/group-scavenge-roles.lua")));
        runner.run("KS_CombatPositioning",Files.readString(root.resolve("mod/42/media/lua/client/KS_CombatPositioning.lua")));
        runner.run("combat_positioning",Files.readString(root.resolve("java/fixtures/combat-positioning.lua")));
        runner.run("guide_layout_source","local Guide={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivalGuide.lua")),
                "Guide.PAGES = {", "Guide.TEXT = table.concat")
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivalGuide.lua")),
                "function Guide.layoutPage", "local function installTextOnlyLayout")
            +"codecGuideLayout=Guide");
        runner.run("guide_layout",Files.readString(root.resolve("java/fixtures/guide-layout.lua")));
        Object missionController=runner.run("KS_SurvivorMissionController",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorMissionController.lua")));
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"codecMissionControllerModule",missionController);
        runner.run("mission_controller_require", "local fallback=require; require=function(name) "
            +"if name=='KS_SurvivorMissionController' then return codecMissionControllerModule end; "
            +"return fallback(name) end");
        Object controllerUpdates=runner.run("KS_SurvivorControllerUpdates",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorControllerUpdates.lua")));
        table.getMethod("rawset",Object.class,Object.class)
            .invoke(environment,"codecControllerUpdatesModule",controllerUpdates);
        runner.run("controller_update_require", "local fallback=require; require=function(name) "
            +"if name=='KS_SurvivorControllerUpdates' then return codecControllerUpdatesModule end; "
            +"return fallback(name) end");
        Object sharedMeal=runner.run("KS_SurvivorSharedMeal",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorSharedMeal.lua")));
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"codecSharedMealModule",sharedMeal);
        runner.run("shared_meal_require", "local fallback=require; require=function(name) "
            +"if name=='KS_SurvivorSharedMeal' then return codecSharedMealModule end; "
            +"return fallback(name) end");
        runner.run("KS_Controller",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")));
        runner.run("ambient_facing",Files.readString(root.resolve("java/fixtures/ambient-facing.lua")));
        String controllerTuneSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"));
        // The controller keeps its tuning in a file-local TUNE table. Snippets pulled out of it
        // below refer to TUNE fields, so expose the production values rather than copying them.
        Object controllerTune=runner.run("controller_tune_values",
            section(controllerTuneSource,"local TUNE = {","Controller.TUNING.THINK_JITTER_TICKS")+"\nreturn TUNE");
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"TUNE",controllerTune);
        runner.run("perception_phase_source",
            section(controllerTuneSource,"local function perceptionScanOffset", "local function carriedItemByType")
            +"codecPerceptionOffset=perceptionScanOffset");
        Object perceptionPhaseEvidence=runner.run("perception_phase_recovery",Files.readString(root.resolve("java/fixtures/perception-phase-recovery.lua")));
        System.out.println(perceptionPhaseEvidence);
        runner.run("controller_updates",Files.readString(root.resolve("java/fixtures/controller-updates.lua")));
        String glassAction=Files.readString(Path.of(args[1]).resolve("media/lua/shared/TimedActions/ISRemoveBrokenGlass.lua"));
        runner.run("native_glass_action_source", "nativeGlassActionFactory=function(ISBaseTimedAction) local ISRemoveBrokenGlass;\n"
            +glassAction+"\nreturn ISRemoveBrokenGlass end");
        runner.run("window_glass_action",Files.readString(root.resolve("java/fixtures/window-glass-action.lua")));

        runner.run("controller_state_handlers",Files.readString(root.resolve("java/fixtures/controller-state-handlers.lua")));
        runner.run("traversal_follow_recovery",Files.readString(root.resolve("java/fixtures/traversal-follow-recovery.lua")));
        runner.run("garage_door_obstacle",Files.readString(root.resolve("java/fixtures/garage-door-obstacle.lua")));
        runner.run("corner_obstacle_recovery",Files.readString(root.resolve("java/fixtures/corner-obstacle-recovery.lua")));
        runner.run("follow_door_regroup",Files.readString(root.resolve("java/fixtures/follow-door-regroup.lua")));
        runner.run("combat_pursuit_door",Files.readString(root.resolve("java/fixtures/combat-pursuit-door.lua")));
        runner.run("door_reach_recovery",Files.readString(root.resolve("java/fixtures/door-reach-recovery.lua")));
        runner.run("contact_proximity",Files.readString(root.resolve("java/fixtures/contact-proximity.lua")));
        runner.run("self_defense_range",Files.readString(root.resolve("java/fixtures/self-defense-range.lua")));
        runner.run("threat_priority",Files.readString(root.resolve("java/fixtures/threat-priority.lua")));
        runner.run("door_corner_recovery",Files.readString(root.resolve("java/fixtures/door-corner-recovery.lua")));
        runner.run("corner_sidestep",Files.readString(root.resolve("java/fixtures/corner-sidestep.lua")));
        runner.run("base_corner_movement",Files.readString(root.resolve("java/fixtures/base-corner-movement.lua")));
        runner.run("formation_cross_zone_refresh",Files.readString(root.resolve("java/fixtures/formation-cross-zone-refresh.lua")));
        runner.run("KS_ThreatClassifier",Files.readString(root.resolve("mod/42/media/lua/client/KS_ThreatClassifier.lua")));
        runner.run("bandit_disposition",Files.readString(root.resolve("java/fixtures/bandit-disposition.lua")));
        runner.run("companion_leash",Files.readString(root.resolve("java/fixtures/companion-leash.lua")));
        runner.run("human_hostility",Files.readString(root.resolve("java/fixtures/human-hostility.lua")));
        runner.run("combat_anchor_cache",Files.readString(root.resolve("java/fixtures/combat-anchor-cache.lua")));
        runner.run("world_population_guarantee_source","WorldPopulation={} "
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_WorldPopulation.lua")),
                "local GUARANTEED_CONTEXTS","local function openingRegionPlan"));
        runner.run("world_population_guarantee",Files.readString(root.resolve("java/fixtures/world-population-guarantee.lua")));
        String openingBudgetSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_WorldPopulation.lua"));
        runner.run("KS_WorldPopulation",openingBudgetSource);
        runner.run("population_spread",Files.readString(root.resolve("java/fixtures/population-spread.lua")));
        runner.run("opening_budget_source","openingBudgetFactory=function(b) local WorldPopulation=b.world;local KnoxSettings=b.settings;local KnoxPersistence=b.persistence;"
            +"local INITIAL_ALLOCATION_BATCH=24;local regionCounts=b.regionCounts;local allocateAtOrigin=b.allocate;local allocateOne=b.general;local formInitialGroups=b.groups;"
            +section(openingBudgetSource,"local openingPlanState,", "function WorldPopulation.maintain(")
            +" return maintainCore end");
        Object openingBudgetEvidence=runner.run("opening_budget",Files.readString(root.resolve("java/fixtures/opening-budget.lua")));
        Path openingBudgetPath=root.resolve("build/verification/opening-budget.json");
        Files.createDirectories(openingBudgetPath.getParent());
        Files.writeString(openingBudgetPath,String.valueOf(openingBudgetEvidence));

        runner.run("world_population_selection_source","WorldPopulation={} "
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_WorldPopulation.lua")),
                "function WorldPopulation.activationCandidateLess",
                "function WorldPopulation.activationCandidates"));
        runner.run("world_population_selection",Files.readString(root.resolve("java/fixtures/world-population-selection.lua")));
        runner.run("protected_method_source",
            section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "local safeMethod\n", "local function separatedByImmediateBarrier")
            +"codecSafeMethod=safeMethod");
        runner.run("protected_method_lookup",Files.readString(root.resolve("java/fixtures/protected-method-lookup.lua")));
        Object baseSafeHelper=runner.run("KS_SafeCall",Files.readString(root.resolve("mod/42/media/lua/shared/KS_SafeCall.lua")));
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"baseSafeHelper",baseSafeHelper);
        runner.run("base_safe_wrappers","baseSafeDispatch={}");
        String[][] baseSafeOwners={{"Compound","function Compound.detectRooms"},
            {"CorpseHandling","local function zoneBounds"},{"Farming","local function walkItems"},
            {"Repairs","local function instanceOf"},{"Woodcutting","local function walkItems"}};
        for (String[] owner:baseSafeOwners) {
            String source=Files.readString(root.resolve("mod/42/media/lua/client/KS_Base"+owner[0]+".lua"));
            runner.run("base_safe_"+owner[0],"do local KS_SafeCall=baseSafeHelper\n"
                +section(source,"local function safeCall(",owner[1])
                +"\nbaseSafeDispatch."+owner[0]+"=safeCall end");
        }
        runner.run("base_safe_dispatch",Files.readString(root.resolve("java/fixtures/base-safe-dispatch.lua")));
        runner.run("group_safe_source","do local KS_SafeCall=baseSafeHelper\n"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_GroupSupport.lua")),
                "local function safeCall(","local function needKind(")
            +"\ngroupSafeProbe={call=safeCall,walk=walk} end");
        runner.run("group_safe_dispatch",Files.readString(root.resolve("java/fixtures/group-safe-dispatch.lua")));
        String supportControllerSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua"));
        runner.run("group_support_receipt_source","local Controller={TUNING={GROUP_SUPPORT_RETRY_TICKS=30,GROUP_SUPPORT_COOLDOWN_TICKS=60}}; local THINK_MIN_TICKS=1;"
            +section(supportControllerSource,"local function hasPendingTimedActions", "local function sayDialogue")
            +"local function sayDialogue(...) codecSupportSpeech(...) end;"
            +section(supportControllerSource,"local function reservedByOther", "local function ambientSpotKey")
            +section(supportControllerSource,"function Controller:releaseGroupSupport", "function Controller:beginWindowDetour")
            +"codecSupportController=Controller;local Support={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_GroupSupport.lua")),
                "function Support.verify", "return Support")+"codecGroupSupportVerify=Support.verify");
        runner.run("group_support_receipt",Files.readString(root.resolve("java/fixtures/group-support-receipt.lua")));
        String storageCacheSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorage.lua"));
        runner.run("storage_cache_source","local Storage={policies=function() return {} end,resolvePolicy=function() return nil end}\n"
            +section(storageCacheSource,"local loadedContainerCache = {}","\nlocal MEDICAL_TYPES")+"\n"
            +section(storageCacheSource,"local function storageArea(base)","-- Transient, read-only migration")
            +"\nstorageCacheProbe={storage=Storage,cache=loadedContainerCache}");
        runner.run("storage_cache_retention",Files.readString(root.resolve("java/fixtures/storage-cache-retention.lua")));
        runner.run("storage_native_bounds",Files.readString(root.resolve("java/fixtures/storage-native-bounds.lua")));
        String relationSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorRelationships.lua"));
        runner.run("relationship_observation_source",
            "local Relationships={}\nlocal TAG='[fixture]'\nlocal AWARENESS_RADIUS=32\nlocal CAUTIOUS_APPROACH_RADIUS=20\nlocal pairStates={}\nlocal pendingMeetings={}\n"
            +section(relationSource,"local function availableForNpcSocial(","local function clamp(")
            +section(relationSource,"function Relationships.companySeeker(","local function resumeMeetingController(")
            +"\nrelationshipObservationProbe={relationships=Relationships,states=pairStates,meetings=pendingMeetings}");
        runner.run("relationship_observation_retention",Files.readString(root.resolve("java/fixtures/relationship-observation-retention.lua")));


        runner.run("KS_EquipmentIntelligence",Files.readString(root.resolve("mod/42/media/lua/client/KS_EquipmentIntelligence.lua")));
        runner.run("equipment_comfort",Files.readString(root.resolve("java/fixtures/equipment-comfort.lua")));
        runner.run("faction_uniform",Files.readString(root.resolve("java/fixtures/faction-uniform.lua")));
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
        runner.run("donor_bed_loan",Files.readString(root.resolve("java/fixtures/donor-bed-loan.lua")));
        runner.run("journey",Files.readString(root.resolve("java/fixtures/companion-journey.lua")));
        runner.run("hold_post",Files.readString(root.resolve("java/fixtures/hold-post.lua")));
        runner.run("contact_defense",Files.readString(root.resolve("java/fixtures/contact-defense.lua")));
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
            +"require=function(name) if name=='KS_SafeCall' then return baseSafeHelper end return rawget(_G,'KnoxSurvivorNames') or true end");
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
        runner.run("cold_perishable_filters",Files.readString(root.resolve("java/fixtures/cold-perishable-filters.lua")));
        runner.run("storage_fuel_routing",Files.readString(root.resolve("java/fixtures/storage-fuel-routing.lua")));
        runner.run("storage_summary_cache",Files.readString(root.resolve("java/fixtures/storage-summary-cache.lua")));
        runner.run("storage_capacity_overflow",Files.readString(root.resolve("java/fixtures/storage-capacity-overflow.lua")));
        runner.run("KS_EquipmentIntelligence",Files.readString(root.resolve("mod/42/media/lua/client/KS_EquipmentIntelligence.lua")));
        runner.run("role_kit",Files.readString(root.resolve("java/fixtures/role-kit.lua")));
        runner.run("storage_filter_common",Files.readString(root.resolve("java/fixtures/storage-filter-common.lua")));
        runner.run("base_supply_planner",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseSupplyPlanner.lua")));
        runner.run("item_stock_goals",Files.readString(root.resolve("java/fixtures/item-stock-goals.lua")));
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
        runner.run("weather_work",Files.readString(root.resolve("java/fixtures/weather-work.lua")));
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
        runner.run("KS_NightShelter",Files.readString(root.resolve("mod/42/media/lua/client/KS_NightShelter.lua")));
        runner.run("overnight_permission",Files.readString(root.resolve("java/fixtures/overnight-permission.lua")));
        runner.run("private_rest_boundary",Files.readString(root.resolve("java/fixtures/private-rest-boundary.lua")));
        runner.run("structural_alarm",Files.readString(root.resolve("java/fixtures/structural-alarm.lua")));
        runner.run("combat_human_positioning",Files.readString(root.resolve("java/fixtures/combat-human-positioning.lua")));
        runner.run("base_idle_musing",Files.readString(root.resolve("java/fixtures/base-idle-musing.lua")));
        runner.run("base_roster_fetch",Files.readString(root.resolve("java/fixtures/base-roster-fetch.lua")));
        runner.run("base_perimeter_defence",Files.readString(root.resolve("java/fixtures/base-perimeter-defence.lua")));
        runner.run("base_greet_integration",Files.readString(root.resolve("java/fixtures/base-greet-integration.lua")));
        runner.run("base_muse_integration",Files.readString(root.resolve("java/fixtures/base-muse-integration.lua")));
        runner.run("KS_SurvivorContextMenu",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorContextMenu.lua")));
        runner.run("base_roster_menu",Files.readString(root.resolve("java/fixtures/base-roster-menu.lua")));
        runner.run("combat_cover_geometry",Files.readString(root.resolve("java/fixtures/combat-cover-geometry.lua")));
        runner.run("combat_squad_cohesion",Files.readString(root.resolve("java/fixtures/combat-squad-cohesion.lua")));
        runner.run("combat_player_assist",
            "local Controller = {}\n"
            + section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "function Controller.threatEngagementRadius","local function withinZombieEngagement")
            + Files.readString(root.resolve("java/fixtures/combat-player-assist.lua")));
        runner.run("traversal_climb_choice",
            "local Traversal = (function()\n"
            + Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorTraversal.lua"))
            + "\nend)()\n"
            + Files.readString(root.resolve("java/fixtures/traversal-climb-choice.lua")));
        runner.run("text_fallback",
            "local originalTranslator = getText\n"
            + Files.readString(root.resolve("mod/42/media/lua/client/KS_Text.lua"))
            + Files.readString(root.resolve("java/fixtures/text-fallback.lua"))
            + "\nassert(getText == originalTranslator, 'translation fixture must restore the shared translator')");
        runner.run("creator_starters",
            "local Creator = (function()" + System.lineSeparator()
            + Files.readString(root.resolve("mod/42/media/lua/client/KS_Creator.lua"))
            + System.lineSeparator() + "end)()" + System.lineSeparator()
            + Files.readString(root.resolve("java/fixtures/creator-starters.lua")));
        runner.run("path_failure_source","local Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "-- PATH FAILURE CLASSIFICATION (pure)","-- END PATH FAILURE CLASSIFICATION")
            +"codecPathFailure=Controller;");
        runner.run("path_failure_classification",Files.readString(root.resolve("java/fixtures/path-failure-classification.lua")));
        runner.run("creator_items",
            "local Creator = (function()" + System.lineSeparator()
            + Files.readString(root.resolve("mod/42/media/lua/client/KS_Creator.lua"))
            + System.lineSeparator() + "end)()" + System.lineSeparator()
            + Files.readString(root.resolve("java/fixtures/creator-items.lua")));
        runner.run("combat_group_fight",Files.readString(root.resolve("java/fixtures/combat-group-fight.lua")));
        runner.run("combat_hostile_group",Files.readString(root.resolve("java/fixtures/combat-hostile-group.lua")));
        runner.run("combat_tick_formation",Files.readString(root.resolve("java/fixtures/combat-tick-formation.lua")));
        runner.run("group_follow_field",Files.readString(root.resolve("java/fixtures/group-follow-field.lua")));
        runner.run("combat_tick_drift",Files.readString(root.resolve("java/fixtures/combat-tick-drift.lua")));
        runner.run("military_admission",Files.readString(root.resolve("java/fixtures/military-admission.lua")));
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
        String storageSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorage.lua"));
        runner.run("military_outpost_source","militaryOutpostFactory=function(BaseManager) local function worldAge() return 50 end;"
            +"local function ensureFactionZones() end;local function ensureFactionStorage() end;local function ensureFactionBeds() end;"
            +section(baseManagerSource,"local function areaFromBuilding", "local function territoryAround")
            +section(baseManagerSource,"function BaseManager.ensureFactionBase(faction)", "function BaseManager.ensureFactionBases()")
            +" return BaseManager end");
        runner.run("military_command",Files.readString(root.resolve("java/fixtures/military-command.lua")));
        // Real siting slice (storageRoleAssigned/containerFitsFactionRole/ensureFactionStorage);
        // the cell, container key and persistence writer are fixture boundaries.
        runner.run("faction_siting_source","local BaseManager={};"
            +section(baseManagerSource,"local function storageRoleAssigned","local AUTO_BED_QUALITY")
            +"codecFactionSiting={ensure=ensureFactionStorage,BaseManager=BaseManager};");
        runner.run("faction_siting",Files.readString(root.resolve("java/fixtures/faction-siting.lua")));
        // Real knowledge predicate + real display filter; save store and faction
        // map are fixture boundaries.
        runner.run("faction_knowledge_source","local realP,realW=KnoxPersistence,WorldView;local P={};KnoxPersistence=P;"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_Persistence.lua")),
                "function KnoxPersistence.factionKnownToPlayer","function KnoxPersistence.bindFactionEventIdentity")
            +"local W={};WorldView=W;"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNotebook.lua")),
                "function WorldView.visibleFactions","function WorldView:populate")
            +"codecFactionKnowledge={P=P,W=W,realP=realP,realW=realW};");
        runner.run("faction_knowledge",Files.readString(root.resolve("java/fixtures/faction-knowledge.lua")));
        // Real theft staging; save root, lookups and relationship write are boundaries.
        runner.run("theft_warning_source","local realP=KnoxPersistence;local P={};KnoxPersistence=P;"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_Persistence.lua")),
                "function KnoxPersistence.recordPlayerFactionTheft","-- A faction's people share one accent")
            +"codecTheftWarning={P=P,realP=realP};");
        runner.run("theft_warning",Files.readString(root.resolve("java/fixtures/theft-warning.lua")));

        runner.run("base_layout_source","local BaseManager={};"
            +section(baseManagerSource,"BaseManager.ZONE_TYPES = {","local function worldAge()")
            +section(baseManagerSource,"function BaseManager.addZone","function BaseManager.containerReference")
            +section(baseManagerSource,"function BaseManager.containsSquare","function BaseManager.setTerritory")
            +section(baseManagerSource,"function BaseManager.containerReference","function BaseManager.setStorageFilters")
            +section(baseManagerSource,"-- BASE LAYOUT PROPOSAL (pure)","-- END BASE LAYOUT PROPOSAL")
            +"codecBaseLayout=BaseManager");
        runner.run("base_layout",Files.readString(root.resolve("java/fixtures/base-layout.lua")));
        runner.run("base_starter_establish_source","starterEstablishFactory=function(BaseManager,area) local function areaFromBuilding() return area end;"
            +"local function worldAge() return 12 end;local PLAYER_BASE_YARD_PADDING=0;local function territoryAround() return area end;"
            +"local function blockedBySurvivorSafehouse() return false end;"
            +section(baseManagerSource,"function BaseManager.establishPlayerBase", "-- Additional player base")
            +"return BaseManager.establishPlayerBase end");
        runner.run("base_starter_establish",Files.readString(root.resolve("java/fixtures/base-starter-establish.lua")));
        runner.run("base_storage_layout",Files.readString(root.resolve("java/fixtures/base-storage-layout.lua")));
        runner.run("KS_BaseCompound",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseCompound.lua")));
        runner.run("base_compound",Files.readString(root.resolve("java/fixtures/base-compound.lua")));
        // Real base membership + generator selection; loaded generators and Fluid
        // are fixture boundaries, the association/selection rule and petrol proof
        // are production.
        runner.run("base_generator_source","local BaseManager={};local Storage={};local Fluid={Petrol=\"Petrol\"};"
            +section(baseManagerSource,"function BaseManager.containsSquare","function BaseManager.setTerritory")
            +section(storageSource,"-- REAL PETROL PROOF (pure)","-- END REAL PETROL PROOF")
            +"codecBaseGenerator={base=BaseManager,storage=Storage};");
        runner.run("base_generator",Files.readString(root.resolve("java/fixtures/base-generator.lua")));
        runner.run("KS_BaseStorageDepot",storageSource);
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
            +section(baseManagerSource,"local function claimBedLive","local function bedReferenceKey")
            +section(baseManagerSource,"-- BASE BED ROSTER (pure)","-- END BASE BED ROSTER")
            +"codecBedRoster=BaseManager");
        runner.run("bed_roster_claims",Files.readString(root.resolve("java/fixtures/bed-roster-claims.lua")));
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
        runner.run("ammo_name_source","local ammoWord=codecAmmoWord;"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorViewModel.lua")),
                "-- AMMO NAME (projection)","-- END AMMO NAME")
            +"codecAmmoName=ammoName");
        runner.run("ammo_name",Files.readString(root.resolve("java/fixtures/ammo-name.lua")));
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
        Object waterLooting=runner.run("KS_SurvivorLooting",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorLooting.lua")));
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"codecWaterLooting",waterLooting);
        runner.run("mission_loot_priority",Files.readString(root.resolve("java/fixtures/mission-loot-priority.lua")));
        runner.run("vehicle_discovery_source",section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
            "local function findExploration", "-- (bounded follower-loot reach check")+"\n_G.codecVehicleDiscovery=findExploration");
        runner.run("vehicle_loot",Files.readString(root.resolve("java/fixtures/vehicle-loot.lua")));
        runner.run("settlement_supply_source",section(
            Files.readString(root.resolve("mod/42/media/lua/client/KS_GroupScavenge.lua")),
            "local function settlementSupplyNeeds", "local function isSupplyPartySettlement")
            +"codecSettlementSupplyNeeds=settlementSupplyNeeds");
        runner.run("settlement_supply_handoff",Files.readString(root.resolve("java/fixtures/settlement-supply-handoff.lua")));
        runner.run("KS_SurvivorExercise",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorExercise.lua")));
        String nativeActionQueue=Files.readString(Path.of(args[1]).resolve("media/lua/client/TimedActions/ISTimedActionQueue.lua"));
        runner.run("exercise_queue_source","function codecInstallExerciseQueue() ISTimedActionQueue={queues={}};"
            +section(nativeActionQueue,"function ISTimedActionQueue:addToQueue", "function ISTimedActionQueue:indexOf")
            +section(nativeActionQueue,"function ISTimedActionQueue:isCurrentActionAddingOtherActions", "ISTimedActionQueue.addAfter")+"end");
        runner.run("survivor_exercise",Files.readString(root.resolve("java/fixtures/survivor-exercise.lua")));
        runner.run("claimed_origin_source", "local WorldPopulation={};"
            +section(worldSource,"function WorldPopulation.firstSpawnUnclaimed", "function WorldPopulation.findFirstMaterializationSquare")
            +"codecClaimedOrigin=WorldPopulation");
        runner.run("claimed_property",Files.readString(root.resolve("java/fixtures/claimed-property.lua")));
        runner.run("stock_transfer_permission_source","local InventoryActions={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInventoryActions.lua")),
                "function InventoryActions.canTakeWorldStock", "local KnoxNpcInventoryTransferAction")
            +"codecStockPermission=InventoryActions");
        runner.run("stock_transfer_permission",Files.readString(root.resolve("java/fixtures/stock-transfer-permission.lua")));
        runner.run("household_origins",Files.readString(root.resolve("java/fixtures/household-origins.lua")));
        runner.run("county_origin_source","local WorldPopulation={};"+section(worldSource,"function WorldPopulation.laterOriginEligible", "local function firstUnusedOrigin")+section(worldSource,"local function stableHash", "local function sortedKeys")
            +section(worldSource,"local function firstUnusedOrigin", "local function chooseTravelOrigin")
            +section(worldSource,"local function chooseBalancedOrigin", "local function ensureOriginCapabilities")
            +section(worldSource,"function WorldPopulation.openingSocialCandidate", "local function formInitialGroups")
            +"codecCountyOrigins={next=firstUnusedOrigin,choose=chooseBalancedOrigin,eligible=WorldPopulation.laterOriginEligible,social=WorldPopulation.openingSocialCandidate}");
        runner.run("county_origins",Files.readString(root.resolve("java/fixtures/county-origins.lua")));
        runner.run("population_continuity",Files.readString(root.resolve("java/fixtures/population-continuity.lua")));
        runner.run("away_cargo_delivery",Files.readString(root.resolve("java/fixtures/away-cargo-delivery.lua")));
        runner.run("reset_looting","KnoxSurvivorLooting=nil");
        runner.run("KS_BaseStorage_by_label",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorage.lua")));
        runner.run("KS_BaseOrganize",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseOrganize.lua")));
        runner.run("base_floor_world_collector",Files.readString(root.resolve("java/fixtures/base-floor-world-collector.lua")));
        runner.run("base_supply_targets",Files.readString(root.resolve("java/fixtures/base-supply-targets.lua")));
        runner.run("settlement_storage_problems",Files.readString(root.resolve("java/fixtures/settlement-storage-problems.lua")));
        runner.run("base_organize_misfiled",Files.readString(root.resolve("java/fixtures/base-organize-misfiled.lua")));
        runner.run("unshelved_cargo_report",Files.readString(root.resolve("java/fixtures/unshelved-cargo-report.lua")));
        runner.run("overflow_deposit_wiring",Files.readString(root.resolve("java/fixtures/overflow-deposit-wiring.lua")));
        runner.run("KS_MissionTargets",Files.readString(root.resolve("mod/42/media/lua/client/KS_MissionTargets.lua")));
        runner.run("KS_VehicleNavigation",Files.readString(root.resolve("mod/42/media/lua/client/KS_VehicleNavigation.lua")));
        runner.run("KS_NpcVehicleTravel",Files.readString(root.resolve("mod/42/media/lua/client/KS_NpcVehicleTravel.lua")));
        runner.run("vehicle_fetch_order",Files.readString(root.resolve("java/fixtures/vehicle-fetch-order.lua")));
        runner.run("vehicle_claim_source",section(Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionVehicles.lua")),
            "local function recordAssignment", "local function startDrive")
            +"\n_G.codecRecordVehicleAssignment=recordAssignment;_G.codecReleaseVehicleAssignment=releaseAssignment");
        runner.run("vehicle_claim",Files.readString(root.resolve("java/fixtures/vehicle-claim.lua")));
        runner.run("vehicle_engine_start",Files.readString(root.resolve("java/fixtures/vehicle-engine-start.lua")));
        runner.run("KS_MapOrders",Files.readString(root.resolve("mod/42/media/lua/client/KS_MapOrders.lua")));
        runner.run("map_base_destination",Files.readString(root.resolve("java/fixtures/map-base-destination.lua")));
        runner.run("map_car_fetch_menu",Files.readString(root.resolve("java/fixtures/map-car-fetch-menu.lua")));
        runner.run("vehicle_approach",Files.readString(root.resolve("java/fixtures/vehicle-approach.lua")));
        runner.run("vehicle_surface_driving",Files.readString(root.resolve("java/fixtures/vehicle-surface-driving.lua")));
        runner.run("mission_dispatch_targets",Files.readString(root.resolve("java/fixtures/mission-dispatch-targets.lua")));
        runner.run("mission_area_dispatch",Files.readString(root.resolve("java/fixtures/mission-area-dispatch.lua")));
        runner.run("KS_Creator",Files.readString(root.resolve("mod/42/media/lua/client/KS_Creator.lua")));
        runner.run("creator_trait_codec",Files.readString(root.resolve("java/fixtures/creator-trait-codec.lua")));
        runner.run("creator_authored_capabilities",Files.readString(root.resolve("java/fixtures/creator-authored-capabilities.lua")));
        runner.run("creator_roster",Files.readString(root.resolve("java/fixtures/creator-roster.lua")));
        runner.run("creator_handover",Files.readString(root.resolve("java/fixtures/creator-handover.lua")));
        runner.run("creator_menu_button",Files.readString(root.resolve("java/fixtures/creator-menu-button.lua")));
        runner.run("creator_appearance",Files.readString(root.resolve("java/fixtures/creator-appearance.lua")));
        runner.run("KS_SurvivorStartingGear",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorStartingGear.lua")));
        runner.run("creator_bag_cargo",Files.readString(root.resolve("java/fixtures/creator-bag-cargo.lua")));
        runner.run("creator_bag_catalogue_source","local Creator={slotById=KnoxCreator.slotById,weaponCatalogue=KnoxCreator.weaponCatalogue};local SLOT_LOCATIONS={};local catalogueCache={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_Creator.lua")),"function Creator.slotCatalogue", "function Creator.slotOption")
            +"codecBagCatalogue=Creator.slotCatalogue");
        runner.run("creator_bag_catalogue",Files.readString(root.resolve("java/fixtures/creator-bag-catalogue.lua")));
        runner.run("creator_accessory_source","local Creator={slotById=KnoxCreator.slotById,weaponCatalogue=KnoxCreator.weaponCatalogue};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_Creator.lua")),"local SLOT_LOCATIONS =", "function Creator.slotOption")
            +"codecAccessoryCatalogue=Creator.slotCatalogue");
        System.out.println("Creator equipment preview "+runner.run("creator_equipment_preview",
            Files.readString(root.resolve("java/fixtures/creator-equipment-preview.lua"))));
        runner.run("creator_pack_items",Files.readString(root.resolve("java/fixtures/creator-pack-items.lua")));
        String autonomySource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomy.lua"));
        runner.run("KS_LifecyclePolicy",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorLifecyclePolicy.lua")));
        runner.run("unloaded_transient_expiry",Files.readString(root.resolve("java/fixtures/unloaded-transient-expiry.lua")));
        runner.run("active_controller_tick_source","activeControllerTickFactory=function(activeIds,controllers,hibernateRollbackPending,KnoxCompanionService) "
            +"local ticks=100;local KnoxSurvivorRuntime={unregister=function() end};local function removeActiveId() end;"
            +"local KnoxWorldPopulation={beginPopulationProfilePhase=function() return 0 end};"
            +"return function() "
            +section(autonomySource,"    local controllersStarted = KnoxWorldPopulation.beginPopulationProfilePhase()",
                "    KnoxWorldPopulation.endPopulationProfilePhase(\"active_controllers\"")
            +"end end");
        runner.run("culling_lifecycle_source","cullingFactory=function(b,KnoxSurvivorLifecyclePolicy) "
            +"local controllers,activeIds=b.controllers,b.ids;local KnoxPersistence=b.persistence;"
            +"local KnoxWorldPopulation=b.world;local KnoxSurvivorRuntime=b.runtime;local KnoxUnloadedSurvival=b.unloaded;"
            +"local hibernateRollbackPending,detachedGrace,recentlyDetached={},{},{};local ticks=0;local TAG='[fixture]';"
            +"local DETACHED_GRACE_CHECKS=3;local DETACHED_COMPANION_GRACE_CHECKS=10;"
            +section(autonomySource,"local HIBERNATION_INTERVAL_TICKS =", "local DEFAULT_ACTIVATION_DISTANCE")
            +"local function activeWorldLookup() return {} end;local function hibernationDistance() return 100 end;local function hibernationDistanceSquared() return 10000 end;"
            +"local function finiteNearestPlayerDistanceSquared(c) return b.world.nearestPlayerDistanceSquared(c:getCurrentSquare()) end;"
            +"local function actorXYZDescription() return 'actor' end;local function squareDescription() return 'square' end;"
            +"local function getGameTime() return {getWorldAgeHours=function() return 10 end} end;"
            +"local function removeActiveId(id) for i=#activeIds,1,-1 do if activeIds[i]==id then table.remove(activeIds,i) end end end;"
            +"local function prepareUnloadedResourceHandoff() return true end;"
            +section(autonomySource,"local function recognizedDetachedTransient", "local function prepareUnloadedResourceHandoff")
            +section(autonomySource,"local function hibernateDistantWorldSurvivors", "local function activateWorldCandidate")
            +"return function(at) ticks=at;return hibernateDistantWorldSurvivors(b.bridge,{}) end end");
        runner.run("culling_lifecycle",Files.readString(root.resolve("java/fixtures/culling-lifecycle.lua")));
        runner.run("creator_cargo_source","local Autonomy={};"
            +section(autonomySource,"function Autonomy.applyCreatorCargo", "local function createSurvivorAt")
            +"creatorApplyCargoProbe=Autonomy.applyCreatorCargo");
        runner.run("creator_runtime_policy",Files.readString(root.resolve("java/fixtures/creator-runtime-policy.lua")));
        runner.run("creator_doctor_aid",Files.readString(root.resolve("java/fixtures/creator-doctor-aid.lua")));
        runner.run("medical_help_order",Files.readString(root.resolve("java/fixtures/medical-help-order.lua")));

        runner.run("medical_aid_discovery",Files.readString(root.resolve("java/fixtures/medical-aid-discovery.lua")));
        runner.run("availability_source","local Autonomy={};KnoxSurvivorAutonomy=Autonomy;controllers={};"
            +section(autonomySource,"local LIVE_READY_STATES", "-- Creates the durable roster")
            +"local function canWatchMission() return false end;"
            +"local function dispatchAwayTeam(...) return codecDispatchBoundary(...) end;"
            +section(autonomySource,"local function awayTravelEtaHours", "-- A mission whose destination")
            +section(autonomySource,"local BASE_MISSION_TYPES = {","-- CompanionService calls this only after"));
        runner.run("mission_availability",Files.readString(root.resolve("java/fixtures/mission-availability.lua")));
        runner.run("duty_revision_stamp",Files.readString(root.resolve("java/fixtures/duty-revision-stamp.lua")));
        runner.run("mission_roles",Files.readString(root.resolve("java/fixtures/mission-roles.lua")));
        runner.run("mission_controller_handoff",Files.readString(root.resolve("java/fixtures/mission-controller-handoff.lua")));
        runner.run("away_return_casualty",Files.readString(root.resolve("java/fixtures/away-return-casualty.lua")));
        runner.run("mission_map_crew",Files.readString(root.resolve("java/fixtures/mission-map-crew.lua")));
        Object missionPrior=get.invoke(environment,"data");
        Object missionGraph=get.invoke(environment,"codecMissionGraph");
        ByteBuffer missionBytes=ByteBuffer.allocate(8*1024*1024);
        missionGraph.getClass().getMethod("save",ByteBuffer.class).invoke(missionGraph,missionBytes);
        missionBytes.flip();
        Object missionRestored=platform.getClass().getMethod("newTable").invoke(platform);
        missionRestored.getClass().getMethod("load",ByteBuffer.class,int.class).invoke(missionRestored,missionBytes,240);
        if(missionBytes.hasRemaining()) throw new AssertionError("Mission codec did not consume exact snapshot");
        set.invoke(environment,"data",missionRestored);
        runner.run("mission_reload","verifyMissionReload()");
        set.invoke(environment,"data",missionPrior);
        runner.run("mission_search_storage",Files.readString(root.resolve("java/fixtures/mission-search-storage.lua")));
        runner.run("mission_activation_source","codecMissionActivation=function(remaining,activeIds) "
            +"local candidates={};local bridge={};local players={};"
            +"local function activationDistance() return 100 end;"
            +"local function acceptsActivation() return true end;"
            +section(autonomySource,"    local activeLookup = {}", "    table.sort(candidates")
            +"return candidates end");
        runner.run("mission_activation",Files.readString(root.resolve("java/fixtures/mission-activation.lua")));
        runner.run("mission_ui_source","local MissionsView={};local UILayout=KnoxSurvivorUILayout;"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNotebook.lua")),
                "function MissionsView:drawEntry", "-- Empty is a state")
            +"codecMissionRow=MissionsView");
        runner.run("mission_ui_receiver",Files.readString(root.resolve("java/fixtures/mission-ui-receiver.lua")));
        Object missionComposer=runner.run("KS_MissionComposer",
            Files.readString(root.resolve("mod/42/media/lua/client/KS_MissionComposer.lua")));
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"codecMissionComposer",missionComposer);
        runner.run("mission_composer",Files.readString(root.resolve("java/fixtures/mission-composer.lua")));
        runner.run("mission_readable_layout",Files.readString(root.resolve("java/fixtures/mission-readable-layout.lua")));

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
        runner.run("resident_population_source","local WorldPopulation={};"
            +section(worldSource,"local VIRTUAL_LOCATION_ACTIVITIES = {", "local function coordinateKey")
            +section(worldSource,"local function playersFrom(options)", "function WorldPopulation.activationCandidateLess")
            +"codecResidentPopulation=WorldPopulation");
        runner.run("resident_capture_location",Files.readString(root.resolve("java/fixtures/resident-capture-location.lua")));
        runner.run("intent_travel_source","intentTravelFactory=function(KnoxPersistence) local WorldPopulation={};"
            +section(worldSource,"local ORIGIN_TRAVEL_SPEED =", "local ORIGIN_TRAVEL_RADIUS")
            +section(worldSource,"local function finite", "local function coordinateKey")
            +section(worldSource,"function WorldPopulation.advanceIntentTravel", "-- Shared coarse itinerary")
            +"return WorldPopulation end");
        String unloadedActivitySource=Files.readString(root.resolve("mod/42/media/lua/client/KS_UnloadedSurvival.lua"));
        runner.run("unloaded_activity_source","unloadedActivityFactory=function() "
            +section(unloadedActivitySource,"local MAX_STEP_HOURS =", "local function finite")
            +section(unloadedActivitySource,"local function areaDimensions", "local function nowHours")
            +section(unloadedActivitySource,"local function stableHash", "function Simulation.prepareBaseResidentForStorage")
            +section(unloadedActivitySource,"local function advanceWorldActivity", "local function advanceRestAndTravel")
            +"return advanceWorldActivity end");
        runner.run("offscreen_purpose_travel",Files.readString(root.resolve("java/fixtures/offscreen-purpose-travel.lua")));
        runner.run("true_location_restore",Files.readString(root.resolve("java/fixtures/true-location-restore.lua")));
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
        runner.run("firearm_safe_call", "require=function(name) if name=='KS_SafeCall' then return baseSafeHelper end return true end");
        runner.run("KS_FirearmSupport",Files.readString(root.resolve("mod/42/media/lua/client/KS_FirearmSupport.lua")));
        runner.run("firearm_inventory",Files.readString(root.resolve("java/fixtures/firearm-inventory-ownership.lua")));
        runner.run("firearm_hook_attempts",Files.readString(root.resolve("java/fixtures/firearm-hook-attempts.lua")));
        runner.run("firearm_efz",Files.readString(root.resolve("java/fixtures/firearm-efz-compat.lua")));
        runner.run("cooking_action_stub", "ISToggleStoveAction={derive=function(self,name) return {} end}");
        runner.run("KS_BaseCooking",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseCooking.lua")));
        runner.run("cooking_policy",Files.readString(root.resolve("java/fixtures/base-cooking-policy.lua")));
        runner.run("cooking_crossfloor_trip",Files.readString(root.resolve("java/fixtures/cooking-crossfloor-trip.lua")));
        runner.run("cooking_distant_trip",Files.readString(root.resolve("java/fixtures/cooking-distant-trip.lua")));
        runner.run("base_recipe_meal",Files.readString(root.resolve("java/fixtures/base-recipe-meal.lua")));
        runner.run("base_recipe_execution",Files.readString(root.resolve("java/fixtures/base-recipe-execution.lua")));
        runner.run("faction_transfer_allocation",Files.readString(root.resolve("java/fixtures/faction-transfer-allocation.lua")));
        runner.run("KS_FactionProperty",Files.readString(root.resolve("mod/42/media/lua/client/KS_FactionProperty.lua")));
        runner.run("verify_faction_transfer_allocation","runFactionTransferFixture()");
        String serviceSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua"));
        runner.run("base_sync_projection_source","syncProjectionFactory=function(b) local CompanionService={};local syncCache={};"
            +"local KnoxPersistence=b.persistence;local KnoxSettings=b.settings;"
            +"local function rawget(env,key) if key=='KnoxJavaBridge' then return b.bridge elseif key=='KnoxBaseManager' then return b.manager elseif key=='KnoxCompanionVehicles' then return b.vehicles end end;"
            +section(serviceSource,"function CompanionService.syncController", "local function currentPlayerPartyCharacters")
            +"return CompanionService,function(c) return syncCache[c] end end");
        runner.run("base_sync_work_budget",Files.readString(root.resolve("java/fixtures/base-sync-work-budget.lua")));
        System.out.println("Sync projection counts PASS "+String.valueOf(get.invoke(environment,"KS_SYNC_RECEIPT")));
        String awarenessSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_ZombieAwareness.lua"));
        runner.run("zombie_list_cache_source","local ZombieAwareness={};"
            +section(awarenessSource,"-- One cell zombie list per tick","-- End of the shared zombie list cache")
            +"KS_ZOMBIE_LIST=ZombieAwareness.zombieList");
        runner.run("zombie_list_cache",Files.readString(root.resolve("java/fixtures/zombie-list-cache.lua")));
        System.out.println("Zombie list cache PASS "+String.valueOf(get.invoke(environment,"KS_ZOMBIE_RECEIPT")));
        String perfNameplateSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNameplates.lua"));
        runner.run("nameplate_render_cost_source","local labels={};local COLORS={neutral={1,1,1}};"
            +"local function cameraMode() return \"iso\" end;"
            +"local function projectHead() return 100,100 end;"
            +"local function companyLine(c) if c==nil then return nil end return \"With Ana\" end;"
            +"local function finite(v) return type(v)==\"number\" end;"
            +"local function setVisible() end;"
            +"local drawnBuffer,drawnUsed={},0;"
            +"local Nameplates={};Nameplates.crowdedBy=function() return false end;"
            +"Nameplates.statusWord=function() return \"working\" end;"
            +section(perfNameplateSource,"function Nameplates.render()","function Nameplates.clear()")
            +"KS_RENDER=Nameplates.render;KS_LABELS=labels");
        runner.run("nameplate_render_cost",Files.readString(root.resolve("java/fixtures/nameplate-render-cost.lua")));
        System.out.println("Nameplate render cost PASS "+String.valueOf(get.invoke(environment,"KS_NAMEPLATE_RECEIPT")));
        runner.run("nameplate_pass_cost_source","local labels={};local tagged={};local taggedCount=0;"
            +"local COLORS={neutral={1,1,1},ally={0.25,0.86,0.34},hostile={0.92,0.18,0.18}};"
            +"local Nameplates={};local function fullName(id) return id end;"
            +section(perfNameplateSource,"function Nameplates.classify","function Nameplates.crowdedBy")
            +"KS_PASS=Nameplates.update;KS_PASS_STATE=function() return labels,taggedCount end");
        runner.run("nameplate_pass_cost",Files.readString(root.resolve("java/fixtures/nameplate-pass-cost.lua")));
        System.out.println("Nameplate pass cost PASS "+String.valueOf(get.invoke(environment,"KS_NAMEPLATE_PASS_RECEIPT")));
        String combatScenarioSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_CombatTestScenarios.lua"));
        runner.run("combat_ticker_lazy_source","KS_TICKER_ADDS=0;KS_TICKER_REMOVES=0;"
            +"local Events={OnTick={Add=function() KS_TICKER_ADDS=KS_TICKER_ADDS+1 end,"
            +"Remove=function() KS_TICKER_REMOVES=KS_TICKER_REMOVES+1 end}};"
            +section(combatScenarioSource,"local tickerInstalled = false\nlocal update\nlocal function installTicker()","local lastResult = nil")
            +"KS_TICKER_INSTALL=installTicker;KS_TICKER_REMOVE=removeTicker;"
            +"KS_TICKER_STATE=function() return tickerInstalled end");
        runner.run("combat_ticker_lazy",Files.readString(root.resolve("java/fixtures/combat-ticker-lazy.lua")));
        System.out.println("Combat ticker lazy PASS "+String.valueOf(get.invoke(environment,"KS_TICKER_RECEIPT")));
        runner.run("threat_pcall_source","local Controller={TUNING={NIGHT_SWEEP_RADIUS=10}};"
            +"local instanceof=function() return true end;"
            +"local distanceSquared=function() return 0 end;"
            +section(controllerSource,"local function isZombieThreat","local function navigationDistanceSquared")
            +section(controllerSource,"function Controller:isFacilityClearingTarget(threat)","local function withinDutyCombatLeash")
            +section(controllerSource,"function Controller:followerLeaderSquare()","-- Contact defence is never refused")
            +section(controllerSource,"local function withinZombieEngagement","-- Reservations are loaded-world leases")
            +"KS_CLEAR=function(s,t) return Controller.isFacilityClearingTarget(s,t) end;"
            +"KS_LEADER=function(s) return Controller.followerLeaderSquare(s) end;"
            +"KS_ENGAGE=withinZombieEngagement");
        runner.run("threat_pcall_budget",Files.readString(root.resolve("java/fixtures/threat-pcall-budget.lua")));
        System.out.println("Threat pcall budget PASS "+String.valueOf(get.invoke(environment,"KS_THREAT_PCALL_RECEIPT")));
        runner.run("shared_list_consumers_source","local Controller={};"
            +section(controllerSource,"local function nearbyRetreatThreats(self, radius)","local function nearbyAllyCount")
            +"KS_RETREAT=nearbyRetreatThreats;KS_STEALTH=shouldRemainStealthy");
        runner.run("KS_CombatPositioning_consumer",Files.readString(root.resolve("mod/42/media/lua/client/KS_CombatPositioning.lua")));
        runner.run("shared_list_consumers",Files.readString(root.resolve("java/fixtures/shared-zombie-consumers.lua")));
        System.out.println("Shared zombie consumers PASS "+String.valueOf(get.invoke(environment,"KS_SHARED_LIST_RECEIPT")));
        runner.run("tactics_readout_source","CompanionService={};"
            +section(serviceSource,"local TACTIC_DEFAULTS = {","function CompanionService.commonTactics")
            +section(serviceSource,"function CompanionService.commonTactics","local function playerPartyMemberIds")
            +"KnoxCompanionService=CompanionService");
        runner.run("KS_RadialOrders",Files.readString(root.resolve("mod/42/media/lua/client/KS_RadialOrders.lua")));
        runner.run("tactical_readout",Files.readString(root.resolve("java/fixtures/tactical-readout.lua")));
        runner.run("driving_service_gate_source","CompanionService={};"
            +section(serviceSource,"-- DRIVING SETTING GATE","-- END DRIVING SETTING GATE")
            +"KnoxCompanionService=CompanionService");
        runner.run("driving_service_gate",Files.readString(root.resolve("java/fixtures/driving-service-gate.lua")));
        runner.run("driving_order_gate",Files.readString(root.resolve("java/fixtures/driving-order-gate.lua")));
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
            +"local function worldAge() return 0 end\n"
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
        String safeCallStub="require=function(name) if name==[[KS_SafeCall]] then return {invoke=function(object,method,...) if object==nil or type(object[method])~=[[function]] then return nil end local ok,value=pcall(object[method],object,...) if ok then return value end return nil end} end return true end; ";
        runner.run("farming_intent_source",safeCallStub+Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseFarming.lua")));
        runner.run("farming_intent",Files.readString(root.resolve("java/fixtures/farming-intent.lua")));
        runner.run("farming_intent_receipt","assert(farmingPass==true)");
        System.out.println("Farming intent PASS "+String.valueOf(get.invoke(environment,"farmingReceipt"))+" nativeGameplay=false");
        runner.run("storage_priority_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseStorage.lua")));
        runner.run("storage_priority",Files.readString(root.resolve("java/fixtures/storage-priority-order.lua")));
        runner.run("storage_priority_receipt","assert(storagePriorityPass==true)");
        System.out.println("Storage priority PASS "+String.valueOf(get.invoke(environment,"storagePriorityReceipt"))+" nativeGameplay=false");
        runner.run("order_feedback_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseTaskBoard.lua")));
        runner.run("order_feedback",Files.readString(root.resolve("java/fixtures/order-feedback.lua")));
        runner.run("order_feedback_receipt","assert(orderFeedbackPass==true)");
        System.out.println("Order feedback PASS "+String.valueOf(get.invoke(environment,"orderFeedbackReceipt"))+" nativeGameplay=false");
        runner.run("depot_semantics",Files.readString(root.resolve("java/fixtures/depot-semantics.lua")));
        runner.run("depot_semantics_receipt","assert(depotPass==true)");
        System.out.println("Depot semantics PASS "+String.valueOf(get.invoke(environment,"depotReceipt"))+" nativeGameplay=false");
        String socialSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua"));
        runner.run("social_history_source","socialHistoryPrevious=CompanionService;"
            +"socialHistoryPreviousKnox=KnoxCompanionService;"
            +"KnoxCompanionService={};CompanionService=KnoxCompanionService;"
            +"CompanionService.standingReaction=function() return nil end;"
            +"CompanionService.hurtReaction=function() return nil end;"
            +section(socialSource,"-- Remembered history (2026-11-06)","function CompanionService.answerStanding"));
        runner.run("social_history",Files.readString(root.resolve("java/fixtures/social-history.lua")));
        runner.run("social_history_receipt","assert(socialHistoryPass==true)");
        runner.run("social_history_restore","CompanionService=socialHistoryPrevious;"
            +"KnoxCompanionService=socialHistoryPreviousKnox");
        System.out.println("Social history PASS "+String.valueOf(get.invoke(environment,"socialHistoryReceipt"))+" nativeGameplay=false");
        runner.run("share_reserve_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNeeds.lua")));
        runner.run("share_reserve",Files.readString(root.resolve("java/fixtures/share-reserve.lua")));
        runner.run("share_reserve_receipt","assert(shareReservePass==true)");
        System.out.println("Share reserve PASS "+String.valueOf(get.invoke(environment,"shareReserveReceipt"))+" nativeGameplay=false");
        runner.run("share_supplies",Files.readString(root.resolve("java/fixtures/share-supplies.lua")));
        runner.run("share_supplies_receipt","assert(shareSuppliesPass==true)");
        System.out.println("Share supplies PASS "+String.valueOf(get.invoke(environment,"shareSuppliesReceipt"))+" nativeGameplay=false");
        runner.run("talk_panel",Files.readString(root.resolve("java/fixtures/talk-panel.lua")));
        runner.run("KS_OffscreenStories",Files.readString(root.resolve("mod/42/media/lua/client/KS_OffscreenStories.lua")));
        runner.run("KS_SurvivorDialogue",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorDialogue.lua")));
        runner.run("combat_bark_entry_source", "combatBarkEntryFactory=function(self,target)\n"
            +"local awareness={}; local result=\"fixture\"\n"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "local function sayDialogue(","-- A task can enter")
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "    self:sampleCombatConfidence(false)", "    self:diag(\"combat\", \"combat_started\"")
            +"return targetKind end");
        runner.run("combat_bark_entry",Files.readString(root.resolve("java/fixtures/combat-bark-entry.lua")));
        runner.run("recognition_living",Files.readString(root.resolve("java/fixtures/recognition-living.lua")));
        runner.run("recognition_known_persistence",production);
        runner.run("recognition_known",Files.readString(root.resolve("java/fixtures/recognition-known.lua")));
        runner.run("recognition_undead_pressure_source",
            section(controllerSource,"local function isCorpseProxy(","require \"TimedActions/ISTimedActionQueue\"")
            +section(controllerSource,"local function distanceSquared(","local function navigationDistanceSquared(")
            +section(controllerSource,"local function zombiePressureAt(","function Controller.selectRoamCandidate")
            +"codecZombiePressure=zombiePressureAt");
        runner.run("recognition_undead",Files.readString(root.resolve("java/fixtures/recognition-undead.lua")));
        runner.run("witnessed_death_source","witnessedDeathFactory=function(activeIds,controllers,removeActiveId)\n"
            +"local TAG=\"[fixture]\"\n"
            +section(autonomySource,"local function dispatchWitnessedDeath(","local function retireDeadControllers(")
            +"return retireDeadSurvivor end");
        runner.run("witnessed_death",Files.readString(root.resolve("java/fixtures/witnessed-death.lua")));
        runner.run("native_evidence_source", "local Controller={};local function statusDestination() return \"fixture\" end\n"
            +section(controllerSource,"do\nlocal function nativeEvidence(self)","function Controller:canHibernateForDistance()")
            +"codecEvidenceStatus=Controller.status");
        runner.run("native_evidence",Files.readString(root.resolve("java/fixtures/native-evidence.lua")));
        runner.run("native_evidence_cadence_source","nativeEvidenceCadence=function(ticks,bridge,controllers,activeIds) local TAG=\"fixture\"; local STATUS_INTERVAL_TICKS=300\n"
            +section(autonomySource,"    if ticks % STATUS_INTERVAL_TICKS == 0 and KnoxSettings.showDeveloperDiagnostics() then", "\nend\n\nlocal function onGameStart()")
            +"\nend");
        runner.run("native_evidence_cadence",Files.readString(root.resolve("java/fixtures/native-evidence-cadence.lua")));
        Object corpseIdentityTable=platform.getClass().getMethod("newTable").invoke(platform);
        if (!KnoxNpcRegistry.tagCorpseSurvivorId(new FakeCorpseData(corpseIdentityTable), "r3b2-victim"))
            throw new AssertionError("Java corpse identity tag failed");
        table.getMethod("rawset",Object.class,Object.class).invoke(environment,"corpseIdentityTable",corpseIdentityTable);
        String corpseSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseCorpseHandling.lua"));
        runner.run("known_corpse_owner", "local require=function(name) return baseSafeHelper end\n" + corpseSource);
        runner.run("known_corpse",Files.readString(root.resolve("java/fixtures/known-corpse.lua")));
        String corpseUpdates=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorControllerUpdates.lua"));
        String admission=section(corpseUpdates,"                    if action == nil then\n                        self:failBaseTaskAction(ticks, \"corpse_queue:", "                if not self.character:getCharacterActions():isEmpty() then");
        admission=admission.substring(0,admission.lastIndexOf("                end"));
        runner.run("known_corpse_admission_source","corpseAdmission=function(self,action,actionResult,target,ticks)\n"+admission+"end");
        runner.run("known_corpse_admission",Files.readString(root.resolve("java/fixtures/known-corpse-admission.lua")));
        runner.run("combat_outcome_entry_source","combatOutcomeEntryFactory=function(self)\n"
            +section(controllerSource,"    self.activeDecision = \"fight\"\n    self.state = \"COMBAT\"", "    self:sampleCombatConfidence(false)")
            +"end");
        runner.run("combat_outcome",Files.readString(root.resolve("java/fixtures/combat-outcome.lua")));
        runner.run("recognition_player_service_source","local CompanionService={}\n"
            +section(serviceSource,"local TALK_GAIN =", "-- Search-style orders")
            +section(serviceSource,"local function displayName", "-- Read-only contact admission")
            +section(serviceSource,"local function hasPlayerAffiliation", "function CompanionService.askNeeds")
            +"recognitionTalkService=CompanionService");
        runner.run("recognition_player_talk",Files.readString(root.resolve("java/fixtures/recognition-player-talk.lua")));
        runner.run("dialogue_variation",Files.readString(root.resolve("java/fixtures/dialogue-variation.lua")));
        runner.run("talk_history_variation",Files.readString(root.resolve("java/fixtures/talk-history-variation.lua")));
        runner.run("truthful_recount",Files.readString(root.resolve("java/fixtures/truthful-recount.lua")));
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
        runner.run("radio_attempt_source","local TAG='[fixture]';"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomy.lua")),
                "local function baseHomeSquare", "local function createDeveloperSurvivor")
            +"codecRadioTick=checkRadioTowerArrivals");
        runner.run("radio_attempt_cadence",Files.readString(root.resolve("java/fixtures/radio-attempt-cadence.lua")));
        runner.run("radio_context_source","local BaseContextMenu={};local addRadioMenu;"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseContextMenu.lua")),
                "function BaseContextMenu.radioStatusText", "Events.OnFillWorldObjectContextMenu.Add")
            +"codecRadioContext=BaseContextMenu;codecAddRadioMenu=addRadioMenu");
        runner.run("radio_context_dispatch",Files.readString(root.resolve("java/fixtures/radio-context-dispatch.lua")));
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
        runner.run("job_material_search_source", "jobMaterialSearchFactory=function(search) "
            +"local Controller={}; local findSupply=search; local SUPPLY_RETRY_TICKS=60; "
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "function Controller:beginWorldSearch", "function Controller:beginWorldWaterAction")
            +" return Controller end");
        runner.run("job_material_needs",Files.readString(root.resolve("java/fixtures/job-material-needs.lua")));
        runner.run("base_rota_balance",Files.readString(root.resolve("java/fixtures/base-rota-balance.lua")));
        runner.run("base_roster_dispatch",Files.readString(root.resolve("java/fixtures/base-roster-dispatch.lua")));
        runner.run("KS_OrderSignals",Files.readString(root.resolve("mod/42/media/lua/client/KS_OrderSignals.lua")));
        runner.run("base_seated_musing",Files.readString(root.resolve("java/fixtures/base-seated-musing.lua")));
        runner.run("rota_duty_integration",Files.readString(root.resolve("java/fixtures/rota-duty-integration.lua")));
        runner.run("bed_shortage_source", "bedShortageFactory=function(clock) local BaseManager={}; "
            +"local function worldAge() return clock() end; "
            +section(baseManagerSource,"local AUTO_BED_QUALITY", "-- BASE BED ROSTER (pure)")
            +" return ensureFactionBeds,BaseManager end");
        runner.run("bed_shortage_notice",Files.readString(root.resolve("java/fixtures/bed-shortage-notice.lua")));
        runner.run("donor_bed_pickup",Files.readString(root.resolve("java/fixtures/donor-bed-pickup.lua")));
        runner.run("assigned_bed_removed",Files.readString(root.resolve("java/fixtures/assigned-bed-removed.lua")));
        runner.run("supply_intent_coherence",Files.readString(root.resolve("java/fixtures/supply-intent-coherence.lua")));
        Object supplyIntentPrior=get.invoke(environment,"data");
        Object supplyIntentGraph=get.invoke(environment,"supplyIntentGraph");
        ByteBuffer supplyIntentBytes=ByteBuffer.allocate(8*1024*1024);
        supplyIntentGraph.getClass().getMethod("save",ByteBuffer.class).invoke(supplyIntentGraph,supplyIntentBytes);
        supplyIntentBytes.flip();
        Object supplyIntentRestored=platform.getClass().getMethod("newTable").invoke(platform);
        supplyIntentRestored.getClass().getMethod("load",ByteBuffer.class,int.class).invoke(supplyIntentRestored,supplyIntentBytes,240);
        if(supplyIntentBytes.hasRemaining()) throw new AssertionError("Supply intent codec did not consume exact snapshot");
        set.invoke(environment,"data",supplyIntentRestored);
        runner.run("supply_intent_reload","verifySupplyIntentReload()");
        set.invoke(environment,"data",supplyIntentPrior);
        runner.run("capability_level_ups_source","local Capabilities={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorCapabilities.lua")),
                "-- LEVEL UPS (pure)","-- END LEVEL UPS")
            +"codecLevelUps=Capabilities");
        runner.run("capability_level_ups",Files.readString(root.resolve("java/fixtures/capability-level-ups.lua")));
        // Live 42.22.2 (f:5401/f:8701): the exposed character:applyTraits call
        // raised on return inside applyIdentity, aborting activation
        // mid-identity. The fixture drives the real production function through
        // a section load (same idiom as the controller TUNE/perception windows)
        // against a character whose applyTraits raises, and asserts fail-closed
        // refusal plus an unchanged clean-identity path.
        String capabilityIdentitySource=Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorCapabilities.lua"));
        runner.run("identity_apply_source",
            section(capabilityIdentitySource,"local function professionId","local function ranked")
                +section(capabilityIdentitySource,"local function findProfession","local function conflicts")
                +section(capabilityIdentitySource,"local function nutritionSnapshot","local function restoreSkills")
                +"\nknoxIdentityFunctions={applyIdentity=applyIdentity}");
        requireGlobals(environment,table,"identity_apply_traits_fail_closed","knoxIdentityFunctions");
        runner.run("identity_apply_traits_fail_closed",Files.readString(root.resolve("java/fixtures/identity-apply-traits-fail-closed.lua")));
        runner.run("text_wrap_source","local Layout={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorUILayout.lua")),
                "-- TEXT WRAP (pure)","-- END TEXT WRAP")
            +"codecTextWrap=Layout");
        runner.run("ui_text_wrap",Files.readString(root.resolve("java/fixtures/ui-text-wrap.lua")));
        runner.run("survivor_company",Files.readString(root.resolve("java/fixtures/survivor-company.lua")));
        runner.run("task_giveup",Files.readString(root.resolve("java/fixtures/task-giveup.lua")));
        // Kept last: it adds two survivor identities, and earlier fixtures assert
        // shared survivor counts. The needs rule and notice owner are real.
        runner.run("medical_maintenance_setup", "medicalPrior={Needs=KnoxSurvivorNeeds,Medical=KnoxMedicalActions,Supplies=KnoxMedicalSupplies,Bandage=ISApplyBandage,Disinfect=ISDisinfect};"
            +"KnoxSurvivorNeeds=nil;KnoxMedicalActions=nil;KnoxMedicalSupplies=nil;"
            +"local Base={};function Base:derive() return setmetatable({},{__index=self}) end;"
            +"function Base:new(character) return setmetatable({character=character},{__index=self}) end;"
            +"ISApplyBandage=Base;ISDisinfect=Base;ISSplint=Base;");
        runner.run("medical_supplies_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivalMedical.lua")));
        runner.run("medical_actions_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorMedicalActions.lua")));
        runner.run("medical_needs_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNeeds.lua")));
        runner.run("medical_maintenance",Files.readString(root.resolve("java/fixtures/medical-maintenance.lua")));
        runner.run("care_lifecycle",Files.readString(root.resolve("java/fixtures/care-lifecycle.lua")));
        runner.run("water_capacity_recovery",Files.readString(root.resolve("java/fixtures/water-capacity-recovery.lua")));
        runner.run("eat_capacity_recovery",Files.readString(root.resolve("java/fixtures/eat-capacity-recovery.lua")));
        runner.run("d3b_pantry_retrieval",Files.readString(root.resolve("java/fixtures/d3b-pantry-retrieval.lua")));
        runner.run("medical_capacity_recovery",Files.readString(root.resolve("java/fixtures/medical-capacity-recovery.lua")));
        runner.run("medical_bag_retrieval",Files.readString(root.resolve("java/fixtures/medical-bag-retrieval.lua")));
        runner.run("medical_disinfect_bag",Files.readString(root.resolve("java/fixtures/medical-disinfect-bag.lua")));
        runner.run("medical_splint_bag",Files.readString(root.resolve("java/fixtures/medical-splint-bag.lua")));
        runner.run("base_need_chatter",Files.readString(root.resolve("java/fixtures/base-need-chatter.lua")));
        runner.run("aided_dressing",Files.readString(root.resolve("java/fixtures/aided-dressing.lua")));
        runner.run("aided_splint",Files.readString(root.resolve("java/fixtures/aided-splint.lua")));
        runner.run("spoken_triage",Files.readString(root.resolve("java/fixtures/spoken-triage.lua")));
        runner.run("sleep_admission_source","local Needs={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNeeds.lua")),
                "-- SLEEP ADMISSION (pure)","-- END SLEEP ADMISSION")
            +"codecSleepNeed=Needs");
        runner.run("sleep_wake_source","local Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "-- SLEEP WAKE CLOCK (pure)","-- END SLEEP WAKE CLOCK")
            +"codecSleepWake=Controller");
        requireGlobals(environment,table,"sleep_admission","codecSleepNeed","codecSleepWake");
        runner.run("sleep_admission",Files.readString(root.resolve("java/fixtures/sleep-admission.lua")));
        runner.run("gap04_setup", "gapPrior={Support=KnoxGroupSupport,Inventory=KnoxInventoryActions,Transfer=ISInventoryTransferAction,Grab=ISGrabItemAction,Base=ISBaseTimedAction,Runtime=KnoxSurvivorRuntime};KnoxGroupSupport=nil;KnoxInventoryActions=nil;KnoxSurvivorRuntime=nil;local Base={};function Base:derive() return setmetatable({},{__index=self}) end;function Base:new(character) return setmetatable({character=character},{__index=self}) end;ISBaseTimedAction=Base;ISInventoryTransferAction=Base;function Base:isValid() return true end;function Base:transferItem(item) self.srcContainer:remove(item);self.destContainer:add(item) end;function Base:new(character,item,source,destination) return setmetatable({character=character,item=item,srcContainer=source,destContainer=destination},{__index=self}) end;");
        runner.run("order_contact_source","local CompanionService={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua")),
                "-- ORDER CONTACT (pure)","-- END ORDER CONTACT")
            +"codecOrderContact=CompanionService");
        requireGlobals(environment,table,"follow_contact","codecOrderContact");
        runner.run("follow_contact",Files.readString(root.resolve("java/fixtures/follow-contact.lua")));
        runner.run("self_splint",Files.readString(root.resolve("java/fixtures/self-splint.lua")));
        runner.run("base_repair_source","baseRepairPrior={Repairs=KnoxBaseRepairs};local Repairs={};"+section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseRepairs.lua")),"function Repairs.needsRepair","local function damaged")+"KnoxBaseRepairs=Repairs;");
        runner.run("base_repair_scan",Files.readString(root.resolve("java/fixtures/base-repair-scan.lua")));
        runner.run("KS_BaseEngineRepairs_benchmark",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseEngineRepairs.lua")));
        runner.run("base_engine_repair_order",Files.readString(root.resolve("java/fixtures/base-engine-repair-order.lua")));
        runner.run("base_repair_restore","KnoxBaseRepairs=baseRepairPrior.Repairs;baseRepairPrior=nil;");
        runner.run("water_choice_source","waterPrior={Needs=KnoxSurvivorNeeds};local Needs={};"+section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNeeds.lua")),"function Needs.betterWaterSource","local function isSmokeItem")+"KnoxSurvivorNeeds=Needs;");
        runner.run("water_source_choice",Files.readString(root.resolve("java/fixtures/water-source-choice.lua")));
        runner.run("water_choice_restore","KnoxSurvivorNeeds=waterPrior.Needs;waterPrior=nil;");
        runner.run("group_recruitment_source","groupPrior={Service=KnoxCompanionService};local CompanionService={};"+section(Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua")),"local function groupMemberIds","function CompanionService.canRecruit")+section(Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua")),"function CompanionService.admitGroup","-- What a resident says")+"KnoxCompanionService=CompanionService;");
        runner.run("group_recruitment",Files.readString(root.resolve("java/fixtures/group-recruitment.lua")));
        runner.run("group_recruitment_restore","KnoxCompanionService=groupPrior.Service;groupPrior=nil;");
        runner.run("settlement_capacity_source","capacityPrior={Owner=KnoxSettlementCapacity};"+section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SettlementCapacity.lua")),"local Capacity = rawget","Capacity.loaded = true")+"KnoxSettlementCapacity=Capacity;");
        runner.run("settlement_capacity",Files.readString(root.resolve("java/fixtures/settlement-capacity.lua")));
        runner.run("settlement_provisions",Files.readString(root.resolve("java/fixtures/settlement-provisions.lua")));
        runner.run("settlement_provisions_receipt","assert(provisionPass==true,'GH2 fixture stopped before its completion marker')");
        Object provisionGraph=get.invoke(environment,"data");
        ByteBuffer provisionBytes=ByteBuffer.allocate(8*1024*1024);
        provisionGraph.getClass().getMethod("save",ByteBuffer.class).invoke(provisionGraph,provisionBytes);
        provisionBytes.flip();
        Object provisionRestored=platform.getClass().getMethod("newTable").invoke(platform);
        provisionRestored.getClass().getMethod("load",ByteBuffer.class,int.class).invoke(provisionRestored,provisionBytes,240);
        if(provisionBytes.hasRemaining()) throw new AssertionError("Provision codec did not consume exact snapshot");
        set.invoke(environment,"data",provisionRestored);
        runner.run("settlement_provisions_codec","verifyProvisionsCodec()");
        System.out.println("Settlement provisions GH2 PASS "+String.valueOf(get.invoke(environment,"provisionReceipt"))+" nativeGameplay=false");
        runner.run("capacity_gate_source", "capacityGateFactory=function(BaseManager,area) local AUTO_BED_QUALITY={goodBed=5,averageBed=4,badBed=2};"
            +section(baseManagerSource,"local function discoverFactionBeds", "local function ensureFactionBeds")
            +"local function areaFromBuilding() return area end; local function worldAge() return 12 end; local PLAYER_BASE_YARD_PADDING=0; local function territoryAround() return area end; local function blockedBySurvivorSafehouse() return false end;"
            +section(baseManagerSource,"function BaseManager.establishOutpost", "function BaseManager.movePlayerBase")
            +"return BaseManager end");
        runner.run("capacity_gate",Files.readString(root.resolve("java/fixtures/capacity-gate.lua")));
        runner.run("promotion_transaction",Files.readString(root.resolve("java/fixtures/promotion-transaction.lua")));
        runner.run("settlement_capacity_restore","KnoxSettlementCapacity=capacityPrior.Owner;capacityPrior=nil;");
        runner.run("gap04_runtime_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorRuntime.lua")));
        runner.run("floor_grab_native_boundary",Files.readString(root.resolve("java/fixtures/floor-grab-native-boundary.lua")));
        runner.run("gap04_inventory_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInventoryActions.lua")));
        runner.run("donor_property_pickup",Files.readString(root.resolve("java/fixtures/donor-property-pickup.lua")));
        // Live 42.22.2 (f:5791/f:14326): the timed-action add path raised on
        // return at ISBaseTimedAction.begin:88. Inside this gap04 scope the
        // real InventoryActions module is loaded against the Base action
        // stubs; the fixture stubs ISTimedActionQueue.add with a raise and
        // asserts the existing <kind>_queue_refused refusal contract, plus an
        // unchanged normal-admission passthrough.
        runner.run("inventory_queue_admission_raise",Files.readString(root.resolve("java/fixtures/inventory-queue-admission-raise.lua")));
        runner.run("gap04_support_source","local KS_SafeCall=baseSafeHelper;"+section(Files.readString(root.resolve("mod/42/media/lua/client/KS_GroupSupport.lua")),"local Support =", "return Support"));
        runner.run("gap04_offer",Files.readString(root.resolve("java/fixtures/gap04-cigarette-offer.lua")));
        runner.run("shared_meal",Files.readString(root.resolve("java/fixtures/shared-meal.lua")));
        runner.run("base_hygiene_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseHygiene.lua")));
        runner.run("base_surface_cleaning",Files.readString(root.resolve("java/fixtures/base-surface-cleaning.lua")));
        runner.run("player_care_setup","careSourcePrior={Service=KnoxCompanionService,Events=Events};KnoxCompanionService=nil;Events=nil;");
        runner.run("player_care_service",Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua")));
        runner.run("player_care_standing",Files.readString(root.resolve("java/fixtures/player-care-standing.lua")));
        runner.run("depot_placement",Files.readString(root.resolve("java/fixtures/depot-placement.lua")));
        runner.run("floor_haul",Files.readString(root.resolve("java/fixtures/floor-haul.lua")));
        System.out.println("Floor haul S3a PASS "+String.valueOf(get.invoke(environment,"floorHaulReceipt"))+" nativeGameplay=false");
        runner.run("gap04_restore", "KnoxGroupSupport=gapPrior.Support;KnoxInventoryActions=gapPrior.Inventory;ISInventoryTransferAction=gapPrior.Transfer;ISGrabItemAction=gapPrior.Grab;ISBaseTimedAction=gapPrior.Base;KnoxSurvivorRuntime=gapPrior.Runtime;gapPrior=nil;");
        runner.run("medical_maintenance_restore", "KnoxSurvivorNeeds=medicalPrior.Needs;KnoxMedicalActions=medicalPrior.Medical;KnoxMedicalSupplies=medicalPrior.Supplies;"
            +"ISApplyBandage=medicalPrior.Bandage;ISDisinfect=medicalPrior.Disinfect;medicalPrior=nil;");
        // The home-defence assignment is a marked pure section of the base
        // owner, so the fixture drives the production decision rather than a copy.
        runner.run("home_defence_source","local BaseManager={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseManager.lua")),
                "-- HOME DEFENCE ASSIGNMENT (pure)","-- END HOME DEFENCE ASSIGNMENT")
            +"codecDefence=BaseManager");
        // Runs here because it allocates survivors, bases and factions, and the
        // earlier fixtures assert shared survivor counts. All of it is real
        // persistence state in the scratch ModData root.
        runner.run("group_kind_behaviour",Files.readString(root.resolve("java/fixtures/group-kind-behaviour.lua")));
        runner.run("death_cause_needs_source","local Needs={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorNeeds.lua")),
                "function Needs.snapshot","function Needs.isNeedCurrent")
            +"codecDeathNeeds=Needs");
        // Earlier fixtures install their own notice stub and do not put the real
        // module back, so the owner is restored before this fixture captures it.
        runner.run("KS_ActivityFeed",Files.readString(root.resolve("mod/42/media/lua/client/KS_ActivityFeed.lua")));
        requireGlobals(environment,table,"death_cause","codecDeathNeeds","KnoxActivityFeed","KnoxPersistence");
        runner.run("death_cause",Files.readString(root.resolve("java/fixtures/death-cause.lua")));
        runner.run("group_home_looting",Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorLooting.lua")));
        runner.run("group_home_scout_source",Files.readString(root.resolve("mod/42/media/lua/client/KS_FactionBaseScouting.lua")));
        runner.run("group_home_permission_source","local Controller={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "function Controller:onGroupHomeRevoked", "function Controller:onDutyChanged")
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "function Controller:releaseTransferActions", "function Controller:completeRobbery")
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorAutonomyController.lua")),
                "function Controller:releaseSupplyCollection", "-- Selection owns a trip")
            +"codecGroupHomeController=Controller;local CompanionService={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_CompanionService.lua")),
                "local function groupMemberIds", "function CompanionService.canRecruit")
            +"codecGroupHomeRecruit=CompanionService;"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_GroupScavenge.lua")),
                "local function belongsToSettlement", "local function readyForSortie")
            +"codecGroupHomePermissions={belongsToSettlement=belongsToSettlement,leaseAuthorized=leaseAuthorized};");
        runner.run("group_home",Files.readString(root.resolve("java/fixtures/group-home.lua")));
        for(int pass=0;pass<2;pass++) {
            Object groupGraph=get.invoke(environment,"data");
            ByteBuffer groupBytes=ByteBuffer.allocate(8*1024*1024);
            groupGraph.getClass().getMethod("save",ByteBuffer.class).invoke(groupGraph,groupBytes);
            groupBytes.flip();
            Object groupRestored=platform.getClass().getMethod("newTable").invoke(platform);
            groupRestored.getClass().getMethod("load",ByteBuffer.class,int.class).invoke(groupRestored,groupBytes,240);
            if(groupBytes.hasRemaining()) throw new AssertionError("Group home codec did not consume exact snapshot");
            set.invoke(environment,"data",groupRestored);
            runner.run("group_home_reload_source",production);
            runner.run("group_home_codec","verifyGroupHomeCodec()");
        }
        runner.run("group_home_finish","finishGroupHomeCodec()");
        runner.run("group_home_receipt","assert(groupHomePass==true,'GH1 fixture stopped before its completion marker')");
        // P1/P5: a streamed-in settlement seeds the real discovery once and reports
        // the return through the existing feed. Marked pure section, so the fixture
        // drives production code rather than a copy.
        runner.run("base_stream_in_source","local BaseJobs={};"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseJobs.lua")),
                "-- STREAM-IN DISCOVERY (pure)","-- END STREAM-IN DISCOVERY")
            +"codecBaseStreamIn=BaseJobs");
        runner.run("base_stream_in",Files.readString(root.resolve("java/fixtures/base-stream-in.lua")));
        // P3: a group home staffs itself from its own roster on stream-in through
        // the admission owner the loaded path already uses. The real section is
        // extracted here so the fixture drives production code, not a copy.
        runner.run("group_home_staffing_source","local BaseManager={};"
            +"local worldAge=function() return 20 end;"
            +"KnoxSettings={autoGenerateBaseWorkAreas=function() return false end};"
            +"ensureFactionZones=function() end;ensureFactionStorage=function() end;ensureFactionBeds=function() end;"
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseManager.lua")),
                "-- Unpromoted homes share ordinary zones","function BaseManager.ensureFactionBases()")
            +"codecGroupStaffing=BaseManager");
        runner.run("group_home_staffing",Files.readString(root.resolve("java/fixtures/group-home-staffing.lua")));
        // P2: stored-material labour has its own predicate. canAdvanceOffscreen
        // stays watch-only because its result gates the return walk.
        String dutySource=Files.readString(root.resolve("mod/42/media/lua/client/KS_BaseDutySimulation.lua"));
        int dutyCut=dutySource.lastIndexOf("return Duty");
        if(dutyCut<0) throw new IllegalStateException("the base duty simulation no longer ends with return Duty");
        runner.run("base_duty_labor_source",dutySource.substring(0,dutyCut)+"codecDutyLabor=Duty");
        runner.run("base_duty_labor",Files.readString(root.resolve("java/fixtures/base-offscreen-labor.lua")));
        String unloadedSource=Files.readString(root.resolve("mod/42/media/lua/client/KS_UnloadedSurvival.lua"));
        if(!unloadedSource.contains("KnoxBaseDutySimulation.advanceLabor("))
            throw new IllegalStateException("the off-screen labour predicate is not wired into advanceWorldActivity");
        if(!unloadedSource.contains("if not security and KnoxBaseDutySimulation.advanceLabor ~= nil then"))
            throw new IllegalStateException("off-screen labour is not guarded against the watch/return predicate");
        runner.run("group_home_gh3_capacity",Files.readString(root.resolve("mod/42/media/lua/client/KS_SettlementCapacity.lua")));
        runner.run("group_home_gh3",Files.readString(root.resolve("java/fixtures/group-home-gh3.lua")));
        Object gh3Graph=get.invoke(environment,"data");
        ByteBuffer gh3Bytes=ByteBuffer.allocate(8*1024*1024);
        gh3Graph.getClass().getMethod("save",ByteBuffer.class).invoke(gh3Graph,gh3Bytes);
        gh3Bytes.flip();
        Object gh3Restored=platform.getClass().getMethod("newTable").invoke(platform);
        gh3Restored.getClass().getMethod("load",ByteBuffer.class,int.class).invoke(gh3Restored,gh3Bytes,240);
        if(gh3Bytes.hasRemaining()) throw new AssertionError("GH3 codec did not consume exact snapshot");
        set.invoke(environment,"data",gh3Restored);
        runner.run("group_home_gh3_codec","verifyGroupHomeTransferCodec()");
        runner.run("group_home_gh3_receipt","assert(gh3Pass==true and gh3Pass~=nil)");
        System.out.println("Group home GH3 PASS "+String.valueOf(get.invoke(environment,"gh3Receipt"))+" nativeGameplay=false");
        runner.run("group_home_gh3_feedback","assert(gh3FeedbackPass==true)");
        System.out.println("Group home GH3 feedback PASS "+String.valueOf(get.invoke(environment,"gh3FeedbackReceipt"))+" nativeGameplay=false");
        System.out.println("Group home GH1 PASS actualClaim=true residency=true defense=true stock=true leaseRevocation=true unrelatedQueue=true singletonCodecPasses=2 lastDeathLogicalOnly=true companionRefused=true nativeGameplay=false");
        runner.run("KS_SurvivorRelationships_full",relationSource);
        runner.run("solo_visible_company",Files.readString(root.resolve("java/fixtures/solo-visible-company.lua")));
        runner.run("group_spawn_link",Files.readString(root.resolve("java/fixtures/group-spawn-link.lua")));
        runner.run("scavenge_rota_integration",Files.readString(root.resolve("java/fixtures/scavenge-rota-integration.lua")));
        runner.run("bed_craft_source", "bedCraftActionsFactory=function() local InventoryActions={}; "
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInventoryActions.lua")),
                "function InventoryActions.canTakeWorldStock", "-- One native world-object grab")
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInventoryActions.lua")),
                "-- One native world-object grab", "local KnoxNpcSearchContainerAction")
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInventoryActions.lua")),
                "function KnoxNpcInventoryTransferAction:startActionAnim", "-- Native admission returns")
            +section(Files.readString(root.resolve("mod/42/media/lua/client/KS_SurvivorInventoryActions.lua")),
                "local function admitAction", "function InventoryActions.queueSearch")
            +" return InventoryActions end");
        runner.run("bed_craft_manager_source", "bedCraftManagerFactory=function(clock) local BaseManager={}; local function worldAge() return clock() end; "
            +section(baseManagerSource,"local AUTO_BED_QUALITY", "-- BASE BED ROSTER (pure)")
            +section(baseManagerSource,"function BaseManager.containsSquare", "function BaseManager.setTerritory")
            +section(baseManagerSource,"local function meetsRequirements", "-- BASE LAYOUT PROPOSAL (pure)")
            +" return BaseManager,ensureFactionBeds end");
        runner.run("bed_craft",Files.readString(root.resolve("java/fixtures/bed-craft.lua")));
        // Real per-tick cost: the production Controller:tick over a fixed survivor and
        // zombie population. Setup and warmup are outside the timed window; every mode
        // runs the identical scenario on the source under test.
        runner.run("KS_ZombieAwareness_benchmark",Files.readString(root.resolve("mod/42/media/lua/client/KS_ZombieAwareness.lua")));
        runner.run("tick_cost_benchmark",Files.readString(root.resolve("java/fixtures/tick-cost-benchmark.lua")));
        for (String benchMode : new String[]{"floor","scan","scan_solo","scan_solo_far","scan_empty","movement","full"}) {
            String benchmarkSetup="KS_BENCH_SETUP('"+benchMode+"')";
            runner.run("benchmark_setup_"+benchMode,benchmarkSetup);
            runner.run("benchmark_warmup_"+benchMode,"KS_BENCH_RUN(60)");
            runner.run("benchmark_reset_"+benchMode,benchmarkSetup);
            long benchmarkStarted=System.nanoTime();
            Object benchmarkTicks=runner.run("benchmark_"+benchMode,"return KS_BENCH_RUN(240)");
            long benchmarkNs=System.nanoTime()-benchmarkStarted;
            long benchmarkCount=((Number)benchmarkTicks).longValue();
            System.out.println("Tick benchmark PASS mode="+benchMode+" ticks="+benchmarkCount
                +" elapsedMs="+String.format(java.util.Locale.ROOT,"%.3f",benchmarkNs/1_000_000.0)
                +" nsPerTick="+String.format(java.util.Locale.ROOT,"%.1f",(double)benchmarkNs/benchmarkCount));
            runner.run("benchmark_report_"+benchMode,"KS_BENCH_REPORT()");
        }
        runner.run("benchmark_restore","KS_BENCH_RESTORE()");
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

    private static void verifySandboxDefaults(Path root) throws java.io.IOException {
        String options=Files.readString(root.resolve("mod/42/media/sandbox-options.txt"));
        String settings=Files.readString(root.resolve("mod/42/media/lua/client/KS_Settings.lua"));
        java.util.Map<String,String> shipped=new java.util.LinkedHashMap<>();
        java.util.regex.Matcher entry=java.util.regex.Pattern.compile(
            "option[ ]+KnoxSurvivors[.]([A-Za-z0-9_]+)[ ]*=[ ]*[{]([^}]*)[}]",
            java.util.regex.Pattern.DOTALL).matcher(options);
        while(entry.find()){
            String name=entry.group(1), body=entry.group(2);
            java.util.regex.Matcher def=java.util.regex.Pattern.compile(
                "default[ ]*=[ ]*([A-Za-z0-9_-]+)").matcher(body);
            if(!def.find()) throw new AssertionError("sandbox defaults: "+name+" has no default");
            if(shipped.put(name,def.group(1))!=null)
                throw new AssertionError("sandbox defaults: duplicate option "+name);
            java.util.regex.Matcher kind=java.util.regex.Pattern.compile(
                "type[ ]*=[ ]*([A-Za-z]+)").matcher(body);
            String type=kind.find()?kind.group(1):"?";
            if("integer".equals(type)){
                int min=intOption(body,"min"), max=intOption(body,"max");
                int value=Integer.parseInt(def.group(1));
                if(value<min||value>max) throw new AssertionError(
                    "sandbox defaults: "+name+"="+value+" outside schema range "+min+".."+max);
            }else if("enum".equals(type)){
                int count=intOption(body,"numValues"), value=Integer.parseInt(def.group(1));
                if(value<1||value>count) throw new AssertionError(
                    "sandbox defaults: "+name+"="+value+" outside enum 1.."+count);
            }
        }
        if(shipped.isEmpty()) throw new AssertionError("sandbox defaults: no KnoxSurvivors options parsed");
        java.util.Map<String,String> code=new java.util.LinkedHashMap<>();
        int start=settings.indexOf("local DEFAULTS = {"), end=settings.indexOf("\n}",start);
        if(start<0||end<0) throw new AssertionError("sandbox defaults: KS_Settings DEFAULTS block not found");
        for(String line:settings.substring(start,end).split("\n")){
            java.util.regex.Matcher m=java.util.regex.Pattern.compile(
                "^[ ]{4}([A-Za-z][A-Za-z0-9]*)[ ]*=[ ]*(true|false|-?[0-9]+),[ ]*$").matcher(line);
            if(m.find()) code.put(m.group(1),m.group(2));
        }
        java.util.Set<String> missingInCode=new java.util.TreeSet<>(shipped.keySet());
        missingInCode.removeAll(code.keySet());
        java.util.Set<String> missingInFile=new java.util.TreeSet<>(code.keySet());
        missingInFile.removeAll(shipped.keySet());
        if(!missingInCode.isEmpty()||!missingInFile.isEmpty()) throw new AssertionError(
            "sandbox defaults: schema and KS_Settings disagree; missing in code="+missingInCode
                +", missing in shipped file="+missingInFile);
        for(String name:shipped.keySet()) if(!shipped.get(name).equals(code.get(name)))
            throw new AssertionError("sandbox defaults: "+name+" ships "+shipped.get(name)
                +" but code falls back to "+code.get(name));
        java.util.Map<String,String> pinned=new java.util.LinkedHashMap<>();
        pinned.put("MaxActiveSurvivors","24");
        pinned.put("ActivationsPerUpdate","1");
        pinned.put("SurvivorEncounterDistance","160");
        pinned.put("PopulationRefillDays","14");
        pinned.put("InitialGroupChance","35");
        pinned.put("InitialGroupCount","40");
        pinned.put("InitialFactionCount","4");
        pinned.put("CompanionLimit","3");
        pinned.put("RequireCloseContact","true");
        pinned.put("ZombieEngagementDistance","3");
        pinned.put("SurvivorNameplateDistance","12");
        pinned.put("FactionEntryMinimumDays","14");
        pinned.put("FactionEntryIntervalDays","14");
        pinned.put("FactionRaidMinimumDays","30");
        pinned.put("FactionRaidIntervalDays","14");
        pinned.put("SurvivorAimingAssist","3");
        for(java.util.Map.Entry<String,String> e:pinned.entrySet()){
            String actual=shipped.get(e.getKey());
            if(!e.getValue().equals(actual)) throw new AssertionError(
                "sandbox defaults: preset "+e.getKey()+"="+e.getValue()+" but shipped "+actual);
        }
        System.out.println("Sandbox defaults PASS knobs="+shipped.size()
            +" code_match=true pinned="+pinned.size()+" schema_ranges=true");
    }

    private static int intOption(String body,String field){
        java.util.regex.Matcher m=java.util.regex.Pattern.compile(field+"[ ]*=[ ]*(-?[0-9]+)").matcher(body);
        if(!m.find()) throw new AssertionError("sandbox defaults: option body missing "+field);
        return Integer.parseInt(m.group(1));
    }

    private static String section(String source,String start,String end) {
        // Source windows must behave the same in LF and Windows CRLF checkouts.
        source=source.replace("\r\n","\n");
        int first=source.indexOf(start), last=source.indexOf(end,Math.max(0,first));
        if(first<0 || last<=first) throw new AssertionError("Missing production source section: "+start);
        return source.substring(first,last);
    }

    public static final class FakeCorpseData {
        private final Object data;
        public FakeCorpseData(Object data) { this.data=data; }
        public Object getModData() { return data; }
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
