import AppKit

@MainActor
func clearTextInputFocusIfNeeded() {
    guard let responder = NSApp.keyWindow?.firstResponder, responder is NSTextInputClient else {
        return
    }
    NSApp.keyWindow?.makeFirstResponder(nil)
}
