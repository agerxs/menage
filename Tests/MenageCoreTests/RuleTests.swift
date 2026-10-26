import Foundation
import Testing
@testable import MenageCore

private let now = ISO8601DateFormatter().date(from: "2026-10-26T12:00:00Z")!

@Suite struct ProjectDetectorTests {
    /// - `oldapp` : dépôt git, dernier commit le 2025-01-01. `node_modules` et `dist` ignorés,
    ///   `build/` suivi par git (donc du code, à garder).
    /// - `nogit` : projet Flutter sans git. `.dart_tool` oui, `build/` non (ambigu, rien ne prouve que c'est un artefact).
    func makeProjects() throws -> (Fixture, [Project]) {
        let fixture = try Fixture()
        try fixture.file("devapps/oldapp/package.json", contents: "{}")
        try fixture.file("devapps/oldapp/.gitignore", contents: "node_modules\ndist\n")
        try fixture.file("devapps/oldapp/build/script.js", contents: "console.log(1)")
        try fixture.file("devapps/oldapp/node_modules/lib/package.json", contents: "{}")
        try fixture.file("devapps/oldapp/node_modules/lib/blob", bytes: 6 * megabyte)
        try fixture.file("devapps/oldapp/dist/bundle.js", bytes: 6 * megabyte)
        try fixture.git(["init", "-q"], in: "devapps/oldapp")
        try fixture.git(["add", "."], in: "devapps/oldapp")
        try fixture.git(["commit", "-q", "-m", "init"], in: "devapps/oldapp")
        // Rien touché depuis : les fichiers sont plus vieux que le commit.
        try fixture.age("devapps/oldapp", to: ISO8601DateFormatter().date(from: "2024-06-01T00:00:00Z")!)

        try fixture.file("devapps/clients/nogit/pubspec.yaml", contents: "name: nogit")
        try fixture.file("devapps/clients/nogit/.dart_tool/cache", bytes: 1000)
        try fixture.file("devapps/clients/nogit/build/app.apk", bytes: 1000)

        let projects = ProjectDetector(roots: [fixture.url("devapps")]).detect()
        return (fixture, projects.sorted { $0.name < $1.name })
    }

    @Test func findsProjectsButNotInsideDependencies() throws {
        let (_, projects) = try makeProjects()
        #expect(projects.map(\.name) == ["clients/nogit", "oldapp"])
    }

    @Test func gitTrackedAndUnprovableFoldersAreNeverArtifacts() throws {
        let (_, projects) = try makeProjects()
        #expect(projects[1].artifacts.map(\.lastPathComponent).sorted() == ["dist", "node_modules"])
        #expect(projects[0].artifacts.map(\.lastPathComponent) == [".dart_tool"])
        #expect(projects[1].rebuildCommands == ["npm install"])
    }

    @Test func lastActivityComesFromGitThenFromFiles() throws {
        let (_, projects) = try makeProjects()
        #expect(projects[1].lastActivity == ISO8601DateFormatter().date(from: "2025-01-01T12:00:00Z")
            .map { $0.addingTimeInterval(-Double(TimeZone.current.secondsFromGMT(for: $0))) })
        #expect(projects[0].lastActivity.map { Date().timeIntervalSince($0) < 3600 } == true)
    }

    @Test func uncommittedEditsMakeAProjectActive() throws {
        let (fixture, _) = try makeProjects()
        try fixture.file("devapps/oldapp/src/new.js", contents: "// modifié aujourd'hui, pas commité")
        let projects = ProjectDetector(roots: [fixture.url("devapps")]).detect()
        let oldapp = try #require(projects.first { $0.name == "oldapp" })
        #expect(oldapp.lastActivity.map { Date().timeIntervalSince($0) < 3600 } == true)
    }

    /// git a enregistré `Build/main.c`, le disque a `build/` (APFS ignore la casse) : c'est du code suivi.
    @Test func trackedFolderWithDifferentCaseIsKept() throws {
        let fixture = try Fixture()
        try fixture.file("devapps/app/package.json", contents: "{}")
        try fixture.file("devapps/app/Build/main.c", contents: "int main(){}")
        try fixture.file("devapps/app/Pods/Lib.m", contents: "// suivi")
        try fixture.git(["init", "-q"], in: "devapps/app")
        try fixture.git(["add", "."], in: "devapps/app")
        try fixture.git(["commit", "-q", "-m", "init"], in: "devapps/app")
        try fixture.file("devapps/app/.gitignore", contents: "build/\n")
        try FileManager.default.moveItem(at: fixture.url("devapps/app/Build"), to: fixture.url("devapps/app/tmp"))
        try FileManager.default.moveItem(at: fixture.url("devapps/app/tmp"), to: fixture.url("devapps/app/build"))
        try fixture.file("devapps/app/Podfile", contents: "")
        try FileManager.default.moveItem(at: fixture.url("devapps/app/Pods"), to: fixture.url("devapps/app/tmp"))
        try FileManager.default.moveItem(at: fixture.url("devapps/app/tmp"), to: fixture.url("devapps/app/pods"))

        let projects = ProjectDetector(roots: [fixture.url("devapps")]).detect()
        #expect(projects.flatMap(\.artifacts).isEmpty)
    }

    /// Un projet dans un dossier ignoré par un dépôt parent : git dirait « ignoré » pour tout.
    @Test func projectInsideAnIgnoredFolderIsTreatedAsUntracked() throws {
        let fixture = try Fixture()
        try fixture.file("devapps/mono/.gitignore", contents: "experiments/\n")
        try fixture.git(["init", "-q"], in: "devapps/mono")
        try fixture.git(["add", "."], in: "devapps/mono")
        try fixture.git(["commit", "-q", "-m", "init"], in: "devapps/mono")
        try fixture.file("devapps/mono/experiments/app/package.json", contents: "{}")
        try fixture.file("devapps/mono/experiments/app/build/main.js", contents: "// écrit à la main")
        try fixture.file("devapps/mono/experiments/app/node_modules/x/index.js", contents: "")

        let projects = ProjectDetector(roots: [fixture.url("devapps")]).detect()
        let app = try #require(projects.first { $0.name == "mono/experiments/app" })
        #expect(app.artifacts.map(\.lastPathComponent) == ["node_modules"])
    }

    @Test func onlyInactiveProjectsAreProposed() throws {
        let (fixture, projects) = try makeProjects()
        let scan = ProjectArtifactsRule().scan(fixture.context(projects: projects, now: now))
        #expect(scan.candidates.map(\.title) == ["oldapp"])
        #expect(scan.candidates[0].bytes >= 12 * Int64(megabyte))
        #expect(scan.candidates[0].detail.contains("npm install"))
        guard case .trash(let urls) = scan.candidates[0].action else { Issue.record("action attendue : Corbeille"); return }
        #expect(urls.map(\.lastPathComponent).sorted() == ["dist", "node_modules"])
    }
}

@Suite struct DownloadsRuleTests {
    let apps = ["DaVinci Resolve", "FL Studio 2025", "ChatGPT", "Obsidian", "Telegram", "Ménage"]

    @Test func matchesInstallersToInstalledApps() {
        #expect(InstallerMatcher.matchingApp(forInstaller: "DaVinci_Resolve_21.1_Mac.dmg", installedApps: apps) == "DaVinci Resolve")
        #expect(InstallerMatcher.matchingApp(forInstaller: "flstudio_mac_26.1.6.5406.dmg", installedApps: apps) == "FL Studio 2025")
        #expect(InstallerMatcher.matchingApp(forInstaller: "ChatGPT.dmg", installedApps: apps) == "ChatGPT")
        #expect(InstallerMatcher.matchingApp(forInstaller: "Facture-2026.pdf.dmg", installedApps: apps) == nil)
    }

    /// Le nom de l'app doit ouvrir le nom du fichier, pas y apparaître n'importe où.
    @Test func personalArchivesAreNotInstallers() {
        #expect(InstallerMatcher.matchingApp(forInstaller: "Sauvegarde Telegram 2025.dmg", installedApps: apps) == nil)
        #expect(InstallerMatcher.matchingApp(forInstaller: "demenagement_mac.dmg", installedApps: apps) == nil)
    }

    @Test func zipsAreNeverTakenForInstallers() {
        #expect(!InstallerMatcher.looksLikeInstaller("DaVinci_Resolve_21.1_Mac.zip"))
        #expect(!InstallerMatcher.looksLikeInstaller("Obsidian_vault.zip"))
        #expect(InstallerMatcher.looksLikeInstaller("ChatGPT.dmg"))
        #expect(InstallerMatcher.looksLikeInstaller("Xcode_26.xip"))
        #expect(!InstallerMatcher.looksLikeInstaller("film.mp4"))
    }

    @Test func appsInstalledInAFolderAreFoundAndAppleAppsSkipped() throws {
        let fixture = try Fixture()
        try fixture.directory("Applications/ChatGPT.app")
        try fixture.directory("Applications/DaVinci Resolve/DaVinci Resolve.app")
        try fixture.directory("Applications/DaVinci Resolve/Uninstall Resolve.app")
        try fixture.file("Applications/Pages.app/Contents/Info.plist", contents: """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.apple.iWork.Pages</string></dict></plist>
        """)
        #expect(InstallerMatcher.installedApps(in: [fixture.url("Applications")]).sorted()
            == ["ChatGPT", "DaVinci Resolve", "Uninstall Resolve"])
    }

    @Test func installersAndLargeFilesDoNotOverlap() throws {
        let fixture = try Fixture()
        try fixture.directory("Applications/ChatGPT.app")
        try fixture.file("home/Downloads/ChatGPT.dmg", bytes: 30 * megabyte)
        try fixture.file("home/Downloads/Obsidian_vault.zip", bytes: 30 * megabyte)
        let context = fixture.context(now: now)

        let installers = InstallersRule().scan(context).candidates
        #expect(installers.map(\.title) == ["ChatGPT.dmg"])
        #expect(installers[0].detail.contains("ChatGPT"))

        // Seuil des gros fichiers à 500 Mo : rien ici, et l'installateur n'y serait jamais compté deux fois.
        #expect(LargeDownloadsRule().scan(context).candidates.isEmpty)
    }
}

@Suite struct AndroidRuleTests {
    /// Pixel utilise android-35 (installée), Broken pointe vers android-36.1 (absente), android-37 est orpheline.
    func makeAndroid() throws -> Fixture {
        let fixture = try Fixture()
        try fixture.file("home/.android/avd/Pixel.avd/config.ini", contents: "hw.ramSize=2048\nimage.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\n")
        try fixture.file("home/.android/avd/Pixel.avd/snapshots/default_boot/ram.bin", bytes: 2000)
        try fixture.file("home/.android/avd/Pixel.ini", contents: "path=x")
        try fixture.file("home/.android/avd/Broken.avd/config.ini", contents: "image.sysdir.1=system-images/android-36.1/google_apis_playstore/arm64-v8a/\n")
        try fixture.file("home/.android/avd/Broken.avd/userdata.img", bytes: 3000)
        try fixture.file("home/.android/avd/Broken.ini", contents: "path=y")
        try fixture.file("home/Library/Android/sdk/system-images/android-35/google_apis/arm64-v8a/system.img", bytes: 1000)
        try fixture.file("home/Library/Android/sdk/system-images/android-37.1/google_apis_playstore_ps16k/arm64-v8a/system.img", bytes: 1000)
        return fixture
    }

    @Test func parsesTheImageOfAnEmulator() {
        #expect(AndroidInventory.systemImage(fromConfig: "a=b\nimage.sysdir.1 = system-images/android-35/google_apis/arm64-v8a/\n")
            == "system-images/android-35/google_apis/arm64-v8a")
        #expect(AndroidInventory.systemImage(fromConfig: "a=b") == nil)
    }

    @Test func unusedImagesBrokenEmulatorsAndSnapshots() throws {
        let fixture = try makeAndroid()
        let context = fixture.context(now: now)

        #expect(UnusedAndroidImagesRule().scan(context).candidates.map(\.title) == ["android-37.1 · google_apis_playstore_ps16k · arm64-v8a"])

        let broken = BrokenEmulatorsRule().scan(context).candidates
        #expect(broken.map(\.title) == ["Broken"])
        guard case .trash(let urls) = broken[0].action else { Issue.record("action attendue : Corbeille"); return }
        #expect(urls.map(\.lastPathComponent) == ["Broken.avd", "Broken.ini"])

        #expect(EmulatorSnapshotsRule().scan(context).candidates.map(\.title) == ["Pixel"])
    }

    /// SDK ailleurs que prévu (ANDROID_HOME non transmis à une app du Finder) : on ne déclare rien cassé.
    @Test func missingSDKBreaksNothing() throws {
        let fixture = try makeAndroid()
        var context = fixture.context(now: now)
        context.androidSDK = fixture.url("nowhere/sdk")
        let scan = BrokenEmulatorsRule().scan(context)
        #expect(scan.candidates.isEmpty)
        #expect(scan.note?.contains("introuvable") == true)
    }

    /// `ndkVersion = flutter.ndkVersion` : la version vient du SDK Flutter désigné par local.properties.
    @Test func flutterDefaultNDKIsKept() throws {
        let fixture = try Fixture()
        try fixture.file("flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt",
                         contents: "class FlutterExtension {\n    val ndkVersion: String = \"28.2.13676358\"\n}")
        try fixture.file("app/android/app/build.gradle.kts", contents: "android {\n    ndkVersion = flutter.ndkVersion\n}")
        try fixture.file("app/android/local.properties", contents: "sdk.dir=/x\nflutter.sdk=\(fixture.url("flutter").path)\n")
        let project = Project(
            url: fixture.url("app/android"), name: "app/android", ecosystems: ["Gradle"],
            artifacts: [], rebuildCommands: [], lastActivity: nil
        )
        #expect(OldNDKRule.referencedVersions(in: [project]) == ["28.2.13676358"])
    }

    @Test func ndkKeepsNewestAndReferencedVersions() throws {
        #expect(OldNDKRule.removable(installed: ["27.0.12077973", "28.2.13676358", "29.0.14206865"], referenced: ["27.0.12077973"]) == ["28.2.13676358"])
        #expect(OldNDKRule.removable(installed: ["9.1", "10.0"], referenced: []) == ["9.1"])
        #expect(OldNDKRule.removable(installed: [], referenced: []) == [])

        let fixture = try Fixture()
        try fixture.file("app/android/app/build.gradle.kts", contents: "android {\n    ndkVersion = \"28.2.13676358\"\n}")
        let project = Project(
            url: fixture.url("app/android"), name: "app/android", ecosystems: ["Gradle"],
            artifacts: [], rebuildCommands: [], lastActivity: nil
        )
        #expect(OldNDKRule.referencedVersions(in: [project]) == ["28.2.13676358"])
    }
}

@Suite struct ToolOutputTests {
    @Test func dockerSizes() {
        #expect(DockerRule.parseSize("0B") == 0)
        #expect(DockerRule.parseSize("12.5kB") == 12_500)
        #expect(DockerRule.parseSize("350MB") == 350_000_000)
        #expect(DockerRule.parseSize("1.2GB") == 1_200_000_000)
        #expect(DockerRule.parseSize("n/a") == 0)
    }

    @Test func dockerReclaimableBuildCache() {
        let output = """
        {"Active":"2","Reclaimable":"1.5GB (40%)","Size":"3.8GB","TotalCount":"9","Type":"Images"}
        {"Active":"0","Reclaimable":"2.3GB","Size":"2.3GB","TotalCount":"41","Type":"Build Cache"}
        """
        #expect(DockerRule.reclaimable(ofType: "Build Cache", inSystemDF: output) == 2_300_000_000)
        #expect(DockerRule.reclaimable(ofType: "Volumes", inSystemDF: output) == 0)
    }

    @Test func unavailableSimulators() {
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[{"udid":"A1","name":"iPhone 15","isAvailable":false}],
        "com.apple.CoreSimulator.SimRuntime.iOS-18-0":[]}}
        """
        #expect(UnavailableSimulatorsRule.unavailableDevices(fromJSON: json).map(\.name) == ["iPhone 15"])
        #expect(UnavailableSimulatorsRule.unavailableDevices(fromJSON: "pas du json").isEmpty)
    }

    @Test func derivedDataFolderNames() {
        #expect(DerivedDataRule.projectName("Runner-fzbvdkqmejxhwygoxiuwcmrdkuoz") == "Runner")
        #expect(DerivedDataRule.projectName("ModuleCache.noindex") == "ModuleCache.noindex")
    }

    @Test func cachesSkipMacOSAndPlaywright() throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Caches/com.openai.codex/blob", bytes: 60 * megabyte)
        try fixture.file("home/Library/Caches/com.apple.textunderstandingd/blob", bytes: 60 * megabyte)
        try fixture.file("home/Library/Caches/ms-playwright/chromium", bytes: 60 * megabyte)
        try fixture.file("home/Library/Caches/tiny/blob", bytes: 1000)
        #expect(ApplicationCachesRule().scan(fixture.context()).candidates.map(\.title) == ["com.openai.codex"])
    }
}
