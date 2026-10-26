import CoreGraphics
import Foundation
import Testing
@testable import MenageCore

@Suite struct TreemapTests {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)

    @Test func areasAreProportionalAndTileTheBounds() {
        let weights: [Double] = [500, 300, 120, 60, 10, 6, 3, 1]
        let tiles = Treemap.layout(weights.enumerated().map { (id: $0.offset, weight: $0.element) }, in: bounds)
        let total = weights.reduce(0, +)

        #expect(tiles.count == weights.count)
        for tile in tiles {
            let expected = weights[tile.id] / total * Double(bounds.width * bounds.height)
            #expect(abs(Double(tile.rect.width * tile.rect.height) - expected) / expected < 0.001, "tuile \(tile.id)")
            #expect(bounds.insetBy(dx: -0.001, dy: -0.001).contains(tile.rect))
        }
        let covered = tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        #expect(abs(covered - Double(bounds.width * bounds.height)) < 1)
    }

    @Test func tilesNeverOverlap() {
        let tiles = Treemap.layout((0..<40).map { (id: $0, weight: Double(40 - $0) * 1.7) }, in: bounds)
        for (i, a) in tiles.enumerated() {
            for b in tiles[(i + 1)...] {
                let overlap = a.rect.intersection(b.rect)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01, "\(a.id) et \(b.id)")
            }
        }
    }

    @Test func equalWeightsInASquareGiveSquares() {
        let tiles = Treemap.layout((0..<4).map { (id: $0, weight: 1.0) }, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        for tile in tiles {
            #expect(abs(tile.rect.width - 50) < 0.001)
            #expect(abs(tile.rect.height - 50) < 0.001)
        }
    }

    @Test func emptyOrZeroWeightsGiveNothing() {
        #expect(Treemap.layout([(id: 1, weight: 0.0)], in: bounds).isEmpty)
        #expect(Treemap.layout([(id: 1, weight: 5.0)], in: .zero).isEmpty)
        #expect(Treemap.layout([(id: 1, weight: 5.0), (id: 2, weight: 0)], in: bounds).map(\.id) == [1])
    }
}

@Suite struct DiskScannerTests {
    /// home/
    ///   devapps/app/video.mp4      3 Mo  (gardé : ≥ 1 Mo)
    ///   devapps/app/notes.txt      petit (fondu dans « autres »)
    ///   Downloads/film.mov         2 Mo  (gros fichier au seuil de 1,5 Mo)
    ///   tiny/a                     petit dossier entier (fondu dans « autres » de home)
    ///   lien -> devapps            ignoré
    func makeTree() throws -> (Fixture, DiskScanResult) {
        let fixture = try Fixture()
        try fixture.file("home/devapps/app/video.mp4", bytes: 3 * megabyte)
        try fixture.file("home/devapps/app/notes.txt", bytes: 2000)
        try fixture.file("home/Downloads/film.mov", bytes: 2 * megabyte)
        try fixture.file("home/tiny/a", bytes: 500)
        try FileManager.default.createSymbolicLink(at: fixture.url("home/lien"), withDestinationURL: fixture.url("home/devapps"))
        let scanner = DiskScanner(minimumNodeBytes: 1_000_000, maxDepth: 12, bigFileThreshold: 1_500_000)
        return (fixture, scanner.scan(fixture.url("home")))
    }

    @Test func sizesAddUpAndSmallItemsAreGrouped() throws {
        let (_, result) = try makeTree()
        let root = result.root
        #expect(root.children.map(\.name).prefix(2) == ["devapps", "Downloads"])
        #expect(root.bytes == root.children.reduce(0) { $0 + $1.bytes })
        #expect(root.bytes >= 5 * Int64(megabyte))
        #expect(root.children.last?.isOthers == true)
        #expect(root.children.last?.name == "1 petit élément")
        #expect(result.fileCount == 4)

        let app = try #require(root.node(atPath: root.path + "/devapps/app"))
        #expect(app.children.map(\.name) == ["video.mp4", "1 petit élément"])
    }

    @Test func symlinksAreNotFollowed() throws {
        let (_, result) = try makeTree()
        #expect(!result.root.children.contains { $0.name == "lien" })
        #expect(result.root.bytes < 6 * Int64(megabyte))
    }

    @Test func bigFilesAreCollectedLargestFirst() throws {
        let (_, result) = try makeTree()
        #expect(result.bigFiles.map(\.name) == ["video.mp4", "film.mov"])
        #expect(result.bigFiles[0].modified != nil)
    }

    @Test func detailIsDroppedBelowMaxDepth() throws {
        let fixture = try Fixture()
        try fixture.file("root/a/b/c/big.bin", bytes: 2 * megabyte)
        let result = DiskScanner(maxDepth: 2).scan(fixture.url("root"))
        let b = try #require(result.root.node(atPath: result.root.path + "/a/b"))
        #expect(b.children.isEmpty)
        #expect(b.bytes >= 2 * Int64(megabyte))
    }

    @Test func unreadableFoldersAreReported() throws {
        let fixture = try Fixture()
        try fixture.file("root/locked/secret", bytes: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.url("root/locked").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.url("root/locked").path) }
        let result = DiskScanner().scan(fixture.url("root"))
        #expect(result.unreadable.map { ($0 as NSString).lastPathComponent } == ["locked"])
    }

    /// Des instantanés de sauvegarde à liens physiques : la place n'est occupée qu'une fois.
    @Test func hardLinksAreCountedOnce() throws {
        let fixture = try Fixture()
        let original = try fixture.file("root/snap1/data.bin", bytes: 3 * megabyte)
        for snapshot in ["snap2", "snap3", "snap4"] {
            try fixture.directory("root/\(snapshot)")
            try FileManager.default.linkItem(at: original, to: fixture.url("root/\(snapshot)/data.bin"))
        }
        let result = DiskScanner().scan(fixture.url("root"))
        #expect(result.root.bytes < 4 * Int64(megabyte))
        #expect(result.root.bytes >= 3 * Int64(megabyte))
        #expect(result.fileCount == 4)
    }

    /// Un gros fichier sous la coupe de profondeur n'a pas de nœud : ses octets sont retirés du plus
    /// profond de ses parents présents, et de tous les autres.
    @Test func removingAFileBelowTheCutFixesSizesAnyway() throws {
        let fixture = try Fixture()
        try fixture.file("root/a/b/c/big.bin", bytes: 2 * megabyte)
        try fixture.file("root/a/keep.bin", bytes: 2 * megabyte)
        let result = DiskScanner(maxDepth: 2).scan(fixture.url("root"))
        let root = result.root
        let hidden = root.path + "/a/b/c/big.bin"
        #expect(root.node(atPath: hidden) == nil)
        // Tout ce que contient b/ est ce fichier : sa taille est celle de b/.
        let bytes = try #require(root.node(atPath: root.path + "/a/b")).bytes

        let updated = root.removing(path: hidden, bytes: bytes)
        #expect(updated.bytes == root.bytes - bytes)
        #expect(updated.node(atPath: root.path + "/a/b")?.bytes == 0)
        #expect(updated.node(atPath: root.path + "/a")?.bytes == root.node(atPath: root.path + "/a")!.bytes - bytes)
    }

    @Test func removingANodeFixesParentSizes() throws {
        let (_, result) = try makeTree()
        let root = result.root
        let videoPath = root.path + "/devapps/app/video.mp4"
        let video = try #require(root.node(atPath: videoPath))
        let updated = root.removing(path: videoPath)

        #expect(updated.node(atPath: videoPath) == nil)
        #expect(updated.bytes == root.bytes - video.bytes)
        #expect(updated.node(atPath: root.path + "/devapps")?.bytes == root.node(atPath: root.path + "/devapps")!.bytes - video.bytes)
        #expect(root.ancestry(of: videoPath).map(\.name) == ["home", "devapps", "app", "video.mp4"])
    }
}

@Suite struct FileCategoryTests {
    func node(_ path: String, _ kind: DiskNode.Kind = .directory) -> DiskNode {
        DiskNode(path: path, name: (path as NSString).lastPathComponent, kind: kind, bytes: 1)
    }

    @Test func categories() {
        #expect(FileCategory.of(node("/Users/a/Library/Caches/Firefox")) == .caches)
        #expect(FileCategory.of(node("/Users/a/Library/Developer/Xcode/DerivedData/Runner-x")) == .caches)
        #expect(FileCategory.of(node("/Users/a/devapps/my-app/node_modules")) == .code)
        #expect(FileCategory.of(node("/Users/a/Downloads/film.mp4", .file)) == .medias)
        #expect(FileCategory.of(node("/Users/a/Downloads/DaVinci.dmg", .file)) == .archives)
        #expect(FileCategory.of(node("/Applications/Xcode.app")) == .apps)
        #expect(FileCategory.of(node("/Users/a/Library/Android")) == .systeme)
        #expect(FileCategory.of(node("/Users/a/Movies")) == .medias)
        #expect(FileCategory.of(DiskNode(path: "/x/…", name: "3 petits éléments", kind: .others(count: 3), bytes: 1)) == .autres)
    }
}
