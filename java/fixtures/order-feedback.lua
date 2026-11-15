-- Interface polish, pass 1: a work order the survivor cannot walk to is spoken
-- by that survivor, naming the player who can clear the way; a missing supply
-- keeps the readable notice. One rule, in the task-board owner.
local B = KnoxBaseTaskBoard
assert(type(B.blockedOrderFeedback) == "function",
    "the task-board owner answers what a blocker should say")

local route = "task_move_no_progress"
local kind, line = B.blockedOrderFeedback(route)
assert(kind == "speak" and line == "I can't get through, take a look.",
    "a blocked route is spoken, not printed as a cancel")

local unreachable = B.blockedOrderFeedback("assigned_supply_entry_unavailable")
assert(unreachable == "speak", "an unreachable entry is spoken too")
local approach = B.blockedOrderFeedback("storage_approach_unavailable")
assert(approach == "speak", "a storage the survivor cannot stand at is spoken")

local entry = select(2, B.blockedOrderFeedback("alternate_entry_unavailable"))
assert(entry == "You handle it, I couldn't figure it out.",
    "an entry the survivor tried and failed is handed to the player")
assert(select(1, B.blockedOrderFeedback("door_break_failed:failed")) == "speak",
    "a failed forced entry is the survivor's own report")

-- Supply and material blockers keep the notice text the player acts on.
local noteKind, note = B.blockedOrderFeedback("missing_carried_hammer_or_plank")
assert(noteKind == "notice" and note == "Needs a hammer and plank in inventory",
    "a missing material keeps its readable notice")
local assigned = select(1, B.blockedOrderFeedback("missing_assigned_item=Base.Nails"))
assert(assigned == "notice", "a missing stored item is a notice, not a walk problem")

assert(select(1, B.blockedOrderFeedback(nil)) == "notice"
    and select(2, B.blockedOrderFeedback(nil)) == nil,
    "no reason means no line at all")
assert(select(1, B.blockedOrderFeedback("")) == "notice", "an empty reason says nothing")

orderFeedbackReceipt = "spoken=4 noticed=2 blank=2"
orderFeedbackPass = true
