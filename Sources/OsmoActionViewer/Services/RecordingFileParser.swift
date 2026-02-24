import Foundation

struct ParsedRecordingName {
    let timestampText: String
    let clipNumber: String
    let segmentNumber: Int

    var groupKey: String { "\(timestampText)_\(clipNumber)" }
}

enum RecordingFileParser {
    private static let regex = try! NSRegularExpression(
        pattern: #"^DJI_(\d{14})_(\d{4})_D(?:_(\d{3}))?\.MP4$"#,
        options: [.caseInsensitive]
    )

    static func parse(fileName: String) -> ParsedRecordingName? {
        let range = NSRange(location: 0, length: (fileName as NSString).length)
        guard let match = regex.firstMatch(in: fileName, range: range) else { return nil }

        guard
            let tsRange = Range(match.range(at: 1), in: fileName),
            let clipRange = Range(match.range(at: 2), in: fileName)
        else {
            return nil
        }

        let timestamp = String(fileName[tsRange])
        let clip = String(fileName[clipRange])

        let segment: Int
        if let segmentRange = Range(match.range(at: 3), in: fileName) {
            segment = Int(fileName[segmentRange]) ?? 0
        } else {
            segment = 0
        }

        return ParsedRecordingName(timestampText: timestamp, clipNumber: clip, segmentNumber: segment)
    }
}
