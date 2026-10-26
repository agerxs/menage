import Foundation
@testable import MenageCore

/// Arborescence jetable dans le dossier temporaire, supprimée à la fin du test.
final class Fixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("menage-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    @discardableResult
    func file(_ path: String, bytes: Int = 1, contents: String? = nil) throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = contents.map { Data($0.utf8) } ?? Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        try data.write(to: url)
        return url
    }

    @discardableResult
    func directory(_ path: String) throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// git avec une identité et une date de commit fixées.
    @discardableResult
    func git(_ arguments: [String], in path: String, date: String = "2025-01-01T12:00:00") throws -> String {
        let process = Process()
        process.executableURL = Executables.git
        process.arguments = ["-C", url(path).path, "-c", "user.name=Test", "-c", "user.email=test@example.com"] + arguments
        process.environment = ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date, "HOME": root.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Les chemins protégés standard, sans `/var` ni `/private` : le dossier temporaire des tests y vit.
    func protected() -> ProtectedPaths {
        var paths = ProtectedPaths.standard(home: url("home"))
        paths.sanctuaries.removeAll { ["/var", "/private", "/tmp"].contains($0) }
        return paths
    }

    /// Recule la date de modification de tout un dossier, pour simuler un projet qui dort.
    func age(_ path: String, to date: Date) throws {
        let base = url(path)
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        var items = [base]
        while let item = enumerator?.nextObject() as? URL { items.append(item) }
        for item in items {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: item.path)
        }
    }

    func context(projects: [Project] = [], now: Date = Date(), runner: any CommandRunner = ProcessRunner()) -> CleanupContext {
        CleanupContext(
            home: url("home"),
            applicationDirectories: [url("Applications")],
            androidSDK: url("home/Library/Android/sdk"),
            projects: projects,
            inactivityDays: 60,
            now: now,
            runner: runner
        )
    }
}

/// Note les chemins au lieu de les mettre à la Corbeille.
final class RecordingTrasher: Trasher, @unchecked Sendable {
    private let lock = NSLock()
    private var _trashed: [URL] = []

    var trashed: [URL] { lock.withLock { _trashed } }

    func trash(_ url: URL) throws {
        lock.withLock { _trashed.append(url) }
    }
}

/// Répond toujours la même chose, et note les commandes.
final class StubRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    let result: CommandResult?

    init(result: CommandResult?) {
        self.result = result
    }

    var calls: [String] { lock.withLock { _calls } }

    func run(_ executable: URL, _ arguments: [String], in directory: URL?) -> CommandResult? {
        lock.withLock { _calls.append(([executable.lastPathComponent] + arguments).joined(separator: " ")) }
        return result
    }
}

let megabyte = 1_000_000
