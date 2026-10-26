import Foundation

public struct Alert: Equatable, Sendable {
    public var signal: Signal
    public var level: Level
    public var title: String
    public var body: String
}

/// Décide quand notifier.
///
/// Une notification quand un signal monte d'un palier. Le même palier d'un même signal n'est
/// pas renotifié avant `cooldown`, pour qu'un disque qui oscille autour de 40 Go ne spamme pas.
/// Passer d'attention à critique notifie tout de suite : c'est un autre palier.
public struct AlertPolicy: Sendable {
    public var cooldown: TimeInterval
    private var previousLevels: [Signal: Level] = [:]
    private var lastNotified: [Signal: [Level: Date]] = [:]

    public init(cooldown: TimeInterval = 30 * 60) {
        self.cooldown = cooldown
    }

    public mutating func alerts(for snapshot: SystemSnapshot, thresholds: Thresholds, now: Date = Date()) -> [Alert] {
        var alerts: [Alert] = []
        for signal in Signal.allCases {
            let level = thresholds.level(of: signal, in: snapshot)
            let previous = previousLevels[signal] ?? .normal
            previousLevels[signal] = level
            guard level > previous else { continue }
            if let last = lastNotified[signal]?[level], now.timeIntervalSince(last) < cooldown { continue }
            lastNotified[signal, default: [:]][level] = now
            alerts.append(Self.alert(signal: signal, level: level, snapshot: snapshot))
        }
        return alerts
    }

    static func alert(signal: Signal, level: Level, snapshot: SystemSnapshot) -> Alert {
        let critique = level == .critique
        let heaviest = snapshot.topApps.first.map { " Le plus gourmand : \($0.name) (\(ByteFormat.string($0.bytes)))." } ?? ""
        switch signal {
        case .disque:
            let free = ByteFormat.string(snapshot.diskFree)
            return Alert(
                signal: signal, level: level,
                title: critique ? "Disque presque plein" : "Espace disque bas",
                body: critique
                    ? "Plus que \(free) libres. Le swap n'aura bientôt plus de place : libère de l'espace maintenant."
                    : "Plus que \(free) libres sur le disque de démarrage."
            )
        case .swap:
            let swap = ByteFormat.string(snapshot.swapUsed)
            return Alert(
                signal: signal, level: level,
                title: critique ? "Swap très élevé" : "Swap élevé",
                body: "\(swap) de mémoire déchargés sur le disque.\(heaviest)"
            )
        case .memoire:
            return Alert(
                signal: signal, level: level,
                title: critique ? "Mémoire saturée" : "Mémoire sous pression",
                body: critique
                    ? "Le Mac va ralentir ou se bloquer. Ferme une app lourde.\(heaviest)"
                    : "La pression mémoire est élevée.\(heaviest)"
            )
        }
    }
}
