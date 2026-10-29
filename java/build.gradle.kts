import java.util.Properties

plugins {
    java
}

group = "com.knoxsurvivors"
version = rootProject.version

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.isFile) {
        file.inputStream().use(::load)
    }
}
val pzHome = providers.gradleProperty("pzHome")
    .orElse(localProperties.getProperty("pzHome") ?: "")
val knoxBridgeApiJar = providers.gradleProperty("knoxBridgeApiJar")
    .orElse(localProperties.getProperty("knoxBridgeApiJar")
        ?: rootProject.projectDir.parentFile.resolve("KnoxBridgeRuntime/runtime-api/build/libs/runtime-api-0.1.0-alpha3.jar").absolutePath)
val knoxBridgeRuntimeJar = providers.gradleProperty("knoxBridgeRuntimeJar")
    .orElse(rootProject.projectDir.parentFile.resolve("KnoxBridgeRuntime/runtime-core/build/libs/knoxbridge-agent-0.1.0-alpha11.jar").absolutePath)

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

dependencies {
    compileOnly(files(pzHome.map { file(it).resolve("projectzomboid.jar") }))
    compileOnly(files(knoxBridgeApiJar))
    compileOnly(files(pzHome.map { file(it).resolve("ZombieBuddy.jar") }))
    testImplementation(files(pzHome.map { file(it).resolve("ZombieBuddy.jar") }))
    testImplementation(files(knoxBridgeRuntimeJar))
}

tasks.register("verifyGameJar") {
    group = "verification"
    description = "Checks that the configured Project Zomboid game jar is available."

    doLast {
        require(pzHome.get().isNotBlank()) {
            "Set pzHome in local.properties before building."
        }
        val gameJar = file(pzHome.get()).resolve("projectzomboid.jar")
        require(gameJar.isFile) {
            "Project Zomboid jar not found at ${gameJar.absolutePath}"
        }
    }
}

tasks.register("verifyKnoxBridgeApi") {
    group = "verification"
    description = "Checks for the KnoxBridge module API used by the Workshop runtime module."

    doLast {
        val jar = file(knoxBridgeApiJar.get())
        require(jar.isFile) {
            "KnoxBridge API jar not found at ${jar.absolutePath}. Build KnoxBridge runtime-api or set knoxBridgeApiJar in local.properties."
        }
        logger.lifecycle("KnoxBridge module API found; API classes are supplied by the runtime.")
    }
}

tasks.compileJava {
    dependsOn("verifyGameJar", "verifyKnoxBridgeApi")
    options.encoding = "UTF-8"
    options.release = 17
}

tasks.jar {
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true
    archiveBaseName = "knox-survivors"
    manifest {
        attributes(
            "Implementation-Title" to "Knox Survivors unified runtime module",
            "Implementation-Version" to project.version,
        )
    }
}

val verifyRuntimeAdapters by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies annotation-runtime/module startup, owner guards and both JAR contracts."
    dependsOn(tasks.testClasses, tasks.jar, ":packageUnifiedMod")
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.runtime.KnoxRuntimeAdapterVerifier")
    doFirst {
        args(tasks.jar.get().archiveFile.get().asFile.absolutePath,
            layout.buildDirectory.dir("runtime-adapter-fixtures").get().asFile.absolutePath,
            rootProject.projectDir.absolutePath,
            rootProject.layout.buildDirectory.dir("distribution/KnoxSurvivors").get().asFile.absolutePath,
            sourceSets.test.get().output.classesDirs.singleFile.absolutePath)
    }
}

val verifyInstalledRuntimeApi by tasks.registering(Exec::class) {
    group = "verification"
    description = "Inspects the installed ZombieBuddy public API without initializing it or launching PZ."
    dependsOn(tasks.testClasses, "verifyGameJar")
    doFirst {
        val gameHome = file(pzHome.get())
        val gameJar = gameHome.resolve("projectzomboid.jar")
        val framework = providers.gradleProperty("zombieBuddyJar")
            .orElse(gameHome.resolve("ZombieBuddy.jar").absolutePath).get()
        commandLine(gameHome.resolve("jre64/bin/java.exe").absolutePath,
            "-Duser.home=${layout.buildDirectory.dir("runtime-api-inspection-home").get().asFile.absolutePath}",
            "-cp", sourceSets.test.get().output.classesDirs.asPath,
            "com.knoxsurvivors.engine.KnoxInstalledRuntimeApiVerifier",
            "--inspect", gameJar.absolutePath, framework)
    }
}

val verifyZombieBuddyPatches by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Binds supported ZombieBuddy advice to installed engine bytes and exercises isolated fixtures; no game launch."
    dependsOn(tasks.testClasses, tasks.jar)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.runtime.KnoxZombieBuddyPatchVerifier")
    doFirst {
        args(layout.buildDirectory.dir("zombiebuddy-patch-verification").get().asFile.absolutePath,
            file(pzHome.get()).resolve("projectzomboid.jar").absolutePath,
            tasks.jar.get().archiveFile.get().asFile.absolutePath,
            file(pzHome.get()).resolve("ZombieBuddy.jar").absolutePath)
    }
}

val verifyUnifiedZombieBuddy by tasks.registering(Exec::class) {
    group = "verification"
    dependsOn(tasks.testClasses, ":stageUnifiedMod")
    doFirst {
        val home = file(pzHome.get())
        workingDir(home)
        val classpath = listOf(tasks.jar.get().archiveFile.get().asFile.absolutePath,
            home.resolve("ZombieBuddy.jar").absolutePath, home.resolve("projectzomboid.jar").absolutePath,
            sourceSets.test.get().output.classesDirs.asPath).joinToString(System.getProperty("path.separator"))
        commandLine(home.resolve("jre64/bin/java.exe").absolutePath,
            "-Duser.home=${layout.buildDirectory.dir("unified-zb-test-home").get().asFile.absolutePath}",
            "-Dknox.logDirectory=${layout.buildDirectory.dir("verification-logs/unified-zb").get().asFile.absolutePath}",
            "-cp", classpath, "com.knoxsurvivors.runtime.KnoxUnifiedZombieBuddyVerifier",
            tasks.jar.get().archiveFile.get().asFile.absolutePath,
            rootProject.layout.buildDirectory.dir("distribution/KnoxSurvivors").get().asFile.absolutePath)
    }
}
val verifyUnifiedKnoxBridge by tasks.registering(JavaExec::class) {
    group = "verification"
    dependsOn(tasks.testClasses, ":stageUnifiedMod")
    // Deliberately exclude ZombieBuddy AND main output dirs; exercise the shipped artifact.
    classpath = files(tasks.jar.flatMap { it.archiveFile }, knoxBridgeRuntimeJar, sourceSets.test.get().output.classesDirs)
    mainClass.set("com.knoxbridge.runtime.KnoxUnifiedBridgeVerifier")
    doFirst { args(rootProject.layout.buildDirectory.dir("distribution/KnoxSurvivors/42").get().asFile.absolutePath) }
}

val verifyCombatTransformer by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies the narrow melee callback patch against the configured game jar."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.agent.KnoxSwipeStateTransformerVerifier")
    doFirst {
        val gameJar = file(pzHome.get()).resolve("projectzomboid.jar")
        args(gameJar.absolutePath)
    }
}

val verifyZombieVisibilityTransformer by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies the Knox shell visibility adapter against the configured game jar."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.agent.KnoxZombieVisibilityTransformerVerifier")
    doFirst {
        val gameJar = file(pzHome.get()).resolve("projectzomboid.jar")
        args(gameJar.absolutePath)
    }
}

val verifyZombieVisibilityRuntime by tasks.registering(Exec::class) {
    group = "verification"
    description = "Defines the transformed IsoZombie class with Project Zomboid's Java runtime."
    dependsOn(tasks.testClasses)
    doFirst {
        val gameHome = file(pzHome.get())
        val gameJar = gameHome.resolve("projectzomboid.jar")
        val javaRuntime = gameHome.resolve("jre64/bin/java.exe")
        require(javaRuntime.isFile) {
            "Project Zomboid Java runtime not found at ${javaRuntime.absolutePath}"
        }
        val classpath = listOf(
            sourceSets.main.get().output.classesDirs.asPath,
            gameJar.absolutePath,
            sourceSets.test.get().output.classesDirs.asPath,
        ).joinToString(System.getProperty("path.separator"))
        commandLine(
            javaRuntime.absolutePath,
            "-Xverify:all",
            "-cp",
            classpath,
            "com.knoxsurvivors.agent.KnoxZombieVisibilityClassVerifier",
            gameJar.absolutePath,
        )
    }
}

val verifyGameLuaCompilation by tasks.registering(Exec::class) {
    group = "verification"
    description = "Compiles all shipped Lua with the installed Build 42 compiler without executing gameplay."
    dependsOn(tasks.testClasses, "verifyGameJar")
    doFirst {
        val gameHome = file(pzHome.get())
        val javaRuntime = gameHome.resolve("jre64/bin/java.exe")
        require(javaRuntime.isFile) { "Project Zomboid Java runtime not found at ${javaRuntime.absolutePath}" }
        val classpath = listOf(
            gameHome.resolve("projectzomboid.jar").absolutePath,
            sourceSets.test.get().output.classesDirs.asPath,
        ).joinToString(System.getProperty("path.separator"))
        commandLine(javaRuntime.absolutePath, "-cp", classpath,
            "com.knoxsurvivors.engine.KnoxLuaCompilerVerifier",
            rootProject.file("mod").absolutePath)
    }
}

val verifyInstalledCompanionApi by tasks.registering(Exec::class) {
    group = "verification"
    description = "Checks installed companion APIs and the real active-mod parser without starting PZ."
    dependsOn(tasks.testClasses, "verifyGameJar")
    doFirst {
        val gameHome = file(pzHome.get())
        val evidence = rootProject.layout.buildDirectory.dir("verification/installed-companion-api").get().asFile
        evidence.mkdirs()
        val fixture = evidence.resolve("default.txt")
        fixture.writeText("VERSION = 1,\nmods\n{\n    mod = KnoxSurvivors,\n}\nmaps\n{\n}\n")
        val gameJar = gameHome.resolve("projectzomboid.jar")
        val classpath = listOf(gameJar.absolutePath, sourceSets.test.get().output.classesDirs.asPath)
            .joinToString(System.getProperty("path.separator"))
        commandLine(gameHome.resolve("jre64/bin/java.exe").absolutePath,
            "-Duser.home=${evidence.resolve("home").absolutePath}", "-cp", classpath,
            "com.knoxsurvivors.engine.KnoxInstalledCompanionApiVerifier",
            gameJar.absolutePath, fixture.absolutePath)
    }
}

val verifyIsoPlayerShellPolicy by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies that the generated NPC shell never claims local input ownership."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.engine.KnoxIsoPlayerShellPolicyVerifier")
}

val verifyIsoPlayerShellRuntime by tasks.registering(Exec::class) {
    group = "verification"
    description = "Defines the generated IsoPlayer NPC shell with Project Zomboid's Java runtime."
    dependsOn(tasks.testClasses)
    doFirst {
        val gameHome = file(pzHome.get())
        val gameJar = gameHome.resolve("projectzomboid.jar")
        val javaRuntime = gameHome.resolve("jre64/bin/java.exe")
        require(javaRuntime.isFile) {
            "Project Zomboid Java runtime not found at ${javaRuntime.absolutePath}"
        }
        val classpath = listOf(
            sourceSets.main.get().output.classesDirs.asPath,
            gameJar.absolutePath,
            sourceSets.test.get().output.classesDirs.asPath,
        ).joinToString(System.getProperty("path.separator"))
        commandLine(
            javaRuntime.absolutePath,
            "-Xverify:all",
            "-cp",
            classpath,
            "com.knoxsurvivors.engine.KnoxIsoPlayerShellVerifier",
        )
    }
}

val verifyCorpseLifecycle by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies that Knox death handoff uses the native reanimation decision."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxNpcRegistryVerifier")
}

val verifyMovementOwnership by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies movement ownership, replacement, release, and recovery state."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxMovementRequestVerifier")
}

val verifyTraversalPolicy by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies native-first obstacle policy, edge suppression, and route continuation."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxTraversalVerifier")
}

val verifyCompanionLocomotion by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies companion walk, run, sprint, downgrade, and condition policy."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxLocomotionVerifier")
}

val verifyMeleeCombatLifecycle by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies terminal melee input, route, and ownership cleanup."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxCombatControllerVerifier")
}

val verifyPersistenceCodec by tasks.registering(Exec::class) {
    group = "verification"
    description = "Runs production persistence Lua through the installed B42 table save/load codec without a world."
    dependsOn(tasks.testClasses, "verifyGameJar")
    doFirst {
        val gameHome = file(pzHome.get())
        commandLine(gameHome.resolve("jre64/bin/java.exe").absolutePath,
            "-Dknox.logDirectory=" + layout.buildDirectory.dir("verification-logs/verifyPersistenceCodec").get().asFile.absolutePath,
            "-cp", listOf(gameHome.resolve("projectzomboid.jar").absolutePath,
                sourceSets.main.get().output.classesDirs.asPath, sourceSets.test.get().output.classesDirs.asPath).joinToString(System.getProperty("path.separator")),
            "com.knoxsurvivors.npc.KnoxPersistenceCodecVerifier", rootProject.projectDir.absolutePath, gameHome.absolutePath)
    }
}

val verifyInventorySnapshot by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies native item payload handoff, bag contents, equipment and legacy inventory migration."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxInventorySnapshotVerifier")
}

val verifyEquipmentOwnership by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Verifies exact carried garment selection without substituting same-type gear."
    dependsOn(tasks.testClasses)
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.knoxsurvivors.npc.KnoxEquipmentControllerVerifier")
}

// Synthetic verifier failures must never contaminate the player's live log.
tasks.withType<JavaExec>().configureEach {
    systemProperty("knox.logDirectory", layout.buildDirectory.dir("verification-logs/$name").get().asFile.absolutePath)
}
tasks.withType<Test>().configureEach {
    systemProperty("knox.logDirectory", layout.buildDirectory.dir("verification-logs/$name").get().asFile.absolutePath)
}

tasks.check {
    dependsOn(
        verifyCombatTransformer,
        verifyZombieVisibilityTransformer,
        verifyZombieVisibilityRuntime,
        verifyIsoPlayerShellPolicy,
        verifyIsoPlayerShellRuntime,
        verifyCorpseLifecycle,
        verifyMovementOwnership,
        verifyTraversalPolicy,
        verifyCompanionLocomotion,
        verifyMeleeCombatLifecycle,
        verifyInventorySnapshot,
        verifyPersistenceCodec,
        verifyEquipmentOwnership,
        verifyGameLuaCompilation,
        verifyInstalledCompanionApi,
        verifyInstalledRuntimeApi,
        verifyRuntimeAdapters,
        verifyZombieBuddyPatches,
        verifyUnifiedZombieBuddy,
        verifyUnifiedKnoxBridge,
    )
}
