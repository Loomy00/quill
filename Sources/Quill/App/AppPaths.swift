import Foundation

enum AppPaths {
    /// Kept from the app's original name so existing permissions and keychain items still apply.
    static let bundleID = "com.local.dictate"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Quill", isDirectory: true)
        // One-time move of data (history, downloaded models) from the app's previous name.
        let legacy = base.appendingPathComponent("Dictate", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var modelsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
