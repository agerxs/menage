import Foundation

/// Ce qu'on sait des émulateurs et du SDK Android, lu sur le disque.
struct AndroidInventory {
    struct VirtualDevice {
        var name: String
        var directory: URL
        var iniFile: URL
        /// `system-images/android-35/google_apis/arm64-v8a`
        var systemImage: String?
    }

    var sdk: URL
    var devices: [VirtualDevice]
    /// Chemins relatifs au SDK, sans `/` final.
    var installedImages: [String]
    /// Sans dossier `system-images`, le SDK n'est pas là où on le cherche : on ne conclut rien.
    var sdkFound: Bool

    init(home: URL, sdk: URL) {
        self.sdk = sdk
        let avdDirectory = home.appendingPathComponent(".android/avd")
        devices = subdirectories(of: avdDirectory)
            .filter { $0.pathExtension == "avd" }
            .map { directory in
                let config = (try? String(contentsOf: directory.appendingPathComponent("config.ini"), encoding: .utf8)) ?? ""
                return VirtualDevice(
                    name: directory.deletingPathExtension().lastPathComponent,
                    directory: directory,
                    iniFile: avdDirectory.appendingPathComponent(directory.deletingPathExtension().lastPathComponent + ".ini"),
                    systemImage: Self.systemImage(fromConfig: config)
                )
            }
        let images = sdk.appendingPathComponent("system-images")
        sdkFound = FileManager.default.fileExists(atPath: images.path)
        installedImages = subdirectories(of: images).flatMap { api in
            subdirectories(of: api).flatMap { tag in
                subdirectories(of: tag).map { abi in
                    "system-images/\(api.lastPathComponent)/\(tag.lastPathComponent)/\(abi.lastPathComponent)"
                }
            }
        }
    }

    static func systemImage(fromConfig config: String) -> String? {
        for line in config.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "image.sysdir.1" else { continue }
            return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return nil
    }

    var usedImages: Set<String> { Set(devices.compactMap(\.systemImage)) }

    func isBroken(_ device: VirtualDevice) -> Bool {
        guard sdkFound, let image = device.systemImage else { return false }
        return !installedImages.contains(image)
    }

    static func describe(image: String) -> String {
        image.split(separator: "/").dropFirst().joined(separator: " · ")
    }
}

public struct UnusedAndroidImagesRule: CleanupRule {
    public let id = "android.images"
    public let title = "Android : images système inutilisées"
    public let explanation = "Images qu'aucun émulateur n'utilise. Android Studio les retélécharge si tu crées un émulateur qui en a besoin."
    public let risk = Risk.regenerable

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        let inventory = AndroidInventory(home: context.home, sdk: context.androidSDK)
        let used = inventory.usedImages
        let candidates = inventory.installedImages
            .filter { !used.contains($0) }
            .map { Candidate.trash(context.androidSDK.appendingPathComponent($0), title: AndroidInventory.describe(image: $0), detail: "Aucun émulateur ne l'utilise") }
            .filter { $0.bytes > 0 }
        return RuleScan(candidates: candidates)
    }
}

public struct BrokenEmulatorsRule: CleanupRule {
    public let id = "android.broken"
    public let title = "Android : émulateurs cassés"
    public let explanation = "Émulateurs dont l'image système n'est plus installée : ils ne démarrent plus. Leurs données (apps installées, comptes) partent avec."
    public let risk = Risk.aVerifier

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        let inventory = AndroidInventory(home: context.home, sdk: context.androidSDK)
        if !inventory.devices.isEmpty, !inventory.sdkFound {
            return RuleScan(note: "SDK Android introuvable dans \(context.androidSDK.path) : impossible de juger les émulateurs")
        }
        let candidates = inventory.devices.filter(inventory.isBroken).map { device in
            Candidate(
                id: candidateID(device.directory.path),
                title: device.name,
                detail: "Pointe vers \(AndroidInventory.describe(image: device.systemImage ?? "")), absente du SDK",
                bytes: DirectorySize.of(device.directory) + DirectorySize.of(device.iniFile),
                action: .trash([device.directory, device.iniFile].filter { FileManager.default.fileExists(atPath: $0.path) }),
                location: device.directory
            )
        }
        return RuleScan(candidates: candidates)
    }
}

public struct EmulatorSnapshotsRule: CleanupRule {
    public let id = "android.snapshots"
    public let title = "Android : sauvegardes d'émulateurs"
    public let explanation = "États sauvegardés pour un démarrage rapide. Sans eux, l'émulateur démarre à froid la prochaine fois, c'est tout."
    public let risk = Risk.regenerable

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        let inventory = AndroidInventory(home: context.home, sdk: context.androidSDK)
        let candidates = inventory.devices
            .filter { !inventory.isBroken($0) }
            .map { Candidate.trash($0.directory.appendingPathComponent("snapshots"), title: $0.name, detail: "Démarrage rapide de \($0.name)") }
            .filter { $0.bytes > 0 }
        return RuleScan(candidates: candidates)
    }
}

public struct OldNDKRule: CleanupRule {
    public let id = "android.ndk"
    public let title = "Android : anciennes versions du NDK"
    public let explanation = "On garde la plus récente et celles qu'un projet demande explicitement. Gradle retélécharge une version manquante au besoin."
    public let risk = Risk.regenerable

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        let ndk = context.androidSDK.appendingPathComponent("ndk")
        let versions = subdirectories(of: ndk).map(\.lastPathComponent)
        let referenced = Self.referencedVersions(in: context.projects)
        let candidates = Self.removable(installed: versions, referenced: referenced).map {
            Candidate.trash(ndk.appendingPathComponent($0), title: "NDK \($0)", detail: "Plus récente gardée : \(Self.newest(versions) ?? "")")
        }
        return RuleScan(candidates: candidates)
    }

    static func removable(installed: [String], referenced: Set<String>) -> [String] {
        guard let newest = newest(installed) else { return [] }
        return installed.filter { $0 != newest && !referenced.contains($0) }.sorted()
    }

    static func newest(_ versions: [String]) -> String? {
        versions.max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    /// `ndkVersion "27.0.12077973"`, `ndkVersion = "…"`, ou `val ndkVersion: String = "…"` (Flutter).
    nonisolated(unsafe) static let versionPattern = /ndkVersion(?:\s*:\s*String)?\s*=?\s*["']([0-9][0-9.]*)["']/

    /// Les versions demandées par les fichiers Gradle des projets. `ndkVersion = flutter.ndkVersion`
    /// renvoie à la version fixée par le SDK Flutter du projet (`flutter.sdk` dans `local.properties`).
    static func referencedVersions(in projects: [Project]) -> Set<String> {
        var versions: Set<String> = []
        var flutterSDKs: Set<String> = []
        for project in projects where project.ecosystems.contains("Gradle") {
            for file in ["build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts"] {
                guard let text = try? String(contentsOf: project.url.appendingPathComponent(file), encoding: .utf8) else { continue }
                for match in text.matches(of: versionPattern) { versions.insert(String(match.1)) }
                if text.contains("flutter.ndkVersion"), let sdk = flutterSDK(of: project.url) { flutterSDKs.insert(sdk) }
            }
        }
        for sdk in flutterSDKs {
            versions.formUnion(flutterDefaultVersions(sdk: URL(fileURLWithPath: sdk)))
        }
        return versions
    }

    static func flutterSDK(of gradleProject: URL) -> String? {
        guard let properties = try? String(contentsOf: gradleProject.appendingPathComponent("local.properties"), encoding: .utf8) else {
            return nil
        }
        for line in properties.split(whereSeparator: \.isNewline) where line.hasPrefix("flutter.sdk=") {
            return String(line.dropFirst("flutter.sdk=".count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func flutterDefaultVersions(sdk: URL) -> Set<String> {
        let gradle = sdk.appendingPathComponent("packages/flutter_tools/gradle/src/main")
        let files = ["kotlin/FlutterExtension.kt", "groovy/flutter.groovy"].map { gradle.appendingPathComponent($0) }
        return Set(files.flatMap { file -> [String] in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
            return text.matches(of: versionPattern).map { String($0.1) }
        })
    }
}
