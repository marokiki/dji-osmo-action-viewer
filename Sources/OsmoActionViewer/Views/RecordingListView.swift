import SwiftUI

struct RecordingListView: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Open Recording Folder") {
                model.chooseFolder()
            }

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

            if !model.recordingSections.isEmpty {
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

            List {
                ForEach(model.selectedSection?.recordings ?? []) { recording in
                    Button {
                        clearTextInputFocusIfNeeded()
                        model.play(recordingID: recording.id)
                    } label: {
                        HStack {
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
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        model.selectedRecordingID == recording.id ? Color.accentColor.opacity(0.2) : Color.clear
                    )
                }
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }
}
