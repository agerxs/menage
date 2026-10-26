import MenageCore
import SwiftUI

struct JournalView: View {
    let entries: [JournalEntry]

    private static let dateFormat: Date.FormatStyle = .dateTime
        .day().month(.wide).year().hour().minute()
        .locale(Locale(identifier: "fr_FR"))

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "Journal vide",
                systemImage: "list.bullet.rectangle",
                description: Text("Chaque ménage y sera noté : ce qui est parti, quand, et combien de place il a libéré.")
            )
        } else {
            List(entries) { entry in
                DisclosureGroup {
                    ForEach(entry.items, id: \.self) { item in
                        Text(item).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    ForEach(entry.errors, id: \.self) { error in
                        Text(error).font(.caption.monospaced()).foregroundStyle(.orange)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(entry.date.formatted(Self.dateFormat))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.method == .corbeille ? "Corbeille" : "Commande")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ByteFormat.string(entry.bytes))
                            .monospacedDigit()
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}
