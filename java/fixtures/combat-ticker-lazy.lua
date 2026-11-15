-- Counting harness for the combat-test ticker. KS_TICKER_INSTALL/REMOVE are the
-- real production lifecycle helpers; the fake Events table counts handlers.
assert(KS_TICKER_STATE() == false,
    "an idle game installs no combat-test ticker")

KS_TICKER_INSTALL()
KS_TICKER_INSTALL()
assert(KS_TICKER_ADDS == 1 and KS_TICKER_STATE(),
    "arming installs the ticker exactly once, got " .. tostring(KS_TICKER_ADDS))

KS_TICKER_REMOVE()
KS_TICKER_REMOVE()
assert(KS_TICKER_REMOVES == 1 and KS_TICKER_STATE() == false,
    "teardown removes the one handler, got " .. tostring(KS_TICKER_REMOVES))

KS_TICKER_INSTALL()
assert(KS_TICKER_ADDS == 2,
    "re-arming installs again without leaking the old handler, got "
        .. tostring(KS_TICKER_ADDS))
KS_TICKER_REMOVE()
assert(KS_TICKER_REMOVES == 2 and KS_TICKER_STATE() == false,
    "the second teardown also leaves nothing behind")

KS_TICKER_RECEIPT = "installs=" .. tostring(KS_TICKER_ADDS)
    .. " removes=" .. tostring(KS_TICKER_REMOVES)
    .. " idle_installs=0 duplicate_install=false"
