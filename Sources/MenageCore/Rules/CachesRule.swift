import Foundation

public struct ApplicationCachesRule: CleanupRule {
    public let id = "caches"
    public let title = "Caches des apps"
    public let explanation = "Fichiers temporaires que chaque app recrée au besoin. Quitte l'app concernée avant pour qu'elle ne les recrée pas aussitôt."
    public let risk = Risk.sansRisque

    /// Ce que macOS gère lui-même (y compris sans préfixe `com.apple.` : voix de Siri, Plans…),
    /// et ce qui porte le nom de cache sans en être (les navigateurs de Playwright, à retélécharger).
    static let excludedPrefixes = [
        "com.apple.", "CloudKit", "SiriTTS", "GeoServices", "familycircled", "PassKit", "ms-playwright",
    ]
    static let minimumBytes: Int64 = 50_000_000

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        let caches = context.home.appendingPathComponent("Library/Caches")
        let candidates = subdirectories(of: caches)
            .filter { folder in !Self.excludedPrefixes.contains { folder.lastPathComponent.hasPrefix($0) } }
            .map { Candidate.trash($0, detail: "~/Library/Caches/\($0.lastPathComponent)") }
            .filter { $0.bytes >= Self.minimumBytes }
            .sorted { $0.bytes > $1.bytes }
        return RuleScan(candidates: candidates)
    }
}
