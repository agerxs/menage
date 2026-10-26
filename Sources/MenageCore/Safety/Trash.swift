import Foundation

/// Mise à la Corbeille. Jamais de `removeItem` : tout reste récupérable depuis le Finder.
public protocol Trasher: Sendable {
    func trash(_ url: URL) throws
}

public struct SystemTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
