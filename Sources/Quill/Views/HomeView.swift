import SwiftUI

struct HomeView: View {
    var goTo: (MainView.Page) -> Void
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsKey.triggerKey) private var trigger = TriggerKey.fn.rawValue
    @State private var stats = Database.Stats()
    @State private var recent: [Transcript] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                Text(headline)
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    Figure(value: stats.words.formatted(), label: "words")
                    Figure(value: "\(stats.wordsPerMinute)", label: "wpm")
                    Figure(value: "\(stats.streakDays)", label: stats.streakDays == 1 ? "day running" : "days running")
                    Figure(value: "\(stats.dictations)", label: "takes")
                }
            }

            SetupBanners()

            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("How it works")
                let key = TriggerKey(rawValue: trigger) ?? .fn
                VStack(alignment: .leading, spacing: 0) {
                    if key != .none {
                        HowRow(keys: [key.short], text: "Hold, talk, let go. The text lands wherever your cursor is.")
                        HowRow(keys: [key.short, key.short], text: "Tap twice to keep listening. Tap once more when you're done.")
                    }
                    HowRow(keys: ["esc"], text: "Throw away the current take.")
                    HowRow(keys: ["“scratch that”"], text: "Drops the last sentence. “No wait…” keeps only the correction.", last: true)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Recent")
                    Spacer()
                    if !recent.isEmpty {
                        Button("All history →") { goTo(.history) }
                            .buttonStyle(.plain).font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                }
                if recent.isEmpty {
                    Text("Nothing yet. Put your cursor in any text box and hold \(TriggerKey(rawValue: trigger)?.short ?? "fn").")
                        .font(Theme.body(13)).foregroundStyle(Theme.muted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recent) { item in TranscriptRow(item: item) }
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: state.historyVersion) { reload() }
    }

    private var headline: String {
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        guard stats.words > 0 else {
            return name.isEmpty ? "Say it. Quill writes it down." : "Say it, \(name). Quill writes it down."
        }
        let m = stats.minutesSaved
        let saved = m >= 90 ? String(format: "%.1f hours", m / 60) : "\(max(1, Int(m.rounded()))) minutes"
        return "\(stats.words.formatted()) words spoken, about \(saved) you didn't spend typing."
    }

    private func reload() {
        stats = state.database?.stats() ?? Database.Stats()
        recent = state.database?.fetch(limit: 4) ?? []
    }
}

private struct Figure: View {
    let value: String
    let label: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(Theme.mono(13, weight: .semibold)).foregroundStyle(Theme.accent).monospacedDigit()
            Text(label).font(Theme.mono(11)).foregroundStyle(Theme.muted)
        }
    }
}

private struct HowRow: View {
    let keys: [String]
    let text: String
    var last = false
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) { ForEach(keys.indices, id: \.self) { KeyCap(label: keys[$0]) } }
                .frame(width: 140, alignment: .leading)
            Text(text).font(Theme.body(13)).foregroundStyle(Theme.text.opacity(0.85))
            Spacer()
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .overlay(alignment: .bottom) { if last { Rectangle().fill(Theme.line).frame(height: 1) } }
    }
}
