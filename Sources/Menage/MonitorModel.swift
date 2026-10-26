import AppKit
import MenageCore
import Observation

/// Relève l'état du Mac toutes les 5 secondes et déclenche les alertes.
@MainActor
@Observable
final class MonitorModel {
    static let refreshInterval: Duration = .seconds(5)
    private static let thresholdsKey = "thresholds"

    private(set) var snapshot: SystemSnapshot?
    var thresholds: Thresholds {
        didSet { save(thresholds) }
    }

    @ObservationIgnored private var policy = AlertPolicy()
    @ObservationIgnored private let notifier = Notifier()

    init() {
        thresholds = Self.loadThresholds()
        notifier.requestAuthorization()
        // La boucle s'arrête d'elle-même si le modèle disparaît.
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    var overall: Level {
        snapshot.map { thresholds.overall(in: $0) } ?? .normal
    }

    func level(of signal: Signal) -> Level {
        snapshot.map { thresholds.level(of: signal, in: $0) } ?? .normal
    }

    func refresh() async {
        let reading = await Task.detached(priority: .utility) { SystemReader.read() }.value
        snapshot = reading
        for alert in policy.alerts(for: reading, thresholds: thresholds) {
            notifier.post(alert)
        }
    }

    /// Demande à l'app de quitter proprement, comme Cmd-Q : elle peut proposer d'enregistrer.
    func quit(_ app: AppMemory) {
        guard canQuit(app), let bundlePath = app.bundlePath else { return }
        for running in NSWorkspace.shared.runningApplications
        where running.bundleURL?.path == bundlePath && running != .current {
            running.terminate()
        }
    }

    /// Jamais Ménage lui-même ni une app système (Finder, Dock, loginwindow…).
    func canQuit(_ app: AppMemory) -> Bool {
        guard let bundlePath = app.bundlePath,
              bundlePath != Bundle.main.bundlePath,
              !bundlePath.hasPrefix("/System/") else { return false }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == bundlePath }
    }

    func sendTestNotification() {
        notifier.postTest()
    }

    private func save(_ thresholds: Thresholds) {
        guard let data = try? JSONEncoder().encode(thresholds) else { return }
        UserDefaults.standard.set(data, forKey: Self.thresholdsKey)
    }

    private static func loadThresholds() -> Thresholds {
        if let data = UserDefaults.standard.data(forKey: thresholdsKey),
           let saved = try? JSONDecoder().decode(Thresholds.self, from: data),
           saved.isConsistent {
            return saved
        }
        return .standard(physicalMemory: Int64(ProcessInfo.processInfo.physicalMemory))
    }
}
