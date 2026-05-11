import AppKit

/// Manages notification sound playback using macOS system sounds.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let defaultsKey = "notification.sound.name"
    static let defaultSoundName = "Bottle"
    private static var activeSound: NSSound?

    /// Returns the list of available system sound names (without file extension).
    static func availableSounds() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: soundsDirectory) else {
            return []
        }
        return contents
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }

    /// The currently selected sound name, persisted in UserDefaults.
    static var selectedSoundName: String {
        get {
            UserDefaults.standard.string(forKey: defaultsKey) ?? defaultSoundName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    /// Plays a system sound by name.
    static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            NotificationDebugLog.write("sound missing name=\(name)")
            return
        }
        activeSound = sound
        sound.stop()
        NotificationDebugLog.write("sound play name=\(name)")
        sound.play()
    }

    /// Plays the user-selected notification sound, respecting the mute setting.
    static func playNotification(isMuted: Bool) {
        guard !isMuted else {
            NotificationDebugLog.write("sound skipped muted=true")
            return
        }
        play(selectedSoundName)
    }
}
