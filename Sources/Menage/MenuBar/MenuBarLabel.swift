import MenageCore
import SwiftUI

/// Ce qui reste visible dans la barre de menus : une icône d'état et l'espace libre.
struct MenuBarLabel: View {
    let monitor: MonitorModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: monitor.overall.menuBarSymbol)
            if let snapshot = monitor.snapshot {
                Text(ByteFormat.string(snapshot.diskFree))
                    .monospacedDigit()
            }
        }
    }
}

extension Level {
    var menuBarSymbol: String {
        switch self {
        case .normal: "internaldrive"
        case .attention: "exclamationmark.triangle"
        case .critique: "exclamationmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .normal: .accentColor
        case .attention: .orange
        case .critique: .red
        }
    }

    var summary: String {
        switch self {
        case .normal: "Tout va bien"
        case .attention: "À surveiller"
        case .critique: "Critique"
        }
    }
}
