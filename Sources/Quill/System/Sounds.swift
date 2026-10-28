import AppKit

enum Sounds {
    static func play(_ name: String) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.playSounds) else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
    static func start() { play("Tink") }
    static func stop() { play("Pop") }
    static func error() { play("Basso") }
}
