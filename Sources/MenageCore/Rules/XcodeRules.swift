import Foundation

public struct DerivedDataRule: CleanupRule {
    public let id = "xcode.deriveddata"
    public let title = "Xcode : DerivedData"
    public let explanation = "Index et fichiers de compilation d'Xcode. Ils se reconstruisent au prochain build."
    public let risk = Risk.sansRisque

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        let derivedData = context.home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let candidates = subdirectories(of: derivedData)
            .map { Candidate.trash($0, title: Self.projectName($0.lastPathComponent), detail: $0.lastPathComponent) }
            .filter { $0.bytes >= 1_000_000 }
            .sorted { $0.bytes > $1.bytes }
        return RuleScan(candidates: candidates)
    }

    /// `Runner-fzbvdkqmejxhwygoxiuwcmrdkuoz` → `Runner`.
    static func projectName(_ folder: String) -> String {
        guard let dash = folder.lastIndex(of: "-") else { return folder }
        return String(folder[..<dash])
    }
}

public struct UnavailableSimulatorsRule: CleanupRule {
    public let id = "xcode.simulators"
    public let title = "Simulateurs iOS obsolètes"
    public let explanation = "Simulateurs dont la version d'iOS n'est plus installée : ils ne peuvent plus démarrer."
    public let risk = Risk.sansRisque

    public init() {}

    public func scan(_ context: CleanupContext) -> RuleScan {
        guard let result = context.runner.run(
            Executables.xcrun, ["simctl", "list", "devices", "unavailable", "--json"], in: nil
        ), result.succeeded else {
            return RuleScan(note: "xcrun simctl ne répond pas (Xcode absent ?)")
        }
        let devices = Self.unavailableDevices(fromJSON: result.output)
        guard !devices.isEmpty else { return RuleScan() }
        let devicesDirectory = context.home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        let bytes = devices.reduce(Int64(0)) { $0 + DirectorySize.of(devicesDirectory.appendingPathComponent($1.udid)) }
        let names = devices.map(\.name).sorted().joined(separator: ", ")
        return RuleScan(candidates: [Candidate(
            id: candidateID("unavailable"),
            title: devices.count == 1 ? "1 simulateur indisponible" : "\(devices.count) simulateurs indisponibles",
            detail: names,
            bytes: bytes,
            action: .command(Command(executable: Executables.xcrun, arguments: ["simctl", "delete", "unavailable"])),
            location: devicesDirectory
        )])
    }

    struct Device: Decodable, Equatable {
        var udid: String
        var name: String
    }

    static func unavailableDevices(fromJSON json: String) -> [Device] {
        struct Listing: Decodable { var devices: [String: [Device]] }
        guard let listing = try? JSONDecoder().decode(Listing.self, from: Data(json.utf8)) else { return [] }
        return listing.devices.values.flatMap { $0 }
    }
}
