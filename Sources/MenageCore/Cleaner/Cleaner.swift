import Foundation

/// Ce qu'une règle a trouvé, prêt à afficher.
public struct RuleReport: Sendable, Identifiable {
    public var id: String
    public var title: String
    public var explanation: String
    public var risk: Risk
    public var candidates: [Candidate]
    public var note: String?

    public var totalBytes: Int64 { candidates.reduce(0) { $0 + $1.bytes } }
}

public struct ExecutionResult: Sendable, Equatable {
    /// Ce qui est parti à la Corbeille : l'espace revient quand on la vide.
    public var trashedBytes: Int64 = 0
    /// Ce que les commandes ont supprimé définitivement.
    public var deletedBytes: Int64 = 0
    public var errors: [String] = []
    /// Chemins refusés par les chemins protégés, avec la raison.
    public var refused: [String] = []
    /// Candidats qui n'ont pas été traités en entier : ils restent affichés.
    public var failedCandidates: Set<String> = []

    public init() {}
}

public struct Cleaner: Sendable {
    public var rules: [any CleanupRule]
    public var protected: ProtectedPaths
    public var trasher: any Trasher
    public var journal: ActionJournal

    public init(rules: [any CleanupRule], protected: ProtectedPaths, trasher: any Trasher, journal: ActionJournal) {
        self.rules = rules
        self.protected = protected
        self.trasher = trasher
        self.journal = journal
    }

    /// Du plus sûr au plus délicat : c'est l'ordre d'affichage.
    public static let standardRules: [any CleanupRule] = [
        DerivedDataRule(),
        UnavailableSimulatorsRule(),
        ApplicationCachesRule(),
        InstallersRule(),
        ProjectArtifactsRule(),
        UnusedAndroidImagesRule(),
        OldNDKRule(),
        EmulatorSnapshotsRule(),
        DockerRule(),
        BrokenEmulatorsRule(),
        LargeDownloadsRule(),
    ]

    /// Lance toutes les règles en parallèle. `progress` reçoit le titre de chaque règle terminée.
    public func scan(_ context: CleanupContext, progress: @escaping @Sendable (String) -> Void = { _ in }) async -> [RuleReport] {
        let protected = protected
        let reports = await withTaskGroup(of: (Int, RuleReport).self) { group in
            for (index, rule) in rules.enumerated() {
                group.addTask {
                    let scan = rule.scan(context)
                    progress(rule.title)
                    // Une règle ne propose jamais un chemin protégé, même par erreur.
                    let candidates = scan.candidates.filter { candidate in
                        guard case .trash(let urls) = candidate.action else { return true }
                        return !urls.isEmpty && urls.allSatisfy { !protected.isProtected($0) }
                    }
                    return (index, RuleReport(
                        id: rule.id, title: rule.title, explanation: rule.explanation,
                        risk: rule.risk, candidates: candidates, note: scan.note
                    ))
                }
            }
            var collected: [(Int, RuleReport)] = []
            for await report in group { collected.append(report) }
            return collected
        }
        return reports.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Exécute les candidats choisis, règle par règle, et note chaque action au journal.
    public func execute(_ selection: [(report: RuleReport, candidates: [Candidate])], runner: any CommandRunner, now: Date = Date()) -> ExecutionResult {
        var result = ExecutionResult()
        for (report, candidates) in selection where !candidates.isEmpty {
            var items: [String] = []
            var bytes: Int64 = 0
            var errors: [String] = []
            var method = JournalEntry.Method.corbeille

            for candidate in candidates {
                switch candidate.action {
                case .trash(let urls):
                    var failed = false
                    var trashedAny = false
                    for url in urls {
                        if let reason = protected.refusal(for: url) {
                            result.refused.append("\(url.path) : \(reason)")
                            failed = true
                            continue
                        }
                        guard FileManager.default.fileExists(atPath: url.path) else { continue }
                        do {
                            try trasher.trash(url)
                            items.append(url.path)
                            trashedAny = true
                        } catch {
                            errors.append("\(url.path) : \(error.localizedDescription)")
                            failed = true
                        }
                    }
                    if failed {
                        result.failedCandidates.insert(candidate.id)
                        if trashedAny {
                            errors.append("\(candidate.title) : traité en partie, place libérée non comptée")
                        }
                    } else if trashedAny {
                        // Déjà disparu avant le ménage : rien n'a été libéré, rien à compter.
                        bytes += candidate.bytes
                        result.trashedBytes += candidate.bytes
                    }
                case .command(let command):
                    method = .commande
                    items.append(command.display)
                    if let run = runner.run(command.executable, command.arguments, in: nil), run.succeeded {
                        bytes += candidate.bytes
                        result.deletedBytes += candidate.bytes
                    } else {
                        errors.append("\(command.display) a échoué")
                        result.failedCandidates.insert(candidate.id)
                    }
                }
            }

            result.errors += errors
            guard !items.isEmpty || !errors.isEmpty else { continue }
            let entry = JournalEntry(
                date: now, ruleID: report.id, title: report.title, method: method,
                items: items, bytes: bytes, errors: errors
            )
            do {
                try journal.append(entry)
            } catch {
                result.errors.append("Journal non écrit : \(error.localizedDescription)")
            }
        }
        return result
    }
}
