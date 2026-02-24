import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var model = ViewerModel()
    @State private var keyMonitor: Any?
    @State private var didRestoreLastFolder = false

    var body: some View {
        HStack(spacing: 0) {
            RecordingListView(model: model)
                .frame(width: 440)

            Divider()

            RecordingDetailView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1180, minHeight: 700)
        .contentShape(Rectangle())
        .gesture(
            TapGesture().onEnded {
                clearTextInputFocusIfNeeded()
            },
            including: .gesture
        )
        .onAppear {
            if !didRestoreLastFolder {
                didRestoreLastFolder = true
                model.restoreLastOpenedFolderIfAvailable()
            }
            installKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeKeyMonitorIfNeeded()
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let responder = event.window?.firstResponder, responder is NSTextInputClient {
                return event
            }

            switch event.keyCode {
            case 123:
                model.seek(seconds: -10)
                return nil
            case 124:
                model.seek(seconds: 10)
                return nil
            case 49:
                model.togglePlayPause()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitorIfNeeded() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}
