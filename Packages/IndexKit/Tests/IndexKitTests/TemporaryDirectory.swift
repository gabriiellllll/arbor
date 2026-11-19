import Foundation

/// A uniquely named directory under the system temporary directory, deleted on `remove()`.
/// Tests never touch anything outside it.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexKitTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ path: String, size: Int = 0, modified: Date? = nil) throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(count: size).write(to: file)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        }
        return file
    }

    @discardableResult
    func directory(_ path: String) throws -> URL {
        let dir = url.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
