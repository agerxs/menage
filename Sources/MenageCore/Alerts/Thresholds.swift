import Foundation

/// Niveau d'un signal, et de l'état général du Mac (le pire des signaux).
public enum Level: Int, Comparable, Sendable, CaseIterable, Codable {
    case normal = 0
    case attention = 1
    case critique = 2

    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum Signal: String, CaseIterable, Sendable, Codable {
    case disque, swap, memoire
}

/// Seuils réglables, en gigaoctets.
///
/// Le swap se juge en valeur absolue : macOS agrandit et réduit son total à la demande
/// (12 Go un jour, 7 Go le lendemain), donc un pourcentage du total ne veut rien dire.
public struct Thresholds: Codable, Equatable, Sendable {
    public var diskAttentionGB: Double
    public var diskCritiqueGB: Double
    public var swapAttentionGB: Double
    public var swapCritiqueGB: Double

    public init(diskAttentionGB: Double, diskCritiqueGB: Double, swapAttentionGB: Double, swapCritiqueGB: Double) {
        self.diskAttentionGB = diskAttentionGB
        self.diskCritiqueGB = diskCritiqueGB
        self.swapAttentionGB = swapAttentionGB
        self.swapCritiqueGB = swapCritiqueGB
    }

    /// Disque : 40 / 20 Go libres. Swap : un quart puis la moitié de la RAM.
    public static func standard(physicalMemory: Int64) -> Thresholds {
        let ramGB = ByteFormat.ramGigabytes(physicalMemory)
        return Thresholds(
            diskAttentionGB: 40,
            diskCritiqueGB: 20,
            swapAttentionGB: (ramGB / 4).rounded(),
            swapCritiqueGB: (ramGB / 2).rounded()
        )
    }

    /// Des seuils que les réglages savent afficher : attention avant critique, écarts minimaux respectés.
    public var isConsistent: Bool {
        diskCritiqueGB >= 5 && diskAttentionGB >= diskCritiqueGB + 5 && diskAttentionGB <= 200
            && swapAttentionGB >= 1 && swapCritiqueGB >= swapAttentionGB + 1
    }

    public func level(of signal: Signal, in snapshot: SystemSnapshot) -> Level {
        switch signal {
        case .disque:
            // Lecture du volume en échec : pas de fausse alerte « 0 octet libre ».
            guard snapshot.diskTotal > 0 else { return .normal }
            if snapshot.diskFree < ByteFormat.gigabytes(diskCritiqueGB) { return .critique }
            if snapshot.diskFree < ByteFormat.gigabytes(diskAttentionGB) { return .attention }
            return .normal
        case .swap:
            if snapshot.swapUsed > ByteFormat.gigabytes(swapCritiqueGB) { return .critique }
            if snapshot.swapUsed > ByteFormat.gigabytes(swapAttentionGB) { return .attention }
            return .normal
        case .memoire:
            switch snapshot.pressure {
            case .normale: return .normal
            case .elevee: return .attention
            case .critique: return .critique
            }
        }
    }

    public func levels(in snapshot: SystemSnapshot) -> [Signal: Level] {
        Dictionary(uniqueKeysWithValues: Signal.allCases.map { ($0, level(of: $0, in: snapshot)) })
    }

    public func overall(in snapshot: SystemSnapshot) -> Level {
        Signal.allCases.map { level(of: $0, in: snapshot) }.max() ?? .normal
    }
}
