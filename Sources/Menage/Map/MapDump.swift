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
    @MainActor
    static func renderTreemapIfRequested() {
        guard let output = ProcessInfo.processInfo.environment["MENAGE_TREEMAP"] else { return }
        let directory = ProcessInfo.processInfo.environment["MENAGE_TREEMAP_DIR"] ?? "~"
        let root = DiskScanner().scan(URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)).root
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

    private static func countNodes(_ node: DiskNode) -> Int {
        1 + node.children.reduce(0) { $0 + countNodes($1) }
    }
}
#endif
