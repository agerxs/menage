import Foundation

/// Avancement d'un scan, lisible depuis l'interface pendant qu'il tourne.
public final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _files = 0
    private var _bytes: Int64 = 0

    public init() {}

    public var files: Int { lock.withLock { _files } }
    public var bytes: Int64 { lock.withLock { _bytes } }

    func add(files: Int, bytes: Int64) {
        lock.withLock {
            _files += files
            _bytes += bytes
        }
    }
}

public struct DiskScanResult: Sendable {
    public var root: DiskNode
    /// Du plus gros au plus petit.
    public var bigFiles: [BigFile]
    /// Dossiers que macOS a refusé de lister (souvent faute d'accès complet au disque).
    public var unreadable: [String]
    public var fileCount: Int
    public var duration: TimeInterval
}

/// Mesure un dossier entier et garde un arbre allégé pour la carte.
public struct DiskScanner: Sendable {
    /// En dessous, un élément est fondu dans le nœud « autres » de son dossier.
    public var minimumNodeBytes: Int64
    /// Au-delà de cette profondeur, on garde les totaux mais plus le détail.
    public var maxDepth: Int
    public var bigFileThreshold: Int64

    public init(minimumNodeBytes: Int64 = 1_000_000, maxDepth: Int = 12, bigFileThreshold: Int64 = 100_000_000) {
        self.minimumNodeBytes = minimumNodeBytes
        self.maxDepth = maxDepth
        self.bigFileThreshold = bigFileThreshold
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isVolumeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
        .linkCountKey, .fileIdentifierKey,
    ]

    /// Bloquant : à lancer hors du fil principal.
    public func scan(_ root: URL, progress: ScanProgress = ScanProgress()) -> DiskScanResult {
        let start = Date()
        let partial = scanDirectory(root, depth: 0, progress: progress, links: HardLinks())
        return DiskScanResult(
            root: partial.node,
            bigFiles: partial.bigFiles.sorted { $0.bytes > $1.bytes },
            unreadable: partial.unreadable,
            fileCount: partial.files,
            duration: Date().timeIntervalSince(start)
        )
    }

    struct Partial {
        var node: DiskNode
        var bigFiles: [BigFile] = []
        var unreadable: [String] = []
        var files = 0
    }

    /// Le pool est vidé après chaque dossier : sinon les URL et leurs valeurs préchargées de
    /// 2 millions de fichiers restent en mémoire jusqu'à la fin du scan (1,2 Go mesurés).
    private func scanDirectory(_ url: URL, depth: Int, progress: ScanProgress, links: HardLinks) -> Partial {
        autoreleasepool { scanDirectoryContents(url, depth: depth, progress: progress, links: links) }
    }

    private func scanDirectoryContents(_ url: URL, depth: Int, progress: ScanProgress, links: HardLinks) -> Partial {
        let name = url.lastPathComponent
        guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys) else {
            return Partial(node: DiskNode(path: url.path, name: name, kind: .directory, bytes: 0), unreadable: [url.path])
        }

        var directories: [URL] = []
        var result = Partial(node: DiskNode(path: url.path, name: name, kind: .directory, bytes: 0))
        var nodes: [DiskNode] = []
        var othersBytes: Int64 = 0
        var othersCount = 0
        var batchBytes: Int64 = 0

        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(Self.keys)), values.isSymbolicLink != true else { continue }
            // Le chemin vient du parent, pas de l'entrée : macOS rend tantôt /var, tantôt /private/var,
            // et l'arbre doit rester cohérent pour qu'on y retrouve un chemin.
            let child = url.appendingPathComponent(entry.lastPathComponent)
            if values.isDirectory == true {
                // Un autre volume monté ici (disque externe, image disque) n'est pas ce dossier.
                if values.isVolume == true { continue }
                directories.append(child)
            } else if values.isRegularFile == true {
                // Un fichier à plusieurs liens physiques (instantanés de sauvegarde) n'occupe sa place
                // qu'une fois : seul le premier lien rencontré la compte.
                if (values.linkCount ?? 1) > 1, let inode = values.fileIdentifier, !links.firstSighting(of: inode) {
                    result.files += 1
                    continue
                }
                let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                result.files += 1
                batchBytes += bytes
                if bytes >= bigFileThreshold {
                    result.bigFiles.append(BigFile(path: child.path, bytes: bytes, modified: values.contentModificationDate))
                }
                if bytes >= minimumNodeBytes {
                    nodes.append(DiskNode(path: child.path, name: entry.lastPathComponent, kind: .file, bytes: bytes))
                } else {
                    othersBytes += bytes
                    othersCount += 1
                }
            }
        }
        progress.add(files: result.files, bytes: batchBytes)

        for child in subdirectoryPartials(directories, depth: depth, progress: progress, links: links) {
            result.files += child.files
            result.bigFiles += child.bigFiles
            result.unreadable += child.unreadable
            var node = child.node
            if node.bytes >= minimumNodeBytes {
                if depth + 1 >= maxDepth { node.children = [] }
                nodes.append(node)
            } else {
                othersBytes += node.bytes
                othersCount += 1
            }
        }

        if othersBytes > 0 {
            nodes.append(DiskNode(
                path: url.path + "/\u{2026}",
                name: othersCount == 1 ? "1 petit élément" : "\(othersCount) petits éléments",
                kind: .others(count: othersCount),
                bytes: othersBytes
            ))
        }
        result.node.children = nodes.sorted { $0.bytes > $1.bytes }
        result.node.bytes = nodes.reduce(0) { $0 + $1.bytes }
        return result
    }

    /// Les sous-dossiers de la racine en parallèle (un par cœur), les autres à la suite.
    private func subdirectoryPartials(_ directories: [URL], depth: Int, progress: ScanProgress, links: HardLinks) -> [Partial] {
        guard depth == 0, directories.count > 1 else {
            return directories.map { scanDirectory($0, depth: depth + 1, progress: progress, links: links) }
        }
        let results = PartialBox(count: directories.count)
        DispatchQueue.concurrentPerform(iterations: directories.count) { index in
            results.set(index, scanDirectory(directories[index], depth: depth + 1, progress: progress, links: links))
        }
        return results.values
    }
}

/// Les fichiers à liens multiples déjà comptés, partagés par les fils du scan (un seul volume).
private final class HardLinks: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: Set<UInt64> = []

    /// `true` la première fois qu'on voit ce fichier, `false` pour ses autres liens.
    func firstSighting(of inode: UInt64) -> Bool {
        lock.withLock { seen.insert(inode).inserted }
    }
}

/// Résultats écrits par plusieurs fils, chacun à son indice.
private final class PartialBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DiskScanner.Partial?]

    init(count: Int) {
        items = Array(repeating: nil, count: count)
    }

    func set(_ index: Int, _ partial: DiskScanner.Partial) {
        lock.withLock { items[index] = partial }
    }

    var values: [DiskScanner.Partial] { lock.withLock { items.compactMap { $0 } } }
}
