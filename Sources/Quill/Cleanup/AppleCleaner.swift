import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device cleanup with Apple Intelligence's system language model (macOS 26+).
enum AppleCleaner {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(let reason): return "Apple Intelligence unavailable (\(reason))."
            }
        }
        #endif
        return "Requires macOS 26 with Apple Intelligence."
    }

    static func respond(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0))
            return response.content
        }
        #endif
        throw CleanupError.badResponse
    }
}
