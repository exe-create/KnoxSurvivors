-- Immersive conversation, first slice: remembered history changes the sentence
-- before standing does, and no history reads exactly as the pair did before.
local C = KnoxCompanionService

local refused, refusedWhy = C.rememberExchange(nil, "helped", 1)
assert(refused == nil and refusedWhy == "unknown_relation", "no record, no history")
assert(select(2, C.rememberExchange({}, "gossiped", 1)) == "unknown_history",
    "an unknown exchange never invents a bucket")

local relation = { trust = 40, meetings = 1 }
assert(C.historyTone(relation) == "neutral", "a record with no history reads neutral")
assert(C.historyTone(nil) == "neutral", "no record reads neutral")
assert(C.historyTone({ history = "unreadable" }) == "neutral",
    "an unreadable history reads neutral, never warm")

assert(C.rememberExchange(relation, "helped", 2))
assert(C.historyTone(relation) == "warmer", "remembered help makes the pair warmer")
local warmLine = C.socialResponse(40, "joke", 1, "fallback", nil, relation)
assert(warmLine == C.HISTORY_WARM_LINES.joke[1],
    "a warmer pair gets the warm history line, not the fallback")
assert(C.socialResponse(40, "joke", 2, "fallback", nil, relation)
    == C.HISTORY_WARM_LINES.joke[2], "meetings still cycle the chosen bank")
assert(C.socialResponse(40, "insult", 1, "fallback", nil, relation) == "fallback",
    "an act with no warm line keeps today's answer")

assert(C.rememberExchange(relation, "argued", 3))
assert(C.historyTone(relation) == "guarded", "more quarrels than help reads guarded")
assert(C.socialResponse(40, "joke", 1, "fallback", nil, relation)
    == C.HISTORY_GUARDED_LINES[1], "a guarded pair answers guardedly, whatever the act")
assert(C.rememberExchange(relation, "helped", 1))
assert(C.historyTone(relation) == "neutral", "an even tally returns to today's answer")

local baseline = C.socialResponse(40, "joke", 1, "fallback", nil, nil)
assert(baseline == "fallback", "with no standing line, no history means the fallback")

socialHistoryReceipt = "refused=2 tones=5 warm=2 guarded=1 neutral=2"
socialHistoryPass = true
