import Foundation

struct FolderBookmarkStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "lastFolderBookmarkData") {
        self.defaults = defaults
        self.key = key
    }

    func save(folderURL: URL) throws {
        let data = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: key)
    }

    func restoreURL() throws -> (url: URL, isStale: Bool)? {
        guard let data = defaults.data(forKey: key) else { return nil }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }
}
