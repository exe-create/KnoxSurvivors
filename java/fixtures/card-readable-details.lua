for _, font in ipairs({14, 24, 32}) do
    local helpers = cardDetailFactory(font)
    for _, width in ipairs({220, 380, 560}) do
        local lines, bottom = {}, 0
        local view = {}
        function view:drawText(text, x, y)
            assert(x >= 10 and x + #text*font*0.55 <= 10 + width, "card text remains inside content")
            lines[#lines+1] = text
            bottom = math.max(bottom, y + font)
        end
        function view:drawTextRight(text, right, y)
            self:drawText(text, right - #text*font*0.55, y)
        end
        local value = "Bitten on the left forearm. Bleeding needs attention."
        local nextY = helpers.detail(view,"Condition",value,10,0,width,{1,1,1},{1,1,1})
        local rendered = table.concat(lines," ")
        assert(rendered == "Condition " .. value, "complete condition and its reason remain visible")
        assert(nextY >= bottom, "following content clears every rendered line")
        lines = {}
        local token = "ExtremelyLongModdedFactionNameWithoutAnySpaces"
        nextY = helpers.text(view,token,10,0,width,1,{1,1,1})
        assert(table.concat(lines,"") == token, "long identity is preserved across lines")
        assert(nextY > font, "long identity reserves additional height")
    end
end
local helpers = cardDetailFactory(14)
local draws = {}
local view = {drawText=function(self,text,x,y) draws[#draws+1]={text=text,y=y} end,
    drawTextRight=function(self,text,x,y) draws[#draws+1]={text=text,y=y} end}
assert(helpers.detail(view,"Job","Guard",10,0,500,{1,1,1},{1,1,1}) == 18,
    "short details keep a compact single row")
assert(draws[1].y == draws[2].y, "short values remain beside their labels")
print("Card readable details PASS full_condition=true identity=true bounds=true compact=true")

for _,font in ipairs({14,24,32}) do
    local function button(title)
        return {title=title,width=122,height=24,setTitle=function(self,v) self.title=v end,
            setX=function(self,v) self.x=v end,setY=function(self,v) self.y=v end,
            setWidth=function(self,v) self.width=v end,setHeight=function(self,v) self.height=v end}
    end
    local view={height=400,inventoryButton=button("Inventory"),medicalButton=button("Check Bleeding")}
    view.medicalButton.knoxLabel="Check Bleeding"
    local contentH=cardDetailFactory(font).footer(view,500,300,font)
    for _,b in ipairs({view.inventoryButton,view.medicalButton}) do
        assert(b.x>=10 and b.x+b.width<=310,"card action stays inside content")
        assert(#b.title*font*0.55+24<=b.width,"complete action caption fits")
        assert(b.y>=508 and b.y+b.height<=contentH,"footer follows all details")
    end
    if font>=24 then assert(view.medicalButton.y>view.inventoryButton.y,"large actions stack") end
end
