-- The card's Order row keeps the accepted order and adds the fact that the
-- next order will be refused. This drives the pure rule; it does not open a card.
local O = assert(codecOrderRow, "order row source is loaded")

assert(O.orderRowLabel("Following", "steady") == "Following",
    "a willing order is unchanged")
assert(O.orderRowLabel("Following", nil) == "Following",
    "an unknown willingness is unchanged")
assert(O.orderRowLabel("Following", "") == "Following",
    "an empty willingness is unchanged")
assert(O.orderRowLabel("Following", "wary") == "Following - won't take new orders",
    "a wary order says what will happen next")
assert(O.orderRowLabel("Holding", "wary") == "Holding - won't take new orders",
    "the accepted order stays in front")
assert(O.orderRowLabel(nil, "wary") == "Won't take new orders",
    "a missing order still states the refusal")
assert(O.orderRowLabel("", "wary") == "Won't take new orders",
    "an empty order still states the refusal")
assert(O.orderRowLabel("Following", "hostile") == "Following - hostile",
    "a hostile order is named")
assert(O.orderRowLabel(nil, "hostile") == "Hostile",
    "a missing hostile order is named")
print("OrderRow PASS steady=true wary=true hostile=true")
