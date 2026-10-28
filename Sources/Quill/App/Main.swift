import Foundation
import SwiftUI
import AppKit
import WhisperKit

/// Entry point. `Quill --selftest [audio-file]` exercises storage, cleanup and
/// transcription headlessly; otherwise the SwiftUI app launches.
@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), args.count > i + 1 {
            MainActor.assumeIsolated {
                do { try IconRenderer.render(to: URL(fileURLWithPath: args[i + 1])); exit(0) }
                catch { print(error); exit(1) }
            }
        }
        if let i = args.firstIndex(of: "--render-preview"), args.count > i + 1 {
            // Renders the main window offscreen for design review (controls may draw as placeholders).
            MainActor.assumeIsolated {
                SettingsKey.registerDefaults()
                let pages: [(String, AnyView)] = [
                    ("home", AnyView(HomeView(goTo: { _ in }))), ("history", AnyView(HistoryView())),
                    ("style", AnyView(StyleView())), ("dictionary", AnyView(DictionaryView())),
                ]
                for (name, page) in pages {
                    let view = page.environmentObject(AppState.shared)
                        .padding(40).frame(width: 790, alignment: .topLeading).background(Theme.bg)
                        .preferredColorScheme(.dark)
                    let r = ImageRenderer(content: view)
                    r.scale = 2
                    if let cg = r.cgImage {
                        let url = URL(fileURLWithPath: args[i + 1]).appendingPathComponent("\(name).png")
                        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
                    }
                }
                exit(0)
            }
        }
        if let i = args.firstIndex(of: "--format"), args.count > i + 1 {
            // Quill --format "<transcript>" [category]: run the configured cleanup and print it.
            let category = args.count > i + 2 ? AppCategory(rawValue: args[i + 2]) ?? .other : .other
            Task {
                SettingsKey.registerDefaults()
                let ctx = AppContext(appName: nil, bundleID: nil, windowTitle: nil, category: category)
                let (out, used) = await TextCleaner.fromDefaults(context: ctx, database: nil).clean(args[i + 1])
                print("[\(used)] \(out)")
                exit(0)
            }
            dispatchMain()
        }
        if let i = args.firstIndex(of: "--selftest") {
            let audio = args.count > i + 1 ? args[i + 1] : nil
            Task {
                let ok = await SelfTest.run(audioPath: audio)
                exit(ok ? 0 : 1)
            }
            dispatchMain()
        }
        QuillApp.main()
    }
}

enum SelfTest {
    static func run(audioPath: String?) async -> Bool {
        var ok = true
        func check(_ name: String, _ cond: Bool, _ detail: String = "") {
            print("\(cond ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
            if !cond { ok = false }
        }

        // SQLite
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dictate-selftest-\(UUID().uuidString).sqlite")
        do {
            let db = try Database(url: tmp)
            let id = try db.insert(rawText: "hello raw", cleanedText: "Hello cleaned.", duration: 1.5, appName: "Notes", model: "m", cleanupProvider: "basic")
            check("sqlite insert", id > 0)
            check("sqlite fetch", db.fetch().first?.cleanedText == "Hello cleaned.")
            check("sqlite search", db.fetch(search: "raw").count == 1 && db.fetch(search: "zzz").isEmpty)
            db.delete(id: id)
            check("sqlite delete", db.fetch().isEmpty)
        } catch { check("sqlite", false, error.localizedDescription) }
        try? FileManager.default.removeItem(at: tmp)

        // Rule-based formatter
        func expect(_ name: String, _ input: String, _ want: String, style: WritingStyle = .formal) {
            let got = TextCleaner.basicClean(input, style: style)
            check(name, got == want, got.debugDescription)
        }
        expect("fillers + new line", "um so i think the the meeting is uh at four new line thanks", "So I think the meeting is at four\nThanks.")
        expect("self-correction", "let's meet at 3 no wait at 4 on friday", "Let's meet at 4 on friday.")
        expect("scratch that", "send it to john. actually scratch that. send it to mary", "Send it to mary.")
        expect("numbered list", "my plan is first finish the page second record the demo third email the list", "My plan is:\n1. Finish the page\n2. Record the demo\n3. Email the list")
        expect("spoken punctuation", "is it ready question mark yes comma ship it exclamation point", "Is it ready? Yes, ship it!")
        expect("casual style", "are you free for lunch tomorrow", "Are you free for lunch tomorrow", style: .casual)
        expect("very casual style", "are you free tomorrow. I think so", "are you free tomorrow. I think so", style: .veryCasual)
        let dict = [DictionaryEntry(id: 1, term: "Kubernetes", soundsLike: "cooper netties")]
        check("dictionary", TextCleaner.applyDictionary("deploy to cooper netties now", dict) == "deploy to Kubernetes now")
        let snip = [Snippet(id: 1, trigger: "my email", expansion: "me@example.com")]
        check("snippet", TextCleaner.applySnippets("My email.", snip) == "me@example.com")
        print("      apple intelligence available: \(AppleCleaner.isAvailable)")

        // Whisper
        if let audioPath {
            do {
                let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)
                let model = ProcessInfo.processInfo.environment["DICTATE_MODEL"] ?? "openai_whisper-tiny"
                let t = Transcriber()
                let start = Date()
                try await t.load(model: model)
                print("      model \(model) loaded in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
                let s2 = Date()
                let text = try await t.transcribe(samples, language: "en")
                print("      transcribed in \(String(format: "%.2f", Date().timeIntervalSince(s2)))s: \(text.debugDescription)")
                check("whisper transcription", !text.isEmpty)
                let provider: CleanupProvider = AppleCleaner.isAvailable ? .apple : .basic
                let (polished, used) = await TextCleaner(provider: provider).clean(text)
                print("      cleaned [\(used)]: \(polished.debugDescription)")
            } catch { check("whisper transcription", false, error.localizedDescription) }
        }
        return ok
    }
}
