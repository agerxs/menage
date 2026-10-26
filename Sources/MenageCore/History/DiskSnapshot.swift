import Foundation

/// Ce qu'on garde d'un scan pour le comparer plus tard : la taille des dossiers jusqu'à 3 niveaux
/// sous le dossier perso, ceux d'au moins 10 Mo. Pas fichier par fichier : l'historique reste petit.
public struct DiskSnapshot: Codable, Sendable, Equatable {
    public var date: Date
    public var scannedBytes: Int64
    public var diskFree: Int64
    /// Chemin relatif au dossier perso (`devapps/vitalis`) → octets.
    public var sizes: [String: Int64]
    /// Dossiers illisibles lors de ce scan (relatifs), comptés 0 octet : ils ne sont pas comparables.
    public var unreadable: [String]

    public init(date: Date, scannedBytes: Int64, diskFree: Int64, sizes: [String: Int64], unreadable: [String] = []) {
        self.date = date
        self.scannedBytes = scannedBytes
        self.diskFree = diskFree
        self.sizes = sizes
        self.unreadable = unreadable
    }

    public init(
        root: DiskNode, unreadable: [String] = [], diskFree: Int64, date: Date = Date(),
        maxDepth: Int = 3, minimumBytes: Int64 = 10_000_000
    ) {
        var sizes: [String: Int64] = [:]
        func visit(_ node: DiskNode, relative: String, depth: Int) {
            for child in node.children where child.isDirectory && child.bytes >= minimumBytes {
                let path = relative.isEmpty ? child.name : relative + "/" + child.name
                sizes[path] = child.bytes
                if depth < maxDepth { visit(child, relative: path, depth: depth + 1) }
            }
        }
        visit(root, relative: "", depth: 1)
        let prefix = root.path + "/"
        let relativeUnreadable = unreadable.compactMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
        self.init(date: date, scannedBytes: root.bytes, diskFree: diskFree, sizes: sizes, unreadable: relativeUnreadable)
    }

    private enum CodingKeys: String, CodingKey {
        case date, scannedBytes, diskFree, sizes, unreadable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        scannedBytes = try container.decode(Int64.self, forKey: .scannedBytes)
        diskFree = try container.decode(Int64.self, forKey: .diskFree)
        sizes = try container.decode([String: Int64].self, forKey: .sizes)
        unreadable = try container.decodeIfPresent([String].self, forKey: .unreadable) ?? []
    }
}

public struct Growth: Sendable, Equatable, Identifiable {
    public var path: String
    public var before: Int64
    public var after: Int64
    /// Un dossier qui a perdu à peu près autant : sans doute un renommage ou un déplacement,
    /// pas une vraie croissance. Affiché, mais jamais notifié.
    public var movedFrom: String?
    /// La part de la croissance qui vient de sous-dossiers déplacés ici.
    public var movedBytes: Int64

    public init(path: String, before: Int64, after: Int64, movedFrom: String? = nil, movedBytes: Int64 = 0) {
        self.path = path
        self.before = before
        self.after = after
        self.movedFrom = movedFrom
        self.movedBytes = movedBytes
    }

    public var id: String { path }
    public var delta: Int64 { after - before }
    /// La vraie croissance : sans ce qui n'a fait que changer de place.
    public var realDelta: Int64 { movedFrom == nil ? delta - movedBytes : 0 }
    /// Ce qu'on affiche : la vraie croissance, ou la taille arrivée pour un déplacement.
    public var displayDelta: Int64 { movedFrom == nil ? realDelta : delta }
}

public enum GrowthReport {
    public enum Period: Hashable, Sendable {
        case lastScan
        case days(Int)
    }

    /// L'instantané auquel comparer le plus récent : le précédent, ou le dernier d'il y a au moins
    /// `n` jours. Si l'historique est plus court que la période, le plus ancien disponible.
    public static func baseline(in snapshots: [DiskSnapshot], period: Period) -> DiskSnapshot? {
        guard snapshots.count >= 2, let latest = snapshots.last else { return nil }
        switch period {
        case .lastScan:
            return snapshots[snapshots.count - 2]
        case .days(let days):
            let limit = latest.date.addingTimeInterval(-Double(days) * 86_400)
            return snapshots.last { $0.date <= limit } ?? snapshots.first
        }
    }

    /// Les dossiers qui ont le plus grossi entre deux instantanés, du plus fort au plus faible.
    ///
    /// - Un parent n'est pas listé quand un de ses enfants explique à lui seul 80 % de sa croissance :
    ///   « `Library/Caches/com.openai.codex` +3 Go » dit tout, inutile d'y ajouter « `Library` +3 Go ».
    /// - Un dossier illisible à l'un des deux scans et lisible à l'autre (accès complet au disque
    ///   accordé entre-temps) n'est pas comparable : ni lui, ni ses parents, ni ses enfants.
    /// - Un dossier nouveau dont la taille correspond à une baisse ailleurs (à 5 % près) est marqué comme
    ///   déplacement, et ses parents ne comptent que leur vraie croissance.
    public static func growth(from old: DiskSnapshot, to new: DiskSnapshot, minimumDelta: Int64 = 100_000_000, limit: Int = 20) -> [Growth] {
        let readabilityChanged = Set(old.unreadable).symmetricDifference(new.unreadable)
        func comparable(_ path: String) -> Bool {
            !readabilityChanged.contains { changed in
                changed == path || changed.hasPrefix(path + "/") || path.hasPrefix(changed + "/")
            }
        }

        // Ce qui a perdu de la place, disparu compris : les sources possibles d'un déplacement.
        let paths = Set(old.sizes.keys).union(new.sizes.keys)
        let shrinks = paths.compactMap { path -> (path: String, loss: Int64)? in
            let loss = (old.sizes[path] ?? 0) - (new.sizes[path] ?? 0)
            return loss >= minimumDelta && comparable(path) ? (path, loss) : nil
        }

        var growing = new.sizes.compactMap { path, after -> Growth? in
            var growth = Growth(path: path, before: old.sizes[path] ?? 0, after: after)
            guard growth.delta >= minimumDelta, comparable(path) else { return nil }
            // Seul un dossier nouveau peut être un déplacement (renommage, dossier déplacé) : un dossier
            // existant qui grossit d'autant qu'un autre a maigri, c'est le plus souvent une coïncidence.
            guard growth.before == 0 else { return growth }
            growth.movedFrom = shrinks
                .filter { !$0.path.hasPrefix(path + "/") && !path.hasPrefix($0.path + "/") }
                .filter { abs(Double($0.loss - growth.delta)) <= 0.05 * Double(growth.delta) }
                // Le plus précis : le plus profond des dossiers qui ont perdu cette place.
                .max { $0.path.split(separator: "/").count < $1.path.split(separator: "/").count }?
                .path
            return growth
        }

        // Un parent qui contient un dossier déplacé n'a vraiment grossi que du reste.
        let moved = growing.filter { $0.movedFrom != nil }
        for index in growing.indices where growing[index].movedFrom == nil {
            let parent = growing[index].path
            let below = moved.filter { $0.path.hasPrefix(parent + "/") }
            // Seulement les plus hauts : un déplacement imbriqué dans un autre n'est pas compté deux fois.
            let outermost = below.filter { item in !below.contains { item.path.hasPrefix($0.path + "/") } }
            growing[index].movedBytes = outermost.reduce(0) { $0 + $1.delta }
        }
        growing.removeAll { $0.movedFrom == nil && $0.realDelta < minimumDelta }

        let realDeltas = growing.filter { $0.movedFrom == nil }.map { ($0.path, $0.realDelta) }
        return growing
            .filter { parent in
                parent.movedFrom != nil || !realDeltas.contains { path, delta in
                    path.hasPrefix(parent.path + "/") && Double(delta) >= 0.8 * Double(parent.realDelta)
                }
            }
            .sorted { $0.displayDelta != $1.displayDelta ? $0.displayDelta > $1.displayDelta : $0.path < $1.path }
            .prefix(limit)
            .map { $0 }
    }

    /// La croissance qui mérite une notification : au moins `threshold` de vraie croissance,
    /// déplacements exclus.
    public static func notable(from old: DiskSnapshot, to new: DiskSnapshot, threshold: Int64) -> Growth? {
        growth(from: old, to: new, minimumDelta: threshold, limit: .max).first { $0.movedFrom == nil }
    }
}

/// Quand lancer le scan quotidien.
public enum DailyScan {
    public static let interval: TimeInterval = 23 * 3600

    /// Dû si aucun instantané, si le dernier a plus de 23 h, ou s'il est daté du futur (horloge
    /// en avance au moment du scan) : sinon le scan quotidien ne repartirait jamais.
    public static func isDue(lastSnapshot: Date?, now: Date) -> Bool {
        guard let last = lastSnapshot else { return true }
        return last > now || now.timeIntervalSince(last) >= interval
    }
}
