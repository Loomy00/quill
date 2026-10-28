import Foundation

enum CleanupProvider: String, CaseIterable, Identifiable {
    case off, basic, apple, anthropic, openAICompatible
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off (raw Whisper output)"
        case .basic: return "Basic (local rules)"
        case .apple: return "Apple Intelligence (on-device)"
        case .anthropic: return "Claude (Anthropic API)"
        case .openAICompatible: return "Local LLM (Ollama / LM Studio)"
        }
    }
}

enum InsertionMode: String, CaseIterable, Identifiable {
    case paste, accessibility, clipboardOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .paste: return "Auto-paste (recommended)"
        case .accessibility: return "Accessibility API, then paste"
        case .clipboardOnly: return "Copy to clipboard only"
        }
    }
}

/// Key held for push-to-talk, double-tapped for hands-free.
enum TriggerKey: String, CaseIterable, Identifiable {
    case fn, rightOption, rightCommand, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fn: return "fn (🌐)"
        case .rightOption: return "Right ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .none: return "None"
        }
    }
    var short: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "right ⌥"
        case .rightCommand: return "right ⌘"
        case .none: return ""
        }
    }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case bottom, top, left, right
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottom: return "Bottom (above Dock)"
        case .top: return "Top (below menu bar)"
        case .left: return "Left edge"
        case .right: return "Right edge"
        }
    }
    var isVertical: Bool { self == .left || self == .right }
}

struct WhisperModelOption: Identifiable, Hashable {
    let id: String
    let label: String
    static let all: [WhisperModelOption] = [
        .init(id: "openai_whisper-tiny", label: "Tiny · fastest, ~75 MB"),
        .init(id: "openai_whisper-base", label: "Base · fast, ~145 MB"),
        .init(id: "openai_whisper-small", label: "Small · accurate, ~480 MB"),
        .init(id: "openai_whisper-large-v3-v20240930_turbo_632MB", label: "Large v3 Turbo · most accurate (recommended), ~630 MB"),
    ]
}

/// UserDefaults keys and defaults shared by @AppStorage and non-view code.
enum SettingsKey {
    static let whisperModel = "whisperModel"
    static let language = "language"
    static let cleanupProvider = "cleanupProvider"
    static let anthropicModel = "anthropicModel"
    static let localLLMURL = "localLLMURL"
    static let localLLMModel = "localLLMModel"
    static let customInstructions = "customInstructions"
    static let insertionMode = "insertionMode"
    static let hotkey = "hotkey"
    static let hotkeyEnabled = "hotkeyEnabled"
    static let triggerKey = "triggerKey"
    static let playSounds = "playSounds"
    static let restoreClipboard = "restoreClipboard"
    static let overlayPosition = "overlayPosition"
    static let overlayOffset = "overlayOffset"
    static let overlayAlwaysVisible = "overlayAlwaysVisible"
    static let showInDock = "showInDock"
    static let spokenPunctuation = "spokenPunctuation"
    static let autoLists = "autoLists"
    static func style(_ c: AppCategory) -> String { "style.\(c.rawValue)" }

    static func registerDefaults() {
        var defaults: [String: Any] = [
            whisperModel: "openai_whisper-large-v3-v20240930_turbo_632MB",
            language: "auto",
            cleanupProvider: (AppleCleaner.isAvailable ? CleanupProvider.apple : .basic).rawValue,
            anthropicModel: "claude-opus-5-5",
            localLLMURL: "http://localhost:11434/v1/chat/completions",
            localLLMModel: "llama3.2",
            customInstructions: "",
            insertionMode: InsertionMode.paste.rawValue,
            hotkey: HotkeyPreset.optionSpace.rawValue,
            hotkeyEnabled: true,
            triggerKey: TriggerKey.fn.rawValue,
            playSounds: true,
            restoreClipboard: true,
            overlayPosition: OverlayPosition.bottom.rawValue,
            overlayOffset: 0.5,
            overlayAlwaysVisible: true,
            showInDock: false,
            spokenPunctuation: true,
            autoLists: true,
        ]
        for c in AppCategory.allCases { defaults[style(c)] = c.defaultStyle.rawValue }
        UserDefaults.standard.register(defaults: defaults)
    }
}

extension UserDefaults {
    var cleanupProvider: CleanupProvider { CleanupProvider(rawValue: string(forKey: SettingsKey.cleanupProvider) ?? "") ?? .basic }
    var insertionMode: InsertionMode { InsertionMode(rawValue: string(forKey: SettingsKey.insertionMode) ?? "") ?? .paste }
    var triggerKey: TriggerKey { TriggerKey(rawValue: string(forKey: SettingsKey.triggerKey) ?? "") ?? .fn }
    var overlayPosition: OverlayPosition { OverlayPosition(rawValue: string(forKey: SettingsKey.overlayPosition) ?? "") ?? .bottom }
    func style(for c: AppCategory) -> WritingStyle { WritingStyle(rawValue: string(forKey: SettingsKey.style(c)) ?? "") ?? c.defaultStyle }
}
