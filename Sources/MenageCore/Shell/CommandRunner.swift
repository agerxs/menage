import Foundation

public struct CommandResult: Sendable, Equatable {
    public var status: Int32
    public var output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }

    public var succeeded: Bool { status == 0 }
}

/// Lance un outil en ligne de commande (git, xcrun, docker). Injectable pour les tests.
public protocol CommandRunner: Sendable {
    /// `nil` si l'exécutable n'existe pas ou ne peut pas être lancé.
    func run(_ executable: URL, _ arguments: [String], in directory: URL?) -> CommandResult?
}

public struct ProcessRunner: CommandRunner {
    /// Un `docker` ou un `simctl` bloqué ne doit pas figer l'analyse : au-delà, le processus est arrêté.
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 120) {
        self.timeout = timeout
    }

    public func run(_ executable: URL, _ arguments: [String], in directory: URL?) -> CommandResult? {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Lire en parallèle : un tuyau plein bloquerait le processus avant sa fin.
        let output = OutputBuffer()
        let reading = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.data = pipe.fileHandleForReading.readDataToEndOfFile()
            reading.signal()
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        reading.wait()
        return CommandResult(status: process.terminationStatus, output: String(decoding: output.data, as: UTF8.self))
    }
}

/// Écrit par le fil de lecture, lu après sa fin (le sémaphore ordonne les deux).
private final class OutputBuffer: @unchecked Sendable {
    var data = Data()
}

/// Emplacements des outils. Une app lancée depuis le Finder n'a pas le `PATH` du terminal.
public enum Executables {
    public static let git = URL(fileURLWithPath: "/usr/bin/git")
    public static let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")

    public static var docker: URL? {
        [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ]
        .map { URL(fileURLWithPath: $0) }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
