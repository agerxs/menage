import Foundation

/// Dernier garde-fou avant la Corbeille, quel que soit ce que propose une règle.
///
/// Deux sortes de chemins :
/// - les **sanctuaires** : ni eux ni rien à l'intérieur (`~/ai-brain`, `~/.ssh`, iCloud…) ;
/// - les **ancres** : on peut nettoyer à l'intérieur, mais jamais l'ancre elle-même
///   (`~/Library`, `~/Downloads`, `~/devapps`…).
/// Supprimer un parent d'un sanctuaire ou d'une ancre est refusé aussi : ce serait les supprimer.
public struct ProtectedPaths: Sendable {
    public var sanctuaries: [String]
    public var anchors: [String]

    public init(sanctuaries: [String], anchors: [String]) {
        self.sanctuaries = sanctuaries.map(Self.normalize)
        self.anchors = anchors.map(Self.normalize)
    }

    public static func standard(home: URL, projectRoots: [URL] = []) -> ProtectedPaths {
        let h = home.path
        return ProtectedPaths(
            sanctuaries: [
                "\(h)/ai-brain", "\(h)/.ssh", "\(h)/.gnupg", "\(h)/Documents", "\(h)/Desktop",
                "\(h)/Library/Keychains", "\(h)/Library/Mobile Documents", "\(h)/Library/Mail",
                "\(h)/Library/Messages", "\(h)/Pictures", "/System", "/usr", "/bin", "/sbin",
                // `standardizingPath` réécrit /private/var en /var quand le chemin existe : les deux formes.
                "/private", "/var", "/etc", "/tmp",
            ],
            anchors: [
                "/", "/Applications", "/Library", "/Users", h, "\(h)/Library", "\(h)/Library/Caches",
                "\(h)/Library/Application Support", "\(h)/Library/Containers", "\(h)/Library/Group Containers",
                "\(h)/Library/Preferences",
                "\(h)/Library/Developer", "\(h)/Library/Android", "\(h)/Downloads", "\(h)/Applications",
                "\(h)/.android", "\(h)/Movies", "\(h)/Music",
            ] + projectRoots.map(\.path)
        )
    }

    /// La raison du refus, ou `nil` si le chemin peut aller à la Corbeille.
    public func refusal(for url: URL) -> String? {
        let path = Self.normalize(url.path)
        for sanctuary in sanctuaries where path == sanctuary || path.hasPrefix(sanctuary + "/") || Self.isAncestor(path, of: sanctuary) {
            return "protégé (\(sanctuary))"
        }
        for anchor in anchors where path == anchor || Self.isAncestor(path, of: anchor) {
            return "dossier racine protégé (\(anchor))"
        }
        return nil
    }

    public func isProtected(_ url: URL) -> Bool {
        refusal(for: url) != nil
    }

    private static func isAncestor(_ path: String, of other: String) -> Bool {
        path == "/" ? other != "/" : other.hasPrefix(path + "/")
    }

    /// En minuscules : APFS ignore la casse, `~/AI-BRAIN` est le même dossier que `~/ai-brain`.
    private static func normalize(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath.lowercased()
        return standardized.isEmpty ? "/" : standardized
    }
}
