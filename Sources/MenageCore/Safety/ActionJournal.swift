import Foundation

public struct JournalEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Method: String, Codable, Sendable {
        case corbeille, commande
    }

    public var id: UUID
    public var date: Date
    public var ruleID: String
    public var title: String
    public var method: Method
    /// Chemins mis à la Corbeille, ou commandes lancées.
    public var items: [String]
    public var bytes: Int64
    public var errors: [String]

    public init(
        id: UUID = UUID(), date: Date, ruleID: String, title: String,
        method: Method, items: [String], bytes: Int64, errors: [String]
    ) {
        self.id = id
        self.date = date
        self.ruleID = ruleID
        self.title = title
        self.method = method
        self.items = items
        self.bytes = bytes
        self.errors = errors
    }
}

/// Journal des actions, une ligne JSON par action, dans `~/Library/Application Support/Menage/`.
public struct ActionJournal: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func standard() -> ActionJournal {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ActionJournal(url: support.appendingPathComponent("Menage/journal.jsonl"))
    }

    public func append(_ entry: JournalEntry) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(entry)
        line.append(0x0A)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    /// Les entrées, de la plus récente à la plus ancienne. Une ligne illisible est ignorée.
    public func read() -> [JournalEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A)
            .compactMap { try? decoder.decode(JournalEntry.self, from: Data($0)) }
            .reversed()
    }
}
