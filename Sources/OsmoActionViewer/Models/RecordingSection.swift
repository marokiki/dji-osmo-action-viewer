import Foundation

struct RecordingSection: Identifiable {
    let name: String
    let recordings: [Recording]

    var id: String { name }
}
