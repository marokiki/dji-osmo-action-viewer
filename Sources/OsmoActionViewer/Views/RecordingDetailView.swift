import SwiftUI

struct RecordingDetailView: View {
    @ObservedObject var model: ViewerModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let recording = model.selectedRecording {
                PlayerContainerView(player: model.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearTextInputFocusIfNeeded()
                    }

                playbackControls
                deleteControls
                exportControls
                markerControls(recording: recording)
                metadataEditors(recording: recording)
            } else {
                emptyState
            }
        }
        .padding()
        .alert("Delete selected video?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                model.deleteSelectedRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves the selected video file(s) to Trash.")
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            Button("<< 10s") { model.seek(seconds: -10) }
            Button("Play/Pause") { model.togglePlayPause() }
            Button("10s >>") { model.seek(seconds: 10) }
            Text("Shortcuts: ← / → / Space")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var exportControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clip Export")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Start (sec)", text: $model.exportStartSecondsText)
                    .frame(width: 100)
                Button("Set Start = Current") {
                    model.setExportStartFromCurrentTime()
                }

                TextField("End (sec)", text: $model.exportEndSecondsText)
                    .frame(width: 100)
                Button("Set End = Current") {
                    model.setExportEndFromCurrentTime()
                }

                Button(model.isExporting ? "Exporting..." : "Export") {
                    model.exportSelectedRange()
                }
                .disabled(model.isExporting)
            }
        }
    }

    private var deleteControls: some View {
        HStack {
            Button("Delete Video", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    private func markerControls(recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Current: \(model.formattedTime(model.currentPlaybackSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Mark Current") {
                    model.addMarkerAtCurrentTime()
                }
                TextField("Seconds", text: $model.markerInputSeconds)
                    .frame(width: 100)
                Button("Add Marker") {
                    model.addMarkerFromInput()
                }
            }

            let markers = model.markers(for: recording)
            if !markers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Markers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(markers.enumerated()), id: \.offset) { _, seconds in
                                HStack(spacing: 8) {
                                    Button(model.formattedTime(seconds)) {
                                        model.seekToMarker(seconds)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Delete") {
                                        model.removeMarker(seconds)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 120)

                    HStack(spacing: 8) {
                        TextField("Clip Length (sec)", text: $model.markerClipDurationSecondsText)
                            .frame(width: 130)
                        Button(model.isExporting ? "Exporting..." : "Export Marker Highlights") {
                            model.exportHighlightsFromMarkers()
                        }
                        .disabled(model.isExporting)
                    }
                }
            }
        }
    }

    private func metadataEditors(recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let capturedAt = model.effectiveCapturedAt(for: recording) {
                Text("Captured At: \(capturedAt.formatted(date: .numeric, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Captured At: unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(
                "Location",
                text: $model.editingLocationText,
                prompt: Text(model.effectiveLocationText(for: recording) ?? "Not set")
            )
            .textFieldStyle(.roundedBorder)
            .onChange(of: model.editingLocationText) { _ in
                model.persistEditingMetadata()
            }

            HStack(spacing: 8) {
                TextField(
                    "Google Maps URL",
                    text: $model.editingGoogleMapsURL,
                    prompt: Text(model.effectiveGoogleMapsURL(for: recording) ?? "Not set")
                )
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.editingGoogleMapsURL) { _ in
                    model.persistEditingMetadata()
                }

                if let urlString = model.validatedGoogleMapsURLString(),
                   let url = URL(string: urlString) {
                    Link("Open", destination: url)
                } else {
                    Button("Open") {}
                        .disabled(true)
                }
            }

            Text("Title")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Display Name", text: $model.editingTitle, prompt: Text(model.recordingDisplayName(recording)))
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.editingTitle) { _ in
                    model.persistEditingMetadata()
                }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No videos found")
                .font(.headline)
            Text("Select a folder that contains video files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
