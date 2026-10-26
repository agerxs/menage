import Foundation

/// Ce qu'on accepte de mettre à la Corbeille depuis la carte ou la liste des gros fichiers.
///
/// Plus strict que le nettoyeur : là, chaque règle sait ce qu'elle propose ; ici, l'utilisateur peut
/// viser n'importe quel nœud. Dans `~/Library`, seul ce qui se régénère est permis (caches, outils de
/// développement, SDK Android, journaux). Les données d'apps (`Application Support`, `Containers`,
/// `Group Containers`, `Preferences`…) se gèrent depuis l'app concernée, ou à la main dans le Finder.
public struct ManualTrashPolicy: Sendable {
    public var protected: ProtectedPaths
    public var home: URL

    static let allowedInLibrary: Set<String> = ["caches", "developer", "android", "logs"]

    public init(protected: ProtectedPaths, home: URL) {
        self.protected = protected
        self.home = home
    }

    /// La raison du refus, ou `nil` si ce chemin peut aller à la Corbeille.
    public func refusal(for path: String) -> String? {
        if path.hasSuffix("/\u{2026}") { return "regroupement de petits éléments, pas un vrai dossier" }
        if let reason = protected.refusal(for: URL(fileURLWithPath: path)) { return reason }
        let library = (home.path as NSString).standardizingPath.lowercased() + "/library/"
        let lowered = (path as NSString).standardizingPath.lowercased()
        if lowered.hasPrefix(library) {
            let top = lowered.dropFirst(library.count).split(separator: "/").first.map(String.init) ?? ""
            if !Self.allowedInLibrary.contains(top) {
                return "données d'apps : à gérer depuis l'app concernée ou dans le Finder"
            }
        }
        return nil
    }
}
