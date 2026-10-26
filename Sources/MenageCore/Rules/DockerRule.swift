import Foundation

public struct DockerRule: CleanupRule {
    public let id = "docker"
    public let title = "Docker : cache de build et images orphelines"
    public let explanation = "Couches de build en cache et images sans nom ni conteneur. Tes conteneurs, volumes et images nommées ne sont pas touchés."
    public let risk = Risk.regenerable

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        guard let docker = Executables.docker else { return RuleScan(note: "Docker n'est pas installé") }
        guard let usage = context.runner.run(docker, ["system", "df", "--format", "{{json .}}"], in: nil), usage.succeeded else {
            return RuleScan(note: "Docker n'est pas lancé : ouvre Docker Desktop puis relance l'analyse")
        }
        var candidates: [Candidate] = []

        let buildCache = Self.reclaimable(ofType: "Build Cache", inSystemDF: usage.output)
        if buildCache > 0 {
            candidates.append(Candidate(
                id: candidateID("builder"),
                title: "Cache de build",
                detail: "docker builder prune --all",
                bytes: buildCache,
                // `--all` : la colonne « Reclaimable » compte tout le cache inutilisé, pas seulement l'orphelin.
                action: .command(Command(executable: docker, arguments: ["builder", "prune", "--all", "-f"])),
                location: nil
            ))
        }

        if let dangling = context.runner.run(docker, ["images", "-f", "dangling=true", "--format", "{{.Size}}"], in: nil),
           dangling.succeeded {
            let sizes = dangling.output.split(whereSeparator: \.isNewline).map { Self.parseSize(String($0)) }
            let bytes = sizes.reduce(0, +)
            if bytes > 0 {
                candidates.append(Candidate(
                    id: candidateID("dangling"),
                    title: sizes.count == 1 ? "1 image orpheline" : "\(sizes.count) images orphelines",
                    detail: "docker image prune",
                    bytes: bytes,
                    action: .command(Command(executable: docker, arguments: ["image", "prune", "-f"])),
                    location: nil
                ))
            }
        }
        return RuleScan(candidates: candidates)
    }

    /// Colonne « Reclaimable » d'une ligne de `docker system df --format '{{json .}}'`.
    static func reclaimable(ofType type: String, inSystemDF output: String) -> Int64 {
        struct Row: Decodable {
            var type: String
            var reclaimable: String
            enum CodingKeys: String, CodingKey { case type = "Type", reclaimable = "Reclaimable" }
        }
        for line in output.split(whereSeparator: \.isNewline) {
            guard let row = try? JSONDecoder().decode(Row.self, from: Data(line.utf8)), row.type == type else { continue }
            // « 1.2GB (34%) » : la taille est avant l'espace.
            return parseSize(String(row.reclaimable.split(separator: " ").first ?? ""))
        }
        return 0
    }

    /// Tailles Docker, en unités décimales : `0B`, `12.5kB`, `350MB`, `1.2GB`.
    static func parseSize(_ text: String) -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (suffix, factor) in units where trimmed.hasSuffix(suffix) {
            guard let value = Double(trimmed.dropLast(suffix.count)) else { return 0 }
            return Int64(value * factor)
        }
        return 0
    }
}
