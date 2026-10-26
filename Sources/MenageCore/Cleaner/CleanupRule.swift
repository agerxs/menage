import Foundation

public enum Risk: Int, Sendable, Comparable, CaseIterable {
    /// Se régénère tout seul, aucun travail perdu. Pré-coché.
    case sansRisque
    /// Se reconstruit, mais coûte un build ou un téléchargement.
    case regenerable
    /// C'est peut-être à toi : rien n'est pré-coché.
    case aVerifier

    public static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .sansRisque: "Sans risque"
        case .regenerable: "Régénérable"
        case .aVerifier: "À vérifier"
        }
    }

    public var preselected: Bool { self == .sansRisque }
}

public struct Command: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]

    public init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var display: String {
        ([executable.lastPathComponent] + arguments).joined(separator: " ")
    }
}

public enum CleanupAction: Sendable, Equatable {
    /// Mise à la Corbeille : récupérable.
    case trash([URL])
    /// Outil externe (`docker`, `xcrun simctl`) : suppression définitive, affichée avant d'être lancée.
    case command(Command)
}

public struct Candidate: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var bytes: Int64
    public var action: CleanupAction
    /// Ce que « Afficher dans le Finder » sélectionne.
    public var location: URL?

    public init(id: String, title: String, detail: String, bytes: Int64, action: CleanupAction, location: URL?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.bytes = bytes
        self.action = action
        self.location = location
    }

    /// Un candidat qui part entier à la Corbeille.
    public static func trash(_ url: URL, title: String? = nil, detail: String, bytes: Int64? = nil) -> Candidate {
        Candidate(
            id: url.path,
            title: title ?? url.lastPathComponent,
            detail: detail,
            bytes: bytes ?? DirectorySize.of(url),
            action: .trash([url]),
            location: url
        )
    }
}

public struct RuleScan: Sendable {
    public var candidates: [Candidate]
    /// Pourquoi la règle n'a rien pu mesurer (« Docker n'est pas lancé »).
    public var note: String?

    public init(candidates: [Candidate] = [], note: String? = nil) {
        self.candidates = candidates
        self.note = note
    }
}

/// Tout ce dont une règle a besoin pour chercher, injectable pour les tests.
public struct CleanupContext: Sendable {
    public var home: URL
    public var applicationDirectories: [URL]
    public var androidSDK: URL
    public var projects: [Project]
    public var inactivityDays: Int
    public var now: Date
    public var runner: any CommandRunner

    public init(
        home: URL, applicationDirectories: [URL], androidSDK: URL, projects: [Project],
        inactivityDays: Int, now: Date, runner: any CommandRunner
    ) {
        self.home = home
        self.applicationDirectories = applicationDirectories
        self.androidSDK = androidSDK
        self.projects = projects
        self.inactivityDays = inactivityDays
        self.now = now
        self.runner = runner
    }

    public static func live(projects: [Project], inactivityDays: Int) -> CleanupContext {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        let sdk = (environment["ANDROID_HOME"] ?? environment["ANDROID_SDK_ROOT"]).map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent("Library/Android/sdk")
        return CleanupContext(
            home: home,
            applicationDirectories: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")],
            androidSDK: sdk,
            projects: projects,
            inactivityDays: inactivityDays,
            now: Date(),
            runner: ProcessRunner()
        )
    }
}

public protocol CleanupRule: Sendable {
    var id: String { get }
    var title: String { get }
    var explanation: String { get }
    var risk: Risk { get }
    func scan(_ context: CleanupContext) -> RuleScan
}

extension CleanupRule {
    func candidateID(_ suffix: String) -> String { "\(id):\(suffix)" }
}

/// Sous-dossiers directs, liens symboliques exclus.
func subdirectories(of url: URL) -> [URL] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
    let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
    return children.filter {
        let values = try? $0.resourceValues(forKeys: Set(keys))
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// « il y a 4 mois », « il y a 12 jours ».
func ago(_ date: Date, now: Date) -> String {
    let days = Int(now.timeIntervalSince(date) / 86_400)
    switch days {
    case ..<1: return "aujourd'hui"
    case 1: return "hier"
    case ..<60: return "il y a \(days) jours"
    case ..<730: return "il y a \(days / 30) mois"
    default: return "il y a \(days / 365) ans"
    }
}
