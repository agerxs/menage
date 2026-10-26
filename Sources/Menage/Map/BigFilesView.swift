import MenageCore
import SwiftUI

/// L'onglet Gros fichiers : tous les fichiers au-dessus d'un seuil, triables.
struct BigFilesView: View {
    @Bindable var model: DiskMapModel
    @AppStorage("bigFiles.minimumMB") private var minimumMB = 500
    @State private var sortOrder = [KeyPathComparator(\BigFile.bytes, order: .reverse)]
    @State private var selection: BigFile.ID?
    @State private var pendingTrash: BigFile?

    private static let thresholds = [100, 500, 1000, 5000]
    private static let dateFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
        .locale(Locale(identifier: "fr_FR"))

    private var files: [BigFile] {
        model.bigFiles
            .filter { $0.bytes >= Int64(minimumMB) * 1_000_000 }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            ActionBar(subtitle: subtitle) {
                Picker("Seuil", selection: $minimumMB) {
                    ForEach(Self.thresholds, id: \.self) { mb in
                        Text(mb >= 1000 ? "Plus de \(mb / 1000) Go" : "Plus de \(mb) Mo").tag(mb)
                    }
                }
                .fixedSize()
                Button(model.root == nil ? "Analyser le dossier perso" : "Relancer l'analyse") {
                    Task { await model.scan() }
                }
                .disabled(model.isScanning)
            }
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            pendingTrash.map { "Mettre « \($0.name) » à la Corbeille ?" } ?? "",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { file in
            Button("Mettre à la Corbeille (\(ByteFormat.string(file.bytes)))", role: .destructive) {
                model.trash(file.path, bytes: file.bytes)
            }
        } message: { file in
            Text("\(file.path)\n\nRécupérable depuis le Finder tant que la Corbeille n'est pas vidée.")
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .idle: "Les gros fichiers viennent de l'analyse de la carte."
        case .scanning: "Analyse en cours…"
        case .ready: "\(files.count) fichiers · \(ByteFormat.string(files.reduce(0) { $0 + $1.bytes }))"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label("Pas encore analysé", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Une seule analyse sert à la carte et à cette liste. Environ une minute.")
            } actions: {
                Button("Analyser le dossier perso") { Task { await model.scan() } }
                    .buttonStyle(.borderedProminent)
            }
        case .scanning:
            ProgressView()
        case .ready:
            VStack(spacing: 0) {
                Table(files, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Nom", value: \.name) { file in
                        Text(file.name).lineLimit(1).truncationMode(.middle).help(file.path)
                    }
                    TableColumn("Dossier", value: \.folder) { file in
                        Text(file.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    TableColumn("Taille", value: \.bytes) { file in
                        Text(ByteFormat.string(file.bytes)).monospacedDigit()
                    }
                    .width(80)
                    TableColumn("Modifié", value: \.modifiedForSort) { file in
                        Text(file.modified?.formatted(Self.dateFormat) ?? "").foregroundStyle(.secondary)
                    }
                    .width(100)
                }
                .contextMenu(forSelectionType: BigFile.ID.self) { ids in
                    if let file = file(ids.first) {
                        Button("Afficher dans le Finder") { model.reveal(file.path) }
                        Button("Mettre à la Corbeille…") { pendingTrash = file }
                            .disabled(model.trashRefusal(for: file.path) != nil)
                    }
                } primaryAction: { ids in
                    if let file = file(ids.first) { model.reveal(file.path) }
                }
                Divider()
                selectionBar
            }
        }
    }

    private var selectionBar: some View {
        HStack {
            if let file = file(selection) {
                let refusal = model.trashRefusal(for: file.path)
                if let refusal {
                    Label("Protégé : \(refusal)", systemImage: "lock").foregroundStyle(.secondary).lineLimit(1)
                } else if let error = model.lastError {
                    Text(error).foregroundStyle(.orange)
                }
                Spacer()
                Button("Afficher dans le Finder") { model.reveal(file.path) }
                Button("Mettre à la Corbeille…") { pendingTrash = file }
                    .disabled(refusal != nil)
            } else {
                Text("Sélectionne un fichier. Double-clic pour l'afficher dans le Finder.").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func file(_ id: BigFile.ID?) -> BigFile? {
        guard let id else { return nil }
        return model.bigFiles.first { $0.id == id }
    }
}

extension BigFile {
    /// Pour trier par date : un fichier sans date passe en dernier.
    var modifiedForSort: Date { modified ?? .distantPast }
}
