import AppKit
import AVFoundation
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle, recording, transcribing, cleaning, error(String), notice(String)
        var isBusy: Bool { self == .transcribing || self == .cleaning }
    }

    @Published var phase: Phase = .idle
    /// True when dictation continues without holding the trigger key (double-tap, menu, or pill click).
    @Published var handsFree = false
    @Published var levels: [Float] = Array(repeating: 0, count: 28)
    @Published var modelState: Transcriber.State = .unloaded
    @Published var downloadProgress: Double = 0
    @Published var lastText: String = ""
    @Published var lastOutcome: String = ""
    @Published var historyVersion = 0
    @Published var accessibilityTrusted = TextInserter.isTrusted
    @Published var microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var fnConflict = FnKeySystemSetting.conflicts

    let recorder = AudioRecorder()
    let transcriber = Transcriber()
    let hotkeys = HotkeyManager()
    let database: Database?
    private(set) lazy var overlay = OverlayController(state: self)

    private var targetApp: NSRunningApplication?
    private var context = AppContext(appName: nil, bundleID: nil, windowTitle: nil, category: .other)
    private var processingTask: Task<Void, Never>?
    private var startCueTask: Task<Void, Never>?
    private var maxLengthTask: Task<Void, Never>?
    private var defaultsObserver: AnyCancellable?
    private var permissionTimer: Timer?

    init() {
        SettingsKey.registerDefaults()
        do { database = try Database() } catch {
            NSLog("Quill: database unavailable: \(error)")
            database = nil
        }
    }

    func start() {
        recorder.onLevel = { [weak self] lvl in
            Task { @MainActor in
                guard let self else { return }
                self.levels.removeFirst()
                self.levels.append(lvl)
            }
        }
        Task {
            await transcriber.setStateHandler { s in Task { @MainActor [weak self] in self?.modelState = s } }
            await transcriber.setProgressHandler { p in Task { @MainActor [weak self] in self?.downloadProgress = p } }
        }
        hotkeys.isRecordingExternally = { [weak self] in self?.phase == .recording }
        hotkeys.onGesture = { [weak self] g in self?.handle(g) }
        applySettings()

        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applySettings()
                self?.loadModelIfNeeded()
            }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }

        Task { microphoneAuthorized = await AudioRecorder.requestPermission() }
        loadModelIfNeeded()
        overlay.refresh()
    }

    private func handle(_ g: HotkeyManager.Gesture) {
        switch g {
        case .holdBegan:
            startRecording(handsFree: false)
        case .holdEnded:
            stopAndProcess()
        case .holdAbandoned:
            if phase == .recording, !handsFree { cancel(silently: true) }
        case .handsFreeBegan:
            guard phase == .recording else { startRecording(handsFree: true); return }
            handsFree = true
            Sounds.play("Morse")
        case .handsFreeEnded:
            stopAndProcess()
        case .toggle:
            toggle()
        case .cancel:
            cancel()
        }
    }

    // MARK: Settings

    private var currentHotkey: HotkeyPreset?? = .none
    private var currentTrigger: TriggerKey?

    func applySettings() {
        let d = UserDefaults.standard
        let preset: HotkeyPreset? = d.bool(forKey: SettingsKey.hotkeyEnabled)
            ? (HotkeyPreset(rawValue: d.string(forKey: SettingsKey.hotkey) ?? "") ?? .optionSpace) : nil
        if currentHotkey == nil || currentHotkey! != preset { hotkeys.register(preset: preset); currentHotkey = .some(preset) }
        if d.triggerKey != currentTrigger { hotkeys.setTrigger(d.triggerKey); currentTrigger = d.triggerKey }
        let policy: NSApplication.ActivationPolicy = d.bool(forKey: SettingsKey.showInDock) ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        overlay.refresh()
    }

    func refreshPermissions() {
        let trusted = TextInserter.isTrusted
        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
            // Global key monitors only start delivering once trust is granted; re-arm them.
            currentTrigger = nil
            applySettings()
        }
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        fnConflict = FnKeySystemSetting.conflicts
        writeStatus()
    }

    /// Small diagnostics file (permissions, model, last insertion result) to make support easier.
    func writeStatus() {
        let status: [String: Any] = [
            "accessibilityTrusted": TextInserter.isTrusted,
            "postEventAccess": CGPreflightPostEventAccess(),
            "microphoneAuthorized": microphoneAuthorized,
            "modelState": "\(modelState)",
            "lastOutcome": lastOutcome,
            "updated": ISO8601DateFormatter().string(from: Date()),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: AppPaths.supportDirectory.appendingPathComponent("status.json"))
        }
    }

    var selectedModel: String { UserDefaults.standard.string(forKey: SettingsKey.whisperModel) ?? "openai_whisper-base" }

    func loadModelIfNeeded() {
        let model = selectedModel
        Task {
            if await transcriber.loadedModel == model { return }
            switch await transcriber.state {
            case .downloading, .loading: return
            default: break
            }
            // While a new model downloads, start with any model already on disk so dictation works now.
            if await !transcriber.hasModel, !Self.isDownloaded(model),
               let fallback = WhisperModelOption.all.map(\.id).first(where: Self.isDownloaded) {
                try? await transcriber.load(model: fallback)
            }
            try? await transcriber.load(model: model)
        }
    }

    static func isDownloaded(_ model: String) -> Bool {
        let dir = AppPaths.modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model)")
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("AudioEncoder.mlmodelc").path)
    }

    // MARK: Recording flow

    /// Menu item, pill click and the toggle hotkey all use hands-free mode.
    func toggle() {
        switch phase {
        case .recording: stopAndProcess()
        case .transcribing, .cleaning: break
        default: startRecording(handsFree: true)
        }
    }

    func startRecording(handsFree: Bool) {
        guard !phase.isBusy, phase != .recording else { return }
        guard microphoneAuthorized else {
            fail("Allow microphone access in System Settings → Privacy & Security → Microphone.")
            return
        }
        targetApp = NSWorkspace.shared.frontmostApplication
        context = AppContext.capture(targetApp)
        do {
            try recorder.start()
            levels = Array(repeating: 0, count: levels.count)
            self.handsFree = handsFree
            phase = .recording
            overlay.refresh()
            // Delay the start sound so fn shortcuts (fn+arrow, fn+F…) don't chirp.
            startCueTask?.cancel()
            startCueTask = Task {
                try? await Task.sleep(nanoseconds: handsFree ? 0 : 250_000_000)
                if !Task.isCancelled, self.phase == .recording { Sounds.start() }
            }
            maxLengthTask?.cancel()
            maxLengthTask = Task {
                try? await Task.sleep(nanoseconds: 20 * 60 * 1_000_000_000)
                if !Task.isCancelled, self.phase == .recording { self.stopAndProcess() }
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func cancel(silently: Bool = false) {
        startCueTask?.cancel()
        maxLengthTask?.cancel()
        _ = recorder.stop()
        processingTask?.cancel()
        hotkeys.reset()
        handsFree = false
        phase = .idle
        if !silently { Sounds.play("Funk") }
        overlay.refresh()
    }

    func stopAndProcess() {
        guard phase == .recording else { return }
        startCueTask?.cancel()
        maxLengthTask?.cancel()
        hotkeys.reset()
        handsFree = false
        Sounds.stop()
        phase = .transcribing
        overlay.refresh()

        let model = selectedModel
        let language = UserDefaults.standard.string(forKey: SettingsKey.language)
        let target = targetApp
        let context = self.context
        let vocabulary = database?.dictionary().map(\.term) ?? []
        processingTask = Task { [weak self] in
            guard let self else { return }
            // Keep recording briefly so the last word isn't clipped when the key is released.
            try? await Task.sleep(nanoseconds: 300_000_000)
            let samples = self.recorder.stop()
            let duration = Double(samples.count) / AudioRecorder.sampleRate
            guard !Task.isCancelled, duration >= 0.5 else { self.phase = .idle; self.overlay.refresh(); return }
            do {
                // Use whatever model is loaded; a newly selected one swaps in once it's ready.
                if await !self.transcriber.hasModel {
                    try await self.transcriber.load(model: model)
                }
                let raw = try await self.transcriber.transcribe(samples, language: language, vocabulary: vocabulary)
                try Task.checkCancellation()
                guard !raw.isEmpty else { self.notice("Didn't catch that — try again"); return }

                self.phase = .cleaning
                self.overlay.refresh()
                let cleaner = TextCleaner.fromDefaults(context: context, database: self.database)
                let (cleaned, provider) = await cleaner.clean(raw)
                try Task.checkCancellation()

                if let target, target != NSWorkspace.shared.frontmostApplication, !target.isTerminated {
                    target.activate()
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                let d = UserDefaults.standard
                let outcome = await TextInserter.insert(cleaned, mode: d.insertionMode, restoreClipboard: d.bool(forKey: SettingsKey.restoreClipboard))

                try? self.database?.insert(rawText: raw, cleanedText: cleaned, duration: duration,
                                           appName: context.appName, model: await self.transcriber.loadedModel ?? model,
                                           cleanupProvider: provider, outcome: outcome.rawValue)
                self.lastText = cleaned
                self.lastOutcome = outcome.rawValue
                self.historyVersion += 1
                if outcome == .clipboard && d.insertionMode != .clipboardOnly {
                    self.notice("Copied — press ⌘V. Allow Accessibility to auto-paste.")
                    self.accessibilityTrusted = TextInserter.isTrusted
                } else {
                    self.phase = .idle
                    self.overlay.refresh()
                }
            } catch is CancellationError {
                self.phase = .idle
                self.overlay.refresh()
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func notice(_ message: String) {
        phase = .notice(message)
        overlay.refresh()
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if case .notice = self.phase { self.phase = .idle; self.overlay.refresh() }
        }
    }

    private func fail(_ message: String) {
        Sounds.error()
        phase = .error(message)
        overlay.refresh()
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if case .error = self.phase { self.phase = .idle; self.overlay.refresh() }
        }
    }

    var menuBarSymbol: String {
        switch phase {
        case .recording: return "waveform"
        case .transcribing, .cleaning: return "ellipsis"
        case .error: return "exclamationmark.triangle"
        case .idle, .notice: return "pencil.tip"
        }
    }
}
