import SwiftUI

struct StyleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeader(eyebrow: "Style", title: "How you sound, per app",
                       subtitle: "Quill notices where you're typing and adjusts punctuation and tone.")
            VStack(spacing: 0) {
                ForEach(AppCategory.allCases) { c in StyleRow(category: c) }
            }
        }
    }
}

private struct StyleRow: View {
    let category: AppCategory
    @AppStorage private var selection: String

    init(category: AppCategory) {
        self.category = category
        _selection = AppStorage(wrappedValue: category.defaultStyle.rawValue, SettingsKey.style(category))
    }

    private var style: WritingStyle { WritingStyle(rawValue: selection) ?? category.defaultStyle }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.label).font(Theme.body(14, weight: .medium)).foregroundStyle(Theme.text)
                    Text(category.examples).font(Theme.mono(10.5)).foregroundStyle(Theme.faint)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(WritingStyle.allCases) { s in
                        let on = s.rawValue == selection
                        Button(s.label) { selection = s.rawValue }
                            .buttonStyle(.plain)
                            .font(Theme.mono(10.5, weight: .semibold))
                            .foregroundStyle(on ? Theme.bg : Theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? Theme.accent : .clear))
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line))
            }
            Text(style.example)
                .font(Theme.display(15))
                .italic()
                .foregroundStyle(Theme.text.opacity(0.7))
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.accent.opacity(0.5)).frame(width: 2) }
                .animation(.easeOut(duration: 0.15), value: selection)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
