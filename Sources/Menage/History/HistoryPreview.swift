#if DEBUG
import AppKit
import MenageCore
import SwiftUI

/// Outil de développement : `MENAGE_HISTORY=/chemin.png swift run Menage` remplit un historique de test
/// dans un dossier temporaire (jamais le vrai) et rend l'onglet Historique en image.
enum HistoryPreview {
    @MainActor
    static func renderIfRequested() {
        guard let output = ProcessInfo.processInfo.environment["MENAGE_HISTORY"] else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("menage-history-preview-\(UUID().uuidString)")
        let store = SnapshotStore(directory: directory)
        let log = FreeSpaceLog(url: directory.appendingPathComponent("free.jsonl"))
        let now = Date()
        let gb: Int64 = 1_000_000_000
        for day in stride(from: 30, through: 0, by: -1) {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            let codex = Int64(Double(gb) * (1 + Double(30 - day) * 0.1))
            // Il y a 3 jours : my-app grossit de 3 Go, et 5 Go de vidéos passent de Téléchargements à Projects.
            var sizes: [String: Int64] = [
                "Library": 100 * gb + codex,
                "Library/Caches": 6 * gb + codex,
                "Library/Caches/com.openai.codex": codex,
                "Projects": 60 * gb + (day < 3 ? 8 * gb : 0),
                "Projects/my-app": 10 * gb + (day < 3 ? 3 * gb : 0),
                "Downloads": day < 3 ? 14 * gb : 19 * gb,
            ]
            if day < 3 { sizes["Projects/videos"] = 5 * gb } else { sizes["Downloads/videos"] = 5 * gb }
            try? store.save(DiskSnapshot(date: date, scannedBytes: 250 * gb, diskFree: (60 - Int64(30 - day)) * gb, sizes: sizes), now: now)
            for hour in stride(from: 0, to: 24, by: 6) {
                let sample = date.addingTimeInterval(Double(hour) * 3600)
                guard sample <= now else { continue }
                try? log.append(FreeSpaceSample(date: sample, diskFree: (60 - Int64(30 - day)) * gb - Int64(hour) * 50_000_000, swapUsed: 0))
            }
        }
        let map = DiskMapModel(protectedPaths: { .standard(home: FileManager.default.homeDirectoryForCurrentUser) }, onTrash: {})
        let history = HistoryModel(map: map, store: store, freeSpaceLog: log)
        history.autoScan = UserDefaults.standard.object(forKey: "history.autoScan") as? Bool ?? true
        history.period = .days(7)

        let renderer = ImageRenderer(content: HistoryContent(model: history, map: map, showsPeriodPicker: false) {}
            .frame(width: 900)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: output))
        }
        try? FileManager.default.removeItem(at: directory)
        exit(0)
    }
}
#endif
