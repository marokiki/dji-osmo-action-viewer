import Foundation
import AVKit
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class ViewerModel: ObservableObject {
    private let supportedVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    @Published var folderURL: URL?
    @Published var recordings: [Recording] = []
    @Published var recordingSections: [RecordingSection] = []
    @Published var selectedSectionName: String?
    @Published var selectedRecordingID: String?
    @Published var player = AVPlayer()
    @Published var errorMessage: String?
    @Published var editingTitle: String = ""
    @Published var editingLocationText: String = ""
    @Published var editingGoogleMapsURL: String = ""
    @Published var markerInputSeconds: String = ""
    @Published var currentPlaybackSeconds: Double = 0
    @Published var exportStartSecondsText: String = ""
    @Published var exportEndSecondsText: String = ""
    @Published var isExporting: Bool = false

    private var currentItemCancellable: AnyCancellable?
    private var timeObserverToken: Any?
    private var scopedFolderURL: URL?
    private var metadataByRecordingKey: [String: RecordingMetadata] = [:]
    private var detectedMetadataByRecordingKey: [String: DetectedRecordingMetadata] = [:]

    private let metadataStoreService = MetadataStoreService()
    private let folderBookmarkStore = FolderBookmarkStore()

    private let parseInputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    var selectedRecording: Recording? {
        guard let selectedRecordingID else { return nil }
        return recordings.first(where: { $0.id == selectedRecordingID })
    }

    var selectedSection: RecordingSection? {
        guard let selectedSectionName else { return nil }
        return recordingSections.first(where: { $0.name == selectedSectionName })
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Recording Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        switchScopedFolderAccess(to: folder)
        folderURL = folder

        do {
            try folderBookmarkStore.save(folderURL: folder)
        } catch {
            errorMessage = "Failed to save last opened folder: \(error.localizedDescription)"
        }

        loadRecordings(from: folder)
    }

    func restoreLastOpenedFolderIfAvailable() {
        do {
            guard let restored = try folderBookmarkStore.restoreURL() else { return }

            switchScopedFolderAccess(to: restored.url)
            folderURL = restored.url

            if restored.isStale {
                try folderBookmarkStore.save(folderURL: restored.url)
            }

            loadRecordings(from: restored.url)
        } catch {
            errorMessage = "Failed to restore last opened folder: \(error.localizedDescription)"
        }
    }

    func loadRecordings(from folder: URL) {
        metadataByRecordingKey = metadataStoreService.load(from: folder)
        detectedMetadataByRecordingKey = [:]

        var grouped: [String: (sectionName: String, values: [(ParsedRecordingName, URL)], fallbackDisplayName: String?)] = [:]
        let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let item = enumerator?.nextObject() as? URL {
            guard supportedVideoExtensions.contains(item.pathExtension.lowercased()) else { continue }
            let isRegularFile = (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegularFile else { continue }

            let name = item.lastPathComponent
            let sectionName = sectionName(for: item, rootFolder: folder)
            if let parsed = RecordingFileParser.parse(fileName: name) {
                let groupedKey = "\(sectionName)|\(parsed.groupKey)"
                if grouped[groupedKey] == nil {
                    grouped[groupedKey] = (sectionName: sectionName, values: [], fallbackDisplayName: nil)
                }
                grouped[groupedKey]?.values.append((parsed, item))
            } else {
                let relativePath = item.path.replacingOccurrences(of: folder.path + "/", with: "")
                let groupedKey = "\(sectionName)|RAW|\(relativePath)"
                let fallbackDisplayName = item.deletingPathExtension().lastPathComponent
                let synthetic = ParsedRecordingName(
                    timestampText: "00000000000000",
                    clipNumber: "0000",
                    segmentNumber: 0
                )
                grouped[groupedKey] = (
                    sectionName: sectionName,
                    values: [(synthetic, item)],
                    fallbackDisplayName: fallbackDisplayName
                )
            }
        }

        let builtRecordings = grouped
            .map { groupedKey, group -> Recording in
                let values = group.values
                let sectionName = group.sectionName
                let sorted = values.sorted { $0.0.segmentNumber < $1.0.segmentNumber }
                let first = sorted[0].0
                return Recording(
                    key: groupedKey,
                    sectionName: sectionName,
                    timestampText: first.timestampText,
                    clipNumber: first.clipNumber,
                    segmentURLs: sorted.map { $0.1 },
                    fallbackDisplayName: group.fallbackDisplayName
                )
            }
            .sorted { lhs, rhs in
                if lhs.sectionName != rhs.sectionName {
                    return lhs.sectionName < rhs.sectionName
                }
                if lhs.timestampText == rhs.timestampText {
                    return lhs.clipNumber < rhs.clipNumber
                }
                return lhs.timestampText < rhs.timestampText
            }

        let sections = Dictionary(grouping: builtRecordings, by: { $0.sectionName })
            .map { name, recordings in
                RecordingSection(name: name, recordings: recordings)
            }
            .sorted { $0.name < $1.name }

        recordings = builtRecordings
        recordingSections = sections
        selectedSectionName = sections.first?.name

        if let first = sections.first?.recordings.first {
            play(recordingID: first.id)
        } else {
            clearSelection()
            player.replaceCurrentItem(with: nil)
            errorMessage = "No video files were found."
        }
    }

    func selectSection(name: String) {
        guard selectedSectionName != name else { return }
        selectedSectionName = name

        guard let section = recordingSections.first(where: { $0.name == name }) else { return }
        if let selectedRecordingID,
           section.recordings.contains(where: { $0.id == selectedRecordingID }) {
            return
        }
        if let first = section.recordings.first {
            play(recordingID: first.id)
        }
    }

    private func sectionName(for fileURL: URL, rootFolder: URL) -> String {
        let filePath = fileURL.deletingLastPathComponent().path
        let rootPath = rootFolder.path

        guard filePath.hasPrefix(rootPath) else { return "Uncategorized" }

        let suffix = filePath.dropFirst(rootPath.count)
        let normalized = suffix.hasPrefix("/") ? suffix.dropFirst() : suffix[...]
        let relativeComponents = normalized.split(separator: "/").map(String.init)
        if let first = relativeComponents.first, !first.isEmpty {
            return first
        }
        return "Root"
    }

    func play(recordingID: String) {
        guard let recording = recordings.first(where: { $0.id == recordingID }) else { return }

        selectedRecordingID = recordingID
        let metadata = metadataByRecordingKey[recording.key] ?? RecordingMetadata()
        let detected = detectedMetadata(for: recording)

        editingTitle = metadata.title
        editingLocationText = metadata.locationText.isEmpty ? (detected.locationText ?? "") : metadata.locationText
        editingGoogleMapsURL = metadata.googleMapsURL

        markerInputSeconds = ""
        currentPlaybackSeconds = 0
        exportStartSecondsText = ""
        exportEndSecondsText = ""

        let item = PlayerItemFactory.makeItem(for: recording)

        currentItemCancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .failed {
                    self.errorMessage = "Cannot play: \(recordingDisplayName(recording)) (\(item.error?.localizedDescription ?? "Unknown error"))"
                } else if status == .readyToPlay {
                    self.errorMessage = nil
                }
            }

        player.replaceCurrentItem(with: item)
        startPlaybackTimeObserver()
        player.play()
    }

    func seek(seconds: Double) {
        guard player.currentItem != nil else { return }

        let current = CMTimeGetSeconds(player.currentTime())
        let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)

        let unclamped = current + seconds
        let clamped: Double
        if duration.isFinite && duration > 0 {
            clamped = min(max(0, unclamped), duration)
        } else {
            clamped = max(0, unclamped)
        }

        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    func togglePlayPause() {
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
    }

    func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    func recordingDisplayName(_ recording: Recording) -> String {
        let customTitle = metadataByRecordingKey[recording.key]?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customTitle.isEmpty {
            return customTitle
        }

        if let fallbackDisplayName = recording.fallbackDisplayName, !fallbackDisplayName.isEmpty {
            return fallbackDisplayName
        }

        if let date = parseInputDateFormatter.date(from: recording.timestampText) {
            return "\(displayDateFormatter.string(from: date)) clip\(recording.clipNumber)"
        }
        return "DJI_\(recording.timestampText)_\(recording.clipNumber)"
    }

    func persistEditingMetadata() {
        guard let recording = selectedRecording else { return }
        var meta = metadataByRecordingKey[recording.key] ?? RecordingMetadata()
        meta.title = editingTitle
        meta.locationText = editingLocationText
        meta.googleMapsURL = editingGoogleMapsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        metadataByRecordingKey[recording.key] = meta
        saveMetadataIfPossible()
    }

    func effectiveCapturedAt(for recording: Recording) -> Date? {
        return detectedMetadata(for: recording).capturedAt ?? parseInputDateFormatter.date(from: recording.timestampText)
    }

    func capturedAtText(for recording: Recording) -> String {
        guard let capturedAt = effectiveCapturedAt(for: recording) else {
            return "Unknown"
        }
        return displayDateFormatter.string(from: capturedAt)
    }

    func effectiveLocationText(for recording: Recording) -> String? {
        let meta = metadataByRecordingKey[recording.key] ?? RecordingMetadata()
        if !meta.locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return meta.locationText
        }
        return detectedMetadata(for: recording).locationText
    }

    func effectiveGoogleMapsURL(for recording: Recording) -> String? {
        let meta = metadataByRecordingKey[recording.key] ?? RecordingMetadata()
        let saved = meta.googleMapsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? nil : saved
    }

    func validatedGoogleMapsURLString() -> String? {
        let raw = editingGoogleMapsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw) != nil ? raw : nil
        }

        let prefixed = "https://\(raw)"
        return URL(string: prefixed) != nil ? prefixed : nil
    }

    func markers(for recording: Recording) -> [Double] {
        metadataByRecordingKey[recording.key]?.markers.sorted() ?? []
    }

    func addMarkerAtCurrentTime() {
        addMarker(seconds: currentPlaybackSeconds)
    }

    func addMarkerFromInput() {
        guard let seconds = Double(markerInputSeconds.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Marker seconds must be a valid number."
            return
        }
        addMarker(seconds: seconds)
        markerInputSeconds = ""
    }

    func seekToMarker(_ seconds: Double) {
        guard player.currentItem != nil else { return }
        let clamped = max(0, seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    func removeMarker(_ seconds: Double) {
        guard let recording = selectedRecording else { return }
        var meta = metadataByRecordingKey[recording.key] ?? RecordingMetadata()
        meta.markers.removeAll(where: { abs($0 - seconds) < 0.05 })
        metadataByRecordingKey[recording.key] = meta
        saveMetadataIfPossible()
    }

    func setExportStartFromCurrentTime() {
        exportStartSecondsText = String(format: "%.1f", max(0, currentPlaybackSeconds))
    }

    func setExportEndFromCurrentTime() {
        exportEndSecondsText = String(format: "%.1f", max(0, currentPlaybackSeconds))
    }

    func exportSelectedRange() {
        guard let recording = selectedRecording else { return }
        guard !isExporting else { return }

        guard let start = Double(exportStartSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let end = Double(exportEndSecondsText.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            errorMessage = "Please enter numeric start/end seconds."
            return
        }

        guard start >= 0, end > start else {
            errorMessage = "End seconds must be greater than start seconds."
            return
        }

        let asset = PlayerItemFactory.makeAsset(for: recording)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        if durationSeconds.isFinite {
            guard end <= durationSeconds else {
                errorMessage = "End seconds exceeds duration. Max: \(String(format: "%.1f", durationSeconds)) sec"
                return
            }
        }

        let panel = NSSavePanel()
        panel.title = "Export Clipped Video"
        panel.nameFieldStringValue = defaultExportFileName(for: recording, start: start, end: end)
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            errorMessage = "Failed to initialize exporter."
            return
        }

        let outputFileType: AVFileType = exporter.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        exporter.outputURL = outputURL
        exporter.outputFileType = outputFileType
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )

        isExporting = true
        errorMessage = nil
        exporter.exportAsynchronously { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isExporting = false

                switch exporter.status {
                case .completed:
                    self.errorMessage = nil
                case .failed:
                    self.errorMessage = "Export failed: \(exporter.error?.localizedDescription ?? "Unknown error")"
                case .cancelled:
                    self.errorMessage = "Export was cancelled."
                default:
                    self.errorMessage = "Export did not complete."
                }
            }
        }
    }

    private func addMarker(seconds: Double) {
        guard let recording = selectedRecording else { return }
        let rounded = (max(0, seconds) * 10).rounded() / 10

        var meta = metadataByRecordingKey[recording.key] ?? RecordingMetadata()
        if meta.markers.contains(where: { abs($0 - rounded) < 0.05 }) {
            return
        }

        meta.markers.append(rounded)
        meta.markers.sort()
        metadataByRecordingKey[recording.key] = meta
        errorMessage = nil
        saveMetadataIfPossible()
    }

    private func clearSelection() {
        selectedRecordingID = nil
        selectedSectionName = nil
        editingTitle = ""
        editingLocationText = ""
        editingGoogleMapsURL = ""
        exportStartSecondsText = ""
        exportEndSecondsText = ""
        currentPlaybackSeconds = 0
    }

    private func defaultExportFileName(for recording: Recording, start: Double, end: Double) -> String {
        let safeTitle = recordingDisplayName(recording)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(safeTitle)_\(Int(start))-\(Int(end)).mp4"
    }

    private func startPlaybackTimeObserver() {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentPlaybackSeconds = CMTimeGetSeconds(time)
            }
        }
    }

    private func switchScopedFolderAccess(to folder: URL) {
        if let scopedFolderURL {
            scopedFolderURL.stopAccessingSecurityScopedResource()
            self.scopedFolderURL = nil
        }

        if folder.startAccessingSecurityScopedResource() {
            scopedFolderURL = folder
        }
    }

    private func saveMetadataIfPossible() {
        guard let folderURL else { return }
        do {
            try metadataStoreService.save(entries: metadataByRecordingKey, to: folderURL)
        } catch {
            errorMessage = "Failed to save metadata: \(error.localizedDescription)"
        }
    }

    private func detectedMetadata(for recording: Recording) -> DetectedRecordingMetadata {
        if let cached = detectedMetadataByRecordingKey[recording.key] {
            return cached
        }

        let detected = VideoMetadataDetector.detect(from: recording.segmentURLs[0])
        detectedMetadataByRecordingKey[recording.key] = detected
        return detected
    }
}
