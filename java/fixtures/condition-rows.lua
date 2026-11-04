-- The Condition tab reads the self-report the snapshot already carries. This
-- fixture proves the two projections the card uses: pain as a 0..1 bar and a
-- bleed count as words. It does not open a card or read a body.
local C = assert(codecConditionRows, "condition rows source is loaded")

assert(C.painFraction(nil) == nil, "an unreported pain is unknown")
assert(C.painFraction(0) == 0, "no pain is an empty bar")
assert(C.painFraction(50) == 0.5, "half pain is half the bar")
assert(C.painFraction(100) == 1, "full pain fills the bar")
assert(C.painFraction(140) == 1, "pain above the scale clamps")
assert(C.painFraction(-20) == 0, "pain below zero clamps")
assert(C.painFraction(0 / 0) == nil, "a NaN pain is unknown")

assert(C.bleedingWord(nil) == nil, "an unreported bleed is quiet")
assert(C.bleedingWord(0) == nil, "zero parts is not a bleed")
assert(C.bleedingWord(1) == "1 part", "one part is singular")
assert(C.bleedingWord(3) == "3 parts", "several parts are plural")
assert(C.bleedingWord(2.9) == "2 parts", "a fractional count floors")
assert(C.bleedingWord(-4) == nil, "a negative count is not a bleed")

assert(C.medicalLabel(0) == "Medical Check", "a clean body keeps the general check")
assert(C.medicalLabel(nil) == "Medical Check", "an unreported bleed keeps the general check")
assert(C.medicalLabel(1) == "Check Bleeding", "a bleed names the check")
assert(C.medicalLabel(2.9) == "Check Bleeding", "a fractional bleed still names it")
assert(C.medicalLabel(-3) == "Medical Check", "a negative count is not a bleed")

assert(C.infectionWord(true) == "Bitten", "a bite is named")
assert(C.infectionWord(false) == nil, "a clean body spends no row")
assert(C.infectionWord(nil) == nil, "an unread body is not a bite")
assert(C.infectionWord("true") == nil, "only the engine's boolean counts")

print("ConditionRows PASS pain=true bleed=true clamp=true medical=true infection=true")
