import AppKit
import MenageCore
import Observation

/// L'analyse et le ménage : ce qui est trouvé, ce qui est coché, ce qui a été fait.
@MainActor
@Observable
final class CleanerModel {
    enum Phase: Equatable {
        case idle
        case detectingProjects
        case scanning(done: Int, total: Int)
        case ready
        case executing
    }

    private static let rootsKey = "cleaner.projectRoots"
    private static let inactivityKey = "cleaner.inactivityDays"

    private(set) var phase = Phase.idle
    private(set) var reports: [RuleReport] = []
    var selection: Set<String> = []
    private(set) var lastResult: ExecutionResult?
    private(set) var journalEntries: [JournalEntry] = []
    private(set) var lastScanDate: Date?

    var projectRoots: [URL] {
        didSet { UserDefaults.standard.set(projectRoots.map(\.path), forKey: Self.rootsKey) }
    }
    var inactivityDays: Int {
        didSet { UserDefaults.standard.set(inactivityDays, forKey: Self.inactivityKey) }
    }

    @ObservationIgnored private let journal = ActionJournal.standard()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let saved = UserDefaults.standard.stringArray(forKey: Self.rootsKey) {
            projectRoots = saved.map { URL(fileURLWithPath: $0) }
        } else {
            projectRoots = ["devapps", "develop"]
                .map { home.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        let days = UserDefaults.standard.integer(forKey: Self.inactivityKey)
        inactivityDays = days > 0 ? days : 60
        journalEntries = journal.read()
    }

    var isBusy: Bool {
        switch phase {
        case .detectingProjects, .scanning, .executing: true
        case .idle, .ready: false
        }
    }

    var reportsWithCandidates: [RuleReport] { reports.filter { !$0.candidates.isEmpty } }
    var emptyReports: [RuleReport] { reports.filter { $0.candidates.isEmpty } }

    var selectedCandidates: [Candidate] {
        reports.flatMap(\.candidates).filter { selection.contains($0.id) }
    }

    var selectedBytes: Int64 { selectedCandidates.reduce(0) { $0 + $1.bytes } }
    var foundBytes: Int64 { reports.reduce(0) { $0 + $1.totalBytes } }

    func isSelected(_ candidate: Candidate) -> Bool {
        selection.contains(candidate.id)
    }

    func toggle(_ candidate: Candidate) {
        if selection.contains(candidate.id) { selection.remove(candidate.id) } else { selection.insert(candidate.id) }
    }

    func isFullySelected(_ report: RuleReport) -> Bool {
        report.candidates.allSatisfy { selection.contains($0.id) }
    }

    func setSelection(_ report: RuleReport, selected: Bool) {
        let ids = report.candidates.map(\.id)
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func scan() async {
        guard !isBusy else { return }
        phase = .detectingProjects
        lastResult = nil
        let roots = projectRoots
        let days = inactivityDays
        let cleaner = Self.makeCleaner(projectRoots: roots)
        let total = cleaner.rules.count

        let projects = await Task.detached(priority: .userInitiated) {
            ProjectDetector(roots: roots).detect()
        }.value
        phase = .scanning(done: 0, total: total)

        let context = CleanupContext.live(projects: projects, inactivityDays: days)
        let found = await cleaner.scan(context) { _ in
            Task { @MainActor [weak self] in
                guard let self, case .scanning(let done, let total) = self.phase else { return }
                self.phase = .scanning(done: done + 1, total: total)
            }
        }
        reports = found
        selection = Set(found.filter { $0.risk.preselected }.flatMap { $0.candidates.map(\.id) })
        lastScanDate = Date()
        phase = .ready
    }

    func execute() async {
        guard phase == .ready, !selection.isEmpty else { return }
        phase = .executing
        let chosen = reports.compactMap { report -> (report: RuleReport, candidates: [Candidate])? in
            let candidates = report.candidates.filter { selection.contains($0.id) }
            return candidates.isEmpty ? nil : (report, candidates)
        }
        let cleaner = Self.makeCleaner(projectRoots: projectRoots)
        let result = await Task.detached(priority: .userInitiated) {
            cleaner.execute(chosen, runner: ProcessRunner())
        }.value

        // Ce qui a été traité disparaît de la liste ; un échec reste visible avec son erreur.
        let done = selection.subtracting(result.failedCandidates)
        reports = reports.map { report in
            var report = report
            report.candidates.removeAll { done.contains($0.id) }
            return report
        }
        selection = []
        lastResult = result
        journalEntries = journal.read()
        phase = .ready
    }

    func reloadJournal() {
        journalEntries = journal.read()
    }

    func reveal(_ candidate: Candidate) {
        guard let location = candidate.location else { return }
        NSWorkspace.shared.activateFileViewerSelecting([location])
    }

    func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }

    static func makeCleaner(projectRoots: [URL]) -> Cleaner {
        Cleaner(
            rules: Cleaner.standardRules,
            protected: .standard(home: FileManager.default.homeDirectoryForCurrentUser, projectRoots: projectRoots),
            trasher: SystemTrasher(),
            journal: .standard()
        )
    }
}
