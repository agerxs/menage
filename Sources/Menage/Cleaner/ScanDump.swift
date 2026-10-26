#if DEBUG
import Foundation
import MenageCore

/// Outil de développement : `MENAGE_SCAN=1 swift run Menage` lance l'analyse réelle,
/// l'affiche dans le terminal et quitte. Ne supprime rien.
enum ScanDump {
    @MainActor
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["MENAGE_SCAN"] != nil else { return }
        Task { @MainActor in
            let model = CleanerModel()
            let start = Date()
            await model.scan()
            var lines = ["Analyse en \(Int(Date().timeIntervalSince(start))) s, \(ByteFormat.string(model.foundBytes)) trouvés"]
            for report in model.reports {
                let mark = report.risk.preselected ? "[x]" : "[ ]"
                lines.append("\n\(mark) \(report.title) [\(report.risk.label)] : \(ByteFormat.string(report.totalBytes))\(report.note.map { " (\($0))" } ?? "")")
                for candidate in report.candidates {
                    lines.append("      \(ByteFormat.string(candidate.bytes).padding(toLength: 9, withPad: " ", startingAt: 0)) \(candidate.title) | \(candidate.detail)")
                }
            }
            lines.append("\nCoché par défaut : \(model.selection.count) éléments, \(ByteFormat.string(model.selectedBytes))")
            print(lines.joined(separator: "\n"))
            exit(0)
        }
    }
}
#endif
