import Foundation

/// État du Mac à un instant donné : disque de démarrage, swap, pression mémoire, apps les plus lourdes.
public struct SystemSnapshot: Sendable, Equatable {
    public var date: Date
    public var diskFree: Int64
    public var diskTotal: Int64
    public var swapUsed: Int64
    public var swapTotal: Int64
    public var physicalMemory: Int64
    public var pressure: MemoryPressure
    public var topApps: [AppMemory]

    public init(
        date: Date = Date(),
        diskFree: Int64,
        diskTotal: Int64,
        swapUsed: Int64,
        swapTotal: Int64,
        physicalMemory: Int64,
        pressure: MemoryPressure,
        topApps: [AppMemory] = []
    ) {
        self.date = date
        self.diskFree = diskFree
        self.diskTotal = diskTotal
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.physicalMemory = physicalMemory
        self.pressure = pressure
        self.topApps = topApps
    }

    public var diskUsedFraction: Double {
        diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0
    }
}

/// Niveau de pression mémoire tel que le noyau le publie (`kern.memorystatus_vm_pressure_level`).
public enum MemoryPressure: Sendable, Equatable {
    case normale, elevee, critique

    /// Le noyau publie 1 (normal), 2 (avertissement) ou 4 (critique).
    public init(sysctlLevel: Int32) {
        switch sysctlLevel {
        case 4: self = .critique
        case 2: self = .elevee
        default: self = .normale
        }
    }

    public var label: String {
        switch self {
        case .normale: "normale"
        case .elevee: "élevée"
        case .critique: "critique"
        }
    }
}

/// Mémoire consommée par une app, tous ses processus additionnés.
public struct AppMemory: Sendable, Equatable, Identifiable {
    /// Chemin du bundle `.app`, ou `process:<nom>` pour un processus hors app.
    public var id: String
    public var name: String
    public var bundlePath: String?
    public var bytes: Int64
    public var processCount: Int

    public init(id: String, name: String, bundlePath: String?, bytes: Int64, processCount: Int) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.bytes = bytes
        self.processCount = processCount
    }
}
