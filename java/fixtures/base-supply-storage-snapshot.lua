local planner=KnoxBaseSupplyPlanner
assert(not planner.hasKnownStorageSnapshot(nil),"missing summary is unknown")
assert(not planner.hasKnownStorageSnapshot({loadedPolicies=0,totals={food=0}}),
    "unloaded or absent containers must not trigger an empty-stock supply run")
assert(not planner.hasKnownStorageSnapshot({loadedPolicies=0,unavailablePolicies=2,totals={food=0}}),
    "streamed-out storage remains unknown rather than empty")
assert(planner.hasKnownStorageSnapshot({loadedPolicies=1,totals={food=0}}),
    "an inspected empty container is evidence of a real shortage")
assert(planner.chooseAvailableShortage({food=0},{1},{},"resident")=="find_food",
    "known empty storage still permits an actual food supply run")
print("Base supply storage snapshot PASS missing_unknown=true unloaded_unknown=true loaded_empty_shortage=true")
