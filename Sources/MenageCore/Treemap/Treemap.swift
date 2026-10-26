import CoreGraphics

/// Carte en rectangles proportionnels, algorithme « squarified » (Bruls, Huizing, van Wijk, 2000) :
/// les rectangles restent proches du carré, donc lisibles et faciles à viser.
public enum Treemap {
    public struct Tile<ID: Hashable & Sendable>: Sendable {
        public var id: ID
        public var rect: CGRect
    }

    /// Un rectangle par élément de poids positif, d'aire proportionnelle à son poids, qui pavent `bounds`.
    public static func layout<ID: Hashable & Sendable>(_ items: [(id: ID, weight: Double)], in bounds: CGRect) -> [Tile<ID>] {
        let positive = items.filter { $0.weight > 0 }.sorted { $0.weight > $1.weight }
        let total = positive.reduce(0) { $0 + $1.weight }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }

        let scale = Double(bounds.width * bounds.height) / total
        let areas = positive.map { (id: $0.id, area: $0.weight * scale) }
        var tiles: [Tile<ID>] = []
        var remaining = bounds
        var row: [(id: ID, area: Double)] = []

        for item in areas {
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row + [item], side: side) <= worst(row, side: side) {
                row.append(item)
            } else {
                tiles += place(row, in: &remaining)
                row = [item]
            }
        }
        tiles += place(row, in: &remaining)
        return tiles
    }

    /// Le pire rapport largeur/hauteur d'une rangée posée le long d'un côté de longueur `side`.
    static func worst<ID>(_ row: [(id: ID, area: Double)], side: Double) -> Double {
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0, side > 0, let largest = row.map(\.area).max(), let smallest = row.map(\.area).min() else { return .infinity }
        let side2 = side * side
        let sum2 = sum * sum
        return max(side2 * largest / sum2, sum2 / (side2 * smallest))
    }

    /// Pose la rangée le long du côté court du rectangle restant, et le rétrécit d'autant.
    private static func place<ID>(_ row: [(id: ID, area: Double)], in remaining: inout CGRect) -> [Tile<ID>] {
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0 else { return [] }
        var tiles: [Tile<ID>] = []

        if remaining.width >= remaining.height {
            // Colonne à gauche.
            let width = CGFloat(sum / Double(remaining.height))
            var y = remaining.minY
            for (index, item) in row.enumerated() {
                let height = index == row.count - 1 ? remaining.maxY - y : CGFloat(item.area / Double(width))
                tiles.append(Tile(id: item.id, rect: CGRect(x: remaining.minX, y: y, width: width, height: height)))
                y += height
            }
            remaining = CGRect(x: remaining.minX + width, y: remaining.minY, width: max(remaining.width - width, 0), height: remaining.height)
        } else {
            // Rangée en haut.
            let height = CGFloat(sum / Double(remaining.width))
            var x = remaining.minX
            for (index, item) in row.enumerated() {
                let width = index == row.count - 1 ? remaining.maxX - x : CGFloat(item.area / Double(height))
                tiles.append(Tile(id: item.id, rect: CGRect(x: x, y: remaining.minY, width: width, height: height)))
                x += width
            }
            remaining = CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: max(remaining.height - height, 0))
        }
        return tiles
    }
}
