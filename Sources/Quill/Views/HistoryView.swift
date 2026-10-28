import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var search = ""
    @State private var items: [Transcript] = []
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .lastTextBaseline) {
                PageHeader(eyebrow: "History", title: "Everything you've said", subtitle: "Kept on this Mac only.")
                if !items.isEmpty || !search.isEmpty {
                    Button("Clear all") { confirmClear = true }
                        .buttonStyle(.plain).font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.faint)
                TextField("", text: $search, prompt: Text("Search").foregroundColor(Theme.faint))
                    .textFieldStyle(.plain).font(Theme.body(13)).foregroundStyle(Theme.text)
            }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }

            if items.isEmpty {
                Text(search.isEmpty ? "Nothing here yet." : "Nothing matches “\(search)”.").font(Theme.body(13)).foregroundStyle(Theme.muted)
            }
            ForEach(groups, id: \.0) { title, rows in
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(title)
                    VStack(spacing: 0) {
                        ForEach(rows) { item in
                            TranscriptRow(item: item, onDelete: { state.database?.delete(id: item.id); reload() })
                        }
                    }
                }
            }
        }
        .confirmationDialog("Delete all history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { state.database?.deleteAll(); reload() }
        }
        .onAppear(perform: reload)
        .onChange(of: search) { reload() }
        .onChange(of: state.historyVersion) { reload() }
    }

    private func reload() { items = state.database?.fetch(search: search) ?? [] }

    private var groups: [(String, [Transcript])] {
        let cal = Calendar.current
        var out: [(String, [Transcript])] = []
        for item in items {
            let title: String
            if cal.isDateInToday(item.createdAt) { title = "Today" }
            else if cal.isDateInYesterday(item.createdAt) { title = "Yesterday" }
            else { title = item.createdAt.formatted(.dateTime.weekday(.wide).month().day()) }
            if out.last?.0 == title { out[out.count - 1].1.append(item) } else { out.append((title, [item])) }
        }
        return out
    }
}

struct TranscriptRow: View {
    let item: Transcript
    var onDelete: (() -> Void)? = nil
    @State private var showRaw = false
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(Theme.mono(11, weight: .medium)).foregroundStyle(Theme.muted)
                if let app = item.appName {
                    Text(app).font(Theme.mono(10)).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            .frame(width: 74, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(showRaw ? item.rawText : item.finalText)
                    .font(Theme.body(13.5))
                    .lineSpacing(3)
                    .foregroundStyle(showRaw ? Theme.muted : Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hovering || showRaw {
                    HStack(spacing: 14) {
                        if item.rawText != item.finalText {
                            Button(showRaw ? "Show cleaned" : "Show what I said") { showRaw.toggle() }
                        }
                        Button(copied ? "Copied" : "Copy") {
                            TextInserter.setClipboard(item.finalText)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                        }
                        if let onDelete { Button("Delete", action: onDelete) }
                        Spacer()
                        Text(String(format: "%.1fs", item.durationSeconds)).foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(10.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
