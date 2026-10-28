import Foundation
import WhisperKit

/// Local, on-device speech recognition via WhisperKit (Core ML Whisper).
actor Transcriber {
    enum State: Equatable { case unloaded, downloading, loading, ready, failed(String) }

    private var whisper: WhisperKit?
    private(set) var loadedModel: String?
    private(set) var state: State = .unloaded

    var onStateChange: (@Sendable (State) -> Void)?
    var onDownloadProgress: (@Sendable (Double) -> Void)?

    var hasModel: Bool { whisper != nil }

    func setProgressHandler(_ handler: @escaping @Sendable (Double) -> Void) { onDownloadProgress = handler }

    func setStateHandler(_ handler: @escaping @Sendable (State) -> Void) { onStateChange = handler }

    private func update(_ s: State) {
        state = s
        onStateChange?(s)
    }

    /// Downloads (first run only) and loads the requested model.
    func load(model: String) async throws {
        if loadedModel == model, whisper != nil { return }
        // Keep the current model usable until the new one is ready.
        do {
            update(.downloading)
            let progress = onDownloadProgress
            let folder = try await WhisperKit.download(variant: model, downloadBase: AppPaths.modelsDirectory) { p in
                progress?(p.fractionCompleted)
            }
            update(.loading)
            let config = WhisperKitConfig(
                model: model,
                downloadBase: AppPaths.modelsDirectory,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false)
            let fresh = try await WhisperKit(config)
            whisper = fresh
            loadedModel = model
            update(.ready)
        } catch {
            update(whisper != nil ? .ready : .failed(error.localizedDescription))
            throw error
        }
    }

    func transcribe(_ samples: [Float], language: String?, vocabulary: [String] = []) async throws -> String {
        guard let whisper else { throw NSError(domain: "Quill", code: 1, userInfo: [NSLocalizedDescriptionKey: "Whisper model is not loaded yet."]) }
        let lang = (language == nil || language == "auto") ? nil : language
        var options = DecodingOptions(
            task: .transcribe,
            language: lang,
            temperature: 0,
            usePrefillPrompt: lang != nil,
            detectLanguage: lang == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad)
        // Bias recognition toward the user's dictionary words.
        if !vocabulary.isEmpty, let tokenizer = whisper.tokenizer {
            let text = " " + vocabulary.prefix(60).joined(separator: ", ") + "."
            options.promptTokens = tokenizer.encode(text: text).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }
        var text = Self.stripArtifacts(try await whisper.transcribe(audioArray: samples, decodeOptions: options).map(\.text).joined(separator: " "))
        // Whisper occasionally returns nothing for clear speech (seen right after a model is
        // first compiled). If the audio clearly contains sound, retry once without VAD chunking.
        if text.isEmpty, Self.rms(samples) > 0.01 {
            options.chunkingStrategy = nil
            text = Self.stripArtifacts(try await whisper.transcribe(audioArray: samples, decodeOptions: options).map(\.text).joined(separator: " "))
        }
        return text
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Removes Whisper's common non-speech hallucinations.
    static func stripArtifacts(_ text: String) -> String {
        var t = text
        for junk in ["[BLANK_AUDIO]", "[MUSIC]", "(music)", "[Music]", "[NO SPEECH]", "(silence)"] {
            t = t.replacingOccurrences(of: junk, with: "")
        }
        t = t.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Whisper sometimes wraps the whole utterance in quotes.
        if t.count > 2, t.first == "\"", t.last == "\"", !t.dropFirst().dropLast().contains("\"") {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }
}
