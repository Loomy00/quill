import SwiftUI

struct MainView: View {
    enum Page: String, Hashable, CaseIterable {
        case home, history, dictionary, snippets, style, settings
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .home: return "square.grid.2x2"
            case .history: return "clock"
            case .dictionary: return "character.book.closed"
            case .snippets: return "text.quote"
            case .style: return "textformat"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @EnvironmentObject var state: AppState
    @State private var page: Page

    init(initialPage: Page = .home) { _page = State(initialValue: initialPage) }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(page: $page)
            Rectangle().fill(Theme.line).frame(width: 1)
            ScrollView {
                Group {
                    switch page {
                    case .home: HomeView(goTo: { page = $0 })
                    case .history: HistoryView()
                    case .dictionary: DictionaryView()
                    case .snippets: SnippetsView()
                    case .style: StyleView()
                    case .settings: SettingsView()
                    }
                }
                .padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 40)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}

private struct Sidebar: View {
    @Binding var page: MainView.Page
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.triggerKey) private var trigger = TriggerKey.fn.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                QuillMark().frame(width: 24, height: 24)
                Text("Quill").font(Theme.display(22)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 20).padding(.top, 48).padding(.bottom, 28)

            VStack(spacing: 2) {
                ForEach(MainView.Page.allCases, id: \.self) { p in
                    NavItem(page: p, selected: page == p) { page = p }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(Theme.line).frame(height: 1)
                HStack(spacing: 7) {
                    Circle().fill(dotColor).frame(width: 6, height: 6)
                        .shadow(color: dotColor.opacity(0.8), radius: 4)
                    Text(statusText.uppercased()).font(Theme.mono(9.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                if let key = TriggerKey(rawValue: trigger), key != .none {
                    HStack(spacing: 6) {
                        Text("HOLD").font(Theme.mono(9.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.faint)
                        KeyCap(label: key.short)
                        Text("TO WRITE").font(Theme.mono(9.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.faint)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 210)
        .background(Theme.sidebar)
    }

    private var statusText: String {
        switch state.phase {
        case .recording: return "Listening"
        case .transcribing, .cleaning: return "Writing"
        case .error: return "Last take failed"
        case .notice: return "Copied to clipboard"
        case .idle:
            switch state.modelState {
            case .ready: return "Ready"
            case .downloading: return "Model \(Int(state.downloadProgress * 100))%"
            case .loading: return "Warming up"
            case .unloaded: return "Starting"
            case .failed: return "Model error"
            }
        }
    }

    private var dotColor: Color {
        if state.phase == .recording { return Theme.rec }
        if case .ready = state.modelState { return Theme.ok }
        if case .failed = state.modelState { return Theme.rec }
        return Theme.accent
    }
}

private struct NavItem: View {
    let page: MainView.Page
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: page.symbol).font(.system(size: 12.5, weight: .medium)).frame(width: 16)
                Text(page.title).font(Theme.body(13, weight: selected ? .medium : .regular))
                Spacer()
            }
            .foregroundStyle(selected ? Theme.text : (hovering ? Theme.text.opacity(0.85) : Theme.muted))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.surfaceHi : (hovering ? Theme.surface : .clear)))
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Theme.accent).frame(width: 2.5, height: 14)
                        .shadow(color: Theme.accent.opacity(0.8), radius: 4)
                        .offset(x: -4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Small logo used in the sidebar.
struct QuillMark: View {
    var body: some View { QuillLogo() }
}
