import SwiftUI

/// Quill's look: warm near-black, cream type, one amber "phosphor" accent.
/// Minimal, with a faint retro edge from monospaced labels and keycaps.
enum Theme {
    static let bg = Color(hex: 0x0E0D0B)
    static let sidebar = Color(hex: 0x0B0A09)
    static let surface = Color(hex: 0x161412)
    static let surfaceHi = Color(hex: 0x1E1B18)
    static let line = Color(hex: 0x2A2622)
    static let text = Color(hex: 0xEDE6D6)
    static let muted = Color(hex: 0x8D8579)
    static let faint = Color(hex: 0x5C564E)
    static let accent = Color(hex: 0xE8A33D)
    static let accentSoft = Color(hex: 0xE8A33D).opacity(0.14)
    static let rec = Color(hex: 0xE2563F)
    static let ok = Color(hex: 0x8FB573)

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Small uppercase monospaced label, e.g. "— RECENT".
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted
    init(_ text: String, color: Color = Theme.muted) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(Theme.mono(10, weight: .semibold)).tracking(1.6).foregroundStyle(color)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
    }
}

/// Faint CRT scanlines — the only overtly retro texture, used sparingly.
struct Scanlines: View {
    var opacity: Double = 0.035
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(opacity)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(Theme.mono(11, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.surfaceHi, Theme.surface], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.line))
            .shadow(color: .black.opacity(0.6), radius: 0, y: 2)
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(eyebrow)
            Text(title).font(Theme.display(32)).foregroundStyle(Theme.text)
            if let subtitle { Text(subtitle).font(Theme.body(13)).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuillButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(prominent ? Theme.bg : Theme.text)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(prominent ? Theme.accent : Theme.surfaceHi))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(prominent ? .clear : Theme.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct QuillTextField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.faint))
            .textFieldStyle(.plain)
            .font(Theme.body(13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
    }
}

/// A quiet inline notice: hairline rule, small marker, plain copy.
struct Banner: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = Theme.accent
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().fill(tint).frame(width: 6, height: 6).offset(y: -1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.body(13, weight: .medium)).foregroundStyle(Theme.text)
                Text(message).font(Theme.body(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.plain)
                    .font(Theme.mono(11, weight: .semibold)).foregroundStyle(tint)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// Alerts for missing setup, shown on Home and Settings.
struct SetupBanners: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.triggerKey) private var trigger = TriggerKey.fn.rawValue

    var body: some View {
        VStack(spacing: 0) {
            if !state.microphoneAuthorized {
                Banner(symbol: "mic.slash", title: "Microphone access needed",
                       message: "Quill records only while you dictate, and transcribes on this Mac.",
                       tint: Theme.rec, actionTitle: "Allow →") {
                    Task { state.microphoneAuthorized = await AudioRecorder.requestPermission() }
                    openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                }
            }
            if !state.accessibilityTrusted {
                Banner(symbol: "hand.raised", title: "Accessibility access needed to auto-paste",
                       message: "Lets Quill hear the fn key and paste into other apps. If Quill is already listed, remove it with − and add it again.",
                       tint: Theme.rec, actionTitle: "Allow →") {
                    TextInserter.promptForAccessibility()
                    openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
            }
            if trigger == TriggerKey.fn.rawValue && state.fnConflict {
                Banner(symbol: "globe", title: "Set the 🌐 fn key to “Do Nothing”",
                       message: "Keyboard settings → “Press 🌐 key to” → Do Nothing, and don't use “Press 🌐 twice” for Apple Dictation.",
                       actionTitle: "Open settings →") { FnKeySystemSetting.openKeyboardSettings() }
            }
            switch state.modelState {
            case .downloading:
                Banner(symbol: "arrow.down.circle", title: "Downloading speech model · \(Int(state.downloadProgress * 100))%",
                       message: "One-time download for better accuracy. Quill keeps working with the current model meanwhile.")
            case .loading:
                Banner(symbol: "cpu", title: "Preparing speech model…",
                       message: "Optimizing Whisper for the Neural Engine. The first time can take a minute.")
            case .failed(let m):
                Banner(symbol: "exclamationmark.triangle", title: "Speech model failed to load", message: m, tint: Theme.rec)
            default: EmptyView()
            }
        }
    }

    private func openURL(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
}
