import Foundation

/// Owns the on-disk layout for imported book files and cover images.
///
/// Everything lives under `Application Support/Reader/`. The database stores
/// **relative** paths (`Books/<key>.epub`), and this type resolves them to
/// absolute URLs at runtime — so the library survives the OS relocating the app
/// container between launches, and the stored paths stay portable for sync.
struct BookStorage: Sendable {
    let root: URL

    init(fileManager: FileManager = .default) throws {
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        root = base.appendingPathComponent("Reader", isDirectory: true)
        try fileManager.createDirectory(at: booksDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: coversDir, withIntermediateDirectories: true)
    }

    var booksDir: URL { root.appendingPathComponent("Books", isDirectory: true) }
    var coversDir: URL { root.appendingPathComponent("Covers", isDirectory: true) }

    func absoluteURL(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    func bookRelativePath(key: String) -> String { "Books/\(key).epub" }
    func coverRelativePath(key: String) -> String { "Covers/\(key).png" }
}
