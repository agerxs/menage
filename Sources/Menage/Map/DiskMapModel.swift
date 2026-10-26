import AppKit
import MenageCore
import Observation

/// Le scan du dossier perso, partagé par la carte et la liste des gros fichiers.
@MainActor
@Observable
final class DiskMapModel {
    enum Phase: Equatable {
        case idle, scanning, ready
    }

    private(set) var phase = Phase.idle
    private(set) var root: DiskNode?
    private(set) var bigFiles: [BigFile] = []
    private(set) var unreadable: [String] = []
    private(set) var fileCount = 0
    private(set) var scanDate: Date?
    private(set) var scanDuration: TimeInterval = 0
    /// Pendant le scan : fichiers vus et place comptée.
    private(set) var progressFiles = 0
    private(set) var progressBytes: Int64 = 0
    var currentPath: String?
    var selectedPath: String?
    private(set) var lastError: String?

    let scanRoot = FileManager.default.homeDirectoryForCurrentUser
    @ObservationIgnored private let protectedPaths: @MainActor () -> ProtectedPaths
    @ObservationIgnored private let onTrash: @MainActor () -> Void
    /// Appelé après chaque scan. `automatic` : lancé par le scan quotidien, pas par un clic.
    @ObservationIgnored var onScanned: (@MainActor (DiskScanResult, _ automatic: Bool) -> Void)?

    /// `protectedPaths` : les chemins protégés à jour (ils dépendent des racines de projets réglées).
    /// `onTrash` : appelé après une mise à la Corbeille, pour rafraîchir le journal.
    init(protectedPaths: @escaping @MainActor () -> ProtectedPaths, onTrash: @escaping @MainActor () -> Void) {
        self.protectedPaths = protectedPaths
        self.onTrash = onTrash
    }

    var current: DiskNode? {
        guard let root else { return nil }
        return root.node(atPath: currentPath ?? root.path) ?? root
    }

    var breadcrumb: [DiskNode] {
        guard let root, let current else { return [] }
        return root.ancestry(of: current.path)
    }

    var selected: DiskNode? {
        guard let root, let selectedPath else { return nil }
        return root.node(atPath: selectedPath)
    }

    /// Le scan quotidien tourne sans toucher à l'affichage : la carte reste utilisable pendant ce temps.
    private(set) var backgroundScanning = false
    /// Dossier à montrer dès que l'arbre est là (« Voir sur la carte » avant tout scan).
    @ObservationIgnored private var pendingReveal: String?

    var isScanning: Bool { phase == .scanning || backgroundScanning }

    func scan(automatic: Bool = false) async {
        guard !isScanning else { return }
        if automatic {
            backgroundScanning = true
        } else {
            phase = .scanning
            progressFiles = 0
            progressBytes = 0
        }
        lastError = nil
        let progress = ScanProgress()
        let root = scanRoot

        let poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                self?.progressFiles = progress.files
                self?.progressBytes = progress.bytes
            }
        }
        // Le scan quotidien passe en arrière-plan : il ne doit pas ralentir ce que fait l'utilisateur.
        let result = await Task.detached(priority: automatic ? .background : .userInitiated) {
            DiskScanner().scan(root, progress: progress)
        }.value
        poller.cancel()

        self.root = result.root
        bigFiles = result.bigFiles
        unreadable = result.unreadable
        fileCount = result.fileCount
        scanDuration = result.duration
        scanDate = Date()
        // On reste où l'on était si ce dossier existe toujours.
        if let path = currentPath, result.root.node(atPath: path) == nil { currentPath = nil }
        if let path = selectedPath, result.root.node(atPath: path) == nil { selectedPath = nil }
        backgroundScanning = false
        phase = .ready
        if let pending = pendingReveal {
            pendingReveal = nil
            reveal(relativePath: pending)
        }
        onScanned?(result, automatic)
    }

    /// Ouvre la carte sur ce dossier (relatif au dossier perso). Sans arbre en mémoire (app relancée
    /// depuis), lance d'abord l'analyse et y va ensuite.
    func reveal(relativePath: String) {
        guard let root else {
            pendingReveal = relativePath
            Task { await scan() }
            return
        }
        let path = scanRoot.appendingPathComponent(relativePath).path
        guard let node = root.node(atPath: path) else { return }
        currentPath = node.canOpen ? node.path : (path as NSString).deletingLastPathComponent
        selectedPath = node.canOpen ? nil : node.path
    }

    func open(_ node: DiskNode) {
        if node.canOpen {
            currentPath = node.path
            selectedPath = nil
        } else {
            selectedPath = node.path
        }
    }

    func goTo(_ node: DiskNode) {
        currentPath = node.path
        selectedPath = nil
    }

    func goUp() {
        let crumbs = breadcrumb
        guard crumbs.count > 1 else { return }
        goTo(crumbs[crumbs.count - 2])
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Pourquoi ce chemin ne peut pas aller à la Corbeille, ou `nil` s'il le peut.
    func trashRefusal(for path: String) -> String? {
        if root?.node(atPath: path)?.isOthers == true { return "regroupement de petits éléments, pas un vrai dossier" }
        return ManualTrashPolicy(protected: protectedPaths(), home: scanRoot).refusal(for: path)
    }

    func trash(_ path: String, bytes: Int64) {
        let url = URL(fileURLWithPath: path)
        if let refusal = trashRefusal(for: path) {
            lastError = "Refusé : \(refusal)"
            return
        }
        do {
            try SystemTrasher().trash(url)
        } catch {
            lastError = "Impossible de mettre à la Corbeille : \(error.localizedDescription)"
            return
        }
        try? ActionJournal.standard().append(JournalEntry(
            date: Date(), ruleID: "manuel", title: "Carte du disque", method: .corbeille,
            items: [path], bytes: bytes, errors: []
        ))
        root = root?.removing(path: path, bytes: bytes)
        bigFiles.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
        if selectedPath == path { selectedPath = nil }
        if let currentPath, currentPath == path || currentPath.hasPrefix(path + "/") {
            self.currentPath = (path as NSString).deletingLastPathComponent
        }
        lastError = nil
        onTrash()
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
