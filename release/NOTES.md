Manual download for **Project Zomboid Build 42.22, single-player**.

Download **KnoxSurvivors-0.3.0-rc2.zip** under Assets and follow its **README.txt**.
The ZIP contains only `mods/KnoxSurvivors` and the installation README, including
the compiled gameplay JAR. GitHub's automatic source archives are for developers.

You need one separately installed Java runtime: **ZombieBuddy 2.3.4** or
**KnoxBridge Runtime**. The README includes setup links, the required runtime
Workshop mod, module approval, avoiding duplicate Knox copies, and rollback.
This release does not update the Steam Knox Survivors item.

Please test following and base work around doors, wall corners and furniture,
including tight turns at walking and running speeds. This candidate includes
the current survivor update and additional route-waypoint and recovery-floor
checks. These changes have offline regression coverage; their in-game effect
still needs testing.

**Checks passed:** full offline Java/Lua suite, all 130 shipped Lua sources
compiled with zero failures, runtime-adapter checks, and exact ZIP/source/JAR
comparison. New movement regressions failed before their fixes; deliberately
broken assertions failed and were restored before the final passing checks.

**Public test build:** native movement, collision, performance and save/reload
acceptance are pending. Back up saves and use a disposable test save first.
42.21 and multiplayer are unsupported. Downgrade save compatibility is unverified.

Report problems with your game version, mod version and runtime at
[GitHub Issues](https://github.com/exe-create/KnoxSurvivors/issues).
Official release downloads are permitted for personal gameplay and testing;
redistribution, reuploads and reuse of the code/assets remain restricted.

ZIP SHA-256: `0b05581bbe06cec492373a9dd8d271679c59a7bcb17a67a8152bdba628107db3`
