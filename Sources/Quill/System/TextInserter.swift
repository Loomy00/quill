import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Inserts text into the focused field of the frontmost app.
enum TextInserter {
    enum Outcome: String { case accessibility, paste, clipboard, failed }

    /// Accessibility trust covers both reading the focused field and posting the ⌘V keystroke.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
    }

    @MainActor
    static func insert(_ text: String, mode: InsertionMode, restoreClipboard: Bool) async -> Outcome {
        guard !text.isEmpty else { return .failed }
        switch mode {
        case .clipboardOnly:
            setClipboard(text)
            return .clipboard
        case .paste:
            return await paste(text, restore: restoreClipboard)
        case .accessibility:
            if insertViaAccessibility(text) { return .accessibility }
            return await paste(text, restore: restoreClipboard)
        }
    }

    /// Writes into the focused element's selected-text range. Web and Electron views often report
    /// success without changing anything, so the value is re-read to confirm the edit landed.
    static func insertViaAccessibility(_ text: String) -> Bool {
        guard isTrusted, let element = focusedElement() else { return false }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        let before = stringValue(element)
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else { return false }
        guard let after = stringValue(element) else { return false }
        return after != before && after.contains(text)
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    private static func stringValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    @MainActor
    static func paste(_ text: String, restore: Bool) async -> Outcome {
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = restore ? (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } : []

        setClipboard(text)
        guard isTrusted else { return .clipboard }

        // Let the dictation key be fully released so its modifier isn't merged into ⌘V.
        await waitForModifiersReleased()
        let changeCount = pb.changeCount
        sendCommandV()

        if restore {
            try? await Task.sleep(nanoseconds: 700_000_000)
            // Only restore if nothing else touched the clipboard meanwhile.
            if pb.changeCount == changeCount {
                pb.clearContents()
                if !saved.isEmpty { pb.writeObjects(saved) }
            }
        }
        return .paste
    }

    static func setClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private static func waitForModifiersReleased() async {
        for _ in 0..<20 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let held: CGEventFlags = [.maskSecondaryFn, .maskAlternate, .maskCommand, .maskControl, .maskShift]
            if flags.intersection(held).isEmpty { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private static func sendCommandV() {
        // A private source keeps physically-held keys (fn, ⌥) out of the synthesized event.
        let src = CGEventSource(stateID: .privateState)
        let v = CGKeyCode(kVK_ANSI_V)
        let cmd = CGKeyCode(kVK_Command)
        let events: [(CGKeyCode, Bool, CGEventFlags)] = [
            (cmd, true, .maskCommand), (v, true, .maskCommand), (v, false, .maskCommand), (cmd, false, []),
        ]
        for (key, down, flags) in events {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
            usleep(8_000)
        }
    }
}
