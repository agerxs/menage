import Foundation
import MenageCore
import Observation

/// L'historique : instantanés des scans, courbe de l'espace libre, scan quotidien.
@MainActor
@Observable
final class HistoryModel {
    private static let autoScanKey = "history.autoScan"
    /// Une croissance de cette taille entre deux scans automatiques mérite une notification.
    static let notableGrowth: Int64 = 5_000_000_000

    private(set) var snapshots: [DiskSnapshot] = []
    private(set) var samples: [FreeSpaceSample] = []
    var period = GrowthReport.Period.lastScan
    var autoScan: Bool {
        didSet { UserDefaults.standard.set(autoScan, forKey: Self.autoScanKey) }
    }

    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored private let freeSpaceLog: FreeSpaceLog
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private let map: DiskMapModel

    init(map: DiskMapModel, store: SnapshotStore = .standard(), freeSpaceLog: FreeSpaceLog = .standard()) {
        self.map = map
        self.store = store
        self.freeSpaceLog = freeSpaceLog
        autoScan = UserDefaults.standard.object(forKey: Self.autoScanKey) as? Bool ?? true
        snapshots = store.load()
        samples = freeSpaceLog.read()
        map.onScanned = { [weak self] result, automatic in self?.record(result, automatic: automatic) }
        sampleFreeSpace()
        // Toutes les heures : un relevé d'espace libre, et le scan du jour s'il n'a pas eu lieu.
        // Le premier passage attend 10 minutes : pas de scan lourd pendant l'ouverture de session.
        // La référence à self n'est prise que le temps d'un passage, pas pendant l'heure d'attente.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            while !Task.isCancelled {
                guard await self?.tick() != nil else { return }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    private func tick() async {
        sampleFreeSpace()
        await scanIfDue()
    }

    var latest: DiskSnapshot? { snapshots.last }
    var baseline: DiskSnapshot? { GrowthReport.baseline(in: snapshots, period: period) }

    /// Calculé à l'appel : la vue le lit une fois par affichage.
    func report() -> [Growth] {
        guard let latest, let baseline else { return [] }
        return GrowthReport.growth(from: baseline, to: latest)
    }

    var lastScanDate: Date? { latest?.date }
    private(set) var saveError: String?

    private func record(_ result: DiskScanResult, automatic: Bool) {
        let disk = SystemReader.diskSpace(volume: URL(fileURLWithPath: "/"))
        let snapshot = DiskSnapshot(root: result.root, unreadable: result.unreadable, diskFree: disk.free)
        let previous = snapshots.last
        do {
            try store.save(snapshot)
            saveError = nil
        } catch {
            saveError = "Analyse non enregistrée dans l'historique : \(error.localizedDescription)"
            return
        }
        snapshots = store.load()
        if automatic, let previous { notifyNotableGrowth(from: previous, to: snapshot) }
    }

    /// Prévient quand un dossier a beaucoup grossi depuis le dernier scan : c'est le signal
    /// qui aurait évité le disque plein (un cache qui s'emballe, une sauvegarde oubliée).
    /// Un déplacement ou un dossier redevenu lisible ne compte pas.
    private func notifyNotableGrowth(from previous: DiskSnapshot, to snapshot: DiskSnapshot) {
        guard let top = GrowthReport.notable(from: previous, to: snapshot, threshold: Self.notableGrowth) else {
            return
        }
        notifier.post(
            id: "menage.growth",
            title: "\(Self.display(top.path)) a grossi",
            body: "+\(ByteFormat.string(top.realDelta)) depuis le dernier scan, \(ByteFormat.string(top.after)) au total. Ouvre Ménage, onglet Historique."
        )
    }

    private func sampleFreeSpace() {
        if let last = samples.last, Date().timeIntervalSince(last.date) < 3000 { return }
        let disk = SystemReader.diskSpace(volume: URL(fileURLWithPath: "/"))
        let swap = SystemReader.swapUsage()
        try? freeSpaceLog.append(FreeSpaceSample(date: Date(), diskFree: disk.free, swapUsed: swap.used))
        samples = freeSpaceLog.read()
    }

    /// Un scan par jour quand l'app tourne, sauf en mode économie d'énergie ou si le Mac chauffe.
    private func scanIfDue() async {
        guard autoScan, !map.isScanning, DailyScan.isDue(lastSnapshot: snapshots.last?.date, now: Date()) else { return }
        let info = ProcessInfo.processInfo
        guard !info.isLowPowerModeEnabled, info.thermalState == .nominal || info.thermalState == .fair else { return }
        await map.scan(automatic: true)
    }

    /// `Library/Caches/com.openai.codex` → `~/Library/Caches/com.openai.codex`.
    static func display(_ relativePath: String) -> String {
        "~/" + relativePath
    }
}
