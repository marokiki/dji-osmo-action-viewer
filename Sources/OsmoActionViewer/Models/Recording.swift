import Foundation

struct Recording: Identifiable, Hashable {
    let key: String
    let sectionName: String
    let timestampText: String
    let clipNumber: String
    let segmentURLs: [URL]
    let fallbackDisplayName: String?

    var id: String { key }
}
