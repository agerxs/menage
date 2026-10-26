import Foundation

/// Un dossier ou un fichier de la carte, avec sa place occupée.
///
/// L'arbre n'est pas complet : les éléments de moins de 1 Mo d'un dossier sont regroupés en un seul
/// nœud « autres », et sous une certaine profondeur on ne garde que les totaux. Sinon `node_modules`
/// seul ferait des centaines de milliers de nœuds.
public struct DiskNode: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        case directory
        case file
        /// Les petits éléments d'un dossier, regroupés.
        case others(count: Int)
    }

    public var path: String
    public var name: String
    public var kind: Kind
    public var bytes: Int64
    /// Du plus lourd au plus léger.
    public var children: [DiskNode]

    public init(path: String, name: String, kind: Kind, bytes: Int64, children: [DiskNode] = []) {
        self.path = path
        self.name = name
        self.kind = kind
        self.bytes = bytes
        self.children = children
    }

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var isDirectory: Bool { kind == .directory }
    public var isOthers: Bool { if case .others = kind { true } else { false } }
    public var canOpen: Bool { isDirectory && !children.isEmpty }

    /// Le nœud à ce chemin, s'il est dans l'arbre.
    public func node(atPath target: String) -> DiskNode? {
        if target == path { return self }
        guard let child = children.first(where: { target == $0.path || target.hasPrefix($0.path + "/") }) else { return nil }
        return child.node(atPath: target)
    }

    /// Les nœuds de la racine jusqu'à ce chemin, pour le fil d'Ariane.
    public func ancestry(of target: String) -> [DiskNode] {
        if target == path { return [self] }
        guard let child = children.first(where: { target == $0.path || target.hasPrefix($0.path + "/") }) else { return [self] }
        return [self] + child.ancestry(of: target)
    }

    /// L'arbre sans ce nœud, tailles des parents corrigées (après une mise à la Corbeille).
    ///
    /// Si le chemin n'est pas dans l'arbre (fichier sous la profondeur où le détail est coupé),
    /// `bytes` est retiré du nœud le plus profond qui le contient, et de tous ses parents.
    public func removing(path target: String, bytes fallback: Int64 = 0) -> DiskNode {
        var copy = self
        if let index = copy.children.firstIndex(where: { $0.path == target }) {
            copy.bytes -= copy.children[index].bytes
            copy.children.remove(at: index)
        } else if let index = copy.children.firstIndex(where: { target.hasPrefix($0.path + "/") }) {
            let updated = copy.children[index].removing(path: target, bytes: fallback)
            copy.bytes -= copy.children[index].bytes - updated.bytes
            copy.children[index] = updated
        } else if target.hasPrefix(path + "/") {
            copy.bytes = max(copy.bytes - fallback, 0)
        }
        return copy
    }
}

public struct BigFile: Sendable, Identifiable, Equatable {
    public var path: String
    public var bytes: Int64
    public var modified: Date?

    public init(path: String, bytes: Int64, modified: Date?) {
        self.path = path
        self.bytes = bytes
        self.modified = modified
    }

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { (path as NSString).lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }
}
