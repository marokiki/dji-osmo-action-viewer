import Foundation

struct RecordingMetadata: Codable {
    var title: String = ""
    var note: String = ""
    var markers: [Double] = []
    var locationText: String = ""
    var googleMapsURL: String = ""
}

struct MetadataStore: Codable {
    var entries: [String: RecordingMetadata] = [:]
}
