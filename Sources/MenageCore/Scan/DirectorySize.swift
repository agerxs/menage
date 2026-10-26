import Foundation

/// Place réellement occupée sur le disque (`totalFileAllocatedSize`), pas la taille apparente :
/// un fichier creux comme `Docker.raw` annonce 494 Go mais n'en occupe que 6.
public enum DirectorySize {
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Taille d'un fichier ou d'un dossier entier. Les liens symboliques ne sont pas suivis.
    public static func of(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { return 0 }
        guard values.isDirectory == true else { return allocated(values) }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += allocated(values)
        }
        return total
    }

    private static func allocated(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
