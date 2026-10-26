import Foundation

public struct ProjectArtifactsRule: CleanupRule {
    public let id = "projects.artifacts"
    public let title = "Projets inactifs"
    public let explanation = "Dépendances et builds des projets sans activité récente. Le code n'est pas touché ; une commande suffit à tout reconstruire."
    public let risk = Risk.regenerable
    static let minimumBytes: Int64 = 10_000_000

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        let limit = context.now.addingTimeInterval(-Double(context.inactivityDays) * 86_400)
        let candidates = context.projects
            // Sans date d'activité, on ne peut pas dire que le projet dort : on s'abstient.
            .filter { project in project.lastActivity.map { $0 < limit } ?? false && !project.artifacts.isEmpty }
            .map { project -> Candidate in
                let bytes = project.artifacts.reduce(Int64(0)) { $0 + DirectorySize.of($1) }
                let folders = project.artifacts.map(\.lastPathComponent).joined(separator: ", ")
                let when = project.lastActivity.map { ago($0, now: context.now) } ?? ""
                let rebuild = project.rebuildCommands.joined(separator: " · ")
                return Candidate(
                    id: candidateID(project.url.path),
                    title: project.name,
                    detail: "Dernière activité \(when) · \(folders) · pour reconstruire : \(rebuild)",
                    bytes: bytes,
                    action: .trash(project.artifacts),
                    location: project.url
                )
            }
            .filter { $0.bytes >= Self.minimumBytes }
            .sorted { $0.bytes > $1.bytes }
        return RuleScan(candidates: candidates)
    }
}
