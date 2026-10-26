import MenageCore
import SwiftUI

/// Dernier regard avant d'agir : chaque chemin, chaque commande, le total.
struct ConfirmationSheet: View {
    let model: CleanerModel
    @Binding var isPresented: Bool

    private var trashPaths: [String] {
        model.selectedCandidates.flatMap { candidate -> [String] in
            guard case .trash(let urls) = candidate.action else { return [] }
            return urls.map { abbreviate($0.path) }
        }
    }

    private var commands: [String] {
        model.selectedCandidates.compactMap { candidate in
            guard case .command(let command) = candidate.action else { return nil }
            return command.display
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Confirmer le ménage").font(.title3.weight(.semibold))
            Text("\(ByteFormat.string(model.selectedBytes)) au total.")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !trashPaths.isEmpty {
                        group(
                            title: "\(trashPaths.count) éléments à la Corbeille",
                            note: "Récupérables depuis le Finder tant que la Corbeille n'est pas vidée.",
                            lines: trashPaths,
                            tint: .secondary
                        )
                    }
                    if !commands.isEmpty {
                        group(
                            title: "\(commands.count) commandes",
                            note: "Suppression définitive : ces outils ne passent pas par la Corbeille.",
                            lines: commands,
                            tint: .orange
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(commands.isEmpty ? "Mettre à la Corbeille" : "Confirmer") {
                    isPresented = false
                    Task { await model.execute() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func group(title: String, note: String, lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(note).font(.caption).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
