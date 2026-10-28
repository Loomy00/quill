import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject var state: AppState
    @State private var entries: [DictionaryEntry] = []
    @State private var term = ""
    @State private var soundsLike = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeader(eyebrow: "Dictionary", title: "Words Quill should know",
                       subtitle: "Names, slang and jargon. They also nudge the speech model toward the right spelling.")
            HStack(spacing: 10) {
                QuillTextField(placeholder: "Word or name", text: $term)
                QuillTextField(placeholder: "Misheard as… (optional, comma-separated)", text: $soundsLike)
                Button("Add", action: add).buttonStyle(QuillButtonStyle(prominent: true))
                    .keyboardShortcut(.return)
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            VStack(spacing: 0) {
                if entries.isEmpty {
                    Text("Empty for now. Try adding your own name.").font(Theme.body(13)).foregroundStyle(Theme.muted)
                }
                ForEach(entries) { e in
                    HStack(alignment: .firstTextBaseline) {
                        Text(e.term).font(Theme.body(14, weight: .medium)).foregroundStyle(Theme.text)
                        if !e.soundsLike.isEmpty {
                            Text("not “\(e.soundsLike)”").font(Theme.mono(11)).foregroundStyle(Theme.faint)
                        }
                        Spacer()
                        RemoveButton { state.database?.deleteDictionary(id: e.id); reload() }
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func add() {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        state.database?.addDictionary(term: t, soundsLike: soundsLike.trimmingCharacters(in: .whitespaces))
        term = ""; soundsLike = ""
        reload()
    }

    private func reload() { entries = state.database?.dictionary() ?? [] }
}

struct SnippetsView: View {
    @EnvironmentObject var state: AppState
    @State private var snippets: [Snippet] = []
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeader(eyebrow: "Snippets", title: "Say less, type more",
                       subtitle: "A short phrase that expands into something longer — an address, a link, a sign-off.")
            VStack(alignment: .leading, spacing: 10) {
                QuillTextField(placeholder: "When I say…  e.g. my calendar link", text: $trigger)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $expansion)
                        .font(Theme.body(13)).foregroundStyle(Theme.text)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 72)
                    if expansion.isEmpty {
                        Text("…write this instead").font(Theme.body(13)).foregroundStyle(Theme.faint).padding(11).allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.line))
                HStack {
                    Spacer()
                    Button("Add snippet", action: add).buttonStyle(QuillButtonStyle(prominent: true))
                        .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
                }
            }
            VStack(spacing: 0) {
                ForEach(snippets) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(s.trigger).font(Theme.mono(12, weight: .semibold)).foregroundStyle(Theme.accent)
                            .frame(width: 170, alignment: .leading)
                        Text(s.expansion).font(Theme.body(13)).foregroundStyle(Theme.text.opacity(0.85)).textSelection(.enabled)
                        Spacer()
                        RemoveButton { state.database?.deleteSnippet(id: s.id); reload() }
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func add() {
        state.database?.addSnippet(trigger: trigger.trimmingCharacters(in: .whitespaces), expansion: expansion)
        trigger = ""; expansion = ""
        reload()
    }

    private func reload() { snippets = state.database?.snippets() ?? [] }
}

struct RemoveButton: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? Theme.rec : Theme.faint)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Remove")
    }
}
