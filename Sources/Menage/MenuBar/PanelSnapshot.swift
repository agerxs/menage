#if DEBUG
import AppKit
import SwiftUI

/// Outil de développement : `MENAGE_RENDER=/chemin.png swift run Menage` enregistre le panneau
/// en image puis quitte. Sert à vérifier le rendu sans cliquer dans la barre de menus.
enum PanelSnapshot {
    @MainActor
    static func renderIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["MENAGE_RENDER"] else { return }
        Task { @MainActor in
            let monitor = MonitorModel()
            await monitor.refresh()
            let renderer = ImageRenderer(
                content: MenuBarPanel(monitor: monitor)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .dark)
            )
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("rendu impossible\n".utf8))
                exit(1)
            }
            try? png.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
#endif
