import SwiftUI


struct QuillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(state)
        } label: {
            Image(systemName: state.menuBarSymbol)
        }

        Window("Quill", id: "main") {
            MainView().environmentObject(state)
                .frame(minWidth: 860, minHeight: 580)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 700)
    }
}

extension AppState {
    static let shared = AppState()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppState.shared.start() }
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.triggerKey) private var trigger = TriggerKey.fn.rawValue
    @AppStorage(SettingsKey.overlayPosition) private var position = OverlayPosition.bottom.rawValue

    var body: some View {
        Button(state.phase == .recording ? "Finish Dictation" : "Start Dictation") { state.toggle() }
            .disabled(state.phase.isBusy)
        if state.phase == .recording || state.phase.isBusy {
            Button("Cancel") { state.cancel() }
        }
        if let key = TriggerKey(rawValue: trigger), key != .none {
            Text("Hold \(key.short) to talk · double-tap for hands-free")
        }
        Divider()
        Text(modelLine)
        if !state.lastText.isEmpty {
            Button("Copy Last Dictation") { TextInserter.setClipboard(state.lastText) }
        }
        Picker("Bar Position", selection: $position) {
            ForEach(OverlayPosition.allCases) { Text($0.label).tag($0.rawValue) }
        }
        Divider()
        Button("Open Quill") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("Quit Quill") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var modelLine: String {
        switch state.modelState {
        case .ready: return "Speech model ready"
        case .downloading: return "Downloading model… \(Int(state.downloadProgress * 100))%"
        case .loading: return "Preparing model…"
        case .unloaded: return "Model not loaded"
        case .failed(let m): return "Model error: \(m)"
        }
    }
}
