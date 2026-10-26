import Foundation

/// Repère les installateurs dont l'app est déjà installée. Ils sont pré-cochés « Sans risque »,
/// donc la règle préfère rater un installateur que prendre une archive personnelle pour un.
enum InstallerMatcher {
    /// Pas de `.zip` : une archive peut contenir n'importe quoi (`CV_Pages_Mac.zip`, une sauvegarde).
    /// Un zip d'installation reste visible dans « Gros fichiers », à vérifier.
    static let extensions: Set<String> = ["dmg", "pkg", "xip"]

    /// Le nom de l'app installée que cet installateur a servi à installer, s'il y en a une.
    ///
    /// Le nom du fichier doit **commencer** par celui de l'app : `DaVinci_Resolve_21.1_Mac.dmg` →
    /// `DaVinci Resolve`, `flstudio_mac_26.1.dmg` → `FL Studio 2025`, mais pas
    /// `Sauvegarde Telegram 2025.dmg`. On compare en minuscules, sans accents, chiffres ni ponctuation.
    static func matchingApp(forInstaller fileName: String, installedApps: [String]) -> String? {
        let installer = normalize((fileName as NSString).deletingPathExtension)
        return installedApps
            .map { ($0, normalize($0)) }
            .filter { $0.1.count >= 4 && installer.hasPrefix($0.1) }
            .max { $0.1.count < $1.1.count }?
            .0
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars
            .filter { CharacterSet.lowercaseLetters.contains($0) && $0.isASCII }
            .map(String.init)
            .joined()
    }

    /// Les apps à la racine, et un niveau plus bas : certaines s'installent dans un dossier
    /// (`/Applications/DaVinci Resolve/DaVinci Resolve.app`). Les apps d'Apple (Pages, Safari, Xcode…)
    /// ne s'installent jamais par un .dmg téléchargé : leurs noms courts et courants sont écartés.
    static func installedApps(in directories: [URL]) -> [String] {
        let fileManager = FileManager.default
        func apps(in directory: URL) -> [URL] {
            ((try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }
        return directories.flatMap { directory -> [URL] in
            let entries = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return entries.flatMap { $0.pathExtension == "app" ? [$0] : apps(in: $0) }
        }
        .filter { Bundle(url: $0)?.bundleIdentifier?.hasPrefix("com.apple.") != true }
        .map { $0.deletingPathExtension().lastPathComponent }
    }

    static func looksLikeInstaller(_ fileName: String) -> Bool {
        extensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    static func installers(in context: CleanupContext) -> [(file: URL, app: String)] {
        let apps = installedApps(in: context.applicationDirectories)
        return downloadedFiles(in: context, recursive: false)
            .filter { looksLikeInstaller($0.lastPathComponent) }
            .compactMap { file in matchingApp(forInstaller: file.lastPathComponent, installedApps: apps).map { (file, $0) } }
    }
}

func downloadedFiles(in context: CleanupContext, recursive: Bool) -> [URL] {
    let downloads = context.home.appendingPathComponent("Downloads")
    let keys: [URLResourceKey] = [.isRegularFileKey]
    if recursive {
        guard let enumerator = FileManager.default.enumerator(
            at: downloads, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }
        var files: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            if (try? item.resourceValues(forKeys: Set(keys)))?.isRegularFile == true { files.append(item) }
        }
        return files
    }
    return ((try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: keys)) ?? [])
        .filter { (try? $0.resourceValues(forKeys: Set(keys)))?.isRegularFile == true }
}

public struct InstallersRule: CleanupRule {
    public let id = "downloads.installers"
    public let title = "Installateurs déjà utilisés"
    public let explanation = "Images disque et paquets (.dmg, .pkg, .xip) dans Téléchargements dont l'app est déjà installée."
    public let risk = Risk.sansRisque
    static let minimumBytes: Int64 = 20_000_000

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        let candidates = InstallerMatcher.installers(in: context)
            .map { Candidate.trash($0.file, detail: "\($0.app) est déjà dans Applications") }
            .filter { $0.bytes >= Self.minimumBytes }
            .sorted { $0.bytes > $1.bytes }
        return RuleScan(candidates: candidates)
    }
}

public struct LargeDownloadsRule: CleanupRule {
    public let id = "downloads.large"
    public let title = "Gros fichiers dans Téléchargements"
    public let explanation = "Fichiers de plus de 500 Mo. Vérifie que tu n'en as plus besoin ou qu'ils sont ailleurs."
    public let risk = Risk.aVerifier
    static let minimumBytes: Int64 = 500_000_000

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        let installers = Set(InstallerMatcher.installers(in: context).map(\.file.path))
        let candidates = downloadedFiles(in: context, recursive: true)
            .filter { !installers.contains($0.path) }
            .map { file -> Candidate in
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let relative = String(file.path.dropFirst(context.home.path.count + 1))
                let when = modified.map { ", modifié \(ago($0, now: context.now))" } ?? ""
                return Candidate.trash(file, detail: "~/\(relative)\(when)")
            }
            .filter { $0.bytes >= Self.minimumBytes }
            .sorted { $0.bytes > $1.bytes }
        return RuleScan(candidates: candidates)
    }
}
