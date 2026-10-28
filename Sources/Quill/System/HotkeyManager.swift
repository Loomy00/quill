import AppKit
import Carbon.HIToolbox

enum HotkeyPreset: String, CaseIterable, Identifiable {
    case optionSpace, controlOptionSpace, commandShiftSpace, controlSpace, f5
    var id: String { rawValue }
    var label: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        case .commandShiftSpace: return "⇧⌘ Space"
        case .controlSpace: return "⌃ Space"
        case .f5: return "F5"
        }
    }
    var keyCode: UInt32 {
        switch self {
        case .f5: return UInt32(kVK_F5)
        default: return UInt32(kVK_Space)
        }
    }
    var modifiers: UInt32 {
        switch self {
        case .optionSpace: return UInt32(optionKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .commandShiftSpace: return UInt32(cmdKey | shiftKey)
        case .controlSpace: return UInt32(controlKey)
        case .f5: return 0
        }
    }
}

/// Global shortcuts:
///  - a toggle hotkey registered with Carbon (works without extra permissions), and
///  - a trigger key (fn by default): hold to talk, double-tap for hands-free, tap again to stop.
///    Observing modifier keys globally needs Accessibility permission.
final class HotkeyManager {
    /// Gesture events delivered on the main thread.
    enum Gesture { case holdBegan, holdEnded, holdAbandoned, handsFreeBegan, handsFreeEnded, toggle, cancel }
    var onGesture: ((Gesture) -> Void)?
    /// Asked on each trigger press so a tap can stop dictation started elsewhere (menu, overlay).
    var isRecordingExternally: (() -> Bool)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var monitors: [Any] = []

    private enum TriggerState { case idle, holding, awaitingSecondTap, handsFree, swallowRelease }
    private var trigger: TriggerKey = .none
    private var triggerState: TriggerState = .idle
    private var keyIsDown = false
    private var pressedAt = Date.distantPast
    private var tapTimer: Timer?

    /// A press shorter than this is a tap; longer is push-to-talk.
    private let tapThreshold: TimeInterval = 0.28
    /// Max gap between the two taps of a double-tap.
    private let doubleTapWindow: TimeInterval = 0.35

    private static let signature: OSType = 0x4443_5441 // 'DCTA'

    // MARK: Toggle hotkey

    func register(preset: HotkeyPreset?) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        guard let preset else { return }
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { mgr.onGesture?(.toggle) }
                return noErr
            }, 1, &spec, selfPtr, &handlerRef)
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(preset.keyCode, preset.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { NSLog("Quill: failed to register hotkey \(preset.label) (\(status))") }
    }

    // MARK: Trigger key

    func setTrigger(_ key: TriggerKey) {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        trigger = key
        reset()
        guard key != .none else { return }
        let flags: (NSEvent) -> Void = { [weak self] e in self?.handleFlags(e) }
        let keyDown: (NSEvent) -> Void = { [weak self] e in self?.otherKeyPressed(e) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyDown) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { keyDown($0); return $0 }) { monitors.append(m) }
    }

    /// Called when dictation ends for another reason (menu, overlay button, error).
    func reset() {
        tapTimer?.invalidate()
        tapTimer = nil
        triggerState = .idle
    }

    private func matches(_ e: NSEvent) -> (isKey: Bool, down: Bool) {
        switch trigger {
        case .fn:
            // 63 = fn on built-in keyboards; 179 = 🌐 globe on some external keyboards.
            return (e.keyCode == 63 || e.keyCode == 179, e.modifierFlags.contains(.function))
        case .rightOption:
            return (e.keyCode == UInt16(kVK_RightOption), e.modifierFlags.contains(.option))
        case .rightCommand:
            return (e.keyCode == UInt16(kVK_RightCommand), e.modifierFlags.contains(.command))
        case .none:
            return (false, false)
        }
    }

    private func handleFlags(_ e: NSEvent) {
        let (isKey, down) = matches(e)
        guard isKey, down != keyIsDown else { return }
        keyIsDown = down
        down ? pressed() : released()
    }

    private func pressed() {
        pressedAt = Date()
        switch triggerState {
        case .idle:
            if isRecordingExternally?() == true {
                // A tap stops dictation that was started from the menu or overlay.
                triggerState = .swallowRelease
                onGesture?(.handsFreeEnded)
            } else {
                triggerState = .holding
                onGesture?(.holdBegan) // start immediately so no words are lost
            }
        case .awaitingSecondTap:
            tapTimer?.invalidate()
            triggerState = .swallowRelease
            onGesture?(.handsFreeBegan)
            handsFreePending = true
        case .handsFree:
            triggerState = .swallowRelease
            onGesture?(.handsFreeEnded)
        case .holding, .swallowRelease:
            break
        }
    }

    private var handsFreePending = false

    private func released() {
        switch triggerState {
        case .holding:
            if Date().timeIntervalSince(pressedAt) >= tapThreshold {
                triggerState = .idle
                onGesture?(.holdEnded)
            } else {
                // Short tap: wait to see whether a second tap follows.
                triggerState = .awaitingSecondTap
                tapTimer = Timer.scheduledTimer(withTimeInterval: doubleTapWindow, repeats: false) { [weak self] _ in
                    guard let self, self.triggerState == .awaitingSecondTap else { return }
                    self.triggerState = .idle
                    self.onGesture?(.holdAbandoned)
                }
            }
        case .swallowRelease:
            triggerState = handsFreePending ? .handsFree : .idle
            handsFreePending = false
        default:
            break
        }
    }

    /// fn + another key is a system shortcut (fn+arrows, fn+F-keys, fn+E…), not dictation.
    private func otherKeyPressed(_ e: NSEvent) {
        if e.keyCode == UInt16(kVK_Escape), triggerState == .handsFree || isRecordingExternally?() == true {
            reset()
            onGesture?(.cancel)
            return
        }
        guard keyIsDown, triggerState == .holding else { return }
        triggerState = .idle
        onGesture?(.holdAbandoned)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        monitors.forEach { NSEvent.removeMonitor($0) }
    }
}

/// Reads the system "Press 🌐 key to…" setting so the app can warn when fn also opens the emoji picker.
enum FnKeySystemSetting {
    /// 0 = Do Nothing, 1 = Change Input Source, 2 = Show Emoji & Symbols, 3 = Start Dictation.
    static var usage: Int? {
        UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
    }
    static var conflicts: Bool { usage != 0 }
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
