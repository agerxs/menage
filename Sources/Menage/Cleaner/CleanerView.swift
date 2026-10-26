import MenageCore
import SwiftUI

/// La fenêtre « Faire le ménage » : analyse, choix, confirmation, journal.
struct CleanerView: View {
    static let windowID = "cleaner"

    @Bindable var model: CleanerModel
    @State private var tab = Tab.nettoyage
    @State private var confirming = false

    enum Tab: String, CaseIterable {
        case nettoyage = "Nettoyage"
        case journal = "Journal"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch tab {
                case .nettoyage: cleaningContent
                case .journal: JournalView(entries: model.journalEntries)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if tab == .nettoyage, model.phase == .ready || model.phase == .executing {
                Divider()
                footer
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .sheet(isPresented: $confirming) {
            ConfirmationSheet(model: model, isPresented: $confirming)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Faire le ménage").font(.title2.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Vue", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button(model.reports.isEmpty ? "Analyser" : "Relancer l'analyse") {
                tab = .nettoyage
                Task { await model.scan() }
            }
            .disabled(model.isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var subtitle: String {
        switch model.phase {
        case .idle: "Rien n'est supprimé sans ton accord, et tout passe par la Corbeille."
        case .detectingProjects: "Recherche des projets…"
        case .scanning(let done, let total): "Analyse en cours : \(done) règles sur \(total)"
        case .executing: "Ménage en cours…"
        case .ready: "\(ByteFormat.string(model.foundBytes)) récupérables trouvés"
        }
    }

    @ViewBuilder
    private var cleaningContent: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label("Pas encore analysé", systemImage: "sparkle.magnifyingglass")
            } description: {
                Text("L'analyse cherche les caches, les builds de projets inactifs, les installateurs déjà utilisés et les restes d'Android, d'Xcode et de Docker. Elle ne touche à rien.")
            } actions: {
                Button("Analyser") { Task { await model.scan() } }
                    .buttonStyle(.borderedProminent)
            }
        case .detectingProjects, .scanning:
            VStack(spacing: 12) {
                ProgressView()
                Text(subtitle).foregroundStyle(.secondary)
            }
        case .ready, .executing:
            CandidateList(model: model)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let result = model.lastResult {
                ResultBanner(result: result, openTrash: model.openTrash)
            }
            HStack {
                Text(model.selection.isEmpty
                     ? "Rien de coché"
                     : "\(model.selection.count) éléments cochés · \(ByteFormat.string(model.selectedBytes))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if model.phase == .executing { ProgressView().controlSize(.small) }
                Button("Faire le ménage…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selection.isEmpty || model.isBusy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct CandidateList: View {
    @Bindable var model: CleanerModel

    var body: some View {
        List {
            ForEach(model.reportsWithCandidates) { report in
                Section {
                    ForEach(report.candidates) { candidate in
                        CandidateRow(
                            candidate: candidate,
                            isSelected: model.isSelected(candidate),
                            toggle: { model.toggle(candidate) },
                            reveal: { model.reveal(candidate) }
                        )
                    }
                } header: {
                    RuleHeader(
                        report: report,
                        fullySelected: model.isFullySelected(report),
                        setSelection: { model.setSelection(report, selected: $0) }
                    )
                }
            }
            if !model.emptyReports.isEmpty {
                Section("Rien à faire") {
                    ForEach(model.emptyReports) { report in
                        HStack {
                            Text(report.title)
                            Spacer()
                            Text(report.note ?? "Propre").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .listStyle(.inset)
        .disabled(model.phase == .executing)
    }
}

private struct RuleHeader: View {
    let report: RuleReport
    let fullySelected: Bool
    let setSelection: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(report.title).font(.headline).foregroundStyle(.primary)
                RiskBadge(risk: report.risk)
                Spacer()
                Text(ByteFormat.string(report.totalBytes))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Button(fullySelected ? "Tout décocher" : "Tout cocher") { setSelection(!fullySelected) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Text(report.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = report.note {
                Text(note).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .textCase(nil)
    }
}

private struct CandidateRow: View {
    let candidate: Candidate
    let isSelected: Bool
    let toggle: () -> Void
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(candidate.title).lineLimit(1)
                    if case .command = candidate.action {
                        Text("Commande")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(.secondary.opacity(0.5)))
                            .foregroundStyle(.secondary)
                            .help("Lancé par un outil externe : ne passe pas par la Corbeille")
                    }
                }
                Text(candidate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(ByteFormat.string(candidate.bytes)).monospacedDigit()
            Button(action: reveal) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Afficher dans le Finder")
            .opacity(candidate.location == nil ? 0 : 1)
            .disabled(candidate.location == nil)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .padding(.vertical, 2)
    }
}

struct RiskBadge: View {
    let risk: Risk

    var body: some View {
        Text(risk.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(risk.color.opacity(0.15), in: Capsule())
            .foregroundStyle(risk.color)
    }
}

extension Risk {
    var color: Color {
        switch self {
        case .sansRisque: .green
        case .regenerable: .blue
        case .aVerifier: .orange
        }
    }
}

private struct ResultBanner: View {
    let result: ExecutionResult
    let openTrash: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "checkmark.circle").foregroundStyle(.green)
                Text(summary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if result.trashedBytes > 0 {
                    Button("Ouvrir la Corbeille", action: openTrash)
                }
            }
            let problems = result.refused + result.errors
            if !problems.isEmpty {
                DisclosureGroup("\(problems.count) éléments non traités") {
                    ForEach(problems, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var summary: String {
        var parts: [String] = []
        if result.trashedBytes > 0 {
            parts.append("\(ByteFormat.string(result.trashedBytes)) mis à la Corbeille. L'espace revient quand tu la vides.")
        }
        if result.deletedBytes > 0 {
            parts.append("\(ByteFormat.string(result.deletedBytes)) libérés par les commandes.")
        }
        return parts.isEmpty ? "Rien n'a été supprimé." : parts.joined(separator: " ")
    }
}
