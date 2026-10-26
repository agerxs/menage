import Foundation

/// Les instantanés, un fichier JSON par scan, dans `~/Library/Application Support/Menage/history/`.
///
/// Élagage : tout est gardé sur les 7 derniers jours ; avant, un seul par jour (le dernier du jour),
/// pour que plusieurs scans manuels par jour ne raccourcissent pas l'historique ; et `maxCount` au plus.
public struct SnapshotStore: Sendable {
    public let directory: URL
    public var maxCount: Int

    public init(directory: URL, maxCount: Int = 90) {
        self.directory = directory
        self.maxCount = maxCount
    }

    /// Les fichiers à supprimer, parmi des dates d'instantanés (dans n'importe quel ordre).
    static func datesToPrune(_ dates: [Date], now: Date, maxCount: Int, calendar: Calendar = .current) -> Set<Date> {
        let recentLimit = now.addingTimeInterval(-7 * 86_400)
        var keep: [Date] = []
        var lastPerDay: [DateComponents: Date] = [:]
        for date in dates {
            if date >= recentLimit {
                keep.append(date)
            } else {
                let day = calendar.dateComponents([.year, .month, .day], from: date)
                if lastPerDay[day].map({ date > $0 }) ?? true { lastPerDay[day] = date }
            }
        }
        keep += lastPerDay.values
        let kept = Set(keep.sorted().suffix(maxCount))
        return Set(dates).subtracting(kept)
    }

    public static func standard() -> SnapshotStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SnapshotStore(directory: support.appendingPathComponent("Menage/history"))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Enregistre, puis élague. Ce sont les propres fichiers de l'app : ils sont supprimés, pas mis à la Corbeille.
    public func save(_ snapshot: DiskSnapshot, now: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "snapshot-\(Int(snapshot.date.timeIntervalSince1970)).json"
        try Self.encoder().encode(snapshot).write(to: directory.appendingPathComponent(name), options: .atomic)
        let existing = files()
        let dates = existing.map { Date(timeIntervalSince1970: TimeInterval(timestamp($0))) }
        let prune = Self.datesToPrune(dates, now: now, maxCount: maxCount)
        for (file, date) in zip(existing, dates) where prune.contains(date) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Du plus ancien au plus récent. Un fichier illisible est ignoré, comme un instantané daté de
    /// plus d'une heure dans le futur (horloge déréglée) : il resterait « le plus récent » pour toujours.
    public func load(now: Date = Date()) -> [DiskSnapshot] {
        files().compactMap { try? Self.decoder().decode(DiskSnapshot.self, from: Data(contentsOf: $0)) }
            .filter { $0.date <= now.addingTimeInterval(3600) }
            .sorted { $0.date < $1.date }
    }

    /// Les fichiers d'instantanés, du plus ancien au plus récent (le nom porte la date).
    private func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") && $0.pathExtension == "json" }
            .sorted { timestamp($0) < timestamp($1) }
    }

    private func timestamp(_ url: URL) -> Int {
        Int(url.deletingPathExtension().lastPathComponent.dropFirst("snapshot-".count)) ?? 0
    }
}

/// Un relevé de l'espace libre et du swap.
public struct FreeSpaceSample: Codable, Sendable, Equatable, Identifiable {
    public var date: Date
    public var diskFree: Int64
    public var swapUsed: Int64

    public init(date: Date, diskFree: Int64, swapUsed: Int64) {
        self.date = date
        self.diskFree = diskFree
        self.swapUsed = swapUsed
    }

    public var id: Date { date }
}

/// Un relevé par heure, une ligne JSON chacun, 90 jours gardés : de quoi tracer la courbe.
public struct FreeSpaceLog: Sendable {
    public let url: URL
    public var retention: TimeInterval

    public init(url: URL, retention: TimeInterval = 90 * 86_400) {
        self.url = url
        self.retention = retention
    }

    public static func standard() -> FreeSpaceLog {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FreeSpaceLog(url: support.appendingPathComponent("Menage/history/free-space.jsonl"))
    }

    /// Du plus ancien au plus récent.
    public func read() -> [FreeSpaceSample] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(FreeSpaceSample.self, from: Data($0)) }
    }

    /// Ajoute le relevé et réécrit le fichier sans ceux qui ont dépassé la durée de conservation.
    public func append(_ sample: FreeSpaceSample) throws {
        let limit = sample.date.addingTimeInterval(-retention)
        let kept = read().filter { $0.date >= limit } + [sample]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for item in kept {
            data.append(try encoder.encode(item))
            data.append(0x0A)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
