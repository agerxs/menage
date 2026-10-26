import MenageCore
import SwiftUI

/// L'onglet Carte : le dossier perso en rectangles, navigable, avec la liste à côté.
struct DiskMapView: View {
    @Bindable var model: DiskMapModel
    @State private var pendingTrash: DiskNode?

    var body: some View {
        VStack(spacing: 0) {
            ActionBar(subtitle: subtitle) {
                Button(model.root == nil ? "Analyser le dossier perso" : "Relancer l'analyse") {
                    Task { await model.scan() }
                }
                .disabled(model.phase == .scanning)
            }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            pendingTrash.map { "Mettre « \($0.name) » à la Corbeille ?" } ?? "",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { node in
            Button("Mettre à la Corbeille (\(ByteFormat.string(node.bytes)))", role: .destructive) {
                model.trash(node.path, bytes: node.bytes)
            }
        } message: { node in
            Text("\(node.path)\n\nRécupérable depuis le Finder tant que la Corbeille n'est pas vidée.")
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .idle:
            return "Mesure tout le dossier perso. Environ une minute ; rien n'est modifié."
        case .scanning:
            return "Analyse : \(model.progressFiles.formatted(.number.locale(Locale(identifier: "fr_FR")))) fichiers, \(ByteFormat.string(model.progressBytes))"
        case .ready:
            let files = model.fileCount.formatted(.number.locale(Locale(identifier: "fr_FR")))
            return "\(ByteFormat.string(model.root?.bytes ?? 0)) dans \(files) fichiers, analysés en \(Int(model.scanDuration)) s"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label("Carte du disque", systemImage: "square.grid.3x3.square")
            } description: {
                Text("Chaque rectangle est un dossier ou un fichier, à la taille de la place qu'il prend. Clique pour entrer dans un dossier.")
            } actions: {
                Button("Analyser le dossier perso") { Task { await model.scan() } }
                    .buttonStyle(.borderedProminent)
            }
        case .scanning:
            VStack(spacing: 12) {
                ProgressView()
                Text(subtitle).foregroundStyle(.secondary).monospacedDigit()
            }
        case .ready:
            if let current = model.current {
                VStack(alignment: .leading, spacing: 10) {
                    if !model.unreadable.isEmpty { unreadableBanner }
                    if let error = model.lastError {
                        Text(error).font(.callout).foregroundStyle(.orange)
                    }
                    breadcrumb
                    HStack(spacing: 12) {
                        TreemapView(node: current, selectedPath: model.selectedPath) { model.open($0) }
                            .frame(minWidth: 360)
                        ChildList(node: current, model: model, pendingTrash: $pendingTrash)
                            .frame(width: 300)
                    }
                    legend
                }
                .padding(16)
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button { model.goUp() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .disabled(model.breadcrumb.count <= 1)
                .help("Dossier parent")
            ForEach(Array(model.breadcrumb.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Button(index == 0 ? "Dossier perso" : node.name) { model.goTo(node) }
                    .buttonStyle(.borderless)
                    .fontWeight(index == model.breadcrumb.count - 1 ? .semibold : .regular)
                    .lineLimit(1)
            }
            Spacer()
            if let current = model.current {
                Text(ByteFormat.string(current.bytes)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private var unreadableBanner: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "lock")
            Text("\(model.unreadable.count) dossiers illisibles : macOS les réserve aux apps qui ont l'accès complet au disque. Leur taille n'est pas comptée.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Ouvrir les réglages", action: model.openFullDiskAccessSettings)
        }
        .font(.callout)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(FileCategory.allCases, id: \.self) { category in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(category.color.opacity(0.75)).frame(width: 10, height: 10)
                    Text(category.label)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Les mêmes éléments que la carte, en liste : plus précis pour les petits, et accessible au clavier.
private struct ChildList: View {
    let node: DiskNode
    let model: DiskMapModel
    @Binding var pendingTrash: DiskNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(node.children.prefix(200), id: \.path, selection: Binding(
                get: { model.selectedPath },
                set: { model.selectedPath = $0 }
            )) { child in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(FileCategory.of(child).color.opacity(0.75))
                        .frame(width: 8, height: 8)
                    Text(child.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(ByteFormat.string(child.bytes)).monospacedDigit().foregroundStyle(.secondary)
                    if child.canOpen {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.open(child) }
                .onTapGesture { model.selectedPath = child.path }
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let selected = model.selected {
                SelectionPanel(node: selected, model: model, pendingTrash: $pendingTrash)
            } else {
                Text("Double-clic pour ouvrir un dossier, clic pour le sélectionner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SelectionPanel: View {
    let node: DiskNode
    let model: DiskMapModel
    @Binding var pendingTrash: DiskNode?

    var body: some View {
        let refusal = model.trashRefusal(for: node.path)
        VStack(alignment: .leading, spacing: 6) {
            Text(node.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            Text(node.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack {
                Text(ByteFormat.string(node.bytes)).monospacedDigit()
                Text(FileCategory.of(node).label).foregroundStyle(.secondary)
            }
            .font(.caption)
            HStack {
                Button("Afficher dans le Finder") { model.reveal(node.path) }
                    .disabled(node.isOthers)
                Button("Corbeille…") { pendingTrash = node }
                    .disabled(refusal != nil)
                    .help(refusal.map { "Impossible : \($0)" } ?? "Mettre à la Corbeille")
            }
            .controlSize(.small)
            if let refusal {
                Label(refusal, systemImage: "lock").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
