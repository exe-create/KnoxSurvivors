local G=assert(codecGuideLayout)
do -- tab structure and grounded controls: one page per system, asked-for words present
    local pages=G.PAGES
    assert(type(pages)=="table" and #pages==8,"one tab per system: got "..#pages)
    local ids={}
    for i=1,#pages do
        local page=pages[i]
        assert(type(page.id)=="string" and page.id:find("KnoxSurvivors_Guide",1,true)==1,
            "Knox page ids keep the prefix: "..tostring(page.id))
        assert(ids[page.id]==nil,"no duplicate guide page id: "..tostring(page.id))
        ids[page.id]=true
        assert(type(page.title)=="string" and type(page.lines)=="table" and #page.lines>0,
            "each page carries a title and lines: "..tostring(page.id))
    end
    local parts={}
    for i=1,#pages do parts[#parts+1]=table.concat(pages[i].lines," ") end
    local joined=table.concat(parts," ")
    for _,phrase in ipairs({"Assign Bed","Establish Home Base","Container Item Filters",
            "Faction Raids","Your People Continue After Death","Toggle Survival Guide"}) do
        assert(joined:find(phrase,1,true)~=nil,"guide names real controls: missing "..phrase)
    end
end
local function panel(y,height)
    return {y=y,height=height,visible=true,pages=0,
        getY=function(self) return self.y end,getHeight=function(self) return self.height end,
        setY=function(self,value) self.y=value end,setHeight=function(self,value) self.height=value end,
        setWidth=function(self,value) self.width=value end,setVisible=function(self,value) self.visible=value end,
        paginate=function(self) self.pages=self.pages+1 end}
end
local video,text=panel(20,480),panel(500,120)
local window={videoRichText=video,descriptionRichText=text,listBox=panel(20,600),
    getWidth=function() return 1200 end,selectedItem={id="KnoxSurvivors_Guide_Base"}}
window.listBox.getRight=function() return 240 end
G.layoutPage(window)
assert(text.y==20 and text.height==600,"Knox page gets the complete text viewport")
assert(text.width==960 and text.pages==1,"paragraphs reflow to the actual right pane")
assert(not video.visible and video.height==0,"Knox pages leave no blank video rectangle")
window.selectedItem={id="VanillaTutorial"}
G.layoutPage(window)
assert(video.visible and video.height==480,"vanilla video is restored after a Knox page")
assert(text.y==500 and text.height==120,"vanilla description returns below the video")
window.selectedItem={id="KnoxSurvivors_Guide"}
G.layoutPage(window)
assert(text.height==600 and not video.visible,"switching back reapplies text layout")
G.layoutPage(nil)

local oldCore=getCore
getCore=function() return {getScreenWidth=function() return 1024 end,
    getScreenHeight=function() return 768 end} end
local resized={width=1400,height=900,videoRichText=panel(20,480),
    descriptionRichText=panel(500,380),listBox=panel(20,860),
    selectedItem={id="KnoxSurvivors_Guide"}}
resized.listBox.getRight=function() return 240 end
resized.getWidth=function(self) return self.width end
resized.getHeight=function(self) return self.height end
resized.setWidth=function(self,value) self.width=value end
resized.setHeight=function(self,value) self.height=value;self.listBox.height=value-40 end
resized.setX=function(self,value) self.x=value end
resized.setY=function(self,value) self.y=value end
G.layoutPage(resized)
assert(resized.width==992 and resized.height==736,"Knox guide fits a small display with margins")
assert(resized.descriptionRichText.width==752 and resized.descriptionRichText.height==696,
    "long sentences reflow inside the resized text viewport")
resized.selectedItem={id="Vanilla"}
G.layoutPage(resized)
assert(resized.width==1400 and resized.videoRichText.height==480,
    "native geometry is restored when returning to vanilla pages")
getCore=oldCore
