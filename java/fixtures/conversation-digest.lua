local Feed = assert(KnoxActivityFeed, "the notice owner is loaded")
assert(type(Feed.conversationLine) == "function", "the conversation formatter is loaded")

local day = Feed.conversationLine("Their Day", "  Nothing   yet. ")
assert(day == 'asked about their day: "Nothing yet."', "day answer: " .. tostring(day))
assert(Feed.conversationLine("What They Need", "Water.") == 'asked about what they need: "Water."',
    "need answer keeps its label")
assert(Feed.conversationLine("", "It is quiet.") == 'asked about it: "It is quiet."',
    "a missing question falls back to it")
assert(Feed.conversationLine("Their Day", "   ") == nil, "an empty answer is not a line")
local long = Feed.conversationLine("Their Day", string.rep("a", 300))
assert(#long == 265 and long:sub(-4) == '..."', "long answer is capped: " .. tostring(#long))
print("Conversation digest PASS question=true answer=true cap=240")
