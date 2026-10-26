import AppKit
import MenageCore
import SwiftUI

/// Le panneau qui s'ouvre depuis la barre de menus.
struct MenuBarPanel: View {
    let monitor: MonitorModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let snapshot = monitor.snapshot {
                VStack(spacing: 12) {
                    diskRow(snapshot)
                    swapRow(snapshot)
                    pressureRow(snapshot)
                }
                Divider()
                topApps(snapshot)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Ménage").font(.headline)
            Spacer()
            Label(monitor.overall.summary, systemImage: monitor.overall.menuBarSymbol)
                .font(.subheadline)
                .foregroundStyle(monitor.overall == .normal ? Color.secondary : monitor.overall.tint)
        }
    }

    private func diskRow(_ snapshot: SystemSnapshot) -> some View {
        MetricRow(
            title: "Disque",
            symbol: "internaldrive",
            value: "\(ByteFormat.string(snapshot.diskFree)) libres",
            detail: "sur \(ByteFormat.string(snapshot.diskTotal))",
            fraction: snapshot.diskUsedFraction,
            level: monitor.level(of: .disque)
        )
    }

    private func swapRow(_ snapshot: SystemSnapshot) -> some View {
        let critique = ByteFormat.gigabytes(monitor.thresholds.swapCritiqueGB)
        return MetricRow(
            title: "Swap",
            symbol: "arrow.left.arrow.right",
            value: "\(ByteFormat.string(snapshot.swapUsed)) utilisés",
            detail: "critique à \(ByteFormat.string(critique))",
            fraction: critique > 0 ? Double(snapshot.swapUsed) / Double(critique) : 0,
            level: monitor.level(of: .swap)
        )
    }

    private func pressureRow(_ snapshot: SystemSnapshot) -> some View {
        MetricRow(
            title: "Mémoire",
            symbol: "memorychip",
            value: "Pression \(snapshot.pressure.label)",
            detail: "\(ByteFormat.ram(snapshot.physicalMemory)) de RAM",
            fraction: nil,
            level: monitor.level(of: .memoire)
        )
    }

    private func topApps(_ snapshot: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps les plus gourmandes")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(snapshot.topApps) { app in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).lineLimit(1)
                        if app.processCount > 1 {
                            Text("\(app.processCount) processus")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(ByteFormat.string(app.bytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if monitor.canQuit(app) {
                        Button {
                            monitor.quit(app)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Quitter \(app.name)")
                    } else {
                        Image(systemName: "xmark.circle").hidden()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Moniteur d'activité") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Spacer()
            Button("Réglages") {
                NSApp.activate()
                openSettings()
            }
            Button("Quitter") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .font(.subheadline)
    }
}

private struct MetricRow: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let fraction: Double?
    let level: Level

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(level == .normal ? Color.secondary : level.tint)
                Text(title)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(value).monospacedDigit()
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let fraction {
                GaugeBar(fraction: fraction, tint: level.tint)
            }
        }
    }
}

/// Barre de remplissage fine.
private struct GaugeBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}
