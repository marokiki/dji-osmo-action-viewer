import Foundation

struct DetectedRecordingMetadata {
    var capturedAt: Date?
    var locationText: String?
}

enum VideoMetadataDetector {
    static func detect(from videoURL: URL) -> DetectedRecordingMetadata {
        var capturedAt: Date?

        if let resourceValues = try? videoURL.resourceValues(forKeys: [.creationDateKey]),
           let fileCreationDate = resourceValues.creationDate {
            capturedAt = fileCreationDate
        }

        return DetectedRecordingMetadata(
            capturedAt: capturedAt,
            locationText: nil
        )
    }
}
