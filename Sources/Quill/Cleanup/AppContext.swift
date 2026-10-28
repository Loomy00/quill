import AppKit
import ApplicationServices

/// Kind of app being dictated into; each has its own writing style.
enum AppCategory: String, CaseIterable, Identifiable {
    case messages, work, email, code, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .messages: return "Personal messages"
        case .work: return "Work messages"
        case .email: return "Email"
        case .code: return "Coding"
        case .other: return "Everything else"
        }
    }
    var examples: String {
        switch self {
        case .messages: return "Messages, WhatsApp, Telegram, Signal, Discord"
        case .work: return "Slack, Teams, Linear, Notion comments"
        case .email: return "Mail, Outlook, Gmail, Superhuman"
        case .code: return "Xcode, VS Code, Cursor, Terminal, Claude Code"
        case .other: return "Notes, Docs, browsers and all other apps"
        }
    }
    var symbol: String {
        switch self {
        case .messages: return "message"
        case .work: return "bubble.left.and.bubble.right"
        case .email: return "envelope"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc.text"
        }
    }
    var defaultStyle: WritingStyle {
        switch self {
        case .messages: return .casual
        case .work: return .casual
        case .email, .other: return .formal
        case .code: return .formal
        }
    }
}

enum WritingStyle: String, CaseIterable, Identifiable {
    case formal, casual, veryCasual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .veryCasual: return "Very casual"
        }
    }
    var example: String {
        switch self {
        case .formal: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
        case .casual: return "Hey are you free for lunch tomorrow? Let's do 12 if that works for you"
        case .veryCasual: return "hey are you free for lunch tomorrow? let's do 12 if that works for you"
        }
    }
    var instruction: String {
        switch self {
        case .formal: return "Use full capitalization and punctuation."
        case .casual: return "Keep capitalization but use lighter punctuation; omit the final period."
        case .veryCasual: return "Use all lowercase sentence starts and minimal punctuation; omit the final period."
        }
    }
}

/// Snapshot of where the user is dictating, captured when recording starts.
struct AppContext {
    let appName: String?
    let bundleID: String?
    let windowTitle: String?
    let category: AppCategory

    static func capture(_ app: NSRunningApplication?) -> AppContext {
        let bundle = app?.bundleIdentifier
        let title = app.flatMap { focusedWindowTitle(pid: $0.processIdentifier) }
        return AppContext(appName: app?.localizedName, bundleID: bundle, windowTitle: title,
                          category: categorize(bundle: bundle, title: title))
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let win, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }

    static func categorize(bundle: String?, title: String?) -> AppCategory {
        let b = (bundle ?? "").lowercased()
        let t = (title ?? "").lowercased()
        let messages = ["com.apple.mobilesms", "net.whatsapp", "ru.keepcoder.telegram", "org.whispersystems.signal", "com.hnc.discord", "com.facebook.archon"]
        let work = ["com.tinyspeck.slackmacgap", "com.microsoft.teams", "com.linear", "notion.id", "com.figma"]
        let email = ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail", "com.superhuman", "com.google.gmail", "com.mimestream"]
        let code = ["com.apple.dt.xcode", "com.microsoft.vscode", "com.todesktop.230313mzl4w4u92", "com.apple.terminal", "com.googlecode.iterm2",
                    "dev.warp", "com.jetbrains", "dev.zed", "com.sublimetext", "com.exafunction.windsurf", "com.mitchellh.ghostty", "com.anthropic.claude"]
        if messages.contains(where: b.hasPrefix) { return .messages }
        if work.contains(where: b.hasPrefix) { return .work }
        if email.contains(where: b.hasPrefix) { return .email }
        if code.contains(where: b.hasPrefix) { return .code }
        // Browsers: infer from the tab/window title.
        if t.contains("gmail") || t.contains("outlook") || t.contains("inbox") { return .email }
        if t.contains("slack") || t.contains("teams") || t.contains("linear") { return .work }
        if t.contains("whatsapp") || t.contains("messenger") || t.contains("discord") || t.contains("telegram") { return .messages }
        if t.contains("github") || t.contains("gitlab") || t.contains("colab") { return .code }
        return .other
    }
}
