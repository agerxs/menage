import MenageCore
import SwiftUI

/// Les enfants du dossier courant en rectangles proportionnels. Clic : entrer dans un dossier,
/// ou sélectionner un fichier.
struct TreemapView: View {
    let node: DiskNode
    let selectedPath: String?
    let onActivate: (DiskNode) -> Void
    @State private var hoveredPath: String?

    /// Au-delà, les rectangles sont trop petits pour être vus : inutile de les calculer.
    private static let maxTiles = 300

    var body: some View {
        GeometryReader { geometry in
            let tiles = layout(in: CGRect(origin: .zero, size: geometry.size))
            Canvas { context, _ in
                for tile in tiles {
                    draw(tile, in: &context)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoveredPath = tiles.first { $0.rect.contains(location) }?.id
                case .ended: hoveredPath = nil
                }
            }
            .onTapGesture { location in
                guard let path = tiles.first(where: { $0.rect.contains(location) })?.id,
                      let child = node.children.first(where: { $0.path == path }) else { return }
                onActivate(child)
            }
            .overlay(alignment: .bottomLeading) { hoverLabel }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func layout(in bounds: CGRect) -> [Treemap.Tile<String>] {
        let items = node.children.prefix(Self.maxTiles).map { (id: $0.path, weight: Double($0.bytes)) }
        return Treemap.layout(Array(items), in: bounds)
    }

    private func draw(_ tile: Treemap.Tile<String>, in context: inout GraphicsContext) {
        guard let child = node.children.first(where: { $0.path == tile.id }) else { return }
        let rect = tile.rect.insetBy(dx: 1, dy: 1)
        guard rect.width > 0, rect.height > 0 else { return }
        let shape = Path(roundedRect: rect, cornerRadius: min(4, rect.width / 4, rect.height / 4))
        let category = FileCategory.of(child)
        let emphasized = tile.id == hoveredPath || tile.id == selectedPath
        context.fill(shape, with: .color(category.color.opacity(child.isOthers ? 0.35 : (emphasized ? 0.95 : 0.75))))
        if emphasized {
            context.stroke(shape, with: .color(.primary), lineWidth: 2)
        }
        guard rect.width > 56, rect.height > 30 else { return }
        let label = Text("\(child.name)\n").font(.caption.weight(.semibold))
            + Text(ByteFormat.string(child.bytes)).font(.caption2)
        context.draw(
            label.foregroundStyle(.white),
            in: rect.insetBy(dx: 6, dy: 4)
        )
    }

    @ViewBuilder
    private var hoverLabel: some View {
        if let hoveredPath, let child = node.children.first(where: { $0.path == hoveredPath }) {
            HStack(spacing: 6) {
                Text(child.name).fontWeight(.medium)
                Text(ByteFormat.string(child.bytes)).monospacedDigit()
                if child.canOpen {
                    Text("· clic pour ouvrir").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(8)
            .allowsHitTesting(false)
        }
    }
}

extension FileCategory {
    var color: Color {
        switch self {
        case .code: .blue
        case .medias: .purple
        case .apps: .teal
        case .archives: .orange
        case .caches: .pink
        case .systeme: .gray
        case .autres: .indigo
        }
    }
}
