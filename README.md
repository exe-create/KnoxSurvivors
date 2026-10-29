# Knox Survivors

Knox Survivors is a single-player survivor mod for Project Zomboid Build 42.21. This repository contains the mod source (`mod/`), Java runtime (`java/`), and Workshop packaging files. Version `0.3.0-rc1` is a test candidate; live gameplay and save/load acceptance are pending.

## Build

Copy `gradle.properties.example` to a private `local.properties` and set `pzHome` to the installed Project Zomboid directory. Then run `./gradlew.bat :java:build packageWorkshopCandidate` from the repository root. The result is under `build/workshop-candidate/KnoxSurvivors`. This does not install or publish the mod.

Use either ZombieBuddy or KnoxBridge Runtime, never both in one game process. The separate Knox Survivors Launcher is retired. Test with a disposable save and back up existing saves first.
