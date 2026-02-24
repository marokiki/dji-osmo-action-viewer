import Foundation
import AVFoundation

struct DetectedRecordingMetadata {
    var capturedAt: Date?
    var locationText: String?
}

enum VideoMetadataDetector {
    static func detect(from videoURL: URL) -> DetectedRecordingMetadata {
        var capturedAt: Date?
        var locationText: String?

        if let resourceValues = try? videoURL.resourceValues(forKeys: [.creationDateKey]),
           let fileCreationDate = resourceValues.creationDate {
            capturedAt = fileCreationDate
        }

        let asset = AVURLAsset(url: videoURL)

        if let metadataCreatedAt = creationDate(from: asset) {
            capturedAt = metadataCreatedAt
        }

        if let quickTimeLocation = quickTimeLocation(from: asset), !quickTimeLocation.isEmpty {
            locationText = quickTimeLocation
        }

        return DetectedRecordingMetadata(
            capturedAt: capturedAt,
            locationText: locationText
        )
    }

    private static func creationDate(from asset: AVURLAsset) -> Date? {
        if let item = asset.commonMetadata.first(where: { $0.commonKey?.rawValue == "creationDate" }) {
            if let date = item.dateValue {
                return date
            }

            if let text = item.stringValue {
                let iso = ISO8601DateFormatter()
                if let parsed = iso.date(from: text) {
                    return parsed
                }
            }
        }

        return nil
    }

    private static func quickTimeLocation(from asset: AVURLAsset) -> String? {
        let quickTimeItems = asset.metadata(forFormat: .quickTimeMetadata)
        if let item = quickTimeItems.first(where: { metadataItem in
            guard let key = metadataItem.key as? String else { return false }
            return key == "com.apple.quicktime.location.ISO6709"
        }) {
            return item.stringValue
        }

        return nil
    }
}
