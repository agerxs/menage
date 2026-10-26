import Foundation

/// Une famille de projets : comment la reconnaître, quels dossiers elle régénère.
public struct Ecosystem: Sendable, Equatable {
    public var name: String
    public var markers: [String]
    /// Toujours des artefacts, quel que soit le projet.
    public var artifacts: [String]
    /// Noms qui peuvent aussi désigner du code (`build/`, `vendor/`…) : seulement s'ils sont ignorés par git.
    public var ambiguousArtifacts: [String]
    public var rebuild: String

    public static let all: [Ecosystem] = [
        Ecosystem(
            name: "Node", markers: ["package.json"],
            artifacts: ["node_modules", ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache"],
            ambiguousArtifacts: ["dist", "build"], rebuild: "npm install"
        ),
        Ecosystem(
            name: "Flutter", markers: ["pubspec.yaml"],
            artifacts: [".dart_tool"], ambiguousArtifacts: ["build"], rebuild: "flutter pub get"
        ),
        Ecosystem(
            name: "PHP", markers: ["composer.json"],
            artifacts: [], ambiguousArtifacts: ["vendor"], rebuild: "composer install"
        ),
        Ecosystem(
            name: "Gradle", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
            artifacts: [".gradle"], ambiguousArtifacts: ["build"], rebuild: "./gradlew build"
        ),
        Ecosystem(
            name: "CocoaPods", markers: ["Podfile"],
            artifacts: ["Pods"], ambiguousArtifacts: [], rebuild: "pod install"
        ),
        Ecosystem(
            name: "Rust", markers: ["Cargo.toml"],
            artifacts: ["target"], ambiguousArtifacts: [], rebuild: "cargo build"
        ),
        Ecosystem(
            name: "Python", markers: ["pyproject.toml", "requirements.txt"],
            artifacts: [".venv"], ambiguousArtifacts: ["venv"], rebuild: "python3 -m venv .venv"
        ),
    ]

    /// Dossiers dans lesquels on ne cherche jamais de projet.
    static let skippedWhileWalking: Set<String> = Set(all.flatMap { $0.artifacts + $0.ambiguousArtifacts })
}

public struct Project: Sendable, Equatable, Identifiable {
    public var id: String { url.path }
    public var url: URL
    /// Chemin relatif à la racine où il a été trouvé (`almanach/backend`).
    public var name: String
    public var ecosystems: [String]
    /// Dossiers régénérables présents, déjà filtrés : jamais un dossier suivi par git.
    public var artifacts: [URL]
    public var rebuildCommands: [String]
    public var lastActivity: Date?
}

/// Trouve les projets sous des racines (par défaut `~/devapps`) et leurs artefacts régénérables.
public struct ProjectDetector: Sendable {
    public var roots: [URL]
    public var maxDepth: Int
    public var runner: any CommandRunner

    public init(roots: [URL], maxDepth: Int = 4, runner: any CommandRunner = ProcessRunner()) {
        self.roots = roots
        self.maxDepth = maxDepth
        self.runner = runner
    }

    public func detect() -> [Project] {
        var projects: [Project] = []
        for root in roots {
            walk(root, root: root, depth: 0, into: &projects)
        }
        return projects
    }

    private func walk(_ directory: URL, root: URL, depth: Int, into projects: inout [Project]) {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ) else { return }
        let names = Set(children.map(\.lastPathComponent))

        let ecosystems = Ecosystem.all.filter { !$0.markers.filter(names.contains).isEmpty }
        if !ecosystems.isEmpty, directory != root {
            projects.append(project(at: directory, root: root, ecosystems: ecosystems, names: names))
        }

        guard depth < maxDepth else { return }
        for child in children {
            let name = child.lastPathComponent
            guard !name.hasPrefix("."), !Ecosystem.skippedWhileWalking.contains(name) else { continue }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            walk(child, root: root, depth: depth + 1, into: &projects)
        }
    }

    private func project(at directory: URL, root: URL, ecosystems: [Ecosystem], names: Set<String>) -> Project {
        // Un projet rangé dans un dossier qu'un dépôt parent ignore n'est pas suivi : git y répondrait
        // « ignoré » pour tout, y compris un `build/` écrit à la main.
        let isGitRepo = git(["rev-parse", "--is-inside-work-tree"], in: directory)?.succeeded == true
            && git(["check-ignore", "-q", "."], in: directory)?.status == 1
        var artifacts: [URL] = []
        var seen: Set<String> = []
        var rebuildCommands: [String] = []
        for ecosystem in ecosystems {
            var contributed = false
            for name in ecosystem.artifacts + ecosystem.ambiguousArtifacts where names.contains(name) && !seen.contains(name) {
                let url = directory.appendingPathComponent(name)
                guard isDirectory(url) else { continue }
                let ambiguous = ecosystem.ambiguousArtifacts.contains(name)
                guard isRegenerable(url, ambiguous: ambiguous, inGitRepo: isGitRepo, project: directory) else { continue }
                seen.insert(name)
                artifacts.append(url)
                contributed = true
            }
            // Seulement les commandes qui reconstruisent ce qu'on propose de supprimer.
            if contributed { rebuildCommands.append(ecosystem.rebuild) }
        }
        // Résoudre les deux : macOS rend tantôt /var, tantôt /private/var pour le même dossier.
        let rootPath = root.resolvingSymlinksInPath().path
        let directoryPath = directory.resolvingSymlinksInPath().path
        let relative = directoryPath.hasPrefix(rootPath)
            ? String(directoryPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : directory.lastPathComponent
        return Project(
            url: directory,
            name: relative,
            ecosystems: ecosystems.map(\.name),
            artifacts: artifacts,
            rebuildCommands: rebuildCommands,
            lastActivity: lastActivity(of: directory, inGitRepo: isGitRepo)
        )
    }

    /// Un dossier suivi par git n'est jamais un artefact. Un nom ambigu (`build/`) doit en plus être
    /// explicitement ignoré par git : hors dépôt git, on ne peut pas le prouver, on s'abstient.
    private func isRegenerable(_ url: URL, ambiguous: Bool, inGitRepo: Bool, project: URL) -> Bool {
        let name = url.lastPathComponent
        guard inGitRepo else { return !ambiguous }
        // APFS ignore la casse, git non : `Build/main.c` suivi doit bloquer le dossier `build` sur le disque.
        let tracked = git(["-c", "core.ignorecase=true", "ls-files", "--", ":(icase)\(name)"], in: project)
        guard let tracked, tracked.succeeded, tracked.output.isEmpty else { return false }
        if ambiguous {
            return git(["check-ignore", "-q", name], in: project)?.status == 0
        }
        return true
    }

    /// Le plus récent entre le dernier commit qui touche le projet et la dernière modification d'un
    /// fichier source : un projet modifié hier sans commit depuis 4 mois est actif.
    private func lastActivity(of directory: URL, inGitRepo: Bool) -> Date? {
        var commit: Date?
        if inGitRepo,
           let result = git(["log", "-1", "--format=%ct", "--", "."], in: directory), result.succeeded,
           let seconds = TimeInterval(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            commit = Date(timeIntervalSince1970: seconds)
        }
        return [commit, newestModification(in: directory, depth: 0)].compactMap { $0 }.max()
    }

    private func newestModification(in directory: URL, depth: Int) -> Date? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else { return nil }
        var newest: Date?
        for child in children {
            let name = child.lastPathComponent
            guard !name.hasPrefix("."), !Ecosystem.skippedWhileWalking.contains(name) else { continue }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let candidate = values?.isDirectory == true
                ? (depth < 3 ? newestModification(in: child, depth: depth + 1) : nil)
                : values?.contentModificationDate
            if let candidate, newest.map({ candidate > $0 }) ?? true { newest = candidate }
        }
        return newest
    }

    private func git(_ arguments: [String], in directory: URL) -> CommandResult? {
        runner.run(Executables.git, ["-C", directory.path] + arguments, in: nil)
    }

    private func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }
}
