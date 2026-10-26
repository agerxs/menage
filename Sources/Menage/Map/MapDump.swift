#if DEBUG
import AppKit
import MenageCore
import SwiftUI

/// Outil de développement : `MENAGE_MAP=~/dossier swift run Menage` scanne le dossier, affiche
/// les plus gros éléments et les gros fichiers, et quitte. Ne supprime rien.
enum MapDump {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["MENAGE_MAP"] else { return }
        let result = DiskScanner().scan(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        var lines = [
            "Scan en \(Int(result.duration)) s : \(result.fileCount) fichiers, \(ByteFormat.string(result.root.bytes)), \(countNodes(result.root)) nœuds gardés",
            "Illisibles : \(result.unreadable.count)" + (result.unreadable.prefix(5).map { "\n    \($0)" }.joined()),
            "\nPlus gros :",
        ]
        for child in result.root.children.prefix(12) {
            lines.append("  \(ByteFormat.string(child.bytes).padding(toLength: 9, withPad: " ", startingAt: 0)) \(child.name) [\(FileCategory.of(child).label)]")
        }
        lines.append("\nGros fichiers (\(result.bigFiles.count) de plus de 100 Mo), les 8 premiers :")
        for file in result.bigFiles.prefix(8) {
            lines.append("  \(ByteFormat.string(file.bytes).padding(toLength: 9, withPad: " ", startingAt: 0)) \(file.path)")
        }
        print(lines.joined(separator: "\n"))
        exit(0)
    }

    /// `MENAGE_TREEMAP=/chemin.png [MENAGE_TREEMAP_DIR=~/devapps]` : rend la carte d'un dossier en image.
    /// `MENAGE_TREEMAP_DIR=demo` : un dossier perso fictif, pour les captures publiques.
    @MainActor
    static func renderTreemapIfRequested() {
        guard let output = ProcessInfo.processInfo.environment["MENAGE_TREEMAP"] else { return }
        let directory = ProcessInfo.processInfo.environment["MENAGE_TREEMAP_DIR"] ?? "~"
        let root = directory == "demo"
            ? demoHome()
            : DiskScanner().scan(URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)).root
        let renderer = ImageRenderer(content: TreemapView(node: root, selectedPath: root.children.first?.path) { _ in }
            .frame(width: 900, height: 540)
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: output))
        }
        exit(0)
    }

    /// Le dossier perso d'un développeur imaginaire : rien de réel, tailles plausibles.
    private static func demoHome() -> DiskNode {
        let home = "/Users/demo"
        let gb: Int64 = 1_000_000_000
        let entries: [(String, DiskNode.Kind, Double)] = [
            ("Library", .directory, 96), ("Projects", .directory, 54), ("Downloads", .directory, 21),
            ("Pictures", .directory, 15), (".android", .directory, 13), ("Movies", .directory, 7.5),
            (".gradle", .directory, 4.2), ("Documents", .directory, 4.8), (".cache", .directory, 3.1),
            ("Music", .directory, 2.6), (".npm", .directory, 1.9), (".vscode", .directory, 1.4),
            ("Xcode_26.xip", .file, 3.4), ("backup-2025.zip", .file, 1.2), (".cargo", .directory, 1.1),
            ("Desktop", .directory, 0.8), (".docker", .directory, 0.6), (".pub-cache", .directory, 0.9),
        ]
        var children = entries.map { name, kind, size in
            DiskNode(path: "\(home)/\(name)", name: name, kind: kind, bytes: Int64(size * Double(gb)))
        }
        children.append(DiskNode(path: "\(home)/\u{2026}", name: "312 petits éléments", kind: .others(count: 312), bytes: gb / 2))
        children.sort { $0.bytes > $1.bytes }
        return DiskNode(path: home, name: "demo", kind: .directory, bytes: children.reduce(0) { $0 + $1.bytes }, children: children)
    }

    private static func countNodes(_ node: DiskNode) -> Int {
        1 + node.children.reduce(0) { $0 + countNodes($1) }
    }
}
#endif
