import MenageCore
import SwiftUI

/// La fenêtre principale : nettoyage, carte du disque, gros fichiers, journal.
struct MainWindowView: View {
    static let windowID = "main"

    let cleaner: CleanerModel
    let map: DiskMapModel
    @AppStorage("main.tab") private var tab = Tab.nettoyage

    enum Tab: String, CaseIterable {
        case nettoyage = "Nettoyage"
        case carte = "Carte"
        case grosFichiers = "Gros fichiers"
        case journal = "Journal"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ménage").font(.title2.weight(.semibold))
                Spacer()
                Picker("Vue", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Divider()
            Group {
                switch tab {
                case .nettoyage: CleanerView(model: cleaner)
                case .carte: DiskMapView(model: map)
                case .grosFichiers: BigFilesView(model: map)
                case .journal: JournalView(entries: cleaner.journalEntries)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

/// Bandeau sous les onglets : où on en est, et l'action principale.
struct ActionBar<Actions: View>: View {
    let subtitle: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 12) {
            Text(subtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            actions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
