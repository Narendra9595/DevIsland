import Foundation
import Observation

/// Files dropped on the island. Remembered across launches until removed.
@MainActor
@Observable
final class FileShelf {
    private(set) var files: [URL] = []
    private let defaults: UserDefaults
    private static let key = "shelfFiles"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        files = (defaults.stringArray(forKey: Self.key) ?? [])
            .map { URL(filePath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !files.contains(url) {
            files.append(url)
        }
        save()
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
        save()
    }

    func clear() {
        files.removeAll()
        save()
    }

    private func save() {
        defaults.set(files.map(\.path), forKey: Self.key)
    }
}
