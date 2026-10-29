import java.security.MessageDigest
import java.util.Properties

plugins { base }
group = "com.knoxsurvivors"
version = "0.3.0-rc1"

val localProperties = Properties().apply {
    val config = file("local.properties")
    if (config.isFile) config.inputStream().use(::load)
}
val workshopRoot = providers.gradleProperty("workshopRoot").orElse(localProperties.getProperty("workshopRoot") ?: "")
val workshopModFolder = providers.gradleProperty("workshopModFolder").orElse(localProperties.getProperty("workshopModFolder") ?: "KnoxSurvivors")
val localModsRoot = providers.gradleProperty("localModsRoot").orElse(localProperties.getProperty("localModsRoot") ?: "")
val unifiedJar = project(":java").layout.buildDirectory.file("libs/knox-survivors-${project.version}.jar")
val checksum = layout.buildDirectory.file("unified-mod/knox-survivors.jar.sha256")
val withZbsSigning = providers.gradleProperty("withZbsSigning").map { it == "true" }.orElse(false)
// A fresh signing output prevents reuse of a sidecar from a different JAR/key.
val signedJarDirectory = layout.buildDirectory.dir("zbs/${java.util.UUID.randomUUID()}")
val signUnifiedJarZbs by tasks.registering(Exec::class) {
    group = "distribution"
    description = "Signs a byte-identical copy of the final JAR using the documented ZBS format; no installation or publication."
    dependsOn(":java:jar")
    doFirst {
        val steamId = providers.gradleProperty("zbsSteamID64").orNull
        val privateKey = providers.gradleProperty("zbsPrivateKeyFile").orNull
        val gameHome = providers.gradleProperty("pzHome").orElse(localProperties.getProperty("pzHome") ?: "").get()
        require(!steamId.isNullOrBlank() && !privateKey.isNullOrBlank()) {
            "Configure zbsSteamID64 and zbsPrivateKeyFile in the user-level Gradle properties after owner-approved author setup."
        }
        require(gameHome.isNotBlank()) { "Set pzHome before signing." }
        val finalJarHash = MessageDigest.getInstance("SHA-256").digest(unifiedJar.get().asFile.readBytes())
            .joinToString("") { "%02x".format(it) }
        commandLine("pwsh", "-NoProfile", "-File", file("scripts/sign-zbs.ps1").absolutePath,
            "-InputJar", unifiedJar.get().asFile.absolutePath, "-ExpectedJarSha256", finalJarHash, "-SteamID64", steamId,
            "-PrivateKeyFile", privateKey, "-PzHome", gameHome,
            "-JdkHome", System.getProperty("java.home"), "-OutputDirectory", signedJarDirectory.get().asFile.absolutePath)
    }
}

val writeUnifiedChecksum by tasks.registering {
    dependsOn(":java:jar")
    inputs.file(unifiedJar)
    outputs.file(checksum)
    doLast {
        val digest = MessageDigest.getInstance("SHA-256")
        unifiedJar.get().asFile.inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        checksum.get().asFile.apply {
            parentFile.mkdirs()
            writeText(digest.digest().joinToString("") { "%02x".format(it) } + "  knox-survivors.jar\n")
        }
    }
}
val stageUnifiedMod by tasks.registering(Sync::class) {
    group = "distribution"
    description = "Stages one Knox mod with one JAR and both optional runtime entrypoints; no installed files touched."
    dependsOn(writeUnifiedChecksum)
    into(layout.buildDirectory.dir("distribution/KnoxSurvivors"))
    // Gradle may otherwise skip Sync when an extra sidecar appears in its output.
    outputs.upToDateWhen {
        withZbsSigning.get() || fileTree(layout.buildDirectory.dir("distribution/KnoxSurvivors")) {
            include("**/*.jar.zbs")
        }.isEmpty
    }
    // Signing is opt-in. Never inherit a sidecar from source or an older payload.
    from(layout.projectDirectory.dir("mod")) { exclude("**/*.jar.zbs") }
    if (withZbsSigning.get()) {
        dependsOn(signUnifiedJarZbs)
        from(signedJarDirectory) {
            include("knox-survivors.jar", "knox-survivors.jar.zbs")
            into("42/media/java")
        }
    } else {
        from(unifiedJar) { rename { "knox-survivors.jar" }; into("42/media/java") }
    }
    from(checksum) { into("42/media/java") }
}
tasks.register<Zip>("packageUnifiedMod") {
    group = "distribution"
    dependsOn(stageUnifiedMod)
    archiveFileName.set("KnoxSurvivors-${project.version}.zip")
    destinationDirectory.set(layout.buildDirectory.dir("distribution/archives"))
    from(layout.buildDirectory.dir("distribution")) {
        include("KnoxSurvivors/**")
    }
}
// Staging into the owner's normal paths is a separate, explicitly authorized operation.
fun requireInstalledStagingApproval() {
    require(providers.gradleProperty("allowInstalledStaging").orNull == "true") {
        "Normal-install staging requires owner approval, verified backups, then -PallowInstalledStaging=true. Use packageUnifiedMod for safe preparation."
    }
    // Unsigned JARs use ZombieBuddy's normal exact-JAR approval (default policy).
    // Author signing remains an explicit opt-in; it is not a staging prerequisite.
}
tasks.register<Sync>("deployLocal") {
    group = "knox survivors"
    dependsOn(stageUnifiedMod)
    doFirst {
        requireInstalledStagingApproval()
        require(localModsRoot.get().isNotBlank()) { "Set localModsRoot in local.properties." }
    }
    into(localModsRoot.map { file(it).resolve("KnoxSurvivors") })
    from(layout.buildDirectory.dir("distribution/KnoxSurvivors"))
}
tasks.register<Sync>("stageWorkshop") {
    group = "knox survivors"
    dependsOn(stageUnifiedMod)
    doFirst {
        requireInstalledStagingApproval()
        require(workshopRoot.get().isNotBlank()) { "Set workshopRoot in local.properties." }
        require(workshopModFolder.get().matches(Regex("[A-Za-z0-9][A-Za-z0-9._ -]*"))) { "Workshop mod folder must be a single name." }
    }
    into(workshopRoot.zip(workshopModFolder) { root, folder -> file(root).resolve(folder).resolve("Contents/mods/KnoxSurvivors") })
    from(layout.buildDirectory.dir("distribution/KnoxSurvivors"))
}
tasks.register("deployDev") {
    group = "knox survivors"
    description = "Stages the SAME unified payload to local and Workshop folders, after explicit approval/backups. Does not launch or upload."
    dependsOn("deployLocal", "stageWorkshop")
}
fun writeWorkshopMetadata(root: File) {
    root.mkdirs()
    val description = file("workshop/description.bbcode").readLines(Charsets.UTF_8)
    val metadata = listOf("version=1", "id=3749727604", "title=[42.21 TEST] Knox Survivors - Survivor NPC Rebuild") +
        description.map { "description=$it" } + listOf("tags=Build 42", "visibility=public")
    root.resolve("workshop.txt").writeText(metadata.joinToString("\n", postfix = "\n"))
    file("mod/poster.png").copyTo(root.resolve("preview.png"), overwrite = true)
}

val prepareWorkshopCandidate by tasks.registering(Sync::class) {
    group = "distribution"
    description = "Prepares the existing Steam item's upload layout under build only; no installation or publication."
    dependsOn(stageUnifiedMod)
    into(layout.buildDirectory.dir("workshop-candidate/KnoxSurvivors"))
    from(layout.buildDirectory.dir("distribution/KnoxSurvivors")) {
        into("Contents/mods/KnoxSurvivors")
    }
    inputs.file("workshop/description.bbcode")
    inputs.file("mod/poster.png")
    // Always reconcile this small release tree: extra output files do not
    // necessarily invalidate Gradle's cache (for example an old signature).
    outputs.upToDateWhen { false }
    // Metadata is generated alongside the synced payload, never inside Contents.
    doLast { writeWorkshopMetadata(destinationDir) }
}

tasks.register<Zip>("packageWorkshopCandidate") {
    group = "distribution"
    description = "Archives the workspace-only Workshop candidate for review; never uploads."
    dependsOn(prepareWorkshopCandidate)
    archiveFileName.set("KnoxSurvivors-workshop-${project.version}.zip")
    destinationDirectory.set(layout.buildDirectory.dir("distribution/archives"))
    from(layout.buildDirectory.dir("workshop-candidate")) {
        include("KnoxSurvivors/**")
    }
    includeEmptyDirs = false
}

tasks.register("prepareWorkshopUpload") {
    group = "knox survivors"
    description = "Prepares existing Workshop staging metadata only; never publishes."
    dependsOn("stageWorkshop")
    doLast {
        writeWorkshopMetadata(file(workshopRoot.get()).resolve(workshopModFolder.get()))
    }
}
