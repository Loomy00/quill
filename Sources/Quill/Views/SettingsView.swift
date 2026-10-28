import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    @AppStorage(SettingsKey.triggerKey) private var trigger = TriggerKey.fn.rawValue
    @AppStorage(SettingsKey.hotkey) private var hotkey = HotkeyPreset.optionSpace.rawValue
    @AppStorage(SettingsKey.hotkeyEnabled) private var hotkeyEnabled = true
    @AppStorage(SettingsKey.overlayPosition) private var position = OverlayPosition.bottom.rawValue
    @AppStorage(SettingsKey.overlayAlwaysVisible) private var alwaysVisible = true
    @AppStorage(SettingsKey.showInDock) private var showInDock = false
    @AppStorage(SettingsKey.playSounds) private var playSounds = true
    @AppStorage(SettingsKey.whisperModel) private var whisperModel = "openai_whisper-large-v3-v20240930_turbo_632MB"
    @AppStorage(SettingsKey.language) private var language = "auto"
    @AppStorage(SettingsKey.cleanupProvider) private var provider = CleanupProvider.basic.rawValue
    @AppStorage(SettingsKey.anthropicModel) private var anthropicModel = "claude-opus-5-5"
    @AppStorage(SettingsKey.localLLMURL) private var localURL = ""
    @AppStorage(SettingsKey.localLLMModel) private var localModel = ""
    @AppStorage(SettingsKey.customInstructions) private var customInstructions = ""
    @AppStorage(SettingsKey.spokenPunctuation) private var spokenPunctuation = true
    @AppStorage(SettingsKey.autoLists) private var autoLists = true
    @AppStorage(SettingsKey.insertionMode) private var insertionMode = InsertionMode.paste.rawValue
    @AppStorage(SettingsKey.restoreClipboard) private var restoreClipboard = true

    @State private var apiKey = Keychain.get("anthropicAPIKey") ?? ""
    @State private var testOutput = ""
    @State private var testing = false

    private let languages: [(String, String)] = [
        ("auto", "Detect automatically"), ("en", "English"), ("de", "German"), ("fr", "French"), ("es", "Spanish"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("pl", "Polish"), ("ja", "Japanese"), ("zh", "Chinese"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            PageHeader(eyebrow: "Settings", title: "Preferences")
            SetupBanners()

            Group_("Keys") {
                Row("Dictation key", note: "Hold to talk. Double-tap for hands-free, tap again to finish.") {
                    menu($trigger, TriggerKey.allCases.map { ($0.rawValue, $0.label) })
                }
                Row("Toggle shortcut", note: hotkeyEnabled ? "Starts and stops hands-free dictation." : nil) {
                    HStack(spacing: 10) {
                        if hotkeyEnabled { menu($hotkey, HotkeyPreset.allCases.map { ($0.rawValue, $0.label) }) }
                        Toggle("", isOn: $hotkeyEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
            }

            Group_("The bar") {
                HStack(alignment: .top, spacing: 28) {
                    PositionPicker(selection: $position)
                    VStack(spacing: 0) {
                        Row("Always visible", note: "Otherwise it only appears while you talk.") { toggle($alwaysVisible) }
                        Row("Show in Dock") { toggle($showInDock) }
                        Row("Sounds") { toggle($playSounds) }
                    }
                }
                .padding(.vertical, 12)
                Text("Or just drag the bar to any edge of the screen.").font(Theme.body(12)).foregroundStyle(Theme.faint)
                    .padding(.bottom, 4)
            }

            Group_("Hearing") {
                Row("Speech model", note: "Runs on this Mac. Larger is more accurate.") {
                    menu($whisperModel, WhisperModelOption.all.map { ($0.id, $0.label) })
                }
                Row("Language") { menu($language, languages) }
            }

            Group_("Writing") {
                Row("Clean-up", note: providerNote) {
                    menu($provider, CleanupProvider.allCases.map { ($0.rawValue, $0.label) })
                }
                if provider == CleanupProvider.anthropic.rawValue {
                    Row("API key") {
                        SecureField("", text: $apiKey, prompt: Text("sk-ant-…").foregroundColor(Theme.faint))
                            .textFieldStyle(.plain).font(Theme.mono(12)).frame(width: 240)
                            .onChange(of: apiKey) { Keychain.set(apiKey, for: "anthropicAPIKey") }
                    }
                    Row("Model") { TextField("", text: $anthropicModel).textFieldStyle(.plain).font(Theme.mono(12)).frame(width: 240) }
                }
                if provider == CleanupProvider.openAICompatible.rawValue {
                    Row("Endpoint") { TextField("", text: $localURL).textFieldStyle(.plain).font(Theme.mono(12)).frame(width: 300) }
                    Row("Model") { TextField("", text: $localModel).textFieldStyle(.plain).font(Theme.mono(12)).frame(width: 240) }
                }
                Row("Spoken punctuation", note: "“comma”, “period”, “question mark”") { toggle($spokenPunctuation) }
                Row("Lists", note: "“first… second…” becomes a numbered list") { toggle($autoLists) }
                Row("House rules", note: "Anything Quill should always do.") {
                    TextField("", text: $customInstructions, prompt: Text("e.g. British spelling").foregroundColor(Theme.faint), axis: .vertical)
                        .textFieldStyle(.plain).font(Theme.body(12.5)).lineLimit(1...3).frame(width: 260)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button(testing ? "Writing…" : "Try it on a messy sample") { runTest() }
                        .buttonStyle(QuillButtonStyle()).disabled(testing)
                    if !testOutput.isEmpty {
                        Text(testOutput).font(Theme.body(13)).foregroundStyle(Theme.text.opacity(0.85))
                            .textSelection(.enabled).lineSpacing(3)
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.accent.opacity(0.5)).frame(width: 2) }
                    }
                }
                .padding(.vertical, 14)
            }

            Group_("Pasting") {
                Row("Insert text by") { menu($insertionMode, InsertionMode.allCases.map { ($0.rawValue, $0.label) }) }
                Row("Put my clipboard back afterwards") { toggle($restoreClipboard) }
            }

            Group_("Data") {
                Row("Stored in", note: AppPaths.supportDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory]) }
                        .buttonStyle(QuillButtonStyle())
                }
            }
        }
    }

    private var providerNote: String {
        switch CleanupProvider(rawValue: provider) ?? .basic {
        case .apple: return AppleCleaner.unavailableReason.map { "\($0) Using simple rules instead." } ?? "Apple Intelligence, on this Mac. Nothing leaves it."
        case .anthropic: return "Sends the transcript text (not audio) to Anthropic. Key stays in your Keychain."
        case .openAICompatible: return "Your own local model via Ollama or LM Studio."
        case .basic: return "Simple rules: fillers, punctuation, lists. Works offline."
        case .off: return "Exactly what Whisper heard."
        }
    }

    private func menu(_ binding: Binding<String>, _ options: [(String, String)]) -> some View {
        Picker("", selection: binding) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }

    private func runTest() {
        Keychain.set(apiKey, for: "anthropicAPIKey")
        testing = true
        testOutput = ""
        Task {
            let sample = "um so for the launch we need to uh first finish the landing page second record the demo video and third email the beta list. let's meet at 3 no wait at 4 on friday"
            let ctx = AppContext(appName: nil, bundleID: nil, windowTitle: nil, category: .other)
            let (out, _) = await TextCleaner.fromDefaults(context: ctx, database: state.database).clean(sample)
            testOutput = out
            testing = false
        }
    }
}

/// A titled settings group separated by hairlines.
private struct Group_<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(title)
            VStack(alignment: .leading, spacing: 0) { content }
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }
}

private struct Row<Control: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var control: Control
    init(_ title: String, note: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title; self.note = note; self.control = control()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.body(13)).foregroundStyle(Theme.text)
                if let note { Text(note).font(Theme.body(11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// Miniature screen: click an edge to put the bar there.
private struct PositionPicker: View {
    @Binding var selection: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Theme.bg)
            RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line)
            Scanlines(opacity: 0.03).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(spacing: 0) {
                Rectangle().fill(Theme.surfaceHi).frame(height: 6)
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(Theme.surfaceHi).frame(width: 80, height: 8).padding(.bottom, 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            slot(.top).frame(maxHeight: .infinity, alignment: .top).padding(.top, 9)
            slot(.bottom).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 13)
            slot(.left).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 3)
            slot(.right).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 3)
        }
        .frame(width: 176, height: 110)
    }

    private func slot(_ p: OverlayPosition) -> some View {
        let on = selection == p.rawValue
        return Button {
            selection = p.rawValue
            UserDefaults.standard.set(0.5, forKey: SettingsKey.overlayOffset)
        } label: {
            Capsule()
                .fill(on ? Theme.accent : Theme.faint.opacity(0.6))
                .shadow(color: on ? Theme.accent.opacity(0.8) : .clear, radius: 4)
                .frame(width: p.isVertical ? 5 : 26, height: p.isVertical ? 26 : 5)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(p.label)
    }
}
