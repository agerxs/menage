import Foundation

/// Un processus et son empreinte mémoire (`ri_phys_footprint`, la valeur du Moniteur d'activité).
public struct ProcessFootprint: Sendable, Equatable {
    public var pid: Int32
    public var executablePath: String
    public var bytes: Int64

    public init(pid: Int32, executablePath: String, bytes: Int64) {
        self.pid = pid
        self.executablePath = executablePath
        self.bytes = bytes
    }
}

public enum ProcessGrouping {
    /// Le bundle `.app` le plus extérieur qui contient l'exécutable.
    ///
    /// `/Applications/Firefox.app/Contents/MacOS/plugin-container.app/Contents/MacOS/plugin-container`
    /// appartient à `/Applications/Firefox.app` : les processus d'aide comptent pour leur app.
    public static func appBundlePath(forExecutable path: String) -> String? {
        var bundle = ""
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            bundle += "/" + component
            if component.hasSuffix(".app") { return bundle }
        }
        return nil
    }

    /// Regroupe les processus par app, triés du plus lourd au plus léger.
    public static func group(_ processes: [ProcessFootprint]) -> [AppMemory] {
        var groups: [String: AppMemory] = [:]
        for process in processes where process.bytes > 0 {
            let bundlePath = appBundlePath(forExecutable: process.executablePath)
            let name: String
            let id: String
            if let bundlePath {
                name = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
                id = bundlePath
            } else {
                name = (process.executablePath as NSString).lastPathComponent
                id = "process:" + name
            }
            groups[id, default: AppMemory(id: id, name: name, bundlePath: bundlePath, bytes: 0, processCount: 0)]
                .bytes += process.bytes
            groups[id]?.processCount += 1
        }
        return groups.values.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
    }
}
