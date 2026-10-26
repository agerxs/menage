import Charts
import MenageCore
import SwiftUI

/// L'onglet Historique : la courbe de l'espace libre et ce qui a grossi.
struct HistoryView: View {
    @Bindable var model: HistoryModel
    let map: DiskMapModel
    let showOnMap: () -> Void

    private static let dateFormat: Date.FormatStyle = .dateTime.day().month(.wide).hour().minute()
        .locale(Locale(identifier: "fr_FR"))

    var body: some View {
        VStack(spacing: 0) {
            ActionBar(subtitle: subtitle) {
                Toggle("Analyse quotidienne", isOn: $model.autoScan)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Une analyse par jour quand Ménage tourne, en arrière-plan. Elle alimente cet historique.")
                Button("Analyser maintenant") { Task { await map.scan() } }
                    .disabled(map.isScanning)
            }
            Divider()
            ScrollView {
                HistoryContent(model: model, map: map, showOnMap: showOnMap)
            }
        }
    }

    private var subtitle: String {
        if map.isScanning { return map.backgroundScanning ? "Analyse quotidienne en cours, en arrière-plan…" : "Analyse en cours…" }
        guard let last = model.lastScanDate else { return "Aucune analyse enregistrée pour l'instant." }
        let count = model.snapshots.count
        return "\(count) analyse\(count > 1 ? "s" : "") enregistrée\(count > 1 ? "s" : ""), la dernière le \(last.formatted(Self.dateFormat))"
    }
}

/// La courbe et la liste, sans le défilement (que le rendu en image ne sait pas dessiner).
struct HistoryContent: View {
    @Bindable var model: HistoryModel
    let map: DiskMapModel
    let showOnMap: () -> Void

    private static let dateFormat: Date.FormatStyle = .dateTime.day().month(.wide).hour().minute()
        .locale(Locale(identifier: "fr_FR"))

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            freeSpaceChart
            growthSection
        }
        .padding(20)
    }

    @ViewBuilder
    private var freeSpaceChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Espace libre").font(.headline)
            if model.samples.count < 2 {
                Text("Un relevé par heure tant que Ménage tourne. La courbe apparaît dès le deuxième.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Chart(model.samples) { sample in
                    AreaMark(x: .value("Date", sample.date), y: .value("Go libres", Double(sample.diskFree) / 1e9))
                        .foregroundStyle(.linearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    LineMark(x: .value("Date", sample.date), y: .value("Go libres", Double(sample.diskFree) / 1e9))
                        .foregroundStyle(Color.accentColor)
                }
                .chartYAxisLabel("Go libres")
                .chartYScale(domain: .automatic(includesZero: true))
                .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private var growthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ce qui a grossi").font(.headline)
                Spacer()
                Picker("Période", selection: $model.period) {
                    Text("Depuis la dernière analyse").tag(GrowthReport.Period.lastScan)
                    Text("Sur 7 jours").tag(GrowthReport.Period.days(7))
                    Text("Sur 30 jours").tag(GrowthReport.Period.days(30))
                }
                .labelsHidden()
                .fixedSize()
            }
            if let baseline = model.baseline, let latest = model.latest {
                Text("Du \(baseline.date.formatted(Self.dateFormat)) au \(latest.date.formatted(Self.dateFormat)). Espace libre : \(ByteFormat.string(baseline.diskFree)) → \(ByteFormat.string(latest.diskFree)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                let report = model.report()
                if let error = model.saveError {
                    Text(error).font(.callout).foregroundStyle(.orange)
                }
                if report.isEmpty {
                    Text("Aucun dossier n'a grossi de plus de 100 Mo.")
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(report) { growth in
                            GrowthRow(growth: growth, maxDelta: report.map(\.displayDelta).max() ?? 1) {
                                map.reveal(relativePath: growth.path)
                                showOnMap()
                            }
                            Divider()
                        }
                    }
                }
            } else {
                Text("Il faut deux analyses pour comparer. Avec l'analyse quotidienne, la première comparaison arrive demain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GrowthRow: View {
    let growth: Growth
    let maxDelta: Int64
    let showOnMap: () -> Void

    /// Un déplacement n'est pas une croissance : on le dit plutôt que d'alarmer.
    private var detail: String {
        if let source = growth.movedFrom { return "sans doute déplacé depuis \(HistoryModel.display(source))" }
        if growth.before == 0 { return "nouveau" }
        let sizes = "\(ByteFormat.string(growth.before)) → \(ByteFormat.string(growth.after))"
        return growth.movedBytes > 0 ? "\(sizes), hors \(ByteFormat.string(growth.movedBytes)) déplacés" : sizes
    }


    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(HistoryModel.display(growth.path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                GeometryReader { geometry in
                    Capsule()
                        .fill(growth.movedFrom == nil ? Color.orange.opacity(0.7) : Color.secondary.opacity(0.4))
                        .frame(width: max(4, geometry.size.width * Double(growth.displayDelta) / Double(max(maxDelta, 1))))
                }
                .frame(height: 4)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(ByteFormat.string(growth.displayDelta))").monospacedDigit().fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Voir sur la carte", action: showOnMap)
                .controlSize(.small)
        }
        .padding(.vertical, 8)
    }
}
