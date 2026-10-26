import Foundation

/// La couleur d'un rectangle de la carte : ce qu'est, à vue de nez, un fichier ou un dossier.
public enum FileCategory: String, Sendable, CaseIterable {
    case code, medias, apps, archives, caches, systeme, autres

    public var label: String {
        switch self {
        case .code: "Code et builds"
        case .medias: "Médias"
        case .apps: "Apps"
        case .archives: "Archives et images disque"
        case .caches: "Caches"
        case .systeme: "Bibliothèque et système"
        case .autres: "Autres"
        }
    }

    static let codeFolders: Set<String> = [
        "node_modules", ".dart_tool", "Pods", ".gradle", "vendor", ".next", ".git", "target", ".venv",
        "DerivedData", ".pub-cache", ".npm", ".cargo", ".rustup", "devapps", "develop", "Projects", "Developer",
    ]
    static let mediaFolders: Set<String> = ["Movies", "Music", "Pictures", "Photos Library.photoslibrary"]
    static let mediaExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "mp3", "wav", "aif", "aiff", "flac", "m4a",
        "jpg", "jpeg", "png", "heic", "gif", "raw", "cr2", "psd", "braw", "drp",
    ]
    static let archiveExtensions: Set<String> = ["dmg", "zip", "pkg", "xip", "iso", "tar", "gz", "tgz", "7z", "rar", "apk", "ipa", "aab"]
    static let codeExtensions: Set<String> = ["swift", "dart", "ts", "js", "php", "kt", "java", "py", "rs", "go", "jar", "so", "a", "o"]

    public static func of(_ node: DiskNode) -> FileCategory {
        if node.isOthers { return .autres }
        let path = node.path
        let name = node.name
        let ext = (name as NSString).pathExtension.lowercased()

        if path.contains("/Library/Caches/") || name == "Caches" || name == "DerivedData" || path.contains("/DerivedData/") {
            return .caches
        }
        if ext == "app" || name == "Applications" { return .apps }
        if node.kind == .file {
            if mediaExtensions.contains(ext) { return .medias }
            if archiveExtensions.contains(ext) { return .archives }
            if codeExtensions.contains(ext) { return .code }
        }
        if codeFolders.contains(name) || path.contains("/devapps/") || path.contains("/node_modules/") { return .code }
        if mediaFolders.contains(name) { return .medias }
        if name == "Library" || path.contains("/Library/") || name.hasPrefix(".") { return .systeme }
        return .autres
    }
}
