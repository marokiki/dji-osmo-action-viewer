import SwiftUI

struct RecordingListView: View {
    @ObservedObject var model: ViewerModel
    @State private var showBulkDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Open Recording Folder") {
                model.chooseFolder()
            }

            folderInfoView

            if !model.recordingSections.isEmpty {
                sectionControlsView
            }

            recordingsListView

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .alert("Delete selected videos?", isPresented: $showBulkDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                model.deleteCheckedRecordings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected video files will be moved to Trash.")
        }
    }

    private var folderInfoView: some View {
        Group {
            if let folderURL = model.folderURL {
                Text(folderURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("No folder selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sectionControlsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Select All") {
                    model.selectAllInCurrentSection()
                }
                .disabled((model.selectedSection?.recordings.isEmpty ?? true))

                Button("Clear") {
                    model.clearCheckedInCurrentSection()
                }
                .disabled(model.checkedRecordingIDs.isEmpty)
            }

            HStack(spacing: 8) {
                Button("Delete Selected", role: .destructive) {
                    showBulkDeleteConfirmation = true
                }
                .disabled(model.checkedRecordingIDs.isEmpty)

                TextField("Clip sec", text: $model.markerClipDurationSecondsText)
                    .frame(width: 90)

                Button(model.isExporting ? "Exporting..." : "Export Highlights") {
                    model.exportHighlightsFromCheckedRecordings()
                }
                .disabled(model.isExporting || model.checkedRecordingIDs.isEmpty)
            }

            Picker(
                "Section",
                selection: Binding(
                    get: { model.selectedSectionName ?? "" },
                    set: { model.selectSection(name: $0) }
                )
            ) {
                ForEach(model.recordingSections) { section in
                    Text(section.name).tag(section.name)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var recordingsListView: some View {
        List {
            ForEach(model.selectedSection?.recordings ?? []) { recording in
                rowContent(for: recording)
                .listRowBackground(
                    model.selectedRecordingID == recording.id ? Color.accentColor.opacity(0.2) : Color.clear
                )
            }
        }
    }

    private func rowContent(for recording: Recording) -> some View {
        HStack {
            Button {
                model.toggleChecked(recordingID: recording.id)
            } label: {
                Image(systemName: model.isChecked(recordingID: recording.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(model.isChecked(recordingID: recording.id) ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.recordingDisplayName(recording))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Text(model.capturedAtText(for: recording))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            clearTextInputFocusIfNeeded()
            model.play(recordingID: recording.id)
        }
    }
}
